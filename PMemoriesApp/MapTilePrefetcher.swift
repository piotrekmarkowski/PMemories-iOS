import MapKit
import UIKit

/// Ściąga kafelki satelitarne dla współrzędnej Z WYPRZEDZENIEM, zanim user
/// w ogóle dotrze tam animacją — user 01.08.2026: "jak tylko ktoś zmieni
/// skąd na dokąd, powinno się już ściągać mapę, żeby wybór kolejnego
/// miejsca był tylko formalnością". MapKit samo z siebie tego nie robi
/// (patrz `Travel.md`, backlog "prefetch kolejnego przystanku") — jest
/// reaktywne, ładuje TYLKO to co aktualnie widoczne, nie zna naszej
/// zaplanowanej trasy kamery z góry (to appka wie, przez
/// `TravelCinematics`/`RouteProvider`, nie MapKit).
///
/// Ta ukryta `MKMapView` (ten sam trik co `TravelMapVideoRenderer.
/// makeSession` — bardzo niski `windowLevel`, user jej nigdy nie widzi)
/// odwiedza kilka kluczowych dystansów kamery używanych realnie przez
/// `TravelCinematics` (bliski "dronowy" start/koniec + przelotowy środek),
/// żeby te same kafelki były już w pamięci podręcznej MapKit (współdzielonej
/// systemowo między WSZYSTKIMI `MKMapView`, nie per-instancja) zanim user
/// faktycznie odtworzy animację na żywej mapie.
enum MapTilePrefetcher {
    @MainActor
    static func prefetch(coordinate: CLLocationCoordinate2D, mapTheme: MapTheme = .satellite) {
        Task { @MainActor in
            await prefetchAwaiting(coordinate: coordinate, mapTheme: mapTheme)
        }
    }

    /// BUG znaleziony 01.08.2026 (user, po wielu zgłoszeniach: "mapa się nie
    /// może załadować bo samolot startuje za szybko i ląduje za szybko") —
    /// `prefetch` był wołany WYŁĄCZNIE z edytora trasy (nowy przystanek),
    /// NIGDY z ekranu odtwarzania zapisanej podróży
    /// (`TravelMapAnimationView`/`TravelLiveMapView`). Dla replayu
    /// istniejącej trasy kafelki na docelowym, bliskim zoomie nigdy nie
    /// dostawały sygnału "ściągnij się wcześniej" — zaczynały się ładować
    /// DOPIERO w trakcie samego zjazdu kamery. Naprawa NIE blokuje startu
    /// animacji (user: "kolejne czekanie... nie podoba mi się to") — zamiast
    /// tego `TravelLiveMapView.runAnimation` woła `prefetch` (fire-and-forget,
    /// tak jak edytor) dla NASTĘPNEGO przystanku w tle, w momencie startu
    /// KAŻDEGO odcinka — cały czas trwania lotu (kilka-kilkanaście sekund)
    /// to naturalny zapas czasu na ściągnięcie kafelków celu, zero dodatkowego
    /// widocznego czekania.
    @MainActor
    private static func prefetchAwaiting(coordinate: CLLocationCoordinate2D, mapTheme: MapTheme = .satellite) async {
            guard let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }

            let size = CGSize(width: 200, height: 200)
            let window = UIWindow(windowScene: windowScene)
            window.frame = CGRect(origin: .zero, size: size)
            window.windowLevel = UIWindow.Level(rawValue: -10_000)
            window.isUserInteractionEnabled = false

            let mapView = MKMapView(frame: CGRect(origin: .zero, size: size))
            mapView.preferredConfiguration = mapTheme.mapConfiguration
            mapView.pointOfInterestFilter = mapTheme.pointOfInterestFilter

            let hostViewController = UIViewController()
            hostViewController.view = mapView
            window.rootViewController = hostViewController
            window.isHidden = false
            defer { window.isHidden = true }

            let delegate = PrefetchRenderDelegate()
            mapView.delegate = delegate

            // BUG znaleziony 01.08.2026 (user: zrzuty ekranu + wideo
            // pokazały szarą plamę na trasie Londyn→Lanzarote, 2795 km) —
            // lista dystansów kończyła się na 2 mln metrów, ale
            // `TravelCinematics.baseCameraDistance` dla odcinka tej
            // długości daje kamerę "cruise" na ~6.6 mln metrów (policzone:
            // interpolacja log10 między kotwicami 1500km/3M i 3000km/7M) —
            // czyli DOKŁADNIE ten poziom zoomu nigdy nie był prefetchowany.
            // Rozszerzone do 6 mln i `ceilingDistance` (12 mln, najdalsza
            // możliwa kamera dla tras 6000km+) — teraz pokrywa CAŁY zakres
            // jaki `TravelCinematics` w ogóle może wybrać, nie tylko
            // krótkie/średnie odcinki.
            let distances: [CLLocationDistance] = [
                TravelCinematics.establishingDistance, 500_000, 2_000_000, 6_000_000, TravelCinematics.ceilingDistance
            ]
            for distance in distances {
                mapView.camera = MKMapCamera(lookingAtCenter: coordinate, fromDistance: distance, pitch: 0, heading: 0)
                await delegate.waitForRender(timeoutSeconds: 4.0)
            }
    }

    @MainActor
    private final class PrefetchRenderDelegate: NSObject, MKMapViewDelegate {
        private var continuation: CheckedContinuation<Void, Never>?

        func waitForRender(timeoutSeconds: Double) async {
            await withCheckedContinuation { cont in
                continuation = cont
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    self.resume()
                }
            }
        }

        nonisolated func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            guard fullyRendered else { return }
            Task { @MainActor in self.resume() }
        }

        private func resume() {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume()
        }
    }
}
