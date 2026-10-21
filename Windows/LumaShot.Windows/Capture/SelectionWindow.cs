using System.Diagnostics;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
using LumaShot.Core;
using LumaShot.Windows.Platform;
using LumaShot.Windows.Services;

namespace LumaShot.Windows.Capture;

internal sealed record Selection(PixelRect Bounds, nint TargetWindow);

internal sealed class SelectionWindow : Window
{
    private static readonly SolidColorBrush SelectionBorderBrush = Freeze(Color.FromRgb(180, 163, 255));
    private static readonly SolidColorBrush PillBrush = Freeze(Color.FromArgb(235, 29, 31, 44));
    private static SelectionWindow? dragOwner;
    private static SolidColorBrush Freeze(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    private PixelRect display;
    private IReadOnlyList<DesktopWindow> targets = [];
    private int mode;
    private int pixelWidth;
    private int pixelHeight;
    private string? diagnosticLog;
    private readonly Grid root;
    private readonly BackdropImage backdropImage;
    private readonly BackdropImage previewImage;
    private readonly RectangleGeometry holeGeometry = new();
    private readonly Canvas chrome;
    private readonly Rectangle[] edges;
    private readonly Ellipse[] handles;
    private readonly Border sizePill;
    private readonly TextBlock sizeText;
    private readonly TextBlock hintText;
    private readonly Border hint;
    private readonly SampleBuffer handlerSamples = new();
    private readonly SampleBuffer renderSamples = new();
    private readonly SampleBuffer presentGaps = new();
    private readonly SampleBuffer presentLatency = new();
    private readonly Stopwatch shown = new();
    private Point? start;
    private DesktopWindow? target;
    private Rect region = Rect.Empty;
    private Rect painted = Rect.Empty;
    private bool paintedValid;
    private bool closed;
    private bool loggedFrame;
    private bool loggedSummary;
    private bool trackingFrames;
    private EventHandler? firstPresent;
    private double dpiScale = 1;
    private string sizeLabel = "";
    private int moveCount;
    private int ignoredMoves;
    private int presentCount;
    private long firstFrameMs = -1;
    private long lastPresent;
    private long awaitingSince;
    public event Action<Selection?>? Selected;
    internal bool IsUsable => !closed;
    internal PixelRect BoundDisplay => display;

    private SelectionWindow(string? diagnosticLog)
    {
        this.diagnosticLog = diagnosticLog;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        ShowActivated = false;
        AllowsTransparency = false;
        Topmost = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Background = Brushes.Black;
        Cursor = Cursors.Cross;
        ForceCursor = true;
        root = new Grid { Background = Brushes.Black };
        backdropImage = new BackdropImage { Stretch = Stretch.Fill, IsHitTestVisible = false, SnapsToDevicePixels = true };
        previewImage = new BackdropImage { Stretch = Stretch.Fill, IsHitTestVisible = false, SnapsToDevicePixels = true, Visibility = Visibility.Collapsed, Clip = holeGeometry };
        RenderOptions.SetBitmapScalingMode(backdropImage, BitmapScalingMode.LowQuality);
        RenderOptions.SetBitmapScalingMode(previewImage, BitmapScalingMode.LowQuality);
        edges = [Edge(), Edge(), Edge(), Edge()];
        handles = [Handle(), Handle(), Handle(), Handle()];
        sizeText = new TextBlock { Foreground = Brushes.White, FontSize = 13, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        sizePill = Pill(sizeText, 140);
        sizePill.Visibility = Visibility.Collapsed;
        hintText = new TextBlock { Foreground = Brushes.White, FontSize = 13, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        hint = Pill(hintText, 440);
        chrome = new Canvas { IsHitTestVisible = false };
        foreach (var edge in edges) chrome.Children.Add(edge);
        foreach (var handle in handles) chrome.Children.Add(handle);
        chrome.Children.Add(sizePill);
        chrome.Children.Add(hint);
        root.Children.Add(backdropImage);
        root.Children.Add(previewImage);
        root.Children.Add(chrome);
        Content = root;

        SourceInitialized += (_, _) => PlaceOnDisplay();
        Loaded += (_, _) =>
        {
            CacheDpi();
            PositionHint();
            var loadedPeers = 0;
            foreach (Window window in Application.Current.Windows)
                if (window is SelectionWindow { IsLoaded: true }) loadedPeers++;
            if (loadedPeers <= 1) FocusForInput();
        };
        DpiChanged += (_, _) => CacheDpi();
        SizeChanged += (_, _) =>
        {
            PositionHint();
            if (paintedValid) ApplyChrome(region);
        };
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) { ReleaseOwner(); Selected?.Invoke(null); e.Handled = true; } };
        MouseRightButtonDown += (_, e) => { ReleaseOwner(); Selected?.Invoke(null); e.Handled = true; };
        MouseLeftButtonDown += OnDown;
        MouseMove += OnMove;
        MouseLeftButtonUp += OnUp;
        Closed += (_, _) =>
        {
            closed = true;
            DetachFirstPresent();
            EndFrameTracking();
            ReleaseOwner();
            LogSummary("关闭");
        };
    }

    internal SelectionWindow(PixelRect display, PixelFrame snapshot, IReadOnlyList<DesktopWindow> targets, int mode, PixelFrame? dimmed = null, string? diagnosticLog = null)
        : this(diagnosticLog)
    {
        Bind(display, snapshot, targets, mode, dimmed, diagnosticLog);
    }

    internal static SelectionWindow CreateShell(PixelRect display, string? diagnosticLog)
    {
        var window = new SelectionWindow(diagnosticLog) { display = display };
        window.EnsureHwnd();
        return window;
    }

    internal void Bind(PixelRect display, PixelFrame snapshot, IReadOnlyList<DesktopWindow> targets, int mode, PixelFrame? dimmed, string? diagnosticLog)
    {
        this.display = display;
        this.targets = targets;
        this.mode = mode;
        this.diagnosticLog = diagnosticLog;
        pixelWidth = snapshot.Width;
        pixelHeight = snapshot.Height;
        if (dimmed is null || dimmed.Width != snapshot.Width || dimmed.Height != snapshot.Height)
            dimmed = snapshot.Dimmed(SelectionGeometry.OverlayAlpha);
        backdropImage.Source = ImageCodec.Bitmap(dimmed);
        previewImage.Source = ImageCodec.Bitmap(snapshot);
        hintText.Text = mode == 2 ? "点击选择窗口  ·  Esc / 右键取消" : mode == 4 ? "框选滚动内容，避开固定侧栏  ·  Esc / 右键取消" : "拖动选择区域  ·  Esc / 右键取消";
        closed = false;
        loggedFrame = false;
        loggedSummary = false;
        start = null;
        target = null;
        region = Rect.Empty;
        painted = Rect.Empty;
        paintedValid = false;
        sizeLabel = "";
        moveCount = 0;
        ignoredMoves = 0;
        presentCount = 0;
        lastPresent = 0;
        awaitingSince = 0;
        firstFrameMs = -1;
        handlerSamples.Clear();
        renderSamples.Clear();
        presentGaps.Clear();
        presentLatency.Clear();
        ApplyChrome(Rect.Empty);
        PlaceOnDisplay();
        shown.Restart();
    }

    internal void ShowPrepared()
    {
        shown.Restart();
        loggedFrame = false;
        firstFrameMs = -1;
        DetachFirstPresent();
        firstPresent = (_, _) =>
        {
            DetachFirstPresent();
            LogFirstFrame();
        };
        CompositionTarget.Rendering += firstPresent;
        Show();
        PlaceOnDisplay();
    }

    /// <summary>Hide a warmed window without destroying its HWND.</summary>
    internal void Park()
    {
        DetachFirstPresent();
        EndFrameTracking();
        ReleaseOwner();
        start = null;
        target = null;
        region = Rect.Empty;
        ApplyChrome(Rect.Empty);
        backdropImage.Source = null;
        previewImage.Source = null;
        LogSummary("收起");
        Hide();
    }

    internal bool ContainsScreenPoint(int x, int y) => display.Contains(x, y);

    internal void FocusForInput()
    {
        if (closed) return;
        Activate();
        Focus();
    }

    private void EnsureHwnd() => _ = new WindowInteropHelper(this).EnsureHandle();

    private void PlaceOnDisplay()
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        if (hwnd == 0 || display.Width <= 0 || display.Height <= 0) return;
        Native.SetWindowPos(hwnd, -1, display.X, display.Y, display.Width, display.Height, 0x0010);
    }

