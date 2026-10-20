using LumaShot.Core;

var passed = 0;
void Test(string name, Action test) { test(); Console.WriteLine($"PASS {name}"); passed++; }
void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
PixelFrame Pattern(int width = 160, int height = 1000, int seed = 17)
{
    var random = new Random(seed); var pixels = new byte[width * height * 4]; random.NextBytes(pixels);
    for (var i = 3; i < pixels.Length; i += 4) pixels[i] = 255;
    return new(width, height, pixels);
}
void Equal(PixelFrame first, PixelFrame second) => Check(first.Width == second.Width && first.Height == second.Height && first.Pixels.SequenceEqual(second.Pixels), "Pixel buffers differ.");
var source = Pattern();
Test("Exact overlap and pixel order", () => {
    var stitcher = new ImageStitcher(source.Slice(0, 300)); var result = stitcher.Append(source.Slice(130, 300));
    Check(result.Status == AppendStatus.Appended && result.AddedPixels == 130, "Incorrect shift."); Equal(stitcher.MakeImage(), source.Slice(0, 430));
});
Test("Multiple frames retain every source row", () => {
    var stitcher = new ImageStitcher(source.Slice(0, 300));
    foreach (var offset in new[] { 130, 260, 390, 520 }) Check(stitcher.Append(source.Slice(offset, 300)).Status == AppendStatus.Appended, "Frame rejected.");
    Equal(stitcher.MakeImage(), source.Slice(0, 820)); Check(stitcher.FrameCount == 5, "Incorrect count.");
});
Test("Repeated frame is unchanged", () => {
    var first = source.Slice(0, 300); var stitcher = new ImageStitcher(first);
    Check(stitcher.Append(first).Status == AppendStatus.Unchanged && stitcher.FrameCount == 1, "Duplicate appended."); Equal(stitcher.MakeImage(), first);
});
Test("Unrelated frame does not damage result", () => {
    var first = source.Slice(0, 300); var stitcher = new ImageStitcher(first);
    Check(stitcher.Append(Pattern(160, 300, 90)).Status == AppendStatus.NoOverlap, "Unrelated image accepted."); Equal(stitcher.MakeImage(), first);
});
Test("Different dimensions are rejected", () => {
    var stitcher = new ImageStitcher(source.Slice(0, 300)); Check(stitcher.Append(Pattern(161, 300)).Status == AppendStatus.NoOverlap, "Changed width accepted.");
});
Test("Height limit preserves existing image", () => {
    var first = source.Slice(0, 300); var stitcher = new ImageStitcher(first, 400);
    Check(stitcher.Append(source.Slice(130, 300)).Status == AppendStatus.HeightLimit, "Height limit ignored."); Equal(stitcher.MakeImage(), first);
});
Test("Sticky header and footer appear once", () => {
    PixelFrame View(int offset) {
        var body = source.Slice(offset, 260); var pixels = new byte[160 * 300 * 4];
        for (var y = 0; y < 300; y++) for (var x = 0; x < 160; x++) {
            var p = (y * 160 + x) * 4; pixels[p] = (byte)(y < 20 ? 40 : 210); pixels[p + 1] = 24; pixels[p + 2] = 90; pixels[p + 3] = 255;
        }
        Buffer.BlockCopy(body.Pixels, 0, pixels, 20 * 160 * 4, body.Pixels.Length); return new(160, 300, pixels);
    }
    var first = View(0); var stitcher = new ImageStitcher(first); var result = stitcher.Append(View(110));
    Check(result.Status == AppendStatus.Appended && result.AddedPixels == 110, "Sticky alignment failed.");
    var output = stitcher.MakeImage(); Check(output.Height == 410, "Incorrect sticky height."); Equal(output.Slice(20, 370), source.Slice(0, 370));
});
Test("Sparse content uses informative rows", () => {
    const int width = 160; const int height = 900; var pixels = Enumerable.Repeat((byte)255, width * height * 4).ToArray();
    foreach (var row in new[] { 35, 84, 151, 213, 268, 329, 401, 478, 551, 640, 719, 812 })
    for (var y = row; y < row + 3; y++) for (var x = 12; x < 140; x++) {
        var p = (y * width + x) * 4; pixels[p] = (byte)(row * 7 % 220); pixels[p + 1] = (byte)(x * 11 % 230); pixels[p + 2] = (byte)(row % 180);
    }
    var page = new PixelFrame(width, height, pixels); var stitcher = new ImageStitcher(page.Slice(0, 300));
    Check(stitcher.Append(page.Slice(113, 300)).Status == AppendStatus.Appended, "Sparse overlap not found."); Equal(stitcher.MakeImage(), page.Slice(0, 413));
});
Test("Mosaic replaces actual output pixels", () => {
    var image = Pattern(40, 40); var masked = image.Mosaic(8, 8, 16, 16, 16);
    Check(masked.Width == 16 && masked.Height == 16, "Incorrect mosaic crop.");
    for (var p = 4; p < masked.Pixels.Length; p += 4) Check(masked.Pixels.AsSpan(p, 4).SequenceEqual(masked.Pixels.AsSpan(0, 4)), "Mosaic leaves original detail.");
    Check(!image.Slice(8, 16).Pixels.SequenceEqual(masked.Pixels), "Image unchanged.");
});
Test("Mosaic clamps safely to image edges", () => { var mask = Pattern(20, 20).Mosaic(16, 17, 50, 50); Check(mask.Width == 4 && mask.Height == 3, "Out of bounds mosaic."); });
Test("Oversized and invalid buffers rejected", () => {
    var rejected = false; try { _ = new PixelFrame(100_000, 100_000, []); } catch (ArgumentOutOfRangeException) { rejected = true; }
    Check(rejected, "Pixel cap ignored."); rejected = false; try { _ = new PixelFrame(10, 10, [0]); } catch (ArgumentException) { rejected = true; } Check(rejected, "Invalid buffer accepted.");
});
Test("Annotation coordinates stay in native pixels", () => {
    var a = new Annotation(AnnotationTool.Rectangle, [new(20, 40), new(200, 400)]);
    var moved = a.Move(10, 15); Check(moved.Bounds == new ImageBounds(30, 55, 180, 360), "Movement changed dimensions."); Check(a.Points[0] == new ImagePoint(20, 40), "Original mutated.");
});
Test("Undo and redo restore complete edits", () => {
    var doc = new AnnotationDocument(); var a = new Annotation(AnnotationTool.Arrow, [new(10, 10), new(100, 100)]); doc.Add(a); doc.Replace(a.Move(25, 30));
    doc.Undo(); Check(doc.Items[0].Points[0] == a.Points[0], "Undo move failed."); doc.Undo(); Check(doc.Items.Count == 0, "Undo add failed.");
    doc.Redo(); doc.Redo(); Check(doc.Items[0].Points[0] == new ImagePoint(35, 40), "Redo failed.");
});
Test("New edit invalidates redo branch", () => { var doc = new AnnotationDocument(); var a = new Annotation(AnnotationTool.Number, [new(10,10)]); doc.Add(a); doc.Undo(); doc.Add(a with { Number = 2 }); Check(!doc.CanRedo, "Stale redo branch retained."); });
Test("Snapshot does not alias caller arrays", () => { var points = new ImagePoint[] { new(1,2),new(3,4) }; var doc = new AnnotationDocument(); doc.Add(new(AnnotationTool.Pen, points)); points[0] = new(99,99); Check(doc.Items[0].Points[0] == new ImagePoint(1,2), "Caller mutated document."); });
Test("Delete and clear remain undoable", () => { var doc = new AnnotationDocument(); var a = new Annotation(AnnotationTool.Text, [new(2,3)], Text:"hello"); doc.Add(a); doc.Delete(a.Id); doc.Undo(); Check(doc.Items.Count == 1,"Delete not undoable."); doc.Clear(); doc.Undo(); Check(doc.Items.Count == 1,"Clear not undoable."); });
Test("Drag normalizes, clamps, and matches either direction", () =>
{
    var forward = SelectionGeometry.FromDrag(10, 20, 110, 70, 800, 600);
    var backward = SelectionGeometry.FromDrag(110, 70, 10, 20, 800, 600);
    Check(forward == backward && forward == new SelectionRect(10, 20, 100, 50), "Drag rectangle changed with direction.");
    var clamped = SelectionGeometry.FromDrag(10, 10, -50, 900, 200, 100);
    Check(clamped == new SelectionRect(0, 10, 10, 90), "Drag left the surface.");
});
Test("Off-screen window highlight is clipped to the monitor", () =>
{
    var visible = SelectionGeometry.Visible(new(-20, -10, 100, 40), 200, 100);
    Check(visible == new SelectionRect(0, 0, 80, 30), "Visible intersection mismatch.");
    Check(SelectionGeometry.Visible(new(300, 300, 10, 10), 200, 100).IsEmpty, "Off-screen highlight survived.");
});
Test("Preview crop tracks the selection instead of the full frame", () =>
{
    var crop = SelectionGeometry.PreviewCrop(new(10, 20, 30, 40), 1920, 1080, 3840, 2160);
    Check(crop == new PixelCrop(20, 40, 60, 80), "200% crop mismatch.");
    Check((long)crop.Width * crop.Height * 100 < (long)3840 * 2160, "Crop covers the frame.");
    var fractional = SelectionGeometry.PreviewCrop(new(10.5, 0, 10, 10), 100, 100, 150, 150);
    Check(fractional == new PixelCrop(15, 0, 16, 15), "150% crop mismatch.");
    var edge = SelectionGeometry.Visible(new(90, 40, 30, 20), 100, 50);
    Check(edge == new SelectionRect(90, 40, 10, 10), "Edge intersection mismatch.");
    Check(SelectionGeometry.PreviewCrop(edge, 100, 50, 100, 50) == new PixelCrop(90, 40, 10, 10), "Edge crop mismatch.");
    Check(SelectionGeometry.PreviewCrop(new(0, 0, 10, 10), 0, 100, 100, 100).IsEmpty, "Zero surface still cropped.");
});
Test("Capture pixels keep the overlay commit rounding", () =>
{
    var pixels = SelectionGeometry.ToCapturePixels(100, 100, 320, 250);
    Check(pixels == new CapturePixels(100, 100, 220, 150), "Integer drag changed size.");
    pixels = SelectionGeometry.ToCapturePixels(100.2, 100.6, 320.4, 250.2);
    Check(pixels == new CapturePixels(100, 100, 220, 150), "Fractional screen points drifted.");
    Check(!SelectionGeometry.IsTooSmall(3, 3) && SelectionGeometry.IsTooSmall(2.9, 40), "Minimum drag size changed.");
    Check(SelectionGeometry.IsScrollTooSmall(23, 40) && SelectionGeometry.IsScrollTooSmall(24, 39) && !SelectionGeometry.IsScrollTooSmall(24, 40), "Scroll minimum changed.");
    Check(SelectionGeometry.MeasuredPixels(960, 540, 2) == (1920, 1080), "DPI label scale changed.");
});
Test("Pointer bursts schedule one overlay frame", () =>
{
    var gate = new OverlayFrameGate();
    var scheduled = 0;
    SelectionRect latest = default;
    for (var i = 0; i < 40; i++)
    {
        latest = SelectionGeometry.FromDrag(5, 5, 10 + i, 8 + i, 800, 600);
        if (gate.Request()) scheduled++;
    }
    Check(scheduled == 1 && gate.IsPending, "Each move posted a frame.");
    Check(latest == new SelectionRect(5, 5, 44, 42), "Latest point was dropped.");
    gate.Release();
    Check(!gate.IsPending && gate.Request(), "Gate stayed closed.");
});
Test("Dim overlay darkens a copy and stays opaque", () =>
{
    var source = new PixelFrame(2, 1, [255, 0, 0, 10, 10, 20, 30, 0]);
    var dimmed = source.Dimmed(SelectionGeometry.OverlayAlpha);
    Check(SelectionGeometry.OverlayAlpha == 100, "Overlay alpha drifted.");
    Check(dimmed.Width == 2 && dimmed.Height == 1, "Dimmed size changed.");
    Check(dimmed.Pixels is [155, 0, 0, 255, 6, 12, 18, 255], "Dimmed color mismatch.");
    Check(source.Pixels is [255, 0, 0, 10, 10, 20, 30, 0], "Dimmed mutated the source.");
    var clear = source.Dimmed(0);
    Check(clear.Pixels is [255, 0, 0, 255, 10, 20, 30, 255], "Zero overlay changed RGB.");
});
Test("Selection chrome is the perimeter, not the filled rectangle", () =>
{
    bool Covers(SelectionRect edge, double x, double y) => x >= edge.X && y >= edge.Y && x < edge.Right && y < edge.Bottom;
    var area = new SelectionRect(0, 0, 800, 600);
    var edges = SelectionGeometry.Edges(area);
    Check(edges.Length == 4, "Expected four edges.");
    var edgeArea = edges.Sum(edge => edge.Width * edge.Height);
    Check(edgeArea * 20 < area.Width * area.Height, "800×600 edges cover the selection.");
    Check(edges.All(edge => edge.Width <= SelectionGeometry.EdgeThickness || edge.Height <= SelectionGeometry.EdgeThickness), "An edge is as thick as the selection.");
    var fullHd = new SelectionRect(0, 0, 1920, 1080);
    var hdEdges = SelectionGeometry.Edges(fullHd);
    Check(hdEdges.Sum(edge => edge.Width * edge.Height) * 50 < fullHd.Width * fullHd.Height, "1080p edges cover the selection.");
    Check(hdEdges.Any(edge => Covers(edge, 0, 0)) && hdEdges.Any(edge => Covers(edge, 1919, 1079)), "A 1080p corner is missing.");
    Check(!hdEdges.Any(edge => Covers(edge, 960, 540)), "The 1080p interior is part of the chrome.");
    Check(SelectionGeometry.Edges(default).Length == 0, "Empty selection still has chrome.");
    Check(SelectionGeometry.EdgeThickness == 2, "Edge thickness drifted.");
});
Test("Render flags stay opt-in and arguments win", () =>
{
    Check(RenderModeRequest.Resolve(null, null) == RenderModeRequest.Mode.Default, "Missing input changed the default.");
    Check(RenderModeRequest.Resolve([], "") == RenderModeRequest.Mode.Default, "Empty environment changed the default.");
    Check(RenderModeRequest.Resolve([], "auto") == RenderModeRequest.Mode.Default, "Auto selected a render mode.");
    Check(RenderModeRequest.Resolve([], "nope") == RenderModeRequest.Mode.Default, "Unknown environment selected a render mode.");
    Check(RenderModeRequest.Resolve([], "software") == RenderModeRequest.Mode.Software, "Software environment ignored.");
    Check(RenderModeRequest.Resolve([], "HARDWARE") == RenderModeRequest.Mode.Hardware, "Hardware environment ignored.");
    Check(RenderModeRequest.Resolve(["--software-render"], "hardware") == RenderModeRequest.Mode.Software, "Environment beat the flag.");
    Check(RenderModeRequest.Resolve(["--hardware-render", "--software-render"], null) == RenderModeRequest.Mode.Software, "The last flag did not win.");
    Check(RenderModeRequest.Resolve(["--software-render", "--hardware-render"], "software") == RenderModeRequest.Mode.Hardware, "The last flag did not win.");
    Check(RenderModeRequest.Resolve(["--background"], "software") == RenderModeRequest.Mode.Software, "Unrelated argument hid the environment.");
    Check(RenderModeRequest.EnvironmentVariable == "LUMASHOT_RENDER", "Render environment name changed.");
});
Test("Virtual and basic adapters are recognized by name", () =>
{
    string[] virtualOrBasic =
    [
        "Microsoft Basic Display Adapter", "VMware SVGA 3D", "Microsoft Hyper-V Video",
        "VirtualBox Graphics Adapter", "Parallels Display Adapter (WDDM)", "QEMU VirtIO GPU",
        "Red Hat QXL", "Indirect Display Driver", "Remote Display Adapter", "Virtual Display",
        "Bochs Standard VGA"
    ];
    foreach (var name in virtualOrBasic) Check(AdapterNames.IsVirtualOrBasic(name), $"Missed {name}.");
    foreach (var name in new[] { "NVIDIA GeForce RTX 3060", "Intel(R) UHD Graphics 770", "AMD Radeon RX 6600" })
        Check(!AdapterNames.IsVirtualOrBasic(name), $"Physical adapter {name} looked virtual.");
    Check(!AdapterNames.IsVirtualOrBasic(null) && !AdapterNames.IsVirtualOrBasic("  "), "Blank adapter name looked virtual.");
});
Test("Duration summary reports average, max, and p95", () =>
{
    var empty = DurationSummary.FromMilliseconds([]);
    Check(empty.Count == 0 && empty.Average == 0 && empty.Max == 0 && empty.P95 == 0, "Empty summary is not zero.");
    var one = DurationSummary.FromMilliseconds([4]);
    Check(one.Count == 1 && one.Average == 4 && one.Max == 4 && one.P95 == 4, "Single sample changed.");
    var ten = DurationSummary.FromMilliseconds([10, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    Check(ten.Count == 10 && Math.Abs(ten.Average - 5.5) < 1e-9 && ten.Max == 10 && ten.P95 == 10, "Ten-sample p95 mismatch.");
    var twenty = DurationSummary.FromMilliseconds(Enumerable.Range(1, 20).Select(value => (double)value).ToArray());
    Check(twenty.Max == 20 && twenty.P95 == 19, "Twenty-sample p95 mismatch.");
});
Console.WriteLine($"{passed} core checks passed.");
