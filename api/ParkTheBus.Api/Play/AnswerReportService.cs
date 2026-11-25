using Npgsql;
using NpgsqlTypes;

namespace ParkTheBus.Api.Play;

// Issue #25. Players file wrong/missing reports. Review is tools/review SQL.
public sealed class AnswerReportService(NpgsqlDataSource dataSource, TimeProvider clock)
{
    public async Task<ReportAnswerResponse?> CreateAsync(
        DateOnly puzzleDate,
        long promptId,
        ReportAnswerRequest request,
        CancellationToken cancellationToken)
    {
        if (request.SessionId == Guid.Empty)
            return null;

        var text = (request.Text ?? string.Empty).Trim();
        if (text.Length == 0)
            return null;

        if (!ReportKinds.IsValid(request.Kind))
            return null;

        var kind = ReportKinds.Normalize(request.Kind);
        var notes = string.IsNullOrWhiteSpace(request.Notes) ? null : request.Notes.Trim();
        var now = clock.GetUtcNow();

        await using var command = dataSource.CreateCommand(
            """
            INSERT INTO answer_reports (
              puzzle_date, prompt_id, session_id, raw_input,
              report_kind, review_status, notes, created_at)
            SELECT
              dpp.puzzle_date, dpp.prompt_id, @session_id, @raw_input,
              @report_kind, 'open', @notes, @created_at
            FROM daily_puzzle_prompts AS dpp
            JOIN prompts AS p ON p.id = dpp.prompt_id
            WHERE dpp.puzzle_date = @puzzle_date
              AND dpp.prompt_id = @prompt_id
              AND p.status = 'reviewed'
            RETURNING id, review_status
            """);
        command.Parameters.Add(new NpgsqlParameter("puzzle_date", NpgsqlDbType.Date) { Value = puzzleDate });
        command.Parameters.AddWithValue("prompt_id", promptId);
        command.Parameters.AddWithValue("session_id", request.SessionId);
        command.Parameters.AddWithValue("raw_input", text);
        command.Parameters.AddWithValue("report_kind", kind);
        command.Parameters.Add(new NpgsqlParameter("notes", NpgsqlDbType.Text)
        {
            Value = notes is null ? DBNull.Value : notes
        });
        command.Parameters.Add(new NpgsqlParameter("created_at", NpgsqlDbType.TimestampTz) { Value = now });

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
            return null;

        return new ReportAnswerResponse(reader.GetInt64(0), reader.GetString(1));
    }
}
