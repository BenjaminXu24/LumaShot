namespace LumaShot.Core;

public enum AppendStatus { Appended, Unchanged, NoOverlap, HeightLimit }
public readonly record struct AppendResult(AppendStatus Status, int AddedPixels = 0, int TotalHeight = 0);

/// <summary>Pixel-aligned vertical stitching, with fixed header/footer deduplication.</summary>
public sealed class ImageStitcher
{
    private sealed class Signature
    {
        private const int Width = 80;
        private readonly int height;
        private readonly byte[] values;
        private readonly List<int> anchors = [];
        public Signature(PixelFrame image)
        {
            height = image.Height; values = new byte[Width * height];
            for (var y = 0; y < height; y++) for (var x = 0; x < Width; x++)
            {
                var sourceX = Math.Min(image.Width - 1, (2 * x + 1) * image.Width / (2 * Width));
                var p = (y * image.Width + sourceX) * 4;
                values[y * Width + x] = (byte)((image.Pixels[p + 2] * 3 + image.Pixels[p + 1] * 6 + image.Pixels[p]) / 10);
            }
            var bin = Math.Max(1, height / 24);
            for (var start = 0; start < height; start += bin)
            {
                var strongest = 0; var row = start;
                for (var y = start; y < Math.Min(height, start + bin); y++)
                {
                    var low = 255; var high = 0; var vertical = 0;
                    for (var x = 7; x < Width - 7; x += 2)
                    {
                        var value = (int)values[y * Width + x]; low = Math.Min(low, value); high = Math.Max(high, value);
                        if (y > 0) vertical += Math.Abs(value - values[(y - 1) * Width + x]);
                    }
                    var energy = high - low + vertical / 33;
                    if (energy > strongest) { strongest = energy; row = y; }
                }
                if (strongest > 4) anchors.Add(row);
            }
        }
        public double RowDifference(Signature other, int first, int second)
        {
            var sum = 0; var count = 0;
            for (var x = 7; x < Width - 7; x += 2)
            { sum += Math.Abs(values[first * Width + x] - other.values[second * Width + x]); count++; }
            return (double)sum / count;
        }
        public double Difference(Signature other, int shift, int top, int bottom, int samples = 34)
        {
            var end = height - shift - bottom;
            if (end - top <= 24) return double.PositiveInfinity;
            double total = 0; var count = 0;
            for (var y = top; y < end; y += Math.Max(1, (end - top) / samples))
            { total += RowDifference(other, y + shift, y); count++; }
            foreach (var y in other.anchors) if (y >= top && y < end)
            { total += RowDifference(other, y + shift, y); count++; }
            foreach (var previous in anchors)
            {
                var y = previous - shift;
                if (y >= top && y < end) { total += RowDifference(other, previous, y); count++; }
            }
            return total / Math.Max(1, count);
        }
    }

    private PixelFrame previous;
    private Signature signature;
    private readonly List<PixelFrame> segments;
    private PixelFrame? footer;
    private int footerHeight;
    public int TotalHeight { get; private set; }
    public int FrameCount { get; private set; } = 1;
    public int MaximumHeight { get; }
    public ImageStitcher(PixelFrame first, int maximumHeight = 50_000)
    {
        previous = first; signature = new(first); segments = [first]; TotalHeight = first.Height;
        MaximumHeight = (int)Math.Min(Math.Max(first.Height, maximumHeight), Math.Max(first.Height, PixelFrame.MaximumPixels / first.Width));
    }

    public AppendResult Append(PixelFrame image)
    {
        if (image.Width != previous.Width || image.Height != previous.Height) return new(AppendStatus.NoOverlap);
        var next = new Signature(image); var height = image.Height; var edgeLimit = Math.Max(1, height / 5);
        var top = 0; var bottom = 0;
        while (top < edgeLimit && signature.RowDifference(next, top, top) < 2.2) top++;
        while (bottom < edgeLimit && signature.RowDifference(next, height - bottom - 1, height - bottom - 1) < 2.2) bottom++;
        if (top == edgeLimit) top = 0;
        if (bottom == edgeLimit) bottom = 0;
        var baseline = signature.Difference(next, 0, 0, 0, 70);
        if (baseline < 1.1) return new(AppendStatus.Unchanged);
        var maximumShift = height - Math.Max(Math.Max(40, height / 7), top + bottom + 32);
        var bestShift = 0; var score = double.PositiveInfinity;
        for (var shift = 1; shift <= maximumShift; shift++)
        {
            var candidate = signature.Difference(next, shift, top, bottom);
            if (candidate < score) { score = candidate; bestShift = shift; }
        }
        if (bestShift == 0 || score >= 17 || (score >= baseline * .78 && score >= 2)
            || signature.Difference(next, bestShift, top, bottom, 120) >= 20) return new(AppendStatus.NoOverlap);
        if ((long)TotalHeight + bestShift > MaximumHeight) return new(AppendStatus.HeightLimit);
        var proposedFooter = FrameCount == 1 ? (bottom >= 3 ? bottom : 0) : footerHeight;
        var contentStart = height - proposedFooter - bestShift;
        if (contentStart < top) return new(AppendStatus.NoOverlap);
        // Allocate slices before mutating the existing result.
        var addition = image.Slice(contentStart, bestShift);
        var newFooter = proposedFooter > 0 ? image.Slice(height - proposedFooter, proposedFooter) : null;
        if (FrameCount == 1 && proposedFooter > 0) segments[0] = previous.Slice(0, height - proposedFooter);
        footerHeight = proposedFooter; footer = newFooter; segments.Add(addition);
        TotalHeight += bestShift; FrameCount++; previous = image; signature = next;
        return new(AppendStatus.Appended, bestShift, TotalHeight);
    }

    public PixelFrame MakeImage()
    {
        var output = new byte[checked(previous.Width * TotalHeight * 4)]; var offset = 0;
        foreach (var segment in segments)
        { Buffer.BlockCopy(segment.Pixels, 0, output, offset, segment.Pixels.Length); offset += segment.Pixels.Length; }
        if (footer is not null) Buffer.BlockCopy(footer.Pixels, 0, output, offset, footer.Pixels.Length);
        return new(previous.Width, TotalHeight, output);
    }
}
