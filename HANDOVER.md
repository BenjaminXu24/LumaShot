# LumaShot 交接说明

> macOS 当前交接见 [2026-10-27 长截图修复与本机更新交接](docs/HANDOFF_MAC_SCROLL_20261027.zh-CN.md)。下面保留的是 2026-10-21 的历史记录，其中的分支、版本和暂停状态不代表当前情况。

> 更新于 2026-10-21（UTC+8）。项目当前**暂停**，本文用于以后接手。
> 本文不含任何密钥、token、证书或密码，只记录变量名和存放位置。

## 1. 项目是什么

LumaShot · 拾光截图是一个桌面截图工具，MIT 协议，仓库：<https://github.com/BenjaminXu24/LumaShot>。

- **macOS 版（主线）**：原生 Swift / SwiftUI + AppKit，使用 ScreenCaptureKit 和 Carbon（全局快捷键）。用 Swift Package Manager 构建（`Package.swift`，没有 xcodeproj），要求 macOS 14+。功能包括区域、窗口、显示器和滚动长截图，标注（箭头、矩形、椭圆、画笔、文字、序号、马赛克），复制和保存，以及本地历史（最近 100 张）。没有第三方运行时依赖。默认不联网；仅在用户点击翻译且选择在线引擎时发送识别出的文字（不含图片）。本次不包含 Windows 翻译。
  - 代码：`Sources/LumaShot/`，测试：`Tests/LumaShotTests/`，脚本：`scripts/`。
- **Windows 版（移植）**：C# / .NET 10 WPF，位于 `Windows/`。
  - `Windows/LumaShot.Core`：与平台无关的像素、拼接、裁剪、选区几何、标注模型和诊断辅助代码。
  - `Windows/LumaShot.Windows`：WPF 应用（截图叠加层、编辑器、托盘、全局快捷键、GDI 抓屏）。
  - `Windows/LumaShot.Core.Tests`：核心检查。它是**控制台程序**，不是 `dotnet test` 项目。
  - `Windows/scripts/`：`doctor.ps1`、`build.ps1`、`test.ps1`、`package.ps1`。`Windows/installer/LumaShot.iss` 是 Inno Setup 安装器脚本。
  - 快捷键：Ctrl + Shift + 1–4 分别对应区域、窗口、显示器、滚动截图。

## 2. 当前状态

### 已完成
- macOS v0.1.0 已发布（tag `v0.1.0`）。推荐下载的 `*-notarized.zip` 由仓库所有者在本地 Mac 上完成 Developer ID 签名和 Apple 公证。
- Windows v0.1.0 已发布（tag `windows-v0.1.0`，x64 / ARM64 的安装器和便携版），**未做代码签名**。
- PR #1（Windows 原生版）、PR #2（Windows 源码构建在新电脑上可用）、PR #3（Windows 截图卡顿修复）都已合并。
- `main` HEAD：`f93ecf0`（PR #3 以 squash 方式合并，2026-10-21 12:33 UTC+8）。`main` 上这个提交的 Windows CI（run 39544739053）和 macOS CI（run 39544738880）都通过了。

### Windows 截图卡顿修复的经过（PR #3）
用户反馈是“按快捷键后卡一阵，突然就截好了”。分成四轮修复：

