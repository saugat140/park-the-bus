using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Npgsql;
using ParkTheBus.Api.Play;

namespace ParkTheBus.Api.Tests;

[Collection(PostgresCollection.Name)]
public sealed class AnswerReportTests(PostgresFixture postgres) : IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly List<ApiFactory> _factories = [];
    private readonly DateTimeOffset _day = new(2026, 11, 23, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Report_stores_open_wrong_and_missing_rows_for_reviewed_prompts()
    {
        var clock = new TestClock(_day);
        using var client = Client(clock);
        var session = Guid.NewGuid();
        var promptId = await PromptId("Name a forward from the sample");

        var wrong = await Report(client, promptId, session, "Secret Striker", ReportKinds.Wrong, "scored me wrong");
        Assert.Equal(HttpStatusCode.Created, wrong.Status);
        Assert.NotNull(wrong.Body);
        Assert.True(wrong.Body.Id > 0);
        Assert.Equal("open", wrong.Body.ReviewStatus);

        clock.Advance(TimeSpan.FromMinutes(1));
        var missing = await Report(client, promptId, session, "Another Forward", "MISSING", null);
        Assert.Equal(HttpStatusCode.Created, missing.Status);

        await using var dataSource = NpgsqlDataSource.Create(postgres.ConnectionString);
        await using var command = dataSource.CreateCommand(
            """
            SELECT report_kind, raw_input, notes, review_status
            FROM answer_reports
            WHERE prompt_id = $1 AND session_id = $2
            ORDER BY created_at, id
            """);
        command.Parameters.AddWithValue(promptId);
        command.Parameters.AddWithValue(session);

        await using var reader = await command.ExecuteReaderAsync();
        Assert.True(await reader.ReadAsync());
        Assert.Equal("wrong", reader.GetString(0));
        Assert.Equal("Secret Striker", reader.GetString(1));
        Assert.Equal("scored me wrong", reader.GetString(2));
        Assert.Equal("open", reader.GetString(3));

        Assert.True(await reader.ReadAsync());
        Assert.Equal("missing", reader.GetString(0));
        Assert.Equal("Another Forward", reader.GetString(1));
        Assert.True(reader.IsDBNull(2));
        Assert.Equal("open", reader.GetString(3));
        Assert.False(await reader.ReadAsync());
    }

    [Fact]
    public async Task Report_rejects_bad_input_and_unknown_or_draft_prompts()
    {
        var clock = new TestClock(_day);
        using var client = Client(clock);
        var session = Guid.NewGuid();
        var promptId = await PromptId("Name a forward from the sample");
        var draftId = await PromptId("This draft must stay off the response");

        Assert.Equal(HttpStatusCode.BadRequest,
            (await Report(client, promptId, Guid.Empty, "x", ReportKinds.Wrong)).Status);
        Assert.Equal(HttpStatusCode.BadRequest,
            (await Report(client, promptId, session, "   ", ReportKinds.Wrong)).Status);
        Assert.Equal(HttpStatusCode.BadRequest,
            (await Report(client, promptId, session, "x", "other")).Status);
        Assert.Equal(HttpStatusCode.NotFound,
            (await Report(client, draftId, session, "x", ReportKinds.Missing)).Status);
        Assert.Equal(HttpStatusCode.NotFound,
            (await Report(client, 9_999_999, session, "x", ReportKinds.Missing)).Status);
    }

    [Fact]
    public async Task Open_report_sql_lists_rows_for_review()
    {
        var clock = new TestClock(_day);
        using var client = Client(clock);
        var session = Guid.NewGuid();
        var promptId = await PromptId("Name a Ronaldo");

        Assert.Equal(HttpStatusCode.Created,
            (await Report(client, promptId, session, "Ronaldinho", ReportKinds.Missing, "should count")).Status);

        var sqlPath = FindReviewSql();
        var sql = await File.ReadAllTextAsync(sqlPath);
        await using var dataSource = NpgsqlDataSource.Create(postgres.ConnectionString);
        await using var command = dataSource.CreateCommand(sql);
        await using var reader = await command.ExecuteReaderAsync();

        var found = false;
        while (await reader.ReadAsync())
        {
            if (reader.GetGuid(reader.GetOrdinal("session_id")) != session)
                continue;

            found = true;
            Assert.Equal("missing", reader.GetString(reader.GetOrdinal("report_kind")));
            Assert.Equal("Ronaldinho", reader.GetString(reader.GetOrdinal("raw_input")));
            Assert.Equal("should count", reader.GetString(reader.GetOrdinal("notes")));
            Assert.Equal("Name a Ronaldo", reader.GetString(reader.GetOrdinal("prompt_text")));
            Assert.Equal(new DateOnly(2026, 11, 23), DateOnly.FromDateTime(reader.GetDateTime(reader.GetOrdinal("puzzle_date"))));
        }

        Assert.True(found);
    }

    private HttpClient Client(TestClock clock)
    {
        var factory = new ApiFactory(postgres.ConnectionString, clock);
        _factories.Add(factory);
        return factory.CreateClient();
    }

    public void Dispose()
    {
        foreach (var factory in _factories)
            factory.Dispose();
    }

    private async Task<long> PromptId(string text)
    {
        await using var dataSource = NpgsqlDataSource.Create(postgres.ConnectionString);
        await using var command = dataSource.CreateCommand(
            "SELECT id FROM prompts WHERE prompt_text = $1");
        command.Parameters.AddWithValue(text);
        return (long)(await command.ExecuteScalarAsync())!;
    }

    private static string FindReviewSql()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            var candidate = Path.Combine(dir.FullName, "tools", "review", "list-open-answer-reports.sql");
            if (File.Exists(candidate))
                return candidate;
            dir = dir.Parent;
        }

        throw new InvalidOperationException("tools/review/list-open-answer-reports.sql was not found.");
    }

    private static async Task<(HttpStatusCode Status, ReportAnswerResponse? Body)> Report(
        HttpClient client,
        long promptId,
        Guid sessionId,
        string text,
        string kind,
        string? notes = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, $"/puzzles/today/prompts/{promptId}/report")
        {
            Content = JsonContent.Create(new ReportAnswerRequest(sessionId, text, kind, notes))
        };
        request.Headers.Add("X-Session-Id", sessionId == Guid.Empty ? Guid.NewGuid().ToString() : sessionId.ToString());
        var response = await client.SendAsync(request);
        var raw = await response.Content.ReadAsStringAsync();
        var body = string.IsNullOrWhiteSpace(raw)
            ? null
            : JsonSerializer.Deserialize<ReportAnswerResponse>(raw, JsonOptions);
        return (response.StatusCode, body);
    }
}
