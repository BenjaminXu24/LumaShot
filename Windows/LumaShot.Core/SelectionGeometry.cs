namespace LumaShot.Core;

/// <summary>Device-independent rectangle used by the capture overlay. Width and height are never negative.</summary>
public readonly record struct SelectionRect(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;
    public double Bottom => Y + Height;
    public bool IsEmpty => Width <= 0 || Height <= 0;
}

/// <summary>Bitmap crop in source pixels. This is the only region the selection hole may sample.</summary>
public readonly record struct PixelCrop(int X, int Y, int Width, int Height)
{
    public bool IsEmpty => Width <= 0 || Height <= 0;
}

public readonly record struct CapturePixels(int X, int Y, int Width, int Height);

/// <summary>
/// Pure selection math for the Windows overlay.
/// Pointer moves stay responsive when the UI samples <see cref="PreviewCrop"/> instead of the full frame
/// and posts at most one paint per <see cref="OverlayFrameGate"/> frame.
/// </summary>
public static class SelectionGeometry
{
    /// <summary>Black overlay alpha used by the selection backdrop. Matches the previous <c>Color.FromArgb(100, 0, 0, 0)</c> dim.</summary>
    public const byte OverlayAlpha = 100;

    public static (double X, double Y) Clamp(double x, double y, double width, double height)
    {
        var maxX = Math.Max(0, width);
        var maxY = Math.Max(0, height);
        return (Math.Clamp(x, 0, maxX), Math.Clamp(y, 0, maxY));
    }

    public static SelectionRect FromDrag(double originX, double originY, double x, double y, double surfaceWidth, double surfaceHeight)
    {
        (x, y) = Clamp(x, y, surfaceWidth, surfaceHeight);
        var left = Math.Min(originX, x);
        var top = Math.Min(originY, y);
        return new(left, top, Math.Abs(x - originX), Math.Abs(y - originY));
    }

    /// <summary>Intersection of a highlight with the overlay surface. Empty when the highlight is completely outside.</summary>
    public static SelectionRect Visible(SelectionRect rect, double surfaceWidth, double surfaceHeight)
    {
        if (rect.IsEmpty || surfaceWidth <= 0 || surfaceHeight <= 0) return default;
        var left = Math.Clamp(rect.X, 0, surfaceWidth);
        var top = Math.Clamp(rect.Y, 0, surfaceHeight);
        var right = Math.Clamp(rect.Right, 0, surfaceWidth);
        var bottom = Math.Clamp(rect.Bottom, 0, surfaceHeight);
        if (right <= left || bottom <= top) return default;
        return new(left, top, right - left, bottom - top);
    }

    /// <summary>
    /// Maps a DIP selection to source pixels. The result is clamped to the bitmap and is empty when nothing is visible.
    /// </summary>
    public static PixelCrop PreviewCrop(SelectionRect dip, double surfaceWidth, double surfaceHeight, int pixelWidth, int pixelHeight)
    {
        if (dip.IsEmpty || surfaceWidth <= 0 || surfaceHeight <= 0 || pixelWidth <= 0 || pixelHeight <= 0) return default;
        var scaleX = pixelWidth / surfaceWidth;
        var scaleY = pixelHeight / surfaceHeight;
        var x = (int)Math.Floor(dip.X * scaleX);
        var y = (int)Math.Floor(dip.Y * scaleY);
        var right = (int)Math.Ceiling(dip.Right * scaleX);
        var bottom = (int)Math.Ceiling(dip.Bottom * scaleY);
        x = Math.Clamp(x, 0, pixelWidth);
        y = Math.Clamp(y, 0, pixelHeight);
        right = Math.Clamp(right, 0, pixelWidth);
        bottom = Math.Clamp(bottom, 0, pixelHeight);
        if (right <= x || bottom <= y) return default;
        return new(x, y, right - x, bottom - y);
    }

    public static bool IsTooSmall(double width, double height) => width < 3 || height < 3;

    public static bool IsScrollTooSmall(int pixelWidth, int pixelHeight) => pixelWidth < 24 || pixelHeight < 40;

    /// <summary>Screen-pixel capture rectangle. Origin is floored; size is rounded. Matches the overlay commit path.</summary>
    public static CapturePixels ToCapturePixels(double left, double top, double right, double bottom) =>
        new((int)Math.Floor(left), (int)Math.Floor(top), (int)Math.Round(right - left), (int)Math.Round(bottom - top));

    public static (double Width, double Height) MeasuredPixels(double dipWidth, double dipHeight, double dpiScale) =>
        (Math.Round(dipWidth * dpiScale), Math.Round(dipHeight * dpiScale));
}

/// <summary>
/// Collapses a burst of pointer events into one paint. <see cref="Request"/> is true only for the first call in a frame;
/// the caller writes the latest point on every event and paints that point when the frame runs.
/// </summary>
public sealed class OverlayFrameGate
{
    private bool pending;
    public bool IsPending => pending;

    public bool Request()
    {
        if (pending) return false;
        pending = true;
        return true;
    }

    public void Release() => pending = false;
}
