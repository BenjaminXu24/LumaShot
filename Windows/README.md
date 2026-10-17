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

### 在另一台 Windows 电脑准备环境

使用 Windows 10 22H2 / Windows 11 x64，或 Windows 11 ARM64。源码构建需要 Git、PowerShell 7.2+ 和 **.NET 10 SDK**；仅安装 .NET Runtime 不够。生成 `setup.exe` 还需要 Inno Setup 6.3+。无需安装 Visual Studio；首次构建需要联网还原 .NET 依赖。

可在 Windows 终端中逐条安装：

```powershell
winget install --id Git.Git --exact --source winget
winget install --id Microsoft.PowerShell --exact --source winget
winget install --id Microsoft.DotNet.SDK.10 --exact --source winget
winget install --id JRSoftware.InnoSetup --exact --source winget
```

不打包安装器时可跳过最后一条。没有 `winget` 时，使用官方下载：[Git](https://git-scm.com/install/windows)、[PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows)、[.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)、[Inno Setup](https://jrsoftware.org/isdl.php)。命令中的包标识来自 [Git 安装说明](https://git-scm.com/install/windows)、[Microsoft PowerShell 文档](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows)、[Microsoft .NET 文档](https://learn.microsoft.com/dotnet/core/install/windows)与 [WinGet 的 Inno Setup 清单](https://github.com/microsoft/winget-pkgs/tree/master/manifests/j/JRSoftware/InnoSetup)。

安装完成后关闭并重新打开终端，使 `git`、`pwsh`、`dotnet` 的 PATH 生效。后续命令均在源码根目录执行，脚本由 `pwsh` 运行，Windows 自带的 `powershell.exe` 5.1 不适用。

```powershell
git clone https://github.com/BenjaminXu24/LumaShot.git
cd LumaShot
pwsh -NoProfile -File .\Windows\scripts\doctor.ps1 -Packaging
```

已有克隆时，在仓库根目录执行 `git switch main`、`git pull --ff-only` 获取更新；先提交或保存自己的修改。只开发和测试时，环境检查可省略 `-Packaging`。根目录 `global.json` 选择 .NET 10 的稳定版 SDK，允许使用已安装的更新功能版本。

### 构建、运行与自动测试

```powershell
# 编译 Release，并启动主界面
pwsh -NoProfile -File .\Windows\scripts\build.ps1 -Run
```

不传 `-Run` 则只编译；可用 `-Configuration Debug` 切换配置。关闭主窗口后程序仍留在托盘，请从托盘菜单选择「退出」，然后再运行测试或安装更新。

```powershell
# 核心检查、Release 编译、原生 Windows 界面检查
pwsh -NoProfile -File .\Windows\scripts\test.ps1

# 仅运行像素与标注模型检查，适合无交互桌面的环境
pwsh -NoProfile -File .\Windows\scripts\test.ps1 -CoreOnly
```

完整测试需要当前用户已登录且桌面保持解锁；请先退出已有 LumaShot，保存剪贴板中需要保留的内容，测试过程中不要操作鼠标。测试会移动鼠标、触发快捷键、滚动测试页并改写剪贴板。它使用隔离的测试目录，不使用普通运行时的截图历史，也不安装或卸载已安装的程序。

原生检查覆盖原始像素导出、标注和马赛克渲染、剪贴板、100 张历史保留、全局快捷键实际触发 GDI 截图，以及通过 `SendInput` 滚动本地 WPF 测试页并拼接。输出位于 `build/windows-smoke/`，包括界面 PNG 和 `checks.json`；失败时查看终端输出与该目录的诊断文件。脚本遇到失败会返回非零退出码。

纯核心检查也可直接在 macOS / Linux 执行：

```sh
dotnet run --project Windows/LumaShot.Core.Tests -c Release
```

### 打包与安装本机版本

```powershell
# 大多数 Intel / AMD 电脑
pwsh -NoProfile -File .\Windows\scripts\package.ps1 -Runtime win-x64

# Windows on ARM 设备
pwsh -NoProfile -File .\Windows\scripts\package.ps1 -Runtime win-arm64
```

默认架构为 `win-x64`。如果 Inno Setup 装在自定义位置，可显式指定编译器：

```powershell
pwsh -NoProfile -File .\Windows\scripts\package.ps1 -Runtime win-x64 -InnoCompiler "D:\Tools\Inno Setup 6\ISCC.exe"
```

产物位于 `build/windows-releases/`：对应架构的 `setup.exe`、`portable.zip` 和 `SHA256SUMS-windows.txt`。包内包含 .NET 运行时和许可证，可复制到另一台同架构电脑直接安装或解压运行。源码版本号位于 `Windows/Directory.Build.props`。

退出托盘中的旧版后，双击新生成的安装器，按向导安装；也可以在仓库根目录执行：

```powershell
Start-Process ".\build\windows-releases\LumaShot-v0.1.0-windows-x64-setup.exe" -Wait
```

ARM64 电脑将文件名中的 `x64` 换成 `arm64`；修改过项目版本号时使用实际生成的文件名。安装完成后从开始菜单启动 LumaShot。卸载可通过 Windows「已安装的应用」完成，用户截图与设置会保留。

若终端提示禁止运行脚本，可在确认源码来源后，仅对这一次进程添加 `-ExecutionPolicy Bypass`，例如 `pwsh -NoProfile -ExecutionPolicy Bypass -File .\Windows\scripts\doctor.ps1`；不需要永久修改系统执行策略。受组织策略管理的电脑请按组织要求配置。

### 本机验收

自动测试后，再在实际使用的 Windows 电脑完成这些操作：

1. 用四组全局快捷键分别测试区域、窗口、当前显示器与滚动截图；检查 Esc 取消和快捷键冲突提示。
2. 在浏览器打开较长页面，框选正文，确认自动滚动、暂停、手动添加和完成可用；检查长图顶部、中间、底部的文字是否连续。
3. 添加箭头、文字和马赛克，测试撤销重做；复制到画图或聊天输入框，再保存 PNG / JPEG，确认标注与图片尺寸正确。
4. 若使用多显示器，分别在各屏及实际的 100% / 150% / 200% 缩放下检查框选位置、窗口边界和导出清晰度。
5. 关闭并重新打开应用，检查历史与设置；退出托盘程序后安装更新，确认仍可正常启动和截图。

Windows CI 会编译 x64 / ARM64，执行核心和 x64 原生界面检查，并验证 x64 安装与卸载。ARM64 尚未完成真机测试；自动检查不能替代多显示器硬件、混合缩放和所有第三方应用的兼容性验收。CI 配置见 [Windows workflow](../.github/workflows/windows.yml)。Windows 代码按 MIT 协议发布，详见根目录 [LICENSE](../LICENSE)。

## 实现参考

- [WPF 部署](https://learn.microsoft.com/dotnet/desktop/wpf/app-development/deploying-a-wpf-application-wpf)
- [RegisterHotKey](https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-registerhotkey)
- [GDI 截图](https://learn.microsoft.com/windows/win32/gdi/capturing-an-image)
- [SendInput 与 Windows 输入完整性限制](https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-sendinput)
- [Per-Monitor DPI Awareness](https://learn.microsoft.com/windows/win32/hidpi/high-dpi-desktop-application-development-on-windows)
