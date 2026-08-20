import Foundation

/// Ręczny wybór języka appki (Profile → Language) — user 30.07.2026:
/// "mieszkam w Anglii ale może chcę mieć po polsku" — wybór NIEZALEŻNY od
/// kraju zamieszkania, domyślnie = język telefonu (system), z możliwością
/// nadpisania. Zapisane przez oficjalny mechanizm Apple (`UserDefaults`
/// klucz "AppleLanguages") — to jedyny wspierany sposób nadpisania języka
/// appki bez własnego systemu tłumaczeń równoległego do String Catalog.
/// **Ograniczenie systemowe (nie appki)**: zmiana widoczna dopiero po
/// ponownym otwarciu appki — iOS nie przeładowuje już załadowanych bundle'i
/// językowych "na żywo".
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case polish = "pl"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portugueseBR = "pt-BR"
    case japanese = "ja"
    case korean = "ko"
    case chineseSimplified = "zh-Hans"
    case dutch = "nl"
    case portuguesePT = "pt-PT"
    case swedish = "sv"
    case danish = "da"
    case norwegian = "nb"
    case finnish = "fi"
    case turkish = "tr"
    case greek = "el"
    case czech = "cs"
    case hungarian = "hu"
    case ukrainian = "uk"
    case hindi = "hi"
    case indonesian = "id"
    case thai = "th"
    case vietnamese = "vi"
    case arabic = "ar"
    case hebrew = "he"
    case romanian = "ro"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .polish: return "Polski"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .portugueseBR: return "Português (Brasil)"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .chineseSimplified: return "简体中文"
        case .dutch: return "Nederlands"
        case .portuguesePT: return "Português (Portugal)"
        case .swedish: return "Svenska"
        case .danish: return "Dansk"
        case .norwegian: return "Norsk bokmål"
        case .finnish: return "Suomi"
        case .turkish: return "Türkçe"
        case .greek: return "Ελληνικά"
        case .czech: return "Čeština"
        case .hungarian: return "Magyar"
        case .ukrainian: return "Українська"
        case .hindi: return "हिन्दी"
        case .indonesian: return "Bahasa Indonesia"
        case .thai: return "ไทย"
        case .vietnamese: return "Tiếng Việt"
        case .arabic: return "العربية"
        case .hebrew: return "עברית"
        case .romanian: return "Română"
        }
    }

    private static let key = "AppleLanguages"

    static var current: AppLanguage {
        guard let saved = UserDefaults.standard.array(forKey: key) as? [String],
              let code = saved.first, let language = AppLanguage(rawValue: code) else {
            return .system
        }
        return language
    }

    static func apply(_ language: AppLanguage) {
        switch language {
        case .system:
            UserDefaults.standard.removeObject(forKey: key)
        case .english, .polish, .spanish, .french, .german, .italian, .portugueseBR, .japanese, .korean, .chineseSimplified,
             .dutch, .portuguesePT, .swedish, .danish, .norwegian, .finnish, .turkish, .greek, .czech, .hungarian,
             .ukrainian, .hindi, .indonesian, .thai, .vietnamese, .arabic, .hebrew, .romanian:
            UserDefaults.standard.set([language.rawValue], forKey: key)
        }
    }
}
