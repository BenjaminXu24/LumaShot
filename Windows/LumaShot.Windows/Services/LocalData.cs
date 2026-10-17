using System.IO;
using System.Text.Json;
using System.Windows.Media.Imaging;
using LumaShot.Core;
using Microsoft.Win32;

namespace LumaShot.Windows.Services;

internal sealed record CaptureItem(Guid Id, string Filename, string Mode, DateTimeOffset CreatedAt, int Width, int Height)
{
    public string Description => $"{Mode}  ·  {Width:N0} × {Height:N0}";
    public string Date => CreatedAt.LocalDateTime.ToString("MM月dd日 HH:mm");
}

internal sealed class CaptureStore
{
    public string DirectoryPath { get; }
    public IReadOnlyList<CaptureItem> Items => items;
    private List<CaptureItem> items = [];
    private readonly Dictionary<Guid, BitmapSource> thumbnails = [];
    private string IndexPath => Path.Combine(DirectoryPath, "index.json");
    public event Action? Changed;
    public CaptureStore(string root)
    {
        DirectoryPath = Path.Combine(root, "Captures"); Directory.CreateDirectory(DirectoryPath);
        try
        {
            if (File.Exists(IndexPath)) items = (JsonSerializer.Deserialize<List<CaptureItem>>(File.ReadAllText(IndexPath)) ?? [])
                .Where(i => Safe(i.Filename) && i.Width > 0 && i.Height > 0 && File.Exists(Path.Combine(DirectoryPath, i.Filename)))
                .DistinctBy(i => i.Id).OrderByDescending(i => i.CreatedAt).Take(100).ToList();
        }
        catch (JsonException) { /* Keep damaged metadata for recovery; new captures can still be added. */ }
    }
    private static bool Safe(string filename) => Path.GetFileName(filename) == filename && filename.EndsWith(".png", StringComparison.OrdinalIgnoreCase);
    private void Persist(List<CaptureItem> updated)
    {
        var temp = IndexPath + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(updated, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temp, IndexPath, true);
    }
    public void Add(PixelFrame frame, string mode)
    {
        var id = Guid.NewGuid(); var item = new CaptureItem(id, $"{id}.png", mode, DateTimeOffset.Now, frame.Width, frame.Height);
        var path = Path.Combine(DirectoryPath, item.Filename);
        File.WriteAllBytes(path, ImageCodec.Png(ImageCodec.Bitmap(frame)));
        var updated = items.Prepend(item).Take(100).ToList();
        try { Persist(updated); } catch { File.Delete(path); throw; }
        var expired = items.Where(i => !updated.Any(n => n.Id == i.Id)).ToList(); items = updated;
        foreach (var old in expired) { thumbnails.Remove(old.Id); TryDelete(old.Filename); }
        Changed?.Invoke();
    }
    public PixelFrame Load(CaptureItem item) => Safe(item.Filename) ? ImageCodec.Load(Path.Combine(DirectoryPath, item.Filename)) : throw new IOException("无效的图片名称。");
    public BitmapSource Thumbnail(CaptureItem item)
    {
        if (!Safe(item.Filename)) throw new IOException("无效的图片名称。");
        if (thumbnails.TryGetValue(item.Id, out var image)) return image;
        if (thumbnails.Count >= 40) thumbnails.Clear();
        return thumbnails[item.Id] = ImageCodec.Thumbnail(Path.Combine(DirectoryPath, item.Filename));
    }
    public void Delete(CaptureItem item)
    {
        var updated = items.Where(i => i.Id != item.Id).ToList(); Persist(updated); items = updated;
        thumbnails.Remove(item.Id); TryDelete(item.Filename); Changed?.Invoke();
    }
    public void Clear()
    {
        Persist([]); var old = items; items = []; thumbnails.Clear();
        foreach (var item in old) TryDelete(item.Filename); Changed?.Invoke();
    }
    private void TryDelete(string filename) { if (Safe(filename)) try { File.Delete(Path.Combine(DirectoryPath, filename)); } catch (IOException) { } }
}

internal sealed class Preferences
{
    public bool AutoCopy { get; set; }
    public bool Sound { get; set; } = true;
    public int Delay { get; set; }
    public bool LaunchAtLogin { get; set; }
    public static Preferences Load(string root)
    {
        try { return JsonSerializer.Deserialize<Preferences>(File.ReadAllText(Path.Combine(root, "settings.json"))) ?? new(); }
        catch (Exception ex) when (ex is IOException or JsonException) { return new(); }
    }
    public void Save(string root)
    {
        Directory.CreateDirectory(root); var path = Path.Combine(root, "settings.json");
        File.WriteAllText(path + ".tmp", JsonSerializer.Serialize(this)); File.Move(path + ".tmp", path, true);
    }
    public static bool IsLoginEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        return key?.GetValue("LumaShot") is string value && value == $"\"{Environment.ProcessPath}\" --background";
    }
    public static void SetLogin(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        if (enabled) key.SetValue("LumaShot", $"\"{Environment.ProcessPath}\" --background"); else key.DeleteValue("LumaShot", false);
    }
}
