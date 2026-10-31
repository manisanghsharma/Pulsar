using System;
using System.Globalization;
using System.Windows;
using System.Windows.Data;
using Forms = System.Windows.Forms;

namespace Pulsar;

public partial class App : Application
{
    public static Model Model { get; } = new();
    Forms.NotifyIcon? tray;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var menu = new Forms.ContextMenuStrip();
        var click = menu.Items.Add("Start Clicking", null, (_, _) => Model.ToggleClicking());
        var play = menu.Items.Add("Play Macro", null, (_, _) => Model.TogglePlaying());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Show Pulsar", null, (_, _) => ShowMain());
        menu.Items.Add("Quit Pulsar", null, (_, _) => Quit());
        menu.Opening += (_, _) =>
        {
            click.Text = Model.ClickButtonText;
            play.Text = Model.PlayButtonText;
            play.Enabled = Model.Playing || Model.CanPlay;
        };
        tray = new Forms.NotifyIcon
        {
            Icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!),
            Text = "Pulsar",
            ContextMenuStrip = menu,
            Visible = true,
        };
        tray.DoubleClick += (_, _) => ShowMain();
        Model.InstallHooks();
    }

    public void ShowMain()
    {
        var w = MainWindow;
        if (w == null) return;
        w.Show();
        if (w.WindowState == WindowState.Minimized) w.WindowState = WindowState.Normal;
        w.Activate();
    }

    bool hintShown;

    /// Closing the window keeps Pulsar running in the tray so the shortcuts keep working.
    public void HintTray()
    {
        if (hintShown || tray == null) return;
        hintShown = true;
        tray.ShowBalloonTip(3000, "Pulsar is still running", "Your shortcuts still work. Right-click the tray icon to quit.", Forms.ToolTipIcon.None);
    }

    public void Quit()
    {
        Model.Shutdown();
        if (tray != null) tray.Visible = false;
        tray?.Dispose();
        Shutdown();
    }
}

/// Binds a radio button to a value: checked when the bound value equals the parameter.
/// Also yields Visibility when bound to one.
public sealed class EqualsConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        bool eq = string.Equals(System.Convert.ToString(value, CultureInfo.InvariantCulture), parameter?.ToString(), StringComparison.OrdinalIgnoreCase);
        return targetType == typeof(Visibility) ? (eq ? Visibility.Visible : Visibility.Collapsed) : eq;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is true ? System.Convert.ChangeType(parameter, targetType, CultureInfo.InvariantCulture) : Binding.DoNothing;
}

/// Shows the click interval for a clicks-per-second value.
public sealed class IntervalConverter : IValueConverter
{
    public static readonly IntervalConverter Instance = new();
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is double cps && cps > 0 ? $"{1000 / cps:0.0} ms" : "";
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => Binding.DoNothing;
}
