using System.Threading.RateLimiting;
using Microsoft.AspNetCore.RateLimiting;
using Npgsql;
using ParkTheBus.Api.Play;
using ParkTheBus.Api.Puzzles;

var builder = WebApplication.CreateBuilder(args);

var connectionString = builder.Configuration.GetConnectionString("ParkTheBus");
if (string.IsNullOrWhiteSpace(connectionString))
{
    throw new InvalidOperationException(
        "ConnectionStrings:ParkTheBus is required. Set ConnectionStrings__ParkTheBus.");
}

builder.Services.Configure<GameOptions>(builder.Configuration.GetSection(GameOptions.SectionName));
var gameOptions = builder.Configuration.GetSection(GameOptions.SectionName).Get<GameOptions>() ?? new GameOptions();

builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton(NpgsqlDataSource.Create(connectionString));
builder.Services.AddSingleton<TodayPuzzleReader>();
builder.Services.AddSingleton<PromptPlayService>();
builder.Services.AddControllers();
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("play", httpContext =>
    {
        var ip = httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        var session = httpContext.Request.Headers["X-Session-Id"].FirstOrDefault()
            ?? httpContext.Request.Headers["x-session-id"].FirstOrDefault()
            ?? "anon";
        return RateLimitPartition.GetFixedWindowLimiter(
            $"{ip}:{session}",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = Math.Max(1, gameOptions.PlayPermitLimit),
                Window = TimeSpan.FromSeconds(Math.Max(1, gameOptions.PlayWindowSeconds)),
                QueueLimit = 0
            });
    });
});

var app = builder.Build();

app.UseHttpsRedirection();
app.UseRateLimiter();
app.MapControllers();
app.Run();

public partial class Program;
