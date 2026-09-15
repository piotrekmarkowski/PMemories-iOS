import CloudKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Podstawowa telemetria produktowa (15.09.2026) — user: "musze to jeszcze
/// raz przemyśleć czy ludzie będą chcieli płacić za te dodatkowe funkcje
/// czy wystarczy im free wersja" → "robimy to od razu" → rozszerzone tego
/// samego dnia o pełniejszy zestaw zdarzeń (funnel oglądania → próby użycia
/// → [w przyszłości] zakupu), żeby móc realnie porównać np. "100 osób
/// spróbowało dodać muzykę, 35 otworzyło ekran Premium, 8 zaczęło zakup, 4
/// kupiły" zamiast zgadywać które funkcje Premium są warte ceny — patrz
/// `Docs/Pricing.md`.
///
/// Świadomie WYKORZYSTUJE już istniejący, skonfigurowany kontener CloudKit
/// (`LeaderboardService`), zamiast dokładać nową zależność (Firebase
/// Analytics/TelemetryDeck) — to wymagałoby zakładania kolejnego
/// zewnętrznego konta w przeglądarce (ten sam rodzaj tarcia co Firebase na
/// Androidzie), a appka już ma działającą, publiczną bazę CloudKit gotową
/// do zapisu. Zero nowego SDK, zero nowego "GoogleService-Info.plist".
///
/// ŚWIADOMIE anonimowe — NIE identyfikator Sign in with Apple (ten sam co
/// Leaderboard). Osobny, losowy `UUID` wygenerowany raz per-instalację i
/// zapisany w `UserDefaults` — appka i tak już reklamuje się jako
/// prywatność-pierwsza ("no GPS tracking", `Brand.md`), telemetria
/// produktowa idzie w tym samym duchu: wie CO się dzieje w appce, nie KTO
/// to robi. Nie da się połączyć zdarzenia z konkretnym userem/Leaderboard.
///
/// "Fire-and-forget" — logowanie NIGDY nie blokuje ani nie przerywa akcji
/// usera (eksportu, wyboru przejścia itd.), błędy sieciowe/CloudKit są po
/// cichu ignorowane. To telemetria produktowa, nie coś krytycznego dla
/// działania appki.
///
/// PUŁAPKA znaleziona 15.09.2026 (zero zdarzeń trafiało do bazy mimo kilku
/// odpaleń appki, cichy `try?` ukrywał prawdziwy powód): appka ZAWSZE łączy
/// się z środowiskiem PRODUCTION (`project.yml`,
/// `com.apple.developer.icloud-container-environment: Production`), a
/// Production w CloudKit — w przeciwieństwie do Development — NIE
/// auto-tworzy nowych typów rekordów przy pierwszym zapisie
/// (`CKError.invalidArguments`, "Cannot create new type X in production
/// schema"). Każdy NOWY typ rekordu (nie tylko `AppEvent`) musi najpierw
/// powstać w Development (`cktool import-schema --environment development`)
/// i zostać RĘCZNIE wypchnięty do Production przez CloudKit Dashboard
/// (icloud.developer.apple.com → kontener → Schema → Record Types →
/// "Deploy Schema Changes to Production") — to jedyny krok w całym procesie
/// wymagający przeglądarki, nie da się go zrobić przez `cktool`.
enum AnalyticsLogger {
    private static let container = CKContainer(identifier: "iCloud.com.piotrmarkowski.pmemories")
    private static var publicDB: CKDatabase { container.publicCloudDatabase }
    private static let recordType = "AppEvent"

    private static let deviceIDKey = "com.piotrmarkowski.pmemories.analyticsDeviceID"

