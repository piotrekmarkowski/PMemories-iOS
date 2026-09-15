import SwiftUI
import SwiftData

@main
struct PMemoriesAppApp: App {
    // BUG znaleziony 02.08.2026 (crash na starcie: "CloudKit integration
    // requires that all relationships be optional") — dodanie uprawnienia
    // `com.apple.developer.icloud-services` (dla RANKINGU, publiczna baza
    // CloudKit przez `CKContainer`) sprawiło że SwiftData/Core Data
    // domyślnie ("automatic") PRÓBOWAŁO włączyć WŁASNĄ synchronizację
    // CloudKit dla lokalnej bazy appki, mimo że nigdy jej nie chcieliśmy —
    // ranking to zupełnie inny, niezależny mechanizm (surowe `CKRecord`
    // w publicznej bazie, nie SwiftData). Jawne `cloudKitDatabase: .none`
    // wyłącza to domyślne zachowanie — baza lokalna zostaje CZYSTO lokalna,
    // tak jak było, niezależnie od obecności uprawnienia CloudKit.
    //
    // Shared Trip przez CKShare (12.08.2026) — PRÓBA COFNIĘTA. Krótko
    // istniał tu podział na dwie NAZWANE konfiguracje ("local"/"shared"),
    // bo plan zakładał `CKShare` dla `PlannedTrip`. Dwa realne problemy
    // znalezione PODCZAS implementacji, nie zgadywane:
    // 1) SwiftData w tym SDK (iPhoneOS26.5) nie ma W OGÓLE publicznego API
    //    do `CKShare` (sprawdzone przez grep `.swiftinterface` — jedyne
    //    opcje `ModelConfiguration.CloudKitDatabase` to `.automatic`/`.none`/
    //    `.private`, zero wzmianek o współdzieleniu z konkretnymi ludźmi) —
    //    prawdziwe person-to-person sharing wymagałoby zejścia na surowy
    //    CloudKit, osobny, większy projekt.
    // 2) NAZWANA `ModelConfiguration` bez jawnego `url:` liczy WŁASNĄ,
    //    NOWĄ domyślną ścieżkę pliku (`local.store`/`shared.store`) zamiast
    //    dotychczasowego `default.store` — user stracił WIDOK na 11 zapisanych
    //    podróży/4 projekty/249 elementów (dane bezpieczne na dysku w starym
    //    pliku, appka po prostu przestała go czytać). Złapane od razu przez
    //    usera ("gdzie moje wszystkie memories?!"), potwierdzone przez
    //    `devicectl device copy` + `sqlite3` na obu plikach.
    // Powrót do JEDNEJ, DOMYŚLNEJ (nienazwanej) konfiguracji dla całego
    // schematu — dokładnie jak przed dzisiejszą próbą, appka znów czyta
    // `default.store` ze wszystkimi danymi. Shared Trip (żywe współdzielenie)
    // zostaje w `Docs/TODO.md` jako odłożony temat wymagający surowego
    // CloudKit, nie kolejnej próby przez SwiftData.
    private static let container: ModelContainer = {
        let schema = Schema([SavedTrip.self, SavedStop.self, SavedProject.self, SavedMediaItem.self, SavedCaption.self, PlannedTrip.self, PlannedStop.self, PlaceToVisit.self])
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        TempFileCleanup.purgeStaleTemporaryFiles()
        // 15.09.2026 — patrz `AnalyticsLogger`. Tu, nie w `HomeView.onAppear`,
        // żeby liczyć RAZY appka faktycznie wystartowała (zimny start), nie
        // razy `HomeView` się zrenderował (może się zdarzyć wielokrotnie w
        // jednej sesji przy nawigacji).
        AnalyticsLogger.log(.appOpened)
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(Self.container)
        // 30.08.2026, user: "nie chce zeby zawalala telefon jesli ktos z
        // niej korzysta" — czyszczenie WYŁĄCZNIE przy zimnym starcie
        // (`init()` wyżej) nie odpala się w ogóle dopóki ktoś nie
        // force-quituje appki, a większość userów tego nie robi (appka
        // zwyczajnie wisi w tle). Sprawdzone na żywo na "Pit": 403MB w 303
        // plikach tymczasowych (głównie cache renderów zdjęć z powtórnych
        // eksportów, `PhotoRenderCache`) po ok. godzinie testowania w JEDNEJ
        // ciągłej sesji, bez ani jednego restartu. Dodatkowe czyszczenie przy
        // KAŻDYM zejściu appki do tła — znacznie częstsza, realna okazja niż
        // czekanie na pełny restart.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                TempFileCleanup.purgeStaleTemporaryFiles()
            }
        }
    }
}
