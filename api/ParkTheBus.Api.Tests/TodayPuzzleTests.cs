using System.Net;
using System.Text.Json;
using ParkTheBus.Api.Puzzles;

namespace ParkTheBus.Api.Tests;

[Collection(PostgresCollection.Name)]
public sealed class TodayPuzzleTests(PostgresFixture postgres) : IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly List<ApiFactory> _factories = [];

    [Fact]
    public async Task Today_returns_reviewed_prompts_in_position_order_and_caches_until_utc_midnight()
    {
        var now = new DateTimeOffset(2026, 11, 23, 13, 40, 0, TimeSpan.Zero);
        using var client = ClientAt(now);

        var response = await client.GetAsync("/puzzles/today");
        var raw = await response.Content.ReadAsStringAsync();
        var puzzle = ReadPuzzle(raw);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);
        Assert.True(response.Headers.CacheControl?.Public);
        Assert.Equal(TimeSpan.FromSeconds(37_200), response.Headers.CacheControl?.MaxAge);
        Assert.Equal(
            new DateTimeOffset(2026, 11, 24, 0, 0, 0, TimeSpan.Zero),
            response.Content.Headers.Expires);

        Assert.NotNull(puzzle);
        Assert.Equal(new DateOnly(2026, 11, 23), puzzle.PuzzleDate);
        Assert.Equal(3, puzzle.Prompts.Count);
        Assert.Equal((short)1, puzzle.Prompts[0].Position);
        Assert.Equal(await PromptId("Name a forward from the sample"), puzzle.Prompts[0].PromptId);
        Assert.Equal("Name a forward from the sample", puzzle.Prompts[0].Text);
        Assert.Equal((short)2, puzzle.Prompts[1].Position);
        Assert.Equal(await PromptId("Name a club from the sample"), puzzle.Prompts[1].PromptId);
        Assert.Equal("Name a club from the sample", puzzle.Prompts[1].Text);
        Assert.Equal((short)4, puzzle.Prompts[2].Position);
        Assert.Equal("Name a Ronaldo", puzzle.Prompts[2].Text);

        AssertAbsent(raw);
    }

    [Fact]
    public async Task The_next_utc_date_returns_that_dates_prompt()
    {
        var now = new DateTimeOffset(2026, 11, 24, 0, 0, 1, TimeSpan.Zero);
        using var client = ClientAt(now);

        var response = await client.GetAsync("/puzzles/today");
        var raw = await response.Content.ReadAsStringAsync();
        var puzzle = ReadPuzzle(raw);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.Public);
        Assert.Equal(TimeSpan.FromSeconds(86_399), response.Headers.CacheControl?.MaxAge);
        Assert.NotNull(puzzle);
        Assert.Equal(new DateOnly(2026, 11, 24), puzzle.PuzzleDate);
        Assert.Single(puzzle.Prompts);
        Assert.Equal("Name a goalkeeper scheduled for the next date", puzzle.Prompts[0].Text);
        Assert.DoesNotContain("Name a forward from the sample", raw);
        AssertAbsent(raw);
    }

    [Fact]
    public async Task A_date_with_only_a_draft_returns_no_prompts_and_is_not_cached()
    {
        var now = new DateTimeOffset(2026, 11, 22, 8, 0, 0, TimeSpan.Zero);
        using var client = ClientAt(now);

        var response = await client.GetAsync("/puzzles/today");
        var raw = await response.Content.ReadAsStringAsync();
        var puzzle = ReadPuzzle(raw);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.NoStore);
        Assert.NotNull(puzzle);
        Assert.Equal(new DateOnly(2026, 11, 22), puzzle.PuzzleDate);
        Assert.Empty(puzzle.Prompts);
        Assert.DoesNotContain("Draft day prompt", raw);
        AssertAbsent(raw);
    }

    [Fact]
    public async Task A_missing_date_is_not_found_and_is_not_cached()
    {
        var now = new DateTimeOffset(2026, 11, 25, 12, 0, 0, TimeSpan.Zero);
        using var client = ClientAt(now);

        var response = await client.GetAsync("/puzzles/today");
        var raw = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.NoStore);
        Assert.Contains("\"status\":404", raw);
        Assert.DoesNotContain("puzzleDate", raw);
        AssertAbsent(raw);
    }

    private HttpClient ClientAt(DateTimeOffset utcNow)
    {
        var factory = new ApiFactory(postgres.ConnectionString, new TestClock(utcNow));
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
        await using var dataSource = Npgsql.NpgsqlDataSource.Create(postgres.ConnectionString);
        await using var command = dataSource.CreateCommand(
            "SELECT id FROM prompts WHERE prompt_text = $1");
        command.Parameters.AddWithValue(text);
        return (long)(await command.ExecuteScalarAsync())!;
    }

    private static TodayPuzzleResponse? ReadPuzzle(string raw)
    {
        if (string.IsNullOrEmpty(raw))
            return null;
        return JsonSerializer.Deserialize<TodayPuzzleResponse>(raw, JsonOptions);
    }

    private static void AssertAbsent(string raw)
    {
        Assert.DoesNotContain("Secret Striker", raw);
        Assert.DoesNotContain("must not leave the database", raw);
        Assert.DoesNotContain("Hidden Alias", raw);
        Assert.DoesNotContain("hidden research", raw);
        Assert.DoesNotContain("This draft must stay off the response", raw);
        Assert.DoesNotContain("Sunday League", raw);
        Assert.DoesNotContain("sourceNotes", raw, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("canonicalName", raw);
        Assert.DoesNotContain("\"answers\"", raw);
        Assert.DoesNotContain("\"aliases\"", raw);
        Assert.DoesNotContain("\"fame\"", raw);
    }
}
