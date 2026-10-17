using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using LumaShot.Core;
using LumaShot.Windows.Platform;
using LumaShot.Windows.Services;

namespace LumaShot.Windows.Capture;

internal sealed record Selection(PixelRect Bounds, nint TargetWindow);

internal sealed class SelectionWindow : Window
{
    private readonly PixelRect display;
    private readonly IReadOnlyList<DesktopWindow> targets;
    private readonly int mode;
    private readonly SelectionSurface surface;
    private Point? start;
    private DesktopWindow? target;
    public event Action<Selection?>? Selected;
    public SelectionWindow(PixelRect display, PixelFrame snapshot, IReadOnlyList<DesktopWindow> targets, int mode)
    {
        this.display = display; this.targets = targets; this.mode = mode;
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; ShowInTaskbar = false;
        Topmost = true; WindowStartupLocation = WindowStartupLocation.Manual; Background = Brushes.Black; Cursor = Cursors.Cross;
        surface = new SelectionSurface(ImageCodec.Bitmap(snapshot), mode); Content = surface;
        SourceInitialized += (_, _) => Native.SetWindowPos(new WindowInteropHelper(this).Handle, -1, display.X, display.Y, display.Width, display.Height, 0x0040);
        Loaded += (_, _) => { Activate(); Focus(); };
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) { Selected?.Invoke(null); e.Handled = true; } };
        MouseRightButtonDown += (_, e) => { Selected?.Invoke(null); e.Handled = true; };
        MouseLeftButtonDown += OnDown; MouseMove += OnMove; MouseLeftButtonUp += OnUp;
    }
    private void OnDown(object sender, MouseButtonEventArgs e)
    {
        if (mode == 2) { PickWindow(); return; }
        start = e.GetPosition(surface); surface.Region = Rect.Empty; surface.InvalidateVisual(); CaptureMouse();
    }
    private void PickWindow()
    {
        Native.GetCursorPos(out var mouse);
        target = targets.FirstOrDefault(w => w.Bounds.Contains(mouse.X, mouse.Y));
        if (target.Value.Handle == 0) { target = null; surface.Region = Rect.Empty; }
        else
        {
            var rect = target.Value.Bounds;
            var top = surface.PointFromScreen(new Point(rect.X, rect.Y));
            var bottom = surface.PointFromScreen(new Point(rect.Right, rect.Bottom));
            surface.Region = new Rect(top, bottom);
        }
        surface.InvalidateVisual();
    }
    private void OnMove(object sender, MouseEventArgs e)
    {
        if (mode == 2) { PickWindow(); return; }
        if (start is not { } origin || e.LeftButton != MouseButtonState.Pressed) return;
        var point = e.GetPosition(surface);
        point.X = Math.Clamp(point.X, 0, surface.ActualWidth); point.Y = Math.Clamp(point.Y, 0, surface.ActualHeight);
        surface.Region = new Rect(origin, point); surface.InvalidateVisual();
    }
    private void OnUp(object sender, MouseButtonEventArgs e)
    {
        ReleaseMouseCapture();
        if (mode == 2)
        {
            if (target is { } window) Selected?.Invoke(new(window.Bounds, window.Handle));
            return;
        }
        if (surface.Region.IsEmpty || surface.Region.Width < 3 || surface.Region.Height < 3) { start = null; return; }
        var first = surface.PointToScreen(surface.Region.TopLeft); var last = surface.PointToScreen(surface.Region.BottomRight);
        var bounds = new PixelRect((int)Math.Floor(first.X), (int)Math.Floor(first.Y), (int)Math.Round(last.X - first.X), (int)Math.Round(last.Y - first.Y));
        if (mode == 4 && (bounds.Width < 24 || bounds.Height < 40)) return;
        var candidate = targets.FirstOrDefault(w => w.Bounds.Contains(bounds.X + bounds.Width / 2, bounds.Y + bounds.Height / 2));
        Selected?.Invoke(new(bounds, candidate.Handle));
    }

    private sealed class SelectionSurface(ImageSource snapshot, int mode) : FrameworkElement
    {
        public Rect Region { get; set; } = Rect.Empty;
        protected override void OnRender(DrawingContext dc)
        {
            var bounds = new Rect(RenderSize); dc.DrawImage(snapshot, bounds);
            dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(100, 0, 0, 0)), null, bounds);
            if (!Region.IsEmpty)
            {
                dc.PushClip(new RectangleGeometry(Region)); dc.DrawImage(snapshot, bounds); dc.Pop();
                dc.DrawRectangle(null, new Pen(new SolidColorBrush(Color.FromRgb(180, 163, 255)), 2), Region);
                foreach (var p in new[] { Region.TopLeft, Region.TopRight, Region.BottomLeft, Region.BottomRight }) dc.DrawEllipse(Brushes.White, null, p, 3, 3);
                var scale = VisualTreeHelper.GetDpi(this).DpiScaleX;
                Pill(dc, $"{Math.Round(Region.Width * scale)} × {Math.Round(Region.Height * scale)}", new Point(Math.Clamp(Region.Left, 10, Math.Max(10, ActualWidth - 150)), Math.Max(70, Region.Top - 42)), 140);
            }
            var hint = mode == 2 ? "点击选择窗口  ·  Esc / 右键取消" : mode == 4 ? "框选滚动内容，避开固定侧栏  ·  Esc / 右键取消" : "拖动选择区域  ·  Esc / 右键取消";
            Pill(dc, hint, new Point(Math.Max(10, (ActualWidth - 440) / 2), 25), 440);
        }
        private void Pill(DrawingContext dc, string text, Point point, double width)
        {
            dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(235, 29, 31, 44)), null, new Rect(point.X, point.Y, width, 35), 12, 12);
            var formatted = new FormattedText(text, System.Globalization.CultureInfo.CurrentCulture, FlowDirection.LeftToRight, new Typeface("Segoe UI, Microsoft YaHei UI"), 13, Brushes.White, VisualTreeHelper.GetDpi(this).PixelsPerDip);
            dc.DrawText(formatted, new Point(point.X + (width - formatted.Width) / 2, point.Y + 8));
        }
    }
}
