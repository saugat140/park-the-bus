using Npgsql;
using Testcontainers.PostgreSql;

namespace ParkTheBus.Api.Tests;

public sealed class PostgresFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _container = new PostgreSqlBuilder("postgres:16").Build();

    public string ConnectionString => _container.GetConnectionString();

    public async Task InitializeAsync()
    {
        await _container.StartAsync();
        var schema = await File.ReadAllTextAsync(FindSchema());
        await using var dataSource = NpgsqlDataSource.Create(ConnectionString);
        await using (var apply = dataSource.CreateCommand(schema))
            await apply.ExecuteNonQueryAsync();
        await using (var seed = dataSource.CreateCommand(SeedSql))
            await seed.ExecuteNonQueryAsync();
    }

    public async Task DisposeAsync() => await _container.DisposeAsync();

    private static string FindSchema()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            var candidate = Path.Combine(dir.FullName, "db", "001_schema.sql");
            if (File.Exists(candidate))
                return candidate;
            dir = dir.Parent;
        }

        throw new InvalidOperationException("db/001_schema.sql was not found above the test output.");
    }

    private const string SeedSql = """
        INSERT INTO entities (kind, canonical_name, disambiguation)
        VALUES ('player', 'Secret Striker', 'must not leave the database');

        INSERT INTO entity_aliases (entity_id, alias)
        SELECT id, 'Hidden Alias' FROM entities WHERE canonical_name = 'Secret Striker';

        INSERT INTO prompts (prompt_text, answer_kind, difficulty, status, source_notes) VALUES
          ('Name a forward from the sample', 'player', 2, 'reviewed', 'hidden research note'),
          ('Name a club from the sample', 'club', 3, 'reviewed', NULL),
          ('This draft must stay off the response', 'player', 1, 'draft', NULL),
          ('Name a goalkeeper scheduled for the next date', 'player', 2, 'reviewed', NULL),
          ('Draft day prompt', 'player', 1, 'draft', NULL);

        INSERT INTO daily_puzzles (puzzle_date) VALUES
          ('2026-11-22'),
          ('2026-11-23'),
          ('2026-11-24');

        INSERT INTO daily_puzzle_prompts (puzzle_date, position, prompt_id)
        SELECT DATE '2026-11-23', 2, id FROM prompts WHERE prompt_text = 'Name a club from the sample';

        INSERT INTO daily_puzzle_prompts (puzzle_date, position, prompt_id)
        SELECT DATE '2026-11-23', 1, id FROM prompts WHERE prompt_text = 'Name a forward from the sample';

        INSERT INTO daily_puzzle_prompts (puzzle_date, position, prompt_id)
        SELECT DATE '2026-11-23', 3, id FROM prompts WHERE prompt_text = 'This draft must stay off the response';

        INSERT INTO daily_puzzle_prompts (puzzle_date, position, prompt_id)
        SELECT DATE '2026-11-24', 1, id FROM prompts WHERE prompt_text = 'Name a goalkeeper scheduled for the next date';

        INSERT INTO daily_puzzle_prompts (puzzle_date, position, prompt_id)
        SELECT DATE '2026-11-22', 1, id FROM prompts WHERE prompt_text = 'Draft day prompt';

        INSERT INTO prompt_answers (prompt_id, entity_id, fame)
        SELECT p.id, e.id, 5
        FROM prompts AS p
        CROSS JOIN entities AS e
        WHERE p.prompt_text = 'Name a forward from the sample'
          AND e.canonical_name = 'Secret Striker';
        """;
}

[CollectionDefinition(Name)]
public sealed class PostgresCollection : ICollectionFixture<PostgresFixture>
{
    public const string Name = "postgres";
}
