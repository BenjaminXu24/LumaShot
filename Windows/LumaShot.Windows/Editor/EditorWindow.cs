using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using LumaShot.Core;
using LumaShot.Windows.Services;

namespace LumaShot.Windows.Editor;

internal sealed class EditorWindow : Window
{
    internal AnnotationCanvas Canvas { get; }
    private readonly TextBlock status = new() { VerticalAlignment = VerticalAlignment.Center };
    private readonly Button undo = new() { Content = "↶", ToolTip = "撤销 · Ctrl+Z", Padding = new Thickness(12, 8, 12, 8) };
    private readonly Button redo = new() { Content = "↷", ToolTip = "重做 · Ctrl+Shift+Z", Padding = new Thickness(12, 8, 12, 8), Margin = new Thickness(6, 0, 0, 0) };
    private readonly Dictionary<AnnotationTool, Button> tools = [];
    private bool dirty;
    internal void MarkExported() => dirty = false;
    public EditorWindow(PixelFrame image)
    {
        Style = (Style)Application.Current.FindResource(typeof(Window));
        Title = "截图标注 · LumaShot"; Width = 1200; Height = 850; MinWidth = 900; MinHeight = 650; WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Canvas = new(image); Canvas.RequestText = PromptText;
        var layout = new DockPanel();
        var header = new DockPanel { Margin = new Thickness(22, 18, 22, 14) }; DockPanel.SetDock(header, Dock.Top);
        var actions = new StackPanel { Orientation = Orientation.Horizontal };
        var copy = new Button { Content = "复制图片", Style = (Style)FindResource("PrimaryButton"), Margin = new Thickness(10, 0, 0, 0) };
        var save = new Button { Content = "保存图片", Margin = new Thickness(8, 0, 0, 0) }; actions.Children.Add(undo); actions.Children.Add(redo); actions.Children.Add(save); actions.Children.Add(copy);
        DockPanel.SetDock(actions, Dock.Right); header.Children.Add(actions);
        var branding = new StackPanel(); branding.Children.Add(new TextBlock { Text = "截图标注", FontSize = 20, FontWeight = FontWeights.Bold });
        branding.Children.Add(new TextBlock { Text = $"{image.Width:N0} × {image.Height:N0}  ·  保留原始像素", FontSize = 12, Foreground = (Brush)FindResource("Muted"), Margin = new Thickness(0, 3, 0, 0) }); header.Children.Add(branding); layout.Children.Add(header);
        var toolbar = new WrapPanel { Margin = new Thickness(16, 0, 16, 12) }; DockPanel.SetDock(toolbar, Dock.Top);
        foreach (var (tool, label, key) in new[] { (AnnotationTool.Select,"选择","V"), (AnnotationTool.Arrow,"箭头","A"), (AnnotationTool.Rectangle,"矩形","R"), (AnnotationTool.Ellipse,"圆形","O"), (AnnotationTool.Pen,"画笔","P"), (AnnotationTool.Text,"文字","T"), (AnnotationTool.Number,"序号","N"), (AnnotationTool.Mosaic,"马赛克","M"), (AnnotationTool.Hand,"移动","H") })
        {
            var button = new Button { Content = label, ToolTip = $"{label} · {key}", Padding = new Thickness(12, 9, 12, 9), Margin = new Thickness(3) };
            button.Click += (_, _) => SetTool(tool); tools.Add(tool, button); toolbar.Children.Add(button);
        }
        toolbar.Children.Add(new Border { Width = 1, Height = 25, Background = (Brush)FindResource("Line"), Margin = new Thickness(12, 0, 10, 0) });
        foreach (var color in new uint[] { 0xFF7D59EF, 0xFFEF5264, 0xFFF4A443, 0xFF37A37D, 0xFF3E8BDD, 0xFF24283C, 0xFFFFFFFF })
        {
            var swatch = new Button { Width = 27, Height = 27, Padding = new Thickness(0), Margin = new Thickness(3), Background = new SolidColorBrush(AnnotationRenderer.Color(color)), ToolTip = $"#{color & 0xFFFFFF:X6}" };
            swatch.Click += (_, _) => { Canvas.StrokeColor = color; Canvas.RecolorSelected(); }; toolbar.Children.Add(swatch);
        }
        var widths = new ComboBox { ItemsSource = new[] { 2, 4, 6, 10, 16 }, SelectedItem = 4, MinWidth = 65, Margin = new Thickness(10, 2, 4, 2), ToolTip = "线宽" };
        widths.SelectionChanged += (_, _) => { Canvas.StrokeWidth = (int)widths.SelectedItem; Canvas.RecolorSelected(); }; toolbar.Children.Add(widths);
        var sizes = new ComboBox { ItemsSource = new[] { 18, 24, 28, 36, 48, 64 }, SelectedItem = 28, MinWidth = 65, Margin = new Thickness(4, 2, 4, 2), ToolTip = "文字大小" };
        sizes.SelectionChanged += (_, _) => { Canvas.FontSize = (int)sizes.SelectedItem; Canvas.RecolorSelected(); }; toolbar.Children.Add(sizes);
        var clear = new Button { Content = "清除", Margin = new Thickness(6, 2, 0, 2), Padding = new Thickness(10, 6, 10, 6), ToolTip = "清除所有标注，可撤销" }; clear.Click += (_, _) => Canvas.Document.Clear(); toolbar.Children.Add(clear); layout.Children.Add(toolbar);
        var footer = new DockPanel { Margin = new Thickness(22, 10, 22, 10) }; DockPanel.SetDock(footer, Dock.Bottom);
        var zoom = new StackPanel { Orientation = Orientation.Horizontal };
        var fit = new Button { Content = "适应", Padding = new Thickness(12, 5, 12, 5) }; fit.Click += (_, _) => Canvas.Fit();
        var actual = new Button { Content = "100%", Padding = new Thickness(12, 5, 12, 5), Margin = new Thickness(6, 0, 0, 0) }; actual.Click += (_, _) => Canvas.SetZoom(1);
        zoom.Children.Add(fit); zoom.Children.Add(actual); DockPanel.SetDock(zoom, Dock.Right); footer.Children.Add(zoom); footer.Children.Add(status); layout.Children.Add(footer);
        layout.Children.Add(new Border { Child = Canvas, BorderBrush = (Brush)FindResource("Line"), BorderThickness = new Thickness(0, 1, 0, 1) }); Content = layout;
        undo.Click += (_, _) => Canvas.Document.Undo(); redo.Click += (_, _) => Canvas.Document.Redo();
        copy.Click += async (_, _) => await Copy(); save.Click += (_, _) => Save();
        Canvas.Document.Changed += () => { dirty = true; Update(); }; Canvas.ViewChanged += Update;
        PreviewKeyDown += OnKey; Closing += (_, e) =>
        {
            if (!dirty) return;
            var result = MessageBox.Show(this, "标注尚未复制或保存，要先保存图片吗？", "保存标注", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
            e.Cancel = result == MessageBoxResult.Cancel || result == MessageBoxResult.Yes && !Save();
        };
        SetTool(AnnotationTool.Arrow); Update();
    }
    private void SetTool(AnnotationTool tool)
    {
        Canvas.Tool = tool;
        foreach (var pair in tools) { pair.Value.Background = (Brush)FindResource(pair.Key == tool ? "Accent" : "Line"); pair.Value.Foreground = pair.Key == tool ? Brushes.White : (Brush)FindResource("Ink"); }
        Canvas.Focus(); Update();
    }
    private void Update() { undo.IsEnabled = Canvas.Document.CanUndo; redo.IsEnabled = Canvas.Document.CanRedo; status.Text = $"{Canvas.Zoom:P0}  ·  Shift 约束形状  ·  Alt+拖动平移  ·  Ctrl+滚轮缩放"; }
    private async Task Copy()
    {
        try { await ImageCodec.CopyAsync(Canvas.Export()); dirty = false; status.Text = "✓ 已复制完整标注图，可直接粘贴"; }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "复制失败"); }
    }
    private bool Save()
    {
        try { if (!ImageCodec.SaveDialog(this, Canvas.Export())) return false; dirty = false; status.Text = "✓ 图片已保存到本地"; return true; }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "保存失败"); return false; }
    }
    private async void OnKey(object sender, KeyEventArgs e)
    {
        if (e.OriginalSource is TextBox) return;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control))
        {
            switch (e.Key)
            {
                case Key.C: e.Handled = true; await Copy(); break;
                case Key.S: e.Handled = true; Save(); break;
                case Key.Z: if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) Canvas.Document.Redo(); else Canvas.Document.Undo(); e.Handled = true; break;
                case Key.Y: Canvas.Document.Redo(); e.Handled = true; break;
                case Key.D0: Canvas.Fit(); e.Handled = true; break;
                case Key.D1: Canvas.SetZoom(1); e.Handled = true; break;
            }
            return;
        }
        if (e.Key == Key.Delete) { Canvas.DeleteSelected(); e.Handled = true; return; }
        AnnotationTool? tool = e.Key switch { Key.V => AnnotationTool.Select, Key.A => AnnotationTool.Arrow, Key.R => AnnotationTool.Rectangle, Key.O => AnnotationTool.Ellipse, Key.P => AnnotationTool.Pen, Key.T => AnnotationTool.Text, Key.N => AnnotationTool.Number, Key.M => AnnotationTool.Mosaic, Key.H => AnnotationTool.Hand, _ => null };
        if (tool is { } value) { SetTool(value); e.Handled = true; }
    }
    private string? PromptText()
    {
        var window = new Window { Title = "添加文字", Width = 420, Height = 255, Owner = this, WindowStartupLocation = WindowStartupLocation.CenterOwner, ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false };
        var text = new TextBox { AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, MinHeight = 115, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        var panel = new StackPanel { Margin = new Thickness(20) }; panel.Children.Add(text);
        var add = new Button { Content = "添加文字", Style = (Style)FindResource("PrimaryButton"), HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0) };
        add.Click += (_, _) => window.DialogResult = true; panel.Children.Add(add); window.Content = panel;
        window.Loaded += (_, _) => text.Focus(); window.PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) window.DialogResult = false; };
        return window.ShowDialog() == true ? text.Text : null;
    }
}
