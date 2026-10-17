using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LumaShot.Core;
using LumaShot.Windows.Services;

namespace LumaShot.Windows.Editor;

internal sealed class AnnotationCanvas : FrameworkElement
{
    public PixelFrame Original { get; }
    public AnnotationDocument Document { get; } = new();
    public AnnotationTool Tool { get; set; } = AnnotationTool.Arrow;
    public uint StrokeColor { get; set; } = 0xFF7D59EF;
    public double StrokeWidth { get; set; } = 4;
    public double FontSize { get; set; } = 28;
    public Guid? Selected { get; private set; }
    public double Zoom { get; private set; } = 1;
    private Vector pan;
    private bool fit = true;
    private readonly BitmapSource image;
    private ImagePoint? origin;
    private Point? mouseStart;
    private Vector panStart;
    private Annotation? pending;
    private Annotation? moving;
    private bool panning;
    public event Action? ViewChanged;
    public Func<string?>? RequestText { get; set; }
    public AnnotationCanvas(PixelFrame image)
    {
        Original = image; this.image = ImageCodec.Bitmap(image); Focusable = true; ClipToBounds = true;
        Document.Changed += () => { InvalidateVisual(); ViewChanged?.Invoke(); };
        SizeChanged += (_, _) => { if (fit) Fit(); };
        Loaded += (_, _) => Fit();
    }
    public void Fit() { fit = true; Zoom = Math.Min(1, Math.Min(Math.Max(1, ActualWidth - 70) / Original.Width, Math.Max(1, ActualHeight - 70) / Original.Height)); pan = default; InvalidateVisual(); ViewChanged?.Invoke(); }
    public void SetZoom(double value)
    {
        fit = false; Zoom = Math.Clamp(value, .02, 8); InvalidateVisual(); ViewChanged?.Invoke();
    }
    private Matrix Transform => new(Zoom, 0, 0, Zoom, (ActualWidth - Original.Width * Zoom) / 2 + pan.X, (ActualHeight - Original.Height * Zoom) / 2 + pan.Y);
    private ImagePoint ToImage(Point p)
    {
        var matrix = Transform; matrix.Invert(); var point = matrix.Transform(p);
        return new(Math.Clamp(point.X, 0, Original.Width), Math.Clamp(point.Y, 0, Original.Height));
    }
    protected override void OnRender(DrawingContext dc)
    {
        dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(238, 240, 247)), null, new Rect(RenderSize));
        dc.PushTransform(new MatrixTransform(Transform));
        dc.DrawRectangle(Brushes.White, null, new(0, 0, Original.Width, Original.Height));
        dc.DrawImage(image, new(0, 0, Original.Width, Original.Height));
        foreach (var item in Document.Items)
            AnnotationRenderer.Draw(dc, pending is not null && pending.Id == item.Id ? pending : item, Original);
        if (pending is not null && moving is null) AnnotationRenderer.Draw(dc, pending, Original);
        if (Selected is { } selected)
        {
            var item = pending?.Id == selected ? pending : Document.Items.FirstOrDefault(i => i.Id == selected);
            if (item is not null)
            {
                var bounds = item.Bounds; var rect = new Rect(bounds.X, bounds.Y, bounds.Width, bounds.Height); rect.Inflate(6 / Zoom, 6 / Zoom);
                dc.DrawRectangle(null, new Pen(new SolidColorBrush(Color.FromRgb(125, 89, 239)), 1.5 / Zoom) { DashStyle = DashStyles.Dash }, rect);
            }
        }
        dc.Pop();
    }
    protected override void OnMouseDown(MouseButtonEventArgs e)
    {
        base.OnMouseDown(e); if (e.ChangedButton != MouseButton.Left) return;
        Focus(); CaptureMouse(); var point = e.GetPosition(this); mouseStart = point; origin = ToImage(point);
        panning = Tool == AnnotationTool.Hand || Keyboard.Modifiers.HasFlag(ModifierKeys.Alt); panStart = pan;
        if (panning) { Cursor = Cursors.Hand; return; }
        if (Tool == AnnotationTool.Select)
        {
            moving = Document.Items.LastOrDefault(i => i.Bounds.Contains(origin.Value, 8 / Zoom)); Selected = moving?.Id; InvalidateVisual(); return;
        }
        Selected = null;
        if (Tool == AnnotationTool.Text)
        {
            ReleaseMouseCapture(); var text = RequestText?.Invoke();
            if (!string.IsNullOrWhiteSpace(text)) Document.Add(new(Tool, [origin.Value], StrokeColor, StrokeWidth, text, FontSize));
            origin = null; return;
        }
        if (Tool == AnnotationTool.Number)
        {
            var number = Document.Items.Where(i => i.Tool == AnnotationTool.Number).Select(i => i.Number).DefaultIfEmpty(0).Max() + 1;
            Document.Add(new(Tool, [origin.Value], StrokeColor, StrokeWidth, FontSize: FontSize, Number: number)); origin = null; ReleaseMouseCapture(); return;
        }
        pending = new(Tool, [origin.Value], StrokeColor, StrokeWidth, FontSize: FontSize); InvalidateVisual();
    }
    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (e.LeftButton != MouseButtonState.Pressed || origin is null || mouseStart is null) return;
        var current = e.GetPosition(this);
        if (panning) { fit = false; pan = panStart + (current - mouseStart.Value); InvalidateVisual(); return; }
        var point = ToImage(current);
        if (moving is not null) pending = moving.Move(point.X - origin.Value.X, point.Y - origin.Value.Y);
        else if (pending is not null)
        {
            if (Tool == AnnotationTool.Pen) pending = pending with { Points = [.. pending.Points, point] };
            else
            {
                if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift))
                {
                    var dx = point.X - origin.Value.X; var dy = point.Y - origin.Value.Y;
                    if (Tool == AnnotationTool.Arrow)
                    { var angle = Math.Round(Math.Atan2(dy, dx) / (Math.PI / 4)) * Math.PI / 4; var length = Math.Sqrt(dx * dx + dy * dy); point = origin.Value.Offset(Math.Cos(angle) * length, Math.Sin(angle) * length); }
                    else { var size = Math.Max(Math.Abs(dx), Math.Abs(dy)); point = origin.Value.Offset(Math.CopySign(size, dx), Math.CopySign(size, dy)); }
                }
                pending = pending with { Points = [origin.Value, point] };
            }
        }
        InvalidateVisual();
    }
    protected override void OnMouseUp(MouseButtonEventArgs e)
    {
        base.OnMouseUp(e); if (e.ChangedButton != MouseButton.Left) return;
        ReleaseMouseCapture();
        if (pending is not null)
        {
            if (moving is not null && !pending.Points.SequenceEqual(moving.Points)) Document.Replace(pending);
            else if (moving is null && (pending.Tool == AnnotationTool.Pen || pending.Points.Length > 1)) Document.Add(pending);
        }
        origin = null; mouseStart = null; pending = null; moving = null; panning = false; Cursor = Cursors.Arrow; InvalidateVisual();
    }
    protected override void OnMouseWheel(MouseWheelEventArgs e)
    {
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) SetZoom(Zoom * (e.Delta > 0 ? 1.15 : 1 / 1.15));
        else { fit = false; pan.Y += e.Delta / 2.0; InvalidateVisual(); }
        e.Handled = true;
    }
    public void DeleteSelected() { if (Selected is { } id) Document.Delete(id); Selected = null; InvalidateVisual(); }
    public void RecolorSelected()
    {
        var item = Document.Items.FirstOrDefault(i => i.Id == Selected);
        if (item is not null) Document.Replace(item with { Color = StrokeColor, StrokeWidth = StrokeWidth, FontSize = FontSize });
    }
    public BitmapSource Export() => AnnotationRenderer.Render(Original, Document.Items);
}
