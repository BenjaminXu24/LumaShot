# LumaShot for Windows · 拾光截图

Windows 原生截图、滚动长图与轻量标注工具。采用 C#、WPF 和 .NET 10，沿用 macOS 版的紫色界面与使用方式；无第三方运行依赖、账号、遥测或图片上传。

## 下载与安装

从 [GitHub Releases](https://github.com/BenjaminXu24/LumaShot/releases) 中选择 Windows 发布版本：

| 文件 | 用途 |
| --- | --- |
| `LumaShot-v0.1.0-windows-x64-setup.exe` | 大多数 Intel / AMD Windows 电脑，推荐 |
| `LumaShot-v0.1.0-windows-arm64-setup.exe` | Windows on ARM 设备 |
| `*-portable.zip` | 免安装包；完整解压后运行 `LumaShot.exe` |
| `SHA256SUMS-windows.txt` | 安装包与 ZIP 的 SHA-256 校验值 |

安装包和免安装包均包含 .NET 运行时，无需另装 .NET。x64 版适用于 Windows 10 22H2 / Windows 11；ARM64 版适用于 Windows 11 on ARM。安装器默认安装到当前用户的 `%LOCALAPPDATA%\Programs\LumaShot`，不请求管理员权限，并提供卸载入口。更新前请从系统托盘菜单退出旧版。

Windows 包尚未进行 Authenticode 代码签名；Apple 公证仅适用于 macOS 包。Windows 可能显示未知发布者或 SmartScreen 提示，请先核对来源与 SHA-256。不要关闭系统安全功能。

在 PowerShell 中校验单个文件：

```powershell
Get-FileHash .\LumaShot-v0.1.0-windows-x64-setup.exe -Algorithm SHA256
```

## 截图与长截图

| 功能 | 全局快捷键 | 操作 |
| --- | --- | --- |
| 区域截图 | Ctrl + Shift + 1 | 拖动框选，松开完成 |
| 窗口截图 | Ctrl + Shift + 2 | 悬停高亮窗口，点击捕捉可见画面 |
| 全屏截图 | Ctrl + Shift + 3 | 捕捉鼠标所在显示器 |
| 滚动长截图 | Ctrl + Shift + 4 | 选择滚动内容，自动向下滚动并拼接 |

Esc 或右键取消框选；滚动时 Esc 取消。关闭主窗口后仍在系统托盘运行，双击托盘图标显示主窗口，右键提供截图方式、设置和退出入口。快捷键冲突会显示提示，仍可使用界面或托盘操作。

滚动截图选择实际滚动的内容，避开固定侧栏、播放器及工具栏。到底后自动暂停，点击「完成」进入标注。可以随时暂停、手动滚动约半屏并点击「添加当前屏」。匹配失败会保留已拼接的结果，提示向上回滚后重试。

长图上限 50,000 像素高、约 8,000 万总像素。支持常见固定页眉与页脚去重；动态页面、虚拟列表、重复图案或重叠不足可能影响匹配。Windows 的安全桌面、受保护视频等内容不能正常截图；普通权限应用可能无法自动滚动管理员窗口，此时可手动滚动添加。

## 标注与导出

支持箭头、矩形、椭圆、画笔、文字、序号、马赛克、选择和移动，提供颜色、线宽、字体大小、撤销与重做。

| 操作 | 快捷键 |
| --- | --- |
| 复制完整标注图 | Ctrl + C |
| 保存 PNG / JPEG | Ctrl + S |
| 撤销 / 重做 | Ctrl + Z / Ctrl + Shift + Z，或 Ctrl + Y |
| 适应窗口 / 100% | Ctrl + 0 / Ctrl + 1 |
| 选择 / 箭头 / 矩形 / 椭圆 | V / A / R / O |
| 画笔 / 文字 / 序号 / 马赛克 / 移动 | P / T / N / M / H |
| 删除选中标注 | Delete |

Shift 约束箭头角度、正方形与正圆；Alt + 拖动平移；Ctrl + 滚轮缩放。所有标注都按原图像素导出，缩放不改变导出分辨率。马赛克改变实际导出像素。复制同时提供原生位图与 PNG，方便粘贴到不同应用。关闭尚未复制或保存的标注会提示保存。

打开图片支持系统图像解码器可读取的 PNG、JPEG、BMP、TIFF、GIF（首帧）。「体验标注」使用程序本地生成的练习图，不读取屏幕。

## 本地数据与设置

- 原始截图位于 `%LOCALAPPDATA%\LumaShot\Captures`，保留最近 100 张；历史支持搜索、重新编辑、复制、另存及删除。
- 历史保存原图，不保存标注会话；标注结果请复制或另存。
- 偏好设置支持自动复制、提示音、0 / 3 / 5 秒截图延时和登录启动。登录启动只在用户开启后注册，仅显示托盘图标。
- 卸载程序保留截图与偏好设置，避免删除用户图片；可从界面打开数据文件夹自行管理。

## 开发与验证

要求 .NET 10 SDK。Windows 窗口界面需要 Windows；纯像素和标注模型测试也可在 macOS / Linux 运行。

```powershell
dotnet run --project Windows/LumaShot.Core.Tests -c Release
dotnet build Windows/LumaShot.Windows -c Release
dotnet run --project Windows/LumaShot.Windows
```

原生 Windows 检查（需要可交互桌面，输出仅位于指定的隔离目录）：

```powershell
dotnet run --project Windows/LumaShot.Windows -c Release -- --smoke-test build/windows-smoke
```

检查内容包括原始像素导出、标注和马赛克渲染、剪贴板、100 张历史保留、全局快捷键实际触发 GDI 截图，以及通过 `SendInput` 滚动本地 WPF 测试页并拼接。测试输出界面 PNG 和 `checks.json`；不会使用普通运行时的截图历史。它不能替代多显示器硬件、混合缩放和所有第三方应用的实际兼容性测试。

安装包需要 Windows 和 Inno Setup 6.3+：

```powershell
./Windows/scripts/package.ps1 -Runtime win-x64
./Windows/scripts/package.ps1 -Runtime win-arm64
```

产物位于 `build/windows-releases/`。CI 位于 [Windows workflow](../.github/workflows/windows.yml)。Windows 代码按 MIT 协议发布，详见根目录 [LICENSE](../LICENSE)。

## 实现参考

- [WPF 部署](https://learn.microsoft.com/dotnet/desktop/wpf/app-development/deploying-a-wpf-application-wpf)
- [RegisterHotKey](https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-registerhotkey)
- [GDI 截图](https://learn.microsoft.com/windows/win32/gdi/capturing-an-image)
- [SendInput 与 Windows 输入完整性限制](https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-sendinput)
- [Per-Monitor DPI Awareness](https://learn.microsoft.com/windows/win32/hidpi/high-dpi-desktop-application-development-on-windows)
