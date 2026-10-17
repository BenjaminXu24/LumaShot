import SwiftUI

struct SettingsContent: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            settingsGroup("截图体验", symbol: "sparkles") {
                settingRow("截图后自动复制", subtitle: "打开标注编辑器的同时，将原始截图复制到剪贴板") {
                    Toggle("", isOn: $model.autoCopy).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider().opacity(0.45)
                settingRow("完成提示音", subtitle: "用一声轻响，告诉你截图已完成") {
                    Toggle("", isOn: $model.playSound).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider().opacity(0.45)
                settingRow("截图延时", subtitle: "为展开菜单、切换页面留一点时间") {
                    Picker("", selection: $model.captureDelay) {
                        Text("立即截图").tag(0); Text("延时 3 秒").tag(3); Text("延时 5 秒").tag(5)
                    }.labelsHidden().frame(width: 130)
                }
                Divider().opacity(0.45)
                settingRow("登录时启动", subtitle: "开机后，在菜单栏静候你的下一次灵感") {
                    Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: model.setLogin)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            settingsGroup("系统权限", symbol: "hand.raised") {
                settingRow("屏幕录制", subtitle: "用于区域、窗口、全屏和滚动截图") {
                    permissionButton(granted: model.screenPermission, action: model.requestScreenPermission)
                }
                Divider().opacity(0.45)
                settingRow("辅助功能", subtitle: "用于自动滚动；未授权时也可以手动滚动拼接") {
                    permissionButton(granted: model.accessibilityPermission, action: model.requestAccessibility)
                }
            }
            settingsGroup("快捷键", symbol: "keyboard") {
                ForEach(CaptureMode.allCases) { mode in
                    HStack {
                        Label(mode.title, systemImage: mode.symbol).font(.system(size: 12))
                        Spacer()
                        HStack(spacing: 5) { KeyCap(text: "⌃"); KeyCap(text: "⇧"); KeyCap(text: mode.keyNumber) }
                    }.padding(.vertical, 5)
                }
                if !model.shortcutIssues.isEmpty {
                    Text(model.shortcutIssues.joined(separator: "\n")).font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("拾光截图 LumaShot \(AppVersion.current)").font(.system(size: 11, weight: .medium))
                    Text("无需账号 · 无网络上传 · 图片只留在本机").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button("打开截图文件夹", action: model.revealHistory).font(.system(size: 11)).buttonStyle(.bordered)
            }.padding(.top, 3)
        }
    }

    private func settingsGroup<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 13, content: content).padding(20)
                .background(.white, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.border.opacity(0.75)))
        }
    }

    private func settingRow<Content: View>(_ title: String, subtitle: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 20)
            trailing()
        }.padding(.vertical, 3)
    }

    private func permissionButton(granted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(granted ? "已授权" : "开启权限", systemImage: granted ? "checkmark.circle.fill" : "arrow.up.right")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(granted ? Color(red: 0.25, green: 0.61, blue: 0.44) : Palette.accent)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background((granted ? Color.green : Palette.accent).opacity(0.06), in: Capsule())
        }.buttonStyle(.plain)
    }
}
