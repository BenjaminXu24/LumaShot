using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LumaShot.Core;
using LumaShot.Windows.Capture;
using LumaShot.Windows.Editor;
using LumaShot.Windows.Platform;
using LumaShot.Windows.Services;

namespace LumaShot.Windows.Diagnostics;

internal static class SmokeTests
{
    private static readonly List<string> checks = [];
    private static void Check(bool condition, string name) { if (!condition) throw new Exception(name); checks.Add(name); }
    private static void SaveWindow(Window window, string path)
    {
        window.UpdateLayout(); var visual = window.Content as FrameworkElement ?? throw new Exception("Window content missing.");
        var width = (int)Math.Ceiling(visual.ActualWidth); var height = (int)Math.Ceiling(visual.ActualHeight);
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        var background = new DrawingVisual();
        using (var dc = background.RenderOpen()) dc.DrawRectangle(window.Background, null, new(0, 0, width, height));
        bitmap.Render(background); bitmap.Render(visual);
        ImageCodec.Save(bitmap, path);
    }
    public static async Task Run(string directory)
    {
        Directory.CreateDirectory(directory);
        var controller = new AppController(Path.Combine(directory, "isolated-data")) { InteractiveErrors = false };
        var main = new MainWindow(controller); controller.Main = main; Application.Current.MainWindow = main;
        using var desktop = new DesktopIntegration(main, controller.Capture, controller.ShowMain, () => { }); controller.Desktop = desktop;
        main.Show(); await Task.Delay(350); SaveWindow(main, Path.Combine(directory, "01-home.png"));
        main.SelectPage(2); await Task.Delay(150); SaveWindow(main, Path.Combine(directory, "02-settings.png")); main.SelectPage(0);
        Check(desktop.Conflicts.Count == 0, "Global shortcuts registered");
        var demo = DemoArtwork.Create(); var editor = new EditorWindow(demo);
        editor.Canvas.Document.Add(new(AnnotationTool.Rectangle, [new(140, 420), new(515, 720)]));
        editor.Canvas.Document.Add(new(AnnotationTool.Arrow, [new(1160, 350), new(990, 450)], 0xFFEF5264, 7));
        editor.Canvas.Document.Add(new(AnnotationTool.Text, [new(555, 752)], Text: "Windows 原生截图 · 让重点更清晰", FontSize: 24));
        editor.Show(); await Task.Delay(250); SaveWindow(editor, Path.Combine(directory, "03-editor.png"));
        var rendered = editor.Canvas.Export(); var png = Path.Combine(directory, "annotated.png"); ImageCodec.Save(rendered, png); ImageCodec.Save(rendered, Path.Combine(directory, "annotated.jpg")); editor.MarkExported();
        Check(ImageCodec.Load(png).Width == demo.Width && ImageCodec.Load(png).Height == demo.Height, "Export preserves native pixels");
        var roundTrip = ImageCodec.Frame(rendered); Check(!roundTrip.Pixels.SequenceEqual(demo.Pixels), "Annotation changes exported pixels");
        var mosaic = new Annotation(AnnotationTool.Mosaic, [new(130, 220), new(1000, 390)], StrokeWidth: 10);
        var masked = ImageCodec.Frame(AnnotationRenderer.Render(demo, [mosaic])); Check(!masked.Pixels.SequenceEqual(demo.Pixels), "Mosaic changes output bitmap");
        await ImageCodec.CopyAsync(rendered); Check(Clipboard.ContainsImage() && Clipboard.GetImage()?.PixelWidth == demo.Width && Clipboard.GetData("PNG") is not null, "Native bitmap and PNG clipboard export");
        editor.Close();
        for (var i = 0; i < 103; i++) controller.Store.Add(new(2, 2, Enumerable.Repeat((byte)255, 16).ToArray()), "测试");
        Check(controller.Store.Items.Count == 100 && new CaptureStore(Path.Combine(directory, "isolated-data")).Items.Count == 100, "History retention and persistence");
        controller.Store.Delete(controller.Store.Items[0]); Check(controller.Store.Items.Count == 99, "History delete updates index"); controller.Store.Clear();
        var old = controller.Store.Items.Count; Native.TestHotkey(0x33);
        var deadline = DateTime.UtcNow.AddSeconds(12);
        while (controller.Store.Items.Count == old && DateTime.UtcNow < deadline) await Task.Delay(150);
        Check(controller.Store.Items.Count == old + 1, "Actual global hotkey triggers desktop capture");
        Check(controller.Store.Items[0].Width > 0 && controller.Store.Items[0].Height > 0, "Actual GDI screenshot bitmap");
        foreach (var existing in Application.Current.Windows.OfType<EditorWindow>().ToList()) existing.Close();
        main.Hide();
        var viewer = new ScrollViewer { Content = new Fixture(), VerticalScrollBarVisibility = ScrollBarVisibility.Hidden, CanContentScroll = false, Background = Brushes.White };
        var fixture = new Window { Title = "LumaShot Windows scroll fixture", Content = viewer, Width = 760, Height = 590, Left = 70, Top = 70, Topmost = true };
        fixture.Show(); fixture.Activate(); await Task.Delay(300);
        var display = Native.PointerDisplay();
        var selected = new TaskCompletionSource<Selection?>();
        var regionOverlay = new SelectionWindow(display, Native.Capture(display), [], 1);
        regionOverlay.Selected += value => selected.TrySetResult(value); regionOverlay.Show(); await Task.Delay(200);
        await Native.TestDrag(new(display.X + 100, display.Y + 100, 220, 150));
        var region = await selected.Task.WaitAsync(TimeSpan.FromSeconds(5)); regionOverlay.Close();
        Check(region is not null && Math.Abs(region.Bounds.Width - 220) <= 1 && Math.Abs(region.Bounds.Height - 150) <= 1, "Actual region overlay drag preserves physical coordinates");
        var fixtureHandle = new WindowInteropHelper(fixture).Handle;
        var windowTarget = new DesktopWindow(fixtureHandle, new(display.X + 70, display.Y + 70, 760, 590), "fixture");
        selected = new(); var windowOverlay = new SelectionWindow(display, Native.Capture(display), [windowTarget], 2);
        windowOverlay.Selected += value => selected.TrySetResult(value); windowOverlay.Show(); await Task.Delay(200);
        await Native.TestDrag(new(display.X + 150, display.Y + 150, 0, 0));
        var chosenWindow = await selected.Task.WaitAsync(TimeSpan.FromSeconds(5)); windowOverlay.Close();
        Check(chosenWindow?.TargetWindow == fixtureHandle && chosenWindow.Bounds == windowTarget.Bounds, "Actual window hover and click selects target");
        fixture.Activate(); await Task.Delay(150);
        var first = viewer.PointToScreen(new Point(5, 5)); var last = viewer.PointToScreen(new Point(viewer.ActualWidth - 5, viewer.ActualHeight - 5));
        var bounds = new PixelRect((int)first.X, (int)first.Y, (int)(last.X - first.X), (int)(last.Y - first.Y));
        using var session = new ScrollSession(new(bounds, new WindowInteropHelper(fixture).Handle), Native.Capture(bounds));
        PixelFrame? longImage = null; session.Finished += frame => longImage = frame; session.StartAutomatic();
        deadline = DateTime.UtcNow.AddSeconds(55);
        while (session.IsAutomatic && DateTime.UtcNow < deadline) await Task.Delay(200);
        Check(!session.IsAutomatic && session.Status.Contains("停止滚动"), "Automatic scroll reaches bottom and pauses");
        Check(session.FrameCount >= 3 && session.TotalHeight > bounds.Height * 1.5 && viewer.VerticalOffset > 0, "SendInput and real multi-frame stitching");
        session.Finish(); Check(longImage is not null, "Finish returns stitched bitmap");
        ImageCodec.Save(ImageCodec.Bitmap(longImage!), Path.Combine(directory, "04-scroll-result.png"));
        var scrollFrames = session.FrameCount; var scrollHeight = session.TotalHeight;
        fixture.Close(); main.Show(); main.SelectPage(1); await Task.Delay(150); SaveWindow(main, Path.Combine(directory, "05-history.png"));
        controller.Store.Clear(); desktop.Dispose();
        File.WriteAllText(Path.Combine(directory, "checks.json"), JsonSerializer.Serialize(new { passed = checks, scrollFrames, scrollHeight, os = Environment.OSVersion.ToString(), framework = Environment.Version.ToString() }, new JsonSerializerOptions { WriteIndented = true }));
    }

