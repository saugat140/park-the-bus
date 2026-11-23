using Microsoft.AspNetCore.Mvc;
using ParkTheBus.Api.Puzzles;

namespace ParkTheBus.Api.Controllers;

// Issue #22. Today's puzzle is the row for the current UTC date.
[ApiController]
[Route("puzzles")]
public sealed class PuzzlesController(TodayPuzzleReader puzzles, TimeProvider clock) : ControllerBase
{
    [HttpGet("today")]
    public async Task<ActionResult<TodayPuzzleResponse>> GetToday(CancellationToken cancellationToken)
    {
        var now = clock.GetUtcNow();
        var today = DateOnly.FromDateTime(now.UtcDateTime);
        var puzzle = await puzzles.ReadAsync(today, cancellationToken);
        if (puzzle is null)
        {
            Response.Headers.CacheControl = "no-store";
            return NotFound();
        }

        // An empty day is not playable yet. Do not cache it until reset,
        // or a prompt reviewed later the same day stays hidden.
        if (puzzle.Prompts.Count == 0)
        {
            Response.Headers.CacheControl = "no-store";
            return puzzle;
        }

        CacheUntilNextUtcDay(now, today);
        return puzzle;
    }

    private void CacheUntilNextUtcDay(DateTimeOffset now, DateOnly today)
    {
        var reset = new DateTimeOffset(
            today.AddDays(1).ToDateTime(TimeOnly.MinValue),
            TimeSpan.Zero);
        var maxAge = (int)Math.Floor((reset - now).TotalSeconds);
        if (maxAge < 0)
            maxAge = 0;

        Response.Headers.CacheControl = $"public, max-age={maxAge}";
        Response.Headers.Expires = reset.ToString("R");
    }
}
