import MapKit
import SwiftUI

/// Motyw wizualny mapy Travel Map — wybierany przez usera przed odtworzeniem
/// animacji, ten sam wybór stosowany w żywym podglądzie (`Map.mapStyle`) i w
/// eksportowanym wideo (`MKMapSnapshotter.Options.mapType`), żeby wynik nie
/// zaskakiwał.
enum MapTheme: String, CaseIterable, Identifiable {
    case satellite
    case minimalWhite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .satellite: return L("Satellite")
        case .minimalWhite: return L("Minimal White")
        }
    }

    var icon: String {
        switch self {
        case .satellite: return "globe.americas.fill"
        case .minimalWhite: return "map"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .satellite:
            return .hybrid(elevation: .realistic)
        case .minimalWhite:
            return .standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false)
        }
    }

    var snapshotterMapType: MKMapType {
        switch self {
        case .satellite: return .hybrid
        case .minimalWhite: return .standard
        }
    }

    /// Odpowiednik filtra POI zakodowanego wprost w `mapStyle` — satelita
    /// (`.hybrid(elevation: .realistic)`) NIE filtruje POI w żywym
    /// podglądzie, więc eksport też nie powinien (inaczej znika cała
    /// warstwa podpisów: nazwy miast/mórz/granice, nie tylko punkty
    /// zainteresowania — odkryte 27.07.2026 przy porównaniu zrzutu żywego
    /// podglądu z eksportem). Minimal White jawnie filtruje w `mapStyle`
    /// (`pointsOfInterest: .excludingAll`), więc eksport robi to samo.
    var pointOfInterestFilter: MKPointOfInterestFilter {
        switch self {
        case .satellite: return .includingAll
        case .minimalWhite: return .excludingAll
        }
    }

    /// Odpowiednik `mapStyle` dla `MKMapView` (UIKit/AppKit) —
    /// `preferredConfiguration`, NIE starsza `mapType`. Kluczowe:
    /// `elevationStyle: .realistic` to ta sama właściwość co
    /// `.hybrid(elevation: .realistic)` w SwiftUI — bez niej `MKMapView`
    /// renderuje płaską mapę zamiast widoku globusa z widoczną krzywizną,
    /// mimo identycznej `MKMapCamera` (odkryte 27.07.2026 — eksport z
    /// `MKMapView` nie pokazywał krzywizny, mimo tego samego dystansu co
    /// żywy podgląd, bo ustawiał tylko `mapType`, nie `preferredConfiguration`).
    var mapConfiguration: MKMapConfiguration {
        switch self {
        case .satellite:
            return MKHybridMapConfiguration(elevationStyle: .realistic)
        case .minimalWhite:
            let config = MKStandardMapConfiguration(elevationStyle: .flat)
            config.pointOfInterestFilter = .excludingAll
            config.showsTraffic = false
            return config
        }
    }

    var showsBuildingsInSnapshot: Bool {
        self == .satellite
    }

    /// "Minimal White" ma zawsze wyglądać jasno, niezależnie od trybu
    /// ciemnego systemu — satelita nie potrzebuje wymuszania (zdjęcie
    /// satelitarne nie zależy od light/dark).
    var forcedColorScheme: ColorScheme? {
        self == .minimalWhite ? .light : nil
    }
}
