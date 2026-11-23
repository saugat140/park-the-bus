namespace ParkTheBus.Api.Puzzles;

public sealed record TodayPuzzleResponse(
    DateOnly PuzzleDate,
    IReadOnlyList<TodayPromptResponse> Prompts);

public sealed record TodayPromptResponse(short Position, long PromptId, string Text);
