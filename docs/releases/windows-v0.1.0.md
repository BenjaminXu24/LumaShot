# LumaShot for Windows v0.1.0 · 首个 Windows 版本

Windows 原生截图、滚动长图和轻量标注工具，按 MIT 协议开源。

## 下载

- **Intel / AMD 电脑：**`LumaShot-v0.1.0-windows-x64-setup.exe`，适用于 Windows 10 22H2 / Windows 11。
- **Windows 11 on ARM：**`LumaShot-v0.1.0-windows-arm64-setup.exe`。
- **免安装：**选择对应架构的 `*-portable.zip`，完整解压后运行 `LumaShot.exe`。

所有包均包含 .NET 运行时，无需另装 .NET。安装器默认安装到当前用户目录，不请求管理员权限；可从 Windows 设置卸载。更新前请先从托盘菜单退出旧版。

Windows 包尚未进行 Authenticode 代码签名，可能显示未知发布者或 SmartScreen 提示。请核对 GitHub 来源及随附的 `SHA256SUMS-windows.txt`；Apple 公证仅适用于单独发布的 macOS 安装包。

## 功能

- 区域截图、可见窗口截图、鼠标所在显示器全屏截图。
- 全局快捷键 **Ctrl + Shift + 1 / 2 / 3 / 4**，系统托盘菜单与后台待命。
- 自动滚动长截图与手动添加画面，固定页眉/页脚去重，到底自动暂停，匹配失败保留已拼接结果。
- 箭头、矩形、椭圆、画笔、文字、序号、马赛克；选择移动、颜色、线宽、字体大小、撤销重做。
- 保留原图像素的 PNG/JPEG 导出，以及原生位图/PNG 剪贴板复制。
- 最近 100 张原始截图历史、搜索、删除、重新编辑、复制和另存。
- 自动复制、提示音、截图延时，以及用户主动开启的登录启动。

截图与标注仅在本机处理，无账号、无遥测、不上传图片。历史保存原图，标注结果请复制或另存。

## 验证与边界

16 项核心像素/标注检查，以及 Windows 原生运行检查已覆盖实际全局快捷键截图、鼠标框选、窗口选择、SendInput 自动滚动与多帧拼接、标注和马赛克输出、剪贴板、历史保留及导出。Windows 测试页连续拼接 17 帧并正常到底暂停；x64 安装与卸载流程在 CI 中通过。

ARM64 已完成交叉编译及打包，尚未在 ARM64 真机上验证。混合 DPI 多显示器及第三方应用滚动需要更多实际兼容性测试。动态页面、虚拟列表、重复图案、受保护内容及 Windows 输入完整性限制可能影响捕获或自动滚动；可暂停并使用手动拼接。

长图最多 50,000 像素高，约 8,000 万总像素。窗口截图捕捉窗口在桌面上的可见画面。当前界面为简体中文。

详细说明：[Windows README](https://github.com/BenjaminXu24/LumaShot/blob/main/Windows/README.md)。

## English

The first native Windows edition of LumaShot includes region/window/display/scrolling capture, global shortcuts, annotation, local history, clipboard export, and PNG/JPEG saving. Choose the x64 installer for Intel/AMD PCs, or ARM64 for Windows 11 on ARM; portable ZIPs are also available. Each package includes the .NET runtime.

The Windows binaries are not Authenticode signed. Verify the download with `SHA256SUMS-windows.txt`. Windows-native CI exercises capture, input, stitching, rendering, clipboard, history, and x64 install/uninstall. ARM64 hardware and mixed-DPI multi-monitor setups have not yet been tested. See the Windows README for limitations.
