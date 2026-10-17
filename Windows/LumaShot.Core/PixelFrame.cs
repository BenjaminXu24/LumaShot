namespace LumaShot.Core;

/// <summary>Top-down BGRA pixels, independent of display DPI and UI frameworks.</summary>
public sealed class PixelFrame
{
    public const long MaximumPixels = 80_000_000;
    public int Width { get; }
    public int Height { get; }
    public byte[] Pixels { get; }
    public int Stride => checked(Width * 4);

    public PixelFrame(int width, int height, byte[] pixels)
    {
        if (width <= 0 || height <= 0 || (long)width * height > MaximumPixels)
            throw new ArgumentOutOfRangeException(nameof(width), "图像超过 8,000 万像素上限，请缩小截图区域。");
        if (pixels.Length != checked(width * height * 4)) throw new ArgumentException("Invalid BGRA buffer.", nameof(pixels));
        Width = width; Height = height; Pixels = pixels;
    }

    public PixelFrame Slice(int top, int height)
    {
        if (top < 0 || height <= 0 || top + height > Height) throw new ArgumentOutOfRangeException(nameof(top));
        var data = new byte[checked(Stride * height)];
        Buffer.BlockCopy(Pixels, top * Stride, data, 0, data.Length);
        return new(Width, height, data);
    }

    public PixelFrame Mosaic(int left, int top, int width, int height, int blockSize = 16)
    {
        var right = (int)Math.Clamp((long)left + width, 0, Width);
        var bottom = (int)Math.Clamp((long)top + height, 0, Height);
        left = Math.Clamp(left, 0, Width); top = Math.Clamp(top, 0, Height);
        if (right <= left || bottom <= top) throw new ArgumentException("Empty mosaic region.");
        var result = new byte[checked((right - left) * (bottom - top) * 4)];
        var outputWidth = right - left;
        blockSize = Math.Clamp(blockSize, 2, 100);
        for (var y = top; y < bottom; y += blockSize)
        for (var x = left; x < right; x += blockSize)
        {
            var endY = Math.Min(y + blockSize, bottom); var endX = Math.Min(x + blockSize, right);
            long b = 0, g = 0, r = 0, a = 0; var count = 0;
            for (var yy = y; yy < endY; yy++) for (var xx = x; xx < endX; xx++)
            {
                var p = (yy * Width + xx) * 4;
                b += Pixels[p]; g += Pixels[p + 1]; r += Pixels[p + 2]; a += Pixels[p + 3]; count++;
            }
            for (var yy = y; yy < endY; yy++) for (var xx = x; xx < endX; xx++)
            {
                var p = ((yy - top) * outputWidth + xx - left) * 4;
                result[p] = (byte)(b / count); result[p + 1] = (byte)(g / count);
                result[p + 2] = (byte)(r / count); result[p + 3] = (byte)(a / count);
            }
        }
        return new(outputWidth, bottom - top, result);
    }
}
