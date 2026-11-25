using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace ParkTheBus.Api.Tests;

internal sealed class ApiFactory(string connectionString, TestClock clock) : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(Microsoft.AspNetCore.Hosting.IWebHostBuilder builder)
    {
        builder.UseSetting("ConnectionStrings:ParkTheBus", connectionString);
        builder.UseSetting("Game:PlayPermitLimit", "10000");
        builder.UseSetting("Game:PlayWindowSeconds", "60");
        builder.UseSetting("Game:PromptDurationSeconds", "25");
        builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<TimeProvider>();
            services.AddSingleton<TimeProvider>(clock);
        });
    }
}
