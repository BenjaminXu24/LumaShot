import Foundation
import Security
import XCTest
@testable import LumaShot

@MainActor
final class TranslationTests: XCTestCase {
    private let sourceText = "lumashot-ocr-source-7f3c9a\n第二行"
    private let placeholderKey = "unit-test-not-a-real-key"

    func testPrivacyCopyUsesTheApprovedSentence() {
        XCTAssertEqual(
            TranslationPrivacyCopy.standard,
            "默认不联网；仅在用户点击翻译且选择在线引擎时发送识别出的文字（不含图片）。"
        )
    }

    func testLanguageIdentifiersPreferSimplifiedChineseEnglishAndFilipino() {
        XCTAssertEqual(TranslationLanguage.chinese.appleIdentifierCandidates.first, "zh-Hans")
        XCTAssertEqual(TranslationLanguage.english.appleIdentifierCandidates.first, "en")
        XCTAssertEqual(TranslationLanguage.filipino.appleIdentifierCandidates, ["fil", "fil-PH", "tl"])
        XCTAssertEqual(TranslationLanguage.matchIdentifier("en", in: ["zh-Hans", "en-US"]), "en-US")
        XCTAssertEqual(TranslationLanguage.matchIdentifier("zh-Hans", in: ["en-US", "zh-Hans"]), "zh-Hans")
        XCTAssertEqual(TranslationLanguage.matchIdentifier("zh-Hans", in: ["zh"]), "zh")
        XCTAssertNil(TranslationLanguage.matchIdentifier("fil", in: ["fi", "en", "zh-Hans"]))
        XCTAssertNil(TranslationLanguage.matchIdentifier("tl", in: ["fil"]))
    }

    func testPreferencesRoundTripDoesNotStoreTextOrSecrets() throws {
        let defaults = try makeDefaults()
        XCTAssertEqual(TranslationPreferences.load(from: defaults), .standard)
        var preferences = TranslationPreferences.standard
        preferences.engine = .apple
        preferences.source = .filipino
        preferences.target = .english
        preferences.onlineConsent = true
        preferences.save(to: defaults)
        XCTAssertEqual(TranslationPreferences.load(from: defaults), preferences)
        defaults.set("nope", forKey: TranslationPreferences.engineKey)
        defaults.set("nope", forKey: TranslationPreferences.sourceKey)
        defaults.set("nope", forKey: TranslationPreferences.targetKey)
        let invalidChoices = TranslationPreferences.load(from: defaults)
        XCTAssertEqual(invalidChoices.engine, TranslationPreferences.standard.engine)
        XCTAssertEqual(invalidChoices.source, TranslationPreferences.standard.source)
        XCTAssertEqual(invalidChoices.target, TranslationPreferences.standard.target)
        XCTAssertTrue(invalidChoices.onlineConsent)
        defaults.set("nope", forKey: TranslationPreferences.consentKey)
        XCTAssertEqual(TranslationPreferences.load(from: defaults), .standard)

        let unrelated = "lumashot-ocr-source-7f3c9a"
        for key in TranslationPreferences.storageKeys {
            XCTAssertFalse(String(describing: defaults.object(forKey: key) ?? "").contains(unrelated))
            XCTAssertFalse(String(describing: defaults.object(forKey: key) ?? "").contains(placeholderKey))
        }
    }

