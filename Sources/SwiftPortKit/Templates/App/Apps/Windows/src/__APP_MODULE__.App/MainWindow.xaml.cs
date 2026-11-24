using System.Collections.ObjectModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;

namespace __BUNDLE_ID__;

public sealed partial class MainWindow : Window
{
    private readonly ObservableCollection<TaskItem> _tasks = new();
    private ContractState? _fixture;
    private TaskPhase _phase = TaskPhase.Empty;

    public MainWindow()
    {
        InitializeComponent();
        Title = "__APP_NAME__";
        // Fluent 2 chrome: content extends into the title bar area.
        ExtendsContentIntoTitleBar = true;

        ApplyEnvironment();
        TaskList.ItemsSource = _tasks;
        Render();
    }

    /// Snapshot/contract mode — same SWIFTPORT_* env contract as the Apple
    /// and Linux apps: scenario id + contracts dir render a fixture
    /// directly; theme=light|dark forces the Fluent theme.
    private void ApplyEnvironment()
    {
        var env = Environment.GetEnvironmentVariables();
        switch (env["SWIFTPORT_THEME"] as string)
        {
            case "dark": Root.RequestedTheme = ElementTheme.Dark; break;
            case "light": Root.RequestedTheme = ElementTheme.Light; break;
        }

        var scenario = env["SWIFTPORT_SCENARIO"] as string;
        var contractsDir = env["SWIFTPORT_CONTRACTS_DIR"] as string;
        if (!string.IsNullOrEmpty(scenario)
            && !string.IsNullOrEmpty(contractsDir)
            && Directory.Exists(contractsDir))
        {
            _fixture = ContractFixtures.LoadAll(contractsDir)
                .FirstOrDefault(s => s.Id == scenario);
        }

        _phase = _fixture?.Phase ?? TaskPhase.Empty;
        if (_fixture != null)
        {
            foreach (var task in _fixture.Tasks) _tasks.Add(task);
        }
    }

    private void Render()
    {
        LoadingPanel.Visibility = _phase == TaskPhase.Loading ? Visibility.Visible : Visibility.Collapsed;
        EmptyPanel.Visibility = _phase == TaskPhase.Empty ? Visibility.Visible : Visibility.Collapsed;
        ErrorPanel.Visibility = _phase == TaskPhase.Error ? Visibility.Visible : Visibility.Collapsed;
        TaskList.Visibility = _phase == TaskPhase.Loaded ? Visibility.Visible : Visibility.Collapsed;
        // Add bar is shared by the empty and loaded states — a fresh
        // install must never dead-end without a way to add a task.
        AddBar.Visibility = _phase is TaskPhase.Empty or TaskPhase.Loaded
            ? Visibility.Visible : Visibility.Collapsed;
        if (_phase == TaskPhase.Error)
        {
            ErrorText.Text = _fixture?.ErrorMessage ?? "An unknown error occurred.";
        }
    }

    private void OnAddTask(object sender, RoutedEventArgs e) => AddTask();

    private void OnNewTaskKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == VirtualKey.Enter)
        {
            AddTask();
            e.Handled = true;
        }
    }

    private void AddTask()
    {
        var title = NewTaskBox.Text.Trim();
        if (title.Length == 0) return;
        _tasks.Add(new TaskItem(
            Id: Guid.NewGuid().ToString("N"),
            Title: title, Notes: "", IsCompleted: false, Priority: "medium"));
        NewTaskBox.Text = "";
        // First add transitions empty → loaded so the row becomes visible.
        if (_phase == TaskPhase.Empty)
        {
            _phase = TaskPhase.Loaded;
            Render();
        }
    }

    private void OnDeleteTask(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: TaskItem item })
        {
            _tasks.Remove(item);
        }
    }

    private void OnRetry(object sender, RoutedEventArgs e)
    {
        // Fixtures are deterministic — retry re-renders the same state,
        // but the wiring (reload → render) is the contract being exercised.
        _tasks.Clear();
        if (_fixture != null)
        {
            foreach (var task in _fixture.Tasks) _tasks.Add(task);
        }
        Render();
    }
}