    private static Rectangle Edge() => new()
    {
        Fill = SelectionBorderBrush,
        IsHitTestVisible = false,
        SnapsToDevicePixels = true,
        Visibility = Visibility.Collapsed
    };

    private static Ellipse Handle() => new()
    {
        Width = 6,
        Height = 6,
        Fill = Brushes.White,
        IsHitTestVisible = false,
        SnapsToDevicePixels = true,
        Visibility = Visibility.Collapsed
    };

    private static Border Pill(TextBlock text, double width) => new()
    {
        Width = width,
        Height = 35,
        CornerRadius = new CornerRadius(12),
        Background = PillBrush,
        Child = text,
        IsHitTestVisible = false,
        SnapsToDevicePixels = true
    };

    private void OnDown(object sender, MouseButtonEventArgs e)
    {
        if (mode == 2)
        {
            UpdateTarget();
            ApplyChrome(region);
            return;
        }
        dragOwner = this;
        start = e.GetPosition(root);
        region = Rect.Empty;
        ApplyChrome(region);
        BeginFrameTracking();
        CaptureMouse();
    }

    private void OnMove(object sender, MouseEventArgs e)
    {
        if (dragOwner is not null && dragOwner != this)
        {
            ignoredMoves++;
            return;
        }
        if (mode != 2 && (start is null || e.LeftButton != MouseButtonState.Pressed)) return;
        var started = Stopwatch.GetTimestamp();
        try
        {
            if (mode == 2)
            {
                if (UpdateTarget()) SchedulePaint();
                return;
            }
            var origin = start!.Value;
            var point = e.GetPosition(root);
            var drag = SelectionGeometry.FromDrag(origin.X, origin.Y, point.X, point.Y, root.ActualWidth, root.ActualHeight);
            var next = new Rect(drag.X, drag.Y, drag.Width, drag.Height);
            if (next == region) return;
            region = next;
            SchedulePaint();
        }
        finally
        {
            moveCount++;
            handlerSamples.Add(Stopwatch.GetElapsedTime(started).TotalMilliseconds);
        }
    }

