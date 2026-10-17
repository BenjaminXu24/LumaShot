using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;

namespace LumaShot.Windows.Platform;

internal sealed class DesktopIntegration : IDisposable
{
    private readonly nint handle;
    private readonly HwndSource source;
    private readonly Action<int> capture;
    private readonly Action show;
    private readonly Action quit;
    private readonly List<int> registered = [];
    private nint icon;
    private bool disposed;
    private readonly uint taskbarCreated;
    public Action? Cancel { get; set; }
    public List<string> Conflicts { get; } = [];
    private const int TrayMessage = 0x8001;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct IconData
    {
        public uint Size; public nint Window; public uint Id, Flags, Callback; public nint Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Tip;
        public uint State, StateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Info;
        public uint Timeout;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string InfoTitle;
        public uint InfoFlags; public Guid Guid; public nint BalloonIcon;
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] private static extern bool Shell_NotifyIcon(uint message, ref IconData data);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] private static extern uint ExtractIconEx(string file, int index, out nint large, out nint small, uint count);
    [DllImport("user32.dll")] private static extern bool DestroyIcon(nint icon);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern uint RegisterWindowMessage(string message);

    public DesktopIntegration(Window window, Action<int> capture, Action show, Action quit)
    {
        this.capture = capture; this.show = show; this.quit = quit;
        handle = new WindowInteropHelper(window).EnsureHandle(); source = HwndSource.FromHwnd(handle); source.AddHook(Hook);
        for (var i = 1; i <= 4; i++)
        {
            if (Native.RegisterHotKey(handle, i, 0x4006, (uint)('0' + i))) registered.Add(i);
            else Conflicts.Add($"Ctrl + Shift + {i} 已被其他应用占用，可使用界面或托盘菜单截图。");
        }
        taskbarCreated = RegisterWindowMessage("TaskbarCreated");
        ExtractIconEx(Environment.ProcessPath!, 0, out var large, out icon, 1);
        if (large != 0) DestroyIcon(large);
        AddIcon();
    }
    private IconData Data() => new() { Size = (uint)Marshal.SizeOf<IconData>(), Window = handle, Id = 1, Flags = 7, Callback = TrayMessage, Icon = icon, Tip = "拾光截图 · LumaShot", Info = "", InfoTitle = "" };
    private void AddIcon() { var data = Data(); Shell_NotifyIcon(0, ref data); }
    public void EnableEscape(bool enabled)
    {
        Native.UnregisterHotKey(handle, 10);
        if (enabled) Native.RegisterHotKey(handle, 10, 0x4000, 0x1B);
    }
    private nint Hook(nint window, int message, nint wParam, nint lParam, ref bool handled)
    {
        if ((uint)message == taskbarCreated) AddIcon();
        if (message == 0x312)
        {
            var id = (int)wParam; handled = true;
            if (id == 10) Cancel?.Invoke(); else if (id is >= 1 and <= 4) capture(id);
        }
        if (message == TrayMessage)
        {
            if ((int)lParam == 0x203) show();
            if ((int)lParam == 0x205)
            {
                Native.SetForegroundWindow(handle);
                var menu = new ContextMenu();
                void Add(string name, Action action) { var item = new MenuItem { Header = name }; item.Click += (_, _) => action(); menu.Items.Add(item); }
                Add("打开拾光截图", show); menu.Items.Add(new Separator());
                var names = new[] { "区域截图", "窗口截图", "全屏截图", "滚动长截图" };
                for (var i = 0; i < names.Length; i++) { var id = i + 1; Add($"{names[i]}     Ctrl+Shift+{id}", () => capture(id)); }
                menu.Items.Add(new Separator()); Add("退出", quit); menu.IsOpen = true;
            }
        }
        return 0;
    }
    public void Dispose()
    {
        if (disposed) return; disposed = true;
        foreach (var id in registered) Native.UnregisterHotKey(handle, id);
        Native.UnregisterHotKey(handle, 10); var data = Data(); Shell_NotifyIcon(2, ref data);
        if (icon != 0) { DestroyIcon(icon); icon = 0; }
        source.RemoveHook(Hook);
    }
}