    private sealed class Fixture : FrameworkElement
    {
        public Fixture() { Width = 720; Height = 1300; }
        protected override void OnRender(DrawingContext dc)
        {
            dc.DrawRectangle(Brushes.White, null, new(0,0,Width,Height));
            for (var row = 0; row < 10; row++)
            {
                dc.DrawRectangle(new SolidColorBrush(Color.FromRgb((byte)(225 + row % 3 * 8), (byte)(220 + row % 4 * 7), (byte)(245 - row % 5 * 5))), null, new(0,row*105,Width,105));
                var text = new FormattedText($"SECTION {row+1:00} — LumaShot Windows\nNative screen capture, original pixels, clear ideas.", System.Globalization.CultureInfo.InvariantCulture, FlowDirection.LeftToRight, new Typeface("Segoe UI"), 20, Brushes.Black, VisualTreeHelper.GetDpi(this).PixelsPerDip);
                dc.DrawText(text,new Point(25,row*105+16));
                for (var col = 0; col < 25; col++) dc.DrawRectangle(new SolidColorBrush(Color.FromRgb((byte)((row*37+col*73)%230),(byte)((row*97+col*41)%230),(byte)((row*13+col*19)%230))),null,new(30+col*24,row*105+78,17,10));
            }
        }
    }
}
