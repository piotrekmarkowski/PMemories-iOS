import MediaPlayer

/// Podpowiedzi piosenek Z WŁASNEJ biblioteki usera (31.08.2026, user: "czy
/// AI moze podpowiadac piosenke jaka mozna dodac do swoich zdjec") — appka
/// nie ma dostępu do żadnego zewnętrznego katalogu muzycznego (Spotify/cały
/// Apple Music, wymagałoby płatnego API), tylko do lokalnej biblioteki Apple
/// Music/zakupionych utworów usera (`MPMediaQuery`, ten sam framework co
/// `MusicPicker`). Dopasowanie po WYSTĘPOWANIU słowa kluczowego w tagu
/// gatunku (case-insensitive substring), nie dokładnym dopasowaniu — tagi
/// gatunku w realnych bibliotekach są bardzo niespójne ("Hip-Hop/Rap" vs
/// "Hip Hop"), ścisłe porównanie prawie nigdy niczego by nie znalazło.
enum MusicLibrarySuggester {
    static func suggestions(matchingAny keywords: [String], limit: Int = 3) async -> [MPMediaItem] {
        let status = await requestAuthorizationIfNeeded()
        guard status == .authorized else { return [] }
        guard let items = MPMediaQuery.songs().items, !items.isEmpty else { return [] }

        let lowerKeywords = keywords.map { $0.lowercased() }
        let matches = items.filter { item in
            guard let genre = item.genre?.lowercased(), !genre.isEmpty else { return false }
            return lowerKeywords.contains { genre.contains($0) }
        }
        return Array(matches.shuffled().prefix(limit))
    }

    /// `MPMediaQuery` (w odróżnieniu od `MPMediaPickerController`, który sam
    /// obsługuje autoryzację przez swój systemowy UI) wymaga jawnego
    /// zapytania o dostęp do biblioteki medialnej przy pierwszym użyciu z
    /// kodu — `NSAppleMusicUsageDescription` appka ma już w Info.plist od
    /// samego początku (potrzebny też dla `MusicPicker`).
    private static func requestAuthorizationIfNeeded() async -> MPMediaLibraryAuthorizationStatus {
        let current = MPMediaLibrary.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
