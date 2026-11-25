namespace ParkTheBus.Api.Play;

public sealed record ReportAnswerRequest(
    Guid SessionId,
    string Text,
    string Kind,
    string? Notes = null);

public sealed record ReportAnswerResponse(long Id, string ReviewStatus);

public static class ReportKinds
{
    public const string Wrong = "wrong";
    public const string Missing = "missing";

    public static bool IsValid(string? kind) =>
        string.Equals(kind, Wrong, StringComparison.OrdinalIgnoreCase)
        || string.Equals(kind, Missing, StringComparison.OrdinalIgnoreCase);

    public static string Normalize(string kind) => kind.Trim().ToLowerInvariant();
}