1. **第 1 轮（a71e8d1）**：叠加层每次鼠标移动都把整屏位图画两遍，抓屏也在 UI 线程上跑。改为静态背景，合并重绘请求，抓屏移到后台线程。CI 另外产出 `LumaShot-win-x64-portable` 便携版 artifact。另外处理了首次启动主窗口黑屏：首帧后补一次重绘，并加了日志。
2. **第 2 轮（5c5061a）**：选区挖空和边框原来是整块选区大小的矩形，现在只移动 2px 宽的边条；两块屏幕的叠加层不再同时处理鼠标移动，由单一窗口负责拖动。加了渲染开关 `--software-render`、`--hardware-render` 和环境变量 `LUMASHOT_RENDER`（都需要主动开启，默认行为不变），还加了诊断日志 `%LOCALAPPDATA%\LumaShot\logs\diagnostics-YYYYMMDD.log`（超过 512 KB 轮转）。实测没有改善，但日志显示拖动本身很快。
3. **第 3 轮（3d18667）**：日志定位到根因。**松开鼠标后对选区单独做的一次 BitBlt 要花约 7.6 秒**，而开始时抓整块显示器只需 20–35ms。改为直接从一开始抓到的未压暗整屏位图里裁剪，支持虚拟屏幕 3840×1080@-1920,0 和跨两块屏幕的选区拼接。滚动截图改为整块显示器 BitBlt 后再裁剪。日志里会出现 `选区返回 裁剪=… 来源=已抓屏 无二次BitBlt`。
4. **第 4 轮（d01c909，即合并的版本）**：
   - 鼠标移动不再每次都重绘，改为通过 `CompositionTarget.Rendering` 每帧最多更新一次。
   - 恢复 Snipaste 式视觉反馈：压暗的冻结截图背景，选区内显示原图亮度，带边框和“宽 × 高”尺寸标注。第 3 版拖动时只有线框，看上去像没反应。
   - 去掉热键处理里写死的 200ms 等待。
   - 叠加窗口在启动时预先创建，之后重复使用。
   - **2026-10-21 实测第 4 版通过**（双屏 1920×1080、100% 缩放、AMD Radeon 780M），随后合并到 `main`。

### 进行中
- 没有进行中的开发。项目已暂停，云端编程任务都已停止，没有未推送的代码。

### 已知问题
- **首次启动主窗口黑屏**：只在第一次启动时出现过，重启后消失，一直没能稳定复现。已加首帧后补一次重绘的缓解措施和日志，但没有确认根治。
- **虚拟显示适配器**：测试机上有 10 个未激活的 “GameViewer Virtual Display Adapter”，启动时会被枚举并写进日志。目前没发现它们影响截图，在其他机器上出现异常时可以作为排查方向。
- **Windows 构建没有代码签名**，SmartScreen 可能会提示。
- **热键到可拖动的延迟**：第 3 版日志里约 0.4 秒（见附录）。第 4 版已去掉 200ms 等待并预建窗口，但没有采集第 4 版的日志来量化改善了多少。
- ARM64 版没在真机上测过。多显示器混合缩放（150% / 200%）和第三方应用的滚动截图兼容性需要更多实测。
- `main` 上有 PR #2、#3 的改动**还没发版**。`Windows/Directory.Build.props` 里的版本号仍是 `0.1.0`。

## 3. 分支和 PR

| 分支 / PR | 用途 | 状态 |
| --- | --- | --- |
| `main` | 主线 | HEAD `f93ecf0` |
| `cursor/windows-overlay-responsiveness-020e`（PR #3） | Windows 截图卡顿修复，共 4 轮，head `d01c909` | **已 squash 合并**。分支比 `main` 多 1 个提交（squash 前的原始历史），但 `git diff main origin/cursor/windows-overlay-responsiveness-020e` 为空，内容已全部进入 `main`。可以安全删除，等 Ethan 决定。 |
| `docs/handover-20261021`（本交接 PR，草稿） | 只新增本文件 `HANDOVER.md` | 草稿，等 Ethan 审阅后决定是否合并 |
| PR #1 `codex/windows-app` | Windows 原生版，含安装器和滚动截图 | 已合并，远端分支已删 |
| PR #2 `codex/windows-source-build` | 让 Windows 源码能在新电脑上构建 | 已合并，远端分支已删 |

除本交接 PR 外，没有未合并的 PR，也没有卡住的工作。

## 4. 如何构建、测试和发布

### macOS（需要 Xcode 15+ / Swift 5.9+）
```sh
swift build
swift test                      # 无需屏幕录制权限
./scripts/build.sh              # 生成 build/LumaShot.app
./scripts/package-release.sh    # 通用二进制 zip + SHA256SUMS，输出到 build/releases/，ad-hoc 签名
```
Developer ID 签名和公证只能在**装有仓库所有者 Developer ID Application 证书的 Mac 上本地完成**，见 `docs/NOTARIZATION.md` 和 `scripts/notarize.sh`。CI 不做签名和公证。

