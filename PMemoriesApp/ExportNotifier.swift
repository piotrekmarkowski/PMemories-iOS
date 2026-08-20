import UserNotifications

/// Powiadomienie lokalne po zakończeniu długiego eksportu (filmiku w Studio
/// LUB mapy podróży) — user 31.07.2026: "czy możemy dodać zapisywanie w
/// tle... żeby można było robić coś innego i tylko dostać komunikat?".
///
/// **Uczciwe ograniczenie platformy (nie appki)**: iOS NIE pozwala zwykłej
/// appce działać w tle bez końca — `beginBackgroundTask` (patrz
/// `EditView.performExport`/`TravelMapAnimationView.saveVideo`) daje tylko
/// dodatkowe, ograniczone okno czasu po zejściu appki z ekranu (rzędu
/// kilkunastu-kilkudziesięciu sekund, nie gwarancja przy DŁUGIM odejściu).
/// Powiadomienie mówi userowi PRAWDĘ o wyniku (sukces/błąd) niezależnie od
/// tego czy appka była w tle czy na pierwszym planie — ale bardzo długi
/// eksport przy w pełni zablokowanym telefonie może zostać przerwany przez
/// system zanim zdąży się dokończyć, tak jak każda inna appka na iOS bez
/// specjalnego uprawnienia (np. nawigacja/muzyka).
enum ExportNotifier {
    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        // Appka na pierwszym planie NIE pokazuje domyślnie banera
        // powiadomienia — bez tego user siedzący w appce nigdy by go nie
        // zobaczył, tylko odbiorcy w tle/na innym ekranie.
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            completionHandler([.banner, .sound])
        }
    }

    private static let delegate = Delegate()

    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
