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
        try
        {
            Notify(mode == 4 ? "框选需要滚动的内容区域" : "正在准备截图…");
            hidden.Clear();
            foreach (Window window in Application.Current.Windows)
                if (window.IsVisible && window.WindowState != WindowState.Minimized && window is MainWindow or EditorWindow) hidden.Add(window);
            foreach (var window in hidden) window.Hide();
            await Task.Delay(Math.Clamp(Preferences.Delay, 0, 5) * 1000 + 200, token);
            PixelFrame? result; var label = new[] { "区域截图", "窗口截图", "全屏截图", "滚动长截图" }[mode - 1];
            if (mode == 3) result = Native.Capture(Native.PointerDisplay());
            else
            {
                var targets = Native.Windows();
                selectionTask = new(TaskCreationOptions.RunContinuationsAsynchronously);
                foreach (var display in Native.Displays())
                {
                    var window = new SelectionWindow(display, Native.Capture(display), targets, mode);
                    window.Selected += value => selectionTask?.TrySetResult(value); overlays.Add(window);
                }
                foreach (var window in overlays) window.Show();
                var selected = await selectionTask.Task; selectionTask = null;
                CloseOverlays(); token.ThrowIfCancellationRequested();
                if (selected is null) { Notify("已取消截图"); return; }
                if (selected.TargetWindow != 0) Native.SetForegroundWindow(selected.TargetWindow);
                await Task.Delay(150, token); result = Native.Capture(selected.Bounds);
                if (mode == 4)
                {
                    var completion = new TaskCompletionSource<PixelFrame?>(TaskCreationOptions.RunContinuationsAsynchronously);
                    scrolling = new(selected, result); scrolling.Finished += frame => completion.TrySetResult(frame);
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