### Windows（需要 Git、PowerShell 7.2+、.NET 10 SDK；打安装器还需要 Inno Setup 6.3+）
```powershell
pwsh -NoProfile -File .\Windows\scripts\doctor.ps1 -Packaging   # 检查环境
pwsh -NoProfile -File .\Windows\scripts\build.ps1 -Run           # Release 构建并启动
pwsh -NoProfile -File .\Windows\scripts\test.ps1                 # 核心检查 + 原生界面检查（需要已登录、未锁屏的桌面）
pwsh -NoProfile -File .\Windows\scripts\test.ps1 -CoreOnly
pwsh -NoProfile -File .\Windows\scripts\package.ps1 -Runtime win-x64   # 或 win-arm64；输出到 build/windows-releases/
```
- 核心检查也可以在 macOS / Linux 上运行：`dotnet run --project Windows/LumaShot.Core.Tests -c Release`（控制台程序，不是 `dotnet test`）。
- 在 Linux 上可以交叉编译 Windows 项目做编译检查：`dotnet build ... -p:EnableWindowsTargeting=true`。这样不能运行 WPF 界面。
- SDK 版本由根目录的 `global.json` 固定（10.0.100，rollForward latestFeature）。

### CI（GitHub Actions，`.github/workflows/`）
| 工作流 | 文件 | 触发条件 | 产物 |
| --- | --- | --- | --- |
| macOS CI | `ci.yml` | push 到 main、PR、手动触发 | macos-15 和 macos-15-intel 上跑 `swift test`；artifact `LumaShot-macOS-universal`（保留 14 天） |
| Windows | `windows.yml` | push 到 main 或 PR，且改动 `Windows/**`、`global.json`、本 workflow 或 `LICENSE`；也可手动触发 | 跑 doctor、test、x64 / ARM64 打包和安装卸载验证；artifact `LumaShot-win-x64-portable`（解压即用）、`LumaShot-Windows-packages`（安装器、便携 zip 和 SHA256SUMS）、`Windows-validation`（诊断和预览图），都保留 14 天 |
| Publish Windows release | `windows-release.yml` | 只能在 main 上手动触发，输入一次成功的 Windows run id | 校验该 run 来自 main 的 push，下载 `LumaShot-Windows-packages`，校验哈希和 PE 架构，按 `Windows/Directory.Build.props` 里的版本创建 `windows-v<版本>` release，需要 `docs/releases/windows-v<版本>.md` 发布说明 |

**Actions 账单**：曾担心仓库所有者的 GitHub 账单在国内付不了款，导致 Actions 跑不了。但 2026-10-21 的所有 run（包括 `main` 上的 f93ecf0）都成功了。如果以后被账单卡住，就只能按上面的步骤在 Windows 本机构建测试包。

### 发布 Windows 新版本的流程（参考，需要 Ethan 拍板）
1. 在工作分支上把 `Windows/Directory.Build.props` 的 `<Version>` 改成新版本号（例如 `0.1.1`），并新增 `docs/releases/windows-v0.1.1.md`，提 PR 合并到 main。
2. 等这次 push 到 main 的 Windows workflow 成功。
3. 手动运行 “Publish Windows release”，`run_id` 填上一步那次 run 的 id。

## 5. 外部依赖和配置项（只列名字，不含值）
- **Swift 包依赖**：无。只用到系统框架 AppKit、SwiftUI、ScreenCaptureKit、Carbon。
- **NuGet 包**：`Windows/**.csproj` 里没有 `PackageReference`，只依赖 .NET 10 SDK 和 WPF。
- **GitHub Actions**：
  - `GH_TOKEN`：在 `windows-release.yml` 里取自内置的 `github.token`，不需要配置仓库 Secret。
  - `TASK_REPOSITORY`、`TASK_RUN_ID`：workflow 内部的环境变量。
  - `LUMASHOT_SOURCE`：`windows.yml` 运行时写入 `GITHUB_ENV`。
  - 当前仓库**没有自定义的 Secrets 或 Variables**。
