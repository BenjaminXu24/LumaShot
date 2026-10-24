import Combine
import Foundation

enum OCRTranslationPhase: Equatable {
    case idle
    case translating
    case failed(String)
}

private final class TranslationTaskBox: @unchecked Sendable {
    var task: Task<Void, Never>?
    func cancel() { task?.cancel() }
}

/// In-memory translation for one OCR sheet. Results are not written to UserDefaults or the capture store.
@MainActor
final class OCRTranslationSession: ObservableObject {
    @Published private(set) var phase: OCRTranslationPhase = .idle
    @Published private(set) var translation: String?
    @Published var showConsent = false
    @Published var showKeyPrompt = false
    @Published var appleRequest: AppleTranslationRequest?

    private struct Pending {
        var text: String
        var source: TranslationLanguage?
        var target: TranslationLanguage
        var engine: TranslationEngine
        var appleOSAvailable: Bool
    }

    private var pending: Pending?
    private nonisolated let tasks = TranslationTaskBox()
    private var task: Task<Void, Never>? {
        get { tasks.task }
        set { tasks.task = newValue }
    }
    private let secrets: DeepSeekCredential
    private let translator: DeepSeekTranslator
    private let defaults: UserDefaults
    private let apple: AppleTranslationPreparing

    init(
        secrets: SecretStoring = KeychainSecretStore(),
        translator: DeepSeekTranslator = DeepSeekTranslator(),
        defaults: UserDefaults = .standard,
        apple: AppleTranslationPreparing = .live
    ) {
        self.secrets = DeepSeekCredential(store: secrets)
        self.translator = translator
        self.defaults = defaults
        self.apple = apple
    }

    deinit {
        tasks.cancel()
    }

    func reset() {
        task?.cancel()
        task = nil
        pending = nil
        appleRequest = nil
        translation = nil
        phase = .idle
        showConsent = false
        showKeyPrompt = false
    }

    func requestTranslation(
        text: String,
        source: TranslationLanguage?,
        target: TranslationLanguage,
        engine: TranslationEngine,
        appleOSAvailable: Bool
    ) {
        pending = Pending(text: text, source: source, target: target, engine: engine, appleOSAvailable: appleOSAvailable)
        task?.cancel()
        task = nil
        appleRequest = nil
        showConsent = false
        showKeyPrompt = false

        let consentGranted = TranslationPreferences.load(from: defaults).onlineConsent
        let keyPresent: Bool
        do {
            keyPresent = try secrets.hasAPIKey()
        } catch {
            translation = nil
            phase = .failed("无法读取钥匙串。请重试。")
            return
        }

        let decision = TranslationPlanner.plan(
            text: text,
            source: source,
            target: target,
            engine: engine,
            consentGranted: consentGranted,
            apiKeyPresent: keyPresent,
            appleOSAvailable: appleOSAvailable
        )
        switch decision {
        case .showConsent:
            showConsent = true
        case .promptForAPIKey:
            showKeyPrompt = true
        case .translateOnline:
            translation = nil
            phase = .translating
            startOnline(text: text, source: source, target: target)
        case .translateOffline:
            translation = nil
            phase = .translating
            startOffline(text: text, source: source, target: target)
        case .blocked(let message):
            translation = nil
            phase = .failed(message)
        }
    }

    func grantConsentAndContinue() {
        var preferences = TranslationPreferences.load(from: defaults)
        preferences.onlineConsent = true
        preferences.save(to: defaults)
        replayPending()
    }

    func continueAfterKeySaved() {
        replayPending()
    }

    func completeApple(_ translated: String) {
        guard appleRequest != nil else { return }
        let cleaned = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        appleRequest = nil
        guard !cleaned.isEmpty else {
            translation = nil
            phase = .failed(AppleTranslationMessages.empty)
            return
        }
        translation = cleaned
        phase = .idle
    }

    func failApple(_ message: String) {
        guard appleRequest != nil else { return }
        appleRequest = nil
        translation = nil
        phase = .failed(message)
    }

    func finishCurrentWork() async {
        await task?.value
    }

    private func replayPending() {
        guard let pending else { return }
        requestTranslation(
            text: pending.text,
            source: pending.source,
            target: pending.target,
            engine: pending.engine,
            appleOSAvailable: pending.appleOSAvailable
        )
    }

    private func startOnline(text: String, source: TranslationLanguage?, target: TranslationLanguage) {
        task = Task { [weak self] in
            guard let self else { return }
            do {
                guard let apiKey = try self.secrets.apiKey() else {
                    self.phase = .idle
                    self.showKeyPrompt = true
                    return
                }
                let translated = try await self.translator.translate(
                    text: text,
                    source: source,
                    target: target,
                    apiKey: apiKey
                )
                guard !Task.isCancelled else { return }
                self.translation = translated
                self.phase = .idle
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.translation = nil
                self.phase = .failed(DeepSeekTranslation.userMessage(for: error))
            }
        }
    }

    private func startOffline(text: String, source: TranslationLanguage?, target: TranslationLanguage) {
        task = Task { [weak self] in
            guard let self else { return }
            let prep = await self.apple.prepare(text, source, target)
            guard !Task.isCancelled else { return }
            if let message = AppleTranslationMessages.message(for: prep) {
                self.translation = nil
                self.phase = .failed(message)
                return
            }
            guard case .ready(let pair) = prep else { return }
            self.appleRequest = AppleTranslationRequest(
                id: UUID(),
                text: text,
                sourceIdentifier: pair.sourceIdentifier,
                targetIdentifier: pair.targetIdentifier
            )
        }
    }
}
