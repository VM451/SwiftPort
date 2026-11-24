using System.ComponentModel;
using System.Text.Json;
using Microsoft.UI.Xaml;

namespace __BUNDLE_ID__;

/// UI state phases — mirrors `TaskPhase` in Core/ and the `phase` field of
/// every Verification/Contracts/*.json fixture. Keep the wire values
/// identical across platforms; that is the contract.
public enum TaskPhase { Loading, Empty, Loaded, Error }

/// One task row. Mutable + INPC so the ListView updates live.
public sealed class TaskItem : INotifyPropertyChanged
{
    private bool _isCompleted;

    public string Id { get; }
    public string Title { get; }
    public string Notes { get; }
    public string Priority { get; }

    public bool IsCompleted
    {
        get => _isCompleted;
        set
        {
            if (_isCompleted == value) return;
            _isCompleted = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(IsCompleted)));
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DisplayTitle)));
        }
    }

    /// "✓ " prefix when completed — no strikethrough in plain TextBlock,
    /// so the check glyph carries the done state alongside the CheckBox.
    public string DisplayTitle => (IsCompleted ? "✓ " : "") + Title;

    public string PriorityBadge => Priority.Length == 0
        ? ""
        : char.ToUpperInvariant(Priority[0]) + Priority[1..];

    public Visibility NotesVisibility =>
        string.IsNullOrEmpty(Notes) ? Visibility.Collapsed : Visibility.Visible;

    public TaskItem(string id, string title, string notes, bool isCompleted, string priority)
    {
        Id = id;
        Title = title;
        Notes = notes;
        Priority = priority;
        _isCompleted = isCompleted;
    }

    public event PropertyChangedEventHandler? PropertyChanged;
}

/// The deterministic state a platform UI must render for one contract
/// fixture.
public sealed record ContractState(
    string Id,
    TaskPhase Phase,
    IReadOnlyList<TaskItem> Tasks,
    string? ErrorMessage);

public static class ContractFixtures
{
    public static IReadOnlyList<ContractState> LoadAll(string directory) =>
        Directory.EnumerateFiles(directory, "*.json")
            .OrderBy(p => p, StringComparer.Ordinal)
            .Select(Load)
            .ToList();

    public static ContractState Load(string path)
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(path));
        return Parse(doc.RootElement);
    }

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
