# LumaShot 新 Mac 开发准备记录（2026-10-24）

核验日期：2026-10-24，约 11:57–11:59 UTC。仅同步源码、检查环境与本地验证；功能开发保持暂停。

## 源码与工作区

- 本地目录：`/Users/mima0000/Documents/lumashot`。操作前目录完全为空，没有用户文件或已有 Git 仓库；随后克隆指定仓库。
- origin（fetch/push）：`https://github.com/BenjaminXu24/LumaShot.git`。
- 分支：`main`，跟踪 `origin/main`。
- 本地 HEAD、origin/main 与实时 `git ls-remote origin HEAD refs/heads/main` 一致：`6e82f3afe9dbbc709cee5d810ee3bb1ad959e2d9`。ahead/behind 为 `0/0`。
- HEAD 标题：`docs: 新增交接说明 HANDOVER.md (#4)`。交接 PR #4 已进入主线；HANDOVER 中 `f93ecf0`、交接 PR 为草稿以及“是否合并本交接 PR”等为历史文字，不代表当前未合并状态。
- 克隆后、测试编译后工作区均干净；最终唯一未跟踪文件为本报告。日志和编译产物在已忽略的 `build/`、`.build/` 中。
- 没有 stash、reset、rebase、切换已有分支、merge、commit 或 push，也未修改业务代码及发布配置。
- 仓库内未发现 `AGENTS.md`、`.agents/skills` 或 `.codex` 指令；检查的上级目录也未发现 AGENTS.md。已读中英文 README、HANDOVER、CONTRIBUTING、Package.swift、Mac 构建/发布/公证脚本及 CI 配置，并检查 Windows 开发说明与相关脚本入口。

## 实际工具与平台范围

| 项目 | 本机结果 |
| --- | --- |
| macOS | 27.0.1，build 26A434，Apple Silicon / arm64 |
| 默认开发目录 | `/Library/Developer/CommandLineTools`，未修改全局设置 |
| Xcode | `/Applications/Xcode.app`，27.1，build 27A9275 |
| Swift | Apple Swift 6.4，swiftlang-6.4.0.34.1 |
| Xcode macOS SDK | 27.0 |
| .NET / PowerShell | 当前 PATH 未找到 `dotnet`、`pwsh`；未安装 |

默认 CLT 下 `xcodebuild -version` 提示需要完整 Xcode。使用进程级 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 后成功读取版本并完成测试、编译，不需要 `sudo xcode-select`。

macOS 主代码在 `Sources/LumaShot/`，测试在 `Tests/LumaShotTests/`。这是 Swift Package，没有 xcodeproj，声明 macOS 14+、Swift tools 5.9、Swift 5 语言模式，无外部 Swift 包；使用 AppKit、SwiftUI、ScreenCaptureKit、Carbon。

Windows 是 `Windows/` 下独立 C# / .NET 10 / WPF 实现。`LumaShot.Core.Tests` 是控制台检查程序，不是 `dotnet test` 项目。Windows GUI 构建与真机检查需 Windows 环境；本机未验证 Windows 核心检查、WPF 构建、安装器或 ARM64 运行。

## 本次测试与编译证据

| 验证 | 实际结果 | 本地日志 |
| --- | --- | --- |
| 首次 `swift test` | 退出 1；SwiftPM manifest 的嵌套 `sandbox-exec` 报 `sandbox_apply: Operation not permitted`，不是测试断言失败 | `build/readiness-20261024/swift-test.log` |
| `swift test --disable-sandbox` | 退出 0；Debug 编译完成，17 项 XCTest 全通过、0 失败：标注 4、存储 5、拼接 8 | `build/readiness-20261024/swift-test-local.log` |
| 首次 Release 编译 | 退出 1；`GenerateDSYMFile` / `dsymutil` 被执行沙箱阻止 | `build/readiness-20261024/swift-build-release.log` |
| 同一 Release 编译经执行权限批准后重试 | 退出 0，`Build complete! (1.47秒)` | `build/readiness-20261024/swift-build-release-retry.log` |

测试日志末尾的 Swift Testing “0 tests”是另一测试框架的空套件；XCTest 的 17 项测试确实执行并通过。测试仅用生成图像与隔离临时目录，不运行截图界面。

Release 产物：`.build/release/LumaShot`（指向 `.build/out/Products/Release/LumaShot`），`file` 验证为 `Mach-O 64-bit executable arm64`。本次直接使用 SwiftPM 编译，未执行 codesign、签名脚本或制作应用发行包；不将链接器可能生成的内建签名视为 Developer ID 签名或公证验证。未验证 Intel/universal 产物。

首次受限执行还报告用户级 SwiftPM configuration/security 目录不可写并禁用用户缓存；缓存显式放在项目 `.build/` 下后测试通过。`--disable-sandbox` 仅取消 SwiftPM 自身附加沙箱，不关闭执行环境外层权限限制。Git 克隆的 `.git` 写入和远端读取也经执行权限批准成功；没有遗留拒绝或结果不明的操作。

## 后续开发与启动步骤

先在本项目目录使用以下已验证的环境与命令；只影响当前终端。不要先执行发布脚本。

```sh
cd /Users/mima0000/Documents/lumashot
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-module-cache"
swift test --disable-sandbox --cache-path "$PWD/.build/readiness-cache"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/readiness-cache"
```

在普通本机终端可优先省略 `--disable-sandbox`，本次保留该参数是为适配受限执行环境。若仍遇到 dsymutil 权限错误，需要允许该本地编译操作；不要把失败当作通过。

之后用户明确恢复开发/允许启动时，可在 Xcode 打开 `Package.swift`，选择 LumaShot scheme / My Mac，再运行调试。当前命令行编译产物可通过 `.build/release/LumaShot` 启动，但本次未执行；登录启动等完整应用包行为需后续独立验证。

README 的 `./scripts/build.sh` 即使未设置证书变量也会执行 ad-hoc `codesign`；`package-release.sh` 会调用它并生成通用 ZIP；`notarize.sh` 涉及 Developer ID、Apple 提交与票据装订。以上均不属于本次授权范围，未执行。后续需要完整 `.app` 时，另行确认签名/打包范围后再按 README 操作。

## 权限与剩余缺口

- 实际截图需要系统“屏幕与系统音频录制”（或屏幕录制）权限；自动滚动需要辅助功能权限。手动滚动拼接可不授予辅助功能。本次未请求、检查或变更这些权限，也未运行 CaptureSmoke、预览模式或截图应用。
- 本机单元测试和 arm64 Release 编译已就绪。真实截图、快捷键、复制保存、登录启动、多显示器/混合缩放、第三方自动滚动，以及新系统上的实际 UI 行为仍待用户允许后的交互验证。
- Windows 还缺当前 PATH 中的 .NET / PowerShell；WPF 真机检查需 Windows，ARM64 与混合缩放也需相应设备。未安装任何系统工具或下载运行时大包。
- HANDOVER 的 Windows 首次黑屏、延迟量化及后续发版事项仍仅作为历史待确认线索；本次没有恢复修复、修改版本或安排发布。CI/账单状态未重新查询，历史 CI 通过不能代替当前本机结果。
- 保留本报告为未提交文档。后续同步前应注意工作区已有这份用户可审阅文件，继续保留，不做清理或强制覆盖。
