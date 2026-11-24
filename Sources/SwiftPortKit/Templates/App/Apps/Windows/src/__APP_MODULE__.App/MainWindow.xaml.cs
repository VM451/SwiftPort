using Microsoft.UI.Xaml;

namespace __BUNDLE_ID__;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Title = "__APP_NAME__";
        // Fluent 2 chrome: content extends into the title bar area.
        ExtendsContentIntoTitleBar = true;
    }
}
