using System.Text.Json;

namespace __BUNDLE_ID__.Contracts;

/// UI state phases — mirrors `TaskPhase` in Core/ and the `phase` field of
/// every Verification/Contracts/*.json fixture. Keep the wire values
/// identical across platforms; that is the contract.
public enum TaskPhase { Loading, Empty, Loaded, Error }

public sealed record TaskItem(
    string Id,
    string Title,
    string Notes,
    bool IsCompleted,
    string Priority);

/// The deterministic state a platform UI must render for one contract
/// fixture.
public sealed record ContractState(
    string Id,
    TaskPhase Phase,
    IReadOnlyList<TaskItem> Tasks,
    string? ErrorMessage);

public static class ContractFixtures
{
    public static ContractState Load(string path)
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(path));
        return Parse(doc.RootElement);
    }

    public static IReadOnlyList<ContractState> LoadAll(string directory) =>
        Directory.EnumerateFiles(directory, "*.json")
            .OrderBy(p => p, StringComparer.Ordinal)
            .Select(Load)
            .ToList();

    public static ContractState Parse(JsonElement e)
    {
        var phase = e.GetProperty("phase").GetString() switch
        {
            "loading" => TaskPhase.Loading,
            "empty" => TaskPhase.Empty,
            "loaded" => TaskPhase.Loaded,
            _ => TaskPhase.Error,
        };

        var tasks = new List<TaskItem>();
        if (e.TryGetProperty("tasks", out var array) && array.ValueKind == JsonValueKind.Array)
        {
            foreach (var t in array.EnumerateArray())
            {
                tasks.Add(new TaskItem(
                    Id: t.GetProperty("id").GetString() ?? "",
                    Title: t.GetProperty("title").GetString() ?? "",
                    Notes: t.TryGetProperty("notes", out var n) ? n.GetString() ?? "" : "",
                    IsCompleted: t.TryGetProperty("isCompleted", out var c) && c.GetBoolean(),
                    Priority: t.TryGetProperty("priority", out var p) ? p.GetString() ?? "" : ""));
            }
        }

        string? error = null;
        if (e.TryGetProperty("errorMessage", out var em) && em.ValueKind == JsonValueKind.String)
        {
            error = em.GetString();
        }

        return new ContractState(
            Id: e.GetProperty("id").GetString() ?? "",
            Phase: phase,
            Tasks: tasks,
            ErrorMessage: error);
    }
}
