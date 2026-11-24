using __BUNDLE_ID__.Contracts;
using Xunit;

namespace __BUNDLE_ID__.Tests;

/// Contract-fixture tests — every JSON fixture in Verification/Contracts
/// must parse into a well-formed ContractState. This is the Windows half of
/// `swiftport verify --mode contracts`; visual snapshots land with the
/// Windows CI capture path.
public class ContractTests
{
    private static string FixturesDir()
    {
        // Linked fixtures are copied next to the test assembly under Contracts/.
        var dir = Path.Combine(AppContext.BaseDirectory, "Contracts");
        Assert.True(Directory.Exists(dir), $"contract fixtures not found at {dir}");
        return dir;
    }

    [Fact]
    public void AllFixtures_Parse()
    {
        var states = ContractFixtures.LoadAll(FixturesDir());
        Assert.NotEmpty(states);
        Assert.Equal(
            new[] { "empty", "error", "loading", "longText", "populated" },
            states.Select(s => s.Id).OrderBy(x => x).ToArray());
    }

    [Theory]
    [InlineData("loading", TaskPhase.Loading)]
    [InlineData("empty", TaskPhase.Empty)]
    [InlineData("populated", TaskPhase.Loaded)]
    [InlineData("longText", TaskPhase.Loaded)]
    [InlineData("error", TaskPhase.Error)]
    public void Phase_MapsCorrectly(string fixture, TaskPhase expected)
    {
        var state = ContractFixtures.Load(Path.Combine(FixturesDir(), $"{fixture}.json"));
        Assert.Equal(expected, state.Phase);
    }

    [Fact]
    public void Loaded_HasTasks()
    {
        var state = ContractFixtures.Load(Path.Combine(FixturesDir(), "populated.json"));
        Assert.NotEmpty(state.Tasks);
        Assert.All(state.Tasks, t =>
        {
            Assert.False(string.IsNullOrWhiteSpace(t.Id));
            Assert.False(string.IsNullOrWhiteSpace(t.Title));
        });
    }

    [Fact]
    public void Error_HasMessage()
    {
        var state = ContractFixtures.Load(Path.Combine(FixturesDir(), "error.json"));
        Assert.False(string.IsNullOrWhiteSpace(state.ErrorMessage));
    }
}
