namespace ParkTheBus.Api.Play;

public sealed class GameOptions
{
    public const string SectionName = "Game";

    // Product default from the early mockup. Not tied to prompts-per-day.
    public int PromptDurationSeconds { get; set; } = 25;

    public int PlayPermitLimit { get; set; } = 60;

    public int PlayWindowSeconds { get; set; } = 60;
}
