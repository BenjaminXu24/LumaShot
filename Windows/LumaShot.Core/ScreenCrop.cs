namespace LumaShot.Core;

/// <summary>One monitor's already-captured BGRA bitmap, in screen pixels. The origin may be negative.</summary>
public readonly record struct MonitorBitmap(int X, int Y, int Width, int Height, PixelFrame Frame)
{
    public int Right => X + Width;
    public int Bottom => Y + Height;
}

/// <summary>
/// Crops a screen-pixel rectangle out of the full-monitor bitmaps taken when capture started.
/// A selection that crosses monitors is stitched. Pixels that miss every monitor stay opaque black.
/// </summary>
public static class ScreenCrop
{
    public static PixelFrame FromMonitors(IReadOnlyList<MonitorBitmap> monitors, int x, int y, int width, int height)
    {
        if (width <= 0 || height <= 0 || (long)width * height > PixelFrame.MaximumPixels)
            throw new ArgumentOutOfRangeException(nameof(width), "图像超过 8,000 万像素上限，请缩小截图区域。");
        var pixels = new byte[checked(width * height * 4)];
        for (var i = 3; i < pixels.Length; i += 4) pixels[i] = 255;
        foreach (var monitor in monitors)
        {
            var frameWidth = Math.Min(monitor.Width, monitor.Frame.Width);
            var frameHeight = Math.Min(monitor.Height, monitor.Frame.Height);
            if (frameWidth <= 0 || frameHeight <= 0) continue;
            var left = Math.Max((long)x, monitor.X);
            var top = Math.Max((long)y, monitor.Y);
            var right = Math.Min((long)x + width, (long)monitor.X + frameWidth);
            var bottom = Math.Min((long)y + height, (long)monitor.Y + frameHeight);
            if (right <= left || bottom <= top) continue;
            var copyWidth = (int)(right - left);
            var rows = (int)(bottom - top);
            var sourceX = (int)(left - monitor.X);
            var sourceY = (int)(top - monitor.Y);
            var destX = (int)(left - x);
            var destY = (int)(top - y);
            var source = monitor.Frame.Pixels;
            for (var row = 0; row < rows; row++)
            {
                var sourceIndex = ((sourceY + row) * monitor.Frame.Width + sourceX) * 4;
                var destIndex = ((destY + row) * width + destX) * 4;
                Buffer.BlockCopy(source, sourceIndex, pixels, destIndex, copyWidth * 4);
            }
        }
        return new(width, height, pixels);
    }
}
