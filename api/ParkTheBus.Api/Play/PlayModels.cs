namespace ParkTheBus.Api.Play;

public sealed record StartPromptRequest(Guid SessionId);

public sealed record StartPromptResponse(
    DateTimeOffset StartedAt,
    DateTimeOffset EndsAt,
    int DurationSeconds);

public sealed record AnswerPromptRequest(
    Guid SessionId,
    string Text,
    string? Disambiguation = null);

public sealed record AnswerChoice(string Name, string? Disambiguation);

public sealed record RevealedAnswer(string Name, string? Disambiguation, int Points);

public sealed record AnswerPromptResponse(
    string Outcome,
    int Points,
    AnswerChoice? Matched,
    IReadOnlyList<AnswerChoice>? Choices,
    IReadOnlyList<RevealedAnswer>? Answers);

public static class AnswerOutcomes
{
    public const string Correct = "correct";
    public const string Incorrect = "incorrect";
    public const string TimedOut = "timedOut";
    public const string Ambiguous = "ambiguous";
}