    func testPlannerSendsTextOnlyAfterConsentAndAKey() {
        let base = (
            text: sourceText,
            source: TranslationLanguage?.none,
            target: TranslationLanguage.chinese,
            engine: TranslationEngine.deepSeek,
            consentGranted: false,
            apiKeyPresent: true,
            appleOSAvailable: true
        )
        let needsConsent = TranslationPlanner.plan(
            text: base.text, source: base.source, target: base.target, engine: base.engine,
            consentGranted: false, apiKeyPresent: true, appleOSAvailable: true
        )
        XCTAssertEqual(needsConsent, .showConsent)
        XCTAssertFalse(TranslationPlanner.sendsRecognizedText(needsConsent))

        let needsKey = TranslationPlanner.plan(
            text: sourceText, source: nil, target: .english, engine: .deepSeek,
            consentGranted: true, apiKeyPresent: false, appleOSAvailable: true
        )
        XCTAssertEqual(needsKey, .promptForAPIKey)
        XCTAssertFalse(TranslationPlanner.sendsRecognizedText(needsKey))

        let online = TranslationPlanner.plan(
            text: sourceText, source: .english, target: .filipino, engine: .deepSeek,
            consentGranted: true, apiKeyPresent: true, appleOSAvailable: false
        )
        XCTAssertEqual(online, .translateOnline)
        XCTAssertTrue(TranslationPlanner.sendsRecognizedText(online))

        let offline = TranslationPlanner.plan(
            text: sourceText, source: nil, target: .chinese, engine: .apple,
            consentGranted: false, apiKeyPresent: false, appleOSAvailable: true
        )
        XCTAssertEqual(offline, .translateOffline)
        XCTAssertFalse(TranslationPlanner.sendsRecognizedText(offline))

        let unavailable = TranslationPlanner.plan(
            text: sourceText, source: nil, target: .chinese, engine: .apple,
            consentGranted: true, apiKeyPresent: true, appleOSAvailable: false
        )
        XCTAssertEqual(unavailable, .blocked(TranslationPlanner.appleUnavailableMessage))

        let sameLanguage = TranslationPlanner.plan(
            text: sourceText, source: .chinese, target: .chinese, engine: .deepSeek,
            consentGranted: true, apiKeyPresent: true, appleOSAvailable: true
        )
        XCTAssertEqual(sameLanguage, .blocked(TranslationPlanner.sameLanguageMessage))
        XCTAssertFalse(TranslationPlanner.sameLanguageMessage.contains(sourceText))

        let empty = TranslationPlanner.plan(
            text: " \n\t", source: nil, target: .english, engine: .deepSeek,
            consentGranted: true, apiKeyPresent: true, appleOSAvailable: true
        )
        XCTAssertEqual(empty, .blocked(TranslationPlanner.emptyTextMessage))
    }

    func testRevokingConsentAsksAgainBeforeAnySend() throws {
        let defaults = try makeDefaults()
        var preferences = TranslationPreferences.standard
        preferences.onlineConsent = true
        preferences.save(to: defaults)
        preferences.onlineConsent = false
        preferences.save(to: defaults)
        let decision = TranslationPlanner.plan(
            text: sourceText, source: nil, target: .chinese, engine: .deepSeek,
            consentGranted: TranslationPreferences.load(from: defaults).onlineConsent,
            apiKeyPresent: true, appleOSAvailable: true
        )
        XCTAssertEqual(decision, .showConsent)
    }

