using Npgsql;
using ParkTheBus.Api.Puzzles;

var builder = WebApplication.CreateBuilder(args);

var connectionString = builder.Configuration.GetConnectionString("ParkTheBus");
if (string.IsNullOrWhiteSpace(connectionString))
{
    throw new InvalidOperationException(
        "ConnectionStrings:ParkTheBus is required. Set ConnectionStrings__ParkTheBus.");
}

builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton(NpgsqlDataSource.Create(connectionString));
builder.Services.AddSingleton<TodayPuzzleReader>();
builder.Services.AddControllers();

var app = builder.Build();

app.UseHttpsRedirection();
app.MapControllers();
app.Run();

public partial class Program;
