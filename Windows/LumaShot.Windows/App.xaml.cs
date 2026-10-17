using System.IO;
using System.Threading;
using System.Windows;
using LumaShot.Windows.Platform;
using LumaShot.Windows.Services;

namespace LumaShot.Windows;

public partial class App : Application
{
    private Mutex? instance;
    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if (e.Args.Length >= 2 && e.Args[0] == "--smoke-test")
        {
            try { await Diagnostics.SmokeTests.Run(e.Args[1]); Shutdown(0); }
            catch (Exception ex) { Directory.CreateDirectory(e.Args[1]); File.WriteAllText(Path.Combine(e.Args[1], "failure.txt"), ex.ToString()); Shutdown(1); }
            return;
        }
        instance = new Mutex(true, @"Local\LumaShot.Windows", out var first);
        if (!first)
        {
            var existing = Native.FindWindow(null, "拾光截图 · LumaShot");
            if (existing != 0) { Native.ShowWindow(existing, 9); Native.SetForegroundWindow(existing); }
            Shutdown(); return;
        }
        try
        {
            var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "LumaShot");
            var controller = new AppController(root); var window = new MainWindow(controller); controller.Main = window; MainWindow = window;
            controller.Desktop = new DesktopIntegration(window, controller.Capture, controller.ShowMain, controller.Quit); window.RefreshStatus();
            if (!e.Args.Contains("--background")) window.Show();
            Exit += (_, _) => { controller.Desktop.Dispose(); instance.Dispose(); };
        }
        catch (Exception ex) { MessageBox.Show(ex.Message, "LumaShot 启动失败"); Shutdown(1); }
    }
}
