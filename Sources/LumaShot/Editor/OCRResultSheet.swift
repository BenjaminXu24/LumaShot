import SwiftUI

struct OCRSheetPresenter: View {
    @ObservedObject var session: OCRSession
    var onCopied: (String) -> Void

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .sheet(isPresented: Binding(
                get: { session.isPresented },
                set: { presented in if !presented { session.dismiss() } }
            )) {
                OCRResultSheet(session: session, onCopied: onCopied)
            }
    }
}

struct OCRResultSheet: View {
    @ObservedObject var session: OCRSession
    var onCopied: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var translationSession = OCRTranslationSession()
    @AppStorage(TranslationPreferences.engineKey) private var engineRaw = TranslationEngine.deepSeek.rawValue
    @AppStorage(TranslationPreferences.sourceKey) private var sourceRaw = TranslationSourceChoice.auto.rawValue
    @AppStorage(TranslationPreferences.targetKey) private var targetRaw = TranslationLanguage.chinese.rawValue
    @State private var copiedKind: CopiedText?
    @State private var clearedThisAppearance = false

    private let accent = Color(red: 0.49, green: 0.35, blue: 0.94)
    private let ink = Color(red: 0.17, green: 0.16, blue: 0.23)
    private let muted = Color(red: 0.58, green: 0.57, blue: 0.64)

    private enum CopiedText: Equatable {
        case original, translation, both
    }