    private void OnUp(object sender, MouseButtonEventArgs e)
    {
        ReleaseMouseCapture();
        ReleaseOwner();
        EndFrameTracking();
        LogSummary("鼠标抬起");
        if (mode == 2)
        {
            if (target is { } window) Selected?.Invoke(new(window.Bounds, window.Handle));
            return;
        }
        if (region.IsEmpty || SelectionGeometry.IsTooSmall(region.Width, region.Height)) { start = null; return; }
        var first = root.PointToScreen(region.TopLeft);
        var last = root.PointToScreen(region.BottomRight);
        var pixels = SelectionGeometry.ToCapturePixels(first.X, first.Y, last.X, last.Y);
        if (mode == 4 && SelectionGeometry.IsScrollTooSmall(pixels.Width, pixels.Height)) return;
        var bounds = new PixelRect(pixels.X, pixels.Y, pixels.Width, pixels.Height);
        var candidate = targets.FirstOrDefault(w => w.Bounds.Contains(bounds.X + bounds.Width / 2, bounds.Y + bounds.Height / 2));
        Selected?.Invoke(new(bounds, candidate.Handle));
    }

    private void ReleaseOwner()
    {
        if (dragOwner == this) dragOwner = null;
    }

    private bool UpdateTarget()
    {
        Native.GetCursorPos(out var mouse);
        var next = targets.FirstOrDefault(w => w.Bounds.Contains(mouse.X, mouse.Y));
        if (next.Handle == 0)
        {
            var changed = target is not null || !region.IsEmpty;
            target = null;
            region = Rect.Empty;
            return changed;
        }
        if (target?.Handle == next.Handle) return false;
        target = next;
        var top = root.PointFromScreen(new Point(next.Bounds.X, next.Bounds.Y));
        var bottom = root.PointFromScreen(new Point(next.Bounds.Right, next.Bounds.Bottom));
        region = new Rect(top, bottom);
        return true;
    }

    /// <summary>
    /// Mouse moves only store the latest rectangle. <see cref="CompositionTarget.Rendering"/> applies it once per presented frame,
    /// so a 300+ Hz pointer does not each schedule its own full-window present.
    /// </summary>
    private void SchedulePaint()
    {
        if (closed) return;
        if (awaitingSince == 0) awaitingSince = Stopwatch.GetTimestamp();
        BeginFrameTracking();
    }