    func testDeepSeekRequestIsTextOnlyOnTheOfficialEndpoint() throws {
        let request = try DeepSeekTranslation.makeRequest(
            text: sourceText,
            source: .english,
            target: .filipino,
            apiKey: placeholderKey
        )
        let data = try XCTUnwrap(request.httpBody)
        let body = try JSONDecoder().decode(DeepSeekTranslation.ChatBody.self, from: data)
        let raw = try XCTUnwrap(String(data: data, encoding: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(DeepSeekTranslation.modelID, "deepseek-flash")
        XCTAssertEqual(request.url, URL(string: "https://api.deepseek.com/chat/completions"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(placeholderKey)")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(body.model, "deepseek-flash")
        XCTAssertEqual(body.messages.map(\.role), ["system", "user"])
        XCTAssertEqual(body.messages[1].content, sourceText)
        XCTAssertFalse(body.messages[0].content.contains(sourceText))
        XCTAssertTrue(body.messages[0].content.contains("English"))
        XCTAssertTrue(body.messages[0].content.contains("Filipino"))
        XCTAssertEqual(body.thinking.type, "disabled")
        XCTAssertEqual(body.reasoning_effort, "none")
        XCTAssertFalse(body.stream)
        XCTAssertEqual(body.temperature, 0.2, accuracy: 0.0001)
        XCTAssertEqual(
            Set(object.keys),
            ["model", "messages", "thinking", "reasoning_effort", "stream", "temperature"]
        )
        XCTAssertFalse(raw.contains("image_url"))
        XCTAssertFalse(raw.contains("\"image\""))
        XCTAssertFalse(raw.contains(placeholderKey))
        XCTAssertNil(request.url?.query)
    }

    func testAutoDetectPromptDoesNotEmbedTheSourceText() throws {
        let request = try DeepSeekTranslation.makeRequest(
            text: "他说 \"你好\"",
            source: nil,
            target: .chinese,
            apiKey: placeholderKey
        )
        let body = try JSONDecoder().decode(DeepSeekTranslation.ChatBody.self, from: try XCTUnwrap(request.httpBody))
        XCTAssertEqual(body.messages[1].content, "他说 \"你好\"")
        XCTAssertTrue(body.messages[0].content.contains("Detect"))
        XCTAssertFalse(body.messages[0].content.contains("他说"))
    }

    func testResponsesAndErrorsDoNotEchoTheKeyOrSourceText() throws {
        let translated = try DeepSeekTranslation.parse(
            data: Data(#"{"choices":[{"message":{"content":"  Kumusta  "}}]}"#.utf8),
            statusCode: 200
        )
        XCTAssertEqual(translated, "Kumusta")
        XCTAssertThrowsError(try DeepSeekTranslation.parse(data: Data("{}".utf8), statusCode: 200))
        XCTAssertThrowsError(try DeepSeekTranslation.parse(data: Data("not-json".utf8), statusCode: 200))
        XCTAssertThrowsError(try DeepSeekTranslation.parse(
            data: Data(#"{"error":{"message":"bad sk-secret-value and \#(sourceText)"}}"#.utf8),
            statusCode: 401
        )) { error in
            guard case DeepSeekClientError.httpStatus(401) = error else {
                return XCTFail("unexpected \(error)")
            }
        }

        for error in [
            DeepSeekClientError.httpStatus(401),
            DeepSeekClientError.httpStatus(402),
            DeepSeekClientError.httpStatus(429),
            DeepSeekClientError.httpStatus(500),
            DeepSeekClientError.transport,
            DeepSeekClientError.emptyAPIKey
        ] {
            let message = DeepSeekTranslation.userMessage(for: error)
            XCTAssertFalse(message.contains(placeholderKey))
            XCTAssertFalse(message.contains("sk-"))
            XCTAssertFalse(message.contains(sourceText))
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testEphemeralSessionDoesNotCacheTranslations() {
        let configuration = DeepSeekTranslation.sessionConfiguration()
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testEmptyAPIKeyDoesNotCallTheTransport() async {
        let transport = ScriptedTransport()
        let translator = DeepSeekTranslator(transport: transport)
        do {
            _ = try await translator.translate(text: sourceText, source: nil, target: .english, apiKey: " \n ")
            XCTFail("expected an empty key to be rejected")
        } catch DeepSeekClientError.emptyAPIKey {
            XCTAssertTrue(transport.requests.isEmpty)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testKeychainQueriesStoreOnlyTheNormalizedSecret() throws {
        XCTAssertThrowsError(try KeychainSecretStore.normalizedSecret(" \n\t")) { error in
            XCTAssertEqual(error as? KeychainError, .emptySecret)
        }
        let read = KeychainSecretStore.readQuery(service: DeepSeekCredential.service, account: DeepSeekCredential.account)
        XCTAssertNil(read[kSecValueData as String])
        XCTAssertEqual(read[kSecAttrService as String] as? String, "com.lumashot.mac")
        XCTAssertEqual(read[kSecAttrAccount as String] as? String, "deepseek.api-key")
        XCTAssertEqual(read[kSecClass as String] as? String, kSecClassGenericPassword as String)

        let add = try KeychainSecretStore.addQuery(
            service: DeepSeekCredential.service,
            account: DeepSeekCredential.account,
            secret: "  \(placeholderKey)\n"
        )
        XCTAssertEqual(add[kSecValueData as String] as? Data, Data(placeholderKey.utf8))
        XCTAssertEqual(
            add[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )

        let memory = MemorySecretStore()
        let credential = DeepSeekCredential(store: memory)
        XCTAssertFalse(try credential.hasAPIKey())
        try credential.saveAPIKey("  \(placeholderKey)  ")
        XCTAssertEqual(try credential.apiKey(), placeholderKey)
        XCTAssertFalse(memory.values.values.contains { $0 != placeholderKey })
        try credential.removeAPIKey()
        XCTAssertNil(try credential.apiKey())
    }

    func testCombinedCopyKeepsOriginalAndTranslation() {
        XCTAssertEqual(
            TranslationTranscript.combined(original: "原文甲", translation: "Translation B"),
            "原文：\n原文甲\n\n译文：\nTranslation B"
        )
    }

    func testOnlineTranslationWaitsForConsentThenKeyAndDoesNotCache() async throws {
        let defaults = try makeDefaults()
        let transport = ScriptedTransport()
        let memory = MemorySecretStore()
        let session = OCRTranslationSession(
            secrets: memory,
            translator: DeepSeekTranslator(transport: transport),
            defaults: defaults,
            apple: AppleTranslationPreparing { _, _, _ in .unavailable }
        )

        session.requestTranslation(
            text: sourceText, source: nil, target: .filipino, engine: .deepSeek, appleOSAvailable: true
        )
        XCTAssertTrue(session.showConsent)
        XCTAssertFalse(session.showKeyPrompt)
        XCTAssertTrue(transport.requests.isEmpty)

        session.grantConsentAndContinue()
        await session.finishCurrentWork()
        XCTAssertTrue(defaults.bool(forKey: TranslationPreferences.consentKey))
        XCTAssertTrue(session.showKeyPrompt)
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertNil(session.translation)

        try memory.setSecret(placeholderKey, service: DeepSeekCredential.service, account: DeepSeekCredential.account)
        session.continueAfterKeySaved()
        await session.finishCurrentWork()

        XCTAssertEqual(transport.requests.count, 1)
        let body = try JSONDecoder().decode(
            DeepSeekTranslation.ChatBody.self,
            from: try XCTUnwrap(transport.requests[0].httpBody)
        )
        XCTAssertEqual(body.messages[1].content, sourceText)
        XCTAssertEqual(body.model, "deepseek-flash")
        XCTAssertFalse(String(data: try XCTUnwrap(transport.requests[0].httpBody), encoding: .utf8)?.contains(placeholderKey) ?? true)
        XCTAssertEqual(session.translation, "TRANSLATED-SENTENCE")
        XCTAssertEqual(session.phase, .idle)
        for key in TranslationPreferences.storageKeys {
            let stored = String(describing: defaults.object(forKey: key) ?? "")
            XCTAssertFalse(stored.contains(sourceText))
            XCTAssertFalse(stored.contains("TRANSLATED-SENTENCE"))
            XCTAssertFalse(stored.contains(placeholderKey))
        }
        XCTAssertFalse(session.translation?.contains(placeholderKey) ?? true)

        session.reset()
        XCTAssertNil(session.translation)
        XCTAssertEqual(session.phase, .idle)
        XCTAssertNil(session.appleRequest)
    }

    func testFailedOnlineCallDoesNotEchoTextOrKey() async throws {
        let defaults = try makeDefaults()
        var preferences = TranslationPreferences.standard
        preferences.onlineConsent = true
        preferences.save(to: defaults)
        let transport = ScriptedTransport()
        transport.statusCode = 401
        transport.body = Data(#"{"error":{"message":"bad sk-secret-value \#(sourceText)"}}"#.utf8)
        let memory = MemorySecretStore()
        try memory.setSecret(placeholderKey, service: DeepSeekCredential.service, account: DeepSeekCredential.account)
        let session = OCRTranslationSession(
            secrets: memory,
            translator: DeepSeekTranslator(transport: transport),
            defaults: defaults
        )
        session.requestTranslation(
            text: sourceText, source: .english, target: .chinese, engine: .deepSeek, appleOSAvailable: true
        )
        await session.finishCurrentWork()
        guard case .failed(let message) = session.phase else {
            return XCTFail("expected failure, got \(session.phase)")
        }
        XCTAssertFalse(message.contains(sourceText))
        XCTAssertFalse(message.contains(placeholderKey))
        XCTAssertFalse(message.contains("sk-"))
        XCTAssertNil(session.translation)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testAppleTranslationDoesNotTouchTheNetwork() async throws {
        let defaults = try makeDefaults()
        let transport = ScriptedTransport()
        var preparedText = ""
        let session = OCRTranslationSession(
            secrets: MemorySecretStore(),
            translator: DeepSeekTranslator(transport: transport),
            defaults: defaults,
            apple: AppleTranslationPreparing { text, source, target in
                preparedText = text
                XCTAssertEqual(source, .english)
                XCTAssertEqual(target, .chinese)
                return .ready(AppleLanguagePair(sourceIdentifier: "en", targetIdentifier: "zh-Hans"))
            }
        )
        session.requestTranslation(
            text: sourceText, source: .english, target: .chinese, engine: .apple, appleOSAvailable: true
        )
        await session.finishCurrentWork()
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertFalse(defaults.bool(forKey: TranslationPreferences.consentKey))
        XCTAssertEqual(preparedText, sourceText)
        XCTAssertEqual(session.appleRequest?.text, sourceText)
        XCTAssertEqual(session.appleRequest?.sourceIdentifier, "en")
        XCTAssertEqual(session.appleRequest?.targetIdentifier, "zh-Hans")
        XCTAssertEqual(session.phase, .translating)

        session.completeApple("  你好  ")
        XCTAssertEqual(session.translation, "你好")
        XCTAssertEqual(session.phase, .idle)
        XCTAssertNil(session.appleRequest)
        for key in TranslationPreferences.storageKeys {
            XCTAssertFalse(String(describing: defaults.object(forKey: key) ?? "").contains("你好"))
        }
    }

    func testUnsupportedApplePairDoesNotSend() async throws {
        let defaults = try makeDefaults()
        let transport = ScriptedTransport()
        let session = OCRTranslationSession(
            secrets: MemorySecretStore(),
            translator: DeepSeekTranslator(transport: transport),
            defaults: defaults,
            apple: AppleTranslationPreparing { _, _, _ in .unsupported }
        )
        session.requestTranslation(
            text: sourceText, source: .filipino, target: .english, engine: .apple, appleOSAvailable: true
        )
        await session.finishCurrentWork()
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertNil(session.appleRequest)
        XCTAssertNil(session.translation)
        guard case .failed(let message) = session.phase else {
            return XCTFail("expected failure, got \(session.phase)")
        }
        XCTAssertEqual(message, AppleTranslationMessages.unsupported)
        XCTAssertFalse(message.contains(sourceText))
    }

    func testAppleOnOlderSystemsDoesNotPrepareOrSend() async throws {
        let defaults = try makeDefaults()
        let transport = ScriptedTransport()
        var prepared = false
        let session = OCRTranslationSession(
            secrets: MemorySecretStore(),
            translator: DeepSeekTranslator(transport: transport),
            defaults: defaults,
            apple: AppleTranslationPreparing { _, _, _ in
                prepared = true
                return .unavailable
            }
        )
        session.requestTranslation(
            text: sourceText, source: nil, target: .english, engine: .apple, appleOSAvailable: false
        )
        await session.finishCurrentWork()
        XCTAssertFalse(prepared)
        XCTAssertTrue(transport.requests.isEmpty)
        guard case .failed(let message) = session.phase else {
            return XCTFail("expected failure, got \(session.phase)")
        }
        XCTAssertEqual(message, TranslationPlanner.appleUnavailableMessage)
    }

    func testKeychainReadFailureDoesNotSend() async throws {
        let defaults = try makeDefaults()
        let transport = ScriptedTransport()
        let session = OCRTranslationSession(
            secrets: ThrowingSecretStore(),
            translator: DeepSeekTranslator(transport: transport),
            defaults: defaults
        )
        session.requestTranslation(
            text: sourceText, source: nil, target: .chinese, engine: .deepSeek, appleOSAvailable: true
        )
        XCTAssertTrue(transport.requests.isEmpty)
        guard case .failed(let message) = session.phase else {
            return XCTFail("expected failure, got \(session.phase)")
        }
        XCTAssertFalse(message.contains(sourceText))
        XCTAssertFalse(message.contains(placeholderKey))
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "LumaShotTests.translation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
}

private final class ScriptedTransport: TranslationTransport, @unchecked Sendable {
    var requests: [URLRequest] = []
    var statusCode = 200
    var body = Data(#"{"choices":[{"message":{"content":"TRANSLATED-SENTENCE"}}]}"#.utf8)

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: request.url ?? DeepSeekTranslation.endpoint,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        ))
        return (body, response)
    }
}

private final class MemorySecretStore: SecretStoring, @unchecked Sendable {
    var values: [String: String] = [:]

    func secret(service: String, account: String) throws -> String? {
        values[key(service: service, account: account)]
    }

    func setSecret(_ secret: String, service: String, account: String) throws {
        values[key(service: service, account: account)] = try KeychainSecretStore.normalizedSecret(secret)
    }

    func removeSecret(service: String, account: String) throws {
        values[key(service: service, account: account)] = nil
    }

    private func key(service: String, account: String) -> String { "\(service)\n\(account)" }
}

private struct ThrowingSecretStore: SecretStoring {
    func secret(service: String, account: String) throws -> String? {
        throw KeychainError.unexpectedStatus(errSecAuthFailed)
    }

    func setSecret(_ secret: String, service: String, account: String) throws {
        throw KeychainError.unexpectedStatus(errSecAuthFailed)
    }

    func removeSecret(service: String, account: String) throws {
        throw KeychainError.unexpectedStatus(errSecAuthFailed)
    }
}
