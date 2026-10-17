using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LumaShot.Core;
using LumaShot.Windows.Services;

namespace LumaShot.Windows.Editor;

internal static class AnnotationRenderer
{
    internal static Color Color(uint argb) => System.Windows.Media.Color.FromArgb((byte)(argb >> 24), (byte)(argb >> 16), (byte)(argb >> 8), (byte)argb);
    internal static void Draw(DrawingContext dc, Annotation item, PixelFrame original, double pixelsPerDip = 1)
    {
        if (item.Points.Length == 0) return;
        var brush = new SolidColorBrush(Color(item.Color));
        var pen = new Pen(brush, item.StrokeWidth) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
        Point P(ImagePoint p) => new(p.X, p.Y);
        var bounds = item.Bounds; var rect = new Rect(bounds.X, bounds.Y, bounds.Width, bounds.Height);
        switch (item.Tool)
        {
            case AnnotationTool.Arrow when item.Points.Length >= 2:
                var start = P(item.Points[0]); var end = P(item.Points[^1]); dc.DrawLine(pen, start, end);
                var vector = start - end;
                if (vector.Length < .01) break;
                vector.Normalize(); var length = Math.Max(14, item.StrokeWidth * 4); var side = new Vector(-vector.Y, vector.X);
                dc.DrawLine(pen, end, end + vector * length + side * length * .48);
                dc.DrawLine(pen, end, end + vector * length - side * length * .48); break;
            case AnnotationTool.Rectangle: dc.DrawRectangle(null, pen, rect); break;
            case AnnotationTool.Ellipse: dc.DrawEllipse(null, pen, new(rect.X + rect.Width / 2, rect.Y + rect.Height / 2), rect.Width / 2, rect.Height / 2); break;
            case AnnotationTool.Pen:
                if (item.Points.Length == 1) { dc.DrawEllipse(brush, null, P(item.Points[0]), item.StrokeWidth / 2, item.StrokeWidth / 2); break; }
                var path = new StreamGeometry();
                using (var context = path.Open()) { context.BeginFigure(P(item.Points[0]), false, false); context.PolyLineTo(item.Points.Skip(1).Select(P).ToList(), true, false); }
                path.Freeze(); dc.DrawGeometry(null, pen, path); break;
            case AnnotationTool.Text:
                dc.DrawText(Text(item.Text, item.FontSize, brush, pixelsPerDip), P(item.Points[0])); break;
            case AnnotationTool.Number:
                var center = P(item.Points[0]); var radius = Math.Max(16, item.FontSize * .7);
                dc.DrawEllipse(brush, null, center, radius, radius);
                var number = Text(item.Number.ToString(CultureInfo.InvariantCulture), item.FontSize * .85, Brushes.White, pixelsPerDip);
                dc.DrawText(number, new(center.X - number.Width / 2, center.Y - number.Height / 2)); break;
            case AnnotationTool.Mosaic:
                var left = Math.Clamp((int)Math.Floor(rect.Left), 0, original.Width - 1);
                var top = Math.Clamp((int)Math.Floor(rect.Top), 0, original.Height - 1);
                var width = Math.Min(original.Width - left, Math.Max(1, (int)Math.Ceiling(rect.Right) - left));
                var height = Math.Min(original.Height - top, Math.Max(1, (int)Math.Ceiling(rect.Bottom) - top));
                var mosaic = original.Mosaic(left, top, width, height, Math.Max(10, (int)item.StrokeWidth * 4));
                dc.DrawImage(ImageCodec.Bitmap(mosaic), new(left, top, mosaic.Width, mosaic.Height)); break;
        }
    }
    private static FormattedText Text(string text, double size, Brush brush, double dpi) => new(text, CultureInfo.CurrentCulture, FlowDirection.LeftToRight, new Typeface("Segoe UI, Microsoft YaHei UI"), size, brush, dpi);
    internal static BitmapSource Render(PixelFrame frame, IReadOnlyList<Annotation> annotations)
    {
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            dc.DrawImage(ImageCodec.Bitmap(frame), new(0, 0, frame.Width, frame.Height));
            foreach (var item in annotations) Draw(dc, item, frame);
        }
        var bitmap = new RenderTargetBitmap(frame.Width, frame.Height, 96, 96, PixelFormats.Pbgra32); bitmap.Render(visual); bitmap.Freeze(); return bitmap;
    }
}
