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
    private readonly List<SelectionWindow> pool = [];
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
            // The old +200ms pad was most of 热键等待. Keep the user's preference, and only a short settle so a hidden window is gone from the desktop.
            var preferenceMs = Math.Clamp(Preferences.Delay, 0, 5) * 1000;
            var settleMs = hidden.Count > 0 ? 32 : 0;
            if (preferenceMs + settleMs > 0) await Task.Delay(preferenceMs + settleMs, token);
            var afterSettleMs = started.ElapsedMilliseconds;
            DiagnosticsLog.Write(log, $"热键阶段 隐藏={hiddenMs}ms 偏好={preferenceMs}ms 合成等待={settleMs}ms 到此={afterSettleMs}ms 模式={mode}");
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
                var prepared = await Task.Run(() => PrepareShots(token), token);
                var captureTailMs = started.ElapsedMilliseconds - afterSettleMs;
                token.ThrowIfCancellationRequested();
                DiagnosticsLog.Write(log, $"抓屏阶段 {captureTailMs}ms");
                DiagnosticsLog.Write(log, $"枚举窗口 数量={prepared.Targets.Count} 耗时={prepared.WindowsMs}ms");
                foreach (var shot in prepared.Shots)
                    DiagnosticsLog.Write(log, $"抓屏 {shot.Display.Width}×{shot.Display.Height}@{shot.Display.X},{shot.Display.Y} 抓取={shot.GrabMs}ms 压暗={shot.DimMs}ms");
                var displays = prepared.Shots.Select(shot => shot.Display).ToArray();
                var reused = EnsurePool(displays, log);
                var bindWatch = Stopwatch.StartNew();
                for (var i = 0; i < prepared.Shots.Count; i++)
                {
                    var shot = prepared.Shots[i];
                    pool[i].Bind(shot.Display, shot.Frame, prepared.Targets, mode, shot.Dimmed, log);
                    overlays.Add(pool[i]);
                }
                var bindMs = bindWatch.ElapsedMilliseconds;
                var showWatch = Stopwatch.StartNew();
                foreach (var window in overlays) window.ShowPrepared();
                var showMs = showWatch.ElapsedMilliseconds;
                Native.GetCursorPos(out var cursor);
                var focus = overlays.FirstOrDefault(window => window.ContainsScreenPoint(cursor.X, cursor.Y)) ?? (overlays.Count > 0 ? overlays[0] : null);
                focus?.FocusForInput();
                DiagnosticsLog.Write(log, $"叠加层显示 数量={overlays.Count} 复用={(reused ? "是" : "否")} 绑定={bindMs}ms 显示={showMs}ms");
                var selected = await selectionTask.Task; selectionTask = null;
                var afterUp = Stopwatch.StartNew();
                ReleaseOverlays(); token.ThrowIfCancellationRequested();
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
            ReleaseOverlays(); scrolling?.Dispose(); scrolling = null; Restore();
            Desktop?.EnableEscape(false); operation?.Dispose(); operation = null; Busy = false; Changed?.Invoke();
        }
    }
    internal void WarmOverlays()
    {
        var log = DiagnosticsLog.DailyPath(Root);
        var watch = Stopwatch.StartNew();
        var displays = Native.Displays();
        var reused = EnsurePool(displays, log);
        DiagnosticsLog.Write(log, $"叠加层预热 数量={pool.Count} 耗时={watch.ElapsedMilliseconds}ms 新建={(reused ? "否" : "是")}");
    }
    private bool EnsurePool(IReadOnlyList<PixelRect> displays, string log)
    {
        var matched = pool.Count == displays.Count;
        for (var i = 0; matched && i < displays.Count; i++)
            matched = pool[i].IsUsable && pool[i].BoundDisplay == displays[i];
        if (matched) return true;
        foreach (var window in pool) if (window.IsUsable) window.Close();
        pool.Clear();
        foreach (var display in displays)
        {
            var window = SelectionWindow.CreateShell(display, log);
            window.Selected += value => selectionTask?.TrySetResult(value);
            pool.Add(window);
        }
        return false;
    }
    private (List<DesktopWindow> Targets, List<(PixelRect Display, PixelFrame Frame, PixelFrame Dimmed, long GrabMs, long DimMs)> Shots, long WindowsMs) PrepareShots(CancellationToken token)
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
        return (found, shots, windowsMs);
    }
    private void ReleaseOverlays()
    {
        foreach (var window in overlays)
        {
            if (pool.Contains(window) && window.IsUsable) window.Park();
            else if (window.IsUsable) window.Close();
        }
        overlays.Clear();
    }
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
        Quitting = true; Cancel(); foreach (var window in pool.ToList()) if (window.IsUsable) window.Close(); pool.Clear(); Desktop?.Dispose(); Main.Close(); Application.Current.Shutdown();
    }
}
