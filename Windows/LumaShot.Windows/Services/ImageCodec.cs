using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using LumaShot.Core;

namespace LumaShot.Windows.Services;

internal static class ImageCodec
{
    public static BitmapSource Bitmap(PixelFrame frame)
    {
        var source = BitmapSource.Create(frame.Width, frame.Height, 96, 96, PixelFormats.Bgra32, null, frame.Pixels, frame.Stride);
        source.Freeze(); return source;
    }
    public static PixelFrame Frame(BitmapSource source)
    {
        if ((long)source.PixelWidth * source.PixelHeight > PixelFrame.MaximumPixels) throw new InvalidOperationException("图片超过 8,000 万像素上限。");
        var converted = new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
        var data = new byte[checked(converted.PixelWidth * converted.PixelHeight * 4)];
        converted.CopyPixels(data, converted.PixelWidth * 4, 0);
        return new(converted.PixelWidth, converted.PixelHeight, data);
    }
    public static PixelFrame Load(string path)
    {
        using var stream = File.OpenRead(path);
        var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat | BitmapCreateOptions.DelayCreation, BitmapCacheOption.OnDemand);
        return Frame(decoder.Frames[0]);
    }
    public static BitmapSource Thumbnail(string path)
    {
        using var stream = File.OpenRead(path);
        var header = BitmapDecoder.Create(stream, BitmapCreateOptions.DelayCreation, BitmapCacheOption.OnDemand).Frames[0];
        var scale = Math.Min(1, Math.Min(360.0 / header.PixelWidth, 216.0 / header.PixelHeight));
        var width = Math.Max(1, (int)Math.Round(header.PixelWidth * scale));
        var height = Math.Max(1, (int)Math.Round(header.PixelHeight * scale));
        stream.Position = 0;
        var bitmap = new BitmapImage(); bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad;
        bitmap.DecodePixelWidth = width; bitmap.DecodePixelHeight = height; bitmap.StreamSource = stream; bitmap.EndInit(); bitmap.Freeze(); return bitmap;
    }
    public static byte[] Png(BitmapSource source)
    {
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(source));
        using var stream = new MemoryStream(); encoder.Save(stream); return stream.ToArray();
    }
    public static void Save(BitmapSource source, string path)
    {
        BitmapEncoder encoder = Path.GetExtension(path).Equals(".jpg", StringComparison.OrdinalIgnoreCase)
            || Path.GetExtension(path).Equals(".jpeg", StringComparison.OrdinalIgnoreCase) ? new JpegBitmapEncoder { QualityLevel = 92 } : new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(source));
        var temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { using (var stream = File.Create(temp)) encoder.Save(stream); File.Move(temp, path, true); }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
    public static bool SaveDialog(Window owner, BitmapSource source)
    {
        var downloads = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
        var dialog = new SaveFileDialog { Title = "保存标注图片", FileName = $"LumaShot-{DateTime.Now:yyyyMMdd-HHmmss}.png", Filter = "PNG 图片|*.png|JPEG 图片|*.jpg", DefaultExt = ".png", AddExtension = true, InitialDirectory = Directory.Exists(downloads) ? downloads : Environment.GetFolderPath(Environment.SpecialFolder.MyPictures) };
        if (dialog.ShowDialog(owner) != true) return false;
        Save(source, dialog.FileName); return true;
    }
    public static async Task CopyAsync(BitmapSource source)
    {
        var png = Png(source);
        for (var attempt = 0; ; attempt++)
        {
            try
            {
                var data = new DataObject(); data.SetImage(source); data.SetData("PNG", new MemoryStream(png, false));
                Clipboard.SetDataObject(data, true); return;
            }
            catch (COMException) when (attempt < 3) { await Task.Delay(100); }
        }
    }
}
