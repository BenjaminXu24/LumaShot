using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using LumaShot.Windows.Services;

namespace LumaShot.Windows;

public partial class MainWindow : Window
{
    private readonly AppController controller;
    private bool settingsReady;
    internal MainWindow(AppController controller)
    {
        this.controller = controller; InitializeComponent();
        AutoCopy.IsChecked = controller.Preferences.AutoCopy; PlaySound.IsChecked = controller.Preferences.Sound;
        CaptureDelay.SelectedIndex = controller.Preferences.Delay switch { 3 => 1, 5 => 2, _ => 0 };
        LoginLaunch.IsChecked = controller.Preferences.LaunchAtLogin; settingsReady = true;
        controller.Changed += RefreshStatus; controller.Store.Changed += RenderHistory;
        Closing += (_, e) => { if (!controller.Quitting) { e.Cancel = true; Hide(); } };
        SelectPage(0); RefreshStatus();
    }
    internal void RefreshStatus()
    {
        StatusLabel.Text = controller.Status;
        if (controller.Desktop is { Conflicts.Count: > 0 } desktop) { ConflictBanner.Visibility = Visibility.Visible; ConflictText.Text = string.Join("\n", desktop.Conflicts); }
    }
    internal void SelectPage(int page)
    {
        CapturePage.Visibility = page == 0 ? Visibility.Visible : Visibility.Collapsed;
        HistoryPage.Visibility = page == 1 ? Visibility.Visible : Visibility.Collapsed;
        SettingsPage.Visibility = page == 2 ? Visibility.Visible : Visibility.Collapsed;
        var buttons = new[] { CaptureNav, HistoryNav, SettingsNav };
        for (var i = 0; i < buttons.Length; i++) { buttons[i].Background = i == page ? new SolidColorBrush(Color.FromRgb(238, 232, 253)) : Brushes.Transparent; buttons[i].Foreground = (Brush)FindResource(i == page ? "Accent" : "Muted"); }
        if (page == 1) RenderHistory();
    }
    private void ShowCapture(object sender, RoutedEventArgs e) => SelectPage(0);
    private void ShowHistory(object sender, RoutedEventArgs e) => SelectPage(1);
    private void ShowSettings(object sender, RoutedEventArgs e) => SelectPage(2);
    private void CaptureRegion(object sender, RoutedEventArgs e) => controller.Capture(1);
    private void CaptureWindow(object sender, RoutedEventArgs e) => controller.Capture(2);
    private void CaptureDisplay(object sender, RoutedEventArgs e) => controller.Capture(3);
    private void CaptureScroll(object sender, RoutedEventArgs e) => controller.Capture(4);
    private void ImportImage(object sender, RoutedEventArgs e) => controller.Import();
    private void TryEditor(object sender, RoutedEventArgs e) => controller.OpenEditor(DemoArtwork.Create());
    private void SearchHistory(object sender, TextChangedEventArgs e) { if (IsInitialized) RenderHistory(); }
    private void RenderHistory()
    {
        if (!IsInitialized || HistoryCards is null) return;
        HistoryNav.Content = $"▱    截图历史   {controller.Store.Items.Count}";
        if (HistoryPage.Visibility != Visibility.Visible) return;
        HistoryCards.Children.Clear();
        var query = HistorySearch.Text.Trim();
        var items = controller.Store.Items.Where(i => query.Length == 0 || i.Description.Contains(query, StringComparison.OrdinalIgnoreCase) || i.Date.Contains(query) || i.Filename.Contains(query, StringComparison.OrdinalIgnoreCase)).ToList();
        EmptyHistory.Visibility = items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        foreach (var item in items)
        {
            try
            {
                var stack = new StackPanel();
                var open = new Button { Content = new Image { Source = controller.Store.Thumbnail(item), Height = 126, Stretch = Stretch.UniformToFill }, Padding = new Thickness(0), BorderThickness = new Thickness(0) };
                open.Click += (_, _) => Try(() => controller.OpenEditor(controller.Store.Load(item)));
                stack.Children.Add(open); stack.Children.Add(new TextBlock { Text = item.Mode, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 12, 0, 5) });
                stack.Children.Add(new TextBlock { Text = $"{item.Date}  ·  {item.Width:N0} × {item.Height:N0}", FontSize = 10, Foreground = (Brush)FindResource("Muted") });
                var actions = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 12, 0, 0) };
                var copy = new Button { Content = "复制", FontSize = 11, Padding = new Thickness(10, 5, 10, 5) };
                copy.Click += async (_, _) => { try { await ImageCodec.CopyAsync(ImageCodec.Bitmap(controller.Store.Load(item))); controller.Notify("已复制原始截图"); } catch (Exception ex) { MessageBox.Show(this, ex.Message, "复制失败"); } };
                var save = new Button { Content = "另存", FontSize = 11, Padding = new Thickness(10, 5, 10, 5), Margin = new Thickness(6, 0, 0, 0) }; save.Click += (_, _) => Try(() => ImageCodec.SaveDialog(this, ImageCodec.Bitmap(controller.Store.Load(item))));
                var delete = new Button { Content = "删除", FontSize = 11, Padding = new Thickness(10, 5, 10, 5), Margin = new Thickness(6, 0, 0, 0), Foreground = (Brush)FindResource("Muted") }; delete.Click += (_, _) => Try(() => controller.Store.Delete(item));
                actions.Children.Add(copy); actions.Children.Add(save); actions.Children.Add(delete); stack.Children.Add(actions);
                HistoryCards.Children.Add(new Border { Style = (Style)FindResource("Card"), Width = 235, Padding = new Thickness(14), Margin = new Thickness(0, 0, 14, 14), Child = stack });
            }
            catch (Exception ex) when (ex is System.IO.IOException or NotSupportedException) { controller.Notify("部分历史图片无法读取，可在截图文件夹中检查"); }
        }
    }
    private void Try(Action action) { try { action(); } catch (Exception ex) { MessageBox.Show(this, ex.Message, "操作未完成"); } }
    private void OpenHistoryFolder(object sender, RoutedEventArgs e) => Try(() => AppController.OpenFolder(controller.Store.DirectoryPath));
    private void ClearHistory(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show(this, "清空本机历史记录？已另存的图片不会被删除。", "清空历史", MessageBoxButton.OKCancel, MessageBoxImage.Question) == MessageBoxResult.OK) Try(controller.Store.Clear);
    }
    private void SaveSettings(object sender, RoutedEventArgs e)
    {
        if (!settingsReady) return;
        controller.Preferences.AutoCopy = AutoCopy.IsChecked == true; controller.Preferences.Sound = PlaySound.IsChecked == true; controller.SavePreferences();
    }
    private void DelayChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!settingsReady || CaptureDelay.SelectedItem is not ComboBoxItem selected) return;
        controller.Preferences.Delay = int.Parse((string)selected.Tag); controller.SavePreferences();
    }
    private void ChangeLogin(object sender, RoutedEventArgs e)
    {
        if (!settingsReady) return;
        Try(() => { Preferences.SetLogin(LoginLaunch.IsChecked == true); controller.Preferences.LaunchAtLogin = LoginLaunch.IsChecked == true; controller.SavePreferences(); });
        settingsReady = false; LoginLaunch.IsChecked = Preferences.IsLoginEnabled(); settingsReady = true;
    }
    private void OpenGitHub(object sender, RoutedEventArgs e) => Process.Start(new ProcessStartInfo("https://github.com/BenjaminXu24/LumaShot") { UseShellExecute = true });
}
