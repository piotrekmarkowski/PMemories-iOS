import Foundation
import SwiftData

/// Trwały zapis projektu montażu (SwiftData) — drugi kawałek fundamentu z
/// `Docs/Database.md`, po `SavedTrip`. Przed tym `EditView` tracił cały stan
/// (kolejność, ruch Live Photo, muzyka) przy zamknięciu appki.
///
/// NIE przechowujemy samych zdjęć/wideo (ciężkie, i tak żyją w bibliotece
/// Photos) — tylko `assetLocalIdentifier` (PHAsset.localIdentifier, ten sam
/// co `MediaItem.pickerItemId`), z którego `MediaAssetLoader` odtwarza
/// miniaturki i pliki wideo na żądanie przy otwarciu projektu.
@Model
final class SavedProject {
    // Wartości domyślne PRZY DEKLARACJI na WSZYSTKICH polach (nie tylko tam,
    // gdzie już złapaliśmy błąd) — SwiftData przy automatycznej migracji
    // lekkiej potrzebuje wartości domyślnej bezpośrednio na polu, żeby
    // dopisać ją do already-persisted rekordów sprzed dodania danego pola.
    // Ich brak gdziekolwiek w tych pięciu modelach powodował że CAŁA baza
    // danych przestawała się ładować przy starcie appki ("Cannot migrate
    // store in-place: Validation error missing attribute values on
    // mandatory destination attribute") — SwiftData po cichu podstawiał
    // pustą bazę zamiast crashować, więc wyglądało jakby NIC się nie
    // zapisywało, mimo że `insert`/`save` nie rzucały żadnego błędu
    // (28.07.2026, wielogodzinna sesja diagnostyczna — realna przyczyna
    // znaleziona dopiero przez `--console` i prawdziwy log CoreData).
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Ręczna korekta daty podróży (04.08.2026, user: "dodajmy też opcję
    /// edycji daty, żeby w razie czego mógł ktoś poprawić") — Library grupuje
    /// projekty wg PRAWDZIWEJ daty podróży (najwcześniejsza data zdjęcia w
    /// projekcie, `MediaAssetLoader.earliestCreationDate`), nie wg
    /// `createdAt`/`updatedAt`. To pole wygrywa nad auto-wykrytą datą, gdy
    /// user ją ręcznie poprawi (np. zdjęcia bez metadanych daty, albo
    /// metadane błędne). `nil` = appka używa auto-wykrytej daty.
    var manualTripDate: Date?
    /// Kategoria Memory poza podróżami (`MemoryCategory`, 10.08.2026) —
    /// `nil` = brak kategorii (zachowanie sprzed tej funkcji). Surowy
    /// String zamiast wprost `MemoryCategory?` z tego samego powodu co
    /// `enabledTransitionStylesRaw`/`colorStyleRaw` niżej — SwiftData
    /// lekka migracja chce prostego typu wartości domyślnej na polu.
    var categoryRaw: String?
    var category: MemoryCategory? {
        get { categoryRaw.flatMap(MemoryCategory.init(rawValue:)) }
        set { categoryRaw = newValue?.rawValue }
    }
    /// Które style przejść (`TransitionStyle`) appka wolno wybierać przy
    /// auto-doborze (09.08.2026, user: "użytkownik sobie wybiera jakie
    /// przejścia chce i ile, program automatycznie sam je rozmieszcza") —
    /// rawValues rozdzielone przecinkiem, `nil` = wszystkie dozwolone
    /// (zachowanie sprzed tej funkcji, bez zmian dla już zapisanych
    /// projektów). Wpływa TYLKO na klipy bez ręcznie ustawionego stylu
    /// (`SavedMediaItem.transitionStyleRawValue == nil`) — ręczny wybór per
    /// klip zawsze wygrywa, tak jak dotąd.
    var enabledTransitionStylesRaw: String?
    /// Filtr kolorystyczny na cały film (`ColorStyle`, 09.08.2026) — `nil`
    /// = brak (`ColorStyle.none`), appka eksportuje jednym przebiegiem jak
    /// dotychczas. Cokolwiek innego = drugi przebieg eksportu przez
    /// `ColorGrader` PO głównym renderze.
    var colorStyleRaw: String?
    /// `MPMediaItem.persistentID` wybranego utworu — stabilny identyfikator
    /// do ponownego odnalezienia utworu przez `MPMediaQuery`. `nil` = brak.
    var musicPersistentID: UInt64?
    /// Głośność muzyki w tle (0-1) — niezależna od głośności oryginalnego
    /// dźwięku klipów (`SavedMediaItem.originalVolume`).
    var musicVolume: Double = 1.0
    /// `PHAsset.localIdentifier` ostatniego wyeksportowanego wideo — user:
    /// "żeby nie szukać w telefonie tych filmików, tylko włączać je z
    /// poziomu aplikacji". Appka NIE trzyma samego pliku (jak reszta modelu
    /// — dane żyją w bibliotece Photos), tylko wskaźnik do niego, żeby
    /// Library mogło pokazać przycisk odtwarzania. `nil` = jeszcze
    /// niewyeksportowany.
    var exportedAssetIdentifier: String?
    @Relationship(deleteRule: .cascade, inverse: \SavedMediaItem.project)
    var items: [SavedMediaItem] = []
    @Relationship(deleteRule: .cascade, inverse: \SavedCaption.project)
    var captions: [SavedCaption] = []
    /// Nakładki "picture-in-picture" — Faza 1 "prawdziwego multi-tracku"
    /// (patrz `Docs/Studio.md`). Ten sam wzorzec relacji co `captions`.
    @Relationship(deleteRule: .cascade, inverse: \SavedOverlayItem.project)
    var overlays: [SavedOverlayItem] = []

    init(
        id: UUID = UUID(), title: String, createdAt: Date = Date(), updatedAt: Date = Date(),
        musicPersistentID: UInt64? = nil, musicVolume: Double = 1.0,
        items: [SavedMediaItem] = [], captions: [SavedCaption] = [], overlays: [SavedOverlayItem] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.musicPersistentID = musicPersistentID
        self.musicVolume = musicVolume
        self.items = items
        self.captions = captions
        self.overlays = overlays
    }
}

/// Trwały zapis jednego napisu (patrz ulotny `Caption`).
@Model
final class SavedCaption {
    var text: String = ""
    var startTime: Double = 0
    var endTime: Double = 3
    var positionRawValue: String = CaptionPosition.bottom.rawValue
    var fontRawValue: String = CaptionFont.helvetica.rawValue
    var order: Int = 0
    /// "Share with Family" tłumaczenia — JSON-owany `[String: String]`
    /// (kod języka → tekst), bo SwiftData nie wspiera wprost słowników.
    var translationsJSON: String?
    var project: SavedProject?

