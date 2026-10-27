# LumaShot 长截图修复与本机更新交接

核对时间：2026-10-27 09:58（Asia/Shanghai）。本文只交接 LumaShot；桌面已归还有处，继续操作 UI 前需先协调桌面使用。

## 当前结论

- 长截图滚动输入、暂停/继续、完成时漏帧、失败后重试，以及截图后主窗口再次出现的问题均已完成修复。
- PR [#7](https://github.com/BenjaminXu24/LumaShot/pull/7)、[#8](https://github.com/BenjaminXu24/LumaShot/pull/8)、[#9](https://github.com/BenjaminXu24/LumaShot/pull/9) 均已合入 main。本轮整理前，仓库没有 open PR。
- PR #9 由 BenjaminXu24 于 2026-10-27 08:17:04 合入，main 为 `05f8c25482c808cbe77572b8a3f2956b9565924b`。它与测试分支头 `c38b39a1ad95494f985caa138d0398548328db2c` 的文件树完全一致。
- 功能提交都已推送。此次交接使用 `codex/handoff-20261027` 文档分支，基于上述 main；不直接推送 main。
- 公开最新版仍是 [v0.2.2](https://github.com/BenjaminXu24/LumaShot/releases/tag/v0.2.2)，不包含 PR #9。没有创建新版本 tag 或公开 Release，也没有公证本地修复包。

## 修复范围

| 变更 | 结果 | 主线提交 |
| --- | --- | --- |
| PR #7：滚动输入与采样 | CaptureService 接入连续 pixel scroll 和 began/changed/ended 手势，替换无效的单次 scrollWheel；避免周期性移动真实鼠标影响控制栏操作 | `71e71a5` |
| PR #8：长截图时序 | 暂停时处理在途帧，继续后恢复滚动；完成时等待在途采样；末帧采样失败或 noOverlap 时撤销待完成状态，保留控制栏及重试提示；成功重试后必须再次点完成才导出 | `96e41db` |
| PR #9：窗口生命周期 | 截图成功后保持主窗口隐藏，恢复既有编辑器；处理截图服务独立恢复窗口及 AppKit reopen 事件；有编辑器时优先恢复编辑器，保留显式打开主窗口入口 | `05f8c25` |

PR #9 只改 `AppModel.swift`、`Main.swift`、新增 `CaptureWindowLifecycle.swift` 及其测试，不改滚动算法、OCR、翻译或仓库版本号。

## 验证结果与边界

- 完整单元测试：78 项通过、0 失败；其中滚动驱动时序回归 17 项，窗口生命周期回归 12 项。
- Release 编译与 Universal 构建通过，包含 arm64 / x86_64，最低 macOS 14。
- [PR #9 CI](https://github.com/BenjaminXu24/LumaShot/actions/runs/40351552931)：ARM / Intel 测试和 Universal application 全绿。
- [合入 main 后 CI](https://github.com/BenjaminXu24/LumaShot/actions/runs/40425411898)：`05f8c25` 全绿。
- 真机环境：macOS 27.0.1、Apple M1 Pro、内建 Retina。ChatGPT 合成测试回答共 24 段。
- 自动滚动：导出 8 屏，1560 × 6210；01–24 段与 PR9-BEGIN / PR9-END 完整，无段号缺失或重复。
- 暂停/继续：暂停时保存在途帧；继续后从 2 屏增长到 7 屏。
- 真实 noOverlap：添加末帧过程中点完成，失败后控制栏和重试提示保留，未导出；历史仍为 27 条。成功重试后仍为 27 条；再次点完成才导出并增至 28 条。
- 主窗口：区域截图后打开编辑器，编辑器可见时 reopen 不弹主界面；关闭编辑器后，用户确认“这次没有弹出”。

证据对应关系：上述长截图真机验证在 `a7ec703` 完成；后续 `c38b39a` 只改变窗口生命周期，真机补测了窗口关闭及 reopen。安装版启动验收未重新执行长截图。不要把这些记录写成“全部在安装版重测”。

未覆盖项：系统采样直接返回失败未在真机注入，自动/手动采样失败路径由回归测试覆盖；真实失败恢复使用 noOverlap。最终一轮未重测外接多屏与混合 DPI，也未验证 Windows 或所有第三方应用的滚动兼容性。

## 这台 Mac 的安装状态

- 安装位置：`/Applications/LumaShot.app`。
- 版本：`0.2.2`，build `4.1`，渠道 `local-pr9`，实际构建来源 `c38b39a1ad95494f985caa138d0398548328db2c`。PR #9 后来合入 main，不改写这份历史构建来源。
- 使用与原安装版相同的 Developer ID 签名；严格全架构签名验证通过，安装版与 candidate 的二进制、Info.plist 哈希一致。
- 2026-10-27 启动验收通过；界面显示 0.2.2，屏幕录制和辅助功能均显示“已授权”，无新权限或协议提示。
- 旧 WindowFix 测试版已正常退出，验收结束时仅安装版运行；未改截图历史、偏好或钥匙串。
- 旧安装版为 `0.2.1/build3`，完整备份已解压核对并验签，可回滚。
- 本地修复包未公证，未上传为公开 Release 资产。

本地文件均在以下目录，未纳入 Git：

```text
/Users/mima0000/.codex/worktrees/mac-scroll-fix/lumashot/build/local-update-20261027-c38b39a/
  LumaShot-local-v0.2.2-build4.1-pr9-c38b39a-macOS-universal.zip
  LumaShot-backup-v0.2.1-build3-20261027.zip
  SHA256SUMS-local-update.txt
  manifest.json
  UPDATE-README.zh-CN.md
  tests.log
  universal-build.log
  bundle-build.log
```

安装包 SHA-256：`feba9d236ea60f2b5f23372b90651a53553e9729ffb7196760a9f2943e3d065d`。

旧版备份 SHA-256：`1c0cf51f5cd7972b840acb14ae016b095242186f2646d5b8a6ff55cf1739c10f`。

回滚时先正常退出 LumaShot，将旧版备份解压后替换 `/Applications/LumaShot.app` 再启动。不要同时运行测试包和安装包，也不要删除应用数据目录。

真机记录和合成测试长图：

```text
/Users/mima0000/.codex/worktrees/mac-scroll-fix/lumashot/build/pr9-desktop-test-record.json
/Users/mima0000/.codex/worktrees/mac-scroll-fix/lumashot/build/pr9-chatgpt-auto-8frames.png
/Users/mima0000/.codex/worktrees/mac-scroll-fix/lumashot/build/pr9-chatgpt-retry-export.png
```

原始记录的顶层历史条数是旧快照；应以具体测试条目中 27 → 27 → 28 的时间序列为准。记录中的 PR 未合入状态是当时快照，当前状态以上文远端核对为准。不要提交原始截图历史或个人截图。

## 工作区与接手入口

- 当前工作区：`/Users/mima0000/.codex/worktrees/mac-scroll-fix/lumashot`，交接分支 `codex/handoff-20261027`。
- 原始检出：`/Users/mima0000/Documents/lumashot`，本地 main 仍为 `ce793c5`，落后当前远端 main 一个提交；未强制重置或改写原目录。
- 原目录唯一未跟踪文件 `docs/MAC_DEVELOPMENT_READINESS_20261024.zh-CN.md` 为历史开发准备记录，已复制到交接分支一并推送，原文件保留。其旧版本、测试数量及“暂停”描述仅代表 10 月 24 日，不代表当前状态。
- `.build/`、`build/` 是忽略的本地产物，不属于遗漏提交；不要清理当前 worktree，否则会丢失本地安装包、回滚包和验证证据。

重新开始前先读取实时状态：

```sh
cd /Users/mima0000/.codex/worktrees/mac-scroll-fix/lumashot
git status --short --branch
git fetch origin --prune
gh pr list --repo BenjaminXu24/LumaShot --state open
gh release view --repo BenjaminXu24/LumaShot
```

代码有新改动时，使用进程级 Xcode 设置构建，不修改全局 xcode-select：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --jobs 2
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --arch arm64 --arch x86_64 --jobs 2
```

构建/签名入口见 `scripts/build.sh`、`scripts/package-release.sh`、`docs/NOTARIZATION.md`。稳定更新应沿用已有 Developer ID 身份，避免重置现有截图与辅助功能权限；不要导出证书私钥或把凭据写入交接。

## 下一步

1. 功能修复已进入 main，无待推送的功能提交。本文档 PR 只需审阅，不包含产品变更。
2. 如要正式发版，先明确发布范围和版本号；新版本必须包含 `05f8c25`。不要把本机 build 4.1 冒充公开 v0.2.2，也不要覆盖现有 Release 资产。
3. 对外发布、公证、改版本、打 tag 仍需按用户后续指令执行。本轮只整理和推送文档，没有发版或再次合入功能 PR。
4. 如继续验收，优先补外接多屏/混合 DPI 和真实系统采样失败；操作桌面前与有处、续事协调，避免同时使用 Chrome、Xcode 或截图快捷键。
