using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using LumaShot.Core;
using LumaShot.Windows.Platform;
using LumaShot.Windows.Services;

namespace LumaShot.Windows.Capture;

internal sealed record Selection(PixelRect Bounds, nint TargetWindow);

internal sealed class SelectionWindow : Window
{
    private static readonly SolidColorBrush SelectionBorderBrush = Freeze(Color.FromRgb(180, 163, 255));
    private static readonly SolidColorBrush PillBrush = Freeze(Color.FromArgb(235, 29, 31, 44));
    private static SolidColorBrush Freeze(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    private readonly PixelRect display;
    private readonly IReadOnlyList<DesktopWindow> targets;
    private readonly int mode;
    private readonly int pixelWidth;
    private readonly int pixelHeight;
    private readonly string? diagnosticLog;
    private readonly Grid root;
    private readonly Canvas chrome;
    private readonly Rectangle hole;
    private readonly ImageBrush holeBrush;
    private readonly Rectangle border;
    private readonly Ellipse[] handles;
    private readonly Border sizePill;
    private readonly TextBlock sizeText;
    private readonly Border hint;
    private readonly OverlayFrameGate gate = new();
    private Point? start;
    private DesktopWindow? target;
    private Rect region = Rect.Empty;
    private Rect painted = Rect.Empty;
    private bool paintedValid;
    private bool closed;
    public event Action<Selection?>? Selected;

    public SelectionWindow(PixelRect display, PixelFrame snapshot, IReadOnlyList<DesktopWindow> targets, int mode, PixelFrame? dimmed = null, string? diagnosticLog = null)
    {
        this.display = display;
        this.targets = targets;
        this.mode = mode;
        this.diagnosticLog = diagnosticLog;
        pixelWidth = snapshot.Width;
        pixelHeight = snapshot.Height;
        if (dimmed is null || dimmed.Width != snapshot.Width || dimmed.Height != snapshot.Height)
            dimmed = snapshot.Dimmed(SelectionGeometry.OverlayAlpha);
        var backdrop = ImageCodec.Bitmap(dimmed);
        var preview = ImageCodec.Bitmap(snapshot);
        holeBrush = new ImageBrush(preview)
        {
            Stretch = Stretch.Fill,
            ViewboxUnits = BrushMappingMode.Absolute,
            Viewport = new Rect(0, 0, 1, 1),
            ViewportUnits = BrushMappingMode.RelativeToBoundingBox,
            TileMode = TileMode.None,
            AlignmentX = AlignmentX.Left,
            AlignmentY = AlignmentY.Top
        };

        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Background = Brushes.Black;
        Cursor = Cursors.Cross;
        ForceCursor = true;
        root = new Grid { Background = Brushes.Black };
        var background = new BackdropImage { Source = backdrop, Stretch = Stretch.Fill, IsHitTestVisible = false, SnapsToDevicePixels = true };
        RenderOptions.SetBitmapScalingMode(background, BitmapScalingMode.LowQuality);
        hole = new Rectangle { IsHitTestVisible = false, SnapsToDevicePixels = true, Visibility = Visibility.Collapsed, Fill = holeBrush };
        RenderOptions.SetBitmapScalingMode(hole, BitmapScalingMode.LowQuality);
        border = new Rectangle
        {
            Stroke = SelectionBorderBrush,
            StrokeThickness = 2,
            IsHitTestVisible = false,
            SnapsToDevicePixels = true,
            Visibility = Visibility.Collapsed
        };
        handles = [Handle(), Handle(), Handle(), Handle()];
        sizeText = new TextBlock { Foreground = Brushes.White, FontSize = 13, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        sizePill = Pill(sizeText, 140);
        sizePill.Visibility = Visibility.Collapsed;
        var hintText = mode == 2 ? "点击选择窗口  ·  Esc / 右键取消" : mode == 4 ? "框选滚动内容，避开固定侧栏  ·  Esc / 右键取消" : "拖动选择区域  ·  Esc / 右键取消";
        hint = Pill(new TextBlock { Text = hintText, Foreground = Brushes.White, FontSize = 13, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center }, 440);
        chrome = new Canvas { IsHitTestVisible = false };
        chrome.Children.Add(hole);
        chrome.Children.Add(border);
        foreach (var handle in handles) chrome.Children.Add(handle);
        chrome.Children.Add(sizePill);
        chrome.Children.Add(hint);
        root.Children.Add(background);
        root.Children.Add(chrome);
        Content = root;

        SourceInitialized += (_, _) => Native.SetWindowPos(new WindowInteropHelper(this).Handle, -1, display.X, display.Y, display.Width, display.Height, 0x0040);
        Loaded += (_, _) =>
        {
            PositionHint();
            LogDisplay();
            Activate();
            Focus();
        };
        SizeChanged += (_, _) =>
        {
            PositionHint();
            if (paintedValid) ApplyChrome(region);
        };
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) { Selected?.Invoke(null); e.Handled = true; } };
        MouseRightButtonDown += (_, e) => { Selected?.Invoke(null); e.Handled = true; };
        MouseLeftButtonDown += OnDown;
        MouseMove += OnMove;
        MouseLeftButtonUp += OnUp;
        Closed += (_, _) => closed = true;
    }

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
        start = e.GetPosition(root);
        region = Rect.Empty;
        ApplyChrome(region);
        CaptureMouse();
    }

    private void OnMove(object sender, MouseEventArgs e)
    {
        if (mode == 2)
        {
            if (UpdateTarget()) SchedulePaint();
            return;
        }
        if (start is not { } origin || e.LeftButton != MouseButtonState.Pressed) return;
        var point = e.GetPosition(root);
        var drag = SelectionGeometry.FromDrag(origin.X, origin.Y, point.X, point.Y, root.ActualWidth, root.ActualHeight);
        var next = new Rect(drag.X, drag.Y, drag.Width, drag.Height);
        if (next == region) return;
        region = next;
        SchedulePaint();
    }

    private void OnUp(object sender, MouseButtonEventArgs e)
    {
        ReleaseMouseCapture();
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

    private void SchedulePaint()
    {
        if (closed || !gate.Request()) return;
        try { Dispatcher.BeginInvoke(DispatcherPriority.Render, PaintFrame); }
        catch (InvalidOperationException) { gate.Release(); }
    }

    private void PaintFrame()
    {
        try
        {
            if (!closed) ApplyChrome(region);
        }
        finally
        {
            gate.Release();
            if (!closed && region != painted) SchedulePaint();
        }
    }

    /// <summary>
    /// Moves only selection-sized elements. The full-screen backdrop is never invalidated here:
    /// redrawing it on each move freezes software rendering and remote-desktop updates.
    /// </summary>
    private void ApplyChrome(Rect next)
    {
        painted = next;
        paintedValid = true;
        if (next.IsEmpty || next.Width <= 0 || next.Height <= 0)
        {
            hole.Visibility = Visibility.Collapsed;
            border.Visibility = Visibility.Collapsed;
            sizePill.Visibility = Visibility.Collapsed;
            foreach (var handle in handles) handle.Visibility = Visibility.Collapsed;
            return;
        }
        var logical = new SelectionRect(next.X, next.Y, next.Width, next.Height);
        var visible = SelectionGeometry.Visible(logical, root.ActualWidth, root.ActualHeight);
        var crop = SelectionGeometry.PreviewCrop(visible, root.ActualWidth, root.ActualHeight, pixelWidth, pixelHeight);
        if (visible.IsEmpty || crop.IsEmpty)
            hole.Visibility = Visibility.Collapsed;
        else
        {
            var scaleX = PreviewScale(holeBrush.ImageSource as BitmapSource, true);
            var scaleY = PreviewScale(holeBrush.ImageSource as BitmapSource, false);
            holeBrush.Viewbox = new Rect(crop.X * scaleX, crop.Y * scaleY, crop.Width * scaleX, crop.Height * scaleY);
            Canvas.SetLeft(hole, visible.X);
            Canvas.SetTop(hole, visible.Y);
            hole.Width = visible.Width;
            hole.Height = visible.Height;
            hole.Visibility = Visibility.Visible;
        }
        Canvas.SetLeft(border, next.X);
        Canvas.SetTop(border, next.Y);
        border.Width = Math.Max(0, next.Width);
        border.Height = Math.Max(0, next.Height);
        border.Visibility = Visibility.Visible;
        PlaceHandle(handles[0], next.Left, next.Top);
        PlaceHandle(handles[1], next.Right, next.Top);
        PlaceHandle(handles[2], next.Left, next.Bottom);
        PlaceHandle(handles[3], next.Right, next.Bottom);
        var measured = SelectionGeometry.MeasuredPixels(next.Width, next.Height, VisualTreeHelper.GetDpi(this).DpiScaleX);
        sizeText.Text = $"{measured.Width} × {measured.Height}";
        var left = Math.Clamp(next.Left, 10, Math.Max(10, root.ActualWidth - 150));
        var top = Math.Max(70, next.Top - 42);
        Canvas.SetLeft(sizePill, left);
        Canvas.SetTop(sizePill, top);
        sizePill.Visibility = Visibility.Visible;
    }

    private static double PreviewScale(BitmapSource? source, bool horizontal)
    {
        var dpi = source is null ? 96 : horizontal ? source.DpiX : source.DpiY;
        return dpi <= 0 ? 1 : 96.0 / dpi;
    }

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

    /// <summary>Desired size follows the overlay slot, never the full-resolution bitmap.</summary>
    private sealed class BackdropImage : Image
    {
        protected override Size MeasureOverride(Size constraint) => new(
            double.IsFinite(constraint.Width) ? constraint.Width : 0,
            double.IsFinite(constraint.Height) ? constraint.Height : 0);
    }

    private void LogDisplay()
    {
        var dpi = VisualTreeHelper.GetDpi(this);
        OverlayDiagnostics.Write(diagnosticLog,
            $"选区叠加 dpi={dpi.PixelsPerInchX:0}/{dpi.PixelsPerInchY:0} scale={dpi.DpiScaleX:0.###}×{dpi.DpiScaleY:0.###} " +
            $"窗口DIP={root.ActualWidth:0}×{root.ActualHeight:0} 位图={pixelWidth}×{pixelHeight} " +
            $"显示器={display.Width}×{display.Height}@{display.X},{display.Y} 绘制=仅选区");
    }
}