    init(text: String, startTime: Double, endTime: Double, positionRawValue: String, fontRawValue: String = CaptionFont.helvetica.rawValue, translationsJSON: String? = nil, order: Int) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.positionRawValue = positionRawValue
        self.fontRawValue = fontRawValue
        self.translationsJSON = translationsJSON
        self.order = order
    }
}

@Model
final class SavedMediaItem {
    var assetLocalIdentifier: String = ""
    var isLivePhoto: Bool = false
    var isVideo: Bool = false
    var useMotion: Bool = false
    var duration: Double = 3.0
    /// Kolejność w timeline — SwiftData nie gwarantuje kolejności relacji.
    var order: Int = 0
    /// Punkt startowy w źródłowym klipie (sekundy) — patrz `MediaItem.trimStart`.
    var trimStart: Double = 0
    /// Czy `duration`/`trimStart` zostały ustawione ręcznie w Trim (żeby
    /// automatyczne rozłożenie czasu po zmianie utworu ich nie nadpisało).
    var isManuallyTrimmed: Bool = false
    /// Mnożnik prędkości odtwarzania — patrz `MediaItem.speed`.
    var speed: Double = 1.0
    /// Patrz `MediaItem.rotationDegrees`/`cropFill`. Wartości domyślne PRZY
    /// DEKLARACJI (nie tylko w `init`) — SwiftData przy automatycznej
    /// migracji lekkiej potrzebuje wartości domyślnej bezpośrednio na polu,
    /// żeby dopisać ją do already-persisted rekordów sprzed dodania tego
    /// pola. Ich brak (na tym polu i `originalVolume` niżej) powodował że
    /// CAŁA baza danych przestawała się ładować przy starcie appki
    /// ("Cannot migrate store in-place: Validation error missing attribute
    /// values on mandatory destination attribute") — SwiftData po cichu
    /// podstawiał pustą bazę zamiast crashować, więc wyglądało jakby NIC się
    /// nie zapisywało (28.07.2026, długa sesja diagnostyczna).
    var rotationDegrees: Int = 0
    var cropFill: Bool = false
    /// Patrz `MediaItem.originalVolume`.
    var originalVolume: Double = 1.0
    /// Patrz `MediaItem.transitionStyle` — `nil` = auto. Wartość domyślna
    /// PRZY DEKLARACJI (nie tylko w `init`), z tego samego powodu co
    /// `rotationDegrees`/`cropFill` wyżej — lekka migracja SwiftData.
    var transitionStyleRawValue: String?
    var project: SavedProject?

    init(
        assetLocalIdentifier: String, isLivePhoto: Bool, isVideo: Bool,
        useMotion: Bool, duration: Double, order: Int,
        trimStart: Double = 0, isManuallyTrimmed: Bool = false, speed: Double = 1.0,
        rotationDegrees: Int = 0, cropFill: Bool = false, originalVolume: Double = 1.0,
        transitionStyleRawValue: String? = nil
    ) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.isLivePhoto = isLivePhoto
        self.isVideo = isVideo
        self.useMotion = useMotion
        self.duration = duration
        self.order = order
        self.trimStart = trimStart
        self.isManuallyTrimmed = isManuallyTrimmed
        self.speed = speed
        self.rotationDegrees = rotationDegrees
        self.cropFill = cropFill
        self.originalVolume = originalVolume
        self.transitionStyleRawValue = transitionStyleRawValue
    }
}

/// Trwały zapis jednej nakładki "picture-in-picture" (patrz ulotny
/// `OverlayItem`). Czas liczony WZGLĘDEM CAŁEGO finalnego filmiku, ten sam
/// wzorzec co `SavedCaption.startTime`/`endTime`, nie względem pozycji w
/// głównym torze (`SavedMediaItem.order`).
@Model
final class SavedOverlayItem {
    var assetLocalIdentifier: String = ""
    var isLivePhoto: Bool = false
    var isVideo: Bool = false
    var useMotion: Bool = false
    var globalStartTime: Double = 0
    var duration: Double = 3.0
    var cornerRawValue: String = OverlayCorner.bottomTrailing.rawValue
    var sizeScale: Double = 0.35
    var order: Int = 0
    var project: SavedProject?

    init(
        assetLocalIdentifier: String, isLivePhoto: Bool, isVideo: Bool, useMotion: Bool,
        globalStartTime: Double, duration: Double, cornerRawValue: String, sizeScale: Double, order: Int
    ) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.isLivePhoto = isLivePhoto
        self.isVideo = isVideo
        self.useMotion = useMotion
        self.globalStartTime = globalStartTime
        self.duration = duration
        self.cornerRawValue = cornerRawValue
        self.sizeScale = sizeScale
        self.order = order
    }
}
