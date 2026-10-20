using System.Diagnostics;
using System.IO;
using System.Windows;
using LumaShot.Core;
using LumaShot.Windows.Capture;
using LumaShot.Windows.Editor;
using LumaShot.Windows.Platform;
using Microsoft.Win32;

namespace LumaShot.Windows.Services;

internal sealed class AppController
{
    public string Root { get; }
    public Preferences Preferences { get; }
    public CaptureStore Store { get; }
    public MainWindow Main { get; set; } = null!;
    public DesktopIntegration? Desktop { get; set; }
    public bool Busy { get; private set; }
    public bool Quitting { get; private set; }
    internal bool InteractiveErrors { get; init; } = true;
    public string Status { get; private set; } = "准备好捕捉灵感";
    public event Action? Changed;
    private readonly List<EditorWindow> editors = [];
    private readonly List<SelectionWindow> overlays = [];
    private readonly List<Window> hidden = [];
    private CancellationTokenSource? operation;
    private TaskCompletionSource<Selection?>? selectionTask;
    private ScrollSession? scrolling;
    public AppController(string root)
    {
        Root = root; Directory.CreateDirectory(root); Preferences = global::LumaShot.Windows.Services.Preferences.Load(root); Store = new(root);
        Preferences.LaunchAtLogin = global::LumaShot.Windows.Services.Preferences.IsLoginEnabled();
    }
    public void Notify(string message) { Status = message; Changed?.Invoke(); }
    public void ShowMain() { Main.Show(); if (Main.WindowState == WindowState.Minimized) Main.WindowState = WindowState.Normal; Main.Activate(); }
    public async void Capture(int mode)
    {
        if (Busy || Quitting) return;
        Busy = true; operation = new(); var token = operation.Token;
        Desktop?.EnableEscape(true); if (Desktop is not null) Desktop.Cancel = Cancel;
        var log = DiagnosticsLog.DailyPath(Root);
        var started = Stopwatch.StartNew();
        try
        {
            Notify(mode == 4 ? "框选需要滚动的内容区域" : "正在准备截图…");
            hidden.Clear();
            foreach (Window window in Application.Current.Windows)
                if (window.IsVisible && window.WindowState != WindowState.Minimized && window is MainWindow or EditorWindow) hidden.Add(window);
            foreach (var window in hidden) window.Hide();
            var hiddenMs = started.ElapsedMilliseconds;
            await Task.Delay(Math.Clamp(Preferences.Delay, 0, 5) * 1000 + 200, token);
            DiagnosticsLog.Write(log, $"热键等待 {started.ElapsedMilliseconds}ms（隐藏窗口 {hiddenMs}ms）模式={mode}");
            PixelFrame? result; var label = new[] { "区域截图", "窗口截图", "全屏截图", "滚动长截图" }[mode - 1];
            if (mode == 3)
            {
                var screen = Native.PointerDisplay();
                var grab = Stopwatch.StartNew();
                result = Native.Capture(screen);
                DiagnosticsLog.Write(log, $"全屏抓取 {screen.Width}×{screen.Height}@{screen.X},{screen.Y} {grab.ElapsedMilliseconds}ms");
            }
            else
            {
                selectionTask = new(TaskCreationOptions.RunContinuationsAsynchronously);
                // BitBlt plus the dim copy touch every screen pixel. Keep that off the UI thread so the cursor still moves before the overlay opens.
                var prepared = await Task.Run(() =>
                {
                    var windowWatch = Stopwatch.StartNew();
                    var found = Native.Windows();
                    var windowsMs = windowWatch.ElapsedMilliseconds;
                    var shots = new List<(PixelRect Display, PixelFrame Frame, PixelFrame Dimmed, long GrabMs, long DimMs)>();
                    foreach (var screen in Native.Displays())
                    {
                        token.ThrowIfCancellationRequested();
                        var grabWatch = Stopwatch.StartNew();
                        var frame = Native.Capture(screen);
                        var grabMs = grabWatch.ElapsedMilliseconds;
                        var dimWatch = Stopwatch.StartNew();
                        shots.Add((screen, frame, frame.Dimmed(SelectionGeometry.OverlayAlpha), grabMs, dimWatch.ElapsedMilliseconds));
                    }
                    return (Targets: found, Shots: shots, WindowsMs: windowsMs);
                }, token);
                token.ThrowIfCancellationRequested();
                DiagnosticsLog.Write(log, $"枚举窗口 数量={prepared.Targets.Count} 耗时={prepared.WindowsMs}ms");
                foreach (var shot in prepared.Shots)
                    DiagnosticsLog.Write(log, $"抓屏 {shot.Display.Width}×{shot.Display.Height}@{shot.Display.X},{shot.Display.Y} 抓取={shot.GrabMs}ms 压暗={shot.DimMs}ms");
                foreach (var shot in prepared.Shots)
                {
                    var window = new SelectionWindow(shot.Display, shot.Frame, prepared.Targets, mode, shot.Dimmed, log);
                    window.Selected += value => selectionTask?.TrySetResult(value); overlays.Add(window);
                }
                var showWatch = Stopwatch.StartNew();
                foreach (var window in overlays) window.Show();
                var showMs = showWatch.ElapsedMilliseconds;
                Native.GetCursorPos(out var cursor);
                var focus = overlays.FirstOrDefault(window => window.ContainsScreenPoint(cursor.X, cursor.Y)) ?? (overlays.Count > 0 ? overlays[0] : null);
                focus?.FocusForInput();
                DiagnosticsLog.Write(log, $"叠加层显示 数量={overlays.Count} 耗时={showMs}ms");
                var selected = await selectionTask.Task; selectionTask = null;
                var afterUp = Stopwatch.StartNew();
                CloseOverlays(); token.ThrowIfCancellationRequested();
                if (selected is null) { DiagnosticsLog.Write(log, $"选区返回 取消 {afterUp.ElapsedMilliseconds}ms"); Notify("已取消截图"); return; }
                var cropWatch = Stopwatch.StartNew();
                var monitors = prepared.Shots.Select(shot => new MonitorBitmap(shot.Display.X, shot.Display.Y, shot.Display.Width, shot.Display.Height, shot.Frame)).ToArray();
                result = ScreenCrop.FromMonitors(monitors, selected.Bounds.X, selected.Bounds.Y, selected.Bounds.Width, selected.Bounds.Height);
                DiagnosticsLog.Write(log, $"选区返回 裁剪={result.Width}×{result.Height} 来源=已抓屏 无二次BitBlt 裁剪={cropWatch.ElapsedMilliseconds}ms 抬起至结果={afterUp.ElapsedMilliseconds}ms");
                if (mode == 4)
                {
                    var completion = new TaskCompletionSource<PixelFrame?>(TaskCreationOptions.RunContinuationsAsynchronously);
                    scrolling = new(selected, result, log); scrolling.Finished += frame => completion.TrySetResult(frame);
                    scrolling.StartAutomatic(); result = await completion.Task;
                    scrolling.Dispose(); scrolling = null; token.ThrowIfCancellationRequested();
                }
            }
            Restore();
            if (result is not null)
            {
                try { Store.Add(result, label); } catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { Notify($"截图已打开，历史保存失败：{ex.Message}"); }
                OpenEditor(result);
                if (Preferences.Sound) System.Media.SystemSounds.Asterisk.Play();
                if (Preferences.AutoCopy) try { await ImageCodec.CopyAsync(ImageCodec.Bitmap(result)); } catch (Exception) { Notify("截图完成，自动复制失败，可在编辑器中重试"); return; }
                Notify($"截图完成 · {result.Width:N0} × {result.Height:N0}");
            }
            else Notify("已取消滚动截图");
        }
        catch (OperationCanceledException) { Notify("已取消截图"); }
        catch (Exception ex) { ShowMain(); Notify($"截图未完成：{ex.Message}"); if (InteractiveErrors) MessageBox.Show(Main, ex.Message, "截图未完成", MessageBoxButton.OK, MessageBoxImage.Information); }
        finally
        {
            CloseOverlays(); scrolling?.Dispose(); scrolling = null; Restore();
            Desktop?.EnableEscape(false); operation?.Dispose(); operation = null; Busy = false; Changed?.Invoke();
        }
    }
    private void CloseOverlays() { foreach (var window in overlays) window.Close(); overlays.Clear(); }
    private void Restore() { foreach (var window in hidden) if (Application.Current.Windows.Cast<Window>().Contains(window)) window.Show(); hidden.Clear(); }
    public void Cancel() { operation?.Cancel(); selectionTask?.TrySetResult(null); scrolling?.Cancel(); }
    public void OpenEditor(PixelFrame image)
    {
        var editor = new EditorWindow(image); editors.Add(editor); editor.Closed += (_, _) => editors.Remove(editor); editor.Show(); editor.Activate();
    }
    public void Import()
    {
        var dialog = new OpenFileDialog { Title = "打开图片并标注", Filter = "图片|*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff;*.gif|所有文件|*.*" };
        if (dialog.ShowDialog(Main) != true) return;
        try { OpenEditor(ImageCodec.Load(dialog.FileName)); } catch (Exception ex) { MessageBox.Show(Main, ex.Message, "图片打开失败"); }
    }
    public void SavePreferences() { try { Preferences.Save(Root); } catch (Exception ex) { MessageBox.Show(Main, ex.Message, "设置保存失败"); } }
    public static void OpenFolder(string path) => Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
    public void Quit()
    {
        foreach (var editor in editors.ToList()) { editor.Close(); if (editors.Contains(editor)) return; }
        Quitting = true; Cancel(); Desktop?.Dispose(); Main.Close(); Application.Current.Shutdown();
    }
}
