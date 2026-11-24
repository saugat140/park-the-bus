using Npgsql;
using NpgsqlTypes;

namespace ParkTheBus.Api.Puzzles;

// Issue #22. The selected columns are the whole response. Answers, aliases,
// fame, tiers, notes, and tags are not read.
public sealed class TodayPuzzleReader(NpgsqlDataSource dataSource)
{
    public async Task<TodayPuzzleResponse?> ReadAsync(DateOnly puzzleDate, CancellationToken cancellationToken)
    {
        // A draft or retired prompt still proves the puzzle row exists.
        // Its text is not selected, because the join requires status reviewed.
        const string sql = """
            SELECT dpp.position, p.id, p.prompt_text
            FROM daily_puzzles AS puzzle
            LEFT JOIN daily_puzzle_prompts AS dpp
              ON dpp.puzzle_date = puzzle.puzzle_date
            LEFT JOIN prompts AS p
              ON p.id = dpp.prompt_id
             AND p.status = 'reviewed'
            WHERE puzzle.puzzle_date = @puzzle_date
            ORDER BY dpp.position
            """;

        await using var command = dataSource.CreateCommand(sql);
        command.Parameters.Add(new NpgsqlParameter("puzzle_date", NpgsqlDbType.Date)
        {
            Value = puzzleDate
        });

        var sawPuzzle = false;
        var prompts = new List<TodayPromptResponse>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            sawPuzzle = true;
            if (reader.IsDBNull(1))
                continue;

            prompts.Add(new TodayPromptResponse(
                reader.GetInt16(0),
                reader.GetInt64(1),
                reader.GetString(2)));
        }

        return sawPuzzle
            ? new TodayPuzzleResponse(puzzleDate, prompts)
            : null;
    }
}
