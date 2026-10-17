using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LumaShot.Core;

namespace LumaShot.Windows.Services;

internal static class DemoArtwork
{
    public static PixelFrame Create()
    {
        const int width = 1440, height = 960;
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            dc.DrawRectangle(new LinearGradientBrush(Color.FromRgb(235, 227, 255), Color.FromRgb(245, 248, 255), 45), null, new(0, 0, width, height));
            dc.DrawRoundedRectangle(Brushes.White, null, new(100, 100, 1240, 760), 30, 30);
            void Text(string text, int size, int x, int y, Color color) => dc.DrawText(new FormattedText(text, CultureInfo.CurrentCulture, FlowDirection.LeftToRight, new Typeface("Segoe UI, Microsoft YaHei UI"), size, new SolidColorBrush(color), 1), new(x, y));
            Text("LUMASHOT  /  A LITTLE INSPIRATION", 20, 155, 155, Color.FromRgb(135, 126, 164));
            Text("留住值得分享的瞬间。", 55, 155, 235, Color.FromRgb(40, 42, 63));
            Text("从一个想法，到一张清晰的表达。", 26, 158, 325, Color.FromRgb(135, 140, 160));
            var colors = new[] { Color.FromRgb(240, 233, 255), Color.FromRgb(228, 244, 240), Color.FromRgb(255, 240, 227) };
            for (var i = 0; i < 3; i++)
            {
                var x = 155 + i * 380; dc.DrawRoundedRectangle(new SolidColorBrush(colors[i]), null, new(x, 430, 350, 275), 18, 18);
                Text(new[] { "01  捕捉", "02  标注", "03  分享" }[i], 30, x + 30, 470, Color.FromRgb(55, 54, 78));
                Text(new[] { "框选需要的内容", "让重点一目了然", "复制，随处粘贴" }[i], 21, x + 30, 535, Color.FromRgb(120, 120, 143));
                Text(new[] { "▣", "↗", "✓" }[i], 64, x + 245, 585, Color.FromRgb(125, 89, 239));
            }
            Text("体验箭头、矩形、文字、序号与马赛克。按 Ctrl+C 复制，Ctrl+S 保存。", 20, 158, 768, Color.FromRgb(135, 140, 160));
        }
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32); bitmap.Render(visual); return ImageCodec.Frame(bitmap);
    }
}
