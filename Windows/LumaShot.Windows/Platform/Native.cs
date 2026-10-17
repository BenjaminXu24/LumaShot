using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using LumaShot.Core;

namespace LumaShot.Windows.Platform;

public readonly record struct PixelRect(int X, int Y, int Width, int Height)
{
    public int Right => X + Width;
    public int Bottom => Y + Height;
    public bool Contains(int x, int y) => x >= X && x < Right && y >= Y && y < Bottom;
}
public readonly record struct DesktopWindow(nint Handle, PixelRect Bounds, string Title);

internal static class Native
{
    [StructLayout(LayoutKind.Sequential)] internal struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] internal struct Rect { public int Left, Top, Right, Bottom; public readonly PixelRect Pixels => new(Left, Top, Right - Left, Bottom - Top); }
    [StructLayout(LayoutKind.Sequential)] private struct BitmapInfo
    {
        public uint Size; public int Width, Height; public ushort Planes, BitCount;
        public uint Compression, SizeImage; public int XPelsPerMeter, YPelsPerMeter; public uint ClrUsed, ClrImportant;
    }
    [StructLayout(LayoutKind.Sequential)] private struct MouseInput { public int X, Y; public uint Data, Flags, Time; public nuint ExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] private struct KeyboardInput { public ushort Key, Scan; public uint Flags, Time; public nuint ExtraInfo; }
    [StructLayout(LayoutKind.Explicit)] private struct InputUnion { [FieldOffset(0)] public MouseInput Mouse; [FieldOffset(0)] public KeyboardInput Keyboard; }
    [StructLayout(LayoutKind.Sequential)] private struct Input { public uint Type; public InputUnion Value; }
    internal delegate bool EnumWindowsProc(nint window, nint parameter);
    private delegate bool MonitorProc(nint monitor, nint dc, ref Rect rect, nint data);

    [DllImport("user32.dll")] internal static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] internal static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] internal static extern bool SetForegroundWindow(nint window);
    [DllImport("user32.dll")] internal static extern bool ShowWindow(nint window, int command);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern nint FindWindow(string? className, string title);
    [DllImport("user32.dll")] internal static extern bool SetWindowPos(nint window, nint after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll", SetLastError = true)] internal static extern bool RegisterHotKey(nint window, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] internal static extern bool UnregisterHotKey(nint window, int id);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, nint parameter);
    [DllImport("user32.dll")] private static extern bool EnumDisplayMonitors(nint dc, nint clip, MonitorProc callback, nint data);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(nint window);
    [DllImport("user32.dll")] private static extern bool IsIconic(nint window);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(nint window, out uint process);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(nint window, out Rect rect);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(nint window, StringBuilder text, int length);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(nint window, uint attribute, out Rect value, int length);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(nint window, uint attribute, out int value, int length);
    [DllImport("user32.dll")] private static extern nint GetDC(nint window);
    [DllImport("user32.dll")] private static extern int ReleaseDC(nint window, nint dc);
    [DllImport("gdi32.dll")] private static extern nint CreateCompatibleDC(nint dc);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(nint dc);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(nint obj);
    [DllImport("gdi32.dll")] private static extern nint SelectObject(nint dc, nint obj);
    [DllImport("gdi32.dll")] private static extern nint CreateDIBSection(nint dc, ref BitmapInfo info, uint usage, out nint bits, nint section, uint offset);
    [DllImport("gdi32.dll", SetLastError = true)] private static extern bool BitBlt(nint target, int x, int y, int width, int height, nint source, int sx, int sy, uint operation);
    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, Input[] input, int size);

    internal static List<PixelRect> Displays()
    {
        var displays = new List<PixelRect>();
        MonitorProc callback = (nint monitor, nint dc, ref Rect rect, nint data) => { displays.Add(rect.Pixels); return true; };
        EnumDisplayMonitors(0, 0, callback, 0);
        if (displays.Count == 0) throw new InvalidOperationException("没有找到可用的显示器。");
        return displays;
    }
    internal static PixelRect PointerDisplay()
    {
        GetCursorPos(out var point); var displays = Displays();
        return displays.FirstOrDefault(r => r.Contains(point.X, point.Y), displays[0]);
    }
    internal static List<DesktopWindow> Windows()
    {
        var result = new List<DesktopWindow>();
        EnumWindows((window, _) =>
        {
            GetWindowThreadProcessId(window, out var pid);
            if (pid == Environment.ProcessId || !IsWindowVisible(window) || IsIconic(window)) return true;
            if (DwmGetWindowAttribute(window, 14, out int cloaked, sizeof(int)) == 0 && cloaked != 0) return true;
            if (DwmGetWindowAttribute(window, 9, out Rect rect, Marshal.SizeOf<Rect>()) != 0 && !GetWindowRect(window, out rect)) return true;
            if (rect.Right - rect.Left < 40 || rect.Bottom - rect.Top < 40) return true;
            var title = new StringBuilder(512); GetWindowText(window, title, title.Capacity);
            if (title.Length > 0) result.Add(new(window, rect.Pixels, title.ToString()));
            return true;
        }, 0);
        return result;
    }
    internal static PixelFrame Capture(PixelRect rect)
    {
        if (rect.Width <= 0 || rect.Height <= 0 || (long)rect.Width * rect.Height > PixelFrame.MaximumPixels)
            throw new InvalidOperationException("截图区域过大，请缩小到 8,000 万像素以内。");
        var source = GetDC(0); if (source == 0) throw new Win32Exception("无法读取当前桌面。");
        var dc = CreateCompatibleDC(source); nint bitmap = 0, old = 0;
        try
        {
            if (dc == 0) throw new Win32Exception("无法创建截图缓冲区。");
            var info = new BitmapInfo { Size = 40, Width = rect.Width, Height = -rect.Height, Planes = 1, BitCount = 32 };
            bitmap = CreateDIBSection(source, ref info, 0, out var bits, 0, 0);
            if (bitmap == 0 || bits == 0) throw new Win32Exception("截图缓冲区内存不足。");
            old = SelectObject(dc, bitmap);
            if (!BitBlt(dc, 0, 0, rect.Width, rect.Height, source, rect.X, rect.Y, 0x40CC0020))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "无法捕捉当前画面。");
            var pixels = new byte[checked(rect.Width * rect.Height * 4)]; Marshal.Copy(bits, pixels, 0, pixels.Length);
            for (var i = 3; i < pixels.Length; i += 4) pixels[i] = 255;
            return new(rect.Width, rect.Height, pixels);
        }
        finally
        {
            if (old != 0) SelectObject(dc, old);
            if (bitmap != 0) DeleteObject(bitmap);
            if (dc != 0) DeleteDC(dc);
            ReleaseDC(0, source);
        }
    }
    internal static bool ScrollAt(int x, int y, int ticks)
    {
        SetCursorPos(x, y);
        var input = new Input { Type = 0, Value = new InputUnion { Mouse = new MouseInput { Flags = 0x800, Data = unchecked((uint)(ticks * 120)) } } };
        return SendInput(1, [input], Marshal.SizeOf<Input>()) == 1;
    }
    internal static void TestHotkey(ushort key)
    {
        Input Key(ushort vk, bool up = false) => new() { Type = 1, Value = new InputUnion { Keyboard = new KeyboardInput { Key = vk, Flags = up ? 2u : 0u } } };
        Input[] input = [Key(0x11), Key(0x10), Key(key), Key(key, true), Key(0x10, true), Key(0x11, true)];
        if (SendInput((uint)input.Length, input, Marshal.SizeOf<Input>()) != input.Length) throw new Win32Exception("无法发送测试快捷键。");
    }
}
