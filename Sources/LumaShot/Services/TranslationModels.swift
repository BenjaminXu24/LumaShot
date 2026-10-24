import Foundation

/// Languages shared with the companion translator: Chinese, English, and Filipino.
enum TranslationLanguage: String, CaseIterable, Identifiable {
    case chinese
    case english
    case filipino

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        case .filipino: return "Filipino"
        }
    }

    /// Names passed to DeepSeek. The on-screen UI stays in Chinese.
    var englishName: String {
        switch self {
        case .chinese: return "Simplified Chinese"
        case .english: return "English"
        case .filipino: return "Filipino"
        }
    }

    /// BCP-47 identifiers to try with Apple Translation, most specific first.
    /// Filipino is offered as `fil` and Tagalog `tl` because system language packs differ.
    var appleIdentifierCandidates: [String] {
        switch self {
        case .chinese: return ["zh-Hans", "zh-CN", "zh"]
        case .english: return ["en", "en-US", "en-GB"]
        case .filipino: return ["fil", "fil-PH", "tl"]
        }
    }

    /// Matches a candidate against identifiers the system reports.
    /// "en" matches "en-US"; "fil" does not match Finnish "fi".
    static func matchIdentifier(_ candidate: String, in supported: [String]) -> String? {
        let needle = candidate.lowercased()
        return supported.first { value in
            let haystack = value.lowercased()
            return haystack == needle
                || haystack.hasPrefix(needle + "-")
                || needle.hasPrefix(haystack + "-")
        }
    }
}

enum TranslationSourceChoice: String, CaseIterable, Identifiable {
    case auto
    case chinese
    case english
    case filipino

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "自动检测"
        case .chinese: return TranslationLanguage.chinese.title
        case .english: return TranslationLanguage.english.title
        case .filipino: return TranslationLanguage.filipino.title
        }
    }

    var language: TranslationLanguage? {
        switch self {
        case .auto: return nil
        case .chinese: return .chinese
        case .english: return .english
        case .filipino: return .filipino
        }
    }
}

enum TranslationEngine: String, CaseIterable, Identifiable {
    case deepSeek
    case apple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepSeek: return "DeepSeek 在线"
        case .apple: return "Apple 离线"
        }
    }
}

enum TranslationPrivacyCopy {
    /// Approved in-app wording. Images never leave the device.
    static let standard = "默认不联网；仅在用户点击翻译且选择在线引擎时发送识别出的文字（不含图片）。"
}

enum TranslationAvailability {
    /// Apple's Translation framework is macOS 15+. The app itself still runs on macOS 14.
    static var appleTranslationOSAvailable: Bool {
        if #available(macOS 15, *) {
            #if canImport(Translation)
            return true
            #else
            return false
            #endif
        }
        return false
    }
}

struct TranslationPreferences: Equatable {
    var engine: TranslationEngine
    var source: TranslationSourceChoice
    var target: TranslationLanguage
    var onlineConsent: Bool

    static let engineKey = "translation.engine"
    static let sourceKey = "translation.source"
    static let targetKey = "translation.target"
    static let consentKey = "translation.onlineConsent"
    static let storageKeys = [engineKey, sourceKey, targetKey, consentKey]

    static let standard = TranslationPreferences(
        engine: .deepSeek,
        source: .auto,
        target: .chinese,
        onlineConsent: false
    )

    static func load(from defaults: UserDefaults) -> TranslationPreferences {
        TranslationPreferences(
            engine: TranslationEngine(rawValue: defaults.string(forKey: engineKey) ?? "") ?? .deepSeek,
            source: TranslationSourceChoice(rawValue: defaults.string(forKey: sourceKey) ?? "") ?? .auto,
            target: TranslationLanguage(rawValue: defaults.string(forKey: targetKey) ?? "") ?? .chinese,
            onlineConsent: defaults.bool(forKey: consentKey)
        )
    }

    func save(to defaults: UserDefaults) {
        defaults.set(engine.rawValue, forKey: Self.engineKey)
        defaults.set(source.rawValue, forKey: Self.sourceKey)
        defaults.set(target.rawValue, forKey: Self.targetKey)
        defaults.set(onlineConsent, forKey: Self.consentKey)
    }
}

enum TranslationTranscript {
    static func combined(original: String, translation: String) -> String {
        "原文：\n\(original)\n\n译文：\n\(translation)"
    }
}

enum TranslationPlanner {
    enum Decision: Equatable {
        case showConsent
        case promptForAPIKey
        case translateOnline
        case translateOffline
        case blocked(String)
    }

    static let emptyTextMessage = "没有可翻译的文字。"
    static let sameLanguageMessage = "原文语言和目标语言相同。请改成自动检测，或更换目标语言。"
    static let appleUnavailableMessage = "Apple 离线翻译需要 macOS 15 或更高版本。"

    /// Only an accepted online translation may leave the Mac, and then only as text.
    static func sendsRecognizedText(_ decision: Decision) -> Bool {
        if case .translateOnline = decision { return true }
        return false
    }

    static func plan(
        text: String,
        source: TranslationLanguage?,
        target: TranslationLanguage,
        engine: TranslationEngine,
        consentGranted: Bool,
        apiKeyPresent: Bool,
        appleOSAvailable: Bool
    ) -> Decision {
        guard text.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil else {
            return .blocked(emptyTextMessage)
        }
        if let source, source == target {
            return .blocked(sameLanguageMessage)
        }
        switch engine {
        case .apple:
            guard appleOSAvailable else { return .blocked(appleUnavailableMessage) }
            return .translateOffline
        case .deepSeek:
            if !consentGranted { return .showConsent }
            if !apiKeyPresent { return .promptForAPIKey }
            return .translateOnline
        }
    }
}

struct AppleLanguagePair: Equatable {
    var sourceIdentifier: String?
    var targetIdentifier: String
}

struct AppleTranslationRequest: Equatable, Identifiable {
    var id: UUID
    var text: String
    var sourceIdentifier: String?
    var targetIdentifier: String
}

enum AppleTranslationPrep: Equatable {
    case ready(AppleLanguagePair)
    case unsupported
    case sourceUnclear
    case unavailable
}