    private var selectedEngine: TranslationEngine { TranslationEngine(rawValue: engineRaw) ?? .deepSeek }
    private var selectedSource: TranslationSourceChoice { TranslationSourceChoice(rawValue: sourceRaw) ?? .auto }
    private var selectedTarget: TranslationLanguage { TranslationLanguage(rawValue: targetRaw) ?? .chinese }
    private var showsTranslationPane: Bool {
        translationSession.phase != .idle || translationSession.translation != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("识别只在本机完成，不会上传图片。\(TranslationPrivacyCopy.standard)")
                .font(.system(size: 11))
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
            footer
        }
        .padding(22)
        .frame(width: showsTranslationPane ? 880 : 600, height: showsTranslationPane ? 590 : 530)
        .foregroundStyle(ink)
        .background(Color.white)
        .preferredColorScheme(.light)
        .modifier(AppleTranslationAttachment(
            request: $translationSession.appleRequest,
            onSuccess: { translationSession.completeApple($0) },
            onFailure: { translationSession.failApple($0) }
        ))
        .alert("允许在线翻译？", isPresented: $translationSession.showConsent) {
            Button("允许并翻译") { translationSession.grantConsentAndContinue() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("默认不联网。同意之后，只有在你点击翻译且选择 DeepSeek 时，才会把识别出的文字发送到 api.deepseek.com。不会发送图片，也不会保存译文。")
        }
        .sheet(isPresented: $translationSession.showKeyPrompt) {
            DeepSeekKeyPrompt(onSaved: {
                translationSession.showKeyPrompt = false
                translationSession.continueAfterKeySaved()
            }, onCancel: {
                translationSession.showKeyPrompt = false
            })
        }
        .onAppear {
            if !clearedThisAppearance {
                clearedThisAppearance = true
                clearTranslationState()
            }
        }
        .onChange(of: session.isPresented) { _, presented in
            if !presented {
                clearedThisAppearance = false
                clearTranslationState()
            }
        }
        .onChange(of: session.phase) { _, _ in clearTranslationState() }
        .onChange(of: engineRaw) { _, _ in clearTranslationState() }
        .onChange(of: sourceRaw) { _, _ in clearTranslationState() }
        .onChange(of: targetRaw) { _, _ in clearTranslationState() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.12))
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("识别文字").font(.system(size: 16, weight: .semibold))
                if let scope = session.phase.scope {
                    Text(scope)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(muted)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .idle, .recognizing:
            VStack(spacing: 12) {
                ProgressView()
                Text("正在本机识别…").font(.system(size: 13)).foregroundStyle(muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message, _):
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 28, weight: .regular)).foregroundStyle(accent)
                Text(message).font(.system(size: 13)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .result(let text, _):
            if session.phase.canCopy {
                VStack(alignment: .leading, spacing: 10) {
                    translationControls
                    if showsTranslationPane {
                        comparison(original: text)
                    } else {
                        resultText(text)
                    }
                }
            } else {
                resultText(text)
            }
        }
    }

    private var translationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("原文").font(.system(size: 10)).foregroundStyle(muted)
                    Picker("原文", selection: sourceSelection) {
                        ForEach(TranslationSourceChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 118)
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(muted)
                    .padding(.top, 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text("目标").font(.system(size: 10)).foregroundStyle(muted)
                    Picker("目标", selection: targetSelection) {
                        ForEach(TranslationLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 118)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("引擎").font(.system(size: 10)).foregroundStyle(muted)
                    Picker("引擎", selection: engineSelection) {
                        ForEach(TranslationEngine.allCases) { engine in
                            Text(engine.title).tag(engine)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 148)
                    .accessibilityLabel("翻译引擎")
                }
                Button(action: startTranslation) {
                    Text(translationSession.phase == .translating ? "翻译中" : "翻译")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(accent.opacity(translationSession.phase == .translating ? 0.35 : 1), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .disabled(translationSession.phase == .translating)
                .keyboardShortcut("t", modifiers: .command)
                .help("翻译识别出的文字 · ⌘T")
                .accessibilityLabel("翻译")
                .padding(.top, 12)
            }
            Text(selectedEngine == .apple ? "在这台 Mac 上翻译，不发送文字。" : "只会发送识别出的文字，不发送图片。")
                .font(.system(size: 11))
                .foregroundStyle(muted)
        }
    }

    private func comparison(original: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                textColumn(title: "原文", text: original)
                translationColumn
            }
            VStack(alignment: .leading, spacing: 12) {
                textColumn(title: "原文", text: original)
                translationColumn
            }
        }
    }

    private func textColumn(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(muted)
            ScrollView {
                Text(text)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.06)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minWidth: 280)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var translationColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("译文").font(.system(size: 11, weight: .semibold)).foregroundStyle(muted)
            Group {
                if let translated = translationSession.translation {
                    ScrollView {
                        Text(translated)
                            .font(.system(size: 14))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if translationSession.phase == .translating {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(selectedEngine == .apple ? "正在本机翻译…" : "正在发送文字…")
                            .font(.system(size: 12))
                            .foregroundStyle(muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if case .failed(let message) = translationSession.phase {
                    Text(message)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    Text("译文会显示在这里")
                        .font(.system(size: 13))
                        .foregroundStyle(muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.06)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minWidth: 280)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("译文")
    }

    @ViewBuilder
    private func resultText(_ text: String) -> some View {
        if session.phase.canCopy {
            ScrollView {
                Text(text)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.06)))
        } else {
            Text("没有识别到文字")
                .font(.system(size: 14))
                .foregroundStyle(muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            plainButton("关闭", action: close)
            copyButton("复制原文", kind: .original, enabled: session.phase.canCopy, action: copyOriginal)
            if translationSession.translation != nil {
                copyButton("复制译文", kind: .translation, enabled: true, action: copyTranslation)
                copyButton("复制全部", kind: .both, enabled: true, action: copyBoth)
            }
        }
    }

    private func plainButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }

    private func copyButton(_ title: String, kind: CopiedText, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(copiedKind == kind ? "已复制" : title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(accent.opacity(enabled ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
    }

    private var sourceSelection: Binding<TranslationSourceChoice> {
        Binding(get: { selectedSource }, set: { sourceRaw = $0.rawValue })
    }

    private var targetSelection: Binding<TranslationLanguage> {
        Binding(get: { selectedTarget }, set: { targetRaw = $0.rawValue })
    }

    private var engineSelection: Binding<TranslationEngine> {
        Binding(get: { selectedEngine }, set: { engineRaw = $0.rawValue })
    }

    private func startTranslation() {
        guard case .result(let text, _) = session.phase else { return }
        copiedKind = nil
        translationSession.requestTranslation(
            text: text,
            source: selectedSource.language,
            target: selectedTarget,
            engine: selectedEngine,
            appleOSAvailable: TranslationAvailability.appleTranslationOSAvailable
        )
    }

    private func copyOriginal() {
        guard session.copyToPasteboard() else { return }
        copiedKind = .original
        onCopied("已复制原文")
    }

    private func copyTranslation() {
        guard let text = translationSession.translation, ExportService.copyText(text) else { return }
        copiedKind = .translation
        onCopied("已复制译文")
    }

    private func copyBoth() {
        guard case .result(let original, _) = session.phase, let translated = translationSession.translation else { return }
        guard ExportService.copyText(TranslationTranscript.combined(original: original, translation: translated)) else { return }
        copiedKind = .both
        onCopied("已复制原文和译文")
    }

    private func clearTranslationState() {
        translationSession.reset()
        copiedKind = nil
    }

    private func close() {
        clearTranslationState()
        session.dismiss()
        dismiss()
    }
}

private struct DeepSeekKeyPrompt: View {
    var onSaved: () -> Void
    var onCancel: () -> Void
    @State private var draft = ""
    @State private var message: String?

    private let accent = Color(red: 0.49, green: 0.35, blue: 0.94)
    private let ink = Color(red: 0.17, green: 0.16, blue: 0.23)
    private let muted = Color(red: 0.58, green: 0.57, blue: 0.64)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("填写 DeepSeek API Key").font(.system(size: 16, weight: .semibold))
            Text("Key 只写入本机钥匙串。保存后才会发送识别出的文字，图片不会发送。")
                .font(.system(size: 12))
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("API Key", text: $draft)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("DeepSeek API Key")
                .onSubmit(save)
            if let message {
                Text(message).font(.system(size: 11)).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("取消", action: cancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                Button(action: save) {
                    Text("保存并翻译")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(accent, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(width: 440)
        .foregroundStyle(ink)
        .background(Color.white)
        .preferredColorScheme(.light)
        .onDisappear { draft = "" }
    }

    private func save() {
        do {
            try DeepSeekCredential().saveAPIKey(draft)
            draft = ""
            onSaved()
        } catch KeychainError.emptySecret {
            message = "请先输入 API Key。"
        } catch {
            message = "无法写入钥匙串，请重试。"
        }
    }

    private func cancel() {
        draft = ""
        onCancel()
    }
}
