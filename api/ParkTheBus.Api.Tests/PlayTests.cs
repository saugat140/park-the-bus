using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using ParkTheBus.Api.Play;

namespace ParkTheBus.Api.Tests;

[Collection(PostgresCollection.Name)]
public sealed class PlayTests(PostgresFixture postgres) : IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly List<ApiFactory> _factories = [];
    private readonly DateTimeOffset _day = new(2026, 11, 23, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Start_is_idempotent_and_answer_scores_one_match()
    {
        var clock = new TestClock(_day);
        using var client = Client(clock);
        var session = Guid.NewGuid();
        var promptId = await PromptId("Name a forward from the sample");

        var first = await Start(client, promptId, session);
        clock.Advance(TimeSpan.FromSeconds(3));
        var second = await Start(client, promptId, session);

        Assert.Equal(HttpStatusCode.OK, first.Status);
        Assert.Equal(HttpStatusCode.OK, second.Status);
        Assert.Equal(first.Body!.StartedAt, second.Body!.StartedAt);
        Assert.Equal(25, first.Body.DurationSeconds);
        Assert.Equal(first.Body.StartedAt.AddSeconds(25), first.Body.EndsAt);

        var answer = await Answer(client, promptId, session, "Hidden Alias");
        Assert.Equal(HttpStatusCode.OK, answer.Status);
        Assert.Equal(AnswerOutcomes.Correct, answer.Body!.Outcome);
        Assert.Equal(10, answer.Body.Points);
        Assert.Equal("Secret Striker", answer.Body.Matched!.Name);
        Assert.Contains(answer.Body.Answers!, a => a.Name == "Secret Striker" && a.Points == 10);
        Assert.Null(answer.Body.Choices);
        Assert.DoesNotContain("Hidden Alias", answer.Raw);
        Assert.DoesNotContain("hidden research", answer.Raw);
    }

    [Fact]
    public async Task Ambiguous_match_returns_choices_without_finishing()
    {
        var clock = new TestClock(_day);
        using var client = Client(clock);
        var session = Guid.NewGuid();
        var promptId = await PromptId("Name a Ronaldo");

        Assert.Equal(HttpStatusCode.OK, (await Start(client, promptId, session)).Status);

        var ambiguous = await Answer(client, promptId, session, "Ronaldo");
        Assert.Equal(HttpStatusCode.OK, ambiguous.Status);
        Assert.Equal(AnswerOutcomes.Ambiguous, ambiguous.Body!.Outcome);
        Assert.Equal(0, ambiguous.Body.Points);
        Assert.Null(ambiguous.Body.Answers);
        Assert.Equal(2, ambiguous.Body.Choices!.Count);
        Assert.Contains(ambiguous.Body.Choices, c => c.Disambiguation == "Portugal");
        Assert.Contains(ambiguous.Body.Choices, c => c.Disambiguation == "Brazil, born 1976");
        Assert.DoesNotContain("\"entityId\"", ambiguous.Raw, StringComparison.OrdinalIgnoreCase);

        var confirmed = await Answer(client, promptId, session, "Ronaldo", "Portugal");
        Assert.Equal(HttpStatusCode.OK, confirmed.Status);
        Assert.Equal(AnswerOutcomes.Correct, confirmed.Body!.Outcome);
        Assert.Equal(10, confirmed.Body.Points);
        Assert.Equal("Cristiano Ronaldo", confirmed.Body.Matched!.Name);
        Assert.Equal(2, confirmed.Body.Answers!.Count);
    }

    [Fact]
    public async Task Wrong_answer_finishes_with_zero_and_blocks_a_second_submit()
    {
        var clock = new TestClock(_day);
        using var client = Client(clock);
        var session = Guid.NewGuid();
        var promptId = await PromptId("Name a forward from the sample");

        Assert.Equal(HttpStatusCode.OK, (await Start(client, promptId, session)).Status);

        var wrong = await Answer(client, promptId, session, "Nobody");
        Assert.Equal(HttpStatusCode.OK, wrong.Status);
        Assert.Equal(AnswerOutcomes.Incorrect, wrong.Body!.Outcome);
        Assert.Equal(0, wrong.Body.Points);
        Assert.NotEmpty(wrong.Body.Answers!);

        var again = await Answer(client, promptId, session, "Secret Striker");
        Assert.Equal(HttpStatusCode.Conflict, again.Status);
        Assert.Equal(AnswerOutcomes.Incorrect, again.Body!.Outcome);
        Assert.Equal(0, again.Body.Points);
    }

    [Fact]
    public async Task Answer_after_the_timer_is_a_timeout()
    {
        var clock = new TestClock(_day);
        using var client = Client(clock);
        var session = Guid.NewGuid();
        var promptId = await PromptId("Name a forward from the sample");

        Assert.Equal(HttpStatusCode.OK, (await Start(client, promptId, session)).Status);
        clock.Advance(TimeSpan.FromSeconds(25));

        var timedOut = await Answer(client, promptId, session, "Secret Striker");
        Assert.Equal(HttpStatusCode.OK, timedOut.Status);
        Assert.Equal(AnswerOutcomes.TimedOut, timedOut.Body!.Outcome);
        Assert.Equal(0, timedOut.Body.Points);
        Assert.Null(timedOut.Body.Matched);
        Assert.NotEmpty(timedOut.Body.Answers!);
    }

    [Fact]
    public async Task Answer_without_start_conflicts_and_draft_prompt_is_not_found()
    {
        var clock = new TestClock(_day);
        using var client = Client(clock);
        var session = Guid.NewGuid();
        var forwardId = await PromptId("Name a forward from the sample");
        var draftId = await PromptId("This draft must stay off the response");

        var notStarted = await Answer(client, forwardId, session, "Secret Striker");
        Assert.Equal(HttpStatusCode.Conflict, notStarted.Status);

        var draftStart = await Start(client, draftId, session);
        Assert.Equal(HttpStatusCode.NotFound, draftStart.Status);
    }

    private HttpClient Client(TestClock clock)
    {
        var factory = new ApiFactory(postgres.ConnectionString, clock);
        _factories.Add(factory);
        var client = factory.CreateClient();
        return client;
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

    private static async Task<(HttpStatusCode Status, StartPromptResponse? Body)> Start(
        HttpClient client,
        long promptId,
        Guid sessionId)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, $"/puzzles/today/prompts/{promptId}/start")
        {
            Content = JsonContent.Create(new StartPromptRequest(sessionId))
        };
        request.Headers.Add("X-Session-Id", sessionId.ToString());
        var response = await client.SendAsync(request);
        var raw = await response.Content.ReadAsStringAsync();
        var body = string.IsNullOrWhiteSpace(raw)
            ? null
            : JsonSerializer.Deserialize<StartPromptResponse>(raw, JsonOptions);
        return (response.StatusCode, body);
    }

    private static async Task<(HttpStatusCode Status, AnswerPromptResponse? Body, string Raw)> Answer(
        HttpClient client,
        long promptId,
        Guid sessionId,
        string text,
        string? disambiguation = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, $"/puzzles/today/prompts/{promptId}/answer")
        {
            Content = JsonContent.Create(new AnswerPromptRequest(sessionId, text, disambiguation))
        };
        request.Headers.Add("X-Session-Id", sessionId.ToString());
        var response = await client.SendAsync(request);
        var raw = await response.Content.ReadAsStringAsync();
        var body = string.IsNullOrWhiteSpace(raw)
            ? null
            : JsonSerializer.Deserialize<AnswerPromptResponse>(raw, JsonOptions);
        return (response.StatusCode, body, raw);
    }
}
