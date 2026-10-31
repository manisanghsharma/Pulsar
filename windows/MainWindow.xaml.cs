using System;
using System.ComponentModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace Pulsar;

public partial class MainWindow : Window
{
    readonly Model m = App.Model;
    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(100) };

    public MainWindow()
    {
        InitializeComponent();
        DataContext = m;
        var icon = new IconBitmapDecoder(new Uri("pack://application:,,,/Pulsar.ico"), BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
        Logo.Source = icon.Frames.OrderByDescending(f => f.PixelWidth).First();

        m.OwnRect = () =>
            IsVisible && WindowState != WindowState.Minimized && Native.GetWindowRect(new WindowInteropHelper(this).Handle, out var r)
                ? r : (Native.RECT?)null;
        m.ActivateWindow = () => ((App)Application.Current).ShowMain();
        timer.Tick += (_, _) => m.Tick();
        timer.Start();

        // Enter commits a number field.
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Enter && Keyboard.FocusedElement is TextBox tb)
                tb.GetBindingExpression(TextBox.TextProperty)?.UpdateSource();
        };
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        int dark = 1; // DWMWA_USE_IMMERSIVE_DARK_MODE: dark title bar to match the window
        Native.DwmSetWindowAttribute(new WindowInteropHelper(this).Handle, 20, ref dark, sizeof(int));
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        e.Cancel = true;
        Hide();
        ((App)Application.Current).HintTray();
    }

    void ToggleClicking_Click(object sender, RoutedEventArgs e) => m.ToggleClicking();
    void ToggleRecording_Click(object sender, RoutedEventArgs e) => m.ToggleRecording();
    void TogglePlaying_Click(object sender, RoutedEventArgs e) => m.TogglePlaying();
    void Pick_Click(object sender, RoutedEventArgs e) => m.Picking = !m.Picking;
    void SaveMacro_Click(object sender, RoutedEventArgs e) => m.SaveMacroToFile();
    void OpenMacro_Click(object sender, RoutedEventArgs e) => m.OpenMacroFile();
    void ClearMacro_Click(object sender, RoutedEventArgs e) => m.ClearMacro();

    void Capture_Click(object sender, RoutedEventArgs e)
    {
        var slot = (string)((Button)sender).Tag;
        m.Capturing = m.Capturing == slot ? null : slot;
    }

    void ClearSlot_Click(object sender, RoutedEventArgs e) => m.SetSlot((string)((Button)sender).Tag, null);
}
