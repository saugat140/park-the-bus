using Microsoft.Extensions.Options;
using Npgsql;
using NpgsqlTypes;

namespace ParkTheBus.Api.Play;

// Issue #24. Start records the server timer. Answer judges through SQL only.
public sealed class PromptPlayService(
    NpgsqlDataSource dataSource,
    TimeProvider clock,
    IOptions<GameOptions> options)
{
    public async Task<StartPromptResponse?> StartAsync(
        DateOnly puzzleDate,
        long promptId,
        Guid sessionId,
        CancellationToken cancellationToken)
    {
        if (!await IsPlayablePromptAsync(puzzleDate, promptId, cancellationToken))
            return null;

        var now = clock.GetUtcNow();
        var duration = options.Value.PromptDurationSeconds;

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO prompt_starts (puzzle_date, prompt_id, session_id, started_at)
            VALUES (@puzzle_date, @prompt_id, @session_id, @started_at)
            ON CONFLICT (puzzle_date, prompt_id, session_id) DO NOTHING
            RETURNING started_at
            """,
            connection);
        command.Parameters.Add(new NpgsqlParameter("puzzle_date", NpgsqlDbType.Date) { Value = puzzleDate });
        command.Parameters.AddWithValue("prompt_id", promptId);
        command.Parameters.AddWithValue("session_id", sessionId);
        command.Parameters.Add(new NpgsqlParameter("started_at", NpgsqlDbType.TimestampTz) { Value = now });

        var inserted = await command.ExecuteScalarAsync(cancellationToken);
        DateTimeOffset startedAt;
        if (inserted is DateTime insertedAt)
            startedAt = AsUtc(insertedAt);
        else
        {
            await using var existing = new NpgsqlCommand(
                """
                SELECT started_at
                FROM prompt_starts
                WHERE puzzle_date = @puzzle_date
                  AND prompt_id = @prompt_id
                  AND session_id = @session_id
                """,
                connection);
            existing.Parameters.Add(new NpgsqlParameter("puzzle_date", NpgsqlDbType.Date) { Value = puzzleDate });
            existing.Parameters.AddWithValue("prompt_id", promptId);
            existing.Parameters.AddWithValue("session_id", sessionId);
            startedAt = AsUtc((DateTime)(await existing.ExecuteScalarAsync(cancellationToken))!);
        }

        return new StartPromptResponse(startedAt, startedAt.AddSeconds(duration), duration);
    }

    public async Task<AnswerResult> AnswerAsync(
        DateOnly puzzleDate,
        long promptId,
        AnswerPromptRequest request,
        CancellationToken cancellationToken)
    {
        if (!await IsPlayablePromptAsync(puzzleDate, promptId, cancellationToken))
            return AnswerResult.NotFound();

        var start = await ReadStartAsync(puzzleDate, promptId, request.SessionId, cancellationToken);
        if (start is null)
            return AnswerResult.NotStarted();

        var existing = await ReadSubmissionAsync(puzzleDate, promptId, request.SessionId, cancellationToken);
        if (existing is not null)
            return AnswerResult.Conflict(existing);

        var now = clock.GetUtcNow();
        var duration = options.Value.PromptDurationSeconds;
        var text = request.Text ?? string.Empty;

        if (now >= start.Value.AddSeconds(duration))
        {
            var timedOut = await FinishAsync(
                puzzleDate,
                promptId,
                request.SessionId,
                text,
                matchedEntityId: null,
                correct: false,
                points: 0,
                AnswerOutcomes.TimedOut,
                matched: null,
                cancellationToken);
            return AnswerResult.Ok(timedOut);
        }

        var matches = await MatchAsync(promptId, text, cancellationToken);
        if (matches.Count > 1)
        {
            var selected = SelectMatch(matches, request.Disambiguation);
            if (selected is null)
            {
                return AnswerResult.Ok(new AnswerPromptResponse(
                    AnswerOutcomes.Ambiguous,
                    0,
                    null,
                    matches.Select(m => new AnswerChoice(m.Name, m.Disambiguation)).ToArray(),
                    null));
            }

            matches = [selected];
        }

        if (matches.Count == 1)
        {
            var match = matches[0];
            var points = await ScoreAsync(promptId, match.EntityId, cancellationToken) ?? 0;
            var correct = await FinishAsync(
                puzzleDate,
                promptId,
                request.SessionId,
                text,
                match.EntityId,
                correct: true,
                points,
                AnswerOutcomes.Correct,
                new AnswerChoice(match.Name, match.Disambiguation),
                cancellationToken);
            return AnswerResult.Ok(correct);
        }

        var incorrect = await FinishAsync(
            puzzleDate,
            promptId,
            request.SessionId,
            text,
            matchedEntityId: null,
            correct: false,
            points: 0,
            AnswerOutcomes.Incorrect,
            matched: null,
            cancellationToken);
        return AnswerResult.Ok(incorrect);
    }

    private async Task<bool> IsPlayablePromptAsync(
        DateOnly puzzleDate,
        long promptId,
        CancellationToken cancellationToken)
    {
        await using var command = dataSource.CreateCommand(
            """
            SELECT 1
            FROM daily_puzzle_prompts AS dpp
            JOIN prompts AS p ON p.id = dpp.prompt_id
            WHERE dpp.puzzle_date = @puzzle_date
              AND dpp.prompt_id = @prompt_id
              AND p.status = 'reviewed'
            """);
        command.Parameters.Add(new NpgsqlParameter("puzzle_date", NpgsqlDbType.Date) { Value = puzzleDate });
        command.Parameters.AddWithValue("prompt_id", promptId);
        return await command.ExecuteScalarAsync(cancellationToken) is not null;
    }

    private async Task<DateTimeOffset?> ReadStartAsync(
        DateOnly puzzleDate,
        long promptId,
        Guid sessionId,
        CancellationToken cancellationToken)
    {
        await using var command = dataSource.CreateCommand(
            """
            SELECT started_at
            FROM prompt_starts
            WHERE puzzle_date = @puzzle_date
              AND prompt_id = @prompt_id
              AND session_id = @session_id
            """);
        command.Parameters.Add(new NpgsqlParameter("puzzle_date", NpgsqlDbType.Date) { Value = puzzleDate });
        command.Parameters.AddWithValue("prompt_id", promptId);
        command.Parameters.AddWithValue("session_id", sessionId);
        var value = await command.ExecuteScalarAsync(cancellationToken);
        return value is DateTime startedAt ? AsUtc(startedAt) : null;
    }

    private async Task<AnswerPromptResponse?> ReadSubmissionAsync(
        DateOnly puzzleDate,
        long promptId,
        Guid sessionId,
        CancellationToken cancellationToken)
    {
        await using var command = dataSource.CreateCommand(
            """
            SELECT s.correct, s.points, e.canonical_name, e.disambiguation
            FROM submissions AS s
            LEFT JOIN entities AS e ON e.id = s.matched_entity_id
            WHERE s.puzzle_date = @puzzle_date
              AND s.prompt_id = @prompt_id
              AND s.session_id = @session_id
            """);
        command.Parameters.Add(new NpgsqlParameter("puzzle_date", NpgsqlDbType.Date) { Value = puzzleDate });
        command.Parameters.AddWithValue("prompt_id", promptId);
        command.Parameters.AddWithValue("session_id", sessionId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
            return null;

        var correct = reader.GetBoolean(0);
        var points = reader.GetInt32(1);
        AnswerChoice? matched = reader.IsDBNull(2)
            ? null
            : new AnswerChoice(reader.GetString(2), reader.IsDBNull(3) ? null : reader.GetString(3));
        var outcome = correct ? AnswerOutcomes.Correct
            : points == 0 && matched is null ? AnswerOutcomes.Incorrect
            : AnswerOutcomes.Incorrect;
        // Timed-out rows are also incorrect with zero points. Replay as incorrect.
        var answers = await RevealAnswersAsync(promptId, cancellationToken);
        return new AnswerPromptResponse(outcome, points, matched, null, answers);
    }

    private async Task<IReadOnlyList<MatchRow>> MatchAsync(
        long promptId,
        string text,
        CancellationToken cancellationToken)
    {
        await using var command = dataSource.CreateCommand(
            """
            SELECT entity_id, canonical_name, disambiguation, match_kind
            FROM match_prompt_answer(@prompt_id, @raw)
            ORDER BY canonical_name, disambiguation NULLS FIRST
            """);
        command.Parameters.AddWithValue("prompt_id", promptId);
        command.Parameters.AddWithValue("raw", text);

        var rows = new List<MatchRow>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new MatchRow(
                reader.GetInt64(0),
                reader.GetString(1),
                reader.IsDBNull(2) ? null : reader.GetString(2),
                reader.GetString(3)));
        }

        return rows;
    }

    private static MatchRow? SelectMatch(IReadOnlyList<MatchRow> matches, string? disambiguation)
    {
        if (string.IsNullOrWhiteSpace(disambiguation))
            return null;

        var wanted = disambiguation.Trim();
        return matches.FirstOrDefault(m =>
            string.Equals(m.Disambiguation, wanted, StringComparison.OrdinalIgnoreCase));
    }

    private async Task<int?> ScoreAsync(long promptId, long entityId, CancellationToken cancellationToken)
    {
        await using var command = dataSource.CreateCommand(
            "SELECT score_prompt_answer(@prompt_id, @entity_id)");
        command.Parameters.AddWithValue("prompt_id", promptId);
        command.Parameters.AddWithValue("entity_id", entityId);
        var value = await command.ExecuteScalarAsync(cancellationToken);
        if (value is null or DBNull)
            return null;
        return Convert.ToInt32(value);
    }

    private async Task<AnswerPromptResponse> FinishAsync(
        DateOnly puzzleDate,
        long promptId,
        Guid sessionId,
        string rawInput,
        long? matchedEntityId,
        bool correct,
        int points,
        string outcome,
        AnswerChoice? matched,
        CancellationToken cancellationToken)
    {
        await using var command = dataSource.CreateCommand(
            """
            INSERT INTO submissions (
              puzzle_date, prompt_id, session_id, raw_input,
              matched_entity_id, correct, points)
            VALUES (
              @puzzle_date, @prompt_id, @session_id, @raw_input,
              @matched_entity_id, @correct, @points)
            """);
        command.Parameters.Add(new NpgsqlParameter("puzzle_date", NpgsqlDbType.Date) { Value = puzzleDate });
        command.Parameters.AddWithValue("prompt_id", promptId);
        command.Parameters.AddWithValue("session_id", sessionId);
        command.Parameters.AddWithValue("raw_input", rawInput);
        command.Parameters.Add(new NpgsqlParameter("matched_entity_id", NpgsqlDbType.Bigint)
        {
            Value = matchedEntityId is null ? DBNull.Value : matchedEntityId.Value
        });
        command.Parameters.AddWithValue("correct", correct);
        command.Parameters.AddWithValue("points", points);
        await command.ExecuteNonQueryAsync(cancellationToken);

        var answers = await RevealAnswersAsync(promptId, cancellationToken);
        return new AnswerPromptResponse(outcome, points, matched, null, answers);
    }

    private async Task<IReadOnlyList<RevealedAnswer>> RevealAnswersAsync(
        long promptId,
        CancellationToken cancellationToken)
    {
        // Reveal after the prompt is finished for this session. No aliases, no fame.
        await using var command = dataSource.CreateCommand(
            """
            SELECT e.canonical_name, e.disambiguation, COALESCE(rt.points, 0)
            FROM prompt_answers AS pa
            JOIN entities AS e ON e.id = pa.entity_id
            LEFT JOIN rarity_tiers AS rt ON rt.tier_number = pa.tier_number
            WHERE pa.prompt_id = @prompt_id
            ORDER BY COALESCE(rt.points, 0) DESC, e.canonical_name, e.disambiguation NULLS FIRST
            """);
        command.Parameters.AddWithValue("prompt_id", promptId);

        var answers = new List<RevealedAnswer>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            answers.Add(new RevealedAnswer(
                reader.GetString(0),
                reader.IsDBNull(1) ? null : reader.GetString(1),
                reader.GetInt32(2)));
        }

        return answers;
    }

    private static DateTimeOffset AsUtc(DateTime value)
    {
        return value.Kind switch
        {
            DateTimeKind.Utc => new DateTimeOffset(value),
            DateTimeKind.Local => new DateTimeOffset(value.ToUniversalTime()),
            _ => new DateTimeOffset(DateTime.SpecifyKind(value, DateTimeKind.Utc))
        };
    }

    private sealed record MatchRow(long EntityId, string Name, string? Disambiguation, string MatchKind);
}

public abstract record AnswerResult
{
    public sealed record NotFoundResult : AnswerResult;
    public sealed record NotStartedResult : AnswerResult;
    public sealed record ConflictResult(AnswerPromptResponse Body) : AnswerResult;
    public sealed record OkResult(AnswerPromptResponse Body) : AnswerResult;

    public static AnswerResult NotFound() => new NotFoundResult();
    public static AnswerResult NotStarted() => new NotStartedResult();
    public static AnswerResult Conflict(AnswerPromptResponse body) => new ConflictResult(body);
    public static AnswerResult Ok(AnswerPromptResponse body) => new OkResult(body);
}