    /// Losowy, anonimowy identyfikator URZĄDZENIA (nie usera) — pozwala
    /// policzyć "ile RÓŻNYCH urządzeń zrobiło X" bez wiązania z tożsamością.
    private static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIDKey) {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: deviceIDKey)
        return fresh
    }

    /// 15.09.2026 — dziś ZAWSZE "free": appka nie ma jeszcze żadnego
    /// systemu zakupów/subskrypcji (`StoreKit`), więc nie istnieje realne
    /// rozróżnienie kont Free/Premium do odczytania. Pole zostaje w każdym
    /// zdarzeniu już TERAZ (nie dopisywane później) — żeby nie trzeba było
    /// migrować/dopasowywać wstecz starych rekordów, gdy system płatności
    /// faktycznie powstanie i to pole zacznie się różnicować.
    private static var planTier: String { "free" }

    private static var deviceType: String {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
        "unknown"
        #endif
    }

    /// Zdarzenia śledzone od 15.09.2026. Dwie warstwy, świadomie rozdzielone:
    ///
    /// 1) REALNIE PODPIĘTE dziś — appka nie blokuje jeszcze niczego dla
    ///    testerów (user: "tego narazie nie ruszamy, każdy kto testuje musi
    ///    mieć do tego dostęp", `Pricing.md`), więc "tapped"/"viewed" mierzy
    ///    ZAMIAR (kto sięgnął po funkcję, która DOCELOWO pójdzie do Premium),
    ///    nie faktyczne odbicie się od blokady.
    /// 2) ZDEFINIOWANE, jeszcze NIEPODPIĘTE (`paywall*`/`purchase*`/
    ///    `freeLimitReached`/`upgradeButtonTapped`) — appka nie ma dziś
    ///    żadnego ekranu paywalla ani egzekwowanego limitu długości (to
    ///    dopiero "NOWA funkcja do zbudowania", `Pricing.md`), więc te
    ///    zdarzenia nie mają jeszcze SKĄD się odpalić. Zostają w schemacie
    ///    już teraz (nie dopisywane później) z tego samego powodu co
    ///    `planTier` wyżej — jeden stabilny schemat zamiast dwóch migracji.
    enum Event {
        // MARK: Podpięte

        case appOpened
        case exportStarted
        case exportCompleted(durationSeconds: Double, usedColorFilter: Bool, usedPremiumBoundTransition: Bool)
        case transportModeUsed(mode: String)
        case leaderboardOpened
        /// Ekran z widocznymi funkcjami Premium (zablokowanymi lub nie)
        /// faktycznie się otworzył — `feature` identyfikuje SEKCJĘ ekranu
        /// (np. "transitions", "export_quality"), nie pojedynczy wiersz.
        case premiumFeatureViewed(feature: String, source: String)
        /// User faktycznie spróbował użyć/wybrać funkcję, która docelowo
        /// jest Premium — `feature` to stabilny identyfikator (np. "music",
        /// "overlay_pip", "transition_whip_pan", "export_4k",
        /// "ai_director_full", "multi_transport"), `source` to ekran
        /// (np. "studio", "travel_map").
        case premiumFeatureTapped(feature: String, source: String)

        // MARK: Zdefiniowane, jeszcze NIEPODPIĘTE (brak paywalla/StoreKit/limitu w appce)

        case paywallOpened(source: String)
        case paywallClosed(source: String)
        case purchaseStarted
        case purchaseCompleted
        case purchaseFailed(reason: String)
        case upgradeButtonTapped(source: String)
        /// `limit` np. "memory_length_1min" — dziś appka NIE egzekwuje
        /// żadnego limitu długości Free (patrz `Pricing.md`, "NOWA funkcja
        /// do zbudowania"), więc to zdarzenie nigdy się jeszcze nie odpali.
        case freeLimitReached(limit: String)

        var name: String {
            switch self {
            case .appOpened: return "app_opened"
            case .exportStarted: return "export_started"
            case .exportCompleted: return "export_completed"
            case .transportModeUsed: return "transport_mode_used"
            case .leaderboardOpened: return "leaderboard_opened"
            case .premiumFeatureViewed: return "premium_feature_viewed"
            case .premiumFeatureTapped: return "premium_feature_tapped"
            case .paywallOpened: return "paywall_opened"
            case .paywallClosed: return "paywall_closed"
            case .purchaseStarted: return "purchase_started"
            case .purchaseCompleted: return "purchase_completed"
            case .purchaseFailed: return "purchase_failed"
            case .upgradeButtonTapped: return "upgrade_button_tapped"
            case .freeLimitReached: return "free_limit_reached"
            }
        }

        var fields: [String: CKRecordValue] {
            switch self {
            case .appOpened, .exportStarted, .leaderboardOpened, .purchaseStarted, .purchaseCompleted:
                return [:]
            case let .exportCompleted(duration, usedColor, usedPremiumTransition):
                return [
                    "durationSeconds": duration as CKRecordValue,
                    "usedColorFilter": (usedColor ? 1 : 0) as CKRecordValue,
                    "usedPremiumBoundTransition": (usedPremiumTransition ? 1 : 0) as CKRecordValue,
                ]
            case let .transportModeUsed(mode):
                return ["mode": mode as CKRecordValue]
            case let .premiumFeatureViewed(feature, source):
                return ["feature": feature as CKRecordValue, "source": source as CKRecordValue]
            case let .premiumFeatureTapped(feature, source):
                return ["feature": feature as CKRecordValue, "source": source as CKRecordValue]
            case let .paywallOpened(source), let .paywallClosed(source), let .upgradeButtonTapped(source):
                return ["source": source as CKRecordValue]
            case let .purchaseFailed(reason):
                return ["reason": reason as CKRecordValue]
            case let .freeLimitReached(limit):
                return ["limit": limit as CKRecordValue]
            }
        }
    }

    /// Woła się "po cichu" — nie `async throws`, żeby wołający NIGDY nie
    /// musiał obsługiwać błędu telemetrii jak błędu prawdziwej akcji.
    static func log(_ event: Event) {
        Task.detached(priority: .background) {
            let record = CKRecord(recordType: recordType)
            record["eventName"] = event.name as CKRecordValue
            record["deviceID"] = deviceID as CKRecordValue
            record["appVersion"] = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") as CKRecordValue
            record["planTier"] = planTier as CKRecordValue
            record["deviceType"] = deviceType as CKRecordValue
            for (key, value) in event.fields {
                record[key] = value
            }
            _ = try? await publicDB.save(record)
        }
    }
}
