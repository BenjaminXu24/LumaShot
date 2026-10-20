using System.IO;
using System.Windows.Media;

namespace LumaShot.Windows.Capture;

internal static class OverlayDiagnostics
{
    public static void Write(string? path, string message)
    {
        if (string.IsNullOrWhiteSpace(path)) return;
        try
        {
            var info = new FileInfo(path);
            if (info.Exists && info.Length > 256 * 1024) File.Delete(path);
            var raw = RenderCapability.Tier;
            var tier = raw >> 16;
            var kind = tier switch { 0 => "软件渲染", 1 => "部分硬件加速", _ => "硬件加速" };
            File.AppendAllText(path, $"{DateTimeOffset.Now:O}\t渲染层={tier}（{kind}，Tier原始值={raw}）\t{message}{Environment.NewLine}");
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }
}
