import SwiftUI

struct SettingsContent: View {
    @ObservedObject var model: AppModel
    @AppStorage(TranslationPreferences.engineKey) private var engineRaw = TranslationEngine.deepSeek.rawValue
    @AppStorage(TranslationPreferences.sourceKey) private var sourceRaw = TranslationSourceChoice.auto.rawValue
    @AppStorage(TranslationPreferences.targetKey) private var targetRaw = TranslationLanguage.chinese.rawValue
    @AppStorage(TranslationPreferences.consentKey) private var consentGranted = false
    @State private var apiKeyDraft = ""
    @State private var keyStored = false
    @State private var keyMessage: String?

    private var selectedEngine: TranslationEngine { TranslationEngine(rawValue: engineRaw) ?? .deepSeek }
    private var selectedSource: TranslationSourceChoice { TranslationSourceChoice(rawValue: sourceRaw) ?? .auto }
    private var selectedTarget: TranslationLanguage { TranslationLanguage(rawValue: targetRaw) ?? .chinese }

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
            settingsGroup("翻译", symbol: "character.bubble") {
                settingRow("翻译引擎", subtitle: "DeepSeek 为默认在线引擎。Apple 离线翻译需要 macOS 15 或更高版本，文字不出设备。") {
                    Picker("", selection: engineSelection) {
                        ForEach(TranslationEngine.allCases) { engine in
                            Text(engine.title).tag(engine)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                if selectedEngine == .apple, !TranslationAvailability.appleTranslationOSAvailable {
                    Text(TranslationPlanner.appleUnavailableMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                Divider().opacity(0.45)
                settingRow("原文语言", subtitle: "自动检测，或指定中文、English、Filipino") {
                    Picker("", selection: sourceSelection) {
                        ForEach(TranslationSourceChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                Divider().opacity(0.45)
                settingRow("目标语言", subtitle: "译成中文、English 或 Filipino") {
                    Picker("", selection: targetSelection) {
                        ForEach(TranslationLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                Divider().opacity(0.45)
                VStack(alignment: .leading, spacing: 8) {
                    Text("DeepSeek API Key").font(.system(size: 12, weight: .medium))
                    Text("只保存在本机钥匙串，不会写入截图、日志或源码。").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    HStack(spacing: 8) {
                        SecureField(keyStored ? "输入新的 Key 以替换" : "粘贴 API Key", text: $apiKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("DeepSeek API Key")
                        Button("保存", action: saveAPIKey).font(.system(size: 11))
                        Button("移除", action: removeAPIKey).font(.system(size: 11)).disabled(!keyStored)
                    }
                    if keyStored {
                        Text("已保存在本机钥匙串").font(.system(size: 10, weight: .medium)).foregroundStyle(Color(red: 0.25, green: 0.61, blue: 0.44))
                    }
                    if let keyMessage {
                        Text(keyMessage).font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                    if consentGranted {
                        Button("撤回在线翻译同意") { consentGranted = false }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 3)
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
                    Text("无需账号。\(TranslationPrivacyCopy.standard)")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("打开截图文件夹", action: model.revealHistory).font(.system(size: 11)).buttonStyle(.bordered)
            }.padding(.top, 3)
        }
        .onAppear(perform: refreshKeyStored)
        .onDisappear { apiKeyDraft = "" }
    }

    private var engineSelection: Binding<TranslationEngine> {
        Binding(get: { selectedEngine }, set: { engineRaw = $0.rawValue })
    }

    private var sourceSelection: Binding<TranslationSourceChoice> {
        Binding(get: { selectedSource }, set: { sourceRaw = $0.rawValue })
    }

    private var targetSelection: Binding<TranslationLanguage> {
        Binding(get: { selectedTarget }, set: { targetRaw = $0.rawValue })
    }

    private func refreshKeyStored() {
        do {
            keyStored = try DeepSeekCredential().hasAPIKey()
        } catch {
            keyStored = false
            keyMessage = "无法读取钥匙串。"
        }
    }

    private func saveAPIKey() {
        do {
            try DeepSeekCredential().saveAPIKey(apiKeyDraft)
            apiKeyDraft = ""
            keyStored = true
            keyMessage = "已写入钥匙串。"
        } catch KeychainError.emptySecret {
            keyMessage = "请先输入 API Key。"
        } catch {
            keyMessage = "无法写入钥匙串，请重试。"
        }
    }

    private func removeAPIKey() {
        do {
            try DeepSeekCredential().removeAPIKey()
            apiKeyDraft = ""
            keyStored = false
            keyMessage = "已从钥匙串移除。"
        } catch {
            keyMessage = "无法更新钥匙串，请重试。"
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