- **macOS 签名和公证（只在本地 Mac 上用）**：
  - `NOTARY_PROFILE`：`xcrun notarytool` 用的钥匙串凭据配置名，存在本地钥匙串里。
  - `DEVELOPER_ID_APPLICATION`：可选，用来指定签名身份，证书在本地钥匙串里。
- **Windows 运行时**：
  - `LUMASHOT_RENDER`：环境变量，可选，用于切换渲染模式。命令行参数是 `--software-render` / `--hardware-render`。
  - 诊断日志位置：`%LOCALAPPDATA%\LumaShot\logs\`。
- **Inno Setup**：打包脚本可以用 `-InnoCompiler` 参数指定 `ISCC.exe` 的路径。

## 6. 待 Ethan 决定的事项
1. 是否发布带卡顿修复的新版本（例如 `windows-v0.1.1`）。如果发，也要决定 macOS 是否同步发 `v0.1.1`。macOS 端自 v0.1.0 以来的代码改动需要先确认。
2. Windows 是否做代码签名，比如购买证书或使用 Azure Trusted Signing。
3. 是否删除已合并的分支 `cursor/windows-overlay-responsiveness-020e`。
4. 是否开启 Dependabot（目前只会涉及 GitHub Actions 的版本 pin），以及是否把仓库描述和 topics 更新成包含 Windows（现在只写了 macOS）。
5. 是否合并本交接 PR。

## 7. 下一步建议
- 发版前在不同缩放（150% / 200%）、不同主副屏排列和 ARM64 设备上实测第 4 版，并收集第 4 版的诊断日志，确认热键到可拖动的延迟。
- 如果首次启动黑屏再次出现，保存当天的诊断日志，重点看 `主窗口首帧` 这一行和渲染层信息。
- 可以考虑在 `main` 的 Windows CI 里保留便携版 artifact，方便不会从源码构建的人测试；artifact 保留 14 天，过期后需要重新运行。
- 恢复开发时，先确认 GitHub Actions 的额度和账单状态。

## 附录：诊断日志摘要

原始日志不进仓库，以下只摘录关键数字，已去掉设备和用户信息。测试机为 Windows 10.0.26300 x64，WPF 渲染层 2（硬件），双屏 1920×1080 @100%，虚拟屏幕 3840×1080@-1920,0，显卡为 AMD Radeon 780M，另有 10 个未激活的虚拟显示适配器。

### 第 2 版（5c5061a，2026-10-20）：卡顿根因
| 项 | 数值 |
| --- | --- |
| 热键等待 | 216–217ms（其中隐藏窗口 11–13ms） |
| 整块显示器抓屏 | 20–35ms，压暗 6–9ms |
| 叠加层显示 | 104–149ms |
| 叠加层首帧 | 196–248ms |
| 拖动时每次鼠标移动 | 处理平均 0.04–0.12ms（p95 ≤ 0.28ms），绘制平均 ≤ 0.04ms（最大 0.92ms），446–449 次移动 |
| **松开鼠标后的选区 BitBlt** | **7628–7681ms**（1009×621、984×748） |
| **松开到出结果** | **7822–7890ms** |

结论：拖动本身不卡，卡在松开鼠标后的二次 BitBlt。

### 第 3 版（3d18667，构建版本 0.1.0+97917a4，2026-10-21）：二次 BitBlt 已消除
| 项 | 数值 |
| --- | --- |
| 热键等待 | 212–224ms |
| 整块显示器抓屏 | 19–58ms，压暗 6–9ms |
| 叠加层显示 | 105–118ms |
| 叠加层首帧 | 161–213ms（绘制=仅描边） |
| 拖动时每次鼠标移动 | 处理平均 0.06–0.12ms（最大 0.64ms），绘制平均 0.02–0.03ms（最大 2.19ms），378–570 次移动 |
| 裁剪 | 1–7ms，`来源=已抓屏 无二次BitBlt` |
| **松开到出结果** | **51–76ms** |

结论：松开后的延迟从约 7.8 秒降到 0.1 秒以内。剩下的体感问题有两点：按热键到能拖动约 0.4 秒（热键等待约 220ms，加上叠加层显示和首帧约 160–210ms）；拖动时只有线框，没有压暗和原图反馈。第 4 版针对这两点做了修改，实测通过。
