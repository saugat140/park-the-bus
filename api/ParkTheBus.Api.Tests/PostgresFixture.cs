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
        INSERT INTO entities (kind, canonical_name, disambiguation) VALUES
          ('player', 'Secret Striker', 'must not leave the database'),
          ('player', 'Cristiano Ronaldo', 'Portugal'),
          ('player', 'Ronaldo', 'Brazil, born 1976');

        INSERT INTO entity_aliases (entity_id, alias)
        SELECT id, canonical_name FROM entities;

        INSERT INTO entity_aliases (entity_id, alias)
        SELECT id, 'Hidden Alias' FROM entities WHERE canonical_name = 'Secret Striker';

        INSERT INTO entity_aliases (entity_id, alias)
        SELECT id, 'Ronaldo' FROM entities WHERE canonical_name = 'Cristiano Ronaldo';

        INSERT INTO prompts (prompt_text, answer_kind, difficulty, status, source_notes) VALUES
          ('Name a forward from the sample', 'player', 2, 'reviewed', 'hidden research note'),
          ('Name a club from the sample', 'club', 3, 'reviewed', NULL),
          ('This draft must stay off the response', 'player', 1, 'draft', NULL),
          ('Name a goalkeeper scheduled for the next date', 'player', 2, 'reviewed', NULL),
          ('Draft day prompt', 'player', 1, 'draft', NULL),
          ('Name a Ronaldo', 'player', 2, 'reviewed', NULL);

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
        SELECT DATE '2026-11-23', 4, id FROM prompts WHERE prompt_text = 'Name a Ronaldo';

        INSERT INTO daily_puzzle_prompts (puzzle_date, position, prompt_id)
        SELECT DATE '2026-11-24', 1, id FROM prompts WHERE prompt_text = 'Name a goalkeeper scheduled for the next date';

        INSERT INTO daily_puzzle_prompts (puzzle_date, position, prompt_id)
        SELECT DATE '2026-11-22', 1, id FROM prompts WHERE prompt_text = 'Draft day prompt';

        INSERT INTO prompt_answers (prompt_id, entity_id, fame, prior_rarity, tier_number)
        SELECT p.id, e.id, 5, 0, 1
        FROM prompts AS p
        CROSS JOIN entities AS e
        WHERE p.prompt_text = 'Name a forward from the sample'
          AND e.canonical_name = 'Secret Striker';

        INSERT INTO prompt_answers (prompt_id, entity_id, fame, prior_rarity, tier_number)
        SELECT p.id, e.id, 5, 0, 1
        FROM prompts AS p
        CROSS JOIN entities AS e
        WHERE p.prompt_text = 'Name a Ronaldo'
          AND e.canonical_name = 'Cristiano Ronaldo';

        INSERT INTO prompt_answers (prompt_id, entity_id, fame, prior_rarity, tier_number)
        SELECT p.id, e.id, 2, 75, 4
        FROM prompts AS p
        CROSS JOIN entities AS e
        WHERE p.prompt_text = 'Name a Ronaldo'
          AND e.canonical_name = 'Ronaldo'
          AND e.disambiguation = 'Brazil, born 1976';
        """;
}

[CollectionDefinition(Name)]
public sealed class PostgresCollection : ICollectionFixture<PostgresFixture>
{
    public const string Name = "postgres";
}
