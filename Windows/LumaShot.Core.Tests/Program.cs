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
Console.WriteLine($"{passed} core checks passed.");
