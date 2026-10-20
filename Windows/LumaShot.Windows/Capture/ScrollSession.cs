using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using LumaShot.Core;
using LumaShot.Windows.Platform;

namespace LumaShot.Windows.Capture;

internal sealed class ScrollSession : IDisposable
{
    private readonly Selection selection;
    private readonly ImageStitcher stitcher;
    private readonly string? diagnosticLog;
    private readonly ScrollControls controls;
    private readonly SemaphoreSlim frameLock = new(1, 1);
    private CancellationTokenSource? automatic;
    private bool ended;
    private readonly Native.Point originalCursor;
    public bool IsAutomatic => automatic is not null;
    public int FrameCount => stitcher.FrameCount;
    public int TotalHeight => stitcher.TotalHeight;
    public string Status => controls.Status.Text;
    public event Action<PixelFrame?>? Finished;

    public ScrollSession(Selection selection, PixelFrame first, string? diagnosticLog = null)
    {
        this.selection = selection; this.diagnosticLog = diagnosticLog; stitcher = new(first); Native.GetCursorPos(out originalCursor);
        controls = new ScrollControls();
        controls.Add.Click += async (_, _) => await AddFrame(false);
        controls.Automatic.Click += (_, _) => { if (IsAutomatic) Pause("已暂停，可手动向下滚动约半屏，再添加当前屏"); else StartAutomatic(); };
        controls.Finish.Click += (_, _) => Finish(); controls.Cancel.Click += (_, _) => Cancel();
        controls.SourceInitialized += (_, _) =>
        {
            var monitor = Native.Displays().FirstOrDefault(r => r.Contains(selection.Bounds.X, selection.Bounds.Y), Native.PointerDisplay());
            var dpi = VisualTreeHelper.GetDpi(controls); var width = (int)(controls.Width * dpi.DpiScaleX); var height = (int)(controls.Height * dpi.DpiScaleY);
            var x = Math.Clamp(selection.Bounds.X, monitor.X + 8, Math.Max(monitor.X + 8, monitor.Right - width - 8));
            var y = selection.Bounds.Bottom + height + 12 < monitor.Bottom ? selection.Bounds.Bottom + 8 : selection.Bounds.Y - height - 8;
            y = Math.Clamp(y, monitor.Y + 8, Math.Max(monitor.Y + 8, monitor.Bottom - height - 8));
            Native.SetWindowPos(new WindowInteropHelper(controls).Handle, -1, x, y, width, height, 0x10);
        };
        UpdateCounts(); controls.Show();
    }
    private void UpdateCounts() => controls.Counts.Text = $"{stitcher.FrameCount} 屏 · {stitcher.TotalHeight:N0} px";
    public void StartAutomatic()
    {
        if (ended || automatic is not null) return;
        automatic = new(); controls.Automatic.Content = "Ⅱ  暂停滚动";
        controls.Status.Text = "正在自动向下滚动，到底后自动暂停";
        if (selection.TargetWindow != 0) Native.SetForegroundWindow(selection.TargetWindow);
        _ = RunAutomatic(automatic.Token);
    }
    private async Task RunAutomatic(CancellationToken token)
    {
        var unchanged = 0;
        try
        {
            await Task.Delay(400, token);
            while (!ended && !token.IsCancellationRequested)
            {
                var rect = selection.Bounds;
                if (!Native.ScrollAt(rect.X + rect.Width / 2, rect.Y + rect.Height / 2, -Math.Clamp(rect.Height / 300, 1, 3)))
                { Pause("系统阻止了滚动输入。请手动滚动后添加当前屏"); return; }
                await Task.Delay(650, token);
                var result = await AddFrame(true);
                if (token.IsCancellationRequested || ended) return;
                unchanged = result == AppendStatus.Unchanged ? unchanged + 1 : 0;
                if (unchanged >= 2)
                {
                    Pause(stitcher.FrameCount > 1 ? "页面已停止滚动，点击「完成」进入标注" : "画面没有滚动，请确认选中了滚动内容；也可手动滚动后添加"); return;
                }
                await Task.Delay(180, token);
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { if (!ended) Pause($"滚动已暂停：{ex.Message}"); }
    }
    public async Task<AppendStatus?> AddFrame(bool fromAutomatic = false)
    {
        if (ended || (!fromAutomatic && IsAutomatic) || !await frameLock.WaitAsync(0)) return null;
        controls.Add.IsEnabled = false; controls.Finish.IsEnabled = false;
        try
        {
            // GDI capture does not reliably honor WDA_EXCLUDEFROMCAPTURE. Hide
            // our small control panel while capturing, including full-screen crops.
            controls.Hide(); await Task.Delay(80);
            if (ended) return null;
            var grab = Stopwatch.StartNew();
            var frame = Native.Capture(selection.Bounds);
            DiagnosticsLog.Write(diagnosticLog, $"滚动抓取 {frame.Width}×{frame.Height} {grab.ElapsedMilliseconds}ms 方式=整屏后裁剪");
            var result = await Task.Run(() => stitcher.Append(frame));
            if (ended) return null;
            UpdateCounts();
            switch (result.Status)
            {
                case AppendStatus.Appended: controls.Status.Text = fromAutomatic ? "已拼接，正在继续向下滚动…" : "已添加，可继续滚动或完成"; break;
                case AppendStatus.Unchanged: controls.Status.Text = fromAutomatic ? "正在确认页面是否到底…" : "画面未变化，请向下滚动约半屏再添加"; break;
                case AppendStatus.NoOverlap: Pause("未找到重叠区域，请向上回滚一点，再添加当前屏"); break;
                case AppendStatus.HeightLimit: Pause($"已达到 {stitcher.MaximumHeight:N0} px 上限，请完成当前长图"); break;
            }
            return result.Status;
        }
        catch (Exception ex) { if (!ended) Pause($"本次捕获失败，已拼接内容保留：{ex.Message}"); return null; }
        finally
        {
            if (!ended) { controls.Show(); controls.Add.IsEnabled = !IsAutomatic; controls.Finish.IsEnabled = true; }
            frameLock.Release();
        }
    }
    public void Pause(string message)
    {
        automatic?.Cancel(); automatic?.Dispose(); automatic = null;
        controls.Automatic.Content = "↓  自动滚动"; controls.Add.IsEnabled = true; controls.Status.Text = message;
    }
    public void Finish()
    {
        if (ended || frameLock.CurrentCount == 0) return;
        try { var image = stitcher.MakeImage(); End(); Finished?.Invoke(image); }
        catch (OutOfMemoryException) { Pause("内存不足，请取消并缩小截图区域后重试"); }
    }
    public void Cancel() { if (ended) return; End(); Finished?.Invoke(null); }
    private void End()
    {
        ended = true; automatic?.Cancel(); automatic?.Dispose(); automatic = null;
        controls.Close(); Native.SetCursorPos(originalCursor.X, originalCursor.Y);
    }
    public void Dispose() { if (!ended) End(); }

    private sealed class ScrollControls : Window
    {
        public TextBlock Counts { get; } = new() { Foreground = new SolidColorBrush(Color.FromRgb(183, 178, 210)), Margin = new Thickness(12, 0, 0, 0) };
        public TextBlock Status { get; } = new() { Foreground = Brushes.White, Margin = new Thickness(0, 15, 0, 15), TextWrapping = TextWrapping.Wrap, Text = "可自动滚动，或手动滚动约半屏后添加当前屏" };
        public Button Automatic { get; } = new() { Content = "↓  自动滚动", Padding = new Thickness(12, 7, 12, 7) };
        public Button Add { get; } = new() { Content = "+  添加当前屏", Padding = new Thickness(12, 7, 12, 7), Margin = new Thickness(8, 0, 0, 0) };
        public Button Finish { get; } = new() { Content = "✓  完成", Padding = new Thickness(16, 7, 16, 7), Margin = new Thickness(8, 0, 0, 0) };
        public Button Cancel { get; } = new() { Content = "×", Padding = new Thickness(5, 0, 5, 0), Background = Brushes.Transparent, Foreground = Brushes.White, BorderThickness = new Thickness(0) };
        public ScrollControls()
        {
            Width = 490; Height = 165; WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
            Topmost = true; ShowInTaskbar = false; ShowActivated = false; AllowsTransparency = true; Background = Brushes.Transparent;
            var root = new StackPanel();
            var title = new DockPanel(); DockPanel.SetDock(Cancel, Dock.Right); title.Children.Add(Cancel);
            var heading = new StackPanel { Orientation = Orientation.Horizontal };
            heading.Children.Add(new TextBlock { Text = "▣  滚动截图", Foreground = Brushes.White, FontWeight = FontWeights.SemiBold }); heading.Children.Add(Counts); title.Children.Add(heading);
            root.Children.Add(title); root.Children.Add(Status);
            var actions = new StackPanel { Orientation = Orientation.Horizontal }; actions.Children.Add(Automatic); actions.Children.Add(Add); actions.Children.Add(Finish); root.Children.Add(actions);
            Content = new Border { Background = new SolidColorBrush(Color.FromRgb(33, 32, 46)), CornerRadius = new CornerRadius(15), Padding = new Thickness(19), Child = root };
            PreviewKeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Escape) Cancel.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); };
        }
    }
}
