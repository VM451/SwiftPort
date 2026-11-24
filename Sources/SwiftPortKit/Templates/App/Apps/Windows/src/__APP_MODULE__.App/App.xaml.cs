using Microsoft.UI.Xaml;

namespace __BUNDLE_ID__;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();

        // Snapshot mode: SWIFTPORT_WINDOW_BOUNDS="x,y,w,h" pins the window
        // geometry so `swiftport verify` can screen-capture a known rect.
        var bounds = Environment.GetEnvironmentVariable("SWIFTPORT_WINDOW_BOUNDS");
        if (!string.IsNullOrEmpty(bounds))
        {
            var parts = bounds.Split(',');
            if (parts.Length == 4
                && int.TryParse(parts[0], out var x)
                && int.TryParse(parts[1], out var y)
                && int.TryParse(parts[2], out var w)
                && int.TryParse(parts[3], out var h))
            {
                _window.AppWindow.MoveAndResize(
                    new Windows.Graphics.RectInt32(x, y, w, h));
            }
        }

        _window.Activate();
    }
}
