using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using ParkTheBus.Api.Play;

namespace ParkTheBus.Api.Controllers;

// Issues #24 and #25. Play a prompt and report a wrong or missing answer.
[ApiController]
[Route("puzzles/today/prompts/{promptId:long}")]
[EnableRateLimiting("play")]
public sealed class PlayController(
    PromptPlayService play,
    AnswerReportService reports,
    TimeProvider clock) : ControllerBase
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

    [HttpPost("report")]
    public async Task<ActionResult<ReportAnswerResponse>> Report(
        long promptId,
        [FromBody] ReportAnswerRequest request,
        CancellationToken cancellationToken)
    {
        Response.Headers.CacheControl = "no-store";
        if (request.SessionId == Guid.Empty
            || string.IsNullOrWhiteSpace(request.Text)
            || !ReportKinds.IsValid(request.Kind))
        {
            return BadRequest();
        }

        var today = DateOnly.FromDateTime(clock.GetUtcNow().UtcDateTime);
        var created = await reports.CreateAsync(today, promptId, request, cancellationToken);
        if (created is null)
            return NotFound();

        return Created($"/puzzles/today/prompts/{promptId}/report/{created.Id}", created);
    }
}
