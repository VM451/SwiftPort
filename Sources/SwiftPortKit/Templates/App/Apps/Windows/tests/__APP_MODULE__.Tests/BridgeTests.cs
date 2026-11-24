using __BUNDLE_ID__.Bridge;
using Xunit;

namespace __BUNDLE_ID__.Tests;

/// End-to-end bridge tests: exercise the real Swift `AppCoreCABI.dll`
/// through P/Invoke. The Windows CI job builds the DLL from Core/ and
/// stages it under `Bridges/WindowsABI/lib/`, which the test csproj copies
/// next to the assembly. Tests skip cleanly when the DLL isn't present
/// (local builds before `swift build --product AppCoreCABI`).
public class BridgeTests
{
    private static bool BridgeAvailable =>
        File.Exists(Path.Combine(AppContext.BaseDirectory, "AppCoreCABI.dll"));

    [Fact]
    public void Abi_Version_Is_Positive()
    {
        if (!BridgeAvailable) return;
        Assert.True(SwiftPortBridge.AbiVersion() >= 1);
    }

    [Fact]
    public void Fixture_Snapshot_RoundTrips_Through_Swift()
    {
        if (!BridgeAvailable) return;
        var fixturePath = Path.Combine(AppContext.BaseDirectory, "Contracts", "populated.json");
        Assert.True(File.Exists(fixturePath), $"fixture not found at {fixturePath}");
        var fixtureJson = File.ReadAllText(fixturePath);

        var snap = SwiftPortBridge.SnapshotFromFixture(fixtureJson);
        Assert.NotNull(snap);
        Assert.Equal("loaded", snap!.Phase);
        Assert.NotEmpty(snap.Tasks);
        Assert.All(snap.Tasks, t => Assert.False(string.IsNullOrEmpty(t.Title)));
    }

    [Fact]
    public void Store_Add_Toggle_Delete_Work()
    {
        if (!BridgeAvailable) return;

        var snap = SwiftPortBridge.ResetStore();
        Assert.NotNull(snap);

        snap = SwiftPortBridge.AddTask("bridge round-trip", notes: "", priority: "low");
        Assert.NotNull(snap);
        var added = Assert.Single(snap!.Tasks, t => t.Title == "bridge round-trip");

        snap = SwiftPortBridge.ToggleTask(added.Id);
        Assert.Contains(snap!.Tasks, t => t.Id == added.Id && t.IsCompleted);

        snap = SwiftPortBridge.DeleteTask(added.Id);
        Assert.DoesNotContain(snap!.Tasks, t => t.Id == added.Id);
    }
}
