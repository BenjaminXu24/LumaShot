using System.Globalization;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows;
using System.Windows.Media;
using LumaShot.Core;
using LumaShot.Windows.Platform;

namespace LumaShot.Windows.Capture;

/// <summary>Daily diagnostic log. One line per stage. No pixels, window titles, or account names.</summary>
internal static class DiagnosticsLog
{
    public const int MaxBytes = 512 * 1024;
    private const int Rotations = 3;

    public static string DailyPath(string root, DateTime? day = null) =>
        Path.Combine(root, "logs", $"diagnostics-{(day ?? DateTime.Now):yyyyMMdd}.log");

    public static void Write(string? path, string message)
    {
        if (string.IsNullOrWhiteSpace(path)) return;
        try
        {
            var directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(directory))
            {
                Directory.CreateDirectory(directory);
                TrimOld(directory);
            }
            Rotate(path);
            File.AppendAllText(path, $"{DateTimeOffset.Now:O}\t{message}{Environment.NewLine}");
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }

    public static string Tier()
    {
        var raw = RenderCapability.Tier;
        var tier = raw >> 16;
        var kind = tier switch { 0 => "软件", 1 => "部分硬件", _ => "硬件" };
        return $"{tier}（{kind}，原始={raw}）";
    }

    public static string ActualRenderMode() => System.Windows.Media.RenderOptions.ProcessRenderMode.ToString();

    public static string Version()
    {
        var assembly = typeof(DiagnosticsLog).Assembly;
        var informational = assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
        return string.IsNullOrWhiteSpace(informational) ? assembly.GetName().Version?.ToString() ?? "0.1.0" : informational;
    }

    public static string StartupReport(RenderModeRequest.Mode requested)
    {
        bool? remoteWpf = null;
        try { remoteWpf = SystemParameters.IsRemoteSession; } catch (Exception) { }
        var virtualScreen = Native.VirtualScreen();
        var builder = new StringBuilder();
        builder.Append("启动");
        builder.Append(" 版本=").Append(Version());
        builder.Append(" 系统=").Append(System.Runtime.InteropServices.RuntimeInformation.OSDescription);
        builder.Append(" 进程=").Append(System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture);
        builder.Append(" 渲染层=").Append(Tier());
        builder.Append(" 请求渲染=").Append(Requested(requested));
        builder.Append(" 实际渲染=").Append(ActualRenderMode());
        builder.Append(" 远程会话=").Append(Native.IsRemoteSession() ? "是" : "否");
        builder.Append(" WPF远程=").Append(remoteWpf switch { true => "是", false => "否", _ => "未知" });
        builder.Append(" 虚拟屏幕=").Append(virtualScreen.Width).Append('×').Append(virtualScreen.Height).Append('@').Append(virtualScreen.X).Append(',').Append(virtualScreen.Y);
        builder.Append(" 显示器=[");
        var monitors = Native.Monitors();
        if (monitors.Count == 0) builder.Append("无");
        else builder.Append(string.Join("; ", monitors.Select(monitor =>
            $"{monitor.Bounds.Width}×{monitor.Bounds.Height}@{monitor.Bounds.X},{monitor.Bounds.Y} dpi={monitor.DpiX}/{monitor.DpiY} scale={monitor.ScaleX.ToString("0.###", CultureInfo.InvariantCulture)}×{monitor.ScaleY.ToString("0.###", CultureInfo.InvariantCulture)}")));
        builder.Append("] 显卡=[");
        var adapters = Native.Adapters();
        if (adapters.Count == 0) builder.Append("无");
        else builder.Append(string.Join("; ", adapters.Select(adapter =>
            $"{adapter.Name} 驱动={adapter.DriverVersion ?? "未知"} 活动={(adapter.Active ? "是" : "否")} 虚拟或基本={(adapter.VirtualOrBasic ? "是" : "否")}")));
        builder.Append(']');
        return builder.ToString();
    }

    public static string Requested(RenderModeRequest.Mode mode) => mode switch
    {
        RenderModeRequest.Mode.Software => "软件",
        RenderModeRequest.Mode.Hardware => "硬件",
        _ => "默认"
    };

    public static string Stats(string name, int total, ReadOnlySpan<double> samples)
    {
        var summary = DurationSummary.FromMilliseconds(samples);
        return $"{name} 样本={summary.Count}/{total} avg={summary.Average.ToString("0.###", CultureInfo.InvariantCulture)} max={summary.Max.ToString("0.###", CultureInfo.InvariantCulture)} p95={summary.P95.ToString("0.###", CultureInfo.InvariantCulture)}";
    }

    private static void Rotate(string path)
    {
        var info = new FileInfo(path);
        if (!info.Exists || info.Length <= MaxBytes) return;
        for (var generation = Rotations; generation >= 1; generation--)
        {
            var older = path + "." + generation;
            var newer = generation == 1 ? path : path + "." + (generation - 1);
            if (File.Exists(older)) File.Delete(older);
            if (File.Exists(newer)) File.Move(newer, older);
        }
    }

    private static void TrimOld(string directory)
    {
        var cutoff = DateTime.Today.AddDays(-6);
        foreach (var file in Directory.EnumerateFiles(directory, "diagnostics-*.log*"))
        {
            var name = Path.GetFileName(file);
            if (name.Length < 20 || !DateTime.TryParseExact(name.AsSpan(12, 8), "yyyyMMdd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var day)) continue;
            if (day < cutoff) File.Delete(file);
        }
    }
}