    private void BeginFrameTracking()
    {
        if (trackingFrames || closed) return;
        trackingFrames = true;
        lastPresent = 0;
        CompositionTarget.Rendering += OnPresent;
    }

    private void DetachFirstPresent()
    {
        if (firstPresent is null) return;
        CompositionTarget.Rendering -= firstPresent;
        firstPresent = null;
    }

    private void EndFrameTracking()
    {
        if (!trackingFrames) return;
        trackingFrames = false;
        CompositionTarget.Rendering -= OnPresent;
    }

    private void OnPresent(object? sender, EventArgs e)
    {
        if (closed) { EndFrameTracking(); return; }
        var now = Stopwatch.GetTimestamp();
        if (lastPresent != 0)
            presentGaps.Add(Stopwatch.GetElapsedTime(lastPresent, now).TotalMilliseconds);
        lastPresent = now;
        presentCount++;
        if (awaitingSince != 0)
        {
            presentLatency.Add(Stopwatch.GetElapsedTime(awaitingSince, now).TotalMilliseconds);
            awaitingSince = 0;
        }
        if (region != painted || !paintedValid)
        {
            var started = Stopwatch.GetTimestamp();
            ApplyChrome(region);
            renderSamples.Add(Stopwatch.GetElapsedTime(started).TotalMilliseconds);
        }
    }

    /// <summary>
    /// The dimmed screenshot and the un-dimmed screenshot are both full-window images created before the drag.
    /// A move only changes the un-dimmed image's clip rectangle, plus the 2px border and the size label.
    /// </summary>
    private void ApplyChrome(Rect next)
    {
        painted = next;
        paintedValid = true;
        if (next.IsEmpty || next.Width <= 0 || next.Height <= 0)
        {
            holeGeometry.Rect = Rect.Empty;
            previewImage.Visibility = Visibility.Collapsed;
            foreach (var edge in edges) edge.Visibility = Visibility.Collapsed;
            sizePill.Visibility = Visibility.Collapsed;
            foreach (var handle in handles) handle.Visibility = Visibility.Collapsed;
            return;
        }
        var visible = SelectionGeometry.Visible(new(next.X, next.Y, next.Width, next.Height), root.ActualWidth, root.ActualHeight);
        if (visible.IsEmpty)
        {
            holeGeometry.Rect = Rect.Empty;
            previewImage.Visibility = Visibility.Collapsed;
        }
        else
        {
            holeGeometry.Rect = new Rect(visible.X, visible.Y, visible.Width, visible.Height);
            previewImage.Visibility = Visibility.Visible;
        }
        var parts = SelectionGeometry.Edges(new(next.X, next.Y, next.Width, next.Height));
        for (var i = 0; i < edges.Length; i++)
        {
            if (i >= parts.Length || parts[i].IsEmpty)
            {
                edges[i].Visibility = Visibility.Collapsed;
                continue;
            }
            Canvas.SetLeft(edges[i], parts[i].X);
            Canvas.SetTop(edges[i], parts[i].Y);
            edges[i].Width = parts[i].Width;
            edges[i].Height = parts[i].Height;
            edges[i].Visibility = Visibility.Visible;
        }
        PlaceHandle(handles[0], next.Left, next.Top);
        PlaceHandle(handles[1], next.Right, next.Top);
        PlaceHandle(handles[2], next.Left, next.Bottom);
        PlaceHandle(handles[3], next.Right, next.Bottom);
        var measured = SelectionGeometry.MeasuredPixels(next.Width, next.Height, dpiScale);
        var label = $"{measured.Width.ToString("0", CultureInfo.InvariantCulture)} × {measured.Height.ToString("0", CultureInfo.InvariantCulture)}";
        if (!string.Equals(label, sizeLabel, StringComparison.Ordinal))
        {
            sizeLabel = label;
            sizeText.Text = label;
        }
        var left = Math.Clamp(next.Left, 10, Math.Max(10, root.ActualWidth - 150));
        var top = Math.Max(70, next.Top - 42);
        Canvas.SetLeft(sizePill, left);
        Canvas.SetTop(sizePill, top);
        sizePill.Visibility = Visibility.Visible;
    }

    private void CacheDpi() => dpiScale = VisualTreeHelper.GetDpi(this).DpiScaleX;

    private static void PlaceHandle(Ellipse handle, double x, double y)
    {
        Canvas.SetLeft(handle, x - 3);
        Canvas.SetTop(handle, y - 3);
        handle.Visibility = Visibility.Visible;
    }

