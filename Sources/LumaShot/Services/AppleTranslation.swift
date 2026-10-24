import SwiftUI
#if canImport(Translation)
import Translation
#endif

enum AppleTranslationMessages {
    static let unsupported = "Apple 离线翻译不能完成这个语言组合。可能是原文和目标相同、语言还没下载，或这台 Mac 还不支持 Filipino。请更换语言，或改用 DeepSeek。"
    static let sourceUnclear = "没能判断原文语言。请手动选择中文、English 或 Filipino。"
    static let unavailable = "Apple 离线翻译需要 macOS 15 或更高版本。"
    static let failed = "Apple 离线翻译没有完成。可以改用 DeepSeek，或在“系统设置 → 通用 → 语言与地区 → 翻译语言”中下载语言。"
    static let empty = "没有得到译文。"

    static func message(for prep: AppleTranslationPrep) -> String? {
        switch prep {
        case .ready:
            return nil
        case .unsupported:
            return unsupported
        case .sourceUnclear:
            return sourceUnclear
        case .unavailable:
            return unavailable
        }
    }
}

struct AppleTranslationPreparing {
    var prepare: (String, TranslationLanguage?, TranslationLanguage) async -> AppleTranslationPrep

    static let live = AppleTranslationPreparing { text, source, target in
        await AppleTranslationBridge.prepare(text: text, source: source, target: target)
    }
}

enum AppleTranslationBridge {
    static func prepare(text: String, source: TranslationLanguage?, target: TranslationLanguage) async -> AppleTranslationPrep {
        #if canImport(Translation)
        if #available(macOS 15, *) {
            return await AppleTranslationSupport.prepare(text: text, source: source, target: target)
        }
        #endif
        return .unavailable
    }
}

#if canImport(Translation)
@available(macOS 15, *)
enum AppleTranslationSupport {
    static func prepare(text: String, source: TranslationLanguage?, target: TranslationLanguage) async -> AppleTranslationPrep {
        let availability = LanguageAvailability()
        var fallback: AppleLanguagePair?
        var detectionFailed = false
        for targetID in target.appleIdentifierCandidates {
            let targetLanguage = Locale.Language(identifier: targetID)
            if let source {
                for sourceID in source.appleIdentifierCandidates {
                    let status = await availability.status(
                        from: Locale.Language(identifier: sourceID),
                        to: targetLanguage
                    )
                    let pair = AppleLanguagePair(sourceIdentifier: sourceID, targetIdentifier: targetID)
                    if let ready = absorb(status: status, pair: pair, fallback: &fallback) {
                        return ready
                    }
                }
            } else {
                do {
                    let status = try await availability.status(for: text, to: targetLanguage)
                    let pair = AppleLanguagePair(sourceIdentifier: nil, targetIdentifier: targetID)
                    if let ready = absorb(status: status, pair: pair, fallback: &fallback) {
                        return ready
                    }
                } catch {
                    detectionFailed = true
                }
            }
        }
        if let fallback { return .ready(fallback) }
        if source == nil, detectionFailed { return .sourceUnclear }
        return .unsupported
    }

    /// Installed pairs win immediately. A supported-but-not-installed pair is kept as a downloadable fallback.
    private static func absorb(
        status: LanguageAvailability.Status,
        pair: AppleLanguagePair,
        fallback: inout AppleLanguagePair?
    ) -> AppleTranslationPrep? {
        switch status {
        case .installed:
            return .ready(pair)
        case .supported:
            if fallback == nil { fallback = pair }
            return nil
        case .unsupported:
            return nil
        @unknown default:
            return nil
        }
    }
}

@available(macOS 15, *)
private struct AppleTranslationHost<Content: View>: View {
    @Binding var request: AppleTranslationRequest?
    var onSuccess: (String) -> Void
    var onFailure: (String) -> Void
    @ViewBuilder var content: () -> Content
    @State private var configuration: TranslationSession.Configuration?
    @State private var appliedSource: String?
    @State private var appliedTarget = ""
    @State private var hasConfiguration = false

    var body: some View {
        content()
            .onChange(of: request) { _, newValue in
                apply(newValue)
            }
            .translationTask(configuration) { session in
                guard let request else { return }
                let token = request.id
                let text = request.text
                do {
                    let response = try await session.translate(text)
                    let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run {
                        guard self.request?.id == token else { return }
                        if translated.isEmpty {
                            onFailure(AppleTranslationMessages.empty)
                        } else {
                            onSuccess(translated)
                        }
                    }
                } catch {
                    if Task.isCancelled { return }
                    await MainActor.run {
                        guard self.request?.id == token else { return }
                        onFailure(AppleTranslationMessages.failed)
                    }
                }
            }
    }

    private func apply(_ request: AppleTranslationRequest?) {
        guard let request else { return }
        let samePair = hasConfiguration
            && appliedSource == request.sourceIdentifier
            && appliedTarget == request.targetIdentifier
        appliedSource = request.sourceIdentifier
        appliedTarget = request.targetIdentifier
        if samePair, var existing = configuration {
            existing.invalidate()
            configuration = existing
            hasConfiguration = true
            return
        }
        configuration = TranslationSession.Configuration(
            source: request.sourceIdentifier.map { Locale.Language(identifier: $0) },
            target: Locale.Language(identifier: request.targetIdentifier)
        )
        hasConfiguration = true
    }
}
#endif

struct AppleTranslationAttachment: ViewModifier {
    @Binding var request: AppleTranslationRequest?
    var onSuccess: (String) -> Void
    var onFailure: (String) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(macOS 15, *) {
            AppleTranslationHost(request: $request, onSuccess: onSuccess, onFailure: onFailure) {
                content
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
