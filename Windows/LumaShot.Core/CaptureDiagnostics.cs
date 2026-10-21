namespace LumaShot.Core;

/// <summary>Opt-in render mode. The default leaves <c>ProcessRenderMode</c> untouched.</summary>
public static class RenderModeRequest
{
    public const string EnvironmentVariable = "LUMASHOT_RENDER";

    public enum Mode { Default, Software, Hardware }

    /// <summary>Command-line flags win over the environment variable. The last flag wins. Unknown values stay on the default.</summary>
    public static Mode Resolve(IReadOnlyList<string>? args, string? environmentValue)
    {
        var fromArgs = Mode.Default;
        var sawFlag = false;
        if (args is not null)
        {
            foreach (var arg in args)
            {
                if (arg.Equals("--software-render", StringComparison.OrdinalIgnoreCase)) { fromArgs = Mode.Software; sawFlag = true; }
                else if (arg.Equals("--hardware-render", StringComparison.OrdinalIgnoreCase)) { fromArgs = Mode.Hardware; sawFlag = true; }
            }
        }
        if (sawFlag) return fromArgs;
        if (string.IsNullOrWhiteSpace(environmentValue) || environmentValue.Equals("auto", StringComparison.OrdinalIgnoreCase)) return Mode.Default;
        if (environmentValue.Equals("software", StringComparison.OrdinalIgnoreCase)) return Mode.Software;
        if (environmentValue.Equals("hardware", StringComparison.OrdinalIgnoreCase)) return Mode.Hardware;
        return Mode.Default;
    }
}

/// <summary>Names that usually mean a basic or virtual display adapter. Detection is for logs only.</summary>
public static class AdapterNames
{
    public static bool IsVirtualOrBasic(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return false;
        var text = name.ToLowerInvariant();
        return text.Contains("microsoft basic display", StringComparison.Ordinal)
            || text.Contains("basic display", StringComparison.Ordinal)
            || text.Contains("vmware", StringComparison.Ordinal)
            || text.Contains("svga", StringComparison.Ordinal)
            || text.Contains("hyper-v", StringComparison.Ordinal)
            || text.Contains("virtualbox", StringComparison.Ordinal)
            || text.Contains("parallels", StringComparison.Ordinal)
            || text.Contains("qemu", StringComparison.Ordinal)
            || text.Contains("virtio", StringComparison.Ordinal)
            || text.Contains("qxl", StringComparison.Ordinal)
            || text.Contains("red hat", StringComparison.Ordinal)
            || text.Contains("indirect display", StringComparison.Ordinal)
            || text.Contains("remote display", StringComparison.Ordinal)
            || text.Contains("virtual display", StringComparison.Ordinal)
            || text.Contains("bochs", StringComparison.Ordinal)
            || text.Contains("standard vga", StringComparison.Ordinal);
    }
}

/// <summary>Count, average, max, and nearest-rank p95 for a set of millisecond samples.</summary>
public readonly record struct DurationSummary(int Count, double Average, double Max, double P95)
{
    public static DurationSummary FromMilliseconds(ReadOnlySpan<double> samples)
    {
        if (samples.IsEmpty) return new(0, 0, 0, 0);
        var copy = samples.ToArray();
        Array.Sort(copy);
        double sum = 0;
        foreach (var sample in copy) sum += sample;
        var index = Math.Clamp((int)Math.Ceiling(copy.Length * 0.95) - 1, 0, copy.Length - 1);
        return new(copy.Length, sum / copy.Length, copy[^1], copy[index]);
    }
}
