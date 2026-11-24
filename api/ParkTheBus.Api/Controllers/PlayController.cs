using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using ParkTheBus.Api.Play;

namespace ParkTheBus.Api.Controllers;

// Issue #24. Server timer and answer judging for today's puzzle.
[ApiController]
[Route("puzzles/today/prompts/{promptId:long}")]
[EnableRateLimiting("play")]
public sealed class PlayController(PromptPlayService play, TimeProvider clock) : ControllerBase
{
    [HttpPost("start")]
    public async Task<ActionResult<StartPromptResponse>> Start(
        long promptId,
        [FromBody] StartPromptRequest request,
        CancellationToken cancellationToken)
    {
        Response.Headers.CacheControl = "no-store";
        if (request.SessionId == Guid.Empty)
            return BadRequest();

        var today = DateOnly.FromDateTime(clock.GetUtcNow().UtcDateTime);
        var started = await play.StartAsync(today, promptId, request.SessionId, cancellationToken);
        return started is null ? NotFound() : started;
    }

    [HttpPost("answer")]
    public async Task<ActionResult<AnswerPromptResponse>> Answer(
        long promptId,
        [FromBody] AnswerPromptRequest request,
        CancellationToken cancellationToken)
    {
        Response.Headers.CacheControl = "no-store";
        if (request.SessionId == Guid.Empty)
            return BadRequest();

        var today = DateOnly.FromDateTime(clock.GetUtcNow().UtcDateTime);
        var result = await play.AnswerAsync(today, promptId, request, cancellationToken);
        return result switch
        {
            AnswerResult.NotFoundResult => NotFound(),
            AnswerResult.NotStartedResult => Conflict(new { error = "Prompt has not been started." }),
            AnswerResult.ConflictResult body => Conflict(body.Body),
            AnswerResult.OkResult body => Ok(body.Body),
            _ => StatusCode(StatusCodes.Status500InternalServerError)
        };
    }
}