    private void PositionHint()
    {
        Canvas.SetLeft(hint, Math.Max(10, (root.ActualWidth - hint.Width) / 2));
        Canvas.SetTop(hint, 25);
    }

    private void LogFirstFrame()
    {
        if (loggedFrame) return;
        loggedFrame = true;
        firstFrameMs = shown.ElapsedMilliseconds;
        var dpi = VisualTreeHelper.GetDpi(this);
        var hwnd = new WindowInteropHelper(this).Handle;
        DiagnosticsLog.Write(diagnosticLog,
            $"叠加层首帧 {firstFrameMs}ms 渲染层={DiagnosticsLog.Tier()} 实际渲染={DiagnosticsLog.ActualRenderMode()} " +
            $"透明窗口={(AllowsTransparency ? "是" : "否")} 分层窗口={(Native.IsLayeredWindow(hwnd) ? "是" : "否")} " +
            $"dpi={dpi.PixelsPerInchX.ToString("0", CultureInfo.InvariantCulture)}/{dpi.PixelsPerInchY.ToString("0", CultureInfo.InvariantCulture)} " +
            $"scale={dpi.DpiScaleX.ToString("0.###", CultureInfo.InvariantCulture)}×{dpi.DpiScaleY.ToString("0.###", CultureInfo.InvariantCulture)} " +
            $"窗口DIP={root.ActualWidth.ToString("0", CultureInfo.InvariantCulture)}×{root.ActualHeight.ToString("0", CultureInfo.InvariantCulture)} " +
            $"位图={pixelWidth}×{pixelHeight} 显示器={display.Width}×{display.Height}@{display.X},{display.Y} 绘制=压暗底图+选区原图");
    }

    private void LogSummary(string stage)
    {
        if (loggedSummary || string.IsNullOrWhiteSpace(diagnosticLog)) return;
        loggedSummary = true;
        var hwnd = new WindowInteropHelper(this).Handle;
        DiagnosticsLog.Write(diagnosticLog,
            $"选区{stage} 显示器={display.Width}×{display.Height}@{display.X},{display.Y} " +
            $"窗口DIP={root.ActualWidth.ToString("0", CultureInfo.InvariantCulture)}×{root.ActualHeight.ToString("0", CultureInfo.InvariantCulture)} " +
            $"位图={pixelWidth}×{pixelHeight} 首帧={(firstFrameMs < 0 ? "未到" : firstFrameMs + "ms")} " +
            $"透明窗口={(AllowsTransparency ? "是" : "否")} 分层窗口={(Native.IsLayeredWindow(hwnd) ? "是" : "否")} " +
            $"移动={moveCount} 忽略={ignoredMoves} 呈现帧={presentCount} " +
            $"{DiagnosticsLog.Stats("处理", handlerSamples.Count, handlerSamples.Snapshot())} " +
            $"{DiagnosticsLog.Stats("绘制", renderSamples.Count, renderSamples.Snapshot())} " +
            $"{DiagnosticsLog.Stats("呈现间隔", presentGaps.Count, presentGaps.Snapshot())} " +
            $"{DiagnosticsLog.Stats("移动到呈现", presentLatency.Count, presentLatency.Snapshot())}");
    }

    /// <summary>Desired size follows the overlay slot, never the full-resolution bitmap.</summary>
    private sealed class BackdropImage : Image
    {
        protected override Size MeasureOverride(Size constraint) => new(
            double.IsFinite(constraint.Width) ? constraint.Width : 0,
            double.IsFinite(constraint.Height) ? constraint.Height : 0);
    }

    private sealed class SampleBuffer
    {
        private readonly double[] values = new double[8192];
        private int next;
        public int Count { get; private set; }
        public void Add(double value)
        {
            values[next] = value;
            next = (next + 1) % values.Length;
            Count++;
        }
        public void Clear() { Count = 0; next = 0; }
        public double[] Snapshot()
        {
            var retained = Math.Min(Count, values.Length);
            if (retained == 0) return [];
            var result = new double[retained];
            if (Count <= values.Length) Array.Copy(values, result, retained);
            else
            {
                var tail = values.Length - next;
                Array.Copy(values, next, result, 0, tail);
                Array.Copy(values, 0, result, tail, next);
            }
            return result;
        }
    }
}
