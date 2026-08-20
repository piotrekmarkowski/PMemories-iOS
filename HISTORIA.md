# PMemories iPhone — HISTORIA

Natywna appka iOS (Swift/SwiftUI, Xcode + xcodegen) do montażu filmików z wakacji ze zdjęć i wideo, z własną muzyką, przejściami i obsługą Live Photo jako ruchomego klipu (nie statycznego zdjęcia, jak w CapCut/InShot). Osobny projekt od Python-owego `~/Desktop/PMemories/` (upscaling przez Real-ESRGAN — temat Roswell tam ZAMKNIĘTY 22.07).

## Stan na 24.07.2026

### Ustalenia (dyskusja z userem)
- Kluczowa przewaga funkcjonalna: Live Photo traktowane jako 3-sekundowy klip z ruchem (`PHAssetResource` typu `pairedVideo`), nie jak zwykłe zdjęcie.
- Dopasowanie do muzyki: start od prostego sklejenia do zadanej długości (dzielenie czasu utworu przez liczbę klipów). Cięcie na beat (beat detection) odłożone na później, może wcale.
- Export: `AVMutableComposition` + `AVAssetExportSession`.
- Zakres MVP (~miesiąc pracy): (1) picker zdjęć/wideo, (2) toggle Live Photo per element, (3) wybór muzyki z biblioteki, (4) równy rozkład klipów na długość utworu, (5) export do rolki. Beat sync/przejścia/filtry/napisy — po MVP.
- User wybrał zacząć od tego projektu zamiast dokończenia kontaktów na stronie portfolio (ten temat wciąż czeka).

### Zrobione
- Scaffold projektu: `project.yml` (xcodegen), target iOS 18.0, bundle id `com.piotrmarkowski.pmemories`, uprawnienia w Info.plist (`NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`, `NSAppleMusicUsageDescription`).
- `PMemoriesAppApp.swift` — entry point.
- `MediaItem.swift` — model elementu sekwencji (id, isLivePhoto, isVideo, thumbnail, useMotion, duration).
- `ContentView.swift` — `PhotosPicker` (multi-select zdjęcia+wideo), lista z drag-to-reorder (`onMove`), toggle "ruch" dla wykrytych Live Photo, placeholdery (disabled) na wybór muzyki i export.
- `xcodegen generate` + `xcodebuild -destination "generic/platform=iOS Simulator" build` → **BUILD SUCCEEDED**.

### MVP — kompletny szkielet (24.07, ciągiem, bez przerywania na testy — user: "kontynuuj później będziemy naprawiać")
Wszystkie 5 punktów MVP zaimplementowane i budują się (`xcodebuild -destination "generic/platform=iOS Simulator" build` → **BUILD SUCCEEDED** po każdym kroku). Kod **nie był jeszcze uruchomiony na symulatorze/urządzeniu** — tylko weryfikacja kompilacji. Pliki:

1. **Picker + toggle Live Photo** — `ContentView.swift`, `MediaItem.swift`. `PhotosPicker` (multi-select), lista z drag-to-reorder, toggle "ruch" dla wykrytych Live Photo.
2. **Paired video z Live Photo** — `LivePhotoVideoExtractor.swift`. `PHAsset.fetchAssets(withLocalIdentifiers:)` → `PHAssetResource` typu `.pairedVideo` → `PHAssetResourceManager.writeData(for:toFile:)` do pliku tymczasowego.
3. **Wybór muzyki** — `MusicPicker.swift`, wrapper `UIViewControllerRepresentable` na `MPMediaPickerController` (single-song, `showsCloudItems = false`).
4. **Równy rozkład czasu** — `redistributeDurations()` w `ContentView.swift`, przelicza się przy zmianie `items.count` lub `selectedSong` (`onChange`).
5. **Export** — `VideoComposer.swift` (buduje `AVMutableComposition`: dla każdego elementu wybiera realne wideo > paired video z Live Photo (jeśli `useMotion`) > wyrenderowane zdjęcie statyczne przez `ImageToVideoRenderer.swift` (`AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor`, aspect-fill 1080x1920@30fps); dokleja ścieżkę audio z `selectedSong.assetURL` przycięty do długości wideo). `VideoExporter.swift` — nowe (iOS 18) `AVAssetExportSession.export(to:as:)` async, potem `PHPhotoLibrary.performChanges` zapisuje do rolki. `MovieFile.swift` — custom `Transferable` do wyciągania realnego pliku wideo z `PhotosPickerItem` (potrzebne bo picker nie ma wbudowanego transferable dla wideo).

### Znane ograniczenia / ryzyka do przetestowania na realu (user zdecydował naprawiać w miarę potrzeby, nie teraz)
- **Nigdy nie uruchomione** — tylko `xcodebuild build`, zero testów na symulatorze/urządzeniu, zero testów z prawdziwymi zdjęciami/Live Photo/muzyką.
- `MPMediaItem.assetURL` bywa `nil` dla utworów z Apple Music (DRM/chmura) — `showsCloudItems = false` ogranicza trochę ryzyko, ale utwory kupione/matched w iCloud Music Library nadal mogą nie mieć `assetURL`. Brak obsługi tego przypadku (audio po prostu nie zostanie dodane, cicho).
- `PHAssetResource.pairedVideo` — nie sprawdzone czy `itemIdentifier` z `PhotosPicker` (bez jawnego `PHPhotoLibrary.requestAuthorization`) faktycznie daje dostęp do zasobów assetu w każdym przypadku (limited library access).
- Sklejanie klipów o różnych naturalnych rozmiarach/orientacjach w jednej `AVMutableCompositionTrack` bez `AVMutableVideoComposition` z instrukcjami transformacji — może dawać niespójne kadrowanie między elementami (różne proporcje wideo vs renderowane zdjęcia 1080x1920).
- Brak przycinania/pętli gdy źródłowy klip jest krótszy niż zadany `duration` (bierze co jest, nie zapętla).
- `ImageToVideoRenderer` może być wolny/pamięciożerny dla wielu zdjęć naraz (synchroniczne renderowanie jeden po drugim w `VideoComposer`, brak równoległości).

### Do zrobienia (poza MVP)
- Realne uruchomienie i debug na symulatorze/urządzeniu.
- Beat sync, przejścia, filtry, napisy/emotki.

## Stan na 24.07.2026, ciąg dalszy — instalacja na realnym telefonie

- Dodane `DEVELOPMENT_TEAM: X3NAM3PL95` w `project.yml` (ten sam zespół co PMTalk) — bez tego automatyczne podpisywanie nie działa z linii poleceń (`xcodebuild ... -allowProvisioningUpdates`).
- Dodana `Assets.xcassets/AppIcon.appiconset` — pojedynczy plik `icon_1024.png` (idiom `universal`/`ios`, nowoczesne uproszczone podejście Xcode 14+, system sam generuje pozostałe rozmiary).
- Zbudowane pod realne urządzenie (`xcrun devicectl list devices` → "Pit", iPhone 16 Pro), zainstalowane i uruchomione przez `xcrun devicectl device install app` / `device process launch`.
- **Ikona miała czarne krawędzie po prawej/na dole na telefonie** — ten sam problem i ten sam fix co w `PMemories Mac/HISTORIA.md` (pełny opis tam): źródłowa grafika w moodboardzie ma zaokrąglone rogi na ciemnym tle, więc kwadratowy crop zawsze łapie trochę ciemnego tła w narożnikach; iOS/macOS nie lubią przezroczystości w ikonach (renderuje się jako czarne). Fix: wypełnić całe płótno nieprzezroczystą bielą PRZED narysowaniem zawartości, dopiero potem `clip()` do zaokrąglonego kształtu pasującego do ikonki. Poprawiona ikona przeinstalowana na telefonie.
- Uwaga: appka na telefonie ma na razie SUROWY interfejs (bez `HeaderView`/`Palette` z wersji Mac) — tylko nowa ikonka na ekranie głównym. User świadomie zaakceptował to na razie ("później będziemy robić update").
- **Pierwsze uruchomienie na telefonie wymaga ręcznego zaufania deweloperowi**: Ustawienia → Ogólne → VPN i zarządzanie urządzeniem → zaufaj certyfikatowi (bo to podpis z darmowego/osobistego konta Apple, nie dystrybucja przez App Store/TestFlight).

### iOS 18 Light/Dark/Tinted — 3 warianty ikony
User zauważył na telefonie 3 różne wyglądy ikony w zależności od pory dnia/trybu — to iOS 18 automatycznie generujący warianty Dark/Tinted skoro dostarczyłem tylko jeden (Light). Naprawione: dodane w `Contents.json` dwa dodatkowe wpisy z `"appearances": [{"appearance":"luminosity","value":"dark"|"tinted"}]`:
- **Dark** — wycięty wariant z ciemnym tłem z tego samego moodboardu (rząd "ICON VARIANTS", wariant 2). Współrzędne finalne: `x=811, y=350, size=115` (dużo mniejszy box niż wariant biały — ikonki w tym rzędzie są mniejsze niż w hero-shocie "APP ICON"). Wypełnienie tła kolorem `#10131A` (ten sam mechanizm co biały wariant — wypełnij tłem PRZED narysowaniem, żeby uniknąć przezroczystości/czarnych krawędzi).
- **Tinted** — Apple zaleca wersję przygotowaną pod desaturację (system i tak nakłada własny kolor). Wygenerowana przez konwersję finalnej białej ikonki do skali szarości (`grayscale.swift`: RGB → DeviceGray → z powrotem RGB, żeby Xcode zaakceptował format).

**Do zapamiętania**: dla ciemnych wariantów precyzja kadrowania jest MNIEJ krytyczna niż dla jasnych (kolor tła ikonki = kolor tła strony w moodboardzie, więc drobne niedopasowanie kadru jest niewidoczne — w przeciwieństwie do jasnego wariantu na ciemnym tle, gdzie każdy piksel różnicy jest widoczny). Przy dark-on-dark zwykłe czytanie krawędzi z siatką współrzędnych zawodzi (za mały kontrast) — lepiej działa automatyczna detekcja bounding-boxa po NASYCENIU koloru (`find_colorful.swift`: szukaj pikseli gdzie max(R,G,B)-min(R,G,B) jest duże, nie po jasności) żeby namierzyć środek kolorowego monogramu, a potem dobrać rozmiar kadru iteracyjnie sprawdzając w 1024px.

## Stan na 24.07.2026 — Travel Map (pierwszy "wow" feature z wizji produktu)

User przysłał obszerną wizję produktu (AI Story Creator, Emotion AI, AI Director, Travel Map, Voice Over, itp.) jako TODO backlog do wprowadzania stopniowo. Uczciwa ocena wykonalności: część realna on-device od ręki (chronologia z EXIF, wykrywanie scen przez Vision, TTS), część to spory kawałek roboty (beat-sync, import z chmur), część to osobne projekty badawcze (transfer stylu wideo, rozpoznawanie emocji/akcji w wideo, OCR biletów). User zdecydował zacząć od **Travel Map** jako pierwszego, najbardziej "wow" elementu — wskazał referencyjne wideo (appka "Mult"): satelitarny globus, animowany łuk lotu (geodesic), ikona transportu jadąca po trasie, karta miasta/flagi/kraju na końcu odcinka.

**Zaimplementowane** (interaktywny podgląd w appce — NIE jeszcze wypalanie do eksportowanego wideo, to osobne zadanie na później, dużo trudniejsze technicznie: renderowanie MapKit klatka-po-klatce do AVAssetWriter):
- `TravelMap.swift` — model `TripStop` (miasto, transport, współrzędne, kraj, kod kraju) i `TransportMode` (plane/train/car/boat), `CityGeocoder` (CLGeocoder.geocodeAddressString — proste wpisanie nazwy miasta, user NIE musi fotografować biletu, zgodnie z życzeniem), emoji flagi z kodu ISO kraju.
- `TravelMapView.swift` — lista przystanków (dodawanie/usuwanie), pole tekstowe na miasto + picker środka transportu (dla wszystkich poza pierwszym), przycisk "Pokaż trasę" geokodujący wszystkie miasta i przechodzący do animacji.
- `TravelMapAnimationView.swift` — SwiftUI `Map` (`.mapStyle(.hybrid(elevation: .realistic))` — satelitarny 3D), `MKGeodesicPolyline` do łuku po kuli ziemskiej między przystankami, animacja krok po kroku (kamera leci do regionu obejmującego trasę, ikona transportu przesuwa się wzdłuż punktów łuku, karta miasta/flagi pojawia się na końcu odcinka).

Wpięte pod zakładkę "Templates" w `HomeView` (placeholder tylko tymczasowo tam siedział — nazwa zakładki zostaje "Templates" z mockupu, ale zawartość to już realny Travel Map, nie "wkrótce").

Build (`xcodebuild` symulator + realne urządzenie) → **BUILD SUCCEEDED**, zainstalowane na telefonie.

### Do zrobienia dalej
- Wypalenie animacji Travel Map do faktycznego eksportowanego wideo (żeby "film kończył się animowaną mapą" jak w oryginalnej wizji) — wymaga renderowania `Map` klatka-po-klatce (np. przez `ImageRenderer` na każdą klatkę animacji) i zapisania przez `AVAssetWriter`, tak jak `ImageToVideoRenderer` robi to dla zdjęć. Nietrywialne, osobne zadanie.
- Reszta listy z wizji produktu (patrz zapisana ocena wykonalności) — do wprowadzania stopniowo, po kolei.

## Stan na 24.07.2026, ciąg dalszy — Travel Map: prędkość, obrót ikony, zapis wideo, podpowiedzi

User poprosił o 4 rozszerzenia po zobaczeniu pierwszej wersji Travel Map:

1. **Prędkość animacji** — suwak 0.5x–3.0x w `TravelMapView`, przekazywany do `TravelMapAnimationView(speedMultiplier:)`, dzieli wszystkie `Task.sleep` w pętli animacji.
2. **Obracająca się ikona transportu** — liczona funkcja `bearing(from:to:)` (klasyczny wzór namiaru między współrzędnymi geograficznymi), ikona obracana przez `.rotationEffect` zgodnie z kierunkiem jazdy zamiast statycznie.
3. **Zapis jako wideo** — user doprecyzował że chodzi konkretnie o eksport do pliku (nie tylko zapamiętanie listy miast). Nowy `TravelMapVideoRenderer.swift`: zamiast ryzykownie nagrywać ŻYWY widok `Map` (kafelki satelitarne ładują się async, `ImageRenderer` na UIKit-bridged widoku to niepewny grunt), bierze **jeden nieruchomy zrzut satelitarny na odcinek** przez `MKMapSnapshotter` (synchroniczny, czeka na załadowanie kafelków), a potem dorysowuje trasę/obracaną ikonę/kartę miasta na tym samym zrzucie klatka po klatce (tanie, samo compositing, bez nowych zapytań sieciowych per klatka). Kluczowe: `snapshot.point(for: coordinate)` — oficjalna metoda MKMapSnapshotter.Snapshot do zamiany współrzędnej na piksel W TYM KONKRETNYM zrzucie (poprawna projekcja, nie własne przybliżenie liniowe). Pipeline zapisu klatek do pliku (`AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor`) skopiowany z już sprawdzonego `ImageToVideoRenderer.swift`.
4. **Podpowiedzi miast i lotnisk** — nowy `CitySearchCompleter.swift`, wrapper na `MKLocalSearchCompleter` z `resultTypes = [.address, .pointOfInterest]` i `pointOfInterestFilter` ograniczonym do `.airport` — pokazuje razem podpowiedzi miast i lotnisk. Wybranie podpowiedzi od razu rozwiązuje dokładną współrzędną przez `MKLocalSearch(completion:)` (dokładniejsze niż późniejsze geokodowanie samego wpisanego tekstu, zwłaszcza dla lotnisk).

**WAŻNE — nie przetestowane end-to-end**: kod się kompiluje i wykorzystuje sprawdzone, oficjalne API (MKMapSnapshotter, snapshot.point(for:), wzorzec AVAssetWriter skopiowany z działającego kodu), ale sam przycisk "Zapisz jako wideo" nigdy nie został kliknięty/przetestowany na realu (zgodnie z zasadą — nie klikam appki automatyzacją, user testuje ręcznie). Do sprawdzenia: czy `MKMapSnapshotter` faktycznie pokazuje krzywiznę globusa jak w referencyjnym wideo (czy to tylko live-view Apple Maps "globe mode", nie replikowane w offline snapshotterze), czy tempo/kolejność klatek wygląda dobrze, czy zapis do rolki faktycznie działa.

## Stan na 24.07.2026, ciąg dalszy — bug: "wybiera losowe miasto" po kliknięciu podpowiedzi

User zgłosił, że kliknięcie konkretnej podpowiedzi miasta wybierało inną (losową). Dwie prawdopodobne przyczyny naprawione naraz w `TravelMapView.swift` (`StopRow`):
1. **Za mały/niepewny obszar dotyku** — przyciski podpowiedzi miały tylko `Text`, bez `.frame(maxWidth: .infinity)` / `.contentShape(Rectangle())`, więc tapnięcie obok liter (ale wciąż wizualnie "w wierszu") mogło nie trafiać w button i przechodzić do czegoś innego pod spodem. Dodane pełne obszary dotyku + `.buttonStyle(.plain)`.
2. **Wyścig przy znikaniu listy** — widoczność podpowiedzi była uzależniona od `isFocused` (`@FocusState`). W `List` utrata fokusu (np. przy starcie gestu tapnięcia) mogła powodować przeładowanie wiersza W TRAKCIE gestu, więc tap lądował na czymś innym niż to, co user widział. Zmienione na zależność od `!stop.isResolved` zamiast fokusu — lista nie znika w trakcie samego gestu.
3. Przy okazji: `id: \.self` na `MKLocalSearchCompletion` (NSObject) zamienione na stabilny `id: \.offset`, i dodana ochrona `isApplyingSuggestion` żeby wybór podpowiedzi nie odpalał ponownie `completer.updateQuery` przez `onChange` (przez co lista mogła migać z powrotem po wyborze).

## Stan na 25.07.2026 — własne pseudo-3D ikonki transportu (zamiast SF Symbols)

User: SF Symbols wyglądały jako "tragedia", chciał coś zbliżonego do referencyjnego wideo (cieniowany model widziany pod kątem), ale bez prawdziwego 3D (brak zasobów/silnika — user to jasno wykluczył: "nie może być obiekt 3D"). Ostateczne podejście: własne, narysowane przez Core Graphics kształty (`vehicle_icons.swift`, tymczasowy skrypt poza projektem) — gradient (jasny→ciemniejszy w tym samym odcieniu co element) + cienki ciemny outline + miękki cień pod spodem, dla samolotu/samochodu/pociągu/promu, każdy skierowany dziobem/przodem "do góry" z założenia. Wygenerowane jako PNG 512×512, dodane jako `Vehicle-plane/car/train/boat.imageset` w `Assets.xcassets` obu projektów.

**WAŻNA PUŁAPKA po drodze (ta sama co przy generowaniu ikonki appki wcześniej, ale tym razem dotknęła bezpośrednio rysowania ścieżek wektorowych, nie tylko obrazów)**: pierwsza wersja ikon pojazdów wyszła powyrywana/odwrócona (dziób samolotu na dole zamiast na górze, okno samochodu na dole zamiast przy dachu) — `CGContext` domyślnie ma origin w LEWYM DOLNYM rogu (y rośnie W GÓRĘ), więc współrzędna y=0 w narysowanej ścieżce renderuje się na DOLE obrazu, nie na górze. Naprawione dodaniem flipa `ctx.translateBy(x:0,y:100); ctx.scaleBy(x:1,y:-1)` zaraz po ustaleniu skali, żeby y=0 w kodzie odpowiadało górze obrazu (bardziej intuicyjne przy projektowaniu kształtów). **Do zapamiętania na przyszłość**: to dotyczy TYLKO gołych `CGContext` tworzonych ręcznie (`CGContext(data: nil, ...)`) — nie dotyczy `UIGraphicsImageRenderer` (iOS, ma wbudowany flip pod UIKit-ową konwencję y-w-dół) ani samego rysowania gotowych `CGImage`/`NSImage`/`UIImage` przez `.draw(in:)` (te też mają własną, poprawną obsługę orientacji). Błąd dotyczy wyłącznie WŁASNYCH ścieżek wektorowych (linie/krzywe/kształty) rysowanych bezpośrednio w surowym `CGContext` bez uprzedniego flipa.

Skoro nowe ikony są już narysowane "przodem do góry" z założenia, usunięta cała logika `headingOffsetDegrees` (poprzednia próba korekty kąta dla płaskiego SF Symbol "airplane", który domyślnie wskazywał NE zamiast N) — rotacja to teraz zwykłe `bearing`/`angle` bez żadnej korekty, we wszystkich miejscach (`TravelMapAnimationView` i `TravelMapVideoRenderer`, oba projekty).

Podpięte w `TravelMapAnimationView.swift` (żywy podgląd, `Image(transport.imageAssetName)` zamiast `Image(systemName:)`) i `TravelMapVideoRenderer.swift` (rysowanie PNG zamiast tintowanego SF Symbol, `UIImage(named:)`/`NSImage(named:)`). Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na telefonie/uruchomione na Macu.

**Nie przetestowane end-to-end na realu przez usera** (poszedł do pracy) — sam zweryfikowałem tylko wygląd wygenerowanych PNG (przez `Read`), nie samą animację na żywym urządzeniu. Do potwierdzenia przy następnym kontakcie: czy nowe ikonki wyglądają dobrze w ruchu i czy rotacja rzeczywiście wskazuje kierunek jazdy poprawnie teraz.

## Stan na 25.07.2026, ciąg dalszy — 5 trybów transportu + emoji w pickerze, backlog Travel Map v2

User (feedback od zewnętrznego recenzenta, zaakceptowane): mniej tarcia przy wyborze środka transportu — emoji zamiast SF Symbol w pickerze (szybsze skanowanie wzrokiem), i piąty tryb "Statek wycieczkowy" (🛳️) odróżniony od zwykłego promu (⛴️).

**Zrobione:**
- `TransportMode` — dodany case `.cruise`, nowa właściwość `emoji` (✈️🚆🚗⛴️🛳️) zamiast `systemImage` w UI pickera (`TravelMapView` — `Picker` używa teraz `Text("\(mode.emoji) \(mode.label)")` zamiast `Label(_, systemImage:)`).
- Nowa ikonka "cruise" (ten sam `vehicle_icons.swift`, ten sam flip-fix co reszta) — szerszy płaski kadłub + wielopiętrowa nadbudówka (2 pokłady) + komin, kolor indygo, wyraźnie odróżnialny od jednopokładowego niebieskiego promu.

**Backlog (NIE zrobione, spisane z uczciwą oceną wykonalności na przyszłość):**
1. **Smart Route** (auto-wykrywanie trasy z GPS w zdjęciach, zero ręcznego wpisywania) — REALNE bez zewnętrznych usług: `PHAsset.location` + grupowanie po czasie/odległości, mamy już `CLGeocoder`/`MKLocalSearch` do odwrotnego dopasowania miasto/kraj. Umiarkowany nakład.
2. **Miniaturka zdjęcia w kółku na markerze przystanku** (zamiast zwykłego pinezki) — wykonalne, wymaga wybrania "najlepszego"/reprezentatywnego zdjęcia per miasto i customowego widoku adnotacji zamiast `Marker`. Umiarkowany nakład.
3. **Statystyki podróży na końcu** (kraje/miejsca/km per środek transportu/dni) — w większości wykonalne z tego co już mamy (kraje z `countryCode`, dystans przez `CLLocation.distance(from:)` per odcinek), ALE nie śledzimy dat pobytu per przystanek — trzeba by dodać pole daty do `TripStop`, żeby liczyć "dni". Łatwe-umiarkowane.
4. **Motywy mapy** (Apple/Satellite/Dark/Vintage/Blueprint) — 3 z 5 (Apple standard/Satellite/Dark) to gotowe style MapKit (`.standard`/`.hybrid`/z `colorScheme`), ale "Vintage"/"Blueprint" wymagałyby customowego stylowania kafelków mapy — MapKit tego wprost nie oferuje, dużo trudniejsze.
5. **Bogatsza animacja** (samolot zostawia ślad, statek zostawia falę) — CZĘŚCIOWO już mamy: przebyta trasa zostaje narysowana jako pełna linia za ikoną (`revealedPaths`), więc "ślad" w podstawowej formie już istnieje. Fade-out śladu / efekt fali to dodatkowy, kosmetyczny szlif, umiarkowany nakład.

User zaproponował potraktowanie Travel Map jako "wizytówki PMemories" (rozpoznawalny, charakterystyczny efekt jak szablony CapCut) — świadomy kierunek produktowy, do rozważenia przy priorytetyzacji kolejnych kroków, nie od razu.

## Stan na 25.07.2026, ciąg dalszy — realne trasy auto/pociąg, stylizowany łuk lotu, cieńsza linia

Nowy `RouteProvider.swift` (cross-platform, bez zależności UIKit/AppKit) centralizuje wybór ścieżki do narysowania per środek transportu:
- **Samochód** — prawdziwa trasa drogowa przez `MKDirections(transportType: .automobile)`, fallback do geodezji jeśli się nie uda.
- **Pociąg** — `MKDirections(transportType: .transit)`, fallback do geodezji (pokrycie transit jest bardzo nierówne poza dużymi miastami/krajami — user zaakceptował ten kompromis: "jeśli mamy trasę dajemy trasę, jeśli nie, linię prostą").
- **Samolot** — geodezja + dodany stylizowany "łuk" (`arcedGeodesic`): przesunięcie punktów trasy prostopadle do kierunku, narastające i opadające sinusoidalnie (szczyt w połowie drogi), żeby na krótszych/średnich dystansach nie wyglądało jak płaska linia prosta (user: "u nas to jest linia prosta, musi wyglądać lepiej"). Wysokość łuku ograniczona (`min(długość×0.15, 8°)`) żeby nie przesadzić na bardzo długich trasach.
- **Prom/statek wycieczkowy** — bez zmian, czysta geodezja. **Świadomie NIE zrobione**: omijanie lądu/wysp przez prawdziwą trasę morską — brak darmowego, prostego API do tego (Apple nie ma odpowiednika `MKDirections` dla żeglugi; istnieją projekty typu "searoute" oparte o osobną sieć tras morskich, ale to osobny, znacznie większy temat niż reszta). Wyjaśnione userowi wprost, zaakceptował.

Usunięte zduplikowane prywatne funkcje `geodesicCoordinates` w `TravelMapAnimationView.swift` i `TravelMapVideoRenderer.swift` (obie teraz wołają `RouteProvider.route(...)`, `async`). Grubość linii trasy zmniejszona: live view 3pt→2pt, video renderer 6pt→3pt.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na telefonie/uruchomione na Macu. Nie przetestowane na realu przez usera jeszcze.

## Stan na 25.07.2026, ciąg dalszy — skalowanie ikony przy starcie/lądowaniu

User przysłał drugi referencyjny fragment wideo — pokazuje, że ikona samolotu jest malutka zaraz po starcie (rośnie), pełny rozmiar w środku trasy, potem znowu maleje przy zbliżaniu się do celu (zastąpiona pulsującym pierścieniem przy dokładnym lądowaniu). Dodane `RouteProvider.iconScale(progress:)` — prosta krzywa: narastanie 0.25→1.0 w pierwszych 15% odcinka, pełny rozmiar w środku, opadanie 1.0→0.15 w ostatnich 15%. Użyte w `TravelMapAnimationView` (`.scaleEffect(planeScale)`) i `TravelMapVideoRenderer` (skalowanie `iconSize` przed narysowaniem). Ten sam efekt automatycznie dotyczy wszystkich środków transportu, nie tylko samolotu (współdzielona funkcja).

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na telefonie/uruchomione na Macu.

## Stan na 25.07.2026, ciąg dalszy — licznik przebytych km w rogu

Dodane `RouteProvider.distanceKm(path:)` — suma odległości między kolejnymi punktami ścieżki (po faktycznej trasie, nie linii prostej od-do), więc licznik pokazuje realny dystans nawet dla tras drogowych/kolejowych. Odznaka "X km" w prawym górnym rogu, aktualizowana na żywo w trakcie animacji (`displayedKm = completedLegsKm + legDistanceKm * progress`) — zarówno w `TravelMapAnimationView` (SwiftUI badge), jak i w `TravelMapVideoRenderer` (dorysowana klatka po klatce, ten sam wzorzec co karta miasta).

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na telefonie/uruchomione na Macu.

## Stan na 25.07.2026, ciąg dalszy — bugfix: licznik km liczył zawyżony dystans (długość łuku, nie prawdziwą odległość)

User zgłosił: Rzeszów→Londyn Stansted pokazywało 1734km zamiast realnych ~1530km. Przyczyna: licznik liczył długość NARYSOWANEJ ścieżki (`distanceKm(path:)` sumujący punkty), a dla samolotu ta ścieżka to stylizowany ŁUK (dodany wcześniej dla wyglądu) — dłuższy niż prawdziwa odległość, bo celowo wygięty na bok.

**Fix**: rozdzielone na dwie osobne rzeczy w `RouteProvider` — `RouteResult { path, distanceKm }`. `path` może być stylizowany (łuk dla lotu), ale `distanceKm` zawsze liczony z prawdziwego źródła:
- Samochód/pociąg z realną trasą: `route.distance` z `MKRoute` (dokładniejsze niż ręczne sumowanie punktów polylinii).
- Samolot/prom/statek/fallback: `straightDistanceKm(from:to:)` — prawdziwa odległość po kuli ziemskiej między dwoma punktami, NIE długość łuku.

Usunięte stare `distanceKm(path:)` (sumowanie punktów ścieżki) jako źródło prawdy dla licznika — to była przyczyna zawyżenia.

## Backlog Travel Map v2 — uzupełnienie 25.07.2026 (feedback zewnętrzny)

User przekleił rozbudowaną recenzję/pomysły (zewnętrzny feedback po zobaczeniu ikonek pojazdów) z prośbą, żeby dopisać do TODO to, czego jeszcze nie ma na liście. Część pokrywa się z backlogiem powyżej (pinezki-miniaturki = pkt 2, motywy mapy = pkt 4, bogatsza animacja = pkt 5) — dopisane tylko NOWE elementy:

6. **Styl linii trasy zależny od środka transportu** — nie tylko inna ikona, ale inny wygląd samej linii: samolot = przerywana, samochód = ciągła, pociąg = linia z krótkimi kreskami w poprzek ("podkłady"), łódź = delikatnie falowana, statek = grubsza. Wykonalne w `RouteProvider`/rysowaniu linii (`CGContext.setLineDash`, ew. własny wzorek dla "podkładów"/fali) — umiarkowany nakład, czysto kosmetyczne.
7. **"Minimal White" jako dodatkowy styl mapy** — do listy z pkt 4 (Apple/Satellite/Dark/Vintage/Blueprint) dochodzi jeszcze jasny minimalistyczny wariant. Prawdopodobnie realizowalny przez `.standard` z jasnym `colorScheme` + ew. przyciszone kolory — do sprawdzenia ile MapKit pozwala dostroić.
8. **Automatyczne przełączanie mapy dzień/noc** — na podstawie pory doby w miejscu podróży (albo czasu lokalnego usera). Wymaga wybrania stylu mapy (jasny/ciemny wariant `.hybrid`/`.standard`) na podstawie godziny — wykonalne, ale trzeba ustalić regułę (czas lokalny miasta docelowego? czas urządzenia?).
9. **Płynniejsza, bardziej kinowa kamera** — nie tylko "skok" do regionu, ale łagodne oddalanie/obracanie/przelot nad trasą (jak Apple Maps/Google Earth flyover). Rozszerzenie obecnej `withAnimation(.easeInOut)` na region — wymagałoby sterowania `MapCamera` (heading/pitch/distance) klatka po klatce zamiast samego `region`, żeby uzyskać efekt obrotu/przelotu. Umiarkowany-duży nakład, ale duży wpływ na "wow factor".
10. **Drobne efekty otoczenia** — cień pod ikoną pojazdu (mamy już prosty cień, można pogłębić), chmurki na trasie lotu, animowane fale wokół łodzi/statku, gwiazdki przy nocnych lotach, złota poświata przy trasach o zachodzie słońca. Czysto kosmetyczne warstwy nakładane na istniejący compositing — każdy z osobna łatwy-umiarkowany, razem spory nakład bo dużo drobiazgów do dopieszczenia.
11. **"Travel Replay" — rozpoznawalny ekran zamykający film (branding)** — pomysł strategiczny, nie tylko techniczny: rozszerza pkt 3 (statystyki podróży) o konkretną, "podpisową" realizację — krótki (5–8s) montaż na końcu filmu: lista miast+ikony transportu między nimi, animowana mapa, podsumowanie ("2 countries • 4 cities • 1,243 km travelled") i logo PMemories. Cel: żeby ten ekran stał się rozpoznawalnym elementem appki (jak szablony CapCut), który ludzie kojarzą z PMemories gdy widzą go na TikToku/Instagramie. Wymaga dat pobytu per przystanek (jak pkt 3) + osobnego "outro" segmentu w pipeline eksportu wideo.

Nic z powyższego NIE zaimplementowane teraz — czysto dopisanie do listy na przyszłość, zgodnie z prośbą usera ("później dopisz do listy TODO, teraz rób dalej ikonki").

## Backlog — "Travel Intelligence" — druga wklejka feedbacku 25.07.2026 (zmiana pozycjonowania produktu)

Kluczowa myśl usera/feedbacku: PMemories **nie powinno konkurować z CapCut/InShot jako edytor wideo** — przewagą ma być rola "pamiętnika podróży z AI", czyli agregacja CAŁEGO życia podróżniczego usera, nie tylko montaż pojedynczego filmu. To zmiana pozycjonowania produktu, nie tylko lista featurów — warto to mieć na uwadze przy priorytetyzacji (Travel Map z dotychczasowego backlogu to fundament pod to, nie osobny wątek).

Nowe pozycje (część rozszerza już zapisane punkty, oznaczone gdzie):
12. **"My World" — ekran zbiorczych statystyk życiowych** — NOWA, duża funkcja: w odróżnieniu od Travel Map (animacja JEDNEJ podróży), to trwały ekran agregujący WSZYSTKIE zarejestrowane podróże (kraje, miejsca, loty, km per środek transportu, zdjęcia/wideo, "best memory", najdłuższa podróż, liczba zachodów słońca, plaże, najwyższy punkt itd.). Wymaga trwałego magazynu podróży/przystanków (dziś `TripStop` żyje tylko w ramach jednej sesji Travel Map — trzeba by to zapisywać per-podróż, np. SwiftData/Core Data) — duży nakład, ale fundament pod wszystko poniżej.
13. **Interaktywna mapa świata (kraje podświetlone po odwiedzeniu)** — klik w kraj → lista miast → wspomnienia z tego miasta. Różni się od animowanego Travel Map tym, że to WIDOK PRZEGLĄDOWY/trwały, nie jednorazowa animacja. Zależy od #12 (potrzebuje tych samych danych zbiorczych).
14. **AI Journey/Explorer Score** — gamifikowany wynik (np. "92/100") liczony z zebranych statystyk (kraje/miasta/kontynenty/loty/parki narodowe itd.). Zależy od #12, sam wynik to prosta formuła punktowa.
15. **Travel Passport — kolekcjonowanie pieczątek krajów** — mechanika kolekcjonerska (flaga/pieczątka po odwiedzeniu kraju, jak Pokémony). Zależy od #12.
16. **Year in Review / "Travel Wrapped"** — coroczny automatyczny rekap (na wzór Spotify Wrapped) z animacją, generowany z danych roku. Duży nakład (własny pipeline wideo + dane roczne), ale silny potencjał viralowy/rozpoznawalności marki — łączy się z pkt 11 (Travel Replay) jako ta sama rodzina "auto-generowanych, brandowanych podsumowań".
17. **Travel Time Machine — powiadomienia "X lat temu byłeś w..."** — cyklicznie (np. codziennie) sprawdza czy jest rocznica jakiegoś wspomnienia, wysyła powiadomienie, po kliknięciu odtwarza mini-film z tamtego dnia (zdjęcia, mapa, ew. pogoda/temperatura z tamtego dnia jeśli da się to dociągnąć/zapisać). Wymaga lokalnych powiadomień (`UNUserNotificationCenter`) + zapisanych dat wspomnień (zależy od #12).
18. **Rozszerzenie "Smart Route" (pkt 1) o więcej źródeł auto-wykrywania** — oprócz GPS z EXIF zdjęć: OCR biletów lotniczych/kart pokładowych, rezerwacji hoteli, opcjonalnie maile (za zgodą usera). Znacznie większy nakład niż bazowy #1 (Vision OCR + parsowanie niestandardowych formatów dokumentów, ew. integracja z pocztą) — traktować jako osobny, późniejszy krok rozszerzający #1, nie część MVP tej funkcji.
19. **Dane pogodowe/temperatura w karcie podsumowania podróży** — rozszerzenie pkt 11 (Travel Replay) o pogodę z dni podróży (wymaga API pogodowego z danymi historycznymi albo zapisu pogody w momencie robienia zdjęć).

Całość NIEZAIMPLEMENTOWANA — czysty zapis na przyszłość, zgodnie z prośbą usera. Priorytetyzacja i kolejność wprowadzania do ustalenia później, nie teraz.

## Stan na 25.07.2026, ciąg dalszy — ikony pojazdów zależne od kierunku jazdy (zamiast jednej obracanej ikony)

User przysłał siatkę 5×5 (5 pojazdów × 5 widoków: LEFT SIDE / RIGHT SIDE / TOP VIEW / ISO FRONT-RIGHT / ISO BACK-LEFT, wygenerowaną przez ChatGPT) i poprosił o wycięcie 25 osobnych ikon oraz dobieranie właściwego obrazka do kierunku ruchu na mapie (zamiast dotychczasowego jednego, obracanego o dowolny kąt PNG).

**Wycinanie**: siatka 1536×1024px, kolumny/wiersze namierzone przez `grid_crop.swift` (overlay) + walidacja przez `crop.swift` na próbkach z każdego rzędu, dopiero potem `batch_crop_vehicles.swift` (jednorazowy skrypt w scratchpadzie) wyciął wszystkie 25 obrazków naraz z ustalonych współrzędnych. Każdy wynik zweryfikowany wzrokowo przez `Read` przed użyciem (zgodnie z ustaloną w tej sesji zasadą "zmierz, nie zgaduj").

**Ważne odkrycie po obejrzeniu wyciętych obrazków**: kierunek dziobu/przodu pojazdu NIE zawsze odpowiadał nazwie kolumny z moodboardu — np. oba boczne widoki samolotu (LEFT SIDE i RIGHT SIDE) pokazywały dziób w tę samą stronę (to obrazki AI-generowane niezależnie, nie renderowane z jednego spójnego modelu 3D na obrotowym stole). Dlatego mapowanie kierunek→obrazek zostało ustalone na podstawie tego, co faktycznie widać na każdym z 25 wyciętych obrazków (bezpośrednia inspekcja przez `Read`), a nie na podstawie nazw plików.

**System wyboru ikony** (`VehicleIconSet.swift`, nowy plik, identyczny w obu projektach — czysty Foundation, bez zależności UIKit/AppKit):
- Namiar (bearing, 0–360°, ten sam co już liczony do rotacji) dzielony na 8 sektorów po 45°.
- **N/S** (namiar blisko 0°/180°) → widok "top" (z góry), swobodnie obrócony o dokładny namiar — jedyny widok, który jest rzutem ortogonalnym i można go bezpiecznie kręcić o dowolny kąt bez zniekształcenia perspektywy. Każdy pojazd ma zmierzony osobno `topBaseAngle` (kąt, jaki na obrazku źródłowym reprezentuje domyślnie kierunek "do góry") — bo nie każdy wygenerowany obrazek miał dziób u góry kadru (samolot/pociąg/łódź: dziób u góry = 0°; samochód: reflektory na dole kadru = 180°; statek wycieczkowy: dziób po LEWEJ, bo widok "top" wyszedł poziomy, nie pionowy = 270°).
- **E** → widok "right" wprost. **W** → widok "left" wprost (różne, nieruchome obrazki, bez obracania w kodzie).
- **SE** → widok izometryczny "front-right" wprost (dziób w dół-w-prawo na obrazku źródłowym). **NW** → widok "back-left" wprost (dziób w górę-w-lewo).
- **NE** → widok "back-left" odbity w poziomie (odbicie zamienia "góra-lewo" na "góra-prawo"). **SW** → widok "front-right" odbity w poziomie.

Podpięte w `TravelMapAnimationView.swift` (`.scaleEffect(x: mirrored ? -1 : 1, y: 1)` + `.rotationEffect` na wyniku `VehicleIconSet.resolve`) i w obu wariantach `TravelMapVideoRenderer.swift` (`ctx.rotate` + opcjonalny `ctx.scaleBy(x: -1, y: 1)` przed narysowaniem obrazka). Kąt użyty w rendererach wideo to ten sam wzór co poprzednio (`atan2(dy,dx)` przeliczony na namiar kompasowy), tylko teraz przepuszczony przez `VehicleIconSet` zamiast bezpośrednio obracać jeden PNG.

25 nowych `Vehicle-<pojazd>-<widok>.imageset` w `Assets.xcassets` (oba projekty), stare pojedyncze `Vehicle-plane/car/train/boat/cruise.imageset` USUNIĘTE (zastąpione w całości, żadnych pozostałości starego systemu).

Build (`xcodegen generate` + `xcodebuild`) → **BUILD SUCCEEDED** na obu platformach. Zainstalowane na realnym iPhone (telefon zablokowany w momencie próby uruchomienia — user musi sam odblokować i otworzyć appkę ręcznie), Mac uruchomiony automatycznie. Nie przetestowane wzrokowo na żywo w ruchu (czy dobór obrazków rzeczywiście wygląda dobrze podczas animacji) — do potwierdzenia przy następnym kontakcie z userem.

## Stan na 25.07.2026, ciąg dalszy — POPRAWKA: uproszczenie logiki kierunku + precyzyjne wycinanie (2 poprawki od usera)

User zgłosił dwie rzeczy do poprawy w powyższym systemie:

**1. Logika kierunku była zbyt skomplikowana.** User doprecyzował dokładną zasadę: jadąc w PRAWO używamy TYLKO widoku "right" (bez zmiany obrazka w trakcie ruchu), jadąc w LEWO — tylko "left", a widok "top" (z góry) obsługuje ruch w GÓRĘ i w DÓŁ (jedyny widok, który można bezpiecznie swobodnie obracać). Usunięty cały 8-sektorowy system z widokami izometrycznymi i lustrzanymi odbiciami (NE/SE/SW/NW) — zastąpiony prostym 4-sektorowym podziałem (E→right, W→left, N/S→top obrócony o namiar). `VehicleIconSet.swift` uproszczony: struct `Resolved` stracił pole `mirrored` (nieużywane w nowym schemacie), usunięte odbicia w obu wariantach `TravelMapVideoRenderer.swift`. Widoki izometryczne (`isofr`/`isobl`) — 10 nieużywanych już imagesetów — USUNIĘTE z `Assets.xcassets` obu projektów (nie trzymamy martwych assetów).

**2. Wycinanie obrazków miało za duży margines tła** ("kwadrat", nie ciasny kadr wokół samego pojazdu). Naprawione przez automatyczne wykrywanie bounding-boxa pojazdu zamiast sztywnego prostokąta z siatki:
- Pierwsza próba (`tight_crop_vehicles.swift`, próg koloru=22 względem tła z jednego rogu) zawiodła — granica "uciekała" aż do brzegu okna szukania dla WSZYSTKICH 25 komórek. Diagnoza przez bezpośrednie sondowanie pikseli (`probe.swift`) ujawniła przyczynę: tło w tym obrazku ma MIĘKKI gradient/poświatę wokół każdego pojazdu (nie twardą, jednolitą krawędź) — niski próg koloru łapie tę poświatę jako "zawartość", więc granica rozjeżdża się szeroko.
- Zmierzone empirycznie (`debug_one_cell.swift`, testy z różnymi progami 20/60/100/130): prawdziwa krawędź pojazdu ma odległość koloru rzędu 200-700 od tła, sama poświata maksymalnie ~40-50. Próg **100** daje stabilny wynik (identyczny przy 60 i 130, czyli trafia w realną krawędź, nie w poświatę) — użyty w finalnym `tight_crop_vehicles2.swift` (mediana pikseli brzegowych okna jako odporny estymator tła + próg 100 + margines 6px).
- Wynikowe obrazki znacznie mniejsze i ciaśniejsze niż oryginalne kwadraty (np. samolot z boku: 295×195 → 231×104) — zweryfikowane wzrokowo przez `Read` na próbce z każdego pojazdu i widoku przed podmianą w `Assets.xcassets`.
- **Uwaga na przyszłość — pułapka poboczna podczas debugowania**: przy pierwszym podejrzeniu "coś jest nie tak z osią Y" rozważana była (i odrzucona) teoria o brakującym flipie orientacji `CGContext` (znana pułapka z wcześniejszej pracy nad ikonami pojazdów w tej sesji) — zweryfikowana i OBALONA empirycznie: skan pionowy pokazał sensowny, realny profil pojazdu (tło-zawartość-tło pasujące do kształtu samolotu z boku) w wersji BEZ flipa, a wersja ZE sztucznie dodanym flipem dawała fizycznie nielogiczny wzór ("dziura" w środku sylwetki). Wniosek: manualne tworzenie `CGContext(data:...)` i rysowanie w nie przez `.draw()` NIE zawsze wymaga flipa — zależy od konkretnego przypadku, więc każdą taką sytuację trzeba zweryfikować empirycznie (sondą pikseli), a nie zakładać z góry na podstawie wcześniejszego, innego przypadku w tej samej sesji.

Build → **BUILD SUCCEEDED** na obu platformach po zmianach. Zainstalowane na iPhone, Mac zrestartowany z nową wersją. Nadal nieprzetestowane wzrokowo na żywym urządzeniu przez usera.

## Stan na 25.07.2026, ciąg dalszy — poprawka: samolot tylko widok z góry

User: widok samolotu z boku wygląda słabo i nie jest precyzyjnie wycięty; widok z góry (zweryfikowany wzrokowo — czysty, dziób u góry, oba skrzydła w kadrze) ma być używany WYŁĄCZNIE, dla wszystkich kierunków, nie tylko N/S. `VehicleIconSet.resolve` — dla `.plane` wcześniejsze wyjście z funkcji z samym widokiem "top" swobodnie obróconym o namiar (ten sam mechanizm co wcześniej dla N/S, tylko teraz stosowany zawsze). Pozostałe pojazdy (car/train/boat/cruise) bez zmian — nadal 3-widokowy schemat (right/left/top). Nieużywane już `Vehicle-plane-left`/`Vehicle-plane-right` USUNIĘTE z `Assets.xcassets` obu projektów. Build → **BUILD SUCCEEDED**, zainstalowane na iPhone, Mac zrestartowany.

## Backlog — plan lokalizacji (etapy językowe) — uzupełnienie 25.07.2026 (zadanie #10)

User przekleił rozbudowany plan etapowania lokalizacji (zamiast tłumaczyć na wszystko naraz) — rozwija dotychczasowe zadanie #10 "lokalizacja na 10 najpopularniejszych języków" o konkretną treść:

- **Etap 1 (start)** — 10 języków: English, Spanish, French, German, Italian, Polish, Portuguese (Brazil), Japanese, Korean, Simplified Chinese.
- **Etap 2** — kolejne 10: Dutch, Swedish, Norwegian, Danish, Finnish, Romanian, Czech, Slovak, Turkish, Greek.
- **Etap 3** (jeśli aplikacja zdobędzie popularność) — Ukrainian, Hindi, Indonesian, Thai, Vietnamese, Arabic, Hebrew.
- **AI Voice (lektor)** — węższa lista priorytetowa, bo dobre głosy lektorskie kosztują więcej: English, Spanish, French, German, Italian, Japanese, Korean, Polish.
- **Uzasadnienie etapowania**: lokalizacja to nie tylko UI — obejmuje AI, szablony, komunikaty, onboarding, powiadomienia, napisy generowane przez AI, opis w App Store, stronę WWW, regulaminy — tysiące linijek tekstu, lepiej 10 dopracowanych języków niż 60 słabych.
- **Auto-detekcja języka telefonu** przy pierwszym uruchomieniu — zero ręcznego wyboru przy onboardingu.
- **NOWY pomysł funkcji — "Share with Family"**: przy udostępnianiu gotowego filmu AI pyta czy przetłumaczyć napisy, user wybiera kilka języków naraz (np. Polish/English/Spanish) i ten sam film dostaje napisy w kilku językach jednocześnie — przydatne dla rodzin/znajomych rozsianych po różnych krajach. To osobna, nowa pozycja backlogu (nie tylko lokalizacja UI, tylko multi-language napisy w JEDNYM eksportowanym filmie).

Nic z powyższego niezaimplementowane — czysty zapis planu na przyszłość, zgodnie z wcześniejszą decyzją usera żeby lokalizacją zająć się jako osobnym, późniejszym krokiem, nie w trakcie bieżącej pracy.

## Wizja produktu — architektura 5 modułów — trzecia wklejka feedbacku 25.07.2026

Najbardziej strukturalna z czterech wklejek tej sesji — nie lista featurów, tylko propozycja PODZIAŁU CAŁEJ APLIKACJI na moduły. Kluczowe zdanie usera/feedbacku: PMemories nie powinno być "AI Video Editor", tylko **"The home of your memories"** — edytor to JEDEN z modułów, nie cały produkt. User poprosił wprost o zapisanie tego na TODO, z dopiskiem że w poniedziałek (27.07.2026) będzie "pełny reset roboty" (świeże podejście/planowanie od nowa wokół tej wizji).

**Proponowana struktura 5 modułów**:
1. **📖 Memories** — centrum aplikacji, otwierane najczęściej: Timeline, Kraje, Miasta, Mapa, Statystyki, Filmy, Zdjęcia. To odpowiednik dzisiejszego "Home"/"My World" z backlogu Travel Intelligence (punkt 12), tylko podniesiony do rangi głównego modułu.
2. **🎬 Studio** — tu PMemories ma realnie konkurować z CapCut/InShot: multi-track, trim, split, speed ramp, keyframes, maski, green screen, motion blur, HDR, LUT, stabilizacja, i cała warstwa AI-edycji (remove objects, sky replace, voice, auto captions, music sync, color grade, face/subject tracking). Duży, osobny nakład — pełnoprawny profesjonalny edytor, znacznie więcej niż dzisiejszy prosty EditView.
3. **🌍 Travel** — to, co już budujemy (Travel Map + cały backlog Travel Intelligence z punktów 1-19 wyżej) — mapa, statystyki, animacje, środki transportu, odległości, timeline, pogoda, golden hour, visited countries, passport, wrapped. Ten moduł już ma realny fundament w kodzie.
4. **🤖 AI** — nie tylko narzędzie do tworzenia filmu, ale też "one-click" polecenia stylu ("Create a cinematic movie", "Make it emotional", "Create TikTok version", "Make wedding style", "Add narration") — warstwa nad Studio, ustawia parametry montażu na podstawie jednego opisu.
5. **👤 Profile** — nie "konto", tylko widok całego "życia" usera w liczbach (dołączenia, kraje, miasta, loty, road tripy, stworzone filmy, zdjęcia, wideo, storage, ulubiony kraj) — pokrywa się częściowo z modułem Memories/My World, ale jako osobna, bardziej "kontowa"/motywacyjna zakładka.

**Dwa dodatkowe "killer feature" pomysły wykraczające poza sam podział na moduły**:
- **🧠 Memory AI** — wyszukiwanie konwersacyjne po własnych wspomnieniach: "Show me every sunset I've seen", "How many times have I been to Spain?", "Show every beach holiday", "Show trips with Anna", "Find every photo with mountains". Wymaga: indeksowania zdjęć/wideo pod kątem treści (Vision/scene detection — częściowo pokrywa się z wcześniej ocenianym "Highlight Detector" z pierwotnej wizji produktu), geolokacji, i prostego NLQ→filtr (niekoniecznie pełny LLM on-device, może wystarczyć zestaw reguł na rozpoznanych tagach). Duży, osobny nakład badawczy.
- **🎬 Story Builder** — zamiast ręcznego wybierania zdjęć, user pisze polecenie ("Create a movie from my honeymoon"), a AI samo znajduje pasujące zdjęcia/filmy/lokalizacje/muzykę/pogodę/loty i składa gotowy film. To najbardziej ambitna, złożona funkcja z całej wizji — zależy od Memory AI (wyszukiwanie/grupowanie wspomnień) + AI modułu (dobór stylu) + Studio (silnik montażu) połączonych w jeden automatyczny pipeline.

**Branding**: rekomendacja, żeby nie mówić o PMemories jako o "edytorze", tylko o marce/miejscu na wspomnienia (analogia: Apple nie sprzedaje "telefonu", tylko iPhone'a). Proponowane zdanie pozycjonujące: *"PMemories to inteligentna platforma do przechowywania, odkrywania i opowiadania historii z Twojego życia — z profesjonalnym edytorem wideo i AI, które zamienia zdjęcia oraz filmy w wyjątkowe wspomnienia."*

Nic z powyższego niezaimplementowane — to najwyższego poziomu dokument wizji/architektury (parasol nad wszystkimi punktami z poprzednich trzech wklejek backlogu), do rozpisania na konkretne kroki w poniedziałek.

## Stan na 25.07.2026, ciąg dalszy — POPRAWKA 2: przezroczyste tło ikon + pociąg/samochód też tylko widok z góry

User zgłosił, że wycięte obrazki nadal mają widoczne czarne/ciemne tło wokół pojazdu — sam ciasny bounding-box (poprzednia poprawka) to nie to samo co usunięcie tła. Naprawione przez **chroma-key** zamiast samego przycięcia: `transparent_crop_vehicles.swift` — dla każdego piksela w wykrytym bounding-boxie liczy odległość koloru od lokalnego tła (ta sama mediana z ramki brzegowej co wcześniej) i ustawia kanał alfa: <45 → w pełni przezroczyste, >110 → w pełni kryjące, pomiędzy → miękkie przejście liniowe (żeby krawędź pojazdu nie była postrzępiona, tylko gładka jak przy antyaliasingu). Wynik zapisany jako PNG z prawdziwym kanałem alfa (premultiplied RGBA), zweryfikowany wzrokowo na kilku przykładach (samolot z góry, samochód z boku, statek z boku, pociąg z góry, łódź z boku) — czyste sylwetki na przezroczystym tle, gładkie krawędzie, brak czarnej obwódki.

Przy okazji user doprecyzował: **pociąg i samochód też mają używać WYŁĄCZNIE widoku z góry** (tak jak wcześniej ustalone dla samolotu) — widoki boczne tych dwóch pojazdów też wyszły słabo. `VehicleIconSet.resolve` — warunek "tylko top" rozszerzony z `.plane` na `.plane, .train, .car`. Tylko `.boat` i `.cruise` zachowują teraz pełny 3-widokowy schemat (right/left/top). Nieużywane już `Vehicle-train-left/right` i `Vehicle-car-left/right` USUNIĘTE — zostało 9 imagesetów zamiast 15 (plane-top, train-top, car-top, boat-left/right/top, cruise-left/right/top).

Build → **BUILD SUCCEEDED** na obu platformach. Zainstalowane na iPhone (urządzenie na chwilę się rozłączyło przy pierwszej próbie instalacji — `devicectl` zgłosił błąd 4000, druga próba zaraz potem zadziałała), Mac zrestartowany.

## Stan na 25.07.2026, ciąg dalszy — Home → Dashboard (redesign nawigacji i ekranu startowego)

User przekleił szczegółową recenzję UI (branding 9.5/10, kolory 10/10, ale UI 7.5/10 — architektura interfejsu, nie wygląd, wymaga teraz najwięcej pracy) z gotowym mockupem tekstowym nowego ekranu startowego, uznanym za kolejne zadanie do zrobienia (nie tylko backlog na później).

**Zaimplementowane w `HomeView.swift` (oba projekty)**:
- **Nawigacja**: zakładki zmienione z `Projects/Templates/Music/Profile` na `Home/Studio/Travel/Templates/Library`. Travel Map przeniesiony z zakładki "Templates" na osobną zakładkę "Travel". Profil przeniesiony z zakładki na przycisk-awatar w prawym górnym rogu Dashboardu (otwiera sheet, na razie placeholder "wkrótce").
- **Dashboard** (nowa zawartość zakładki Home): powitanie zależne od pory dnia ("Good morning/afternoon/evening, Piotr" — imię na sztywno, to osobista appka jednego użytkownika), duże CTA **"✨ Create Memory"** (zastępuje "+ New Project" — user: "nie sprzedajesz projektu, sprzedajesz wspomnienia"), sekcje "Travel Intelligence" i "Recent Memories".
- **Świadomie NIE zaimplementowane z mockupu usera** (uczciwie, bez podszywania danych): karta "Continue Editing X%" z prawdziwym postępem, prawdziwe liczby ("47 Countries, 326 Places"), lista ostatnich wspomnień z flagami krajów, animowany globus na starcie, rozbudowany picker typu wspomnienia (Photos/Videos/Album/Vacation/Wedding/Birthday z AI). Żadna z tych rzeczy nie ma jeszcze prawdziwych danych — appka NIE zapisuje trwale projektów ani podróży między uruchomieniami (backlog punkt 12 "My World" — wymaga SwiftData/Core Data). Zamiast fałszywych liczb, sekcje "Travel Intelligence"/"Recent Memories" pokazują uczciwy stan pusty z linkiem do zakładki Travel. Pełna "żywa" wersja czeka na warstwę persystencji — osobne, większe zadanie.
- CTA "Create Memory" używa dokładnie tego samego, już działającego mechanizmu co poprzednie "New Project" (ten sam `PhotosPicker` → `MediaItemLoader` → `EditView`) — zmieniła się tylko nazwa/styl przycisku.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

### Do zrobienia dalej (z tej samej recenzji, nie zaimplementowane)
- Prawdziwa karta "Continue Editing" z % postępu — wymaga zapisywania stanu projektu między uruchomieniami.
- Prawdziwe dane w "Travel Intelligence"/"Recent Memories" — wymaga warstwy persystencji (backlog punkt 12).
- Rozbudowany picker "Create Memory" z wyborem typu (Vacation/Wedding/Birthday) i AI dobierającym zdjęcia/muzykę automatycznie — łączy się ze "Story Builder" z architektury 5 modułów wyżej.
- Animowany globus jako element Dashboardu — kosmetyczne, ale duży "wow factor" według recenzji.

## Stan na 25.07.2026, ciąg dalszy — NOWA METODOLOGIA: `~/Desktop/PMemories Docs/` + rozwój etapami

User zaakceptował (i poprosił o zapisanie jako trwałą zasadę) zewnętrzną rekomendację: nie budować wszystkiego naraz. Trzy etapy: **Fundament** (architektura/nawigacja/dane) → **Studio** (edytor) → **AI** (inteligentne funkcje). Priorytety P0–P3. Dokumentacja przed kodem.

Założona wspólna struktura `~/Desktop/PMemories Docs/` (NADRZĘDNA wobec obu drzew kodu iPhone/Mac, bo dotyczy produktu, nie platformy): `README.md`, `Vision.md`, `Roadmap.md`, `TODO.md`, `UI.md`, `Database.md`, `Brand.md`, `Travel.md`, `Studio.md`, `AI.md` — skonsolidowane z całego dotychczasowego backlogu rozproszonego po tym pliku HISTORIA.md. **HISTORIA.md pozostaje źródłem prawdy dla szczegółowego blow-by-blow (bugfixy, pułapki techniczne, odrzucone pomysły)** — Docs/ to warstwa wyżej: co robimy, w jakiej kolejności, dlaczego.

Największy zidentyfikowany blocker po tym ćwiczeniu: appka NIE ma żadnej trwałej persystencji (projekty i podróże żyją tylko w pamięci sesji) — od tego zależy prawie cały moduł Travel Intelligence i "prawdziwy" Dashboard. Opisane szczegółowo w `Database.md`, zaproponowany szkic modeli SwiftData (`Project`, `Trip`, `TripStopRecord`).

Zapisane też jako trwała pamięć Claude (nie tylko w tym pliku) — reguła współpracy na przyszłe sesje, patrz `feedback_pmemories_staged_development.md` w pamięci Claude.

Nic z kodu nie zmienione w tym kroku — to czysto organizacyjne przygotowanie pod pracę od jutra/poniedziałku.

## Stan na 25.07.2026, ciąg dalszy — przycisk "Odtwórz ponownie" + fallback trasy kolejowej + ocena kosztu API tras morskich

- **Replay animacji**: nowy `@State isAnimationFinished`, ustawiany na `true` po zakończeniu pętli po wszystkich odcinkach w `runAnimation()`. Przycisk "▶ Odtwórz ponownie" (`Palette.blue`) pojawia się nad "Zapisz jako wideo" dopiero po zakończeniu przejazdu, wywołuje `replayAnimation()` — resetuje cały stan (`revealedPaths`, `visitedStops`, `completedLegsKm` itd.) i puszcza `runAnimation()` od nowa.
- **Pociąg — fallback do trasy drogowej zamiast linii prostej**, gdy Apple nie ma danych transit (częste poza dużymi miastami) — pociąg jeździ z grubsza po tych samych korytarzach co drogi, więc to bardziej realistyczne niż goła geodezja, która mogłaby przeciąć wodę. Samochód i tak już używa prawdziwej trasy drogowej (nie przecina wody poza rzadkim skrajnym przypadkiem braku połączenia drogowego).
- **Prom/statek — km nadal liczone po linii prostej**, sprawdzone ceny realnych API tras morskich (Searoutes €400/mies., SeaRoutesNav €4000/rok, NavAPI €6900/rok, Seametrix od €1500/rok) — user potwierdził, że przy appce bez przychodu nie ma to sensu. Zostaje jako świadome ograniczenie, zapisane w `Docs/Travel.md`. Istnieje darmowa alternatywa (biblioteka open-source `searoute` na PyPI), ale wymaga postawienia własnego serwisu/portu na Swift — do rozważenia dopiero przy realnych userach.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone (drugi try po przejściowym błędzie 4000 z `devicectl`), Mac zrestartowany.

## Stan na 26.07.2026 — PIERWSZY KROK FUNDAMENTU: trwały zapis podróży (SwiftData)

User: zaczynamy realizować `Docs/Roadmap.md` po kolei, żeby nie robić wszystkiego naraz. Pierwsza pozycja z `Docs/TODO.md` (Etap 1 "Fundament") — appka nie miała ŻADNEJ trwałej persystencji, co blokowało prawie cały moduł Travel Intelligence i "prawdziwy" Dashboard.

**Nowy `TripPersistence.swift`** (identyczny w obu projektach, czysty Foundation+SwiftData+CoreLocation, bez UIKit/AppKit) — dwa modele `@Model`:
- `SavedTrip` — `id`, `title`, `createdAt`, relacja `stops: [SavedStop]` (cascade delete).
- `SavedStop` — miasto/kraj/kod kraju/współrzędne/środek transportu/kolejność (`order`, bo SwiftData nie gwarantuje kolejności relacji) + odwrotna relacja do `trip`.
- `SavedTrip.asTripStops` — odtwarza posortowaną listę ulotnych `TripStop` do ponownego puszczenia animacji.
- `SavedTrip.countryCodes` — `Set<String>` krajów odwiedzonych w tej podróży, do statystyk.

**Wpięte w `PMemoriesAppApp.swift`**: `.modelContainer(for: [SavedTrip.self, SavedStop.self])` na `WindowGroup`.

**`TravelMapView.swift`**: po udanym geokodowaniu (`buildRoute()`) trasa jest od razu zapisywana (`persistTrip`) — user nic dodatkowo nie klika, zapis jest automatyczny przy każdym "Pokaż trasę". Nowa sekcja "Twoje podróże" na górze listy (widoczna tylko gdy `savedTrips` niepuste) — każda pozycja to przycisk odtwarzający zapisaną podróż od nowa (`resolvedStops = trip.asTripStops`), z możliwością usunięcia przez swipe (`onDelete` → `modelContext.delete`).

**`HomeView.swift` (Dashboard)**: sekcje "Travel Intelligence" i "Recent Memories" teraz pokazują PRAWDZIWE dane, gdy `savedTrips` nie jest puste:
- Travel Intelligence: `"\(liczba unikalnych krajów) Countries • \(liczba podróży) Trips"` zamiast pustego stanu.
- Recent Memories: poziomo przewijana lista ostatnich podróży, flagi krajów (`CityGeocoder.flagEmoji`) + tytuł trasy.
- Uczciwy stan pusty ZOSTAJE jako fallback, dopóki user nie zrobi pierwszej podróży — żadnych fikcyjnych liczb.

To odblokowuje (częściowo) punkty z `Docs/TODO.md`: "Zapisywanie podróży z Travel Map jako Trip", "Dashboard Travel Intelligence z prawdziwymi liczbami", "Dashboard Recent Memories z prawdziwymi danymi". NIE odblokowuje jeszcze: persystencji `Project`/`EditView` (osobny, większy kawałek — media/eksport, nie tylko struktura tras), ani pełnego "My World" (kraje/miasta/km/dni — to wymaga jeszcze dat pobytu per przystanek, dziś zapisujemy tylko `createdAt` całej podróży, nie per-miasto).

Build → **BUILD SUCCEEDED** na obu platformach. Mac zrestartowany z nową wersją od razu. **iPhone: instalacja nieudana w tej chwili** — `devicectl` zgłasza "developer disk image could not be mounted on this device" (urządzenie w stanie "connected (no DDI)") — to wymaga fizycznego odblokowania telefonu przez usera, nie da się tego naprawić z tej strony. Do zainstalowania przy najbliższej okazji. **(Zainstalowane chwilę później, po odblokowaniu telefonu przez usera — połączenie po WiFi, `Pit.coredevice.local`.)**

## Stan na 26.07.2026, ciąg dalszy — DRUGI KROK FUNDAMENTU: trwały zapis projektów montażu (SwiftData)

Kontynuacja pracy nad `Docs/TODO.md` Etap 1 "Fundament" — po `SavedTrip` (podróże) czas na `SavedProject` (projekty montażu z `EditView`), które wcześniej znikały całkowicie przy zamknięciu appki.

**Kluczowa decyzja architektoniczna**: NIE przechowujemy samych zdjęć/wideo w bazie (ciężkie, i tak żyją w bibliotece Photos) — tylko `assetLocalIdentifier` (`PHAsset.localIdentifier`, ten sam co już istniejące `MediaItem.pickerItemId`, pobierane z `PhotosPickerItem.itemIdentifier`). Miniaturki i pliki wideo są odtwarzane NA ŻĄDANIE z Photos przy otwarciu projektu, nie zapisywane.

**Nowy `ProjectPersistence.swift`** — `SavedProject` (id/title/createdAt/updatedAt/muzyka/relacja do `items`) + `SavedMediaItem` (assetLocalIdentifier/isLivePhoto/isVideo/useMotion/duration/order). **Różni się między platformami** (pierwszy taki przypadek dla plików persystencji w tej sesji) — bo muzyka jest wybierana inaczej:
- iPhone: `musicPersistentID: UInt64?` — `MPMediaItem.persistentID`, stabilny identyfikator do ponownego odnalezienia utworu przez `MPMediaQuery`.
- Mac: `musicFilePath: String?` — Mac nie ma biblioteki muzycznej z persistentID (muzyka wybierana przez `NSOpenPanel`, zwykły plik na dysku), więc zapisujemy bezpośrednio ścieżkę; przy ponownym otwarciu sprawdzamy `FileManager.fileExists` (uczciwie — jeśli user przeniósł/usunął plik, muzyka po prostu nie wraca, bez udawania że wciąż tam jest).

**Nowy `MediaAssetLoader.swift`** (identyczny wzorzec co istniejący `LivePhotoVideoExtractor`, dopełniony o zwykłe wideo i miniaturki) — `videoURL(forAssetLocalIdentifier:)` (analogicznie do `pairedVideoURL`, tylko `PHAssetResource.type == .video`), `thumbnail(forAssetLocalIdentifier:)` (`PHImageManager.requestImage`), i `loadMediaItems(from:)` spinające to wszystko w pełną listę `MediaItem` z zapisanych rekordów. **Napotkany i naprawiony bug podczas budowy**: lokalna zmienna `videoURL` przesłaniała nazwę funkcji `videoURL(forAssetLocalIdentifier:)` w tym samym zakresie, co dawało błąd kompilacji "cannot call value of non-function type URL?" — naprawione przez zmianę nazwy zmiennej na `resolvedVideoURL`.

**`EditView.swift`** (oba warianty) — przyjmuje teraz `let project: SavedProject` (zawsze już istniejący, tworzony przez wywołującego, nie przez samo `EditView`). Nowe `syncProject()` zapisuje bieżący stan (kolejność, ruch, czas trwania, muzyka) do `project` w kluczowych momentach: po zmianie liczby elementów, po zmianie utworu/długości utworu, przy powrocie (back button), po udanym eksporcie — świadomie NIE przy każdej mikro-zmianie (np. toggle ruchu Live Photo pojedynczego elementu), żeby nie zapisywać na każdą klatkę; te trafiają do bazy przy najbliższej z powyższych okazji. Nowe `loadInitialSong()`/`loadInitialMusic()` odtwarza wcześniej wybraną muzykę przy ponownym otwarciu zapisanego projektu.

**`HomeView.swift`** (oba warianty) — "Create Memory" teraz od razu tworzy i zapisuje `SavedProject` (`loadSelection`), nie tylko trzyma stan w pamięci. Nowa `openProject(_:)` rehydratuje zapisany projekt (async, przez `MediaAssetLoader`) i otwiera go w `EditView` — używana przez nową zakładkę Library.

**Nowy `LibraryView.swift`** (oba projekty, identyczny) — zastępuje placeholder "wkrótce" prawdziwą listą `@Query` zapisanych projektów, tap otwiera projekt (`onOpenProject` callback do `HomeView`, które trzyma jedyny wspólny `NavigationStack`), swipe-to-delete usuwa.

To odblokowuje kolejne punkty z `Docs/TODO.md`: model danych dla `Project`, zapisywanie/wczytywanie stanu projektu w `EditView`, prawdziwa lista w zakładce Library. **Nadal nieodblokowane**: real drag-and-drop reorder w timeline (dziś tylko tap-to-select), pełne Studio z `Studio.md`.

Build → **BUILD SUCCEEDED** na obu platformach (jeden prawdziwy błąd kompilacji po drodze — przesłonięta nazwa funkcji, opisany wyżej, naprawiony przed instalacją). Zainstalowane na iPhone (WiFi), Mac zrestartowany.

## Stan na 26.07.2026, ciąg dalszy — dokończenie fundamentu: karta "Continue Editing" + daty pobytu per przystanek

User wybrał (przez pytanie z opcjami) dokończenie Etapu 1 "Fundament" zamiast od razu przechodzić do Studio (Etap 2).

**1. Prawdziwa karta "Continue Editing" na Dashboardzie.** Pokazuje ostatnio edytowany `SavedProject` (jeśli istnieje) — tytuł, liczbę klipów, kiedy ostatnio edytowany (`Date.formatted(.relative(presentation: .named))`), tap otwiera go od razu w `EditView` (przez istniejące już `openProject(_:)`). **Świadoma decyzja**: NIE pokazujemy fikcyjnego "% postępu" z oryginalnego mockupu usera — nie ma sensownej definicji "ukończenia" projektu wideo (to nie plik do pobrania z mierzalnym postępem), więc zamiast zmyślać liczbę pokazujemy uczciwe, realne fakty. Karta pojawia się NAD "Create Memory" CTA, tylko gdy jest jakiś zapisany projekt.

**2. Daty pobytu per przystanek w Travel Map.** `TripStop.arrivalDate: Date?` (nowe pole, opcjonalne) i `SavedStop.arrivalDate: Date?` (SwiftData). **Świadomie NIE auto-wypełniane** czasem utworzenia rekordu w appce — Travel Map odtwarza PRZESZŁĄ podróż (user wpisuje nazwy miast z pamięci), więc data powinna być tym, co user faktycznie wpisze jako "kiedy tam byłem", nie momentem klikania w appce. UI w `StopRow` (`TravelMapView.swift`): jeden przycisk "Dodaj datę pobytu" (opcjonalny, zero tarcia jeśli user go nie użyje — zgodnie z wcześniejszą zasadą "wybór ma zajmować 2 sekundy"), po dodaniu — kompaktowy `DatePicker` + przycisk usunięcia. Data pokazywana na karcie miasta zarówno podczas ŻYWEJ animacji (`CityCard` w `TravelMapAnimationView.swift`), jak i w KARCIE EKSPORTOWANEGO WIDEO (`drawCard`/`subtitle(for:)` w obu wariantach `TravelMapVideoRenderer.swift`, UIKit i AppKit) — data dopisana do istniejącej linii kraju (`"Country  •  15 lip 2026"`), żeby nie zmieniać wysokości karty.

To odblokowuje z `Docs/Database.md`: "Prawdziwy Continue Editing z %" (zrealizowane jako uczciwsza wersja bez %) i "Daty pobytu per przystanek" — **kompletne w 100%** (dane + input UI + live-podgląd + eksport wideo, wszystkie miejsca gdzie ta data mogła się pojawić).

Build → **BUILD SUCCEEDED** na obu platformach (dwie osobne rundy — druga po dopisaniu daty w eksporcie wideo), zainstalowane na iPhone, Mac zrestartowany. Etap 1 "Fundament" faktycznie kompletny teraz, bez zastrzeżeń.

## Stan na 26.07.2026, ciąg dalszy — Etap 2 "Studio": Trim (pierwsza z 5 funkcji edytora)

User wybrał (przez pytanie z opcjami), od czego zacząć Studio: **Trim** jako pierwsza, najbardziej fundamentalna z pięciu zapowiedzianych funkcji (Trim/Split/Crop/Rotate/Speed) — bo Split koncepcyjnie jest "dwa przycięte kawałki", więc Trim to naturalny fundament pod niego.

**Model danych** (`MediaItem`, oba projekty): nowe pola `trimStart: Double` (punkt startowy w źródłowym klipie, sekundy), `sourceDuration: Double?` (długość całego źródła — do zbudowania suwaka), `isManuallyTrimmed: Bool` (czy user ręcznie ustawił czas — chroni przed nadpisaniem przez automatyczne rozłożenie czasu po zmianie utworu), i `isTrimmable` (computed: `(isVideo || (isLivePhoto && useMotion)) && sourceDuration != nil`). Te same pola dodane do `SavedMediaItem` (SwiftData) — trim przeżywa zamknięcie appki jak reszta stanu projektu.

**`sourceDuration` wypełniane w dwóch miejscach**: `MediaItemLoader.load(from:)` (nowy wybór z Photos) i `MediaAssetLoader.loadMediaItems(from:)` (rehydracja zapisanego projektu) — w obu przez `AVURLAsset(url:).load(.duration)` na już wyciągniętym pliku wideo/paired-video.

**`VideoComposer.buildComposition`**: `CMTimeRange` zaczyna się teraz od `trimStart` (przycięty do granic źródła), zamiast zawsze od `.zero` — to jest realny efekt Trim w wyeksportowanym filmie, nie tylko UI-owa dekoracja.

**Konflikt z automatycznym rozkładem czasu — rozwiązany**: `redistributeDurations()` (odpalane po zmianie utworu/liczby elementów) wcześniej NADPISYWAŁO `duration` KAŻDEGO elementu równym podziałem długości utworu — co zniszczyłoby ręcznie ustawiony Trim. Naprawione: funkcja teraz dzieli TYLKO elementy z `isManuallyTrimmed == false`, a ręcznie przyciętym zostawia ich czas, licząc dla reszty `(długość utworu − suma ręcznych) / liczba automatycznych`.

**Nowy `TrimView.swift`** (identyczny w obu projektach, czysty SwiftUI) — własnoręcznie zrobiony suwak z dwoma uchwytami (`TrimRangeSlider`, `DragGesture` na każdym uchwycie osobno — SwiftUI nie ma gotowego dual-handle range slidera): lewy uchwyt przesuwa `trimStart` zachowując punkt końcowy, prawy uchwyt zmienia tylko długość zachowując start. Minimalna długość zaznaczenia 0.3s (zabezpieczenie przed zerowym/ujemnym klipem). Przycisk "Przywróć automatyczny czas" czyści `isManuallyTrimmed`.

**Podpięcie w `EditView.swift`**: przycisk paska narzędzi zmieniony z "Adjust" (placeholder "wkrótce") na "Trim" (✂️ `scissors`) — otwiera sheet z `TrimView` dla aktualnie zaznaczonego elementu w timeline, TYLKO jeśli `isTrimmable`; dla zwykłego zdjęcia pokazuje komunikat wyjaśniający czemu Trim jest niedostępny (zamiast po prostu nic nie robić albo dawać mylący pusty ekran).

Build → **BUILD SUCCEEDED** na obu platformach za pierwszym razem, zainstalowane na iPhone (WiFi, jeden przejściowy błąd połączenia po drodze — druga próba zadziałała), Mac zrestartowany.

### Do zrobienia dalej (Studio, pozostałe 3 z 5)
- Speed — przyspieszanie/zwalnianie (`AVMutableComposition` + `scaleTimeRange`, prostsze niż Trim, nie wymaga nowego UI do zaznaczania zakresu).
- Crop / Rotate — kadrowanie i obrót, niższy priorytet wg wcześniejszej dyskusji.
- Multi-track + drag & drop reorder w timeline.

## Stan na 26.07.2026, ciąg dalszy — Etap 2 "Studio": Split (druga z 5 funkcji edytora)

Naturalne rozszerzenie Trim (jak przewidziane w poprzednim wpisie) — zamiast osobnego miejsca w pasku narzędzi (dziś już 5 zajętych: Media/Music/Style/Text/Trim), Split dołożony jako druga akcja WEWNĄTRZ tego samego arkusza `TrimView`, bo obie operują na tym samym zakresie przycięcia wybranego klipu.

**`TrimView.swift`** (oba projekty) — nowy opcjonalny `onSplit: ((Double) -> Void)?` w initze, `@State private var splitPoint: Double` inicjalizowany na środek aktualnego zakresu trim. Gdy `onSplit` podane: pod istniejącym suwakiem trim pojawia się zwykły `Slider` (zakres = bieżący `trimStart...trimStart+duration`) do wyboru punktu podziału + przycisk "✂️ Podziel klip tutaj" wywołujący `onSplit(splitPoint)` i zamykający arkusz. Wysokość arkusza (`presentationDetents`/`frame` w wariancie Mac) zwiększona z 280 do 380, żeby zmieścić nową sekcję.

**`EditView.swift`** (oba projekty) — nowa `splitSelectedItem(at:)`: bierze aktualnie zaznaczony element, tworzy DWIE kopie tego samego źródła (ten sam `pickerItemId`/`thumbnail`/`sourceDuration`) z różnymi `trimStart`/`duration` (pierwsza: od oryginalnego startu do punktu podziału; druga: od punktu podziału do oryginalnego końca), obie oznaczone `isManuallyTrimmed = true`, i zamienia jeden element w `items` na te dwa (`replaceSubrange`). Zabezpieczenie: podział ignorowany, jeśli punkt jest bliżej niż 0.1s od któregoś brzegu (unikanie zerowych/ujemnych kawałków).

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

### Do zrobienia dalej (Studio, pozostałe 2 z 5)
- Speed — przyspieszanie/zwalnianie klipu.
- Crop / Rotate — kadrowanie i obrót.
- Multi-track + drag & drop reorder w timeline.

## Stan na 26.07.2026, ciąg dalszy — Etap 2 "Studio": Speed (trzecia z 5 funkcji edytora)

**Kluczowa decyzja modelowania**: `MediaItem.duration` ZOSTAJE bez zmian znaczeniowych — to zawsze czas wyświetlania klipu w finalnym filmiku (timeline/output), niezależnie od prędkości. Nowe `speed: Double = 1.0` to osobny mnożnik, który `VideoComposer` przelicza na "ile sekund źródła trzeba zużyć" (`duration * speed`), nie na zmianę samego `duration`. Dzięki temu Speed jest w 100% niezależny od Trim/Split/`redistributeDurations()`/`isManuallyTrimmed` — zero konfliktów, żadna z tamtych funkcji nie musiała się zmienić.

**`VideoComposer.buildComposition`** — przepisany fragment insertowania klipu: zamiast wprost insertować `item.duration` sekund źródła, insertuje `min(availableDuration, duration * speed)` sekund w naturalnym tempie, a potem (jeśli `speed != 1.0`) `videoTrack.scaleTimeRange(_:toDuration:)` ściska/rozciąga ten świeżo wstawiony fragment do dokładnie `duration` sekund na timeline. Edge case: jeśli źródło skończy się wcześniej niż potrzeba (`sourceRangeDuration < desiredSourceDuration`), faktyczny output przeliczany proporcjonalnie (`sourceRangeDuration.seconds / speed`), żeby `cursor` (pozycja następnego klipu) się nie rozjechał.

**UI**: `speedPicker` w `TrimView.swift` — presety 0.5x/1x/1.5x/2x/3x jako rząd przycisków (nie dowolny suwak — user zwykle chce jednego ze znanych efektów typu slow-mo albo 2x, nie wartości pośredniej). Wysokość arkusza zwiększona (280→360 bez Split, 380→460 ze Split).

Build → **BUILD SUCCEEDED** na obu platformach (dwa przejściowe błędy instalacji WiFi po drodze — connection interrupted / installcoordination_proxy, obie naprawione drugą próbą), zainstalowane na iPhone, Mac zrestartowany.

### Do zrobienia dalej (Studio, ostatnia z 5 głównych)
- Crop / Rotate — kadrowanie i obrót (niższy priorytet, ostatnia z pierwotnej piątki).
- Multi-track + drag & drop reorder w timeline (kolejny większy krok po całej piątce).

## Stan na 26.07.2026, ciąg dalszy — Etap 2 "Studio": Crop/Rotate (ostatnia z 5 funkcji edytora) — CAŁA PIĄTKA ZAMKNIĘTA

**Największa zmiana architektoniczna z całej piątki** — Trim/Split/Speed operowały tylko na osi CZASU (`CMTimeRange`/`scaleTimeRange`), ale Crop/Rotate wymagają transformacji PRZESTRZENNEJ (obrót/skala/kadrowanie klatki), której `AVMutableComposition` sam z siebie nie obsługuje — do tego służy osobny obiekt `AVMutableVideoComposition` z instrukcjami per-segment, którego appka wcześniej w ogóle nie budowała (eksport szedł bezpośrednio z samej kompozycji, bez żadnych transformów).

**`MediaItem`/`SavedMediaItem`** — nowe pola `rotationDegrees: Int` (0/90/180/270) i `cropFill: Bool` (`false` = fit/całość widoczna z czarnymi pasami, `true` = fill/wypełnia kadr, brzegi mogą być obcięte).

**`VideoComposer` przepisany**: `buildComposition` zwraca teraz `ComposedProject { composition, videoComposition }` zamiast samej `AVMutableComposition` — druga część to `AVMutableVideoComposition` z jedną `AVMutableVideoCompositionInstruction` per klip (ten sam zakres czasu co przy insercie), każda z `AVMutableVideoCompositionLayerInstruction.setTransform(_:at:)` liczonym przez nową `layerTransform(...)`:
1. `preferredTransform` źródła (koryguje naturalną orientację nagrania z telefonu).
2. Dodatkowy obrót usera (`extraRotationTransform` — rotacja + kompensująca translacja w tej samej konwencji co standardowe `preferredTransform` wideo, żeby wynik został dodatnio pozycjonowany).
3. Skala do stałego canvasu **1080×1920** (ten sam wymiar co synteyczne wideo ze zdjęć) — `min(...)` dla fit, `max(...)` dla fill.
4. Wyśrodkowanie.

Nowy stały `VideoComposer.canvasSize` — jeden wspólny wymiar docelowy dla WSZYSTKICH klipów (potrzebny, żeby transformy w ogóle miały sens — bez tego różne klipy o różnych natywnych rozdzielczościach renderowałyby się niespójnie).

**`VideoExporter.exportAndSaveToPhotos`** — przyjmuje teraz `ComposedProject`, ustawia `exportSession.videoComposition` (bez tego cała reszta byłaby bez efektu — sama `AVMutableComposition` nie niesie żadnych transformów, tylko czas/kolejność).

**UI**: `rotateAndCropControls` w `TrimView.swift` — przycisk "Obróć" (cykl 0→90→180→270→0) + segmented control Fit/Fill. Sheet przemianowany z "Trim" na **"Edit Clip"** (i przycisk w toolbarze z "Trim" na "Edit") — skoro hostuje teraz Trim+Split+Speed+Rotate+Crop, "Trim" przestało być trafną nazwą całości. Wysokość arkusza zwiększona do 460/560 (bez/z Split).

Build → **BUILD SUCCEEDED** na obu platformach **za pierwszym razem** mimo sporej zmiany architektonicznej (macierzowa matematyka transformów bez wcześniejszego prototypowania — nie zweryfikowane jeszcze wizualnie na realnym urządzeniu, tylko że się kompiluje i logika jest tym samym wzorcem co standardowe `preferredTransform` z AVFoundation). Zainstalowane na iPhone, Mac zrestartowany.

**Cała piątka Studio (Trim/Split/Crop/Rotate/Speed) zamknięta.** Następny większy krok wg `Docs/Studio.md`: multi-track + drag & drop reorder w timeline.

**Uczciwe zastrzeżenie**: transformy Rotate/Crop nie zostały jeszcze zweryfikowane wzrokowo na eksportowanym wideo przez usera (to matematyka macierzy przeniesiona z ugruntowanego wzorca AVFoundation, ale każdy nowy przypadek — zwłaszcza obrót Live Photo z ruchem czy wideo poziomego — wart faktycznego przetestowania eksportu przed uznaniem za w pełni gotowe).

## Stan na 26.07.2026, ciąg dalszy — Etap 2 "Studio": drag & drop reorder w timeline

Pierwsza z dwóch zapowiedzianych funkcji "Multi-track + drag & drop" — **prawdziwy multi-track** (nakładające się warstwy/PiP) to osobny, znacznie większy temat architektoniczny (nowy model danych, pionowy stos torów zamiast pojedynczej poziomej listy) — świadomie NIE tknięty w tym kroku, zostaje jako osobna pozycja backlogu.

**`EditView.swift`** (oba projekty) — `timeline` (pozioma lista miniatur) dostała `.draggable(String(index))` + `.dropDestination(for: String.self)` na każdym `TimelineThumbnail` (natywne SwiftUI drag & drop, nie custom `NSItemProvider`). Upuszczenie przeciąganego elementu NA inny element przenosi go na tę pozycję (`moveItem(from:to:)` — `items.remove(at:)` + `items.insert(at:)`), z korektą `selectedIndex` jeśli przenoszony element był akurat zaznaczony, i wywołaniem `syncProject()` żeby nowa kolejność od razu się zapisała.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany. Niezweryfikowane jeszcze wzrokowo na realnym urządzeniu (czy gest przeciągania faktycznie działa dobrze w praktyce, zwłaszcza w wąskim poziomym pasku miniatur).

### Do zrobienia dalej (Studio)
- Prawdziwy multi-track (nakładające się warstwy) — osobny, duży temat.
- Captions ręczne.
- Eksport z kontrolą rozdzielczości/jakości.

## Stan na 26.07.2026, ciąg dalszy — Etap 2 "Studio": Miksowanie audio / poziomy

**Ważne odkrycie przy okazji tego zadania**: appka do tej pory w OGÓLE nie eksportowała oryginalnego dźwięku z klipów wideo — `VideoComposer` dodawał tylko jedną ścieżkę audio dla muzyki w tle, żaden dźwięk z samych nagrań (rozmowy, otoczenie) nigdy nie trafiał do finalnego filmu. To naprawione przy okazji budowy kontroli poziomów, nie tylko dodane suwaki.

**`VideoComposer` — nowa ścieżka `originalAudioTrack`**: dla każdego klipu, jeśli źródłowy asset ma ścieżkę audio, wstawiana jest ONA SAMA `timeRange` co wideo (ten sam fragment, ten sam `cursor`), i skalowana TAK SAMO przez `scaleTimeRange` gdy `speed != 1.0` — żeby dźwięk zostawał zsynchronizowany z obrazem nawet przy przyspieszeniu/zwolnieniu (Speed z poprzedniego kroku). Zbierane są też pary (zakres-w-czasie-outputu, głośność) per klip do zbudowania miksu.

**Nowy `AVMutableAudioMix`** (`buildAudioMix`) — dwa `AVMutableAudioMixInputParameters`: jeden dla `originalAudioTrack` z głośnością USTAWIANĄ PER SEGMENT (`setVolume(_:at:)` wywoływane raz na klip — ta metoda obowiązuje "od tego czasu aż do następnego wywołania", więc każdy klip może mieć inną głośność swojego oryginalnego dźwięku), drugi dla ścieżki muzyki ze stałą głośnością na cały utwór. `ComposedProject` ma teraz trzecie pole `audioMix: AVMutableAudioMix?` (nil gdy żadna ścieżka audio nie została wstawiona — np. projekt z samych zdjęć), `VideoExporter` ustawia `exportSession.audioMix`.

**Model danych**: `MediaItem.originalVolume: Double = 1.0` (per klip, 0-1) + `SavedProject.musicVolume: Double = 1.0` (per projekt, jeden wspólny poziom muzyki). Oba zapisywane/odtwarzane tak samo jak reszta stanu (`syncProject()`/`loadInitialSong()`/rehydracja).

**UI**: suwak głośności oryginalnego dźwięku (`volumePicker`) dołożony do arkusza "Edit Clip" (obok Speed/Rotate/Crop) — wysokość zwiększona do 540/640 (bez/z Split). Suwak głośności muzyki (`musicVolumeRow`) — nowy rządek widoczny w `EditView` tylko gdy jakiś utwór jest wybrany, między timeline a dolnym paskiem narzędzi.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany. Sprawdzimy na etapie testowania (`Docs/Roadmap.md`), jak dotychczas.

### Do zrobienia dalej (Studio)
- Prawdziwy multi-track (nakładające się warstwy) — osobny, duży temat.

## Stan na 27.07.2026 — Etap 2 "Studio": Captions ręczne

**Nowy model `Caption`** (`Caption.swift`, ulotny — odpowiednik `MediaItem` dla napisów): tekst, `startTime`/`endTime` w sekundach WZGLĘDEM CAŁEGO finalnego filmiku (nie pojedynczego klipu), pozycja (top/center/bottom). Trwały odpowiednik `SavedCaption` (SwiftData) dołączony do `SavedProject` jako nowa relacja `captions: [SavedCaption]` (cascade delete, jak `items`).

**`CaptionsView.swift`** — lista napisów (dodaj/edytuj/usuń przez swipe), każdy wiersz: pole tekstowe, picker pozycji, dwa suwaki start/koniec ograniczone do `totalDuration` (suma `MediaItem.duration` wszystkich klipów, przekazywana z `EditView`). Nowy napis startuje tam, gdzie kończy się poprzedni (nie nakłada się domyślnie).

**Renderowanie — inny mechanizm niż Trim/Speed/Rotate**: te dotyczyły CZASU/TRANSFORMACJI klipu, ale napis to dodanie TREŚCI do klatki — używa `AVVideoCompositionCoreAnimationTool` (`videoComposition.animationTool`), standardowego wzorca AVFoundation do wypalania nakładek (np. znaku wodnego) w eksportowanym wideo. Dla każdego napisu: `CATextLayer` z `CAKeyframeAnimation` na `opacity` ([0,1,1,0] w `keyTimes`), `beginTime = AVCoreAnimationBeginTimeAtZero + startTime` — layer jest niewidoczny poza swoim zakresem czasu, widoczny w środku. Ta sama konwencja bottom-left-origin co surowy `CGContext` poznana wcześniej w tej sesji dotyczy też CALayer w tym kontekście — pozycje top/center/bottom liczone z tym na uwadze (duże Y = bliżej góry).

**Podpięcie**: przycisk "Text" w toolbarze (dawny placeholder "wkrótce") otwiera `CaptionsView`; podświetlony (`isActive`) gdy są jakieś napisy. `syncProject()`/rehydracja przy otwarciu projektu identyczne jak dla reszty stanu.

**Pułapka po drodze**: build failował po dodaniu `Caption.swift`/`CaptionsView.swift` — zapomniałem odpalić `xcodegen generate` po dodaniu nowych plików (glob w `project.yml` łapie cały folder automatycznie, ale trzeba REGENERACJI projektu, samo dodanie pliku na dysku nie wystarcza). Naprawione, potem build przeszedł czysto.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

## Stan na 27.07.2026, ciąg dalszy — Etap 2 "Studio": eksport z kontrolą jakości — CAŁA LISTA STUDIO ZAMKNIĘTA

Ostatni z zapowiedzianych punktów Etapu 2 (poza świadomie odłożonym prawdziwym multi-trackiem).

**Nowy `ExportQuality.swift`** — enum 720p/1080p/4K, każdy z odpowiadającym `canvasSize` (720×1280 / 1080×1920 / 2160×3840 — appka robi wideo pionowe 9:16 jak Reels/TikTok, więc to skalowanie TEGO wymiaru, nie zmiana proporcji).

**`VideoComposer`**: usunięty sztywny `static let canvasSize`, zastąpiony parametrem `quality: ExportQuality = .hd1080` w `buildComposition(...)` — canvas liczony lokalnie z `quality.canvasSize` na starcie funkcji. `resolveSourceURL` (osobna funkcja, nie widziała lokalnej zmiennej) dostała `canvasSize` jako jawny parametr zamiast czytać dawną stałą.

**UI**: przycisk "Next" nie eksportuje już od razu — otwiera nowy `ExportOptionsView` (segmented picker 720p/1080p/4K + przycisk "Eksportuj"), dopiero stamtąd startuje faktyczny `performExport()`. Wybór jakości NIE jest zapisywany trwale w projekcie (świadoma decyzja — to bardziej jednorazowy wybór przy eksporcie niż stan edycji jak Trim/Speed, żeby nie rozrastać schematu bez wyraźnej potrzeby).

Build → **BUILD SUCCEEDED** na obu platformach za pierwszym razem, zainstalowane na iPhone, Mac zrestartowany.

**Cała lista Etapu 2 "Studio" z `Docs/TODO.md` zamknięta**: Trim, Split, Speed, Crop/Rotate, drag & drop reorder, miksowanie audio, captions ręczne, eksport z kontrolą jakości — 8 z 9 pozycji zrobione, jedyna świadomie odłożona to prawdziwy multi-track (nakładające się warstwy/PiP), osobny, duży temat architektoniczny.

### Do zrobienia dalej (Studio)
- Prawdziwy multi-track (nakładające się warstwy) — osobny, duży temat.

## Stan na 27.07.2026, ciąg dalszy — Travel Map: styl linii per środek transportu

Pierwszy punkt z sekcji "Travel — dokończenie" w `Docs/TODO.md` (kolejny w kolejności po zamknięciu Studio).

**`RouteProvider`** — nowe `lineWidth(for:)` (grubsza dla `.cruise`, standardowa dla reszty) i `lineDashPattern(for:)` (długie kreski dla `.plane`, gęste krótkie dla `.train`, pusta tablica = linia ciągła dla reszty). Nowa `wavyGeodesic(from:to:)` dla `.boat` — ten sam mechanizm co istniejący `arcedGeodesic` (przesunięcie punktów prostopadle do kierunku trasy), ale kilka małych oscylacji (`sin(t × 6π)`) zamiast jednego łuku, wygaszanych do zera na obu końcach (`sin(t×π)` jako obwiednia) — wygląda jak delikatne fale, nie jak wygięta trasa. Statek wycieczkowy (`.cruise`) zostaje bez fal (tylko grubsza linia) — zgodnie z oryginalną specyfikacją "łódź faluje, statek jest grubszy", to dwie różne rzeczy.

**`TravelMapAnimationView`** — `revealedPaths: [[CLLocationCoordinate2D]]` zamieniony na `revealedLegs: [(path:, transport:)]`, żeby każdy odcinek trasy pamiętał JAKIM środkiem transportu został pokonany (wcześniej ta informacja się gubiła po zakończeniu odcinka — działało bo wszystkie odcinki wyglądały tak samo, teraz każdy musi zachować swój styl). `MapPolyline.stroke(_:style:)` z `StrokeStyle(lineWidth:dash:)` zamiast samego `lineWidth`.

**`TravelMapVideoRenderer`** (oba warianty) — te same wartości z `RouteProvider` zaaplikowane przez `ctx.setLineDash(phase:lengths:)`, grubość pomnożona ×1.5 względem żywego podglądu (tak jak już było ustalone wcześniej: wideo 3pt vs żywy podgląd 2pt, teraz to ×1.5 zamiast sztywnej liczby, żeby zachować proporcję dla każdego stylu).

**Pułapka po drodze**: `RouteProvider.lineDashPattern`/`lineWidth` zwracają `Double`, ale `StrokeStyle(dash:)` i `CGContext.setLineDash(lengths:)` chcą `[CGFloat]` — błąd kompilacji złapany od razu przy pierwszym buildzie, naprawiony przez `.map { CGFloat($0) }` w obu miejscach.

Build → **BUILD SUCCEEDED** na obu platformach (po jednej poprawce typu), zainstalowane na iPhone, Mac zrestartowany.

### Do zrobienia dalej (Travel — część niezależna od Database.md)
- Dodatkowy motyw mapy "Minimal White".
- Auto dzień/noc mapy.
- Płynniejsza kinowa kamera.
- Efekty otoczenia (cień/chmury/fale/gwiazdy/złota poświata).
- Przetestować eksport wideo Travel Map end-to-end na realu.

## Stan na 27.07.2026, ciąg dalszy — weryfikacja: dziób pojazdu zawsze zgodny z kierunkiem jazdy

User poprosił o pewność, że przód grafiki pojazdu faktycznie wskazuje kierunek ruchu (nie założenie, realna weryfikacja). Otwarte wszystkie 9 wycinanych assetów (`plane/train/car/boat-top`, `boat/cruise-right`, `boat/cruise-left`, `cruise-top`) i porównane wizualnie z `topBaseAngle(for:)`/logiką right-left w `VehicleIconSet.swift`:

- **plane-top**: dziób u góry kadru → zgodne z `topBaseAngle = 0`.
- **train-top**: zaokrąglona kabina (przód) u góry → zgodne z `topBaseAngle = 0`.
- **car-top**: reflektory na dole kadru (przód = dół) → zgodne z `topBaseAngle = 180`.
- **boat-top**: dziób u góry → zgodne z `topBaseAngle = 0`.
- **boat-right / cruise-right**: dziób wskazuje w prawo → zgodne z użyciem tego assetu wprost (bez rotacji) dla ruchu na wschód.
- **boat-left / cruise-left**: dziób wskazuje w lewo → zgodne z użyciem dla ruchu na zachód.
- **cruise-top**: dziób po lewej stronie kadru (widok poziomy) → zgodne z `topBaseAngle = 270`, potwierdzone też matematycznie (rotacja przy namiarze północnym obraca dziób z pozycji "lewo" na "góra").

**Wynik: wszystkie 9 assetów są zgodne z logiką kodu — dziób/przód pojazdu zawsze wskazuje kierunek jazdy**, dla wszystkich 5 środków transportu i wszystkich kierunków (N/S/E/W dla boat/cruise, dowolny namiar dla plane/train/car). Brak potrzeby poprawek.

## Stan na 27.07.2026, ciąg dalszy — Travel Map: motyw mapy "Minimal White"

Drugi punkt z sekcji "Travel — dokończenie" w `Docs/TODO.md`.

**Nowy `MapTheme.swift`** (wspólny w obu projektach) — enum `.satellite`/`.minimalWhite`, każdy z `mapStyle` (SwiftUI `MapStyle` dla żywego podglądu: `.hybrid(elevation: .realistic)` vs `.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false)`), `snapshotterMapType` (`MKMapType` dla `MKMapSnapshotter` w eksporcie wideo: `.hybrid` vs `.standard`), `showsBuildingsInSnapshot` i `forcedColorScheme` (Minimal White zawsze wymusza `.light`, żeby nie robił się szary w trybie ciemnym systemu — satelita nie potrzebuje wymuszania, zdjęcie nie zależy od light/dark).

**`TravelMapView`**: nowa sekcja "Motyw mapy" (segmented picker) obok istniejącej "Prędkość animacji", wybór przekazywany do `TravelMapAnimationView`.

**`TravelMapAnimationView`**: `.mapStyle(mapTheme.mapStyle)` + `.preferredColorScheme(mapTheme.forcedColorScheme)` zamiast sztywnego `.hybrid`. Wybór przekazywany dalej do `TravelMapVideoRenderer.renderAndSave` przy zapisie wideo, żeby eksport wyglądał tak samo jak podgląd na żywo.

**`TravelMapVideoRenderer`** (oba warianty UIKit/AppKit) — `takeSnapshot` dostał parametr `mapTheme`, ustawia `options.mapType`/`options.showsBuildings` z niego zamiast sztywnych wartości. Karty miasta/dystansu mają własne czarne półprzezroczyste tło, więc czytelność tekstu nie zależy od jasności mapy pod spodem — nie trzeba było zmieniać kolorów tekstu.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

### Do zrobienia dalej (Travel — część niezależna od Database.md)
- Auto dzień/noc mapy.
- Płynniejsza kinowa kamera.
- Efekty otoczenia (cień/chmury/fale/gwiazdy/złota poświata).
- Przetestować eksport wideo Travel Map end-to-end na realu.

## Stan na 27.07.2026, ciąg dalszy — edycja i usuwanie zapisanych podróży

User: zrobił jedną testową podróż nie dodając wszystkich przystanków, drugą żeby pokazać pomysł znajomemu — obie zostały na liście "Twoje podróże" bez możliwości poprawienia czy usunięcia (był tylko tap = odtwórz animację).

**`TravelMapView`**: nowy `@State private var editingTripID: UUID?`. Każdy wiersz podróży dostał `.contextMenu` (Edytuj/Usuń, długi przycisk/prawy klik) + `.swipeActions(edge: .trailing)` (swipe w lewo, natywny iOS — Usuń i Edytuj), zastępując gołe `.onDelete`. Nad formularzem pojawia się pasek "Edytujesz zapisaną podróż" z przyciskiem "Anuluj", kiedy `editingTripID != nil`; przycisk na dole zmienia się z "Pokaż trasę" na "Zapisz zmiany".

**`startEditing(_:)`** — wczytuje `trip.asTripStops` (już istniejące od czasu odtwarzania zapisanych tras) z powrotem do edytowalnej tablicy `stops`, więc user może dodać brakujące przystanki albo poprawić błąd zamiast tworzyć duplikat.

**`persistTrip(_:)`** — rozszerzone: jeśli `editingTripID` wskazuje istniejącą `SavedTrip`, kasuje jej stare `SavedStop` i podmienia na nowe zamiast wstawiać nowy rekord (unikanie duplikatów przy edycji). Bez edycji zachowanie bez zmian (tworzy nowy `SavedTrip` jak dotąd).

**`deleteTrip(_:)`** — usuwa `SavedTrip` z `modelContext`; jeśli akurat edytowana podróż zostanie usunięta, formularz się czyści (`cancelEditing()`), żeby nie zostawić "wiszącego" `editingTripID` wskazującego na nieistniejący rekord.

**Pułapka platformowa**: `.swipeActions` jest dostępne tylko na iOS/iPadOS/Catalyst, NIE na natywnym macOS — w wersji Mac użyty tylko `.contextMenu` (prawy klik) + `.onDelete` (klawisz Delete na zaznaczonym wierszu), bez `.swipeActions`, żeby nie wysypać buildu Maca.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

## Stan na 27.07.2026, ciąg dalszy — przeprojektowanie "Auto dzień/noc mapy" → "Cinematic Lighting" (tylko decyzja, bez kodu)

Kolejny punkt z `Docs/TODO.md` po edycji/usuwaniu tras miał być "Auto dzień/noc mapy". Zaproponowałem dwa warianty (prosty przełącznik wg zegara urządzenia / naukowo dokładny terminator dzień-noc na globusie) — user odrzucił OBA z konkretnym uzasadnieniem UX, nie techniki:

- Zegar urządzenia: "co mnie obchodzi, że u mnie jest 22:00? Jeżeli oglądam podróż po Japonii, chcę widzieć Japonię tak, jak wyglądała PODCZAS tej podróży" — zły punkt odniesienia (widz, nie miejsce/moment).
- Naukowy terminator: "to może zająć kilka tygodni pracy, a użytkownik spojrzy na to przez 3 sekundy — ROI jest słabe".

**Propozycja usera (przyjęta)**: "Cinematic Lighting" — mapa dostosowuje oświetlenie do pory dnia/roku W DANYM MIEJSCU I MOMENCIE PODRÓŻY (docelowo z EXIF zdjęć, dziś jako krok pośredni: godzina przylotu per przystanek, której jeszcze nie zbieramy — `SavedStop.arrivalDate` ma dziś tylko datę). Kategorie: Day/Golden Hour/Blue Hour/Night + sezonowe Snow/Autumn — konsumuje wcześniej osobno logowane "efekty otoczenia" (złota poświata, gwiazdy) zamiast być kolejnym dodatkiem obok nich. Technicznie: prosty kolorowy tint/overlay z cross-fade między odcinkami, NIE fizyczna symulacja/terminator na globusie — user explicité: "nie trzeba robić naukowo dokładnego terminatora, po prostu animujesz przejście".

User dorzucił też nazewniczą uwagę do zapamiętania na przyszłość: nie nazywać featurów po ich mechanizmie technicznym (np. "Auto dzień/noc") tylko po EFEKCIE jaki user odczuwa ("Cinematic Lighting", "mapa wygląda tak, jak pamiętam ten moment") — użytkownika nie interesuje algorytm.

Pełna specyfikacja (kategorie, źródła danych, powiązanie z "Travel Replay" — narracja "Tutaj byłeś rano/o zachodzie/nocowałeś") zapisana w `Docs/Travel.md`. **Nic z tego nie zaimplementowane** — świadomie odłożone, bo wymaga fundamentu (godzina per przystanek lub pełny EXIF pipeline), którego jeszcze nie ma. Kolejny w kolejce z listy "Travel — dokończenie": "Płynniejsza kinowa kamera".

## Stan na 27.07.2026, ciąg dalszy — Travel Map: płynniejsza kinowa kamera (tylko żywy podgląd)

Ostatni "łatwy" punkt z listy "Travel — dokończenie" po odłożeniu Cinematic Lighting.

**Problem**: kamera wcześniej robiła jeden skok do bounding-boxa całego odcinka na początku lotu/jazdy i stała tam nieruchomo — jedynym ruchem był marker pojazdu przesuwający się po nieruchomym tle. Nie wyglądało to "kinowo", tylko jak statyczna mapa z animowaną ikoną.

**Zmiana w `TravelMapAnimationView.runAnimation()`** (identyczna w obu projektach): w pętli 36 kroków animacji, obok dotychczasowej aktualizacji `planeCoordinate`/`planeHeading`, kamera teraz też się porusza — `cameraPosition = .camera(MapCamera(centerCoordinate: point, distance:, heading:, pitch: 55))`, aktualizowana co krok wewnątrz krótkiego `withAnimation(.linear(duration: 0.05 / speedMultiplier))`, żeby ruch był ciągły, nie skokowy. Kamera dosłownie "goni" pojazd, pochylona (pitch 55°) i obrócona zgodnie z kierunkiem jazdy (heading = namiar), zamiast patrzeć płasko z góry.

Struktura ujęcia (kinowa konwencja "establishing shot → close-up → settle"):
1. Ujęcie ustawiające — cały odcinek z góry (bez zmian, jak wcześniej).
2. Kamera pościgowa — 36 kroków lotu/jazdy, dystans (`followDistance(for:)`) skalowany per środek transportu: samolot 220 000 m (szerszy kadr, długie dystanse), łódź/statek 90 000 m, reszta 60 000 m — żeby tempo przelotu wyglądało proporcjonalnie do skali podróży, nie jednakowo ciasno dla samolotu transatlantyckiego i przejażdżki samochodem.
3. Kamera "siada" płasko (pitch 0, heading 0) nad przystankiem tuż przed pokazaniem karty miasta — czytelny, wypoziomowany widok zamiast zostawiania przechylonej kamery z lotu.

**Świadomie NIEZROBIONE — eksport wideo nadal ma starą, statyczną kamerę.** `TravelMapVideoRenderer` bierze JEDEN nieruchomy zrzut satelitarny (`MKMapSnapshotter`) na cały odcinek i komponuje na nim ruch ikony/linii — to była świadoma decyzja architektoniczna od początku (nagrywanie żywego `Map` jest ryzykowne, kafelki ładują się asynchronicznie). Podążająca kamera wymagałaby zrzutu PER KLATKA (36× więcej wywołań `MKMapSnapshotter` na odcinek zamiast 1) — dużo wolniejszy, bardziej kruchy eksport. Rozdzielenie "kinowa kamera w podglądzie" vs. "w eksporcie" na dwa osobne, niezależne zadania — nie udawać że jest to samo.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

### Do zrobienia dalej (Travel — część niezależna od Database.md)
- Kinowa kamera w EKSPORTOWANYM wideo (dziś nadal statyczny zrzut per odcinek) — osobny, potencjalnie kosztowny wydajnościowo temat.
- Przetestować eksport wideo Travel Map end-to-end na realu.

## Stan na 27.07.2026, ciąg dalszy — REGRESJA: kamera "w pościgu" gubi miasto docelowe z kadru

User przetestował nową kinową kamerę na realu (screenshot) i zgłosił: podczas lotu nie widać miasta docelowego, a po lądowaniu też nie. Diagnoza: kamera pościgowa jest ciasno przybliżona (`followDistance`) i pochylona (pitch 55°) na AKTUALNĄ pozycję pojazdu — wcześniej (przed zmianą "kinowa kamera") szeroki, nieruchomy widok pokazywał od razu CAŁY odcinek razem z celem, więc destynacja była zawsze w kadrze (albo przynajmniej jej etykieta z bazowej mapy Apple). Nowa kamera to zgubiła — realna regresja UX z poprzedniej zmiany, nie wymyślony problem.

**Fix**: nowy `@State private var upcomingStop: TripStop?`, ustawiany na cel (`to`) na starcie każdego odcinka, czyszczony w momencie przylotu (`visitedStops.append(to)`). Dwa efekty:
1. Nowy `DestinationBadge` (analogiczny do istniejącego `DistanceBadge`) w rogu `.topLeading` — stały napis "→ 🏳️ Miasto" na ekranie, NIEZALEŻNY od kamery/mapy, więc zawsze czytelny niezależnie jak ciasno/pochylona jest kamera pościgowa.
2. Dodatkowy `Marker` (szary, `.tint(.gray)`) dla `upcomingStop` na samej mapie — jeśli kamera akurat obejmuje ten obszar, cel ma już swoją etykietę zamiast czekać na przylot.

Świadomie NIE cofnąłem kinowej kamery do poprzedniego, statycznego zachowania — user chciał kinowego efektu, tylko bez utraty orientacji "dokąd zmierzam". `DestinationBadge` rozwiązuje to bez rezygnacji z kamery pościgowej.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany. Czeka na ponowny test na realu.

## Stan na 27.07.2026, ciąg dalszy — BUG: ikona samolotu dziwnie się skręcała podczas lotu

User zgłosił: ikona samolotu "dziwnie się skręca" zamiast płynnie wskazywać kierunek lotu. Diagnoza: klasyczny SwiftUI bug z `rotationEffect` na granicy 0°/360° — namiar (`planeHeading`) jest znormalizowany do zakresu [0, 360), więc przy locie w okolicach namiaru północnego wartość potrafi przeskoczyć np. z 359° na 1° (realnie obrót o 2°). Bez zabezpieczenia SwiftUI animuje to jako obrót "długą drogą" (prawie pełne 358° w złą stronę) zamiast krótkiego skrętu o 2° — nowa, animowana co krok kamera "w pościgu" (poprzednia zmiana z tej sesji) najwyraźniej dodała aktywną transakcję animacji, która to ujawniła (wcześniej kamera się nie poruszała co krok, więc problem nie był widoczny).

**Fix**: `.animation(nil, value: resolved.rotationDegrees)` na `Image` ikony pojazdu w obu projektach — wyłącza interpolację obrotu, ikona przeskakuje bezpośrednio do właściwego kąta co krok (36 kroków na odcinek to i tak wystarczająco częste aktualizacje, żeby wyglądało płynnie, bez ryzyka złej strony obrotu).

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

## Stan na 27.07.2026, ciąg dalszy — jakość eksportu wideo: za szeroki kadr startowy + niska jakość obrazu

Pierwszy realny test eksportu wideo Travel Map przez usera (nigdy wcześniej nieklikany przycisk "Zapisz jako wideo"). Zrzut ekranu pokazał: kadr startowy (przed odlotem) pokazywał całą Europę Środkową/Północną (Norwegia→Turcja) zamiast bliskiego ujęcia miasta wylotu, plus ogólne wrażenie niskiej jakości/rozmycia obrazu. User potwierdził oba przez doprecyzowujące pytanie (nazwa lotniska w karcie — "John Paul II Kraków-Balice International Airport" — jest ZAMIERZONA, user świadomie wybrał lotnisko jako punkt wylotu i chce widzieć jego pełną nazwę, to NIE bug).

**Fix 1 — kadr startowy**: `MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30)` w `TravelMapVideoRenderer` (oba warianty) i analogiczny `latitudeDelta: 40, longitudeDelta: 40` w żywym podglądzie (`TravelMapAnimationView.runAnimation()`, oba projekty) zmniejszone do `8×8` — dużo bliższe, "ładniejsze" ujęcie miasta wylotu zamiast pół kontynentu. Ujednolicone między podglądem a eksportem (wcześniej podgląd był nawet SZERSZY niż eksport).

**Fix 2 — jakość obrazu**: `AVAssetWriterInput.outputSettings` nie miał jawnego bitrate'u — AVFoundation dobierał wtedy zachowawczą wartość, co na szczegółowej teksturze satelitarnej (teren/woda/chmury, dużo wysokoczęstotliwościowego szumu wizualnego) dawało widoczne artefakty kompresji. Dodany `AVVideoCompressionPropertiesKey` z `AVVideoAverageBitRateKey: 12_000_000` (12 Mbps) i `AVVideoProfileLevelH264HighAutoLevel` w obu wariantach `TravelMapVideoRenderer`.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany. Czeka na ponowny test eksportu na realu.

## Stan na 27.07.2026, ciąg dalszy — eksport wideo: brak etykiety celu podczas przelotu

User przetestował poprawiony eksport (screenshot) — kadr startowy i jakość obrazu ocenione jako wyraźnie lepsze. Ale nowe zastrzeżenie: **"nie widać skąd startuje i gdzie ląduje"**, z twardym stwierdzeniem: albo eksport nagrywa tak jak żywa animacja w appce, albo nie ma sensu w ogóle.

Diagnoza: w `composite()` (oba warianty `TravelMapVideoRenderer`) podczas samego przelotu (`progress` w `0..<1`) rysowana jest TYLKO linia trasy i ikona pojazdu na nieruchomym zrzucie mapy — żadna etykieta miasta. Karty ("card") pokazują się wyłącznie na starcie (0.8s) i przy lądowaniu (1.2s) — przez resztę (dłuższą) część przelotu user widzi samą linię i ikonę na pustej satelitarnej mapie bez informacji tekstowej dokąd zmierza. Sam bounding-box zrzutu (`regionContaining(path)`) geograficznie ZAWIERA oba punkty (start+koniec), ale bez etykiety user i tak nie wie który to który.

**Ważne rozróżnienie potwierdzone przez usera**: to NIE to samo co odłożona wcześniej "kinowa kamera w eksporcie" (podążająca, kosztowna kamera wymagająca 36× więcej zrzutów). Prawdziwy problem był dużo tańszy do naprawienia — brakowało tylko STAŁEJ ETYKIETY, nie ruchomej kamery.

**Fix**: nowy parametr `destinationStop: TripStop?` w `composite()` (oba warianty), przekazywany dla wszystkich klatek przelotu (`progress < 1`, wyłączony na klatce lądowania gdzie przejmuje kartę). Nowa funkcja `drawDestinationBadge(_:in:canvasSize:)` — dorysowuje "→ 🏳️ Miasto" w rogu KAŻDEJ klatki przelotu, na już istniejącym zrzucie (bez dodatkowych wywołań `MKMapSnapshotter` — tanie). Ten sam pomysł co `DestinationBadge` dodany wcześniej do żywego podglądu, tu przeniesiony na eksport. W wersji Mac uwaga na układ współrzędnych: `CGContext` ma origin lewy-dolny (bez flipa), więc "lewy górny róg" ekranu to WYSOKI `y`, nie niski — zgodnie z istniejącą konwencją w `drawDistanceBadge`.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany. Czeka na ponowny test eksportu na realu.

## Stan na 27.07.2026, ciąg dalszy — Studio: crossfade między klipami + zaplanowane smart-crop

User zgłosił jednym zdjęciem trzy sprawy naraz (zrobiony wcześniej filmik Studio): (1) "przejścia są tragiczne, zwykłe proste bez żadnych ciekawych efektów", (2) "obcina zdjęcia kompletnie bez wyczucia", (3) samolot na Travel Map dalej "nie bardzo się orientuje". Rozdzielone i zdiagnozowane osobno:

1. **Przejścia** — sprawdzone w kodzie: rzeczywiście ZERO przejść, każde cięcie to twardy cut (żadnego `transition`/`crossfade`/`fadeIn` w całym `VideoComposer`). User potwierdził chęć dodania crossfade od razu.
2. **Kadrowanie** — `layerTransform` robi ślepy geometryczny center-crop (`cropFill` = skaluj-do-wypełnienia + wycentruj), bez świadomości gdzie są twarze/ważne elementy zdjęcia. Zaplanowane na później jako "Smart Crop" (Vision framework, `VNDetectFaceRectanglesRequest`) — user świadomie wybrał OSTROŻNIEJSZE podejście ("zaplanuj na później"), bo to miejsce w kodzie (transformy/orientacja) już miało realne bugi w tej sesji (flip/rotacja) i wymaga starannej pracy z mapowaniem współrzędnych, nie szybkiej łatki.
3. **Samolot** — to zdjęcie pochodziło z FILMIKU STUDIO (nie z Travel Map), więc nie wiadomo czy dotyczy najnowszego builda z poprawką `.animation(nil, value:)` — user proszony o ponowny test na aktualnej wersji.

**Zaimplementowane: crossfade (przenikanie) między klipami.** Największa przebudowa `VideoComposer.buildComposition()` w tej sesji:
- **Dwa tory wideo** (`videoTrackA`/`videoTrackB`, na przemian per klip) zamiast jednego — crossfade wymaga żeby dwa sąsiednie klipy przez chwilę odtwarzały się RÓWNOCZEŚNIE (jeden gaśnie, drugi wchodzi), a pojedynczy `AVMutableCompositionTrack` nie pozwala na nakładające się zakresy czasu na tym samym torze. To samo dla oryginalnego dźwięku klipów (`originalAudioTrackA`/`B`) — przy okazji dźwięk też ładnie się przenika zamiast twardo urywać.
- **`ClipPlacement`** — nowa struktura (track/start/duration/transform) do rozdzielenia "wstawiania klipów" od "budowania instrukcji renderowania" na dwa przebiegi: najpierw wszystkie klipy trafiają na swoje tory z odpowiednim przesunięciem (każdy kolejny klip zaczyna się `transitionDuration` PRZED końcem poprzedniego, tworząc zakładkę), dopiero potem `buildInstructions(placements:transitionDurations:)` układa segmenty "solo" (jedna warstwa) i "przejście" (dwie warstwy z rampą przezroczystości `setOpacityRamp`, wchodzący klip na wierzchu).
- **Czas przejścia**: stałe 0.4s, przycinane per-para do połowy KRÓTSZEGO z dwóch sąsiadujących klipów (żeby bardzo krótki klip nie został "zjedzony" przez przejście z obu stron) — matematycznie zagwarantowane, że segment "solo" nigdy nie wychodzi ujemny (suma transition-przed + transition-po ograniczona do całkowitej długości klipu).
- **`buildAudioMix`** rozszerzony o dwa tory oryginalnego dźwięku zamiast jednego, każdy ze swoim `AVMutableAudioMixInputParameters` i przefiltrowanymi segmentami głośności (`trackIndex`).
- Bez nowego UI — user nie prosił o kontrolę per-klip, więc czas przejścia jest stały (0.4s), nie edytowalny.

**Ten sam kod skopiowany bez zmian do wersji Mac** (`VideoComposer.swift` był identyczny między projektami, `cp` zamiast ręcznej edycji drugi raz).

Build → **BUILD SUCCEEDED** na obu platformach za pierwszym razem, zainstalowane na iPhone, Mac zrestartowany. Czeka na test na realu — pierwsza zmiana w tej sesji dotykająca architektury multi-track (choć to NIE to samo co odłożony "prawdziwy multi-track"/PiP z nakładającymi się dowolnie warstwami — to węższy, celowy przypadek: tylko sąsiednie klipy, tylko podczas przejścia).

### Do zrobienia dalej (Studio)
- Smart Crop (kadrowanie wg wykrytych twarzy, Vision framework) — świadomie odłożone, wymaga ostrożnej pracy z mapowaniem współrzędnych.
- Prawdziwy multi-track (nakładające się warstwy/PiP) — nadal osobny, duży temat.

## Stan na 27.07.2026, ciąg dalszy — eksport wideo: samolot leciał tyłem + brakowało miasta startowego

Po serii nieporozumień (user wysyłał miniaturkę wideo z biblioteki Zdjęć zamiast prawdziwej klatki z lotu, ja błędnie chwaliłem klatkę której nie widziałem właściwie) user w końcu przesłał realny zrzut z odtwarzania (pauza w trakcie lotu): etykieta celu DZIAŁAŁA ("→ Bangkok" widoczne) — czyli poprzedni fix faktycznie zadziałał, wcześniejsze zrzuty to była tylko miniaturka. Ale user potwierdził wprost patrząc na wideo: **samolot leci tyłem** (dziób NIE wskazuje kierunku lotu), i zażądał też pokazania miasta STARTOWEGO obok docelowego, nie tylko celu.

**Dyskusja o architekturze**: user zapytał wprost "dlaczego video nie może być takie samo jak animacja?" — uczciwie wytłumaczyłem, że to dwie osobne implementacje (żywy podgląd = prawdziwa matematyka geograficzna w SwiftUI Map; eksport = `MKMapSnapshotter` + ręczne rysowanie `CGContext`, bo nagrywanie żywej mapy uznano za ryzykowne przez asynchroniczne ładowanie kafelków). User wybrał "przebuduj eksport żeby był tym samym co podgląd" — ale po głębszym namyśle sprecyzowałem: `MKMapSnapshotter` (w przeciwieństwie do żywego `MKMapView`) NIE ma problemu z asynchronicznym ładowaniem kafelków (celowo czeka na pełne wyrenderowanie), więc bezpieczniej jest zostawić sprawdzony snapshot i naprawić TYLKO warstwę nakładki (rysowaną ręcznie), zamiast ryzykownej pełnej przebudowy na przechwytywanie żywego widoku. User zaakceptował to doprecyzowanie.

**Fix 1 — obie nazwy miast**: `composite()` dostał nowy parametr `originStop: TripStop?` obok `destinationStop`. Nowa `drawRouteBadge(from:to:)` (zastąpiła `drawDestinationBadge`) rysuje "🏳️ Miasto → 🏳️ Miasto" (obie flagi, user: "powinna być nazwa z flagą obok") zamiast samego celu. To samo zmienione w żywym podglądzie: nowy `currentOriginStop` obok istniejącego `upcomingStop`, `RouteBadge` (zastąpił `DestinationBadge`) pokazuje oba miasta.

**Fix 2 — kierunek samolotu (empiryczny)**: mimo starannej analizy na papierze (sprawdziłem że `atan2` daje poprawny "0=góra,90=prawo,zgodnie z ruchem wskazówek zegara" zarówno dla `bearingDegrees`, jak i że `CGContext.rotate(by:)` w `UIGraphicsImageRenderer` — kontekst z origin lewy-górny/flip — TEŻ obraca zgodnie z ruchem wskazówek dla dodatniego kąta, więc matematyka teoretycznie się zgadzała), user empirycznie potwierdził że w praktyce leci tyłem. Zamiast dalej teoretyzować (ryzyko powtórzenia błędu — ta sama pułapka co wcześniejszy "czerwony śledź" z flipem CGContext w tej sesji), zastosowany empiryczny fix: odwrócony znak (`-resolved.rotationDegrees` zamiast `resolved.rotationDegrees`) w wywołaniu `ctx.rotate(by:)`. **Tylko dla iPhone/UIKit** — czeka na potwierdzenie usera czy to naprawiło problem.

**Mac NIE dostał tej samej poprawki** — tamten `composite()` używa surowego `CGContext` (origin lewy-dolny, BEZ flipa) zamiast `UIGraphicsImageRenderer`, więc konwencja obrotu może być inna (a nawet przeciwna) niż na iPhonie. Zostawiony komentarz w kodzie z instrukcją co spróbować, jeśli Mac ma ten sam problem — eksport na Macu nie był w ogóle testowany w tej sesji.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany. Czeka na potwierdzenie czy samolot teraz leci przodem.

## Stan na 27.07.2026, ciąg dalszy — BUG: apka zabijana w trakcie zapisu wideo Travel Map

User: apka wyłącza się kilka sekund po rozpoczęciu "Zapisywanie…" przy eksporcie wideo. Próba ściągnięcia realnego logu awarii z telefonu (`idevicecrashreport` przez `brew install libimobiledevice`) — nieudana, telefon podłączony tylko przez Wi-Fi, `libimobiledevice` widzi urządzenia wyłącznie przez USB. Brak kabla pod ręką, więc diagnoza wyłącznie przez analizę kodu (bez potwierdzonego logu — jeśli to nie pomoże, trzeba będzie wrócić do tematu z prawdziwym logiem).

**Znaleziony realny anti-pattern**: `renderVideo()` (oba warianty) tworzył NOWY `CVPixelBuffer` od zera (`CVPixelBufferCreate`) dla KAŻDEJ pojedynczej klatki wideo, zamiast reużywać bufory z puli, którą `AVAssetWriterInputPixelBufferAdaptor` udostępnia właśnie w tym celu (`adaptor.pixelBufferPool`) — to udokumentowany, zalecany przez Apple wzorzec, którego kod nie używał. Ciągłe allokowanie nowej pamięci klatka po klatce (przy dziesiątkach/setkach klatek na dłuższej podróży, teraz dodatkowo cięższych przez wyższy bitrate 12 Mbps z poprzedniej poprawki) narastająco obciąża pamięć i może prowadzić do zabicia procesu przez system (classic memory-pressure kill, nie zawsze widoczny jako jawny crash log — czasem to po prostu SIGKILL od jądra).

**Fix**: `appendFrame` pobiera bufor przez `CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, adaptor.pixelBufferPool!, &pixelBufferOut)` zamiast `CVPixelBufferCreate` od zera. Funkcja `pixelBuffer(from:size:)` (alokująca) zastąpiona przez `draw(_:into:size:)` (tylko rysuje w JUŻ dostarczony bufor z puli) w obu wariantach (UIKit/`UIImage`, AppKit/`CGImage`).

**Uczciwe zastrzeżenie**: to najbardziej prawdopodobna przyczyna na podstawie analizy kodu, ale BEZ potwierdzonego logu awarii nie mam 100% pewności że to JEDYNA przyczyna — jeśli crash się powtórzy, kolejny krok to zdobycie prawdziwego logu (kabel USB + `idevicecrashreport`, teraz już zainstalowany na tym komputerze, albo Xcode → Window → Devices and Simulators → View Device Logs).

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

## Stan na 27.07.2026, ciąg dalszy — Travel Map: widok globusa zamiast kamery pościgowej (żywy podgląd)

User pokazał zrzut referencyjny (aplikacja/film pokazujący Londyn na widoku Ziemi jako kuli — widoczna krzywizna, ciemna przestrzeń w tle, etykieta "LONDON / UNITED KINGDOM" z flagą przypięta bezpośrednio do punktu na globusie) i poprosił o dokładnie taki styl: "wtedy mamy wyraźnie skąd samolot startuje, jak leci i gdzie ląduje... to jest dużo lepsze". Wyraźnie stwierdził że to ZASTĘPUJE, nie dodaje do, dotychczasową kamerę "w pościgu" (bliska, pochylona, obracająca się za pojazdem — zbudowana wcześniej w tej sesji) — i że dzięki temu stylowi osobny napis "skąd→dokąd" na górze ekranu (`RouteBadge`, dodany chwilę wcześniej) staje się zbędny.

**Nowa kamera**: `globeDistance = 12_000_000` (metry) — stały, bardzo duży dystans przez CAŁĄ animację (start, przelot, lądowanie), zawsze `heading: 0, pitch: 0` (north-up, bez pochylenia — jak prawdziwe zdjęcia satelitarne/z orbity, NIE obracające się razem z kierunkiem jazdy jak poprzednia kamera pościgowa). Kamera przesuwa swój środek wzdłuż `path` tymi samymi punktami co pozycja pojazdu — sam ten ruch środka kamery przy stałym, bardzo dużym dystansie daje wrażenie "obracającej się planety" pod nieruchomym punktem widzenia, bez żadnej dodatkowej logiki animacji obrotu globusa. Usunięte: osobne "ujęcie ustawiające" (`region(containing:)`), osobna faza "kamera siada płasko przed kartą" — z jednym spójnym stylem przez całą animację te przejściowe etapy przestały być potrzebne.

**Nowe etykiety miast**: `GlobeCityLabel` (flaga, nazwa miasta wielkimi literami, kraj, ciemne półprzezroczyste tło, mały niebieski punkt) zastąpiła zarówno systemowe `Marker` (przystanki odwiedzone/nadchodzący) JAK I usunięty `RouteBadge` — etykieta jest teraz przypięta wprost do współrzędnej na globusie (`Annotation`), nie do stałego miejsca na ekranie. Nadchodzący cel renderowany z `opacity: 0.6` (odróżnienie od już odwiedzonych, pełna nieprzezroczystość).

**Usunięte jako nieużywane**: `followDistance(for:)` (dystans kamery pościgowej per środek transportu), `region(containing:)` (bounding box ustawiającego ujęcia), `RouteBadge` struct, stan `currentOriginStop` (departure jest już zawsze widoczny jako ostatni wpis w `visitedStops`, nie trzeba osobno śledzić).

**Uczciwe zastrzeżenie**: `globeDistance = 12_000_000` to PIERWSZE PRZYBLIŻENIE, nie zmierzona/wykalibrowana wartość — nie da się przewidzieć idealnego dystansu bez zobaczenia renderu na żywo. Będzie trzeba dostroić wspólnie z userem po pierwszym teście wizualnym (za mało/za dużo widocznej krzywizny, za mały/za duży plan miasta itp.).

**Świadomie NIE zmienione**: eksport wideo (`TravelMapVideoRenderer`) nadal używa starego modelu (statyczny zrzut `MKMapSnapshotter` na odcinek, bounding box zawierający całą trasę) — ta zmiana dotyczy WYŁĄCZNIE żywego podglądu w aplikacji. Jeśli user zaakceptuje styl globusa po teście, przeniesienie go też do eksportu to osobny, kolejny krok (wymaga przeliczenia jak zrobić globe-view z pojedynczego statycznego zrzutu na cały odcinek zamiast animowanej kamery).

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany. Czeka na pierwszy test wizualny.

## Stan na 27.07.2026, ciąg dalszy — BUG: kamera globusa nie nadążała za samolotem

User przetestował widok globusa: "kamera nie nadąża za samolotem". Diagnoza: `planeCoordinate` ustawiane natychmiast (bez animacji) co krok pętli, ale `cameraPosition` było opakowane w `withAnimation(.linear(duration:))` — dwa OSOBNE mechanizmy czasowe (natychmiastowe przypisanie stanu vs. animacja SwiftUI), które przy dużych skokach geograficznych między krokami (typowe dla widoku globusa — każdy krok to potencjalnie setki km) rozjeżdżają się w czasie, zostawiając kamerę w tyle za już przesuniętą ikoną samolotu.

**Fix**: usunięty `withAnimation` wokół aktualizacji `cameraPosition` w pętli lotu — kamera ustawiana wprost, w dokładnie tym samym momencie i tempie co `planeCoordinate`. Sama częstotliwość kroków (60 na odcinek, co ~45ms) daje wystarczająco płynne wrażenie ruchu bez potrzeby dodatkowej interpolacji SwiftUI.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

## Stan na 27.07.2026, ciąg dalszy — crash przy zapisie wideo NADAL występował — tym razem prawdziwy log

Poprzedni fix (pula buforów pikseli) nie pomógł — user: "dalej zamyka aplikację przy zapisie". Zamiast zgadywać dalej, zdobyty PRAWDZIWY log awarii bez kabla USB, przez `xcrun devicectl device info files --domain-type systemCrashLogs` (odkryta wcześniej nieznana opcja tego narzędzia) — telefon ma domenę `systemCrashLogs` dostępną też przez Wi-Fi, nie tylko `idevicecrashreport` (które faktycznie wymaga USB). Ściągnięte przez `devicectl device copy from` dwa świeże pliki `JetsamEvent-*.ips`.

**Analiza (Python, parsowanie formatu `.ips` — nagłówek JSON + treść JSON w drugiej linii)**: `JetsamEvent-2026-07-27-125405.ips` potwierdza wprost:
- `"largestProcess": "PMemories"`
- proces PMemories: `"reason": "per-process-limit"`, `"rpages": 216064`
- `pageSize` z `memoryStatus`: 16384 bajtów
- **216064 × 16384 = ~3.3 GB** — PMemories zostało zabite przez system (Jetsam) za przekroczenie limitu pamięci procesu, w trakcie eksportu wideo Travel Map. Realny, potwierdzony dowód — nie domysł.

**Diagnoza**: poprzedni fix (pula buforów pikseli z `adaptor.pixelBufferPool`) był słuszny, ale niewystarczający — dotyczył tylko bufora docelowego. Prawdziwe źródło narastania pamięci: pętla renderowania (`composite()` przez `UIGraphicsImageRenderer`, dziesiątki/setki klatek) działa w kontekście `async`/`await`, gdzie Swift NIE gwarantuje częstego opróżniania puli autorelease tak jak zwykła synchroniczna pętla na wątku głównym (tam runloop drenuje pulę co "tick"). Tymczasowe obiekty Objective-C (CGImage, CGContext i inne wewnętrzne obiekty `UIGraphicsImageRenderer`) mogły się kumulować klatka po klatce zamiast być zwalniane na bieżąco.

**Fix**: `composite()` + rysowanie do bufora piksela opakowane w jawny `autoreleasepool { }` w KAŻDEJ iteracji — nowa funkcja `appendComposedFrame(...)` (oba warianty) łączy budowanie obrazu i dołączanie do writer'a w JEDNYM bloku autorelease, zamiast budować obraz NA ZEWNĄTRZ (bez opakowania) i tylko część zapisu do bufora opakowywać (jak w poprzednim, niewystarczającym fixie).

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany. Czeka na ponowny test — tym razem z realną diagnozą popartą logiem, więc pewność dużo wyższa niż poprzednio.

## Stan na 27.07.2026, ciąg dalszy — eksport wideo PRZEBUDOWANY żeby wyglądał jak żywy podgląd (widok globusa)

User po zobaczeniu, że nawet POPRAWIONY eksport (kadr/jakość/etykieta) nadal wygląda zupełnie inaczej niż nowy widok globusa w aplikacji: "dlaczego nie zapisuje tego co wyświetla przed zapisem? chcę dokładnie to mieć zapisane!!!!", "film z innej perspektywy, całkowicie inny niż ten co widzisz w aplikacji". Słuszna uwaga — eksport od początku sesji był OSOBNĄ implementacją (jeden statyczny zrzut `MKMapSnapshotter` na cały odcinek, bounding box), zbudowaną świadomie inaczej niż żywy podgląd, i seria łatek (etykieta, kierunek samolotu, kadr) poprawiała szczegóły tej innej implementacji zamiast rozwiązać źródło rozjazdu.

**Kluczowe odkrycie przed przebudową**: `MKMapSnapshotter.Options` ma właściwość `camera: MKMapCamera?` — DOKŁADNIE te same parametry co `MapCamera` z żywego podglądu (centerCoordinate/distance/pitch/heading). Oznacza to, że dało się przenieść widok globusa do eksportu BEZ ryzyka, którego appka unikała od początku (nagrywanie ŻYWEGO `MKMapView` — asynchroniczne ładowanie kafelków) — `MKMapSnapshotter` samo w sobie zawsze czekało na pełne wyrenderowanie przed oddaniem obrazka, niezależnie czy dostaje `region` czy `camera`.

**Przebudowa `renderVideo()` (oba warianty)**:
- Zamiast JEDNEGO zrzutu na cały odcinek: zrzut PER KLATKA (`takeGlobeSnapshot(center:)`), z kamerą wycentrowaną na aktualnej pozycji pojazdu — ten sam `globeDistance = 12_000_000` co w `TravelMapAnimationView`, ta sama liczba kroków (60, skalowana przez `speedMultiplier`) — kamera w eksporcie teraz dosłownie podąża za pojazdem tak jak w podglądzie, nie stoi w miejscu nad całym odcinkiem.
- `composite()` przyjmuje teraz `visitedStops: [TripStop]` (wszystkie dotąd odwiedzone, nie tylko poprzedni przystanek) i `upcomingStop: TripStop?` zamiast pary `originStop`/`destinationStop` — dokładnie ten sam model danych co `TravelMapAnimationView`.
- Nowa `drawGlobeCityLabel(_:at:in:dimmed:)` zastąpiła `drawRouteBadge` — etykieta (flaga, miasto WIELKIMI LITERAMI, kraj, ciemne tło, niebieski punkt) rysowana bezpośrednio na projekcji współrzędnej (`snapshot.point(for:)`), nie jako stały napis w rogu ekranu — identyczny wygląd i zachowanie co `GlobeCityLabel` (SwiftUI) w podglądzie, w tym przyciemnienie (`dimmed`) dla celu jeszcze nieosiągniętego.
- `regionContaining(_:)` i stary `takeSnapshot(region:)` usunięte jako nieużywane — zastąpione przez `takeGlobeSnapshot(center:)`.

**Świadomy koszt tej zmiany**: eksport będzie ZAUWAŻALNIE WOLNIEJSZY niż wcześniej — 60 zrzutów `MKMapSnapshotter` na odcinek zamiast 1 (dla trasy Kraków→Bangkok to np. 60 zamiast 1 zrzutu). To bezpośrednia konsekwencja tego, że kamera faktycznie się teraz porusza w eksporcie, nie da się tego uniknąć bez utraty spójności z podglądem. Struktura `autoreleasepool`/pula buforów z poprzedniej poprawki pozostaje — kluczowa właśnie TERAZ, przy dużo większej liczbie zrzutów/klatek.

**Wersja Mac**: przepisana analogicznie, ale UWAGA na inną konwencję współrzędnych (`CGContext` surowy, origin lewy-dolny, bez flipa) — `drawGlobeCityLabel` na Macu układa kolejne linie tekstu przez ODEJMOWANIE wysokości (schodzenie w dół), nie dodawanie jak na iOS. Znak obrotu samolotu na Macu NIE zmieniony (wciąż nieprzetestowany w tej sesji, zostawiona wcześniejsza notatka w kodzie).

**Uczciwe zastrzeżenie**: `MKMapSnapshotter.Options.camera` skompilowało się poprawnie na obu platformach (potwierdza że API istnieje), ale czy wizualnie renderuje TEN SAM widok globusa (widoczna krzywizna, ciemna przestrzeń) co żywy `Map` z `MapCamera` — tego nie da się potwierdzić bez testu na realu. Też nieznane: jak bardzo eksport spowolnił w praktyce.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

## Stan na 27.07.2026, ciąg dalszy — BUG: samolot w przebudowanym eksporcie leciał bokiem

User przetestował nowy eksport z widokiem globusa: "to co zapisało to nie to samo co pokazany filmik w apce i samolot leci bokiem". Diagnoza: przy przebudowie eksportu na widok globusa (poprzedni wpis) namiar samolotu nadal liczył się ze STAREGO przybliżenia — `atan2` na PROJEKCJI EKRANOWEJ (`snapshot.point(for:)`), które było skalibrowane (razem z odwróconym znakiem) dla bliskiej kamery pościgowej. Przy nowym, ogromnym oddaleniu (widok globusa) skala tej projekcji jest zupełnie inna — przybliżenie z pikseli przestało dawać sensowny wynik, stąd "bokiem" zamiast poprawnego kierunku.

**Fix**: zamiast przybliżenia z pikseli ekranu, namiar liczony teraz z PRAWDZIWEJ geografii (szerokość/długość) — nowa `geographicBearing(from:to:)`, identyczny wzór co już sprawdzony w żywym podglądzie (`TravelMapAnimationView.bearing(from:to:)`). To rozwiązanie niezależne od poziomu przybliżenia kamery, więc nie powinno się już psuć przy zmianach zoomu w przyszłości. Poprzedni odwrócony znak (`-resolved.rotationDegrees` na iPhone) zostawiony bez zmian — to osobna kwestia (konwencja obrotu `CGContext`), teraz stosowana do poprawnej wartości kąta zamiast błędnej.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany. Czeka na test — to POPRAWKA DO POPRAWKI, więc szczególnie ważne żeby user potwierdził czy teraz faktycznie się zgadza.

## Stan na 27.07.2026, ciąg dalszy — PRAWDZIWY DOWÓD: MKMapSnapshotter nie umie widoku globusa + przejście na żywą MKMapView

User przetestował przebudowany eksport (z `MKMapSnapshotter.Options.camera`) i przysłał zrzut klatki startowej: zamiast bliskiego widoku Londynu z widoczną krzywizną (jak w referencyjnym filmiku), dostał szeroko oddaloną, płaską mapę całej Europy — mimo identycznej liczbowo wartości `distance`. User: "dlaczego zapis zmienia wygląd?!". To DOWÓD (nie tylko podejrzenie) że `MKMapSnapshotter` — nawet skonfigurowany `MKMapCamera` zamiast `region` — renderuje innym silnikiem niż żywa SwiftUI `Map` i nie potrafi odtworzyć widoku globusa (widoczna krzywizna Ziemi). To dwa różne mechanizmy renderowania, nie dwa sposoby wołania tej samej rzeczy.

**Dyskusja o ryzyku nagrywania żywego widoku** — user trafnie zapytał: skoro przetwarzanie/rekonstruowanie obrazu okazało się bardziej zawodne (kolejne bugi: zły zoom, zły kierunek) niż zwykłe nagranie tego co już jest na ekranie, to dlaczego nagrywanie miałoby być "ryzykowne"? Sprecyzowałem że realne ryzyko to DWIE konkretne rzeczy, nie ogólna "zawodność nagrywania":
1. Mapa renderuje się przez GPU (Metal) — standardowe metody zrzutu widoku czasem nie łapią takiej zawartości poprawnie.
2. Trzeba wiedzieć KIEDY dokładnie widok skończył się ładować po zmianie kamery, żeby nie złapać niedoładowanych kafelków.

User dorzucił kluczowy argument do punktu 2: skoro user OGLĄDAŁ już żywą animację TEJ SAMEJ trasy przed kliknięciem "Zapisz", kafelki MapKit dla tego regionu/zoomu są najpewniej już w pamięci podręcznej (współdzielonej na poziomie procesu) — ryzyko "pustych kafelków" świeżego widoku nie ma tu w pełni zastosowania.

**Przebudowa na żywą `MKMapView`**: `TravelMapVideoRenderer` całkowicie przepisany — zamiast `MKMapSnapshotter`, tworzy prawdziwą `MKMapView` (to samo MapKit co żywy podgląd) w ukrytym, poza-ekranowym oknie (`UIWindow` pozycjonowane daleko poza widocznym obszarem ekranu — NIE `alpha: 0`, bo wtedy GPU mogłoby pominąć renderowanie). Per klatka: ustawia `mapView.camera`, czeka na oficjalny sygnał MapKit `mapViewDidFinishRenderingMap(_:fullyRendered:)` (z timeoutem 2.5s jako zabezpieczenie, przez `MapRenderDelegate` — `@MainActor`, `CheckedContinuation`), potem zgrywa `mapView.drawHierarchy(in:afterScreenUpdates:)`. Etykiety/linia/ikona pojazdu dorysowywane jak wcześniej, ale współrzędne teraz przez `mapView.convert(_:toPointTo:)` zamiast `snapshot.point(for:)`.

**Uczciwe zastrzeżenie — to jest eksperyment, nie pewny fix**: punkt 1 z powyższej dyskusji (Metal/GPU capture) NIE jest w pełni rozwiązany, tylko zaadresowany najlepszą dostępną metodą (`drawHierarchy`) — nie mam pewności że zadziała bez czarnych/pustych fragmentów mapy w klatkach, dopóki user nie przetestuje na realu. To największa architektoniczna zmiana w tej sesji dotycząca eksportu — jeśli nie zadziała, następny krok to sprawdzenie czy `drawHierarchy` faktycznie łapie zawartość Metal, ewentualnie inna metoda przechwytywania.

Build → **BUILD SUCCEEDED** na obu platformach (kompiluje się bez błędów mimo sporego rozmiaru zmiany), zainstalowane na iPhone, Mac zrestartowany.

## Stan na 27.07.2026, ciąg dalszy — BUG: eksport strasznie wolny, w praktyce "nie zapisuje"

User: "dlaczego tak długo schodzi z zapisywaniem? już wiem bo nie zapisuje". User odrzucił propozycję kompromisu (powrót do `MKMapSnapshotter` bez widoku globusa) porównaniem: "oglądasz zwiastun filmu, później idziesz do kina, a tu całkiem inny film" — twarde stanowisko, że ma być 100% identyczne, więc naprawiamy podejście z żywą `MKMapView`, nie wycofujemy się z niego.

**Diagnoza dwóch prawdopodobnych przyczyn**:
1. Ukryte okno było pozycjonowane 200 000 punktów poza ekranem — prawdopodobnie system w ogóle nie renderował w nim zawartości przy tak ekstremalnym przesunięciu, więc `mapViewDidFinishRenderingMap` nigdy się nie wywoływał.
2. Timeout 2.5s per klatka był zbyt ostrożny — przy 60 klatkach/odcinek i braku sygnału "gotowe" każda klatka czekała pełne 2.5s = ponad 2 minuty na sam jeden odcinek.

**Fix**:
- Okno przeniesione na NORMALNE współrzędne ekranu (0,0), ale z bardzo niskim `windowLevel`/`level` (`-10_000`) — sprawdzony wzorzec "niewidoczne, ale realnie renderowane" (zamiast "tak daleko że może w ogóle nie istnieje z punktu widzenia systemu").
- `waitForRender` przemianowane na `settleSeconds` — krótki, stały czas ustalenia (0.3s zamiast 2.5s timeout) — kończy się przy PIERWSZYM z dwóch zdarzeń: sygnale MapKit albo upływie 0.3s. Uzasadnienie: trasa była już wyświetlona na żywo przed kliknięciem "Zapisz", więc kafelki są najpewniej już w pamięci podręcznej — nie trzeba czekać długo "na wszelki wypadek".

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany. Nadal eksperyment — czeka na test czy teraz w ogóle się kończy i czy obraz się pojawia.

## Stan na 27.07.2026, ciąg dalszy — BUG: eksport nadal płaski, bez krzywizny globusa

User przysłał zrzut referencyjnego filmiku (widok globusa z etykietą "LONDON / UNITED KINGDOM") i zapytał wprost: skoro żywy podgląd w apce POKAZUJE kulę (potwierdzone przez usera), a eksport nie — to gdzie jest różnica, skoro obie ścieżki mają teraz tę samą `MKMapCamera` z tym samym `distance`?

**Root cause znaleziony**: żywy podgląd używa `.mapStyle(.hybrid(elevation: .realistic))` — nowszego SwiftUI API, w którym `elevation: .realistic` włącza renderowanie 3D terenu/globusa. Eksportowa `MKMapView` ustawiała tylko starą właściwość `mapType = .hybrid` — bez odpowiednika `elevation: .realistic`. To DWIE różne właściwości: `mapType` wybiera "jaka warstwa" (satelita/standard), ale to `preferredConfiguration` (nowsze UIKit/AppKit API, `MKHybridMapConfiguration(elevationStyle: .realistic)`) odpowiada za "czy w 3D z krzywizną". Sam dystans kamery nic tu nie zmieniał — mapa była zawsze płaska, niezależnie od tego jak daleko cofnięta kamera.

**Fix**: `MapTheme.swift` dostał nową właściwość `mapConfiguration: MKMapConfiguration` — `MKHybridMapConfiguration(elevationStyle: .realistic)` dla satelity, `MKStandardMapConfiguration(elevationStyle: .flat)` dla Minimal White. `TravelMapVideoRenderer` teraz ustawia `mapView.preferredConfiguration = mapTheme.mapConfiguration` zamiast (starej) `mapView.mapType`. To jedyna zmiana — reszta pipeline'u (żywa `MKMapView`, `drawHierarchy`, `settleSeconds: 0.3`, geograficzny namiar) zostaje bez zmian, bo była już dobrze zdiagnozowana.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany. To najbardziej prawdopodobna przyczyna (potwierdzona przez usera że różnica jest DOKŁADNIE w konfiguracji `MKMapView`, nie w czym innym), ale — jak poprzednie poprawki tego pipeline'u — wymaga potwierdzenia na realu.

## Stan na 27.07.2026, ciąg dalszy — POTWIERDZONE: krzywizna globusa naprawiona. Dwa kolejne bugi znalezione i naprawione

User przetestował: klatki (krzywizna globusa) już się zgadzają — `preferredConfiguration` był właściwym fixem. Przy okazji przysłał zrzut z szarymi, niedoładowanymi kafelkami mapy (placeholder MapKit) i zgłosił że "samolot leci bokiem" mimo poprzedniej poprawki namiaru.

**Bug 1 — szare kafelki**: `waitForRender(settleSeconds: 0.3)` z poprzedniej "poprawki na szybkość" w praktyce ZAWSZE wygrywało wyścig z prawdziwym sygnałem `mapViewDidFinishRenderingMap` (bo 0.3s to prawie zawsze mniej niż czas realnego doładowania, zwłaszcza siatki terenu przy `elevation: .realistic`). Efekt: eksport nigdy realnie nie czekał na gotowość mapy, zwłaszcza pierwsza klatka (świeża `MKMapView`, zero kafelków w pamięci). **Fix**: `waitForRender(timeoutSeconds: 3.0)` — to już nie wyścig, tylko prawdziwe czekanie na sygnał z długim zabezpieczeniem na wypadek awarii, nie krótkim timerem który wygrywa "na zasadzie domyślnej".

**Bug 2 — samolot bokiem, tym razem naprawdę**: żywy podgląd stosuje obrót WPROST (`.rotationEffect(.degrees(resolved.rotationDegrees))`), a `composite()` w eksporcie stosował go z ODWRÓCONYM znakiem (`-resolved.rotationDegrees`). To odwrócenie było dostrojone empirycznie do STAREJ metody namiaru (z pikseli ekranu, już porzuconej) — teraz, gdy obie ścieżki liczą namiar identycznym wzorem geograficznym, odwrócenie znaku stało się same w sobie błędem. **Fix**: usunięty minus na iPhone (oba konteksty, SwiftUI i `UIGraphicsImageRenderer`, są Y-down, więc ten sam znak daje ten sam efekt). Na Macu — odwrotnie: dodany minus (surowy `CGContext` jest tam Y-UP, więc żeby dać ten sam wizualny efekt co Y-down SwiftUI, znak trzeba zanegować; nieprzetestowane na Macu w tej sesji, wywiedzione z symetrii konwencji).

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

## Stan na 27.07.2026, ciąg dalszy — drobne cięcie kamery tuż przed lądowaniem

User (po obszernej recenzji porównawczej z filmem referencyjnym — patrz niżej): klatki już dobre, ale zauważył małe, wizualne "cięcie" w kamerze tuż przed lądowaniem.

**Root cause**: żywy podgląd po zakończeniu pętli lotu W OGÓLE nie przestawia kamery — zostaje dokładnie na współrzędnej ostatniej animowanej klatki, dopiero potem pojawia się karta miasta. Eksport robił DODATKOWE, osobne ustawienie kamery na dokładną `toCoordinate` przystanku do klatki przylotu — a `toCoordinate` (punkt w bazie) mogła się nieznacznie różnić od ostatniego punktu wygenerowanej trasy (`path.last`), dając micro-skok kamery dokładnie w momencie "lądowania".

**Fix**: klatka przylotu w eksporcie używa teraz tej samej współrzędnej co ostatnia klatka animacji (`lastAnimatedPoint`), zamiast osobno przeliczanej `toCoordinate` — dokładnie replikuje zachowanie żywego podglądu (zero dodatkowego przestawienia kamery).

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

## Stan na 27.07.2026, ciąg dalszy — duża wizja: "Travel Cinematic Engine"

User przysłał obszerną, zewnętrzną recenzję porównawczą (referencyjny filmik vs nasza animacja) z konkretną propozycją: kamera lecąca za samolotem jak dron (easing, banking, anticipation przed startem, zwolnienie przed lądowaniem), samolot z pitch/roll/cieniem, linia rysująca się za pojazdem, tekst wtopiony w mapę zamiast overlay, płynne przejście mapa→zdjęcie bez cięcia, oraz docelowo łączenie wielu środków transportu w jedną ciągłą, kinową sekwencję (samolot → samochód → szlak pieszy). User explicite: potraktować Travel Map jako jedną z głównych, flagowych funkcji PMemories, budującą rozpoznawalność marki. To NIE zostało jeszcze zaimplementowane — duży, wieloetapowy projekt wymagający osobnego planowania (patrz `Docs/Travel.md`), zgodnie z zasadą "etapami, nie wszystko naraz". Zapisane, user zgodził się to zostawić na później.

## Stan na 27.07.2026, ciąg dalszy — BUG: eksport bez widocznej krzywizny globusa, mimo poprawnej konfiguracji

Po naprawieniu kafelków user przysłał kolejny zrzut klatki startowej — kafelki w 100% załadowane (fix zadziałał), ale sama klatka wygląda jak zwykła, płaska, mocno oddalona mapa satelitarna, BEZ widocznej krzywizny Ziemi i czarnej przestrzeni kosmicznej w tle — nie tak jak w referencyjnym filmiku. Kluczowa poszlaka: user WCZEŚNIEJ w tej sesji potwierdził że żywy podgląd (SwiftUI `Map`) PRZY DOKŁADNIE TYCH SAMYCH parametrach (`pitch: 0`, `globeDistance: 12_000_000`) POKAZUJE kulę poprawnie — więc problem nie może być w samych wartościach kamery, tylko w czymś specyficznym dla `MKMapView`.

**Hipoteza**: `MKMapView` domyślnie ogranicza maksymalny dystans oddalenia kamery (`cameraZoomRange`) — SwiftUI `Map` najpewniej nie ma tego samego domyślnego ograniczenia (albo ma dużo bardziej permisywne). Żądany `globeDistance` (12 000 km) mógł być więc po cichu PRZYCINANY przez `MKMapView` do czegoś dużo mniejszego, mimo że w kodzie ustawialiśmy poprawną wartość — dając płaski, "za blisko" wygenerowany widok bez krzywizny.

**Fix**: jawne, szerokie `mapView.cameraZoomRange = MKMapView.CameraZoomRange(maxCenterCoordinateDistance: 20_000_000)` na eksportowej `MKMapView`, żeby nic po cichu nie przycinało żądanego dystansu. Wartości kamery (`pitch`, `globeDistance`) świadomie NIE zmienione — te są już potwierdzone poprawne przez żywy podgląd.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany. To hipoteza (najbardziej prawdopodobna, uzasadniona logicznie), nie pewność — wymaga potwierdzenia wizualnego przez usera.

## Stan na 27.07.2026, ciąg dalszy — hipoteza z `cameraZoomRange` OBALONA, prawdziwa różnica znaleziona przez bezpośrednie porównanie zrzutów

User przetestował — klatka wygląda DOKŁADNIE tak samo jak przed fixem `cameraZoomRange`. Zero zmiany. Hipoteza o przycinaniu dystansu okazała się błędna (albo bez efektu). Zamiast zgadywać trzeci raz z rzędu, poproszony o zrzut z ŻYWEGO PODGLĄDU w tym samym momencie (start, Gatwick) do bezpośredniego porównania piksel w piksel.

**Prawdziwa różnica znaleziona** (nie krzywizna, jak zakładałem): żywy podgląd pokazuje pełne podpisy Apple Maps — nazwy miast (Stockholm, Rome, Madrid), granice krajów, nazwy mórz ("Norwegian Sea"), etykietę "London Gatwick Airport" wprost na mapie. Eksport pokazuje czystą satelitę BEZ ŻADNYCH podpisów. Przyczyna w kodzie: `mapView.pointOfInterestFilter = .excludingAll` ustawiane bezwarunkowo w eksporcie — a styl satelity w żywym podglądzie (`.hybrid(elevation: .realistic)`) w ogóle NIE filtruje POI. To realna, widoczna w kodzie niezgodność, nie hipoteza.

**Fix**: nowa właściwość `MapTheme.pointOfInterestFilter` (`.includingAll` dla satelity — zgodnie z `mapStyle`, `.excludingAll` dla Minimal White — też zgodnie z `mapStyle`, który tam explicite ustawia `pointsOfInterest: .excludingAll`). Eksport używa teraz `mapView.pointOfInterestFilter = mapTheme.pointOfInterestFilter` zamiast twardo zakodowanego `.excludingAll`.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone (po kilku próbach — telefon zablokowany), Mac zrestartowany. Krzywizna globusa w tej klatce mogła nigdy nie być prawdziwym problemem — obie wersje (żywy podgląd i eksport) przy tym zoomie wyglądają podobnie płasko, to zwykła cecha kamery z tego dystansu, nie bug.

## Stan na 27.07.2026, ciąg dalszy — POTWIERDZONE PRZEZ USERA: eksport Travel Map działa, wideo się zapisuje

User: "travel map export działa jest wideo". Zamyka dzisiejszy, wieloetapowy łańcuch naprawy eksportu (od "samolot leci bokiem" i crashu przy zapisie, przez porzucenie `MKMapSnapshotter`, przejście na żywą `MKMapView`, aż po dzisiejsze dopracowanie: `preferredConfiguration` dla krzywizny, prawdziwe czekanie na render zamiast wyścigu z krótkim timerem, obrót ikony pojazdu bez odwróconego znaku, kamera przylotu bez micro-skoku, filtr POI zgodny z podglądem). `TODO.md` zaktualizowane — pozycja "Przetestować eksport wideo Travel Map end-to-end na realu" oznaczona jako zrobiona.

Zgodnie z ustaloną kolejnością (Etap 1 Fundament i Etap 2 Studio zamknięte poza Crop/Rotate — zaimplementowane 26.07.2026, ale NIGDY niezweryfikowane wzrokowo na realnym eksporcie) — następny krok to weryfikacja Crop/Rotate na realnym eksporcie w Studio, tym samym trybem co dziś (zbuduj → zainstaluj → sprawdź na realu, nie tylko w kodzie).

## Stan na 27.07.2026, ciąg dalszy — BUG: zakładka "Studio" na dolnym pasku była martwym placeholderem

Przy próbie weryfikacji Crop/Rotate okazało się, że Crop/Rotate w ogóle nie da się przetestować przez normalną nawigację — user: "studio pisze mi że wkrótce". Przyczyna: `HomeView.swift` miało `case .studio: PlaceholderTab(title: "Studio", icon: "wand.and.stars")` — stary stub pokazujący "Wkrótce", NIGDY nie podłączony do prawdziwego edytora (`EditView`/`TrimView`), mimo że cała funkcjonalność (Trim/Split/Crop/Rotate/Speed) jest gotowa i była już oznaczona jako "ZAMKNIĘTA" w `TODO.md`. Dla porównania, zakładka "Library" DOSTAŁA analogiczną podmianę wcześniej (26.07.2026) — "Studio" została pominięta, prawdopodobnie przeoczenie przy tamtej pracy.

**Ustalenie z userem**: "Studio" ma otwierać PEŁNY edytor, gdzie user sam wybiera media i sam wszystko ustawia — czyli dokładnie ten sam mechanizm co istniejący przycisk "Create Memory" na Home (ten sam `PhotosPicker` → `loadSelection` → `EditView`), tylko dostępny bezpośrednio z dolnej nawigacji, bez konieczności wracania na Home.

**Fix**: nowy `studioTab` (ikona + tytuł + `PhotosPicker` z tym samym `pickerSelection` co "Create Memory"). `.onChange(of: pickerSelection)` przeniesiony z `dashboardTab` na poziom całego `Group` (żeby działał niezależnie od tego, przez którą zakładkę user wybrał media — wcześniej był podłączony tylko wewnątrz `dashboardTab`, więc picker w nowej zakładce Studio by nie zadziałał bez tej zmiany).

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany. Dopiero teraz Crop/Rotate jest realnie osiągalne do przetestowania przez normalną nawigację (poprzednio user musiał znać istnienie "Create Memory" na Home, bo "Studio" nigdzie nie prowadziło).

## Stan na 27.07.2026, ciąg dalszy — doprecyzowanie roli "Studio" vs "Create Memory"

User doprecyzował podział ról (po tym jak pierwsza wersja fixu — świeży picker w Studio — okazała się niedokładna): **"Create Memory" ma z czasem być coraz bardziej zautomatyzowane** — user wybiera media w kolejności, appka sama buduje pierwszą wersję filmu (to już pokrywa się z zaplanowanym wcześniej "AI Director" w `AI.md` — Etap 3, świadomie nieruszane teraz, bez konkretnej specyfikacji "jak dokładnie"). **"Studio" to miejsce, gdzie user sam grzebie w tym, co zostało zbudowane automatycznie** — nie świeży picker, tylko bezpośrednie otwarcie najnowszego projektu w edytorze.

Zapytany wprost przez `AskUserQuestion` (żeby nie zgadywać trzeci raz z rzędu po nietrafionej hipotezie z `cameraZoomRange`) — user potwierdził: "Ostatni projekt z Create Memory" (Recommended).

**Fix**: `studioTab` przestał zawierać `PhotosPicker` — teraz to tylko stan przejściowy (`ProgressView`) lub pusty stan z zaproszeniem do "Create Memory", gdy nie ma jeszcze żadnego projektu. Prawdziwe otwieranie przez nowy `.onChange(of: selectedTab)` na poziomie `Group`: gdy user przełącza na `.studio` i `savedProjects.first` istnieje, od razu `openProject(project)` — dokładnie ten sam mechanizm co istniejąca karta "Continue Editing" na Home, tylko wyzwalany przez zakładkę zamiast kliknięcia karty.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

## Stan na 27.07.2026, ciąg dalszy — pierwszy prawdziwy test Studio: 3 bugi w `ImageToVideoRenderer`

Pierwszy realny test Crop/Rotate przez nową ścieżkę Studio. User zgłosił jednym zrzutem trzy powiązane problemy: (1) "Eksport nie powiódł się" z `PMemories.ImageToVideoRenderer.RenderError error 0`, (2) w poprzedniej udanej próbie (4K) zdjęcia były "do góry nogami"/"przekręcone na bok", (3) niektóre zdjęcia były źle przycięte/przybliżone tak mocno, że osoby znikały z kadru — user wskazał konkretny plik HEIC z pytaniem "dlaczego jest na boku?".

**Root cause (jeden, dla wszystkich trzech)**: `makePixelBuffer` w `ImageToVideoRenderer.swift` brało `image.cgImage` bezpośrednio — surowe piksele, całkowicie ignorujące `imageOrientation` (metadane EXIF o obrocie, standard w prawie każdym zdjęciu z aparatu; `UIImage` trzyma je jako osobną flagę zamiast fizycznie obracać piksele, dla wydajności). Stąd: zdjęcia pionowe z metadanymi obrotu wychodziły na bok/do góry nogami (bug 1/2). Logika aspect-fill liczyła proporcje z tych samych surowych, nieobróconych wymiarów (`cgImage.width`/`height`) — dla zdjęcia pionowego błędnie rozpoznanego jako poziome przycinała je jak poziome, wycinając ludzi z kadru (bug 3, bezpośrednia konsekwencja buga 1). Dodatkowo `image.cgImage` bywa `nil` dla niektórych zdjęć HEIC/szerokiego gamutu — stąd `RenderError.pixelBufferCreationFailed` (pierwszy przypadek enuma = "error 0" po zbridżowaniu do `NSError`).

**Fix**: nowa `normalizedCGImage(from:)` — jeśli `imageOrientation != .up`, obraz jest przerysowywany przez `UIGraphicsImageRenderer` (`UIImage.draw` honoruje `imageOrientation`, w przeciwieństwie do surowego `.cgImage`), dając świeży `CGImage` z poprawnie "wypieczoną" orientacją, który ZAWSZE istnieje (naprawia też crash). Naprawia wszystkie trzy zgłoszone problemy jedną zmianą, bo bug 2 i 3 były tym samym pierwotnym błędem.

**Mac**: `NSImage` zwykle nie ma tego problemu (ImageIO zazwyczaj wypieka orientację przy dekodowaniu, inny model niż `UIImage`), ale ten sam "`cgImage` może być `nil`" crash jest realny — dodany fallback przez `NSBitmapImageRep(data: tiffRepresentation)` zanim funkcja podda się i zwróci błąd. Nieprzetestowane na Macu w tej sesji.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany. Czeka na retest tego samego zdjęcia/eksportu.

## Stan na 27.07.2026, ciąg dalszy — BUG: klipy wideo "nie wykrywane", pusty kwadrat w timeline

User zgłosił kolejny pusty kwadrat, tym razem dla WIDEO ("video nie są wykrywane"). `TimelineThumbnail` w `EditView.swift` rysuje `Color.secondary.opacity(0.2)` (szary kwadrat) gdy `item.thumbnail == nil` — potwierdzone jako to samo miejsce.

**Pierwsza próba (niewystarczająca)**: `MediaItemLoader.load` też brało `UIImage(data:)` na surowych bajtach — ten sam wzorzec buga co w `ImageToVideoRenderer` (patrz wyżej), tylko w innym pliku odpowiedzialnym za DODAWANIE nowych elementów (świeży picker w Studio, albo przycisk "Media" w trakcie edycji) — `MediaAssetLoader` (używane przy PONOWNYM OTWIERANIU zapisanego projektu) już wcześniej poprawnie używało `PHImageManager`, więc nie miało tego buga. Dodana `videoThumbnail(from:)` przez `AVAssetImageGenerator`. Build, install — user: "dalej pusto".

**Druga, głębsza przyczyna**: user napisał wprost "wideo nie są WYKRYWANE" — nie tylko brak miniaturki, ale możliwe że `isVideo` samo w sobie wychodzi `false`. `let isVideo = pickerItem.supportedContentTypes.contains(.movie)` może być zawodne dla części formatów wideo z Photos (np. niektóre wysokorozdzielczościowe/slow-mo nagrania nie zawsze zgłaszają `.movie` wprost na tej liście) — jeśli `isVideo` wychodzi błędnie `false`, kod nigdy nawet nie PRÓBOWAŁ wczytać pliku jako `MovieFile`, więc cała ścieżka wideo (miniaturka, `videoURL`, trim, render) była łamana u źródła, nie tylko miniaturka.

**Fix**: `isVideo` liczone teraz z PRAWDZIWEJ próby wczytania (`videoURL != nil || supportedContentTypes.contains(.movie)`) — próbujemy realnie załadować `MovieFile` niezależnie od zadeklarowanego typu (poza Live Photo, które mają własną, osobną ścieżkę `pairedVideoURL`); sukces ładowania = dowód że to wideo, silniejszy sygnał niż sama deklaracja typu. To samo w `MediaItemLoader.swift` na obu platformach.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone (tym razem bez blokady telefonu), Mac zrestartowany. To druga, bardziej fundamentalna hipoteza po jednej nietrafionej próbie — user jeszcze nie potwierdził.

## Stan na 27.07.2026, ciąg dalszy — pakiet feedbacku ze Studio: usuwanie napisów, styl napisów, uwagi na przyszłość

User przetestował Captions i zgłosił kilka rzeczy naraz:

**Bug: brak opcji usunięcia napisu**. `CaptionsView` miała `.onDelete` (swipe-to-delete) — technicznie działające, ale wiersz jest cały wypełniony interaktywnymi kontrolkami (TextField, Picker, dwa Slidery), które "zjadają" gest przesunięcia zanim zdąży wywołać usuwanie systemowe — w praktyce nieodkrywalne/niewywoływalne. **Fix**: jawny przycisk kosza (`trash`, `role: .destructive`) obok pola tekstowego w każdym wierszu, zamiast polegać na niepewnym swipe.

**Feature: napisy bez tła + wybór czcionki**. User: "napisy powinny mieć opcję wyboru czcionki i nie być na tle tylko napisane odrazu na filmie". Odpowiedź: sam pomysł "bez tła" ma sens estetycznie, ale czyste zdjęcie tekstu bez ŻADNEGO kontrastu robi się nieczytelne na jasnym/ruchliwym wideo — właściwe podejście (jak TikTok/CapCut) to kontur + cień WOKÓŁ liter zamiast prostokąta ZA nimi. **Fix**: nowy `CaptionFont` (6 skończonych stylów: Klasyczna/Nowoczesna/Elegancka/Filmowa/Zabawna/Retro, konkretne nazwy PostScript systemowych czcionek — `Chalkboard-Bold`/`ChalkboardSE-Bold` różne między Mac/iOS), picker w `CaptionsView`, `Caption.font` + `SavedCaption.fontRawValue` (z domyślną wartością — proste dodanie pola do istniejącego modelu SwiftData). W `VideoComposer.captionsAnimationTool`: `textLayer.backgroundColor` usunięty, zamiast tego `NSAttributedString` z `.strokeWidth: -4` (ujemne = wypełnienie I obrys naraz) + `shadowColor`/`shadowOpacity`/`shadowRadius`/`shadowOffset` na samej warstwie. Przy okazji zbite dwa realne błędy kompilacji: `VideoComposer.swift` nie importował `UIKit` (iPhone) / `AppKit` (Mac), mimo nowego użycia `UIFont`/`UIColor`/`NSFont`/`NSColor` — złapane dopiero na realnym buildzie, nie SourceKit.

**Zgłoszone, ale NIE ruszane teraz (świadomie, zbyt duży zakres na jedną turę)**:
- **Brak podglądu przed zapisem** — user: "muszę czekać na zapisanie żeby wiedzieć czy jest ok". To realna, duża luka UX (dziś jedyny sposób zobaczenia finalnej kompozycji z przejściami/muzyką/napisami to pełny eksport), ale zbudowanie żywego podglądu skomponowanego wideo to osobna, spora funkcja architektoniczna (AVPlayer nad żywą kompozycją, nie tylko statyczna miniaturka aktualnie wybranego klipu) — do zaplanowania osobno, nie doraźna łatka.
- **Eksport długo trwa** — zanotowane, nie zdiagnozowane (brak konkretnego pomiaru/logu na tę chwilę).
- **Przybliżanie/kadrowanie zdjęć nadal słabe, wycina osoby** — to już zdiagnozowany i ŚWIADOMIE odłożony temat Smart Crop (`Studio.md`, wymaga Vision framework do wykrywania twarzy) — user dostał przypomnienie że to już w kolejce, nie nowy bug.
- **Pozytywny feedback (do zapamiętania, NIE zmieniać)**: dopasowanie długości klipu do długości piosenki działa dobrze — user: "to jest duży plus", nie wymaga żadnej zmiany.

Build → **BUILD SUCCEEDED** na obu platformach (po naprawie brakującego importu), zainstalowane na iPhone, Mac zrestartowany.

## Stan na 27.07.2026, ciąg dalszy — Feature: delikatny ducking muzyki w tle pod klipami z dźwiękiem

User zapytał czy muzyka w tle może się delikatnie (nie całkowicie) przyciszać, gdy leci klip wideo z własnym dźwiękiem, zamiast stałej głośności przez cały film.

**Implementacja**: `buildAudioMix` — muzyka ma teraz dynamiczną głośność zamiast jednej stałej wartości. `originalVolumeSegments` (już istniejące, budowane tylko dla realnych klipów wideo/Live Photo z faktyczną ścieżką audio) filtrowane do tych ze słyszalnym dźwiękiem (`volume > 0`), sąsiadujące/nakładające się odcinki SCALONE w jedno okno (żeby dwie kolejne klipy "na styk" nie dały dwóch kolidujących ze sobą komend rampy), potem `setVolumeRamp` w dół (0.3s) przed każdym oknem do `musicVolume * 0.35`, i z powrotem w górę (0.3s) po jego końcu. Zdjęcia (bez audio) nie mają wpływu — muzyka zostaje na pełnej głośności między klipami wideo.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

## Stan na 27.07.2026, ciąg dalszy — Smart Crop: user zmienił zdanie, robimy teraz zamiast odkładać

User przysłał dwa zdjęcia (oryginał: 3 osoby przy stole; klatka z filmu: została widoczna tylko 1 osoba, druga ucięta do połowy, trzecia — user sam — całkowicie zniknęła z kadru) i poprosił o ocenę. Potwierdziłem że to dokładnie zdiagnozowany wcześniej i świadomie odłożony problem Smart Crop, zapytałem czy podnieść priorytet. User najpierw (przez literówkę/autokorektę) napisał coś co brzmiało jak "nie teraz", ale zaraz sprostował: **"nie, naprawiamy bo to duży problem i nie będziemy tego odkładać na później"**.

**Implementacja** (jednak nie w miejscu z pierwotnego planu w `Studio.md`): plan zakładał zmianę `centerTransform` w `VideoComposer.layerTransform`, ale to miejsce dotyczy transformu WIDEO — dla ZDJĘĆ realny crop dzieje się wcześniej, w `ImageToVideoRenderer.makePixelBuffer` (zdjęcie konwertowane do syntetycznego wideo już DOKŁADNIE w rozmiarze kanwy, więc `layerTransform` później nic już nie przycina). Tam dodana nowa `smartCropCenter(in:)` — `VNDetectFaceRectanglesRequest` na już znormalizowanym (poprawiona orientacja) `CGImage`, unia bounding boxów wszystkich wykrytych twarzy, konwersja z przestrzeni Vision (znormalizowana [0,1], origin LEWY DOLNY) do pikseli obrazu (origin LEWY GÓRNY, stąd `1 - unionBox.maxY`). Istniejące dwie gałęzie kadrowania (szerokie zdjęcie → przycina boki, wysokie → przycina góra/dół) dostały nowe obliczenie offsetu: zamiast zawsze `(rozmiar - przeskalowany) / 2` (ślepy środek), offset liczony tak żeby środek unii twarzy wypadł na środku kanwy, przycięty (`min`/`max`) do granic obrazu żeby nie pokazać pustej przestrzeni. Brak wykrytych twarzy → dokładnie stare zachowanie (`blindX`/`blindY` zachowane jako fallback), więc brak regresji dla zdjęć bez ludzi.

**Świadomie NIE dotyka wideo** — tylko zdjęć konwertowanych przez `ImageToVideoRenderer`, zgodnie z pierwotnym zakresem w `Studio.md` (dla wideo pozycja twarzy zmienia się w czasie, osobny, trudniejszy problem).

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany. `Studio.md`/`TODO.md` zaktualizowane — Smart Crop oznaczony jako zrobiony. Czeka na test z tym samym zdjęciem (3 osoby przy stole) żeby potwierdzić że teraz zostają w kadrze.

## Stan na 27.07.2026, ciąg dalszy — Smart Crop: fallback na wykrywanie sylwetek, nie tylko twarzy

User trafnie zapytał: co jeśli osoba jest odwrócona plecami (twarz niewidoczna) — czy nadal ją wytnie? Szczera odpowiedź: tak, przy poprzedniej wersji (tylko `VNDetectFaceRectanglesRequest`) — bez wykrytej twarzy kod wracał do ślepego środka.

**Fix**: `smartCropCenter` teraz dwuwarstwowe — najpierw szuka twarzy (najprecyzyjniejsze), a jeśli nie znajdzie żadnej, próbuje `VNDetectHumanRectanglesRequest` (wykrywa całe sylwetki ludzi, działa niezależnie od tego czy widać twarz — osoba bokiem/plecami też zostanie wykryta). Dopiero brak OBU sygnałów wraca do starego ślepego środka. Wspólna `unionCenter(of:in:)` (przyjmuje `[VNDetectedObjectObservation]` — wspólny nadtyp `VNFaceObservation`/`VNHumanObservation`, oba mają `.boundingBox`) używana dla obu typów wykrycia, żeby nie duplikować logiki konwersji współrzędnych.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

## Stan na 27.07.2026, ciąg dalszy — najpierw przyspieszenie, potem CAŁKOWITA rezygnacja z przycinania zdjęć

Przy okazji pytania o przyspieszenie eksportu (user testował i eksport szedł długo) — dodana `downscaledForDetection` (Vision analizuje mocno pomniejszoną kopię zamiast pełnej rozdzielczości 12+ Mpx; `boundingBox` jest znormalizowany, więc dokładność bez zmian, tylko szybciej).

Zaraz potem user cofnął się o krok dalej: **"wydaje mi się że ogólnie obcinanie zdjęć to nie jest coś dobrego"**. Zgodziłem się i wyjaśniłem czemu — nawet najlepsze Smart Crop tylko ŁAGODZI problem (zgaduje co wyciąć), nie eliminuje go: przy bardzo szerokim zdjęciu z ludźmi rozstawionymi na całej szerokości fizycznie nie da się zmieścić wszystkiego w wąskim kadrze bez utraty krawędzi. Zaproponowałem: zamiast przycinać, pokazuj CAŁE zdjęcie (tryb Fit) z rozmytym, powiększonym tłem z tego samego zdjęcia wypełniającym puste pasy (jak Instagram Stories) zamiast czarnych belek — zero ryzyka wycięcia kogokolwiek. User: "pasuje", a po kolejnym teście (dalej ucinało) potwierdził wprost: "zróbmy zmianę która nie będzie wycinać nic ze zdjęć".

**Implementacja — pełna wymiana podejścia w `ImageToVideoRenderer`**: usunięte `smartCropCenter`/`unionCenter`/Vision (`import Vision` też usunięty, martwy kod). Zamiast tego: `blurredFillImage(from:size:)` — ta sama fotografia pomniejszona (400px, jakość rozmycia nie wymaga więcej), `CIGaussianBlur` (promień 30), przeskalowana aspect-FILL (przycięcie tu OK, to tylko dekoracja) i przycięta do rozmiaru kanwy jako tło. Na wierzchu: CAŁE zdjęcie aspect-FIT (nigdy nie przycięte), wyśrodkowane. Zamiana z dwóch gałęzi "przytnij bok"/"przytnij górę-dół" na dwie gałęzie "dopasuj do szerokości"/"dopasuj do wysokości" — te same warunki (`imageAspect > frameAspect`), odwrócona logika skalowania (dopasowanie zamiast wypełnienia).

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany. `Studio.md`/`TODO.md` będą wymagały aktualizacji przy następnej okazji — Smart Crop, dopiero co oznaczony jako zrobiony, został zastąpiony podejściem "bez przycinania" tego samego dnia.

## Stan na 27.07.2026, ciąg dalszy — dlaczego eksport jest tak wolny: znaleziony i naprawiony realny, samodzielnie wprowadzony bug

User zapytał wprost "dlaczego czas zapisu jest tak długi?" — zamiast dalej odkładać jako "niezdiagnozowane", faktycznie sprawdziłem kod.

**Znaleziona konkretna przyczyna**: nowa `blurredFillImage` (dodana tego samego dnia dla tła Fit) tworzyła `CIContext()` OD NOWA dla KAŻDEGO zdjęcia w projekcie. Tworzenie `CIContext` kompiluje wewnętrzny pipeline GPU/Metal — realnie kosztowna, jednorazowa operacja, którą Apple wprost zaleca robić raz i reużywać, nie tworzyć per-wywołanie. Przy projekcie z wieloma zdjęciami to się sumowało — czysty, samodzielnie wprowadzony regres z dzisiejszej zmiany, nie odziedziczony, stary problem.

**Fix**: `sharedCIContext` — jeden, statyczny, dzielony między wszystkimi zdjęciami w projekcie, tworzony raz.

**Uczciwie o pozostałych, NIE naprawionych dziś czynnikach** (żeby nie sugerować że to jedyna przyczyna): (1) każde zdjęcie przechodzi przez PODWÓJNY przelot — najpierw kodowane do tymczasowego pliku .mov (`ImageToVideoRenderer`), potem TEN plik jest dekodowany ponownie przy wstawianiu do głównej kompozycji (`VideoComposer`) — architektura "wszystko jako klip wideo" ma wbudowany koszt koder→dekoder na każde zdjęcie, nie tylko na filmy; to nie jest szybka łatka, wymagałoby innej architektury renderowania zdjęć bezpośrednio do kompozycji. (2) Jakość eksportu 4K (user wspominał wcześniej testowanie na 4K) z natury trwa dłużej niż 1080p — `AVAssetExportSession` przy wyższej rozdzielczości zawsze wolniejszy.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

## Stan na 27.07.2026, ciąg dalszy — start pracy nad `Database.md`: Statystyki podróży (kraje/miejsca/km/dni)

User: "filmik jest już dużo lepszy, teraz zabieramy się za następne do zrobienia". Sprawdzone `TODO.md`/`Roadmap.md` — Etap 1 Fundament i Etap 2 Studio w pełni zamknięte, cała niezależna od bazy część Travel też. Zaproponowana kolejność: `Database.md` (bo prawie wszystko z pozostałej listy Travel od tego zależy) przed kosmetyką UI Dashboardu — user zaakceptował: "lecimy po kolei co jest do zrobienia".

**Pierwszy konkretny kawałek**: "Statystyki podróży (kraje/miejsca/km/dni)" z `TODO.md`. Fundament (`SavedTrip`/`SavedStop`) już istniał, ale bez dystansu i bez agregacji dni.

**Zmiany**:
- `SavedStop.legDistanceKm: Double = 0` (nowe pole, wartość domyślna dla bezpiecznej migracji SwiftData) — dystans TEGO odcinka od poprzedniego przystanku.
- `persistTrip` w `TravelMapView.swift` zmienione z synchronicznej na `async` — liczy `legDistanceKm` przez `RouteProvider.route(from:to:transport:)` (ten sam wywoływany już przez żywą animację) dla każdej pary kolejnych przystanków PRZED zapisem, więc statystyki czytają gotową wartość zamiast przeliczać za każdym razem.
- `SavedTrip.totalDistanceKm` (suma `legDistanceKm` wszystkich przystanków) i `SavedTrip.dayCount` (liczone z pierwszej i ostatniej `arrivalDate`, `nil` gdy którejkolwiek brakuje — świadomie NIE zgadujemy, `arrivalDate` to opcjonalne, ręcznie wpisywane pole).
- Lista "Twoje podróże" pokazuje teraz `tripSubtitle(for:)` zamiast samej daty: data • km • dni (jeśli znane) • liczba krajów (jeśli >1).

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone (po jednym przejściowym błędzie połączenia — powtórzone), Mac zrestartowany. Czeka na test: nowa podróż powinna teraz pokazać km w liście; dni pokażą się tylko jeśli user wypełni daty przyjazdu.

## Stan na 27.07.2026, ciąg dalszy — BUG: "Twoje podróże" puste mimo udanego zapisu — długi cykl diagnozy

User: "zapisałem przelot z Londynu do Bangkoku i nic się nie zapisało (real się zapisał)" — animacja i eksport wideo działały, ale lista "Twoje podróże" w zakładce Travel pozostawała pusta. Długi cykl wyjaśniania nieporozumień (gdzie dokładnie ma się to pojawić, czy user w ogóle widział animację, pomylone dwa różne nagrania testowe — jedno faktycznie Londyn→Bangkok, drugie Phuket→Doha) zanim doszliśmy do trzonu problemu. Zrzuty ekranu (dosłownie góra zakładki Travel, z widocznym tytułem "Travel Map") POTWIERDZIŁY że sekcja "Twoje podróże" faktycznie nie istnieje — nie pomyłka w miejscu szukania, realny bug.

**Diagnostyka**: zamiast zgadywać dalej, dodany tymczasowy alert w `persistTrip` pokazujący wynik operacji wprost na ekranie (ile przystanków zbudowano, czy `save()` rzucił błąd). User (słusznie) zirytowany intruzywnym popupem zasłaniającym mapę — ale wynik był kluczowy: **"Zapisano: Phuket International Airport → Doha International Airport — 2 przystanków, 0 podróży w bazie"**, `save()` BEZ błędu.

**Interpretacja**: `modelContext.insert()` + `save()` wykonują się poprawnie, bez wyjątku, z poprawnie zbudowanymi przystankami — to NIE dowód że zapis zawiódł. "0 podróży w bazie" to artefakt odczytu `savedTrips.count` (przez `@Query`) ZA WCZEŚNIE — w tej samej synchronicznej klatce co `insert`/`save`, zanim SwiftUI zdążyło odświeżyć zapytanie. Prawdziwy test to czy wpis pojawia się PO powrocie z animacji, nie wewnątrz `persistTrip` samego w sobie.

**Fix**: dodany jawny `try? modelContext.save()` po `insert`/aktualizacji w `persistTrip` (zabezpieczenie na wypadek gdyby autosave SwiftData nie zdążył odłożyć zmian na dysk zanim ekran zostanie zniszczony/odtworzony — np. przy przełączeniu zakładki). Tymczasowy alert diagnostyczny CAŁKOWICIE USUNIĘTY (user: "denerwujące okno... nie powinno mnie informować o czymś co jest oczywiste").

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany. Czeka na finalny test — czy z jawnym `save()` (i bez psującego pomiaru w złym momencie) wpis faktycznie pojawia się na liście po powrocie z animacji.

## Stan na 27/28.07.2026, ciąg dalszy — PRAWDZIWA PRZYCZYNA znaleziona: błąd migracji SwiftData psuł CAŁĄ bazę danych

Kolejny test (Kraków→London Stansted) — dalej pusto, mimo jawnego `save()`. User: "juz to zrobilem nawet zapisalem trase". Sprawdzenie pliku bazy na telefonie (`xcrun devicectl device copy from`) pokazało 2 STARE podróże (sprzed samego początku sesji), bez żadnych zmian nawet PO potwierdzonym, zakończonym teście, bez żadnej reinstalacji z mojej strony w międzyczasie — dowód że coś jest fundamentalnie nie tak, nie kwestia timingu. Kolejna hipoteza (reinstalacje wymazują kontener) też obalona tym samym testem. User trafnie spytał czy celowo kręcę się w kółko przy końcówce limitu — nie, ale przyznane: metoda diagnozy przez pliki wprowadzała w błąd.

**Przełom**: dodany trwały, widoczny licznik `savedTrips.count` w UI (nie alert) — user potwierdził: **0 przed testem, 0 po teście**, na żywym `@Query`, nie przez plik. To wykluczyło ostatecznie "stary plik"/timing jako wyjaśnienie. Sprawdzone: Library/Continue Editing (Studio) TEŻ pokazywały pustkę mimo że działały wcześniej tego dnia — to NIE był bug specyficzny dla Travel Map, tylko coś ogólnego dla całej bazy.

**Prawdziwa diagnoza**: znaleziony `xcrun devicectl device process launch --console` (dotąd nieużywany w tej sesji) — pozwala podpiąć się do żywego stdout/stderr appki. Pierwszy log ujawnił:
```
CoreData: error: reason: Cannot migrate store in-place: Validation error
missing attribute values on mandatory destination attribute
entity=SavedMediaItem, attribute=originalVolume
```
**Cała baza danych nie ładowała się przy KAŻDYM starcie appki** — SwiftData po cichu podstawiał pustą, tymczasową bazę zamiast crashować, więc appka DZIAŁAŁA (Studio, Travel — wszystko), ale WSZYSTKO co user zapisywał znikało przy następnym uruchomieniu. To wyjaśnia KOMPLETNIE cały dzisiejszy dzień diagnozowania — user od rana zapisywał realne dane (projekty Studio, podróże Travel), które faktycznie działały w danej sesji appki, ale nigdy nie przetrwały do następnego uruchomienia (a appka była uruchamiana od nowa przy KAŻDEJ mojej reinstalacji, czyli dziesiątki razy dziennie).

**Przyczyna źródłowa**: `SavedMediaItem.originalVolume` (i, jak się okazało po naprawieniu pierwszego, także `SavedProject.musicVolume`) były zadeklarowane jako `var originalVolume: Double` — BEZ wartości domyślnej PRZY DEKLARACJI POLA (tylko w parametrze `init`, co NIE wystarcza SwiftData do automatycznej migracji lekkiej). SwiftData przy migracji potrzebuje wartości domyślnej wprost na polu, żeby dopisać ją do already-persisted rekordów sprzed dodania tego pola — bez niej migracja całego store'a się wywala.

**Fix — kompleksowy, nie punktowy**: zamiast łatać pole po polu (błąd łapał tylko PIERWSZE brakujące pole na raz, ukrywając kolejne), dodane wartości domyślne PRZY DEKLARACJI do WSZYSTKICH pól nie-opcjonalnych we WSZYSTKICH pięciu modeli (`SavedTrip`, `SavedStop`, `SavedProject`, `SavedMediaItem`, `SavedCaption`) — `ProjectPersistence.swift` i `TripPersistence.swift`, obie platformy. Zweryfikowane przez `--console`: drugi start (po fixie `originalVolume`) ujawnił KOLEJNY brakujący default (`SavedProject.musicVolume`) — potwierdzając że pojedyncze łatanie byłoby kolejnym whack-a-mole; pełna, systematyczna naprawa wszystkich pól na raz usunęła problem raz na zawsze.

**Potwierdzenie**: po pełnym fixie, czysty start appki (przez `--console`) — ZERO błędów CoreData. User natychmiast zobaczył na Home: "Continue Editing — Memory 26 Jul 2026, 67 clips", "Travel Intelligence — 4 Countries • 2 Trips", flagi w Recent Memories — CAŁA stara, "utracona" historia wróciła. Debug licznik w Travel Map: 2 (zgodnie z `@Query`). Kod diagnostyczny (print-y, licznik) usunięty po potwierdzeniu.

**Najważniejsza lekcja z tej sesji**: przy `@Model` w SwiftData KAŻDE nowe, nie-opcjonalne pole dodane do JUŻ ISTNIEJĄCEGO (z rzeczywistymi zapisanymi rekordami) modelu MUSI mieć wartość domyślną bezpośrednio przy deklaracji (`var x: Double = 1.0`), nie tylko w parametrze `init` — inaczej migracja lekka cicho wywala CAŁY store przy starcie, bez crasha, bez widocznego błędu w kodzie aplikacji, tylko z cichym podstawieniem pustej bazy. Przy każdym przyszłym dodawaniu pola do tych pięciu modeli — pamiętać o tym z automatu.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

## Stan na 28.07.2026, ciąg dalszy — dwa mniejsze fixy w Studio: usuwanie klipu + dopasowanie długości do utworu (crossfade)

Po powrocie do weryfikacji Crop/Rotate w Studio, user zgłosił dwie osobne rzeczy przy okazji:

**1. Brak usuwania pojedynczego klipu z timeline** — była tylko zmiana kolejności (drag & drop), żadnej opcji usunięcia. Fix: `.contextMenu` (przytrzymaj → Usuń) na `TimelineThumbnail`, nowa `deleteItem(at:)` — `.onChange(of: items.count)` (już istniejące) samo dociąga `selectedIndex` i przelicza `redistributeDurations()` po usunięciu.

**2. Zdjęcia nie wypełniały całej długości utworu** — user: "cały klip z wakacji ma się mieścić w całym utworze, nie do połowy, nie do 3/4, tylko na cały!". Zdiagnozowane przez te same, potwierdzone dziś realne logi (`--console`): `redistributeDurations()` poprawnie liczyła `perItem` sumujące się do PEŁNEJ długości utworu (67 zdjęć × 2.978s = 199.5s = 3:19), ale finalny wyeksportowany film i tak wychodził krótszy (2:52, ~27s różnicy). Przyczyna: crossfade (`VideoComposer.transitionDuration = 0.4s`) NAKŁADA SIĘ na sąsiednie klipy (nie dodaje czasu) — przy 67 klipach to 66 przejść × 0.4s = 26.4s "zjedzonego" czasu, niemal dokładnie tyle ile brakowało. Potwierdzone dodatkowo przez inny, wcześniejszy (utracony w błędzie migracji) projekt "Lanzarote": 3:46 utwór, 3:26 film = 20s różnicy, spójne z mniejszą liczbą klipów × 0.4s.

**Fix**: `redistributeDurations()` (obie platformy) dolicza rekompensatę `(items.count - 1) × transitionDuration` do docelowej sumy PRZED podzieleniem na `perItem`, żeby po odjęciu nakładania się przejść finalny film i tak trafił w pełną długość utworu. `VideoComposer.transitionDuration` zmienione z `private` na dostępne w module, żeby `EditView` mogło je odczytać.

**Potwierdzone przez usera na nowym projekcie**: "zdjęcia i długość utworu dopasowana idealnie" — działa.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany. Zgłoszone, nie naprawione dziś (świadomie, zbyt późna pora na zgadywanie bez pomiaru): eksport z wieloma zdjęciami trwa zauważalnie długo — do zmierzenia (nie zgadywania) na następnej sesji, per etap (konwersja zdjęć na wideo / crossfade / finalny eksport).

## Stan na 28.07.2026, ciąg dalszy — ostatnie pytanie przed snem: dlaczego jakość zdjęć w eksporcie jest słaba?

User trafnie podejrzewał "drugą generację wideo". Sprawdzone, potwierdzone DWA nakładające się czynniki:
1. **Podwójne kodowanie H.264** — każde zdjęcie przechodzi przez DWA kodowania: raz w `ImageToVideoRenderer` (zdjęcie → krótki klip), drugi raz przy finalnym eksporcie całego projektu. Dwa stratne kodowania z rzędu = klasyczna utrata generacji (jak kopia kopii VHS).
2. **`ImageToVideoRenderer`'s `outputSettings` NIE ustawia bitrate'u w ogóle** (`AVVideoCompressionPropertiesKey` brak) — w przeciwieństwie do np. `TravelMapVideoRenderer`, który ma jawny, wysoki bitrate. System dobiera własny, oszczędny domyślny bitrate, więc PIERWSZE kodowanie już samo w sobie traci jakość, zanim dojdzie do drugiego.

To ten sam "podwójny koder→dekoder" architektoniczny problem co przy temacie szybkości eksportu (zanotowany wcześniej) — teraz mamy dowód że wpływa też na jakość obrazu, nie tylko na czas.

**Do zrobienia następnym razem**:
- Szybka łatka: dodać jawny, wysoki bitrate do `outputSettings` w `ImageToVideoRenderer` (mała zmiana, prawdopodobnie wyraźnie widoczna poprawa).
- Właściwe rozwiązanie: przebudować architekturę tak, żeby zdjęcia nie przechodziły przez pośredni plik wideo w ogóle (rysowane bezpośrednio do kompozycji) — to też rozwiąże temat szybkości eksportu, ten sam korzeń problemu.

**Aktualizacja — jednak naprawione tego samego wieczoru**: user poprosił o od razu, nie na jutro ("naprawiamy to teraz", "jutro mam mieć nowy dzień z czymś innym, nie z nieskończonym zadaniem"). Zaimplementowana szybka łatka: `ImageToVideoRenderer.outputSettings` dostał jawny `AVVideoCompressionPropertiesKey`/`AVVideoAverageBitRateKey`, liczony ze wzoru `width × height × fps × 0.2 bita/piksel/klatkę` (ten sam poziom jakości co już sprawdzony w `TravelMapVideoRenderer` — 12 Mb/s przy 1080×1920@30fps — ale liczony automatycznie z rozmiaru kanwy, więc skaluje się poprawnie dla 720p/1080p/4K zamiast być zaszyty na sztywno dla jednej rozdzielczości). Przy okazji odpowiada na pytanie usera "jak to będzie przy 4K" — bitrate teraz rośnie razem z rozdzielczością (4× piksele = ~4× bitrate), więc 4K nie powinno już wychodzić gorzej niż 1080p. Głębsza, architektoniczna naprawa (zdjęcia bez pośredniego pliku wideo w ogóle) ZOSTAJE odłożona na następną sesję — to już nie szybka łatka, tylko większa przebudowa.

Build → **BUILD SUCCEEDED** na obu platformach, zainstalowane na iPhone, Mac zrestartowany.

**Koniec sesji 28.07.2026 (bardzo długiej, ale z realnym, ważnym rezultatem)**: baza danych naprawiona trwale (błąd migracji SwiftData), Travel Map export potwierdzony działający end-to-end, Smart Crop zbudowany i zastąpiony lepszym podejściem (bez przycinania, rozmyte tło), Studio: usuwanie napisów/klipów, styl napisów, ducking muzyki, dopasowanie długości do utworu, jawny bitrate dla zdjęć (skalowany z rozdzielczością) — wszystko potwierdzone realnymi testami na urządzeniu, nie tylko kodem. Na następną sesję: architektoniczna naprawa podwójnego kodowania zdjęć (szybkość + dalsza jakość), Crop/Rotate w Studio (jeszcze niezweryfikowane na realnym eksporcie).

## 28.07.2026, nowa sesja — wydajność eksportu (na razie tylko diagnoza) + nazwy projektów od lokalizacji

**Wydajność (zgłoszone przez usera na iPhone 16 — "importowanie zdjęć i tworzenie filmiku trwa wieczność", niepokój o starsze telefony):**
Zdiagnozowane kodem (nie zgadywanie) DWA osobne, konkretne wąskie gardła, jeszcze nienaprawione:
1. `VideoComposer.swift:74` — pętla renderująca zdjęcia na osobne pliki `.mov` jest SEKWENCYJNA (`for item in items { await ImageToVideoRenderer.render(...) }`), mimo że renderowania są od siebie niezależne. Łatwy, bezpieczny fix: zrównoleglić przez `TaskGroup`.
2. `TravelMapVideoRenderer.swift` — każda klatka animacji mapy to osobne przesunięcie kamery prawdziwej `MKMapView` + czekanie na `mapViewDidFinishRenderingMap` (limit 3s/klatkę jako zabezpieczenie). Przy trasie z kilkoma odcinkami to 200+ takich przechwyceń z rzędu — jeśli sygnał od MapKit nie przychodzi szybko przy drobnych ruchach kamery, appka realnie czeka blisko pełne 3s na klatkę. Wymaga pomiaru na realu (`--console`) przed poprawką, nie zgadywania.

Zaplanowane: najpierw zrównoleglenie zdjęć (bez ryzyka), potem pomiar mapy na realnym urządzeniu.

**Nazwy projektów od lokalizacji GPS zamiast samej daty** — user: biblioteka pokazuje generyczne "Memory <data>", lepiej zapisać "cel podróży". Zaimplementowane (obie platformy):
- `MediaAssetLoader.firstLocation(forAssetLocalIdentifiers:)` — pierwsza dostępna `PHAsset.location` spośród wybranych zdjęć (zdjęcia z jednego wyboru są zwykle z tego samego miejsca, nie trzeba liczyć "najczęstszej").
- `CityGeocoder.reverseResolve(_:)` — nowa funkcja odwrotnego geokodowania (`CLGeocoder.reverseGeocodeLocation`) obok istniejącego forward-geokodowania używanego przez Travel Map.
- `HomeView.applyLocationBasedTitle(to:)` — wywoływane asynchronicznie PO wejściu do edytora (nie blokuje UI), aktualizuje `project.title` na "Miasto, data" gdy znaleziono lokalizację; bez GPS (screenshoty) zostaje oryginalne "Memory <data>".

Build → **BUILD SUCCEEDED** na obu platformach.

**Backlog (user, na później, nie teraz):** globus pokazujący WSZYSTKIE odwiedzone miejsca / gdzie są wspomnienia — rozszerzenie Travel Map o zbiorczy widok z całej biblioteki projektów, nie tylko pojedynczej trasy. Nie zaimplementowane, tylko zanotowane.

## 28.07.2026, ciąg dalszy — bug: cudza treść w rozmytym tle (screenshot usera)

User przysłał screenshot odtworzonego eksportu — nad i pod zdjęciem plaży widać rozmyte, ale ZUPEŁNIE inne sceny (sufit, blat stołu z telefonem), nie rozmyte wersje tego samego zdjęcia. Zdiagnozowane z rozmiaru screena (1206×2622 = natywny ekran iPhone 16) i matematyki skalowania: zewnętrzne czarne pasy to normalne letterboxowanie odtwarzacza Photos (wideo 1080×1920 nie wypełnia ekranu co do piksela — oczekiwane, nie bug). Ale WEWNĄTRZ samego wideo, w miejscu gdzie miało być nasze rozmyte tło (Fit + blur), pokazywały się fragmenty INNYCH zdjęć.

**Root cause**: `CVPixelBufferCreate` (`ImageToVideoRenderer.makePixelBuffer`) nie gwarantuje wyzerowanej pamięci. Gdy `blurredFillImage()` po cichu zwróci `nil` (np. dla zdjęcia HDR/szerokiego gamutu, gdzie `CIContext` bywa kapryśny), kod w ogóle pomijał rysowanie tła (`if let background = ...`) — więc widać było resztki pamięci bufora po WCZEŚNIEJ renderowanym zdjęciu z tego samego eksportu (system reużywa świeżo zwolnioną pamięć o tym samym rozmiarze).

**Fix (obie platformy)**: jawne wypełnienie czarnym tłem (`context.setFillColor(...); context.fill(...)`) PRZED próbą narysowania rozmytego tła — najgorszy przypadek to teraz zwykły czarny pas, nigdy cudza treść.

Build → **BUILD SUCCEEDED** na obu platformach.

## 28.07.2026, ciąg dalszy — bug: gorsza jakość zdjęć po ponownym otwarciu zapisanego projektu

User: "jak wezmę edytuj [zapisany projekt], zdjęcia nie są już tej samej jakości" — i ujawnił swój dotychczasowy obejście: wybierał te same zdjęcia od nowa za każdym razem zamiast otwierać zapisany projekt, żeby ominąć problem. Uciążliwe, ale trafne intuicyjnie.

**Root cause**: `VideoComposer.resolveSourceURL` używa `item.thumbnail` jako właściwego ŹRÓDŁA obrazu do renderowania klipu (`ImageToVideoRenderer.render(image: thumbnail, ...)`), nie tylko do wyświetlania. Dla NOWEGO projektu `item.thumbnail` to pełna oryginalna rozdzielczość (`MediaItemLoader.load` → `pickerItem.loadTransferable(type: Data.self)` → `UIImage(data:)`, surowe bajty z pickera). Ale dla PONOWNIE OTWARTEGO projektu, `MediaAssetLoader.loadMediaItems` woła `thumbnail(forAssetLocalIdentifier:)` z `targetSize: CGSize(width: 300, height: 300)` — świetne do siatki miniaturek, fatalne jako źródło eksportu: ten sam malutki obrazek trafiał do `ImageToVideoRenderer`, rozciągany do pełnej rozdzielczości kanwy (np. 2160×3840 przy 4K).

**Fix (obie platformy)**: `MediaAssetLoader.thumbnail(forAssetLocalIdentifier:)` — `targetSize` zmienione z `300×300` na `PHImageManagerMaximumSize` (pełna oryginalna rozdzielczość, tak jak przy pierwszym wyborze). `contentMode` jest i tak ignorowane przez `PHImageManager` przy `PHImageManagerMaximumSize` (zawsze zwraca oryginalny kadr bez przycinania) — zgodne z resztą appki.

Build → **BUILD SUCCEEDED** na obu platformach, iPhone zainstalowany świeżo z fixem.

**Do obserwacji**: ta funkcja jest jedynym miejscem które karmi zarówno siatkę JAK I eksport — nazwa `thumbnail` już nie pasuje do roli. Jeśli w przyszłości dojdzie osobny widok siatki dla dużych projektów, warto rozdzielić na dwie funkcje (mała do UI, pełna do eksportu) zamiast trzymać jedną przeciążoną nazwę.

## 28.07.2026, ciąg dalszy — zrównoleglenie renderowania zdjęć (wydajność eksportu)

Pierwszy z dwóch zdiagnozowanych wcześniej wąskich gardeł wydajności — naprawiony. `VideoComposer.buildComposition` renderowało każde zdjęcie na osobny plik `.mov` (`ImageToVideoRenderer`) SEKWENCYJNIE w tej samej pętli co budowanie kompozycji, mimo że renderowania są od siebie niezależne (budowanie kompozycji NIE jest niezależne — kolejny `placementStart` zależy od poprzednich elementów, więc ta część musi zostać sekwencyjna).

**Fix**: nowa `resolveSourceURLs(for:canvasSize:)` — rozwiązuje źródła WSZYSTKICH elementów naraz przez `TaskGroup`, ograniczone do 4 równoległych zadań ("worker pool": startuje 4, po zakończeniu jednego dokłada kolejne) zamiast bez limitu — świadomie ograniczone, żeby nie przeciążyć CPU/pamięci na starszych telefonach (user: obawa o starsze modele). Główna pętla budowania kompozycji zostaje sekwencyjna, ale czyta już gotowe URL-e ze słownika zamiast czekać na każde renderowanie z osobna.

Build → **BUILD SUCCEEDED** na obu platformach, iPhone zainstalowany.

**Pozostaje z listy wydajności**: pomiar (nie zgadywanie) wąskiego gardła Travel Map (`TravelMapVideoRenderer` — 200+ przechwyceń klatek mapy z rzędu, każde czekające do 3s na sygnał MapKit) — do zrobienia następnym razem, wymaga `--console` na realnym urządzeniu.

## 28.07.2026, ciąg dalszy — bug: eksport przerywa się gdy telefon się zablokuje

User: "jeśli telefon wejdzie w stan oczekiwania czyli automatycznie się zablokuje, budowa klipu się przerywa". Root cause: appka nigdy nie wyłączała automatycznego blokowania ekranu (`isIdleTimerDisabled`) ani nie prosiła o czas w tle (`beginBackgroundTask`) na czas eksportu — przy dłuższym renderowaniu (kilka minut przy wielu zdjęciach) ekran gaśnie z bezczynności, telefon się blokuje, iOS usypia appkę w połowie roboty.

**Fix (tylko iPhone — macOS nie ma tego mechanizmu)**:
- `EditView.performExport()` — `UIApplication.shared.isIdleTimerDisabled = true` na czas eksportu (przywracane zawsze, też przy błędzie), plus `beginBackgroundTask`/`endBackgroundTask` jako dodatkowa ochrona na wypadek ręcznego zablokowania przyciskiem bocznym.
- `TravelMapAnimationView.saveVideo()` — ten sam problem dotyczy też eksportu Travel Map (podobnie długi, 200+ klatek) — ta sama blokada `isIdleTimerDisabled`.

Build → **BUILD SUCCEEDED**, iPhone zainstalowany.

## 28.07.2026, ciąg dalszy — pasek postępu przy zapisie wideo mapy + drobny bug rozmiaru

User zgłosił, że przycisk "Zapisz jako wideo" wygląda jakby appka się zawiesiła (statyczny napis "Zapisywanie…" bez żadnej informacji o postępie, przy eksporcie trwającym nawet kilka minut). Zaimplementowany prawdziwy pasek postępu:

- `TravelMapVideoRenderer.renderVideo`/`renderAndSave` — nowy parametr `onProgress: ((Double) -> Void)?`, wywoływany przy każdej zapisanej klatce z realnym ułamkiem postępu (licznik klatek / policzona z góry, dokładna łączna liczba klatek — ta sama logika co pętle generujące klatki, nie oszacowanie).
- `TravelMapAnimationView` — nowy `@State saveProgress`, przycisk przerobiony z systemowego `.borderedProminent` na własny wygląd (`ZStack` z `Capsule` wypełniającą się na biało proporcjonalnie do postępu) — systemowy styl by ukrył nasz pasek pod swoim tłem.

**Bug wprowadzony przy okazji, złapany od razu przez usera (screenshot)**: `Capsule()` bez jawnego rozmiaru rozciągnęła się na niemal cały ekran — po zmianie z `.buttonStyle(.borderedProminent)` (który sam narzucał sensowny rozmiar) na `.buttonStyle(.plain)` nic nie ograniczało już wysokości. Fix: jawne `.frame(height: 52)` na całym `ZStack` przycisku.

Build → **BUILD SUCCEEDED**, iPhone zainstalowany, oczekuje na test.

**Uwaga do przyszłego "Travel Cinematic Engine" (czwartek)**: user słusznie zauważył na realnym screenshocie, że przy dłuższych trasach (2244 km, Londyn→Włochy) etykiety miast nachodzą na siebie, bo dystans kamery jest stały niezależnie od skali trasy — potwierdza to sens zaplanowanej na czwartek pracy nad kamerą skalującą się do trasy. Świadomie NIE naprawiane dziś (user wybrał czekać do czwartku zamiast szybkiej łatki).

## 28.07.2026, ciąg dalszy — mapa: eksport trwał ~20 minut, ograniczenie liczby realnych zdjęć mapy

Realny test przez usera potwierdził najgorszy scenariusz z wcześniejszej diagnozy — jeden eksport Travel Map (trasa z kilkoma odcinkami, prędkość 1.0x) trwał na tyle długo, że user po ~15-20 min i utknięciu na 53% (przez przełączenie się na inną appkę — patrz niżej) zrezygnował: "nie będę czekał 20 min na wygenerowanie jednej mapy".

**Odkryte przy okazji: eksport mapy wymaga pierwszego planu.** Renderowanie żywego `MKMapView` (i `drawHierarchy`) zatrzymuje się kiedy appka schodzi w tło (user przełączył się do innej appki odpisać na wiadomość) — w przeciwieństwie do eksportu zwykłego wideo (Studio), tu `isIdleTimerDisabled`/`beginBackgroundTask` nie pomagają, bo to nie problem systemowego usypiania appki tylko fundamentalne ograniczenie żywego renderowania UI w tle. Nie naprawione (nie da się bez przebudowy silnika renderowania na coś nie-UI-owego, jak snapshot z danych mapy zamiast żywego widoku) — do rozważenia przy okazji Travel Cinematic Engine.

**Fix wykonany od razu (szybka łatka, nie pełny system kamery)**: `TravelMapVideoRenderer` — zamiast robić realne zdjęcie mapy (przesunięcie kamery + czekanie na `mapViewDidFinishRenderingMap`, do 3s w najgorszym razie) dla KAŻDEGO kroku animacji (60 kroków/odcinek przy prędkości 1.0x), robi je teraz co 3. krok (`captureInterval = 3`) — pozostałe klatki używają ostatniego zrobionego zdjęcia jako tła. Kamera fizycznie nie przesuwa się dla pominiętych klatek, więc `mapView.convert(...)` używane do rysowania trasy/ikony pojazdu w `composite()` zostaje spójne z tym tłem (brak rozjazdu). Wizualny efekt: tło mapy "doskakuje" co kilka klatek zamiast płynnie przesuwać się co klatkę, ale ikona pojazdu/linia trasy/dystans nadal aktualizują się co klatkę. Długość i liczba klatek finalnego wideo bez zmian — tylko ~3x mniej kosztownych zdjęć mapy.

Przy okazji naprawione (zgłoszone przez usera na screenshocie z paska postępu, zbudowanego chwilę wcześniej w tej samej sesji):
- Pasek wypełnienia przycisku "nie pokrywał się" z tłem na starcie — osobna `Capsule()` dla paska miała inny promień zaokrąglenia niż tło (promień liczony z WŁASNEJ, wąskiej szerokości). Fix: zwykły kolor zamiast kształtu + `.clipShape(Capsule())` na całości, promień liczony raz z pełnego rozmiaru.
- Przycisk za duży (52pt) — zmniejszony do 46pt.

Build → **BUILD SUCCEEDED**, iPhone zainstalowany. Oczekuje na test — user ma zostać W appce (pierwszy plan) przez cały eksport tym razem.

## 28.07.2026, ciąg dalszy — paski postępu przy wczytywaniu zdjęć i tworzeniu klipu

Po dzisiejszym doświadczeniu z paskiem postępu na ekranie mapy, user poprosił o to samo w dwóch pozostałych miejscach appki, gdzie generyczny `ProgressView()` (bez wartości) dawał zero informacji o tym, ile jeszcze zostało:

- **Wczytywanie zdjęć** — `MediaItemLoader.load` (nowy projekt / dodawanie zdjęć w trakcie edycji) i `MediaAssetLoader.loadMediaItems` (ponowne otwarcie zapisanego projektu) dostały `onProgress: ((Double) -> Void)?`, wywoływane po każdym przetworzonym elemencie (`(index+1)/total`).
- **Tworzenie klipu** — `VideoComposer.buildComposition` (a pod spodem `resolveSourceURLs`, worker pool z dzisiejszej łatki wydajności) raportuje postęp renderowania zdjęć; `VideoExporter.exportAndSaveToPhotos` odpytuje `AVAssetExportSession.progress` w tle co 200ms (brak natywnego callbacku w tym API). `EditView.performExport` łączy oba etapy wagami 0...0.6 (renderowanie zdjęć, zwykle dominujący koszt) i 0.6...1.0 (finalny eksport).
- Nowy, współdzielony widok `ProgressLabel.swift` (karta z paskiem + procentem) — używany w `HomeView`/`EditView` jako overlay podczas ładowania; przycisk "Next" w toolbarze `EditView` pokazuje wprost `%` zamiast spinnera.

Wymagało `xcodegen generate` po dodaniu nowego pliku (`ProgressLabel.swift`) — projekt budowany z `project.yml`, nowe pliki nie pojawiają się w `.xcodeproj` automatycznie.

Build → **BUILD SUCCEEDED**, iPhone zainstalowany.

## 29.07.2026 — ręczna zmiana nazwy projektu w Library

User trafnie zauważył lukę w dzisiejszej auto-nazwie z GPS: sporo zdjęć nie ma lokalizacji zrobienia (wyłączona usługa lokalizacji), a przy przesyłaniu zdjęć między telefonami w innym czasie/miejscu metadane GPS bywają niepewne lub ich brak. Fix: `LibraryView` — `.contextMenu`/`.swipeActions` (iPhone) i `.contextMenu` (Mac, bez swipe — zgodnie z ustalonym wzorcem z `TravelMapView`) z "Zmień nazwę", `.alert` z `TextField` do wpisania nowej nazwy, zapis przez `modelContext.save()`.

Build → **BUILD SUCCEEDED** na obu platformach, iPhone zainstalowany.

**User feedback (ważne do zapamiętania)**: paski postępu (dzisiejszy dodatek) bardzo pomogły — "mogę cierpliwie czekać" — potwierdzenie że kierunek (realny % zamiast generycznego spinnera) był słuszny, warto stosować to konsekwentnie przy każdej dłuższej operacji w przyszłości.

## 29.07.2026, ciąg dalszy — bug wprowadzony przy okazji: zniknęło usuwanie w Library

User: "ok a jak usunąć?" — po dodaniu "Zmień nazwę" do `.swipeActions(edge: .trailing)`, domyślne przesunięcie-do-usunięcia z `.onDelete` PRZESTAŁO się pojawiać (SwiftUI: własne `swipeActions` na danej krawędzi całkowicie zastępuje automatyczną akcję z `onDelete`, nie dokłada się do niej). Fix: jawny przycisk "Usuń" (`role: .destructive`) dopisany obok "Zmień nazwę" zarówno w `.swipeActions`, jak i w `.contextMenu` (na iPhone i Mac — Mac nie miał tego buga, bo nie używa swipeActions, ale też nie miał usuwania w menu, więc dodane tam też dla spójności).

Build → **BUILD SUCCEEDED** na obu platformach, iPhone zainstalowany.

## 29.07.2026, ciąg dalszy — skrót do gotowego filmiku w Library (bez szukania w Zdjęciach)

User: Library pokazuje tylko projekty (źródło), gotowy wyeksportowany film ląduje wyłącznie w systemowej appce Zdjęcia — appka nie ma żadnego skrótu do niego. Doprecyzowane: user NIE chce duplikować pliku w appce (i tak żyje w bibliotece Photos), tylko szybki dostęp/odtworzenie z poziomu PMemories.

**Zaimplementowane**:
- `SavedProject.exportedAssetIdentifier: String?` — nowe pole (opcjonalne, więc bez ryzyka błędu migracji jak 28.07 — optional nie wymaga jawnej wartości domyślnej, patrz już istniejące `musicPersistentID`), zapamiętuje `PHAsset.localIdentifier` ostatniego eksportu.
- `VideoExporter.exportAndSaveToPhotos` zwraca teraz ten identyfikator (`request?.placeholderForCreatedAsset?.localIdentifier` przechwycone wewnątrz `PHPhotoLibrary.performChanges`).
- `EditView.performExport` zapisuje go na projekcie po udanym eksporcie.
- `LibraryView` — wiersz przebudowany z pojedynczego dużego `Button` na `HStack` z DWOMA osobnymi przyciskami (otwórz projekt / odtwórz gotowe wideo) — zagnieżdżony przycisk wewnątrz `Button`'a nie dostałby własnego tapu w SwiftUI. Ikona odtwarzania pojawia się tylko gdy projekt ma zapisany `exportedAssetIdentifier`; tap pobiera plik przez istniejące `MediaAssetLoader.videoURL(forAssetLocalIdentifier:)` i pokazuje go w `AVKit.VideoPlayer` w sheet.

**Świadomie NIE zmienione**: "Usuń" nadal kasuje tylko wpis projektu w PMemories — film zostaje bezpiecznie w bibliotece Zdjęć (user potwierdził że o to chodziło, nie o usuwanie z całej biblioteki).

Build → **BUILD SUCCEEDED** na obu platformach, iPhone zainstalowany.

## 29.07.2026, ciąg dalszy — kolejność akcji + ręczne łączenie ze starymi eksportami

Dwie drobne poprawki od usera po teście:
1. **Kolejność** — user chciał "Zmień nazwę" jako pierwsze, "Usuń" jako drugie. `.swipeActions` na iPhone miało odwrotną kolejność niż `.contextMenu` — ujednolicone.
2. **"Nie widzę gotowości do odtwarzania"** — bo `exportedAssetIdentifier` to nowe pole, appka nigdy wcześniej nie zapisywała powiązania projekt→film, więc nie da się tego odtworzyć wstecz automatycznie. User: "nie chce mi się znowu 3 filmów tworzyć" — słusznie, więc zamiast zmuszać do ponownego eksportu, dodana opcja **"Połącz z gotowym wideo"** (`.contextMenu`, tylko gdy `exportedAssetIdentifier == nil`) — otwiera `PhotosPicker` (filtr `.videos`), user JEDNORAZOWO wskazuje który film w bibliotece to ten gotowy, `itemIdentifier` zapisuje się na projekcie. Dużo mniej roboty niż ponowne tworzenie klipu.

Build → **BUILD SUCCEEDED** na obu platformach, iPhone zainstalowany.

## 29.07.2026, ciąg dalszy — odtwarzanie z Library dalej nie działa (nieznaleziony na razie)

User: po połączeniu starego projektu z gotowym wideo przez picker, przycisk odtwarzania dalej nie odtwarza. Świadomie NIE dochodzone dziś dalej (user: "nie będziemy się teraz z tym bawić") — zostaje jako otwarty temat na następną sesję. Prawdopodobne miejsca do sprawdzenia następnym razem: czy `MediaAssetLoader.videoURL(forAssetLocalIdentifier:)` faktycznie zwraca poprawny URL dla identyfikatora zapisanego przez `PhotosPicker.itemIdentifier` (może inny format/scope niż identyfikator z `PHAssetChangeRequest.placeholderForCreatedAsset`), oraz czy `VideoPlayer`/`AVPlayer` w ogóle dostaje plik (błąd cichy, `try?` connuje błąd bez logowania w `play()`).

## 29.07.2026, ciąg dalszy — odsłonięty prawdziwy błąd zamiast cichego `try?`

Przed pracą usera: dokończenie wątku "dalej nie mogę odtworzyć" z poprzedniej sesji. Root cause samego BRAKU informacji: `play()` używało `try?`, więc jakikolwiek błąd (`assetNotFound`, `videoResourceNotFound`, błąd `PHAssetResourceManager.writeData`) znikał bez śladu — user widział że nic się nie dzieje, ale appka też nie wiedziała dlaczego.

**Fix**: `try?` zamienione na `do/catch` z `.alert` pokazującym realny komunikat błędu + identyfikator, którego dotyczy. Kolejny test od usera powinien pokazać PRAWDZIWĄ przyczynę zamiast zgadywania — dopiero wtedy będzie wiadomo co dokładnie naprawić (np. czy `itemIdentifier` z `PhotosPicker` faktycznie nie pasuje do `PHAsset.fetchAssets`, czy zasób wideo nie jest znajdowany, czy coś innego).

Build → **BUILD SUCCEEDED** na obu platformach, iPhone zainstalowany. Czeka na jeden test usera (tap na odtwarzanie) żeby zobaczyć treść błędu.

## 29.07.2026, ciąg dalszy — ProRes jako pośredni kodek zdjęć (eliminacja podwójnej kompresji)

Kontynuacja tematu "podwójne kodowanie" zdiagnozowanego 28.07 (jakość + szybkość). Świadomie NIE wybrany pełny przebudowany pipeline (custom `AVVideoCompositing`, żeby zdjęcia w ogóle nie przechodziły przez plik pośredni) — zbyt ryzykowna, duża zmiana rdzenia kompozycji żeby robić ją solo, bez usera do testowania na bieżąco. Zamiast tego mniejszy, bezpieczniejszy krok o tym samym praktycznym efekcie:

`ImageToVideoRenderer` — kodek pliku pośredniego zmieniony z H.264 (stratny, dodatkowy jawny bitrate z wczorajszego fixu) na **ProRes 422 HQ** (praktycznie bezstratny). Plik pośredni i tak jest tymczasowy i usuwany zaraz po zbudowaniu kompozycji — rozmiar bez znaczenia. Efekt: zamiast DWÓCH kolejnych stratnych kompresji H.264 ("kopia kopii"), liczy się praktycznie tylko JEDNA — finalny eksport (`AVAssetExportSession`, H.264/HEVC). `AVVideoCompressionPropertiesKey`/bitrate usunięte z tego miejsca — ProRes nie działa na docelowym bitrate jak H.264.

Build → **BUILD SUCCEEDED** na obu platformach, iPhone zainstalowany.

**Nadal otwarte na przyszłość**: pełna eliminacja pliku pośredniego (custom `AVVideoCompositing`, zero dodatkowego kodowania w ogóle) — większy, osobno planowany projekt, nie ruszany dziś.

## 29.07.2026, ciąg dalszy — dodany środek transportu "Wędrówka" (hiking)

Pierwszy krok z dawno zaplanowanego backlogu (`Travel.md`, 26.07.2026 — Waymarked Trails już wtedy zweryfikowane jako darmowe API). Zakres dziś: podstawowy tryb transportu, nie pełna integracja z bazą nazwanych szlaków.

**Zaimplementowane**:
- `TransportMode.hiking` — nowy case (emoji 🥾, etykieta "Wędrówka"). Automatycznie pojawia się w pickerze (`ForEach(TransportMode.allCases)`).
- `RouteProvider` — trasowanie przez `MKDirections(.walking)` (realne ścieżki/drogi piesze, ta sama technika co samochód/pociąg) — **zero GPS-a usera, appka tylko pyta o trasę między dwoma punktami**. Styl linii: kropkowana (konwencja z map turystycznych).
- Ikona na mapie (żywy podgląd + eksport wideo) — **emoji zamiast pseudo-3D grafiki** (user: tymczasowe rozwiązanie), rysowane bez rotacji (figurka nie ma sensownego "kierunku" jak pojazd). `VehicleIconSet` całkowicie pomijane dla tego trybu (dodany tylko case zaślepka w `topBaseAngle` dla wyczerpującego switcha).

Build → **BUILD SUCCEEDED** na obu platformach, iPhone zainstalowany.

**Świadomie NIE zaimplementowane dziś (zapisane w `Travel.md` jako kolejne kroki)**:
- Pełna integracja z Waymarked Trails (przeglądanie/dopasowanie NAZWANYCH szlaków, nie tylko trasowanie punkt-punkt).
- Statystyki wysokości (przewyższenie, najwyższy osiągnięty punkt) — user: "pasuje pokrycie na całym świecie łącznie z wysokościami". Wymaga danych elewacji (GPX/API elewacji), osobny temat.
- **Automatyczne wykrywanie szczytu przez GPS** (user: "wejdę na szczyt, włączę appkę, appka sama wyłapie gdzie jestem i zapisze") — wymaga bazy szczytów (np. `natural=peak` z OSM/Overpass) + dopasowania najbliższego punktu do lokalizacji GPS. Osobna, większa funkcja.

## 30.07.2026 — bug: appka zamyka się przy przełączaniu zakładek (prawdopodobny OOM)

User: "są momenty że przełączając się po menu apka się zamyka" — zdarzyło się 2x, w tym raz podczas pokazywania appki znajomemu. Sporadyczne, nie do wymuszenia na żądanie (próba złapania przez `--console` nie złapała live'a).

**Root cause znaleziony przez przegląd kodu (nie zgadywanie na czuja, konkretny mechanizm)**: `HomeView.swift` — `.onChange(of: selectedTab)` bez żadnego warunku wołało `openProject(savedProjects.first)` przy KAŻDYM przełączeniu na zakładkę Studio, nawet gdy ten sam projekt był już otwarty. `openProject` → `MediaAssetLoader.loadMediaItems` — od wczorajszego fixu jakości (29.07, `PHImageManagerMaximumSize`) to ładuje WSZYSTKIE zdjęcia projektu w PEŁNEJ rozdzielczości, nie małe miniaturki jak wcześniej. Przy projekcie z kilkudziesięcioma zdjęciami, każde przełączenie na Studio = potencjalnie kilka GB pamięci ładowane od nowa. To pasuje idealnie do objawu: system ubija appkę bez żadnego komunikatu (OOM/Jetsam kill) — wygląda jak "appka się zamyka" znikąd.

**Fix**: dodany warunek `editingProject?.id != project.id` — auto-otwarcie ostatniego projektu przy wejściu w Studio dzieje się teraz tylko RAZ (albo gdy zmienił się najnowszy projekt), nie przy każdym powrocie na tę zakładkę.

Build → **BUILD SUCCEEDED** na obu platformach, iPhone zainstalowany. User potwierdził że to pasuje do sytuacji ("mogło tak to właśnie być") — do obserwacji, czy problem faktycznie ustąpi (nie było możliwości złapania live crash logu, więc to najlepsza hipoteza poparta konkretnym mechanizmem w kodzie, nie 100%-owo potwierdzona).

## 30.07.2026 — Travel Cinematic Engine Phase 1 + hiking, dodatkowe drobne fixy

Przed pracą usera (dzień wolny): dodany transport "Wędrówka" (opisane wyżej, 29.07 wpis) plus drobne fixy — `LibraryView.play()` z `try?` na `do/catch` + `.alert` (ta sama poprawka co już zrobiona gdzie indziej, teraz konsekwentnie), `ImageToVideoRenderer` kodek pośredni ProRes422HQ zamiast H.264.

### Travel Cinematic Engine — Phase 1

Zaimplementowany cały plan z zatwierdzonego dokumentu planu (`TravelCinematics.swift`, nowy plik): adaptacyjny dystans/pochylenie kamery zależne od długości odcinka (tabela kotwic w przestrzeni `log10(km)`, zamiast stałego `globeDistance = 12_000_000` dla każdej trasy), pierwszy easing w kodzie (`easeInOutCubic`), asymetryczna obwiednia dystansu (szerzej na starcie odcinka, węziej na końcu), i przybliżone "banking" na zakrętach — przechył doklejany do ROTACJI IKONY (`rawLeanDegrees`/`smoothedLean`), nigdy do namiaru zasilającego wybór assetu left/right/top (`VehicleIconSet.resolve`).

**Trzy realne bugi znalezione i naprawione po pierwszym teście na telefonie** — wszystkie ukryte wcześniej przez stary, stały daleki dystans kamery, ujawnione dopiero przez nowy bliski zoom:
1. **"Auto jeździ tyłem"** — `VehicleIconSet.topBaseAngle(for: .car)` było `180` od samego początku tej funkcji (błędne założenie). Bezpośrednie obejrzenie assetu (`sips -Z`, powiększony PNG) pokazało czerwone tylne światła na DOLE kadru — przód jest u góry jak reszta pojazdów. Naprawione na `0`.
2. **"Auto/pociąg strasznie się trzęsie"** — dwie osobne, niezależne przyczyny: surowa nierówność polilinii z `MKDirections` (fix: `RouteProvider.smoothedPath`, uśrednianie ruchome) ORAZ zbyt rzadkie punkty realnej trasy względem liczby kroków animacji, dające "stój i skocz" (fix: `RouteProvider.resamplePath`, dociąganie do stałej liczby punktów przez interpolację liniową) — user zgłosił drugi problem PO naprawie pierwszego ("pociąg też się trzęsie"), więc to naprawdę dwa osobne mechanizmy, nie jeden.
3. **Niebieska kropka etykiety miasta nie pokrywała się z realnym miejscem zatrzymania** — wcześniej rysowana WEWNĄTRZ karty (przesunięta o padding), naprawione: osobny element wyśrodkowany dokładnie na współrzędnej.

User po trzecim teście: "jak tak będzie nagrane jak widać na tym filmiku to będzie kozak (...) wszystko ok podoba mi się" — żywy podgląd zatwierdzony.

### WYSIWYG — ujednolicenie podglądu i eksportu w jeden silnik

Po zatwierdzeniu podglądu, eksport wideo pokazywał WIDOCZNIE inny wynik ("dlaczego mamy inne ikony pojazdów" — user przysłał eksportowany plik). Przyczyna: żywy podgląd (SwiftUI `Map`) i eksport (surowy `MKMapView`) to były dwie osobne implementacje tej samej sceny — znalezione TRZY niezależne rozjazdy (kierunek obrotu ikony, brakujące zaokrąglone zakończenia linii, dystans kamery).

User przysłał zewnętrzną poradę architektoniczną (WYSIWYG — jeden silnik dla obu) i zapytał czy da się tak zrobić. Po chwili wahania z mojej strony (zaproponowałem odłożenie) user wprost skorygował: "dlaczego chcesz odwlekać coś nad czym pracujemy?" — słusznie: to nie osobny temat, tylko dokończenie tego samego feature'u, i realnie rozwiązuje problem u źródła.

**Zrobione**: `TravelMapVideoRenderer.renderFrames` — jedna funkcja ustawiająca kamerę realnego `MKMapView`, czekająca na `mapViewDidFinishRenderingMap`, komponująca klatkę (`composite()`). Eksport (`renderVideo`) i podgląd (`TravelMapAnimationView`) wołają dosłownie tę samą funkcję — różni je tylko co się dzieje z gotową klatką (zapis do `AVAssetWriter` vs. wyświetlenie w `Image(uiImage:)`). Podgląd stracił przy tym całą swoją SwiftUI-ową warstwę (`Map`, `Annotation`, `GlobeCityDot`/`GlobeCityCard`, `DistanceBadge`) — teraz to po prostu wyświetlacz gotowych, skomponowanych obrazów.

**Kompromis i seria poprawek tego samego wieczoru** — SwiftUI animował kamerę płynnie za darmo; surowy `MKMapView` w tym podejściu wymaga realnego, dyskretnego "zdjęcia" na krok, więc podgląd stracił płynność ("przeskakuje", "nie da się oglądać"). Kolejne iteracje, każda zweryfikowana na realnym urządzeniu:
- **Bufor klatek** (`FrameBuffer`, actor, producent/konsument z ograniczoną pojemnością 12) — oddziela nierówne tempo produkcji (realne oczekiwanie na MapKit) od stałego tempa wyświetlania.
- **`captureInterval: 1`** dla podglądu (odświeżanie kamery co krok zamiast co 3.) — przy `captureInterval: 3` kamera w tle stała przez 2 klatki i skakała na 3., widoczne jako "obraz przesuwa się co 45km" na krótkich, bliskich-zoom odcinkach. Pierwsza próba przy PEŁNEJ rozdzielczości ubiła wydajność (potrojona liczba drogich przechwyceń, user: "samolot nie przeleciał jednego odcinka") — cofnięta.
- **Mniejszy rozmiar przechwytywania w podglądzie** (360×640 zamiast 1080×1920, eksport bez zmian) — 9x mniej kosztu MapKit na klatkę, dzięki czemu `captureInterval: 1` stał się jednak opłacalny.
- **Skalowanie proporcji rysowanych elementów** (`scale = size.width / 1080` w `composite()`/`drawDistanceBadge`/`drawGlobeCityLabel`/`drawCard`) — bez tego czcionki/odznaki/karty narysowane w stałych punktach na mniejszym płótnie wychodziły nieproporcjonalnie duże po rozciągnięciu na pełny ekran (user: "wszystko bardzo duże").
- **`stepsPerLeg: 120`** (2x domyślnych 60 z proporcjonalnie krótszym opóźnieniem na krok, żeby całkowity czas odcinka się nie zmienił) — drobniejsze "cięcia" (~7 km zamiast ~15 km).

**Stan na koniec dnia**: podgląd wyraźnie płynniejszy niż na starcie wieczoru, ale wciąż widocznie kanciasty — świadomie zaakceptowane jako wystarczająco dobre na V1 (nie ciągnąć optymalizacji dalej dziś, malejące zyski). Pełny opis kompromisu + zaplanowane V2 ("Travel Cinematics V2" — żywy, animowany `MKMapView` z prawdziwymi `MKOverlay`/`MKAnnotation` zamiast ręcznego kompozytowania, plus pomysły z zewnętrznej analizy referencyjnego filmu: offset framing, look-ahead kamery, style kamery jako presety) zapisany w `Docs/Travel.md` z mierzalnymi kryteriami sukcesu.

**Diagnostyka na żywo tej nocy nie zadziałała jak zwykle** — `xcrun devicectl device process launch --console` ani razu nie pokazał żadnego `print()` z aplikacji (w tym tymczasowego logu porównującego żądany/faktyczny dystans kamery, dodanego na powrót do `captureBaseImage`) — wszystkie diagnozy dziś oparte o realne testy na telefonie (screen recordingi, `ffmpeg` do wyciągania klatek, matematyka na współrzędnych miast), nie o logi konsoli. Warto sprawdzić przy następnej okazji dlaczego `--console` nie łapie stdout tej aplikacji.

**Pozostałe zadania na jutro**: port wszystkich dzisiejszych zmian (`TravelCinematics.swift`, `RouteProvider.swift`, `VehicleIconSet.swift`, `TravelMapAnimationView.swift`, `TravelMapVideoRenderer.swift`) do wersji Mac — nic z tego nie zostało jeszcze przeniesione. Weryfikacja eksportu wideo po wszystkich dzisiejszych zmianach w podglądzie (parametry eksportu nie zmienione, ryzyko regresji niskie, ale nie potwierdzone na realu tej nocy).

## 30.07.2026, ciąg dalszy — weryfikacja eksportu + dwa realne bugi + port na Mac

Kontynuacja z rana: pierwszy test eksportu wideo po wczorajszej unifikacji WYSIWYG (poprzedni wieczór zabrakło na to czasu). Trasa testowa: Gatwick→Milan→Pontevico→Bellagio→Zurich→Gatwick (pętla).

**Eksport sam w sobie działa poprawnie** — bliski zoom na krótkich odcinkach potwierdzony na realnym pliku (wcześniejsza obawa o "camera clamp" z MKMapView okazała się nietrafiona po unifikacji), karty przylotu/odlotu, etykiety, trasa — wszystko zgodne z oczekiwaniami.

**Bug 1 — ikony pojazdów w eksporcie wyglądały blokowo/kanciasto** ("jak kwadrat", user). Root cause znaleziony przez porównanie klatki eksportu ze źródłowym assetem: `car_top.png` ma tylko 98×166 pikseli, a `composite()` (surowy `CGContext`, bez jawnej jakości interpolacji) skaluje go w dół bez wygładzania — SwiftUI `Image(...).resizable()` w starym podglądzie robił to za darmo dobrze, `CGContext` domyślnie nie. **Fix**: `ctx.cgContext.interpolationQuality = .high` ustawione raz na cały kontekst klatki w `composite()`.

**Bug 2 — zapis do biblioteki czasem kończy się błędem `PHPhotosErrorDomain error 3301`** (`operationInterrupted`) — potwierdzony, udokumentowany hiccup systemowego frameworka Zdjęć (występuje też w innych appkach, np. Halide), poza kontrolą kodu appki. User: appka na rynku "musi być prawie idealna" — słusznie, więc mimo że SAMEGO zdarzenia nie da się w 100% wyeliminować, REAKCJA appki na nie już tak. **Fix**: `TravelMapVideoRenderer.saveToLibrary` — automatyczne ponowienie SAMEGO zapisu (do 3 prób, plik wideo już wyrenderowany na dysku, nie trzeba renderować od nowa) z krótkim opóźnieniem między próbami; jeśli wszystkie 3 zawiodą, alert dostał dodatkowy przycisk "Spróbuj ponownie" obok "OK".

**Dyskusja o "sklejonych odcinkach"** — user zauważył że film z wieloma środkami transportu wygląda jak 4 osobne klipy, nie jedna ciągła podróż (każdy odcinek kończy się zatrzymaniem na karcie i zaczyna od nowa własnym "ustawiającym" ujęciem). Ustalone: to NIE nowy bug — tak ta funkcja wygląda od samego początku, po prostu bardziej widoczne teraz. Zebrane razem z "kanciastą kamerą" (obie dotyczą zachowania kamery) w jedno przyszłe zadanie **"Travel Cinematics V2"** w `Docs/Travel.md`, świadomie NIE robione teraz — user zgodził się skupić na dokończeniu prostszych, mechanicznych rzeczy (port na Mac) zamiast dalszego dłubania przy czymś co i tak przebudujemy.

**Port na Mac** — całość dzisiejszego/wczorajszego wątku (Phase 1 + WYSIWYG + oba powyższe bugi) przeniesiona do `/Users/admin/Desktop/PMemories Mac/PMemoriesApp/`, zaadaptowana do AppKit/CoreText. Pełny opis w HISTORIA tamtego projektu. Build → **BUILD SUCCEEDED**, aplikacja uruchomiona lokalnie żeby potwierdzić start — user świadomie odkłada testowanie Travel Map na Macu na później, priorytet to iPhone.

Build (iPhone) → **BUILD SUCCEEDED**, zainstalowane i przetestowane na urządzeniu.

## 30.07.2026, ciąg dalszy — bug: odtwarzanie w Library dalej nie działało (ZNALEZIONE, cztery osobne przyczyny)

Kontynuacja otwartego od 29.07 wątku ("dalej nie mogę odtworzyć"). Tym razem zdiagnozowane do końca, każda przyczyna potwierdzona realnym dowodem (crash log, alert na urządzeniu), nie zgadywaniem.

**1. Jetsam kill (`per-process-limit`) po szybkim, wielokrotnym tapnięciu "play".** User połączył 3 projekty z gotowymi wideo pod rząd, potem appka "wyleciała" w trakcie ładowania. Crash log ściągnięty bezpośrednio z telefonu (`xcrun devicectl device copy from --domain-type systemCrashLogs`, plik `JetsamEvent-*.ips`) potwierdził: PMemories był największym procesem w systemie, zabity za przekroczenie limitu pamięci procesu. Przycisk odtwarzania (`isLoadingPlayback`, wspólne dla całej listy) nie blokował się podczas ładowania — kilka równoległych `PHAssetResourceManager.writeData` dla dużych plików wideo (zwłaszcza gdy trzeba je dociągnąć z iCloud) mogło wystarczająco podbić pamięć. **Fix**: `.disabled(isLoadingPlayback)` na przycisku play.

**2. "Połącz z gotowym wideo" nic nie robiło.** Root cause: `PhotosPickerItem.itemIdentifier` w SwiftUI jest `nil`, jeśli `.photosPicker` nie dostanie jawnie `photoLibrary: .shared()` — udokumentowane zachowanie API (potwierdzone WebSearch), niezależne od nadanych appce uprawnień. Nasz kod tego parametru nie miał, więc identyfikator ZAWSZE wychodził `nil`, a `guard let newValue, let linkingProject` po cichu przerywał funkcję. Dodatkowo osobny, potencjalny wyścig: `linkingProject` było czyszczone przez TEN SAM binding co zamknięcie sheeta (`isPresented: linkingProject != nil`), więc mogło zostać wyzerowane zanim `.onChange(of: linkSelection)` zdążył je użyć. **Fix**: `photoLibrary: .shared()` dodane (też w `EditView.swift` — ten sam brakujący parametr przy DODAWANIU zdjęć w trakcie edycji, osobny, mniejszy bug znaleziony przy okazji, mógłby psuć wznawianie projektu dla zdjęć dodanych po fakcie). `isLinkPickerPresented` jako osobny, dedykowany `@State` niezależny od `linkingProject` — `linkingProject` czyszczone WYŁĄCZNIE wewnątrz `onChange`, nigdy przez zamknięcie sheeta. Dołożony jawny alert z wynikiem (sukces / konkretny powód niepowodzenia) zamiast ciszy.

**3. Wideo nie odtwarzało się automatycznie, bez dźwięku.** `AVPlayer` w `VideoPlayer` nie odtwarza sam z siebie — user musiał dodatkowo kliknąć play w samym odtwarzaczu. Brak dźwięku: domyślna kategoria sesji audio (`.soloAmbient`) honoruje fizyczny przełącznik cichy na telefonie. **Fix**: `player.play()` + `AVAudioSession.setCategory(.playback)`/`setActive(true)` w `.onAppear`.

**4. Odtwarzacz nie zajmował całego ekranu.** `.sheet` zawsze zostawia margines od góry (widoczny pasek statusu — zegarek/zasięg/bateria) niezależnie od `.ignoresSafeArea()` na zawartości, bo to ograniczenie samego stylu prezentacji karty, nie czegoś do przykrycia od środka. **Fix**: `.fullScreenCover` zamiast `.sheet`, z własnym przyciskiem zamknięcia (`.fullScreenCover`, w przeciwieństwie do `.sheet`, nie ma domyślnego gestu zsuwania w dół).

**Efekt uboczny naprawy #4**: cała zawartość `.fullScreenCover` inline w `LibraryView.body` przekroczyła limit czasu type-checkera Swifta (`"unable to type-check this expression in reasonable time"` — realny błąd kompilacji, potwierdzony przez `xcodebuild`, nie fałszywy alarm SourceKit). Wydzielone do osobnego typu `FullScreenVideoPlayer` — rozbicie dużego wyrażenia SwiftUI na mniejsze kawałki to standardowy sposób obejścia tego ograniczenia kompilatora.

Build → **BUILD SUCCEEDED**, wszystkie 4 fixy zweryfikowane na realnym urządzeniu, user potwierdził że działa.

## 30.07.2026, ciąg dalszy — Multi-track Phase 1 (nakładka "picture-in-picture")

Kolejny punkt z `TODO.md`, idąc ściśle po kolei (user: "zaczynamy od 1 punktu i lecimy po kolei") — najwyższa nieodhaczona pozycja w całym dokumencie: "Prawdziwy multi-track (nakładające się warstwy/PiP)", od tygodnia świadomie odkładany jako "osobny, duży temat: nowy model danych, pionowy stos torów" (`Docs/Studio.md`). Zaplanowany przez `EnterPlanMode`/`ExitPlanMode` (dwa agenty: Explore na architekturę eksportu, Plan na konkretny projekt Fazy 1) — pełny plan w `.claude/plans/glistening-prancing-lynx.md`.

**Zakres Fazy 1**: jeden tor nakładki PiP (zdjęcie/wideo), pozycjonowany w jednym z 4 stałych rogów, 3 presety rozmiaru, zawsze wyciszony, bez własnego trim/speed/rotate/crop. Świadomie POZA zakresem: swobodne przeciąganie, wiele nakładek naraz w tym samym momencie, dźwięk nakładki, przenikanie przy pojawianiu się (twarde cięcie), żywy podgląd odtwarzacza w edytorze (tylko statyczne przybliżenie).

**Model danych**: `OverlayItem.swift` (ulotny) + `SavedOverlayItem` (SwiftData, wszystkie pola z wartością domyślną PRZY DEKLARACJI — twarda zasada z `Database.md`) + `SavedProject.overlays` (ten sam wzorzec relacji co `captions`). Czas nakładki liczony WZGLĘDEM CAŁEGO finalnego filmiku (jak `SavedCaption.startTime`/`endTime`), NIE względem pozycji w głównej sekwencji — pozycje głównych klipów są ulotne (przesuwają się przy każdym reorderze/trimie/splicie/zmianie utworu), więc kotwiczenie do "klipu numer N" wymagałoby ciągłego przeliczania.

**Eksport (`VideoComposer.swift`)** — nowy, POJEDYNCZY tor nakładki (nie naprzemienny A/B jak główny tor — Faza 1 zakazuje nakładkom nachodzenia na siebie nawzajem, więc jeden tor wystarcza), BEZ toru audio (cisza "konstrukcyjnie", nie przez flagę do pamiętania). Nakładanie nakładek na już zbudowane instrukcje `buildInstructions` jako OSOBNY, drugi przebieg (`applyOverlay`) — logika crossfade między głównymi klipami zostaje całkowicie nietknięta:
- Instrukcje "solo" (1 warstwa, bez rampy do zachowania) — bezpiecznie cięte na maks. 3 kawałki wokół zakresu nakładki. `AVMutableVideoCompositionLayerInstruction` nie ma gettera do odczytu transformu/toru już ustawionego przez `setTransform` — oryginalny `ClipPlacement` odtwarzany przez dopasowanie zakresu czasowego instrukcji do placementu, który go w całości zawiera.
- Instrukcje przejścia (2 warstwy, `setOpacityRamp` liczona na CAŁY swój zakres) — traktowane jako ATOMOWE, nigdy nie cięte. `snapOverlayRange` odsuwa granice nakładki na zewnątrz PRZED nałożeniem, jeśli wypadłyby ściśle wewnątrz takiej instrukcji (maks. ~0.4s przesunięcia, niezauważalne).
- `overlayTransform`: pudełko PiP to pomniejszona kopia `canvasSize` W TYCH SAMYCH PROPORCJACH (nie dowolny prostokąt) — dzięki temu `cropFill: true` na zdjęciu (już wyrenderowanym przez `ImageToVideoRenderer` w proporcjach kanwy, fit+blur) matematycznie NIGDY nic nie ucina, zachowując twardą zasadę "nie przycinamy zdjęć" bez specjalnego przypadku. Nakładki wideo o dowolnych proporcjach mogą zostać przycięte — ten sam, już zaakceptowany kompromis co `cropFill` na głównym torze.
- `resolveOverlaySourceURL` — świadomie zduplikowane (nie wydzielone do wspólnej funkcji z `resolveSourceURL`), zgodnie z ustaloną wcześniej zasadą projektu: konkretna duplikacja bezpieczniejsza niż przedwczesna abstrakcja dopóki nie ma trzeciego realnego konsumenta.

**Weryfikacja krok po kroku na realnym urządzeniu** (established wzorzec tej sesji — build+install+test po każdym kroku, nie jeden wielki batch):
1. Sam model danych — build, otwarcie istniejącego projektu, potwierdzone że migracja się nie wysypała.
2. Eksport z zahardkodowaną testową nakładką (self-overlay pierwszego klipu) — **zadziałało za pierwszym razem**, poprawny róg/rozmiar/proporcje na realnym eksportowanym wideo (przypadkowo trafiło do usera podczas niepowiązanego testu, wywołując chwilowe zamieszanie "nie wiem co się wydarzyło" — wyjaśnione, że to zamierzony test tymczasowy).
3. Prawdziwy przycisk "PiP" w dolnym pasku toolbara + picker — po drodze naprawiony realny bug znaleziony PRZED testem przez usera: dwie dodane nakładki domyślnie startowały w tym samym momencie (0s), co próbowałoby wstawić nachodzące się zakresy w POJEDYNCZY tor nakładki i wywaliłoby eksport błędem — naprawione: każda kolejna nakładka domyślnie startuje zaraz po końcu poprzedniej.
4. `OverlaySettingsView.swift` (wzorowany na `TrimView.swift` — suwaki start/długość, siatka 2×2 rogów, 3 presety rozmiaru, usuwanie) + osobny, warunkowo widoczny wiersz miniaturek nakładek pod główną osią czasu (`OverlayThumbnail`, bez drag-reorder — retiming wyłącznie przez ekran ustawień, bo pozycja to jawny czas, nie kolejność w tablicy) + statyczne przybliżenie nakładki w podglądzie edytora (brak żywego odtwarzacza w tym ekranie, ten sam ograniczenie co reszta Studio).

**Realny bug znaleziony i naprawiony po drodze**: dodanie 6. przycisku do `bottomToolbar` i rozbudowa `preview` w `EditView.swift` zadziałały bez problemu, ale dodanie CAŁEJ zawartości ekranu ustawień jako inline w jednym miejscu groziłoby tym samym "unable to type-check" co w `LibraryView.swift` dziś wcześniej — `OverlaySettingsView` od razu wydzielony do osobnego pliku/typu, zapobiegawczo.

Build → **BUILD SUCCEEDED** na każdym z 4 kroków, wszystko zweryfikowane na realnym urządzeniu, user potwierdził że działa i rozumie przeznaczenie funkcji.

**Pozostaje na przyszłość** (świadomie poza Fazą 1, zapisane w `Docs/Studio.md`): swobodne przeciąganie pozycji/rozmiaru zamiast stałych presetów, więcej niż jedna nakładka naraz w tym samym momencie, dźwięk nakładki, przenikanie przy pojawianiu/znikaniu, żywy podgląd odtwarzacza, maski/blend mody/keyframes. Port na Mac — nie zaczęty, osobne zadanie (ten sam wzorzec co Travel Cinematics: iPhone najpierw, Mac później).

## 30.07.2026, ciąg dalszy — Waymarked Trails (Overpass) dla Wędrówki

Kolejny punkt z `TODO.md`, ściśle po kolei. Nowy plik `WaymarkedTrailProvider.swift` — zapytanie Overpass QL do publicznego, bezpłatnego endpointu `overpass-api.de` (bez konta/klucza, ten sam wzorzec "brak własnego serwera" co `MKDirections`/`CLGeocoder`/`MKLocalSearch`) o relacje `route=hiking` (dane OpenStreetMap, ta sama baza co Waymarked Trails) w promieniu wokół odcinka. Dopasowanie: kandydacki szlak akceptowany tylko gdy OBA końce odcinka leżą w promieniu 300m od jego linii (realne miejsce nie pokrywa się dokładnie z geokodowanym pinem miasta); spośród pasujących wybierany NAJKRÓTSZY dopasowany fragment (unika złapania jakiegoś długodystansowego szlaku przechodzącego przez okolicę zamiast precyzyjnej lokalnej ścieżki). `RouteProvider.route` dla `.hiking` próbuje tego NAJPIERW, cicho wraca do dotychczasowego `.walking` gdy nic nie pasuje (dokładnie ten sam styl `try?`-owego fallbacku co reszta pliku) — zero regresji dla odcinków bez realnego szlaku w okolicy.

**Uczciwe ograniczenie, zapisane wprost w kodzie i w `Travel.md`**: Overpass to baza danych OSM, NIE silnik routingu — nie policzy trasy między dwoma dowolnymi punktami, tylko znajdzie prawdziwy, już istniejący szlak gdy faktycznie łączy oba miejsca. Pełne trasowanie po dowolnych punktach wymagałoby płatnego/kluczowanego serwisu (sprawdzone: openrouteservice.org, darmowy tier 2500 zapytań/dzień, ale wymaga konta usera i klucza API) — świadomie NIE zrobione bez pytania usera o założenie takiego konta.

Build → **BUILD SUCCEEDED**, zainstalowane i uruchomione na urządzeniu. User przetestował z realnym odcinkiem Wędrówki — trasa wygląda poprawnie (nie zgłosił żadnego problemu z samą trasą, tylko z już znaną, odłożoną kanciastością podglądu na żywo — niezwiązane z tą zmianą).

## 30.07.2026, ciąg dalszy — Statystyki wysokości przy Wędrówce

Kolejny punkt z `TODO.md`, ściśle po kolei. `ElevationProvider.swift` — Open-Meteo Elevation API (`api.open-meteo.com/v1/elevation`, darmowe/keyless dla użytku niekomercyjnego, do 100 współrzędnych na zapytanie — ścieżka dociągana do limitu przez `RouteProvider.resamplePath`, ta sama technika co gdzie indziej). Liczone w `TravelMapView.persistTrip` TYLKO dla odcinków `.hiking`, w tym samym miejscu/momencie co `legDistanceKm`. Nowe opcjonalne pola `SavedStop.elevationGainMeters`/`highestElevationMeters` (bez jawnego `= nil` — Optional ma domyślne `nil` automatycznie, ten sam wzorzec co istniejące `country`/`arrivalDate` w tym samym modelu), `SavedTrip.totalElevationGainMeters`/`highestElevationMeters` (suma/max po wszystkich odcinkach).

**Diagnostyka podczas testu**: user zgłosił "nie mamy nigdzie km ani wzniesienia" — okazało się że km jednak działało (widoczne "14 km" na liście), tylko odznaka wysokości się nie pojawiała. Zamiast zgadywać dalej, dodana diagnostyczna zmiana: `SavedTrip.hasHikingLeg` + odznaka pokazująca "⛰️ brak danych" zamiast całkiem się chować, gdy Wędrówka jest wykryta ale bez danych wysokości — pozwoliło jednoznacznie odróżnić "nie wykryto Wędrówki" (żadna odznaka) od "wykryto, zapytanie zawiodło" ("brak danych"). Diagnoza: user testował na odcinku gdzie transport NIE był ustawiony na Wędrówka (żadna odznaka się nie pokazywała nawet po zmianie diagnostycznej) — okazało się, że **zmiana transportu przez edycję istniejącej podróży się nie zapisywała** (prawdopodobnie user nie doszedł do końca flow edycji) — obejście: usunięcie i dodanie podróży od nowa z Wędrówką wybraną od razu przy tworzeniu, co zadziałało. Diagnostyczna odznaka "brak danych" **zostawiona na stałe** (nie cofnięta po diagnozie) — uczciwsze niż cicho ukryta odznaka, ten sam duch co zasada "żadnego zgadywania liczb" z sekcji Lifetime Stats.

**Otwarty, niezbadany trop na przyszłość**: dlaczego zmiana transportu przez edycję istniejącej podróży (`editingTripID` flow w `TravelMapView`) nie zawsze się utrwala — nie dochodzone dziś dalej (obejście zadziałało), ale warto sprawdzić przy następnej okazji.

Build → **BUILD SUCCEEDED**, user potwierdził że po utworzeniu podróży od nowa z Wędrówką działa.

## 30.07.2026, ciąg dalszy — Automatyczne wykrywanie szczytu przez GPS

Ostatni punkt Travel z dzisiejszej listy. `PeakDetector.swift` — przycisk 📍 obok pola nazwy w `TravelMapView.StopRow`, w pełni opt-in: `CLLocationManager` (pierwsze użycie GPS w całej appce — dodane `NSLocationWhenInUseUsageDescription` do `project.yml`) odpytywane WYŁĄCZNIE po kliknięciu, jednorazowo (`requestLocation()`, nie ciągłe śledzenie), zero sprawdzania w tle. User wprost zapytał czy to nie będzie dawać niepotrzebnych komunikatów gdziekolwiek indziej — potwierdzone że nie, bo cała logika siedzi za jednym przyciskiem.

`CurrentLocationProvider` — most delegate→async/await dla `CLLocationManager` (ten sam wzorzec `CheckedContinuation` co `MapRenderDelegate` w `TravelMapVideoRenderer`). Po zdobyciu lokalizacji: zapytanie Overpass o węzły `natural=peak` w promieniu 1km (ta sama rodzina API co `WaymarkedTrailProvider`), najbliższy dopasowany po odległości. Współrzędna przystanku ustawiana ze WĘZŁA SZCZYTU w OSM (dokładniejsza niż surowa, zaszumiona przez odbicia od skał pozycja GPS), kraj dociągnięty odwrotnym geokodowaniem (`CLGeocoder.reverseGeocodeLocation`) — przystanek od razu w pełni rozwiązany, bez pośredniego kroku wybierania podpowiedzi z `CitySearchCompleter`.

Build → **BUILD SUCCEEDED**, zainstalowane na urządzeniu. Nie w pełni zweryfikowane na realnym szczycie (user testował z telefonu, nie fizycznie w górach — poprawne zachowanie w tej sytuacji to komunikat "nie znaleziono szczytu", nie błąd) — logika i UI potwierdzone, pełny test "na żywo" (prawdziwy szczyt) czeka na okazję.

## 30.07.2026, ciąg dalszy — Przebudowa Home + Studio (Faza 1 "Lifetime Travel Stats")

Kolejny punkt z `TODO.md`, ściśle po kolei — od 29.07 opisany jako "duży, wielosesyjny temat" (pełna wizja w `Travel.md`), więc zaplanowany przez `EnterPlanMode`/`ExitPlanMode` jako konkretna, jednosesyjna **Faza 1** (ten sam wzorzec skalowania co Multi-track PiP i Waymarked Trails dziś wcześniej), reszta wizji świadomie zostaje w `Travel.md` jako V2.

**Home (`dashboardTab`)**: usunięta karta "Continue Editing" — "Create Memory" jest teraz jedynym CTA, pierwszą rzeczą po powitaniu (wcześniej dwa duże CTA jeden pod drugim konkurowały o uwagę).

**Studio (`studioTab`)**: przestał być cienkim placeholderem, który przez `.onChange(of: selectedTab)` auto-otwierał najnowszy projekt WPROST w edytorze przy każdym tapnięciu zakładki — zastąpiony prawdziwym ekranem: "Continue Editing" → "Recent Projects" (reszta projektów, `StudioProjectRow`) → "Nowy projekt" (ten sam `PhotosPicker` co Home, `photoLibrary: .shared()`). Usunięty auto-open side-effect przy zmianie zakładki — teraz user świadomie wybiera projekt z listy.

**Realny bug znaleziony przez usera PO pierwszym teście**: "Continue Editing" pokazywało `savedProjects.first` (najnowszy wg `updatedAt`) bez sprawdzania czy jest już wyeksportowany — user zapytał wprost, czy skończone Lanzarote pokazałoby się jako "do kontynuacji". Odpowiedź: tak, pokazałoby się (realny bug, nie hipotetyczny). **Fix**: nowy `continuableProject` — `savedProjects.first(where: { $0.exportedAssetIdentifier == nil })`, "Recent Projects" filtrowane po `id` (nie `dropFirst()`, bo kontynuowalny projekt może wcale nie być pierwszy na liście gdy najnowszy jest już skończony).

**Karta statystyk (`travelIntelligenceCard`)**: nazwa "Travel Intelligence" → **"Your Journey"** (user 29.07 uznał oryginalną nazwę za zbyt techniczną/korporacyjną, zaproponował kilka alternatyw bez ostatecznej decyzji — wybrana najkrótsza zamiast dalej zwlekać, niskie ryzyko/łatwo odwracalne). Dodany wiersz z realnym **total km** (suma `SavedTrip.totalDistanceKm`) i **przewyższeniem** (suma `totalElevationGainMeters`, pokazywane tylko gdy > 0 — ta sama zasada "brak danych zamiast zera-jako-placeholdera" co przy przewyższeniu na karcie podróży) — zero nowej persystencji, dane już istniały z dzisiejszych wcześniejszych featurów (Elevation, Waymarked Trails).

**Świadomie poza Fazą 1** (zostaje w `Travel.md` jako wizja): pełny wykres/pasek % per środek transportu, "Around the World" mnożnik, porównania-ciekawostki, liczniki lotów/zdjęć/wideo/"Memories created", osobny pełnoekranowy widok Lifetime Stats, liczba miast — wymagają dodatkowych agregacji poza `SavedTrip`, nie tylko UI.

Build → **BUILD SUCCEEDED** dwukrotnie (raz przed fix-em Lanzarote, raz po), zainstalowane i uruchomione na urządzeniu oba razy, user potwierdził że działa po obu iteracjach.

## 30.07.2026, ciąg dalszy — Cache renderów zdjęć (zamiast pełnego custom AVVideoCompositing)

Kolejny punkt z `TODO.md`: "Pełna eliminacja pliku pośredniego dla zdjęć (custom `AVVideoCompositing`, zero dodatkowego kodowania)". Zbadane przez `EnterPlanMode` + Explore agenta zanim cokolwiek napisane: `ImageToVideoRenderer.render` koduje zdjęcie do near-lossless ProRes 422 HQ (świadomie, 29.07 — unika PODWÓJNEJ stratnej kompresji przy finalnym eksporcie), potem plik trafia do kompozycji jak zwykły klip wideo.

**Kluczowe odkrycie architektoniczne**: `AVVideoComposition.customVideoCompositorClass` w AVFoundation jest "wszystko albo nic" — raz ustawiony, przechwytuje KAŻDĄ instrukcję całego filmu, nie da się go podłączyć tylko do segmentów-zdjęć. W kodzie zero istniejącego prior art dla custom compositora — całe przenikanie (`buildInstructions`, `setOpacityRamp`) i PiP (`applyOverlay`) zbudowane są na standardowym API. Pełna realizacja wizji z TODO oznaczałaby ręczne odtworzenie w custom compositorze też przenikania i PiP — dopiero dziś ustabilizowanych — nie tylko wymianę renderowania zdjęć.

User poproszony wprost o profesjonalną rekomendację między (a) pełnym custom compositorem, (b) mniejszym cache'em, (c) odłożeniem punktu. Rekomendacja: (b) — realny ból usera to nie jakość (ProRes już "praktycznie bezstratny") tylko czas: KAŻDY re-eksport tego samego projektu renderował i kodował WSZYSTKIE zdjęcia od zera, nawet nietknięte. User zaakceptował.

**`PhotoRenderCache.swift`** (nowy plik) — `actor` (ten sam wzorzec co `FrameBuffer` w rendererze Travel Map), klucz `(assetIdentifier, duration, width, height)` → `URL` wyrenderowanego pliku, trwa przez czas życia procesu appki (bez zapisu na dysk, bez eviction — typowe projekty to dziesiątki zdjęć, nie tysiące). Wpięty w `resolveSourceURL`/`resolveOverlaySourceURL` w `VideoComposer.swift` — sprawdzenie cache PRZED wywołaniem `ImageToVideoRenderer.render`, zapis PO. Klucz dzielony między głównym torem a nakładką PiP (oba renderują w pełnym `canvasSize`).

**Uczciwe ograniczenie zapisane w kodzie**: `redistributeDurations()` w `EditView` resetuje `duration` KAŻDEGO nieprzyciętego ręcznie elementu przy zmianie liczby klipów LUB muzyki — więc cache NIE pomaga dokładnie w scenariuszu "zmieniłem tylko muzykę" dla auto-rozłożonych zdjęć (poprawnie, bo piksele faktycznie by się rozjechały z osią czasu). Pomaga za to realnie przy: re-eksporcie bez zmian, zmianie kolejności (drag&drop), edycji napisów/nakładek, zmianie głośności muzyki, i przy ręcznie przyciętych zdjęciach nawet mimo zmiany muzyki/liczby klipów.

**Weryfikacja na urządzeniu**: user przetestował samodzielnie na eksporcie 4K (najcięższy przypadek) — zmierzył czas ręcznie (66%→100% = 1min50s dla samego finalnego kodowania). Drugi eksport TEGO SAMEGO, niezmienionego projektu w 4K wystartował od razu od 60% zamiast od 0% — potwierdza że cała faza renderowania zdjęć (0–60% paska postępu, zmapowana w `EditView.performExport`: `onProgress: { progress in exportProgress = progress * 0.6 }`) wykonała się praktycznie natychmiast. Faza 60–100% (`AVAssetExportSession`, finalne kodowanie H.264/HEVC całego filmu) musi się wykonać za każdym razem — to jedyna część, której cache strukturalnie nie może przyspieszyć.

Build → **BUILD SUCCEEDED**, zainstalowane i przetestowane na urządzeniu, user potwierdził zysk czasu.

**Pełny custom `AVVideoCompositing`** (zero kodowania nawet przy PIERWSZYM eksporcie, nie tylko przy re-eksporcie) zostaje w backlogu jako świadomie odłożony — wymaga ręcznego odtworzenia przenikania/PiP w custom compositorze, realnie wielosesyjny temat wymagający starannych testów, nie coś na koniec długiego dnia.

## 30.07.2026, ciąg dalszy — Bug: nowa nakładka PiP zawsze lądowała na początku filmu

Realny bug zgłoszony przez usera zaraz po przetestowaniu cache'u zdjęć, przy okazji korzystania z PiP z dzisiejszej wcześniejszej sesji: "czy nie powinniśmy zaznaczyć zdjęcia do którego ma być podpięty? czy zawsze będzie podpinany pod pierwsze co jest kompletnie bez sensu". Sprawdzone w kodzie — słuszne: `addOverlay` w `EditView.swift` w ogóle nie patrzył na `selectedIndex` (zaznaczony klip w osi czasu), tylko zawsze doklejał nową nakładkę zaraz po końcu poprzedniej (pierwsza zawsze lądowała na czasie 0, czyli nad pierwszym klipem, niezależnie co user miał akurat zaznaczone).

**Fix**: nowa nakładka domyślnie startuje nad AKTUALNIE zaznaczonym klipem (`desiredStart` = suma czasów klipów przed `selectedIndex`, ten sam przybliżony wzorzec co istniejący `currentOverlayForPreview`). Nowa funkcja `nextAvailableOverlayStart(desiredStart:duration:totalDuration:existingRanges:)` szuka najbliższego WOLNEGO miejsca od `desiredStart` w przód, przesuwając się za kolidujące zakresy istniejących nakładek (Faza 1 wciąż zakazuje nakładkom nachodzenia na siebie nawzajem — pojedynczy tor nakładki w eksporcie) — jeśli zaznaczony klip koliduje z istniejącą nakładką, user trafia w sensowne miejsce zaraz PO kolizji, nie z powrotem na początek filmu.

Build → **BUILD SUCCEEDED**, zainstalowane, user potwierdził że działa.

## 30.07.2026, ciąg dalszy — Smart Route (auto-wykrywanie trasy ze zdjęć)

CloudKit sync (kolejny punkt z `TODO.md`) pominięty świadomie — wymaga płatnego Apple Developer Program (appka dziś podpisana automatycznie na darmowym koncie), a user ustalił nową zasadę: rzeczy wymagające płatnego konta zostają na SAM KONIEC listy, płaci się dopiero jak reszta zrobiona. Przeszedłem więc do kolejnego niezablokowanego punktu: **Smart Route**.

Zbadane przed kodowaniem (Explore agent): cały pipeline zapisu trasy (`persistTrip`, `SavedStop`/`SavedTrip`, `RouteProvider`) działa już dziś na zwykłej tablicy `[TripStop]` — Smart Route musi tylko WYPRODUKOWAĆ tę tablicę ze zdjęć, zero zmian w budowaniu/zapisie trasy.

**`SmartRouteDetector.swift`** (nowy plik) — zachłanne grupowanie sekwencyjne zdjęć (posortowanych po dacie `PHAsset.creationDate`) po BIEŻĄCYM centroidzie klastra (nie stałym pierwszym punkcie — unika driftu przy kilkudniowym pobycie z wędrówkami po całym mieście), promień 20km. Każdy klaster → odwrotne geokodowanie centroidu (nowe `CityGeocoder.reverseResolveFull`, zwraca miasto+kraj+kod kraju — istniejące `reverseResolve` liczyło je wewnętrznie ale odrzucało, zostawiając samą nazwę miasta) → `TripStop` z `arrivalDate` wypełnionym z realnej daty zdjęcia (bonus — dotąd zawsze ręczny `DatePicker`). Transport między kolejnymi przystankami: prosty próg dystansu (>300km → ✈️ Samolot, inaczej → 🚗 Samochód) — **jawnie NIE "AI"**, udokumentowane w kodzie że to tylko wstępna zgadywanka między dwiema opcjami (pociąg/prom/rejs/wędrówka nigdy nie zgadywane, brak wiarygodnego sygnału w samym GPS+czasie).

**`MediaAssetLoader.locationsAndDates`** (nowa funkcja obok istniejącej `firstLocation`) — ten sam `PHAsset.fetchAssets(withLocalIdentifiers:)`, ale zbiera lokalizację+datę KAŻDEGO zdjęcia zamiast zatrzymywać się na pierwszym trafieniu. Zero nowych uprawnień Photos.

**`TravelMapView.swift`** — nowy przycisk "Wykryj trasę ze zdjęć" (sekcja zaraz pod "Dodaj miejsce"), otwiera `PhotosPicker` (`photoLibrary: .shared()`, ten sam wymóg co reszta pickerów), wynik zastępuje `stops` — z potwierdzeniem jeśli obecna lista ma już ręcznie wpisaną treść (żeby nie zgubić cudzej pracy przez przypadek). Puste zdjęcia bez lokalizacji → uczciwy komunikat błędu zamiast cichego nic (ten sam wzorzec co `PeakDetector`). User trafia z powrotem na TEN SAM ekran ręcznej edycji, wygenerowane przystanki są w pełni edytowalne przed zapisaniem.

**Przy okazji, na żywą prośbę usera zaraz po teście**: "czy możemy dodać miejsce na początku albo przesunąć góra dół" — chciał ręcznie dołożyć lot na start trasy wykrytej przez Smart Route (auto-detekcja zaczyna od pierwszego zdjęcia z lokalizacją, nie złapie lotu bez zdjęć w powietrzu). Dodane: drugi przycisk "Dodaj na początku" (obok istniejącego, teraz nazwanego "Dodaj na końcu") + przeciąganie przystanków do zmiany kolejności (`.draggable`/`.dropDestination` na indeksie — dokładnie ten sam wzorzec co timeline w `EditView.moveItem`, żadnego nowego mechanizmu).

Build → **BUILD SUCCEEDED** dwukrotnie (raz po Smart Route, raz po reorder/insert-at-start), zainstalowane i przetestowane na urządzeniu oba razy, user potwierdził że działa.

## 30.07.2026, ciąg dalszy — Miniaturka zdjęcia na markerze przystanku

Kolejny punkt z `TODO.md`, naturalna kontynuacja Smart Route (już mamy identyfikatory zdjęć per przystanek, brakowało tylko pokazania ich na mapie).

Nowe pole `representativePhotoIdentifier: String?` na `TripStop` (`TravelMap.swift`) i `SavedStop` (`TripPersistence.swift`, wątkowane przez `asTripStops`/`persistTrip` jak reszta pól tego dnia). Wypełniane dwoma sposobami:
- **Automatycznie przez Smart Route** — `SmartRouteDetector` teraz śledzi identyfikator zdjęcia przez cały proces klastrowania (wcześniej `MediaAssetLoader.locationsAndDates` zwracał tylko lokalizację+datę, dociągnięty identyfikator), przypisuje chronologicznie PIERWSZE zdjęcie klastra (to samo zdjęcie co już wyznacza `arrivalDate` — oba pola pokazują tę samą, spójną chwilę).
- **Ręcznie** — nowy przycisk-miniaturka w `StopRow` obok pola nazwy, otwiera `PhotosPicker` (`photoLibrary: .shared()`) do przypisania/zmiany zdjęcia dla przystanków spoza Smart Route.

Nowa mała funkcja `MediaAssetLoader.markerThumbnail` — celowo MAŁY `targetSize` (160×160), w odróżnieniu od istniejącego `thumbnail(forAssetLocalIdentifier:)` który świadomie ściąga pełną rozdzielczość (karmi też finalny eksport wideo) — marker na mapie to kilkadziesiąt punktów, nie ma sensu ściągać pełnego zdjęcia tylko po to żeby je zaraz zmniejszyć.

**Rendering** — `TravelMapVideoRenderer.renderFrames` (współdzielony silnik podglądu+eksportu) dostał jednorazowy preload wszystkich miniaturek PRZED pętlą klatek (`TaskGroup`, ten sam wzorzec zrównoleglenia co `VideoComposer.resolveSourceURLs`) — zero kosztu Photos per klatka. Słownik `[UUID: UIImage]` wątkowany przez `composite()` do `drawGlobeCityLabel`, która teraz rysuje zdjęcie przycięte do koła z białym obramowaniem (`CGContext` clip + `draw(in:blendMode:alpha:)`, `alpha` zachowuje istniejące przyciemnienie dla `dimmed` = cel jeszcze nieosiągnięty) zamiast zwykłej niebieskiej kropki — WIĘKSZY rozmiar (26pt vs 8pt) żeby zdjęcie było faktycznie widoczne, reszta układu karty (`dotCardGap`/`boxRect`) skaluje się z nim automatycznie. Brak miniaturki = dokładnie stara kropka, zero regresji.

Build → **BUILD SUCCEEDED**, zainstalowane i przetestowane na urządzeniu, user potwierdził że miniaturki pokazują się poprawnie zarówno w podglądzie jak i eksporcie.

## 30.07.2026, ciąg dalszy — World Globe (Faza 1) + długa seria realnych bugów przy testach na urządzeniu

Ostatni punkt Travel z dzisiejszej listy, zaproponowany przez usera zaraz po przetestowaniu miniaturek na markerach: interaktywny globus pokazujący WSZYSTKIE odwiedzone miejsca naraz (nie jedną podróż), z pinezkami-zdjęciami, tap na połączone miejsce → Library z gotowym filmem. Zaplanowany przez `EnterPlanMode` — user poproszony wprost o rekomendację między pełnym custom compositorem a mniejszym zakresem (jak wcześniej przy cache'u renderów), tym razem chodziło o zakres samego globusu: **Faza 1 = same pinezki ze zdjęciami, bez zacieniowanych granic krajów** (te wymagałyby nowych danych geograficznych, których appka nie ma) — user potwierdził.

**Nowe elementy**: `SavedStop.linkedProjectID` (+ `TripStop` mirror) — ręczne powiązanie przystanku z gotowym filmem, przycisk 🎞️ w `StopRow`, zawsze RĘCZNE (nigdy zgadywane po dacie/nazwie, ten sam duch co "Połącz z gotowym wideo" w Library). `WorldGlobeView.swift` (nowy plik) — SwiftUI `Map`, agregacja `savedTrips.flatMap(\.stops)`, grupowanie po ODLEGŁOŚCI (20km, ten sam wzorzec co `SmartRouteDetector`) zamiast po dokładnej nazwie — lotnisko przylotu i centrum miasta z osobnych zdjęć to dwa różne `SavedStop`, ale jedno miejsce w oczach usera.

**Długa seria realnych bugów znalezionych podczas testowania na żywo** (wszystkie potwierdzone dowodami — crash logi, logi konsoli na żywo przez `devicectl --console`, nie zgadywanie):

1. **Tap na ikonę filmu otwierał picker zdjęć zamiast listy filmów** — sheet prezentowany bezpośrednio z wnętrza wiersza `List` (a nie z jego stabilnego rodzica) potrafił "pomylić" się z sąsiednim `.photosPicker`. Naprawione przeniesieniem WSZYSTKICH prezentacji (sheet/photosPicker/alert) na wspólny, stabilny poziom `VStack` zamiast pojedynczych przycisków w rzędzie.

2. **Migotliwy, losowo się otwierający picker po przeciąganiu/wstawianiu przystanków** — `ForEach(stops.indices, id: \.self)` (tożsamość po POZYCJI w tablicy, potrzebna do przeciągania) powodowała że SwiftUI podmieniało dane POD istniejącym `@State` wiersza zamiast tworzyć nowy. Naprawione: `ForEach($stops)` (tożsamość po `TripStop.id`, stałym UUID), przeciąganie identyfikuje wiersze przez `stop.id.uuidString`.

3. **Zapisanie po połączeniu filmu resetowało całą trasę do pustego szablonu** — user zgłosił to WIELOKROTNIE, z bardzo dokładnymi zrzutami ekranu na każdym kroku. Ostatecznie złapane logiem konsoli na żywo (`print` + `xcrun devicectl --console`): `onSave` i `onCancelTapped` (górne przyciski "Zapisz"/"Anuluj") odpalały się OBA z jednego kliknięcia — brak `.buttonStyle(.plain)` w rzędzie `List` (dokładnie ten sam mechanizm co bug #1, w nowym miejscu — `EditingBanner`). Po drodze dodane też: potwierdzenie przed "Anuluj" (zabezpieczenie dodatkowe, zostaje), jawny strażnik `namedStops.count >= 2` wewnątrz `buildRoute()` (belt-and-suspenders przeciw `RenderError.notEnoughStops`), i osobny szybki "Zapisz" (`showAnimation: false`) na górze bannera, żeby user nie musiał przewijać całej listy przystanków tylko po to, żeby zapisać.

4. **`TravelMapView.body` przekraczało limit czasu type-checkera Swifta** ("unable to type-check this expression in reasonable time") — po dodaniu tylu funkcji w jeden dzień całe `body` jako jedno wyrażenie zrobiło się za duże. Naprawione przez rozbicie na osobne właściwości (`stopsList`, `linkProjectSheet`) i osobne typy (`EditingBanner`, `BuildRouteButton`) — ten sam, już dziś kilkukrotnie sprawdzony wzorzec.

5. **Tap na pinezkę globusu nie robił NIC** — ani `.onTapGesture`, ani zwykły `Button` w środku `Annotation` nie odbierały tapnięcia niezawodnie (mapa sama konkuruje o gest z dowolnym gestem/przyciskiem doklejonym do zawartości adnotacji). Naprawione przejściem na oficjalny mechanizm: `Map(selection:)` + `.tag(_:)` na adnotacji — MapKit obsługuje zaznaczenie sam, bez tej konkurencji.

6. **Po tapnięciu połączonej pinezki appka zostawała na globusie zamiast przenieść do Library** — trzeba było ręcznie wyjść. Naprawione: `WorldGlobeView` dostaje teraz `isPresented: Binding<Bool>` (to samo co steruje `.navigationDestination` w `TravelMapView`) i jawnie zamyka się PRZED przełączeniem `selectedTab`, zamiast liczyć że sama zmiana zakładki wystarczy przy zagnieżdżonym `NavigationStack`.

7. **Miejsce z kilkoma różnymi filmami** (user: dwie osobne wizyty, różne filmy) — dodany wybór po nazwie (`multiLinkPlace` sheet z listą tytułów projektów) zamiast po cichu skakać do pierwszego znalezionego w klastrze.

8. **Odtwarzanie "Lanzarote" w Library rzucało błąd** (`MediaAssetLoader.LoadError.assetNotFound`, error 0) — zapisany identyfikator wskazywał na plik USUNIĘTY z biblioteki Zdjęć. Nie błąd appki (uczciwe zgłoszenie martwej referencji), ale odkryty przy okazji realny gap: opcja ręcznego połączenia ("Połącz z gotowym wideo") w Library pokazywała się TYLKO gdy `exportedAssetIdentifier` było `nil` od początku — nie dawała drogi naprawy gdy identyfikator ISTNIAŁ, ale wskazywał na coś nieistniejącego. Naprawione: opcja (przemianowana na "Zmień połączony plik" gdy już coś jest) dostępna zawsze.

**Metoda pracy przy tej serii bugów** — kluczowa zmiana w połowie: zamiast dalej zgadywać przyczynę ze zrzutów ekranu, przejście na `print()` + `xcrun devicectl device process launch --console` (strumieniowanie stdout na żywo z urządzenia) — każdy kolejny bug złapany TAK został znaleziony na pierwszy strzał, bez zgadywania. User w pewnym momencie słusznie się zdenerwował sugestią że to jego pomyłka (kliknął złe miejsce) — dowód z logów pokazał że miał całkowitą rację, appka miała realny bug. Warto zapamiętać: przy powtarzającym się, dziwnym zachowaniu UI (przycisk X robi Y) sięgać po logi z urządzenia od razu, nie dopiero po kilku nietrafionych teoriach.

Build → **BUILD SUCCEEDED** za każdym razem (kilkanaście iteracji), wszystko zweryfikowane na realnym urządzeniu krok po kroku, user na końcu potwierdził że cały przepływ (link filmu → zapis → globus → Library → odtwarzanie) działa.

**Koniec sesji 30.07.2026** — user robi przerwę, wraca za kilka godzin. Cała lista Travel z `TODO.md` na dziś zamknięta (Smart Route, miniaturki markerów, World Globe); pozostałe punkty Travel ("My World", AI Journey Score, Travel Passport, Travel Wrapped, Travel Time Machine, "Travel Replay" outro, "Cinematic Lighting") zależą od `Database.md` i zostają w backlogu. Następny punkt w `TODO.md` po Travel to "AI (Etap 3)" — explicite oznaczony jako "nie zaczynać przed powyższym", więc kolejna sesja naturalnie zaczyna się od tamtąd, o ile user nie zdecyduje inaczej.

## 02.08.2026 — Ranking testerów (Sign in with Apple + CloudKit) + pierwszy upload na TestFlight

**Ranking/leaderboard**: `AuthManager.swift` (Sign in with Apple), `LeaderboardService.swift` (CloudKit publiczna baza), `LeaderboardView.swift` — wynik to `ExplorerScore.total` z istniejącego systemu Achievements. Entitlements dodane: `com.apple.developer.applesignin`, `com.apple.developer.icloud-services`/`icloud-container-identifiers`.

Bug po drodze: samo dodanie uprawnienia CloudKit sprawiło że SwiftData automatycznie próbowało włączyć własną synchronizację CloudKit dla lokalnej bazy (domyślne zachowanie `ModelConfiguration` gdy uprawnienie jest obecne) — crash na starcie. Fix: jawne `ModelConfiguration(schema:cloudKitDatabase: .none)` w `PMemoriesAppApp.swift`. Zapamiętać przy każdym dodawaniu CloudKit do projektu z SwiftData.

**Pierwszy upload do TestFlight**: rekord appki utworzony w App Store Connect (`com.piotrmarkowski.pmemories`), app-specific password wygenerowany, Claude zrobił `xcodebuild archive` → `xcodebuild -exportArchive` (ExportOptions: method `app-store-connect`, teamID `X3NAM3PL95`) → `xcrun altool --upload-app`. **UPLOAD SUCCEEDED**, build 1.0 (1). Info.plist wcześniej dostał `ITSAppUsesNonExemptEncryption = false`.

Zostało: poczekać aż Apple przetworzy build, uzupełnić "What to Test", skonfigurować testerów (Internal od razu / External wymaga Beta App Review ~24h pierwszy raz).

## 10.08.2026 — Sprint pod update na czwartek 14.08: awatar "P" + "Create memory again"

User po analizie konkurencji i cenach (`TODO.md`/`Pricing.md`, patrz sekcje 09–10.08) zdecydował: ten tydzień kończy się aktualizacją na TestFlight w czwartek 14.08, budujemy listę "quick winów" zamiast czekać na duży moduł Trip Planning. Zasada usera na start pracy: **"zaczynamy więc robić i zobaczymy czy zdążymy, nie oceniamy teraz"** — realizacja, nie kolejna runda planowania.

**Bug awatara "P"** — `ProfileView.swift` i `HomeView.swift` (nagłówek dashboardu) pokazywały zahardcodowane `Text("P")` jako fallback gdy user nie ma zdjęcia profilowego — literówka po developerze appki (Piotr), nie coś wyliczonego z faktycznie zalogowanego usera. Naprawione: inicjał pochodzi teraz z `AuthManager.shared.displayName?.first` (Sign in with Apple), z sensownym fallbackiem na ikonę `person.fill` gdy usera jeszcze nie ma nawet displayName.

**"Create memory again" na karcie "On This Day"** — karta była czysto informacyjna (miasto, ile lat temu, pogoda z dnia wizyty), bez żadnej akcji po tapnięciu. Rozszerzone o `linkedProjectIDs` w `OnThisDayMatch` (`TravelTimeMachineProvider.swift`) — agregacja `linkedProjectID` (to samo pole co ręczne łączenie na World Globe) ze WSZYSTKICH przystanków danej podróży, nie tylko trafionego przystanku. Karta teraz jest przyciskiem:
- Gdy podróż ma już powiązany film → tap przenosi wprost do niego w Library (`pendingLibraryHighlightIDs` + `selectedTab = .library`, dokładnie ten sam mechanizm co World Globe).
- Gdy filmu jeszcze nie ma → tap otwiera zwykły picker "Create Memory" (`.photosPicker(isPresented:)` na nowym `@State isShowingOnThisDayPicker`, dopisujący do TEGO SAMEGO `pickerSelection` co główne CTA — żadnej duplikacji logiki `loadSelection`).

Świadomie NIE zaimplementowane: automatyczne wstępne zaznaczenie zdjęć tej konkretnej podróży w pickerze — `SavedStop` trzyma tylko JEDNO reprezentatywne zdjęcie per przystanek, nie pełną listę assetów całej podróży, więc "prawdziwe" auto-uzupełnienie zdjęć złamałoby zasadę zero-zgadywania (ten sam powód co brak dokładnej liczby zdjęć w `RecentMemoryTile`).

Napisy "Create memory again"/"Open memory" dodane tylko po angielsku na razie (fallback Stringa Catalog = klucz = angielski tekst) — pełne tłumaczenie na 27 języków świadomie odłożone, nie blokuje builda ani tego tygodnia.

Build → **BUILD SUCCEEDED**, zainstalowane na iPhone przez `devicectl` (pierwsza próba instalacji failnęła połączeniem — "Connection reset by peer" — druga się udała, zwykła niestabilność tunelu, nie bug appki).

**Sortowanie rankingu po krajach** — `LeaderboardSort` (enum `.score`/`.countries`) w `LeaderboardService.swift`, `topEntries(sortBy:)` przyjmuje teraz który klucz sortować. `LeaderboardView` dostał segmentowany Picker nad listą; duża liczba po prawej w każdym wierszu podąża za aktywnym trybem (punkty albo kraje), żeby kolejność listy i wyświetlana wartość zawsze się zgadzały.

**WAŻNE — wymaga jednorazowej ręcznej czynności usera przed użyciem**: pole `countries` w CloudKit Dashboard (icloud.developer.apple.com → kontener `iCloud.com.piotrmarkowski.pmemories` → Schema → `LeaderboardEntry`) NIE jest jeszcze oznaczone Queryable+Sortable — dokładnie ten sam jednorazowy krok co przy `score` 02.08.2026. Bez tego przełączenie na "Countries" w appce zwróci błąd CloudKit ("Field 'countries' is not marked queryable/sortable"). Do zrobienia zanim ten fragment aktualizacji trafi przed oczy testerów.

Build → **BUILD SUCCEEDED**, zainstalowane na iPhone. Wszystkie trzy punkty z tygodniowej listy quick-winów zamknięte (awatar, "Create memory again", sortowanie rankingu).

**Sezonowe wyzwania nad Rankingiem** — user: "jest ok lecimy z kolejnymi rzeczami", kolejny punkt z `TODO.md` (feedback 09.08.2026: "powód do wracania do appki nawet bez nowej podróży"). Nowy plik `SeasonalChallenge.swift` — czysto LOKALNE (bez CloudKit, to nie porównanie z innymi userami), dwa proste uczciwie policzalne cele liczone z już zapisanych `SavedTrip`/`SavedProject`: (1) odwiedź 1 NOWY kraj w tym sezonie (kraj już wcześniej odwiedzony PRZED sezonem się nie liczy), (2) stwórz 2 nowe Memories w tym sezonie. Karta pokazuje się nad "Your score" w `LeaderboardView`.

Reużyty istniejący `Season.current()` (z adaptacyjnych skórek teł, 02.08.2026) — dopisana nowa `Season.currentRangeStart(date:regionCode:)`: pierwszy dzień bieżącego meteorologicznego sezonu, z uwzględnieniem półkuli i rollovera roku dla zimy/lata na przełomie grudnia (styczeń/luty należą do sezonu zaczętego w grudniu POPRZEDNIEGO roku kalendarzowego). Dopisana też `Season.displayName` (dotąd `Season` miała tylko nazwę assetu tła).

Bug po drodze: pierwszy build się wywalił (`Cannot find type 'SeasonalChallenge' in scope`) — nowy plik utworzony przez narzędzie edycyjne nie trafił automatycznie do listy plików kompilowanych przez Xcode (projekt generowany przez XcodeGen z `project.yml`, źródło prawdy to system plików, ale `.xcodeproj` trzeba jawnie przeregenerować). Fix: `xcodegen generate` przed kolejnym buildem. **Zapamiętać na przyszłość: po KAŻDYM nowym pliku `.swift` (nie edycji istniejącego) uruchomić `xcodegen generate` zanim `xcodebuild`** — inaczej build fails z mylącym "cannot find type", które wygląda jak literówka, a jest tylko brakiem regeneracji projektu.

Build → **BUILD SUCCEEDED**, zainstalowane na iPhone. Zostało: spiąć w jeden spójny build razem z wcześniej gotowymi funkcjami (10 przejść, 5 filtrów, fix CloudKit Production, score-guard) i — dopiero po wyraźnym "wrzucamy na Apple" od usera — zarchiwizować/wysłać na TestFlight przed czwartkiem 14.08.

**Kategorie/tagi Memory poza podróżami** — kolejny punkt z `TODO.md` (feedback 09.08.2026), user: "jest ok lecimy z kolejnymi rzeczami". Nowy plik `MemoryCategory.swift` (enum: Family/Weekend/Birthday/Road Trip/Adventure/Life Moments, każda z ikoną SF Symbols) + `SavedProject.categoryRaw: String?` (nowe pole, `nil`-default zgodnie z konwencją lekkiej migracji) + computed `category: MemoryCategory?`.

`LibraryView.swift` — kategoria ustawiana ręcznie przez podmenu "Set Category" (`.contextMenu`, ten sam wzorzec co "Rename"/"Edit Date"), pokazywana jako dopisek w podtytule wiersza. Pasek filtra (chipy "All" + każda kategoria z ikoną) nad listą, widoczny TYLKO gdy przynajmniej jeden projekt ma ustawioną kategorię — appka nie zaśmieca UI filtrem którego nikt jeszcze nie użył. Świadomie BEZ auto-wykrywania kategorii — appka nie ma żadnego sygnału (data/lokalizacja/liczba osób) który pozwoliłby zgadnąć "to urodziny" bez ryzyka pomyłki, ta sama zasada zero-zgadywania co reszta appki.

Build → **BUILD SUCCEEDED**, zainstalowane na iPhone. Wszystkie cztery punkty z klastra feedbacku 09.08.2026 (sezonowe wyzwania, ranking wg krajów, "Create Memory again", kategorie Memory) teraz zamknięte.

**Ważna notatka na przyszłość — XcodeGen i nowe pliki**: potwierdzone drugi raz dziś (po `SeasonalChallenge.swift`), że `xcodegen generate` trzeba odpalić PRZED buildem za każdym razem gdy tworzony jest nowy plik `.swift` (nie dotyczy edycji istniejących plików). Ten krok wszedł już do standardowego rytmu pracy w tej sesji.

**Smart Route Detector — sprawdzenie odporności na bałagan (P2, TODO.md 10.08.2026)** — user wybrał ten punkt jako kolejny po zamknięciu czwórki quick-winów. Przegląd `SmartRouteDetector.swift` (73 linie) pod kątem dwóch scenariuszy z analizy konkurencji: zdjęcia bez lokalizacji GPS i podróże z wieloma krótkimi przystankami.

Zdjęcia bez lokalizacji: `MediaAssetLoader.locationsAndDates` po cichu POMIJA zdjęcia bez `asset.location` — uczciwe zachowanie (appka nie zgaduje pozycji), zgodne z resztą appki, brak akcji.

Znaleziony REALNY gap w drugim scenariuszu: zachłanne grupowanie porównywało każdy nowy punkt WYŁĄCZNIE z OSTATNIM klastrem, nie ze wszystkimi dotychczasowymi. Typowy wzorzec "baza + wycieczka jednodniowa + powrót" (np. Rzym → Tivoli → Rzym) tworzył TRZY osobne przystanki zamiast dwóch — powrót do Rzymu nie łączył się z pierwotnym klastrem Rzymu, bo porównanie szło tylko względem Tivoli. Dokładnie ten "bałagan" o który pytał punkt z TODO. Fix: każdy punkt szuka NAJBLIŻSZEGO pasującego klastra spośród wszystkich dotychczasowych (nie tylko ostatniego), scalanie do niego jeśli w promieniu 20km. Kolejność `tripStops` w tablicy zostaje wg momentu PIERWSZEGO powstania klastra (Rzym nadal pierwszy), więc chronologia trasy się nie psuje.

Build → **BUILD SUCCEEDED**, zainstalowane na iPhone. Nie ma na telefonie gotowych danych testowych z realnym wzorcem "baza + wycieczka + powrót" do ręcznej weryfikacji na żywo (jak przy World Globe 30.07) — poprawka zweryfikowana logicznie/przez czytanie kodu, nie na realnym urządzeniu z realną podróżą. Warto potwierdzić przy najbliższej okazji, gdy user faktycznie doda taką podróż.

**Diagnostyka Rankingu (08.08.2026, "user dalej nie widzi wyników innych") — POTWIERDZONE z prawdziwymi danymi.** Zamiast zgadywać, skonfigurowany `cktool` (CLI CloudKit od Apple, `xcrun cktool`) — user wygenerował Management Token I User Token w CloudKit Console (icloud.developer.apple.com → kontener → Settings → Tokens), oba zapisane lokalnie w Keychain przez `xcrun cktool save-token --type management|user`. **Ważne rozróżnienie odkryte po drodze**: Management Token służy TYLKO do operacji na schemacie/konfiguracji, `query-records` (odpytywanie realnych danych) wymaga User Token — pierwsza próba z Management Tokenem dała błąd "Session has expired or is invalid".

`xcrun cktool query-records --team-id X3NAM3PL95 --container-id iCloud.com.piotrmarkowski.pmemories --environment production --database-type public --record-type LeaderboardEntry` zwróciło DOKŁADNIE 2 rekordy: Piotr (725 pkt, 7 krajów, 29 miast, zaktualizowany 10.08) i Alexandra (90 pkt, 2 kraje, 2 miasta, dołączyła 08.08, ostatnia aktualizacja 09.08). Hipoteza z 08.08 potwierdzona — appka działa poprawnie, po prostu bardzo mało testerów dotarło do ekranu Ranking/zalogowało się przez Apple. Zero kodu do zmiany.

**Trwała wartość na przyszłość**: appka ma teraz działający, lokalnie skonfigurowany `cktool` z zapisanymi tokenami — kolejne pytania "co jest w CloudKit" można sprawdzić jednym poleceniem zamiast prosić usera o zrzuty ekranu z Dashboardu.

**Kadrowanie awatara + odznaka testera** — user: "mówiłem robimy wszystko :)", więc oba pozostałe punkty z sekcji "08.08.2026 — NIE zaczynać teraz" też dziś zamknięte (warunek usera "jak się więcej uzbiera" spełniony — cały dzisiejszy sprint).

Nowy `AvatarCropView.swift` — przeciąganie (`DragGesture`) + szczypanie (`MagnificationGesture`) w okrągłej ramce, `ProfileView` prezentuje go jako `fullScreenCover` zaraz po wyborze zdjęcia z `PhotosPicker`, PRZED zapisem do `AvatarStorage` (dawniej zapis szedł od razu, 1:1, bez pytania usera o kadr). Kluczowe, żeby nie wpaść w pułapkę z `feedback_crop_at_target_scale` (znaną z ikonki appki): crop liczony w PIKSELACH oryginalnego zdjęcia (`cgImage.cropping(to:)` z jawnym przeliczeniem punkty→piksele przez `pixelsPerPoint`), nie jako zrzut tego co widać na małym podglądzie ekranu.

Nowy `TesterRegistry.swift` — appka nie ma żadnego backendu/członkostwa TestFlight, więc zamiast budować nową infrastrukturę: ręcznie utrzymywana `Set<String>` znanych identyfikatorów Sign in with Apple. Identyfikatory wzięte WPROST z realnego `recordName` w dzisiejszym `cktool query-records` (ten sam identyfikator co `LeaderboardEntry.recordName` — potwierdzone w `LeaderboardService.submitCurrentScore`) — Piotr i Alexandra już tam są. Nowy tester = ręczne dopisanie po pierwszym zalogowaniu się w Rankingu. Odznaka: gwiazdka + obwódka gradientowa na awatarze w `ProfileView` (pełna wersja, 84pt) i mała gwiazdka w rogu w nagłówku `HomeView` (30pt, za mało miejsca na pełną odznakę).

Build → **BUILD SUCCEEDED**, zainstalowane na iPhone. Cała sekcja "08.08.2026 — feedback z testów" (3 punkty: awatar "P", kadrowanie, odznaka testera) teraz zamknięta.

**Koniec sesji 10.08.2026** — user: "na dziś tyle, jutro ruszamy z trip planning". Zamknięte dziś: 4 punkty z klastra feedbacku 09.08 (sezonowe wyzwania, ranking wg krajów, "Create Memory again", kategorie Memory), sprawdzenie/fix Smart Route Detector (P2), cała sekcja 08.08 (awatar "P", kadrowanie awatara, odznaka testera), diagnostyka Rankingu przez nowo skonfigurowany `cktool` (potwierdzone: tylko 2 realni testerzy, nie bug). Wszystko lokalnie zbudowane i zainstalowane na telefonie, NIC nie wysłane na TestFlight — czeka na wyraźne "wrzucamy na Apple" (`feedback_pmemories_versioning`).

**10.08.2026, ciąg dalszy — realny bug report od testera + brak tłumaczeń całego ekranu Ranking.** User przekazał zrzuty ekranu od testera: "Export failed" / "Operation Stopped" i osobno "ComposerError error 1" po tym jak tester odpowiadał na wiadomość w trakcie eksportu. Diagnoza z kodu (bez zgadywania): `EditView.performExport()` już wcześniej UCZCIWIE dokumentował ten limit — `beginBackgroundTask` daje appce tylko krótkie okno w tle, nie gwarancję. "Operation Stopped" to dokładnie to co AVFoundation zwraca gdy iOS przerywa `AVAssetExportSession` po wygaśnięciu tego okna.

Fix: `EditView` śledzi teraz `@Environment(\.scenePhase)` (nowa `exportBackgroundingWatcher`, wydzielona z głównego `body` — bezpośrednie dopisanie `.onChange` do łańcucha modyfikatorów znów przekroczyło limit czasu type-checkera, ten sam nawracający błąd co wcześniej w tym pliku). Jeśli appka zejdzie z pierwszego planu W TRAKCIE eksportu (`isExporting == true`), `wasBackgroundedDuringExport` się ustawia; jeśli eksport potem faktycznie się nie powiedzie, user widzi zrozumiały komunikat ("Export was interrupted because PMemories left the foreground...") zamiast surowego kodu AVFoundation. Inne, niezwiązane błędy eksportu nadal pokazują prawdziwy `error.localizedDescription`.

Przy tej samej okazji user przesłał zrzut ekranu z telefonu ustawionego na polski — **cały ekran Ranking (Leaderboard/Points/Sort by/Challenge/Complete!/kategorie Memory/itd.) wyświetlał się po angielsku mimo polskiego języka appki**. Przyczyna: te stringi nigdy nie trafiły do `Localizable.xcstrings` — `L()` bez wpisu w katalogu po cichu pokazuje angielski klucz zamiast tłumaczenia, żaden błąd kompilacji tego nie złapie. Dotyczyło całego ekranu Ranking (nigdy niedotknięty podczas Etapu 1-3 lokalizacji, bo powstał 02.08, już po tamtych etapach) PLUS wszystkiego dodanego dziś (sezonowe wyzwania, kategorie Memory, kadrowanie awatara, "Create memory again"). Naprawione jednym przebiegiem: 31 brakujących kluczy × 27 języków = 837 tłumaczeń dopisanych do `Localizable.xcstrings` (skrypt Python, `add_translations.py`, żeby nie edytować 44-tysiąclinijkowego JSON-a ręcznie). **Zapamiętać na przyszłość: każda NOWA funkcja z tekstem widocznym dla usera potrzebuje przebiegu tłumaczeń w TYM SAMYM kroku, nie później — dziś umknęło to przy Rankingu (02.08) i przy całej dzisiejszej ósemce, złapane dopiero na realnym zrzucie ekranu testera.**

Przy okazji: pasek postępu "Zapisywanie..." przy eksporcie animacji Travel Map (`TravelMapAnimationView.swift`) poprawiony na bardziej wyraźny — user: "pasek download z mapy musi być bardziej wyraźny". Wypełnienie 0.28 opacity białego na pomarańczowym `Palette.accent` było prawie niewidoczne; podniesione do 0.55 + dodana jasna 3pt krawędź na końcu wypełnienia.

Build → **BUILD SUCCEEDED**, zainstalowane na iPhone.

**10.08.2026, ciąg dalszy — prawdziwa przyczyna przygaszonego paska + brakująca blokada wygaszania ekranu.** User przesłał świeży zrzut ekranu z zainstalowanego builda — pasek "Zapisywanie... 6%" WCIĄŻ wyglądał blado mimo wcześniejszej poprawki opacity wypełnienia. Prawdziwa przyczyna (przegląd kodu, nie zgadywanie): `.disabled(isSaving)` na przycisku w `TravelMapAnimationView.swift` — SwiftUI automatycznie przyciemnia CAŁĄ zawartość `Button`a gdy jest `.disabled()`, nawet z `.buttonStyle(.plain)` i czysto własną zawartością (`Palette.accent`, `Label`) — stąd "mapa przeświecająca przez pasek" niezależnie od opacity samego wypełnienia. Fix: `.allowsHitTesting(!isSaving)` zamiast `.disabled(isSaving)` — blokuje dotknięcia (ten sam cel) bez dotykania `\.isEnabled`, więc bez przyciemnienia.

Przy tej samej okazji user zapytał wprost: "możemy dodać żeby trzymać aplikację włączoną... czy możemy wstrzymać telefon przed wyłączeniem się na czas ściągnięcia albo tworzenia filmu?" — sprawdzone w kodzie: `isIdleTimerDisabled` (blokada auto-wygaszania ekranu) była JUŻ ustawiona w obu miejscach EKSPORTU (`EditView.performExport`, `TravelMapAnimationView.saveVideo`), ale BRAKOWAŁO jej w fazie ŁADOWANIA/ściągania zdjęć z iCloud PRZED eksportem — `HomeView.loadSelection` (pierwsze tworzenie Memory) i `EditView.addMore` (Add Media w trakcie edycji). Dopisane w obu miejscach, ten sam wzorzec (`UIApplication.shared.isIdleTimerDisabled = true` + `defer` przywracające `false`).

Build → **BUILD SUCCEEDED**, zainstalowane na iPhone.

**10.08.2026, ciąg dalszy — build 6 wysłany na TestFlight.** User: "po tym wszystkim możemy cały update wrzucić na testflight" — pierwszy upload od buildu 5 (02.08.2026), zbiera CAŁY dzisiejszy sprint (sezonowe wyzwania, ranking wg krajów, "Create memory again", kategorie Memory, kadrowanie awatara, odznaka testera, Smart Route fix, czytelny błąd przerwanego eksportu, 837 tłumaczeń w tym cały Ranking, wyraźniejszy pasek "Zapisywanie" + prawdziwa naprawa `.disabled()`, blokada wygaszania ekranu przy ściąganiu z iCloud) plus wcześniej gotowe funkcje (10 przejść, 5 filtrów, fix CloudKit Production, score-guard).

Autoryzacja do App Store Connect: user zdecydował się na app-specific password (nie klucz API — ten wątek zostawiony na później, `~/.appstoreconnect/private_keys/` gotowy na przyszłość jeśli user go dokończy). `CFBundleVersion` podbite z 5→6 (`Info.plist`, `CFBundleShortVersionString` zostaje 1.0.1). Cykl: `xcodebuild archive` (Release, `build/PMemories_build6.xcarchive`) → `xcodebuild -exportArchive` (`build/ExportOptions.plist` z buildu 5, wciąż aktualny) → `xcrun altool --upload-app`. **UPLOAD SUCCEEDED**, Delivery UUID `103c1019-507a-42be-b179-ddbd1e538eb1`.

Zostało: poczekać aż Apple przetworzy build 6, ewentualnie zaktualizować "What to Test" w App Store Connect o dzisiejszą listę zmian, sprawdzić czy testerzy dostają powiadomienie automatycznie (Internal) czy trzeba czekać na Beta App Review (External, jeśli tacy testerzy są skonfigurowani).

## 11.08.2026 — build 6 zaakceptowany, start pracy nad Update 1.0.2 (lokalnie, do czwartku)

User potwierdził: build 6 przeszedł przetwarzanie w App Store Connect (wcześniejsze "nie mogę wybrać" w oknie "Select a Build to Test" to było zwykłe oczekiwanie na przetworzenie po stronie Apple, nie błąd appki). Ustalony rytm na ten tydzień: **wszystko budujemy i instalujemy TYLKO lokalnie, dopiero w czwartek 14.08 zbiorczo wrzucamy na Apple jako Update 1.0.2** — nie po każdej pojedynczej zmianie jak wcześniej.

**Rozmiar napisu "Mapa Podróży" zmniejszony** — user: "wydaje mi się że napis mapa podróży jest trochę za duży" — `TravelMapView.swift`, 34pt→26pt (ten sam duch co zmniejszenie powitania na Home 30.07.2026).

**Kolejna runda brakujących tłumaczeń znaleziona przy okazji** (ten sam zrzut ekranu pokazał "Add peak from my location" po angielsku) — usystematyzowany audyt (skrypt Python: regex po `Text(`/`Button(`/`Label(`/`L(` w plikach Travel/Studio, porównanie z kluczami w katalogu) złapał 5 kolejnych realnych braków: "Add peak from my location", "Finding nearby peak…" (funkcja wykrywania szczytu, 01.08.2026 — powstała PO ostatnim pełnym przebiegu tłumaczeń), "Your travel video has been saved to your camera roll." (treść powiadomienia po zapisie mapy), "min" (skrót minut w szacowanym czasie eksportu), opis skórek w `TemplatesView`. Świadomie POMINIĘTE: "Aa" w wyborze czcionki napisów (`CaptionsView`) — to podgląd alfabetu w danej czcionce, nie sensowny tekst do tłumaczenia. Dopisane: 135 tłumaczeń (5 kluczy × 27 języków), drugi skrypt `add_translations2.py`.

Build → **BUILD SUCCEEDED**, zainstalowane na iPhone lokalnie (bez uploadu — czekamy na czwartek).

**Ten sam zrzut ekranu, kolejna runda** — dwie kolejne rzeczy złapane na jednym screenie ekranu Home:

1. Brakujące tłumaczenie: "Where are we travelling today?" (jeden z losowanych wariantów powitania) było po angielsku mimo polskiego — dopisane, razem z drugim wariantem tego samego mechanizmu ("Ready to create another memory?"), który nie był jeszcze widoczny na zrzucie ale jest tym samym przypadkiem.

2. **Zła polska odmiana liczebnikowa** — karta "Twoja podróż" pokazywała "7 Kraje • 8 Podróże" zamiast poprawnego "7 Krajów • 8 Podróży". Polski ma TRZY formy liczby mnogiej (1 kraj / 2-4 kraje / 5+ krajów), angielski (i dotychczasowy prosty wzorzec `L("Countries")`/`L("Trips")` appki) tylko dwie — appka pokazywała zawsze TĘ SAMĄ formę niezależnie od liczby. Naprawione TYLKO dla polskiego (`HomeView.polishPlural`, reguła mod10/mod100, `isPolishActive` przez `Bundle.main.preferredLocalizations.first == "pl"` — świadomie NIE `AppLanguage.current`, bo ten zwraca `.system` gdy user nigdy ręcznie nie wybrał języka w Profile, co jest normalnym stanem dla większości testerów polegających na domyślnym języku systemu) — pozostałe 26 języków mają dalej uproszczony, dwuwariantowy wzorzec jak dotąd. **Świadomie NIE pełny system ICU plural (Xcode String Catalog "variations")** — appka nigdzie indziej tego nie używa, a wprowadzenie nowego mechanizmu tylko w jednym miejscu byłoby niespójne; to zapisany, większy temat na później jeśli user zechce systematycznie to zrobić dla wszystkich języków/miejsc.

Build → **BUILD SUCCEEDED**, zainstalowane na iPhone lokalnie.

**Pełny audyt WSZYSTKICH tłumaczeń w kodzie** — user: "przejrzyj w kodzie wszystkie tłumaczenia i czy są jakieś braki we wszystkich językach". Napisany skrypt Python skanujący WSZYSTKIE pliki `.swift` (regex po `Text(`/`Button(`/`Label(`/`L(`/`navigationTitle(`/`Section(`/`Picker(`/`DatePicker(`/`TextField(`/`SecureField(`/`.alert(`/`.confirmationDialog(`/`ToolbarItem(`/`Toggle(`), porównujący każdy znaleziony literał z kluczami w `Localizable.xcstrings` — DWA razy (raz węższym, raz szerszym zestawem wzorców, żeby nie polegać na jednym zestawie założeń) i sprawdzający też, czy istniejące klucze mają KOMPLETNE tłumaczenia we wszystkich 27 językach (nie tylko czy klucz w ogóle istnieje).

Wynik: **0 kluczy częściowo przetłumaczonych** (wszystko co już było w katalogu — łącznie z dzisiejszymi wcześniejszymi paczkami — miało komplet 27 języków, żadnych "dziur" w środku). Znalezione i dopisane 10 NOWYCH brakujących kluczy: nazwy 9 skórek teł (`AppSkin.swift` — "Beach"/"Mountains"/"City Lights"/"Forest Waterfall"/"Starry Night"/"Tropical Lagoon"/"Desert Dawn"/"Default (no skin)"/"Seasonal" — nigdy wcześniej nieprzetłumaczone, mimo że funkcja istnieje od 02.08.2026) + "Sign in with Apple failed. Please try again." + "Traveler" (fallback nazwy usera w `AuthManager.swift`). 297 tłumaczeń dopisanych (11 kluczy × 27 języków, `add_translations4.py`).

Świadomie POMINIĘTE jako fałszywe trafienia / niepotrzebne do tłumaczenia: "Aa" (podgląd czcionki, uniwersalny), "P"/"M"/"emories"/"lay " (fragmenty brandingu "PMemories"/"PlayMemories" w Home/Library — nazwa marki, NIE tłumaczy się), "✦"/"✨" (dekoracyjne błyski przy "Create Memory"), emoji 🌍/📅/🛂/🧭 (dekoracyjne ikonki, nie tekst).

Build → **BUILD SUCCEEDED**, zainstalowane na iPhone lokalnie. **Stan na 11.08.2026: kompletny, systematycznie zweryfikowany katalog tłumaczeń — 0 znanych braków w kodzie appki** (poza świadomie pominiętymi elementami brandingowymi/dekoracyjnymi). Nadal PRAWDZIWY, osobny temat: 26 z 27 języków ma tłumaczenia generowane przez AI, nigdy wizualnie niezweryfikowane na urządzeniu (tylko polski jest na bieżąco testowany na żywo) — oraz zapisany wcześniej backlog pełnej obsługi ICU plural rules.

**Eksperyment: wolniejszy eksport mapy dla trasy autem/pociągiem** — user zauważył że zapisywanie mapy wydłuża się wyraźnie dla trasy autem/pociągiem, zapytał dlaczego GPS działa płynnie a to nie, i czy dałoby się obniżyć jakość dla tych środków transportu żeby przyspieszyć.

Diagnoza (bez zgadywania — ISTNIEJĄCY profiler `📊 Travel Export Profile`, `print()` w `TravelMapVideoRenderer.swift`, potwierdzony wcześniej 03.08.2026): dla trasy lądem/wodą **85-90% czasu eksportu to czekanie na kafelki MapKit**, bo kamera samochodu/pociągu/wędrówki/łodzi/rejsu PRZESUWA SIĘ za pojazdem (nowe kafelki na każdym kroku) — w przeciwieństwie do lotu, gdzie kamera głównie zoomuje w tym samym miejscu (te same kafelki, mniej nowych pobrań). To nie problem złej implementacji, tylko fundamentalnie innej ilości pracy sieciowej. GPS jest płynny bo renderuje live TYLKO to co na ekranie w niższej jakości — nasz eksport musi wyrenderować KAŻDĄ klatkę gotowego pliku bez wyjątków.

Sprawdzone też: appka NIE trzyma własnego trwałego cache kafelków między eksportami — polega wyłącznie na wbudowanym cache MapKit (współdzielonym systemowo między wszystkimi `MKMapView`, już wykorzystywanym przez `MapTilePrefetcher`), więc dodatkowy cache appki miałby ograniczoną dodatkową wartość. Bundlowanie map offline (jak w GPS-ach) odrzucone jako pomysł — appka nie wie z góry dokąd user pojedzie, pełne pokrycie świata to setki GB.

**Wdrożony eksperyment**: `effectiveCaptureInterval` (co który krok appka robi PRAWDZIWE zdjęcie mapy zamiast ponownie użyć ostatniego) przeniesiony z jednej wartości na CAŁĄ trasę na wartość PER-ODCINEK, o jeden krok rzadszą dla lądu/wody (car/train/hiking/boat/cruise) — loty bez zmian (i tak już szybkie). Ten sam, już wcześniej zaakceptowany kompromis co historyczny `captureInterval: 2` dla motywu Satellite (drobne "cięcia" w zamian za czas), tylko teraz zależny od środka transportu, nie tylko motywu mapy.

**Do zweryfikowania na urządzeniu, nie samą teorią** — zainstalowane lokalnie, build 12:05. User powinien wyeksportować realną trasę z autem/pociągiem i sprawdzić: (a) subiektywnie czy zauważalnie szybciej, (b) czy przejścia kamery są dalej akceptowalnie płynne (nie za bardzo "poszarpane"). Mogę też strumieniować konsolę (`devicectl device process launch --console`) w trakcie Twojego eksportu, żeby złapać dokładny wydruk profilera z realnymi liczbami przed/po — dokładniejsze niż samo wrażenie.

## 11.08.2026, ciąg dalszy — Trip Planning ("My Next Journey") Etap 1

User: "travel planing jest na teraz" — start budowy P1 z listy priorytetowej 10.08.2026 (największa realna luka: appka dotąd silna TYLKO "po podróży"). Zaplanowane przez `EnterPlanMode` z 2 rundami eksploracji kodu (`Explore` agent x2 — struktura paska/Profile/Templates, wzorce SwiftData/lokalizacji), user potwierdził 2 decyzje przez `AskUserQuestion`: struktura planu = lista przystanków (nie jedno pole notatek, bo naturalnie konwertuje się w `TripStop`), appka trzyma LISTĘ wielu planowanych podróży (nie tylko jedną).

**Nowy model** — `PlannedTripPersistence.swift`: `PlannedTrip`/`PlannedStop`, OSOBNY od `SavedTrip`/`SavedStop` (te zakładają że podróż już się odbyła — dystans/wysokość liczone przez `RouteProvider`/`ElevationProvider` PRZY ZAPISIE). Ten sam wzorzec pól co `TripPersistence.swift` (współrzędne jako dwa `Double` + computed `coordinate`, wartości domyślne na każdym polu dla bezpiecznej migracji SwiftData, `@Relationship(deleteRule: .cascade)`). `PlannedStop.notes: String` — loty/hotele/plany jako wolny tekst, świadomie NIE ustrukturyzowane (nie kopiujemy TripMapory 1:1). Dodane do `Schema([...])` w `PMemoriesAppApp.swift`.

**Nowy ekran** — `TripPlanningView.swift`: lista `@Query` po `PlannedTrip` (pusty stan + "+"), edytor (`PlannedTripEditorView`) z tytułem, listą przystanków (`PlannedStopRow` — reużywa `CitySearchCompleter` 1:1 z `TravelMapView`'s `StopRow`, ten sam wzorzec podpowiedzi miast i opcjonalnej daty), notatkami, i przyciskiem **"Convert Trip → Memory"** — mapuje `PlannedStop`→`TripStop` (`PlannedTrip.asTripStops`, ten sam wzorzec co `SavedTrip.asTripStops`), przełącza na zakładkę Travel z gotowym szkicem trasy, USUWA plan (konwersja jednorazowa, podróż żyje dalej jako normalna trasa w Travel Map).

**Zmiany w istniejących plikach**:
- `TravelMapView.swift` — nowy custom `init` z `pendingPrefillStops: Binding<[TripStop]?>` (ten sam wzorzec co `pendingShowWorldGlobe`) — `_stops = State(initialValue: pendingPrefillStops.wrappedValue ?? [TripStop(), TripStop()])`, czyszczone w `.onAppear` po skonsumowaniu.
- `HomeView.swift` — `MainTab.templates` → `.tripPlanning`, ikona paska `square.grid.2x2`→`airplane.departure`, nowy `@State pendingTravelMapPrefillStops` łączący obie zakładki.
- `ProfileView.swift` — Templates przeniesione tu jako `NavigationLink` (nowa Section) — `TemplatesView` nie miała własnego `NavigationStack`/tytułu, wpięła się bez adaptacji.

**Lokalizacja** — 15 nowych kluczy × 27 języków = 405 tłumaczeń (`add_translations5.py`). Przy tej okazji złapany i naprawiony BUG we WŁASNYM skrypcie audytowym z wcześniejszych przebiegów dziś: `\b` przed `\.alert(`/`\.confirmationDialog(` w regexie nie dopasowywał się (kropka nie jest znakiem słowa, `\b` wymaga przejścia \w↔\W po OBU stronach) — więc tytuły alertów mogły być cicho pomijane we WSZYSTKICH wcześniejszych audytach dzisiaj. Poprawiony regex + ponowny pełny skan całej appki: znaleziony tylko JEDEN dodatkowy przeoczony klucz ("Convert to Memory?", z tego samego Trip Planning) — reszta appki okazała się czysta, potwierdzone nie zgadywaniem.

Build → **BUILD SUCCEEDED za pierwszym razem** po dodaniu wszystkich nowych plików (jeden drobny fix: `#Preview` w `TravelMapView.swift` wołający stary sygnaturę initu). Zainstalowane lokalnie (bez uploadu — czekamy na czwartek 14.08, Update 1.0.2).

**Etap 1 zamknięty.**

## 11.08.2026, ciąg dalszy — Trip Planning: rewizja modelu (Accommodation, daty pobytu, Places to visit)

Zaraz po Etapie 1 user przesłał obszerny, bardzo przemyślany feedback (research konkurencji + własny projekt UX) o tym jak model Trip Planning powinien wyglądać, żeby NIE trzeba było go później przebudowywać. Zaplanowane przez `EnterPlanMode` (drugi raz dziś dla tej samej funkcji — user: "skoro teraz robisz Travel Planning, to warto od początku zaprojektować to tak, żeby później nie trzeba było przebudowywać całego modułu"), 2 potwierdzenia przez `AskUserQuestion`: zakres v1 = dokładnie lista usera (Trip/Destinations/Accommodation/Transport/Places to visit/Notes), przypomnienia o płatnościach → zapisane w TODO, NIE budowane teraz (wymaga `UNUserNotificationCenter`, ten sam duch co wcześniej odłożone powiadomienia push).

**Kluczowa uwaga usera wykorzystana do decyzji**: nikt jeszcze nie ma zapisanych prawdziwych planów (funkcja istnieje od kilkunastu minut) — bezpieczny, ostatni moment na zmianę modelu bez migracji.

**Zmiany modelu** (`PlannedTripPersistence.swift`, przepisany): `PlannedTrip` dostał `tripDescription` (NIE `description` — kolizja z `NSObject.description`, `@Model` mostkuje do Core Data), `startDate`/`endDate` + computed `nightsAndDaysText`. `PlannedStop`: `plannedDate` zastąpione parą `checkInDate`/`checkOutDate` + computed `nights`, nowe `accommodationRawValue`/`accommodationCustomLabel`, nowa relacja `placesToVisit: [PlaceToVisit]` (cascade). Nowe typy: `AccommodationType` (Hotel/Airbnb/Vacation rental/Hostel/Camping/Staying with family-friends/My home/Other — user: "jeden uniwersalny element, dopiero wewnątrz user wybiera typ"), `PlaceVisitStatus` (Must see/Want to visit/Visited), `@Model PlaceToVisit`. `PlaceToVisit.self` dodany do `Schema`.

**Zmiany UI** (`TripPlanningView.swift`, przepisany): nowy reużywalny `OptionalDateField` (wydzielony z Etapu 1's inline wzorca — teraz potrzebny w 4 miejscach zamiast 1: daty całej podróży + check-in/check-out per przystanek). `PlannedTripEditorView` — sekcja "Trip dates" z auto-liczonymi nocami/dniami, pole opisu. `PlannedStopRow` — świadomie ROZBITE na osobne `@ViewBuilder` (cityField/transportPicker/accommodationSection/stayDatesSection/placesToVisitSection/notesField), bo po dodaniu tylu elementów jeden `VStack` zacząłby ryzykować nawracający dziś błąd type-checkera. `stayDatesSection` ukryte CAŁKOWICIE dla "My home" (user chwalił dokładnie ten case: "at home i koniec", appka nie pyta o daty pobytu we własnym domu). `placesToVisitSection` — mini-lista z dodawaniem/usuwaniem/statusem (Menu z emoji).

**Przy okazji naprawiona TA SAMA pułapka co "7 Kraje" na Home** — user w swoim przykładzie sam napisał "15 nights", a `nights`/`nightsAndDaysText` groziły dokładnie tym samym błędem (angielski wzorzec liczby mnogiej, zły dla polskiego 5+). Wyciągnięty `isPolishLanguageActive`/`polishPlural` z `HomeView.swift` do wspólnego `LocalizedString.swift` (były prywatne, zduplikowane gdyby zostały) — HomeView zrefaktoryzowany żeby korzystał ze wspólnej wersji, `PlannedTripPersistence.swift`/`TripPlanningView.swift` też.

**Lokalizacja** — 28 nowych kluczy × 27 języków = 756 tłumaczeń (`add_translations6.py`). Pełny końcowy skan całej appki (poprawionym regexem z dzisiejszej wcześniejszej naprawy) potwierdził zero nowych braków poza znanymi, świadomymi pominięciami (branding/dekoracje/podgląd czcionki).

Build → **BUILD SUCCEEDED**, zainstalowane lokalnie.

**Świadomie NIE zrobione w tym etapie (zapisane w `TODO.md`)**: Budget, Reservations (numer potwierdzenia/PDF/link), day-by-day itinerary jako osobny widok, "Travelling with", przypomnienia o terminach płatności (wymaga infrastruktury powiadomień).

## 11.08.2026, ciąg dalszy — dwa realne bugi zgłoszone przez usera na żywo

**"Nie możemy edytować nowej podróży"** — realny bug, nie zgadywanie: uruchomiona konsola na żywo (`devicectl --console`) w trakcie reprodukcji przez usera, brak crasha w logach — cichy błąd nawigacji SwiftUI, nie awaria. Diagnoza z kodu: `addTrip()` w `TripPlanningView.swift` robił `modelContext.insert(trip)` (zmienia `plannedTrips`, przełączając `Group` z `emptyState` na `list` przy PIERWSZEJ podróży) i `editingTrip = trip` (odpala `.navigationDestination`) w TEJ SAMEJ synchronicznej klatce — SwiftUI gubi się gdy struktura widoku pod `NavigationStack` zmienia się w tym samym cyklu co próba wepchnięcia nowego celu nawigacji. Fix: `editingTrip` ustawiane w następnym cyklu (`DispatchQueue.main.async`), żeby przełączenie `emptyState`→`list` zdążyło się najpierw w pełni odłożyć.

**"13 loty nie wygląda poprawnie gramatycznie"** — user złapał DRUGĄ instancję tej samej pułapki co wczorajsze "7 Kraje" (naprawione dziś rano dla Countries/Trips na karcie "Twoja podróż") — "Cities"/"Flights" w TEJ SAMEJ rotującej karcie miały dokładnie tę samą wadę, po prostu nieprzetestowane wcześniej bo user nie miał jeszcze wystarczająco dużo lotów w danych żeby zobaczyć liczbę 5+. Dopisane `citiesLabel(_:)`/`flightsLabel(_:)` w `HomeView.swift`, ten sam wzorzec `polishPlural` co `countriesLabel`/`tripsLabel`. Sprawdzone: "Hiking"/"km travelled" w tej samej karcie NIE mają tego problemu (to nie zdania "N rzeczownik", tylko "X km + stała etykieta" — km się nie odmienia). Sekcja "Lifetime stats" (pionowa lista "Kraje / Miasta / Loty" z wartością OBOK, nie "N Kraje" w jednym zdaniu) też nie ma tego problemu — inna konstrukcja gramatyczna.

**Warto zapamiętać na przyszłość**: przy KAŻDEJ nowej liczbie+rzeczowniku pokazywanym po polsku warto od razu sprawdzić wszystkie TRZY progi (1/2-4/5+), nie tylko przetestować z małą liczbą — błąd ujawnia się dopiero przy 5+.

Build → **BUILD SUCCEEDED** (oba fixy razem), zainstalowane lokalnie.

**Systematyczny przegląd całej appki pod kątem tej samej wady** — user zapytał wprost "możemy sprawdzić czy gramatyka też się zgadza". Grep po wzorcu `\(count) \(L("..."))` w całym kodzie znalazł jeszcze DWA realne przypadki (poza już naprawionymi): `TripPersistence.swift` (`SavedTrip.subtitle`, "\(countryCount) countries") i `LeaderboardView.swift` (wiersz rankingu, "X km · Y countries · Z cities") — oba naprawione tym samym wzorcem. Sprawdzone i POTWIERDZONE BEZPIECZNE (nie tego typu błąd): "km travelled"/"Hiking"/"pts"/"badges unlocked"/"lap" — to stałe frazy-przyrostki albo dopełniacz liczby mnogiej niezmienny względem liczby ("X / Y odznak"), nie zdania "N rzeczownik" jak Countries/Trips/Cities/Flights.

Build → **BUILD SUCCEEDED**, zainstalowane lokalnie. Cztery miejsca z tą wadą zamknięte dziś: Home (Countries/Trips/Cities/Flights), Ranking (countries/cities), podtytuł zapisanej podróży (countries).

**Następna sesja zaczyna się od dalszego rozwoju/testów Trip Planning** — P1 z listy priorytetowej 10.08.2026, jedyny większy niezaczęty temat po dzisiejszym sprincie. Szkic z `TODO.md`: nowy ekran "My Next Journey" (kraj, daty, loty/hotele/miejsca jako proste notatki, NIE pełny planer budżetu/waluty), kluczowa klamra "Convert Trip → Memory" po powrocie łącząca nowy moduł z tym co appka już robi najlepiej.

## 11.08.2026, ciąg dalszy — Trip Planning: dopracowanie po pierwszym realnym obejrzeniu

User zobaczył cały ekran na żywo pierwszy raz ("Aaa, teraz widzę całość") i pochwalił kierunek (przystanki jako fundament), po czym dał kolejną rundę konkretnego, węższego feedbacku — świadomie NIE przebudowa UI, user wprost: "nie przebudowywałbym teraz całego UI... Skupiłbym się na dopracowaniu noclegów + miejsc do odwiedzenia + edycji przystanków". Zrobione dokładnie to, reszta (auto-sugerowane daty z zakresu podróży, rozszerzone środki transportu, numer lotu/godzina, Places to visit→Explorer Score) świadomie odłożona, dopisana do `TODO.md`.

**`PlannedTripPersistence.swift`**: `accommodationCustomLabel` → `accommodationName` (używane teraz dla WSZYSTKICH typów noclegu, nie tylko "Other" — user: "adres i nazwa powinny być opcjonalne" dla każdego typu), nowe pole `accommodationAddress: String?`. Nowy computed `PlannedTrip.looksCompleted: Bool` (najpóźniejsza znana data — koniec podróży albo najpóźniejszy check-out/check-in przystanku — w przeszłości; `false` gdy appka nie zna żadnej daty, zero zgadywania).

**`TripPlanningView.swift`**: przycisk Convert dynamiczny — user: "bardzo fajna możliwość", "to zostawiłbym zdecydowanie" — pokazuje "✨ Create Memory from this trip" gdy `trip.looksCompleted`, inaczej zwykłe "Convert Trip → Memory" jak dotąd. `accommodationSection` — pola nazwa/adres pokazywane teraz dla KAŻDEGO typu noclegu poza "My home" (wcześniej tylko dla "Other"). `placesToVisitSection` dostała nagłówek "📍 Miejsca do odwiedzenia" (user: nazwa "miejsce" była niejasna bez kontekstu).

**`HomeView.swift`** — `flightsLabel(_:)` rozszerzone o "odbyty/odbyte/odbytych" (user: "co do Lotów można dodać że odbytych, czyli teraz będzie 13 lotów odbytych") — jaśniejsze niż samo "13 lotów" (odbytych vs zaplanowanych w Trip Planning, appka ma teraz oba znaczenia lotu w różnych miejscach).

**Lokalizacja** — 4 nowe klucze × 27 języków = 108 tłumaczeń (`add_translations7.py`): "Accommodation name (optional)", "Address (optional)", "Places to visit", "✨ Create Memory from this trip".

Build → **BUILD SUCCEEDED**, zainstalowane lokalnie na telefonie.

## 11.08.2026, ciąg dalszy — wysyłanie zaplanowanej podróży (Share/Import)

User: "musimy mieć możliwość wysłania do kogoś zaplanowanej wycieczki żeby nie trzeba było wpisywać jak ktoś ma stworzone i leci z tobą". Rozważone dwie opcje, user wybrał prostszą: plik przez natywny Share Sheet (AirDrop/Wiadomości/Poczta) zamiast `CKShare` (live współdzielenie z zarządzaniem uczestnikami, dużo więcej pracy i innego typu potrzeba — user chce jednorazową kopię, nie stały link do tej samej podróży).

**Nowy plik `PlannedTripTransfer.swift`**: własny `UTType` (`com.piotrmarkowski.pmemories.trip`, rozszerzenie `.pmtrip`, zgodny z `public.json`). `TripTransferDTO`/`StopTransferDTO`/`PlaceTransferDTO` — proste `Codable` DTO równoległe do `PlannedTrip`/`PlannedStop`/`PlaceToVisit` (SwiftData `@Model` nie jest wprost `Codable`/`Transferable`). `TripTransferDTO: Transferable` przez `DataRepresentation(exportedContentType: .pmemoriesTrip)` + `.suggestedFileName` — `ShareLink` sam generuje plik na żądanie, bez ręcznego zarządzania plikiem tymczasowym. `PlannedTrip.transferDTO` (eksport) i `TripTransferDTO.makePlannedTrip()` (import) — import ZAWSZE tworzy nową, niezależną kopię (brak `id`/relacji nadawcy), świadomie bez scalania z istniejącymi podróżami.

**`project.yml`** — `UTExportedTypeDeclarations` + `CFBundleDocumentTypes` (żeby plik `.pmtrip` otwierał się w PMemories z Wiadomości/AirDrop/Poczty, "Open in PMemories"), `LSSupportsOpeningDocumentsInPlace: true`. Wymagało `xcodegen generate` (nowy plik `.swift`, znany wcześniej dzisiaj wymóg).

**`TripPlanningView.swift`** — `ShareLink` w toolbarze `PlannedTripEditorView` (ikona `square.and.arrow.up`, `SharePreview` z tytułem podróży), wyłączony dopóki wszystkie przystanki są puste (jak przycisk Convert).

**`HomeView.swift`** — `.onOpenURL` (na `NavigationStack`) odbiera plik `.pmtrip`, dekoduje, wstawia nową `PlannedTrip` do `modelContext`, przełącza na zakładkę Trip Planning, pokazuje alert "Trip imported" z nazwą — albo alert błędu przy uszkodzonym/niepoprawnym pliku (np. plik nie od PMemories).

**Lokalizacja** — 5 nowych kluczy × 27 języków = 135 tłumaczeń (`add_translations8.py`): "Trip", "Trip imported", "Untitled trip", "Couldn't import trip", "\"%@\" was added to Trip Planning."

Build → **BUILD SUCCEEDED** (dwa przebiegi — pierwszy zanim dodano brakujące tłumaczenia, potem finalny), zainstalowane lokalnie na telefonie. **Do przetestowania przez usera**: wysłać podróż do siebie (np. przez AirDrop na Maca i z powrotem, albo Wiadomości do drugiego telefonu) i sprawdzić czy import faktycznie działa na prawdziwym urządzeniu — nie testowane jeszcze end-to-end, tylko build+install.

## 11.08.2026, ciąg dalszy — podgląd vs edycja podróży (osobne tryby)

User: "nie mogę edytować stworzonej podróży, muszę usunąć bo nie da się nic z tym zrobić — do tego powinien być normalny podgląd tego co się ma zapisane, edycja wygląda jak ekran który wypełniamy na początku, podgląd powinien wyglądać ładnie przejrzyście z tymi informacjami które mamy wpisane". Diagnoza z kodu (nie tylko zgadywanie): tapnięcie w ISTNIEJĄCĄ podróż z listy zawsze prowadziło do TEGO SAMEGO formularza wypełniania co przy tworzeniu nowej — brak jakiegokolwiek "trybu podglądu", więc otwarcie zapisanej podróży wyglądało identycznie jak pusty ekran startowy, myląco sugerując że nic się nie zapisało / nie da się tym zarządzać.

**`TripPlanningView.swift` przebudowany**: `PlannedTripEditorView` zastąpiony przez `PlannedTripDetailView` — JEDEN ekran, DWA tryby (`isEditing` `@State`):
- **Podgląd** (`summaryView`, domyślny dla ISTNIEJĄCYCH podróży) — opis, zakres dat (`nightsAndDaysText`, z sensownym fallbackiem "From %@"/"Until %@" gdy user ustawił tylko JEDNĄ datę), karta na każdy przystanek (`StopSummaryCard`, nowy prywatny widok) pokazująca czytelnie WSZYSTKO co zapisane: miasto+ikona transportu, nocleg (emoji+typ+nazwa+adres jeśli wypełnione), liczba nocy, notatki, miejsca do odwiedzenia — plus przycisk Convert/Create Memory na dole (przeniesiony tu z edytora, bo to naturalne miejsce na "finalną akcję" gdy user PRZEGLĄDA gotową podróż).
- **Edycja** (`editForm`, bez zmian w mechanice) — dotychczasowy formularz wypełniania, teraz wchodzi się w niego świadomie przez ✏️ w pasku (albo automatycznie dla NOWO tworzonej pustej podróży — `startInEditMode`, liczone w `TripPlanningView` z zawartości triposu: pusty tytuł + wszystkie przystanki bez miasta = na pewno nowa, podgląd pustego formularza nie miałby sensu).

Przycisk ✏️ (Edit) i Share (`square.and.arrow.up`) w pasku podczas podglądu; przycisk "Done" podczas edycji wraca do podglądu (`isEditing = false`), NIE `dismiss()` — zostaje na tej samej podróży zamiast wracać do listy.

**Wspólny helper** `nightsText(_:)` (polska odmiana 1/2-4/5+) wyciągnięty z `PlannedStopRow` do `LocalizedString.swift` — teraz używany zarówno w edycji jak i w nowej karcie podglądu, bez duplikacji.

**Lokalizacja** — 4 nowe klucze × 27 języków = 108 tłumaczeń (`add_translations9.py`): "Edit trip", "Unnamed stop", "From %@", "Until %@" ("Done" już istniało w katalogu).

Build → **BUILD SUCCEEDED**, zainstalowane lokalnie na telefonie.

**Uwaga do zweryfikowania na urządzeniu**: sam mechanizm nawigacji (`editingTrip = trip` przy tapnięciu wiersza listy) nie został zmieniony w tej rundzie — jeśli po tej aktualizacji tapnięcie w istniejącą podróż WCIĄŻ nic nie robi (a nie tylko "wyglądało myląco jak pusty formularz"), to osobny, głębszy bug nawigacji wymagający diagnozy przez `devicectl --console` na żywo, nie sama zmiana UI.

**Trzecie pytanie usera tej rundy**: "share powinien być dostępny też na komunikatory dostępne na rynku, czyż nie?" — TAK, `ShareLink` używa systemowego Share Sheet (ten sam co "Udostępnij" w Zdjęciach/Safari), pokazuje WSZYSTKIE zainstalowane appki które rejestrują się jako odbiorcy udostępniania (WhatsApp, Messenger, Telegram, Wiadomości, Poczta, AirDrop) — nic dodatkowego do zrobienia, to już działa automatycznie dzięki wyborowi natywnego mechanizmu zamiast własnego.

## 12.08.2026 — deterministyczny prefetch kafelków dla eksportu mapy

Powrót do tematu z 11.08.2026 ("estymowany czas eksportu dla auta/pociągu... temat na później") — user: "jak by wyglądała praca nad systemem animacji... tak żeby wyglądała realistycznie i tak samo liczyła kilometry i żeby było szybkie do pobrania". Wyjaśnione od razu: liczenie km jest CAŁKOWICIE oddzielone od renderowania (liczy `RouteProvider`, niezależnie od silnika obrazu) — nie zmienia się bez względu na wybraną opcję.

User trafnie zapytał: "przecież podczas podglądu mapa powinna się ściągać, więc nie rozumiem dlaczego 2x musi się ściągać?" — słuszna uwaga, kafelki MapKit są faktycznie współdzielone systemowo między wszystkimi `MKMapView` w appce (fakt już wykorzystywany przez `MapTilePrefetcher`). Wyjaśnienie dlaczego to nie wystarcza samo z siebie: żywy podgląd (`TravelLiveMapView`) AKCEPTUJE niedoładowane kafelki (kamera leci dalej, obraz dociąga się wizualnie w locie, user tego prawie nie zauważa) — eksport NIE MOŻE pokazać ani jednej niekompletnej klatki, więc samo "dotknięcie" pozycji przez podgląd nie gwarantuje że kafelki faktycznie zdążyły się w PEŁNI ściągnąć. Zaproponowany darmowy test (obejrzeć cały podgląd przed zapisaniem i zmierzyć czas) — user zamiast tego: "wiemy jak to ma wyglądać i wiemy jak trasa będzie przebiegać i kiedy będą zbliżenia" — słusznie wskazując że skoro appka z góry zna DOKŁADNĄ, deterministyczną ścieżkę kamery (liczoną przez `TravelCinematics`), lepiej jest ją świadomie prefetchować niż polegać na przypadkowym zachowaniu usera (czy obejrzy podgląd do końca, czy nie).

**`TravelMapVideoRenderer.swift`** — nowa funkcja `warmupTileCache(stops:speedMultiplier:mapTheme:captureInterval:stepsPerLeg:size:)`, wołana fire-and-forget (`Task`) na samym początku `renderFrames`, RÓWNOLEGLE z właściwym eksportem, na CAŁKOWICIE OSOBNEJ, drugiej ukrytej `MKMapView` (ten sam trik co `makeSession`/`MapTilePrefetcher` — bardzo niski `windowLevel`). Przechodzi przez DOKŁADNIE te same pozycje kamery co główna pętla przechwytywania (ta sama matematyka: `TravelCinematics.frameState`/`easeInOutCubic`, ten sam wzorzec `effectiveCaptureInterval`), ale BEZ kompozycji/zapisu klatek — dużo tańszy krok niż prawdziwe przechwycenie, więc naturalnie wyprzedza główną pętlę i "dotyka" kafelków zanim będą tam realnie potrzebne. Krótszy limit oczekiwania (3s zamiast 10s w głównej pętli) — to tylko przewaga startowa, nie gwarancja; główna pętla ma WŁASNE, pełne zabezpieczenie bez zmian.

**Świadomie NIE ruszona główna pętla przechwytywania** — zero zmian w jej logice/progach/timingach (wielokrotnie dostrajanych w poprzednich sesjach pod realne bugi, ryzykowne dotykać bez wyraźnej potrzeby). Duplikacja trasowania (`RouteProvider.route` wołane drugi raz, w warmupie) świadoma i zaakceptowana — koszt jednego zapytania API per odcinek jest pomijalny wobec potencjalnego zysku.

Build → **BUILD SUCCEEDED**, zainstalowane lokalnie na telefonie. **NIEZWERYFIKOWANE realnym pomiarem** (ten sam status co eksperyment 11.08.2026) — jedyny sposób żeby to potwierdzić to zmierzyć realny czas eksportu trasy samochodem/pociągiem PRZED i PO tej zmianie na prawdziwym urządzeniu, nie samą teorią. Zapisane w `TODO.md`.

## 12.08.2026, ciąg dalszy — potwierdzony realny koszt eksperymentu 11.08 (cofnięty)

User wyeksportował trasę Londyn→Mielec (samochód) — "w nieco ponad minutę ściągnąłem trasę" (obiecujący czas), ale przesłany plik wideo z werdyktem: "nie działa płynnie".

**Diagnoza NIE zgadywaniem** — analiza klatka po klatce przez `ffmpeg`/Python (różnica pikseli między kolejnymi klatkami, cały film 306 klatek): od mniej więcej połowy trasy wyraźny, powtarzalny wzorzec "2 klatki niemal identyczne (diff ~0.05), potem jedna z DUŻYM skokiem (diff 15-35)" w kółko. To dokładnie objaw eksperymentu z 11.08.2026 (`effectiveCaptureInterval + 1` dla lądu/wody — rzadsze prawdziwe zdjęcie mapy) — kamera samochodu/pociągu cały czas PRZESUWA SIĘ, więc "zamrożone" tło przez 2 klatki z rzędu jest widoczne jako stukanie/skok, w przeciwieństwie do lotu gdzie ten sam trik jest niezauważalny (kamera tam głównie stoi w miejscu).

**Decyzja**: skoro dzisiejszy prefetch (patrz wyżej) atakuje SAM powód wolnego eksportu (czekanie na kafelki), eksperyment z rzadszymi zdjęciami przestaje być potrzebny jako osobny kompromis — **cofnięty całkowicie** (`effectiveCaptureInterval` wraca do tej samej wartości dla WSZYSTKICH środków transportu, tak jak przed 11.08.2026), zarówno w głównej pętli jak i w `warmupTileCache` (musi odwiedzać dokładnie te same pozycje, inaczej prefetch marnowałby czas na pozycje które i tak nie zostaną realnie przechwycone).

Build → **BUILD SUCCEEDED**, zainstalowane lokalnie na telefonie. **Do ponownego przetestowania przez usera** — ta sama trasa Londyn→Mielec (albo inna, dla uczciwego porównania): czy płynność wróciła do normy, i czy czas eksportu (dzięki prefetchowi z tej samej rundy) nadal jest rozsądny mimo częstszych prawdziwych zdjęć.

## 12.08.2026, ciąg dalszy — pojazd zamiera tuż przed przyjazdem (bug znaleziony i naprawiony)

User wyeksportował tę samą trasę drugi raz (Londyn→Mielec, ~1:30) — "samochód jak by znikał i płynność jest podobna, na końcu jest tragiczna". Diagnoza: (1) płynność "podobna" ma sens — cofnięcie eksperymentu z 11.08 przywróciło appkę do stanu SPRZED niego, ale TO ustawienie (`captureInterval: 2` dla satelity) samo w sobie też nie jest w pełni płynne — osobny, starszy kompromis (koszt renderowania realistycznego terenu), nie coś wprowadzonego dziś.

(2) "Samochód znika"/"na końcu tragiczna" — NOWY, realny bug znaleziony analizą klatek (nie zgadywaniem): tuż przed przyjazdem pojazd **zamierał w miejscu** (identyczna pozycja na ekranie przez kilkanaście klatek z rzędu), mimo że licznik km dalej rósł płynnie, po czym appka **nagle cięła** z bliskiego kadru na szeroki kadr przyjazdowy. Przyczyna: pozycja pojazdu liczyła się jako `path[Int(count * progress)]` — ZAOKRĄGLONY W DÓŁ indeks na ścieżce o ograniczonej rozdzielczości (~200 punktów z `RouteProvider.cinematicPath`). Krzywa `easeInOutCubic` (spowolnienie przed przyjazdem) spłaszcza się najmocniej właśnie na końcu — wiele kolejnych, dyskretnych klatek trafiało wtedy w DOKŁADNIE TEN SAM zaokrąglony indeks, więc pojazd wizualnie stał w miejscu mimo że appka "wiedziała" że jedzie dalej (stąd rosnący licznik km, liczony z ciągłego `progress`, nie z tego samego zaokrąglonego indeksu).

**Fix**: nowa `RouteProvider.interpolate(from:to:fraction:)` — prosta liniowa interpolacja MIĘDZY dwoma sąsiednimi punktami ścieżki zamiast zaokrąglania do najbliższego, dająca płynną, ciągłą pozycję niezależnie od rozdzielczości ścieżki/krzywej prędkości. Zastosowana w TRZECH miejscach dla pełnej spójności: głównej pętli eksportu, `warmupTileCache` (prefetch musi celować w tę samą pozycję co realne przechwycenie), i żywego podglądu `TravelLiveMapView` (ta sama matematyka pozycji co eksport, więc ten sam problem, mimo że mniej widoczny tam dzięki animowanej kamerze — naprawione dla spójności między oboma silnikami, zgodnie z zasadą pliku "zero rozjazdu mimo dwóch implementacji").

Build → **BUILD SUCCEEDED**, zainstalowane lokalnie na telefonie. **Do ponownego przetestowania** — ta sama trasa: czy pojazd teraz płynnie dojeżdża do celu zamiast zamierać, i czy przejście do kadru przyjazdowego wygląda mniej gwałtownie.

## 12.08.2026, ciąg dalszy — dalej "przeskakuje" w środku trasy (osobny, głębszy problem)

User przesłał kolejny film: fix zamierania przy przyjeździe POTWIERDZONY (analiza klatek: koniec trasy teraz płynnie zwęża różnicę zamiast zamierać) — ale w ŚRODKU trasy dalej wyraźny wzorzec "co druga klatka duży skok" (diff ~18-20 na przemian z ~0.05). User: "dalej samochód przeskakuje, nie może się poruszać jak samolot, czyli jednym ciągiem, tak żeby nie przeskakiwał?".

**To OSOBNY, głębszy problem niż zamieranie** — tło MAPY (nie sama pozycja pojazdu, już naprawiona) odświeża się tylko co DWIE klatki (`captureInterval: 2` dla Satellite, kompromis z 01.08.2026 z powodu kosztu renderowania realistycznego terenu 3D). Dla lotu niewidoczne (kamera głównie stoi w miejscu), dla auta/pociągu bardzo widoczne (kamera cały czas jedzie, więc "zamrożone" tło przez dodatkową klatkę = wyraźny skok co drugą klatkę).

**Eksperyment**: skoro `warmupTileCache` (ta sama sesja, wyżej) ma teraz odciążać sieciowe czekanie na kafelki, `baseCaptureInterval` podniesiony z powrotem do PEŁNEJ częstotliwości (`1` dla WSZYSTKICH motywów, nie tylko Minimal White) — realne zdjęcie mapy na KAŻDYM kroku, jak przed 01.08.2026. **Świadomie niepewne czy to wystarczy** — prefetch atakuje SIECIOWY koszt, ale bliski zoom z realistycznym terenem 3D ma też koszt czysto LOKALNEGO renderowania (GPU), którego prefetch nie dotyka — możliwe że eksport znowu wyraźnie zwolni.

Build → **BUILD SUCCEEDED**, zainstalowane lokalnie na telefonie. **Do przetestowania** — ta sama trasa: (a) czy tło mapy teraz płynnie przesuwa się bez skoków co drugą klatkę, (b) ile trwa eksport — jeśli wróci do bardzo wolnego, trzeba będzie cofnąć do `2` i zaakceptować że pełna płynność satelity dla lądu/wody to osobny, większy temat (wektorowa animacja albo inny kompromis, patrz `TODO.md`).

**Eksperyment natychmiast COFNIĘTY** — user: "zwolniło... bardzo długo długo to mało powiedziane, zatrzymało się na 74%... a nie idzie 75". `baseCaptureInterval` wraca do `2` dla Satellite (stan sprzed tego eksperymentu). Potwierdza to podejrzenie zapisane wcześniej w komentarzu: koszt bliskiego zoomu z realistycznym terenem 3D to głównie LOKALNE renderowanie (GPU), nie sieć — `warmupTileCache` (atakujący wyłącznie sieciowe kafelki) nie ma tu nic do odciążenia. **Pełna płynność satelity dla lądu/wody zostaje osobnym, większym tematem** w `TODO.md` (wektorowa animacja jak TravelBoast albo świadome obniżenie jakości dla tych segmentów) — nie prosta zmiana jednej stałej.

Build → **BUILD SUCCEEDED**, zainstalowane lokalnie na telefonie (zastępuje utknięty proces eksportu).

## 12.08.2026, ciąg dalszy — przesuwanie ponownie użytego zdjęcia zamiast zamrażania

User: "czy nie da się połączyć płynnie kilku zdjęć z całej trasy, tak żeby to odpowiednio było połączone i samochód sobie po tym przejeżdżał płynnie?". Trafny pomysł, zrealizowany BEZ zwiększania liczby prawdziwych zdjęć (czyli bez ponownego ryzyka spowolnienia jak przy próbie `1` wyżej).

**Mechanizm**: zamiast rysować ponownie użyte zdjęcie mapy dokładnie tam gdzie zostało zrobione (zamrożone), appka liczy o ile POJAZD naprawdę przejechał od ostatniego prawdziwego zdjęcia (`mapView.camera` zostaje NIETKNIĘTA między prawdziwymi zdjęciami, więc `mapView.convert()` dalej odzwierciedla STARĄ projekcję — różnica między tym gdzie aktualny środek kamery by się teraz zrzutował a środkiem canvasu to dokładnie potrzebne przesunięcie) i przesuwa CAŁY rysowany świat (zdjęcie mapy + etykiety + trasa + ikona pojazdu) o tę wartość. Odznaka dystansu i karta przyjazdu świadomie POZA tym przesunięciem — to elementy przyklejone do ekranu, nie do świata.

**Ważna różnica od odrzuconego 03.08.2026 pomysłu "przenikanie dwóch zdjęć"** — tamten dawał podwojone etykiety, bo BLENDOWAŁ dwa różne zdjęcia z różnych środków kadru naraz. Tu jest cały czas TYLKO JEDNO zdjęcie, po prostu inaczej pozycjonowane — nie ma dwóch obrazów do wymieszania, więc ten konkretny problem nie powinien wrócić.

**Świadome ryzyko do sprawdzenia na żywo**: skoro przesunięte zdjęcie nie pokrywa już całego kadru, jeden brzeg canvasu może pokazać wąski, niewypełniony pasek (zdjęcie nie jest szersze niż potrzeba — jeśli przesunięcie okaże się widoczne, prostym dalszym krokiem byłoby robienie prawdziwych zdjęć odrobinę SZERSZYCH niż finalna klatka, żeby było z czego przesuwać).

Build → **BUILD SUCCEEDED**, zainstalowane lokalnie na telefonie. **Do przetestowania** — ta sama trasa: czy tło mapy teraz płynnie "jedzie" razem z pojazdem zamiast skakać co drugą klatkę, i czy widać jakiś brzegowy artefakt (pusty pasek) przy większych przesunięciach.

**POTWIERDZONE na żywo** — user: "no i git, dużo lepiej to wygląda, tak narazie zostawiamy". Zero widocznego artefaktu na brzegu (na tej trasie/zoomie przesunięcie okazało się na tyle małe że margines nie był potrzebny). Mechanizm jest transport-agnostyczny (ten sam `legCameraCenter ?? point` używany dla WSZYSTKICH środków transportu z kamerą podążającą — pociąg/wędrówka/łódź/rejs), więc powinien identycznie pomóc dla pociągu — user chce to sprawdzić przy okazji, nie zakładać na sucho. **Temat zamknięty na dziś** — cała seria dzisiejszych eksperymentów nad płynnością/szybkością eksportu mapy kończy się na: deterministyczny prefetch (zostaje), płynna interpolacja pozycji pojazdu (zostaje), przesuwanie ponownie użytego zdjęcia zamiast zamrażania (zostaje, POTWIERDZONE), próba pełnej częstotliwości zdjęć dla Satellite (COFNIĘTA, zbyt kosztowna lokalnie).

## 12.08.2026, ciąg dalszy — pociąg ujawnił szary brzeg (przewidziane ryzyko, potwierdzone i naprawione)

User przysłał kolejny film (trasa z odcinkiem pociągiem, Londyn→Europa kontynentalna) bez komentarza — "sam zobacz". Analiza klatek: dokładnie ryzyko zapisane wcześniej dziś przy wdrażaniu przesuwania zdjęcia — jedna klatka (44 km, okolice Dartford) pokazywała wyraźną szarą, prostokątną dziurę w rogu kadru. Przyczyna: przesunięte zdjęcie nie było większe niż finalna klatka, więc przy większym przesunięciu (niektóre kombinacje zoomu/prędkości na dłuższym, bardziej zróżnicowanym odcinku pociągu) część canvasu zostawała bez pokrycia.

**Fix**: `captureSize` (rozmiar CAŁEGO `mapView`/`captureWindow`, nie tylko finalnej klatki) zwiększony o 40% w każdym wymiarze względem `size` — MapKit renderuje fizycznie WIĘKSZY obszar za jednym przechwyceniem, dając margines do przesuwania się zanim zdjęcie się "skończy". `composite()` dostał nowy wymagany parametr `captureSize`, licząc `marginOffset` (centrowanie większego zdjęcia względem mniejszego canvasu) połączony z istniejącym `backgroundShift` w jedno przesunięcie stosowane do całego bloku świata (mapa+etykiety+trasa+ikona). Poprawiony też błąd znaleziony PRZY OKAZJI tej zmiany: obliczanie `backgroundShift` używało środka `size` zamiast prawdziwego środka `mapView` (teraz `captureSize/2`, skoro `mapView.bounds` jest fizycznie większa) — bez tej poprawki przesunięcie liczyłoby się od złego punktu odniesienia.

**Koszt do obserwacji**: większy obszar przechwytywania = nieco więcej kafelków/renderowania per prawdziwe zdjęcie (`captureInterval` sam w sobie bez zmian, dalej `2` dla Satellite) — powinno być niewielkim, akceptowalnym narzutem, ale warto sprawdzić czas eksportu przy okazji następnego testu.

Build → **BUILD SUCCEEDED**, zainstalowane lokalnie na telefonie. **Do przetestowania** — ta sama trasa z pociągiem: czy szary brzeg zniknął, i orientacyjnie czy czas eksportu nadal jest rozsądny.

## 12.08.2026, ciąg dalszy — Update 1.0.2 wysłany na TestFlight

User: "chyba możemy zrobić update, czyż nie? robimy jako 1.0.2?" — koniec dzisiejszej rundy zmian. Potwierdzone przez `AskUserQuestion`: cała procedura naraz (podbicie wersji, build, archiwizacja, wysłanie), nie zatrzymywać się przed uploadem.

**Wersja**: `CFBundleShortVersionString` 1.0.1→**1.0.2**, `CFBundleVersion` 5→**7** (musiał być wyższy niż już wysłany build 6 z 10.08 — App Store Connect wymaga rosnących numerów, samo pole w `project.yml` zostało w tyle bo lokalne instalacje przez `devicectl` nie sprawdzają wersji wcale, user to zauważył: "jak nie zmieniamy nr to od razu przechodzi").

**Proces** — ten sam sprawdzony wzorzec co buildy 2-6 (`xcodegen generate` → `xcodebuild archive` → `xcodebuild -exportArchive` z `build/export7/ExportOptions.plist`, metoda `app-store-connect` robi upload bezpośrednio w tym samym kroku, bez osobnego `altool`). `-allowProvisioningUpdates` na obu krokach (profil dystrybucyjny, nie tylko developerski, musiał dociągnąć nowe capability Associated Domains z 12.08.2026).

**Weryfikacja uploadu** — `xcodebuild` zwrócił `** EXPORT SUCCEEDED **`, ale sam ten komunikat i `Packaging.log` NIE pokazują wprost potwierdzenia wysyłki (to tylko etap pakowania IPA) — prawdziwe potwierdzenie sprawdzone w `ContentDelivery.log`/`IDEDistributionAppStoreConnect.log` z tymczasowego katalogu `xcdistributionlogs`: rekord `buildUploads` utworzony (status 200), plik przesłany, cały łańcuch 13 kroków dystrybucji zakończony na `IDEDistributionSummaryStep` (ostatni krok, generuje `DistributionSummary.plist`) bez żadnego błędu — identyczny wzorzec jak przy potwierdzonym udanym buildzie 6.

**Do zrobienia przez usera w App Store Connect (poza zasięgiem terminala)**:
- Poczekać aż Apple skończy przetwarzanie builda po swojej stronie (zwykle kilka-kilkanaście minut, czasem dłużej) — dopiero wtedy build 7 pojawi się jako gotowy do testowania.
- Wypełnić "What to Test" dla tego builda — **BEZ EMOJI** (to był blocker przy buildzie 3, poprzednio złapany dopiero po odrzuceniu).

**Zawartość Update 1.0.2** (skrót dla notatki, pełne szczegóły w tym pliku wyżej, cały dzień 12.08.2026 + 11.08.2026): Trip Planning — godziny check-in/check-out i transportu, wysyłanie zaplanowanej podróży linkiem (Universal Links, backend na VPS), podgląd vs edycja podróży, wymuszone logowanie + auto-wysyłka do rankingu, oraz cała seria poprawek płynności/szybkości eksportu mapy (prefetch kafelków, płynna interpolacja pozycji pojazdu, przesuwanie ponownie użytego zdjęcia z marginesem).

## 12.08.2026, ciąg dalszy — **UPLOAD BUILDA 7 NIE DOTARŁ** — realny, systemowy problem z narzędziem, NIE dokończony

User kilka godzin później: "nie ma go na stronie" (App Store Connect), potem "minęło ponad 6 godzin" — dużo dłużej niż normalne przetwarzanie (zwykle kilkanaście minut do góra kilku godzin). Zbadane dokładnie, NIE zgadywanie:

**Diagnoza** — `xcodebuild -exportArchive` z metodą `app-store-connect` (ta sama, wcześniej sprawdzona metoda co buildy 2-6) zgłaszał `** EXPORT SUCCEEDED **`, ale to WPROWADZAŁO W BŁĄD. Rzeczywiste logi (`ContentDelivery.log` z tymczasowego katalogu `xcdistributionlogs`, nie `Packaging.log` — ten pokazuje tylko pakowanie IPA, nie sam upload) pokazały: appka tworzy poprawny rekord `buildUploads` w App Store Connect (status 200, stan `AWAITING_UPLOAD`), ale **nigdy faktycznie nie wysyła samego pliku** — zero wpisów w `buildUploadFiles` za każdym razem. Sprawdzone TRZY razy z rzędu:
1. Retry z tym samym buildem 7 → appka znajduje STARY rekord sprzed 6 godzin, tylko sprawdza jego status, nie próbuje wysłać pliku od nowa.
2. Drugi retry z buildem 7 → identyczny wynik.
3. Podbicie do builda 8 (żeby wykluczyć że to ten KONKRETNY, "zepsuty" rekord) → appka poprawnie tworzy ŚWIEŻY rekord `buildUploads` (nowe ID), ale znowu kończy dokładnie w tym samym miejscu — zero próby wysłania pliku.

**Wniosek**: to nie problem z konkretnym numerem builda ani stary/zablokowany rekord — to systemowy, powtarzalny błąd w TEJ WERSJI `xcodebuild`/ContentDelivery na tym Macu (Xcode 16.0-24904, `ContentDelivery version 26.40.1`) przy nowszej metodzie `app-store-connect` (bezpośredni upload w jednym kroku). Sprawdzone i wykluczone: miejsce na dysku (13MB plik, 12GB wolnego — nie problem), uwierzytelnienie (sesja Xcode działa poprawnie, wszystkie zapytania API zwracają 200).

**Stan na koniec dnia**:
- `project.yml`: `CFBundleVersion` → **8** (podbite podczas diagnozy, zostaje).
- Gotowe lokalnie, NIEWYSŁANE: `build/PMemories_build8.xcarchive` + `build/export8/PMemories.ipa`.
- User zdecydował (`AskUserQuestion`): zostawić dokończenie wysyłki na jutro, zamiast generować hasło aplikacji o tej porze.

**Dwie drogi na jutro** (obie wymagają innego uwierzytelnienia niż automatyczna sesja Xcode, która nie działa dla samego uploadu):
1. **`xcrun altool --upload-app`** — starsza, bardziej sprawdzona metoda command-line, wymaga hasła aplikacji (appleid.apple.com → Sign-In and Security → App-Specific Passwords, NIE głównego hasła Apple ID).
2. **Transporter.app** — oficjalna appka Apple do przeciągnij-i-upuść, NIE zainstalowana na tym Macu (do pobrania z Mac App Store), user robiłby to ręcznie z gotowym plikiem `build/export8/PMemories.ipa`.

**Do zrobienia jutro**: dokończyć upload (jedną z dwóch dróg wyżej) builda 8 (1.0.2), potem standardowo — poczekać na przetworzenie przez Apple, wypełnić "What to Test" bez emoji.

## 12.08.2026, ciąg dalszy — Shared Trip, Etap 1: fundament CloudKit + realny crash naprawiony

User: "zróbmy wszystko po kolei, łącznie z edycją wspólnej podróży" — zaczęta realizacja wcześniej zapisanej wizji "Shared Trip" (żywy, współdzielony `PlannedTrip` przez `CKShare`, nie jednorazowa kopia jak dzisiejszy link). Zaplanowane przez `EnterPlanMode` (plan zapisany, zatwierdzony) — Etap 1: osobna konfiguracja SwiftData dla `PlannedTrip`/`PlannedStop`/`PlaceToVisit` z CloudKit, zanim jakikolwiek UI współdzielenia.

**`PMemoriesAppApp.swift`** — `ModelContainer` rozbity na DWIE `ModelConfiguration` w jednym kontenerze: `local` (`SavedTrip`/`SavedProject`/itd., `cloudKitDatabase: .none`, bez zmian) i `shared` (`PlannedTrip`/`PlannedStop`/`PlaceToVisit`, `cloudKitDatabase: .automatic`) — reszta appki zostaje czysto lokalna, tylko planowanie podróży dostaje CloudKit.

**REALNY CRASH znaleziony i naprawiony od razu** (dokładnie ta sama klasa buga co 02.08.2026, tym razem inny wariant) — build+install+`devicectl --console` NATYCHMIAST po zmianie (zgodnie z planem), złapany w konsoli: `"CloudKit integration requires that all relationships be optional, the following are not: PlannedStop: placesToVisit, PlannedTrip: stops"`. Różnica względem 02.08: TYM RAZEM chodziło o relacje TO-MANY (tablice `[PlannedStop]`/`[PlaceToVisit]`), nie tylko pojedyncze — CloudKit wymaga optionality też dla tablic, nie tylko `to-one`.

**Fix**: `PlannedTrip.stops`/`PlannedStop.placesToVisit` zmienione z `[T] = []` na `[T]? = []`. Wszystkie miejsca odczytu przełączone na `?? []` (`TripPlanningView.swift`, `PlannedTripTransfer.swift`, `PlannedTripPersistence.swift`'s `asTripStops`/`looksCompleted`) — świadomie NIE ruszane `.stops`/`.placesToVisit` na INNYCH modelach (`SavedTrip`/`SavedStop` w `HomeView.swift`/`TravelAchievements.swift`/itd. — te zostają nieoptymalne bo NIE są w CloudKit-owej konfiguracji, żadnego wymogu optionality).

Build → **BUILD SUCCEEDED**, zainstalowane, **potwierdzone na żywo przez `devicectl device info processes`** że appka działa stabilnie (PID widoczny, żadnego crasha po dłuższym czasie) — nie tylko "zbudowało się", realna weryfikacja startu.

**Następny krok (ta sama sesja)**: UI udostępniania (`CKShare`/`UICloudSharingController`) w `PlannedTripDetailView`.

## 12.08.2026, ciąg dalszy — drag-to-reorder przystanków (zanim dokończymy upload)

User, czekając na dokończenie wysyłki: "dodajmy funkcję którą odłożyliśmy, wtedy nie będzie trzeba robić update niedługo" — z listy odłożonych z 10-11.08.2026 wybrane (`AskUserQuestion`): przeciąganie przystanków w edytorze (dziś tylko dodawanie na końcu + usuwanie).

**`TripPlanningView.swift`** — `.onMove(perform: moveStops)` dopisane obok istniejącego `.onDelete` na `ForEach` przystanków. `moveStops(from:to:)` przestawia posortowaną listę i nadpisuje `order` wszystkich przystanków sekwencyjnie (0, 1, 2...). Nowy `EditButton()` w pasku (widoczny tylko w trybie edycji podróży) — uchwyty przeciągania (☰) w SwiftUI `List` pokazują się wyłącznie w trybie edycji samej listy, a `PlannedStopRow` ma za dużo własnych interaktywnych elementów (pola/menu) żeby przeciąganie działało bez wyraźnego przełącznika. `EditButton()` sam zarządza otaczającym `\.editMode`, zero dodatkowego stanu do spinania. Systemowy komponent — sam się lokalizuje, zero nowych kluczy do tłumaczenia.

Build → **BUILD SUCCEEDED**, zainstalowane lokalnie na telefonie (build 8, wciąż niewysłany — patrz wyżej).

## 11.08.2026, ciąg dalszy — realny bug nawigacji na liście + duży redesign podglądu

User przysłał 2 zrzuty ekranu (podgląd "Romania" i lista z powrotem) z komentarzem "nie mogę nic tu zrobić". Po doprecyzowaniu ("dosłownie nic" po tapnięciu w kartę na liście) — **realny bug znaleziony w kodzie**: `row(for:)` (treść karty podróży na liście, wewnątrz `Button { editingTrip = trip }`) był zwykłym `VStack` BEZ `.frame(maxWidth: .infinity)` i BEZ `.contentShape(Rectangle())` — SwiftUI hit-testuje wtedy TYLKO faktyczny rozmiar wyrenderowanego tekstu (wąski, przyklejony do lewej), nie całą widoczną białą kartę systemowego wiersza `List`. Dotknięcie w kartę poza samymi literami tytułu/podtytułu trafiało w martwe pole — stąd "działało" czasem (gdy user trafił palcem dokładnie w tekst) i "nic" innym razem. Naprawione dopisaniem obu modyfikatorów.

**Przy okazji obszerny, bardzo konkretny redesign** — user po zobaczeniu ekranu podglądu na żywo ocenił że "wizualnie ten ekran jest teraz trochę przypadkowy, nie daje poczucia że oglądamy zaplanowaną podróż" i przysłał gotowy mockup: usunąć/ograniczyć wielkie rozmyte tło skórki, dodać kartę z mapą trasy jako główny element wizualny, zrobić prawdziwy timeline (miasto → ikona transportu → miasto), Convert jako główny CTA na samym dole (nie wysoko jak dotąd), wzbogacić karty na liście (flaga, ikony transportu/noclegu).

**`PlannedTripDetailView.summaryView` przebudowany**:
- `.tabSkinBackground()` USUNIĘTE z tego konkretnego ekranu — świadomy wyjątek od reguły "każda zakładka ma skórkę" (user chce tu czystą hierarchię, nie klimat).
- Nowa `RouteMapCard` — statyczna `Map` (SwiftUI, `interactionModes: []`) ze znacznikami dla przystanków z ROZWIĄZANĄ lokalizacją (`stop.coordinate != nil`) + `MapPolyline` łącząca je gdy ≥2. Znika całkowicie gdy żaden przystanek nie ma współrzędnych (zero pustej/mylącej mapy).
- Nowa `TransportConnector` — mała pionowa kreska + emoji trybu + etykieta MIĘDZY kartami przystanków (usunięta zdublowana ikona transportu wewnątrz samej karty `StopSummaryCard`, teraz to WYŁĄCZNIE rola łącznika).
- `StopSummaryCard.header` — flaga kraju (`CityGeocoder.flagEmoji`) przed nazwą miasta, tag "Start" na pierwszym przystanku (jak w mockupie usera).
- Tytuł nawigacji dostał flagę: "Romania 🇷🇴" zamiast samego "Romania" (`navigationTitleText`, z kodu kraju pierwszego przystanku który go ma).
- `row(for:)` na liście wzbogacony: flagi krajów przed tytułem, unikalne emoji trybów transportu + 🛏️ gdy jakikolwiek przystanek ma nocleg — jeden rząd pod trasą, obok "X nocy · Y dni".

**Lokalizacja** — 1 nowy klucz × 27 języków ("Itinerary" → "Trasa podróży" po polsku), `add_translations10.py`.

Build → **BUILD SUCCEEDED**, zainstalowane lokalnie na telefonie. **Świadomie NIE zrobione w tej rundzie** (poza zakresem który user opisał, do ewentualnego kolejnego etapu): "Places to visit" jako WSPÓLNA sekcja całej podróży zamiast per-przystanek (w mockupie usera wygląda jak jedna płaska lista, dziś dalej pogrupowane per przystanek — zmiana grupowania wymagałaby decyzji o miejscu w modelu danych), miniaturka mapy na kartach LISTY (dziś tylko na ekranie szczegółów).

## 11.08.2026, ciąg dalszy — brakująca data w karcie podróży

User po zobaczeniu karty z wzbogaconymi ikonami: "chyba jeszcze data by się przydała" — karta pokazywała TYLKO czas trwania ("7 nocy · 8 dni"), nie rzeczywisty zakres dat (OD KIEDY). Nowy `PlannedTrip.dateRangeText` (`PlannedTripPersistence.swift`) — `DateIntervalFormatter` (nie ręczne składanie stringa) sam dobiera lokalnie poprawny, skrócony format ("16–23 sie" gdy wspólny miesiąc, osobno gdy różne miesiące/lata) — zero nowych kluczy do tłumaczenia, formatter jest już lokalizowany systemowo. Dodane do karty na liście (przed "7 nocy · 8 dni") i do nagłówka ekranu podglądu (`tripDateSummary`).

Build → **BUILD SUCCEEDED**, zainstalowane lokalnie na telefonie.

## 12.08.2026 — ranking: diagnoza + wymuszone logowanie, godziny w Trip Planning, share do komunikatorów

User: "zmieniliśmy sposób logowania więc każdy przy starcie apki pierwszy raz się musi zalogować, dlaczego dalej widzę tylko jedną osobę w rankingu, czy to znaczy że nikt jeszcze nie stworzył mapy, czy coś jest z tym nie tak?"

**Diagnoza z kodu (nie zgadywanie)**: dwa realne powody, oba wcześniej niezauważone.
1. `OnboardingView.swift`'s ekran logowania miał tekst "Sign in with Apple... **Totally optional**" i przycisk "Skip" na górze kończył CAŁY onboarding (nie tylko tę stronę) — logowanie było w praktyce zawsze pomijalne mimo intencji, świadomie zaprojektowane tak 08.08.2026 ("krok jest POMIJALNY... logowanie zostaje opcjonalne").
2. Nawet dla userów którzy się zalogowali: `LeaderboardService.submitCurrentScore` był wołany WYŁĄCZNIE z `LeaderboardView.refresh()` — czyli tylko gdy user sam otworzył zakładkę Ranking. Zalogowanie się (Sign in with Apple) samo w sobie nigdy nie wysyłało wyniku do CloudKit.

Próba weryfikacji realnej liczby rekordów przez `cktool query-records` — zapisany User Token wygasł ("Session has expired"), `get-teams` (management token) dalej działa. Nie udało się potwierdzić liczby na żywo, tylko z kodu.

User potwierdził przez `AskUserQuestion`: napraw oba miejsca.

**`OnboardingView.swift` przebudowany** — REWIZJA decyzji z 08.08.2026: logowanie teraz WYMAGANE, nie pomijalne. "Skip" na górze ląduje na stronie logowania (nie kończy całego onboardingu). Dolny przycisk "Next"/"Get Started" znika całkowicie na stronie logowania dopóki `auth.isSignedIn == false` — `SignInWithAppleButton` jest wtedy jedyną dostępną akcją. Tekst zmieniony (usunięte "Totally optional"). Po udanym `handleSignIn` appka NATYCHMIAST wysyła wynik do CloudKit (`submitScoreIfSignedIn`, ten sam `TravelAchievementsCalculator.explorerScore` co `LeaderboardView`, `try?` — brak sieci nie przerywa onboardingu).

**Znana luka**: userzy którzy ukończyli onboarding PRZED tą zmianą nie zobaczą już ekranu logowania (flaga `OnboardingStorage.hasCompleted` już ustawiona) — zostaną niezalogowani dopóki sami nie wejdą w Ranking albo Profile. Nie naprawione w tej rundzie (wymagałoby osobnego mechanizmu ponownego pokazania promptu), świadomie odłożone.

## 12.08.2026, ciąg dalszy — godziny w Trip Planning

User: "w planerze nie mam godzin odlotów i przylotów, jak ktoś bierze cruise nie ma czasu, skoro planujemy podróż musi być o jakimś czasie". Potwierdzone przez `AskUserQuestion`: oba miejsca naraz.

**`PlannedTripPersistence.swift`** — `checkInDate`/`checkOutDate` dostały godzinę (`DatePicker` z `[.date, .hourAndMinute]` zamiast samego `.date`). Nowe pola `PlannedStop.transportDepartureTime`/`transportArrivalTime` (tylko `.hourAndMinute` — appka zna dzień z reszty planu, user wpisuje samą porę, np. dla rejsu/lotu/pociągu).

**`TripPlanningView.swift`** — nowy `OptionalTimeField` (wariant `OptionalDateField` tylko na godzinę), nowa `transportTimesSection` w `PlannedStopRow` (widoczna dla `!isFirst`, obok pickera transportu). `TransportConnector` w podglądzie pokazuje teraz godziny gdy ustawione ("✈️ Samolot · 14:00 → 18:30").

**`PlannedTripTransfer.swift`** — DTO rozszerzone o nowe pola (żeby Share/Import nie gubiły godzin).

**Lokalizacja** — 2 nowe klucze × 27 języków ("Departure time"/"Arrival time" → "Godzina odjazdu"/"Godzina przyjazdu"), `add_translations12.py`.

## 12.08.2026, ciąg dalszy — share nie oferował komunikatorów

User: "nie działa udostępnianie, tak samo nie można wybrać Messengera do udostępnienia". Diagnoza: rozszerzenia udostępniania WhatsApp/Messenger (i wielu innych komunikatorów) NIE przyjmują dowolnych niestandardowych plików — typowo tylko obraz/film/URL/zwykły tekst. Nasz `.pmtrip` (customowy `UTType`) miał TYLKO jedną reprezentację (`DataRepresentation`), więc appki bez wsparcia dla tego konkretnego UTI w ogóle nie pojawiały się na liście — to ograniczenie systemowe/appek trzecich, nie bug w naszym kodzie, ale dało się obejść.

**Fix** (`PlannedTripTransfer.swift`): dodana DRUGA, zapasowa reprezentacja — `ProxyRepresentation(exporting: \.shareSummaryText)` (zwykły tekst: tytuł podróży + trasa + "Shared from PMemories"). System sam dobiera pasującą reprezentację do wybranej appki — AirDrop/Wiadomości/Poczta/drugi PMemories dalej dostają pełny plik `.pmtrip` (importowalny), appki bez wsparcia dla plików (Messenger i podobne) dostają tekst zamiast być całkowicie wykluczone z listy. **Ograniczenie do zakomunikowania userowi**: przez Messenger odbiorca dostanie tylko tekst do przeczytania, NIE będzie mógł zaimportować trasy jednym tapnięciem jak przy pliku — to fundamentalne ograniczenie appek trzecich, nie coś co da się dalej naprawić po naszej stronie.

**Lokalizacja** — 1 nowy klucz × 27 języków ("Shared from PMemories"), `add_translations14.py`.

Build → **BUILD SUCCEEDED** (wszystkie trzy tematy razem), zainstalowane lokalnie na telefonie. **Do przetestowania przez usera**: nowy wymagany ekran logowania (najlepiej na świeżym audio/koncie testowym, bo `OnboardingStorage.hasCompleted` obecnego urządzenia już jest ustawione), godziny transportu/pobytu w Trip Planning.

## 12.08.2026, ciąg dalszy — share PRZEBUDOWANY: prawdziwy link zamiast tekstu

User po zobaczeniu pierwszej wersji (tekstowe podsumowanie jako fallback): "nie, share ma przejść i się zapisywać na apce od razu w zaplanowanych, jak się otworzy link — chyba nie zrozumieliśmy się na temat sharu". Poprzednia wersja (ProxyRepresentation z samym tekstem) NIE dawała możliwości importu — to była zła interpretacja "coś zamiast wykluczenia z listy appek". User chciał PEŁNOPRAWNY link, który po otwarciu (nawet z Messengera) sam otwiera PMemories i importuje podróż — dokładnie jak plik `.pmtrip`, tylko przez URL zamiast pliku.

**Doprecyzowane pytaniami**: czy link ma wyglądać jak ładne zaproszenie (karta z tytułem/opisem w komunikatorze — TAK, przez Open Graph meta tagi) i czy dane mogą być przechowywane do daty rozpoczęcia podróży (TAK). User wybrał: krótki link + zapis na serwerze (zamiast całego JSON-a zakodowanego w URL-u) — ładniejszy link, prawdziwe czyszczenie po dacie.

**Nowy backend na VPS** (`root@204.168.216.7`, ten sam wzorzec co istniejący `/opt/macamp_subscribe_server.py` — czysty Python stdlib, `ThreadingHTTPServer`, zero zależności zewnętrznych):
- `/opt/pmemories_share_server.py` — `POST /pmemories/api/trips` (zapisuje JSON podróży, zwraca krótkie ID), `GET /pmemories/api/trips/<id>` (appka pobiera dane do importu), `GET /pmemories/trip/<id>` (strona HTML z Open Graph tagami — tytuł/trasa jako karta w komunikatorze, plus link "Open in PMemories" jako fallback dla userów bez appki).
- Sprzątanie LENIWE (bez cron/timera) — przy każdym nowym zapisie appka usuwa pliki których `endDate`/`startDate` + 3 dni zapasu już minęły.
- Systemd service `pmemories-share.service` (port 127.0.0.1:8091), `nginx` proxy `/pmemories/` na domenie `piotrmarkowski.duckdns.org` (backup configu zrobiony przed edycją: `portfolio.bak_20260812_010110_before_pmemories_share`).
- **Universal Links** — plik `apple-app-site-association` pod `/var/www/portfolio/.well-known/` (Team ID `X3NAM3PL95`, bundle `com.piotrmarkowski.pmemories`, ścieżka `/pmemories/trip/*`), osobny `location` blok w nginx serwujący go z poprawnym `Content-Type`. Zweryfikowane na żywo przez `curl` (AASA, POST/GET testowej podróży, strona podglądu) — wszystko działa, testowy rekord usunięty po weryfikacji.

**App side**:
- `project.yml` — nowe entitlement `com.apple.developer.associated-domains: [applinks:piotrmarkowski.duckdns.org]`. Wymagało `xcodegen generate` + `xcodebuild -allowProvisioningUpdates` (profil provisioningu automatycznie doszedł do capability — Xcode/Apple zrobiły to same, zero ręcznej pracy w portalu developerskim).
- `PlannedTripTransfer.swift` — `ShareLinkService` (POST do stworzenia linku, GET do pobrania danych po ID). **Ważny szczegół znaleziony w kompilatorze** (nie zgadywanie): asynchroniczny wariant `ProxyRepresentation(exporting:)` jest `deprecated` od iOS 17 ("a synchronous exporter should be used instead") — nie da się więc zrobić wywołania sieciowego LENIWIE wewnątrz samego `Transferable`. Rozwiązanie: link generowany OSOBNO, PRZED pokazaniem `ShareLink` (patrz niżej), plik `.pmtrip` (`DataRepresentation`) zostaje jako dodatkowa, w pełni offline'owa opcja dla appek które go obsługują (AirDrop/Mail/drugi PMemories) — nie wymaga VPS-a.
- `TripPlanningView.swift` — przycisk Share w `PlannedTripDetailView` przebudowany: tapnięcie pokazuje `ProgressView` i w tle woła `ShareLinkService.createShareLink` (async), po sukcesie podmienia się na normalny `ShareLink(item: URL)` z gotowym linkiem (cache'owany — kolejne tapnięcia nie tworzą nowego linku, chyba że user wejdzie w edycję i coś zmieni — wtedy `shareLinkURL` czyszczone przy wejściu w tryb edycji). Alert błędu gdy sieć/serwer zawiedzie.
- `HomeView.swift` — `.onOpenURL`/`importTrip(from:)` rozbite na `importTripFromFile` (istniejąca ścieżka plikowa) i `importTripFromLink` (nowa — sprawdza `host == "piotrmarkowski.duckdns.org"` + prefiks ścieżki, pobiera dane z `ShareLinkService.fetchTrip`, async).

**Lokalizacja** — 1 nowy klucz × 27 języków ("Couldn't create share link"), `add_translations15.py`.

Build → **BUILD SUCCEEDED** (dwa przebiegi, prowizoning zaktualizowany automatycznie), zainstalowane lokalnie na telefonie. **Do przetestowania przez usera na żywo** (to jedyny sposób żeby to zweryfikować — Universal Links nie da się w pełni sprawdzić z terminala): wygenerować link z zapisanej podróży, wysłać go do siebie przez Messenger/WhatsApp/Wiadomości, sprawdzić czy (a) pokazuje się ładna karta z tytułem/trasą, (b) tapnięcie otwiera PMemories bezpośrednio (nie Safari) i importuje podróż do Zaplanowanych.

## 12.08.2026, ciąg dalszy — "quick send do osoby" w Share Sheet nic nie wysyła

User: "naciskam na osobę do share i znika po prostu, nie ma potwierdzenia do wysłania i nic się nie wysyła" — tapnięcie w awatar osoby na górze systemowego Share Sheet (iOS "szybka wysyłka", omija ekran kompozycji Wiadomości) zamykało arkusz bez żadnego efektu.

Diagnoza na żywo przez `devicectl --console` (user zreprodukował, konsola streamowana do pliku w scratchpadzie) — **brak crasha, brak błędu appki** w logach, tylko standardowy `viewServiceDidTerminateWithError: Scene was invalidated` (normalny przy zamykaniu dowolnego arkusza udostępniania, nie oznaka błędu). "Szybka wysyłka do osoby" dzieje się w osobnym procesie systemowym (rozszerzenie Wiadomości), którego nasza konsola nie widzi — brak dalszych dowodów możliwych do zebrania z terminala. Sprawdzone i WYKLUCZONE: budowa samego URL-a (zweryfikowana osobnym skryptem Swift — poprawny, bez uszkodzenia).

**Zastosowana poprawka** (nie stuprocentowo potwierdzona przyczyna, ale konkretny, uzasadniony podejrzany): usunięty własny `SharePreview` (tytuł + ikona SF Symbol) z `ShareLink` linku — to znany słaby punkt "szybkiej wysyłki do osoby" w iOS (customowe podglądy z ikonami SF Symbol zamiast bitmapy potrafią cicho zrywać tę konkretną, skróconą ścieżkę). Link ma już własną stronę z Open Graph tagami (`pmemories_share_server.py`) — Wiadomości/komunikatory i tak pobiorą podgląd SAME z tej strony dla zwykłego URL-a, customowy `SharePreview` był zbędny.

Build → **BUILD SUCCEEDED**, zainstalowane lokalnie na telefonie.

**POTWIERDZONE NAPRAWIONE na żywo** — user przesłał zrzut: karta "✈️ Romania / Londyn → Braszów" w Wiadomościach, status "Sent". Usunięcie `SharePreview` z SF Symbol faktycznie rozwiązało "szybką wysyłkę do osoby". **Cały łańcuch zweryfikowany end-to-end** — user tapnął w kartę, PMemories otworzyło się bezpośrednio (Universal Link zadziałał, nie Safari) i podróż faktycznie zaimportowała się jako nowy wpis w Zaplanowanych ("dodało mi kolejną, działa"). Funkcja "wyślij zaplanowaną podróż do kogoś" (11-12.08.2026) — **w pełni zamknięta i sprawdzona na prawdziwym urządzeniu**, nie tylko budowa+instalacja.

## 11.08.2026, ciąg dalszy — tytuł "Planowanie podróży" niewidoczny na skórce

User: "napis planowanie podróży nie jest za bardzo widoczny na tej skórce, musimy mieć pewność że wszystko jest widoczne". Ten sam, już wcześniej rozwiązany problem co "Travel Map" 02.08.2026: `.navigationTitle` NIE reaguje na kolor aktywnej skórki tła (`.toolbarColorScheme` steruje tylko materiałem/przyciskami, nie kolorem tekstu tytułu — sprawdzone bezpośrednio na urządzeniu w tamtej sesji, nie zgadywane) — system zawsze rysuje go domyślnym kolorem trybu jasny/ciemny, niezależnie od jasności zdjęcia w tle.

Ten sam sprawdzony fix co wtedy (i co "Play Memories" w `LibraryView`): `.navigationTitle("")` (pusty systemowy tytuł) + WŁASNY tekst "Trip Planning" jako pierwszy wiersz `List`, stylowany `.skinAwareHeading()` (biały + cień na aktywnej skórce, `.primary` bez skórki — pełna kontrola koloru zamiast walki z systemowym API). Zastosowane tylko do `list` (ekran z zapisanymi podróżami) — `emptyState` już miał własny, poprawnie kolorowany nagłówek ("Plan your next journey" z `.skinAwareHeading()`).

Build → **BUILD SUCCEEDED**, zainstalowane lokalnie na telefonie.

**Od razu potem** — user: "w nagłówku powinno być zaplanowane podróże czy coś w tym stylu, nie sądzisz?". Zgoda, ten sam wzorzec co "Library" (zakładka) / "Play Memories" (nagłówek listy) w `LibraryView` — nazwa zakładki opisuje SEKCJĘ, nagłówek nad listą opisuje ZAWARTOŚĆ. Nowy tekst nagłówka "Planned Trips" (osobny od etykiety zakładki "Trip Planning"), polskie tłumaczenie dokładnie jak user zaproponował: "Zaplanowane podróże" (1 klucz × 27 języków, `add_translations11.py`).

Build → **BUILD SUCCEEDED**, zainstalowane lokalnie na telefonie.

## 12.08.2026, ciąg dalszy — Shared Trip (CKShare): zaczęte, zablokowane, COFNIĘTE po realnym incydencie z danymi

User poprosił o zbudowanie "Shared Trip" — żywego, współdzielonego planowania podróży przez `CKShare` (dwie osoby widzą TĘ SAMĄ podróż, edycja jednej strony widoczna u drugiej), po zobaczeniu działającego linku-kopii. Plan zatwierdzony, Etap 1 rozpoczęty: `PMemoriesAppApp.swift` podzielone na dwie NAZWANE `ModelConfiguration` ("local" bez CloudKit, "shared" z `cloudKitDatabase: .automatic` dla `PlannedTrip`/`PlannedStop`/`PlaceToVisit`).

**Blokada #1 — API nie istnieje.** Przed pisaniem UI współdzielenia sprawdzone bezpośrednio w SDK (grep `.swiftinterface`, nie zgadywanie): `SwiftData.framework` (iPhoneOS26.5) **nie ma żadnego publicznego API do `CKShare`** — `ModelConfiguration.CloudKitDatabase` ma tylko `.automatic`/`.none`/`.private(_:)`, pełny grep całego interfejsu za "hare|CKShare|Participant|CKRecord" zwraca jeden, niezwiązany wynik. Prawdziwe współdzielenie person-to-person wymagałoby zejścia na surowy CloudKit (ręczna serializacja `CKRecord`/`CKShare`) — osobny, znacznie większy projekt niż dzisiejsza sesja.

**Blokada #2 — realny incydent z danymi.** User: "gdzie moje wszystkie memories?!" — nazwana `ModelConfiguration` BEZ jawnego `url:` liczy WŁASNĄ, nową domyślną ścieżkę pliku (`local.store`/`shared.store`) zamiast dotychczasowego `default.store`, na którym appka pracowała od zawsze. Efekt: appka po instalacji zaczęła czytać z dwóch świeżych, pustych baz — user stracił WIDOK na 11 zapisanych podróży, 4 projekty, 249 elementów multimediów (dane cały czas bezpieczne na dysku, appka po prostu przestała po nie sięgać).

Potwierdzone (nie zgadywane) przez `xcrun devicectl device copy` (ściągnięcie kontenera appki z telefonu) + `sqlite3` na obu plikach:
- `default.store` (stary): `ZSAVEDTRIP` = 11, `ZSAVEDPROJECT` = 4, `ZSAVEDMEDIAITEM` = 249, plus 1 testowa `ZPLANNEDTRIP` (2 przystanki).
- `local.store`/`shared.store` (nowe, od dzisiejszej zmiany): wszystkie zera.

**Decyzja: pełne cofnięcie eksperymentu**, nie próba łatania (np. jawny `url:` wskazujący z powrotem na `default.store`) — skoro blokada #1 i tak unieważnia cel (prawdziwy CKShare), nie ma sensu ryzykować drugiego podobnego incydentu. `PMemoriesAppApp.swift` wrócił do JEDNEJ, domyślnej (nienazwanej) `ModelConfiguration` dla całego schematu, `cloudKitDatabase: .none` — dokładnie jak przed tą sesją. Build → **BUILD SUCCEEDED**, zainstalowane, `devicectl` potwierdza proces żywy bez crasha (PID 54583). Osierocone pliki `local.store`/`shared.store` zostały na telefonie (nieużywane, appka ich już nie czyta) — do sprzątnięcia kiedyś, nie pilne.

**Do przetestowania przez usera**: otworzyć appkę i potwierdzić że wszystkie 11 podróży/4 projekty/249 elementów są z powrotem widoczne.

**Shared Trip zostaje w `Docs/TODO.md`** jako świadomie odłożony temat wymagający surowego CloudKit (`CKContainer`/`CKRecord`/`CKShare` bezpośrednio, z ręczną serializacją `PlannedTrip`, tak jak dziś robi to `LeaderboardService` dla Rankingu w bazie publicznej) — nie kolejnej próby przez SwiftData. User zaproponował też tańszą alternatywę po drodze (bez CKShare): appka przy starcie/wejściu na zakładkę CICHO sprawdza czy jest nowsza wersja podróży na istniejącym serwerze linków (VPS, `pmemories_share_server.py`) i podmienia dane lokalnie — wymaga dopisania endpointu `PUT` do aktualizacji istniejącego rekordu (dziś tylko `POST`=nowy/`GET`=odczyt) oraz pola `remoteTripID` na `PlannedTrip`. Nierozpoczęte, czeka na decyzję czy robić teraz czy odłożyć razem z resztą Shared Trip.

## 12.08.2026, ciąg dalszy — Budget w Trip Planning (uproszczony)

User: "można dodać koszty podróży i noclegu, wtedy jeśli ktoś będzie chciał, to może komuś polecić" — po zamknięciu Shared Trip, powrót do listy TODO wyłowił świadomie odłożony punkt "Budget" z 11.08.2026, ale w WĘŻSZYM zakresie niż pierwotny opis (koszty per kategoria loty/nocleg/jedzenie/transport/atrakcje) — user chce szybki szacunek do polecenia trasy komuś, nie księgowość.

**Model** (`PlannedTripPersistence.swift`): `PlannedTrip.currencyCode` (JEDNA waluta na całą podróż, domyślnie `Locale.current.currency` — appka nie przelicza kursów), `PlannedTrip.estimatedCostAmount` (loty/transport/atrakcje razem), `PlannedStop.accommodationCostAmount` (koszt TEGO noclegu — w istniejącej sekcji Accommodation, bo tam już jest kontekst). `PlannedTrip.totalEstimatedCost` sumuje wszystko, `nil` tylko gdy user nie wypełnił ŻADNEGO pola. `PlannedTrip.formattedCost(_:currencyCode:)` — `NumberFormatter` lokalnie poprawny (symbol przed/po kwocie), bez groszy.

**UI** (`TripPlanningView.swift`): nowa sekcja "Budget" w edytorze (Picker waluty — pełna lista ISO przez `Locale.commonISOCurrencyCodes`, pole kosztu podróży), nowe pole `OptionalCostField` (ten sam wzorzec co `OptionalDateField`/`OptionalTimeField` — "+ Add" gdy puste, symbol waluty + `TextField` numeryczny + X gdy wypełnione). Koszt noclegu dopisany do sekcji Accommodation w `PlannedStopRow`. Podgląd: karta "💰 Estimated budget" w `summaryView` (widoczna tylko gdy jest jakiś koszt), koszt noclegu dopisany pod adresem w `StopSummaryCard`.

**Udostępnianie**: `PlannedTripTransfer.swift` — `currencyCode`/`estimatedCostAmount`/`accommodationCostAmount` dopisane do `TripTransferDTO`/`StopTransferDTO`, jadą razem z resztą przez istniejący link (`ShareLinkService`) — odbiorca widzi budżet bez dodatkowej pracy.

**Lokalizacja** — 6 nowych kluczy × 27 języków ("Budget", "Currency", "Add estimated trip costs", "Estimated total", "Add accommodation cost", "Estimated budget"), dopisane od razu tym samym wzorcem co dotąd (skrypt Python w scratchpadzie, `Localizable.xcstrings` zwalidowany jako poprawny JSON po zapisie).

Build → **BUILD SUCCEEDED**, zainstalowane, `devicectl` potwierdza proces żywy (PID 54743). **Do przetestowania przez usera**: dodać koszt noclegu i koszt podróży w edytorze, sprawdzić czy suma pokazuje się poprawnie w podglądzie i czy waluta się zmienia; wysłać podróż linkiem do siebie i sprawdzić czy budżet pojawia się też po drugiej stronie.

## 12.08.2026, ciąg dalszy — Places to visit per dzień z checkboxem + rozbudowa Budget (loty osobno, all-inclusive)

User: "jeśli wpiszemy place to visit rozdzielone na dni, żeby był kwadracik który będziemy odznaczać podczas podróży co zobaczyliśmy, do tego koszty przelotów musimy dodać na górze szacowany koszt żeby się sumował, no chyba że to wycieczka all in z biura podróży, wtedy możemy wpisać całą kwotę tam".

**Places to visit — dzień + checkbox** (`PlannedTripPersistence.swift`): `PlaceToVisit.dayIndex: Int?` (ordynalny numer dnia pobytu, `nil` = "Any day"). W edytorze (`PlaceToVisitRow`) nowe Menu wyboru dnia obok istniejącego Menu priorytetu (Must see/Want to visit/Visited) — zakres dni liczony z `stop.nights` gdy user wypełnił daty pobytu, inaczej rozsądny domyślny zapas (7), z uwzględnieniem już przypisanych dni poza tym zakresem. W PODGLĄDZIE (`StopSummaryCard`, czyli to co się widzi W TRAKCIE podróży) — nowy `PlaceCheckboxRow`: kwadracik (`square`/`checkmark.square.fill`) zamiast Menu, jedno tapnięcie przełącza `.visited` ↔ `.wantToVisit` bezpośrednio (Menu z 3 opcjami zostaje w edytorze do USTAWIANIA priorytetu przed podróżą, checkbox w podglądzie to szybkie odznaczanie W TRAKCIE). Miejsca grupowane pod nagłówkiem "Day N" (+ prawdziwa data gdy `checkInDate` znane, np. "Day 1 · 16.08"), nieprzypisane lądują na końcu pod "Any day".

**Budget — loty osobno + tryb all-inclusive** (`PlannedTripPersistence.swift`): nowe pola `PlannedTrip.flightCostAmount` (osobna linijka, user: "koszty przelotów musimy dodać na górze, żeby się sumował" — zamiast ginąć w ogólnym worku) i `PlannedTrip.isWholePackage` (Toggle "All-inclusive package" w edytorze — user: "chyba że to wycieczka all in z biura podróży, wtedy możemy wpisać całą kwotę tam"). Gdy włączony, sekcja Budget POKAZUJE TYLKO jedno pole "Add package cost" (loty/nocleg/inne ukryte — już wliczone), `totalEstimatedCost` liczy WYŁĄCZNIE tę jedną kwotę zamiast dodawać osobno loty/nocleg (uniknięcie zdublowania). Gdy wyłączony (domyślnie) — trzy osobne pola: Loty, Inne koszty (transport/atrakcje), + nocleg per przystanek jak dotąd.

**Udostępnianie**: `PlaceTransferDTO.dayIndex`, `TripTransferDTO.flightCostAmount`/`isWholePackage` dopisane — dzień przypisania i pełny budżet jadą razem z resztą przez istniejący link.

**Lokalizacja** — 7 nowych kluczy × 27 języków ("Day", "Any day", "All-inclusive package", "Add package cost", "Add flight costs", "Add other costs (transport, activities)", "Already includes flights and accommodation — don't add them separately."), ten sam skrypt Python w scratchpadzie, `Localizable.xcstrings` zwalidowany jako poprawny JSON po zapisie. Świadoma uwaga: etykieta "Day N" to prosta konkatenacja (`L("Day") + numer`), nie w pełni idiomatyczna w językach z inną kolejnością (np. chińskim/japońskim/koreańskim, gdzie naturalne byłoby "1日目"/"1일차") — ten sam, już udokumentowany kompromis co reszta appki (`TODO.md`, "appka NIE ma pełnej obsługi ICU plural rules").

Build → **BUILD SUCCEEDED**, zainstalowane, `devicectl` potwierdza proces żywy (PID 54790). **Do przetestowania przez usera**: dodać kilka Places to visit z różnymi dniami, sprawdzić grupowanie w podglądzie i czy checkbox faktycznie odznacza; włączyć All-inclusive i sprawdzić że suma budżetu liczy TYLKO jedną kwotę (nie dubluje z lotami/noclegiem).

## 12.08.2026, ciąg dalszy — build 9 (1.0.2) wysłany na TestFlight, przyczyna bugu z uploadem obejście

User: "git teraz przygotuj wszystko i robimy update, potrzebujesz hasła?" — po dzisiejszych zmianach (naprawa danych po incydencie Shared Trip, Budget, Places to visit per dzień) zbudowany świeży build 9 (wersja 1.0.2 zostaje, build 8 nigdy nie dotarł do Apple — bezpiecznie nadpisany numerem).

**Ten sam bug co wcześniej** (build 7/8) — bezpośredni upload przez `xcodebuild -exportArchive` (metoda `app-store-connect`) znowu utknął: rekord `buildUploads` tworzy się poprawnie (HTTP 200, `AWAITING_UPLOAD`), ale log (`ContentDelivery.log`) urywa się NATYCHMIAST po utworzeniu rekordu — zero prób faktycznego transferu pliku. Trzeci raz z rzędu ten sam wzorzec, potwierdzony (nie zgadywany) przez bezpośrednią inspekcję logów za każdym razem — to systemowy bug tego Xcode/toolchain na tym Macu przy tej konkretnej metodzie eksportu, nie przypadek.

**Obejście — `xcrun altool --upload-app`** (starsze narzędzie, inny kod uploadu niż nowy `xcodebuild -exportArchive`): user dostarczył hasło aplikacji (app-specific password z appleid.apple.com) bezpiecznie przez Keychain (`security add-generic-password`, nie w plaintext w komendach). Jedna przeszkoda po drodze: pierwsza próba zapisu przez `xcrun altool --store-password-in-keychain-item` stworzyła rekord BEZ ustawionego pola `svce` (service) — przez co sam `altool` przy odczycie `@keychain:PMemoriesUpload` nie mógł go znaleźć ("Failed to find item"). Naprawione ręcznym `security add-generic-password -s "PMemoriesUpload" -a ...` (jawnie ustawia `svce`). System poprosił o hasło do Keychain logowania (osobne od hasła aplikacji) — user zaakceptował.

**UPLOAD SUCCEEDED** — 14 MB przesłane w 1.8s (Delivery UUID `75ee510c-2e98-496d-9343-b3dce5055884` — TEN SAM rekord co utworzony wcześniej przez `xcodebuild`, `altool` po prostu dokończył transfer którego tamten nigdy nie zaczął).

**Nowy, sprawdzony sposób uploadu na przyszłość**: `xcodebuild -exportArchive` do stworzenia `.ipa` (bez `destination: export` do bezpośredniego App Store — DO eksportu pliku), potem `xcrun altool --upload-app -f <ipa> -t ios -u markowskipiotrek85@gmail.com -p "@keychain:PMemoriesUpload"` do faktycznego wysłania. Hasło zostaje w Keychain do ponownego użycia. **Do zrobienia po tej sesji przez usera**: warto zregenerować to hasło aplikacji na appleid.apple.com, skoro wpisane wprost w treść czatu zanim trafiło do Keychain — nie jest już w pełni prywatne, mimo że nigdzie go nie wypisałem ponownie.

Build 9 (1.0.2) czeka teraz na przetworzenie przez Apple w App Store Connect (zwykle kilka-kilkanaście minut) — potem trzeba będzie uzupełnić "What to Test" (BEZ emoji, znany blocker z build 3) i przesłać do review.

Build 9 (1.0.2) przeszedł przetwarzanie Apple — status "Ready to Submit" potwierdzony przez usera. Altool jako metoda uploadu POTWIERDZONA jako działająca end-to-end (nie tylko "UPLOAD SUCCEEDED" w terminalu, ale realne dotarcie buildu do App Store Connect). Następny krok: "What to Test" (bez emoji) + submit do review.

Build 9 (1.0.2) — "What to Test" wypełnione (bez emoji, opis Budget/Places to visit per dzień/sharing linkiem/drag-reorder/godziny transportu/ranking), przesłane do review. Status: **waiting for review**. Update 1.0.2 kompletny po stronie appki i submissiona — czekamy na Apple.

## 12.08.2026, ciąg dalszy — Branded outro "PMemories — Coming soon" na końcu KAŻDEGO eksportu (lokalnie)

User po rozbudowanej dyskusji o brandingu (research konkurencji: CapCut branded outro w templatkach, TravelBoast): "to na razie robimy lokalnie". Na etapie TestFlight świadomie BEZ opcji wyłączenia (user: "niech każdy wygenerowany Memory będzie małą reklamą aplikacji") — pełny model Free (branding)/Premium (bez) zostaje w `Docs/Studio.md` na po oficjalnym release.

**Nowy plik `PMemoriesOutroCardRenderer.swift`** — ten sam, sprawdzony wzorzec co istniejąca karta "Travel Replay" (`TravelReplayCardRenderer.swift`: SwiftUI View → `ImageRenderer` → `ImageToVideoRenderer` → doklejenie jako `MediaItem` na końcu `EditView.performExport()`), ale świadomie ODRĘBNY plik/karta — Travel Replay to "część historii" (statystyki podróży), ta nowa karta jest jawnie marketingowa (✨ PMemories / Coming soon / "Turn your memories into stories.", gradient `Palette.heroGradient`), więc krótka: **2.0s** (user: "1.5-2 sekundy", górna granica — dłużej "aplikacja kradnie miejsce w Twoim własnym filmie").

**Cisza pod kartą** — user: "to będzie wstawka już bez muzyki na końcu". Wymagało realnej zmiany w `VideoComposer.swift`: muzyka w tle dotąd zawsze grała do `timelineEnd` (koniec CAŁEJ kompozycji, łącznie z doklejonymi kartami) — nowe pole `MediaItem.mutesBackgroundMusic` + osobno liczone `musicTimelineEnd` (przestaje się posuwać przy elemencie oznaczonym tą flagą) sprawiają, że ścieżka muzyczna kończy się dokładnie PRZED kartą PMemories, niezależnie od tego jak długi jest wybrany utwór. Świadomie NIE dotyczy istniejącej karty Travel Replay (ta zostaje bez zmian).

Kolejność na końcu eksportu: treść usera → Travel Replay (gdy podróż połączona) → PMemories branding (zawsze).

**Lokalizacja** — "Coming soon" już istniało w katalogu (użyte gdzie indziej), dopisany tylko nowy klucz "Turn your memories into stories." × 27 języków.

Build → **BUILD SUCCEEDED**, zainstalowane (jedna przejściowa utrata połączenia z telefonem przy instalacji — zwykły, przemijający problem tunelu `devicectl`, druga próba zadziałała od razu), `devicectl` potwierdza proces żywy (PID 57312). **Do przetestowania przez usera**: wyeksportować dowolne Memory i sprawdzić że na końcu pojawia się karta PMemories w ciszy (bez urwanej muzyki), krótko (~2s), niezależnie od tego czy projekt ma dołączoną kartę Travel Replay czy nie.

## 12.08.2026/13.08.2026 (po północy), ciąg dalszy — Home: dynamiczna karta "Upcoming/Current Trip"

User po pochwaleniu brandingu ("kozackie") rozwinął temat Home jako "centrum całej podróży" (Planning → Travel → Memories jednym systemem, nie trzema oddzielnymi funkcjami) — zainspirowane wygenerowaną wcześniej grafiką. Doprecyzowane w kolejnej wiadomości: "zamiast tego co się wyświetla będzie wyświetlała się następna podróż z odliczaniem... jeśli jesteśmy w trakcie, dzień pokazuje co dzisiaj do zobaczenia... jak nie ma nic zaplanowanego, jest to co jest teraz".

**Model — nowe computed properties na `PlannedTrip`** (`PlannedTripPersistence.swift`), ten sam duch "zero zgadywania" co istniejące `looksCompleted`: `effectiveStartDate`/`effectiveEndDate` (fallback na daty przystanków gdy `startDate`/`endDate` puste), `isInProgress` (dziś między startem a końcem włącznie, porównanie przez `Calendar.startOfDay` żeby godzina w dacie nie psuła porównania), `daysUntilStart` (0 = dziś), `currentDayNumber`/`totalDayCount` ("Day X of Y"), `currentStop` (przystanek którego daty pobytu obejmują dziś), `placesToVisitToday` (miejsca z `dayIndex` pasującym do dzisiejszego dnia W TYM przystanku, z pominięciem już odznaczonych `.visited` — bezpośrednie wykorzystanie dzisiejszej wcześniejszej funkcji Places to visit per dzień), `routeSummaryText` ("Londyn → Tokio").

**UI — `UpcomingTripCard`** w `HomeView.swift`, ten sam wizualny wzorzec co istniejąca `OnThisDayCard` (gradient w tle, emoji + dwie linie + akcja w `Palette.blue`, chevron) — świadomie spójne, nie nowy język wizualny. Umieszczona TUŻ PO głównym CTA, PRZED "On This Day" (patrzy w przód, bardziej pilna niż wspomnienie wstecz). Nowe `@Query private var plannedTrips: [PlannedTrip]` + `featuredPlannedTrip` (trwająca podróż ma pierwszeństwo przed nadchodzącą; wśród nadchodzących — najwcześniejsza). Trzeci stan ("nic zaplanowanego") obsłużony PROSTO — karta się po prostu nie renderuje (`if let featuredPlannedTrip { ... }`), reszta Home dokładnie jak dziś, zero zmian gdzie indziej.

Tap na kartę → `selectedTab = .tripPlanning` (bez deep-linkowania w konkretną podróż — świadomie prościej, lista Trip Planning i tak pokaże tę samą, oczywistą pozycję).

**Lokalizacja** — 6 nowych kluczy × 27 języków ("Starts today", "1 day to go", "days to go", "Day %d of %d", "Today", "View trip"). Format string z pozycyjnymi specyfikatorami (`%1$d`/`%2$d`) dla języków z innym szykiem wyrazów (np. japoński "%2$d日中%1$d日目" — najpierw suma dni, potem numer, odwrotnie niż polski/angielski) — `String(format:)` obsługuje to poprawnie per-locale niezależnie od tego że angielska/polska wersja używa prostego `%d`.

Build → **BUILD SUCCEEDED**, zainstalowane (jedna przejściowa utrata połączenia telefonu przy instalacji, druga próba zadziałała), `devicectl` potwierdza proces żywy (PID 57454). **Do przetestowania przez usera**: appka ma dziś tylko JEDNĄ testową zaplanowaną podróż (2 przystanki, z incydentu danych wcześniej dziś) — żeby zobaczyć kartę na żywo, trzeba wypełnić realne daty (start w przyszłości → stan "X dni do wyjazdu"; dziś między start/end → "Day X of Y" + dzisiejsze miejsca, jeśli przypisane).

## 13.08.2026 (po północy), ciąg dalszy — Upcoming Trip: pełne 5 stanów + pusty stan z zachętą

User potwierdził kierunek karty ("dużo lepiej, ten kierunek powinieneś zostawić") i doprecyzował DOKŁADNY tekst dla pięciu stanów, pytając wprost "czy tak się będzie zachowywać" — uczciwa odpowiedź: częściowo, licznik dni sam się aktualizuje (liczony na żywo), ale same stany ("Tomorrow", "Your trip starts today" z godziną, "You're in Romania" w trakcie, "Welcome back" po powrocie, pusty stan z zachętą) jeszcze nie istniały — zbudowane teraz w całości.

**Model — kolejne computed properties na `PlannedTrip`** (`PlannedTripPersistence.swift`): `departureTimeToday` (godzina transportu DO drugiego przystanku, tylko w dniu startu), `singleCountryName` (jak `TravelReplayCardRenderer` — tylko dla podróży jednokrajowej, zero zgadywania dla wielokrajowej), `currentRouteSegmentText` ("Brașov → Bucharest" — obecny przystanek → następny), `justCompleted` (zakończona w ciągu ostatnich 7 dni, żeby karta nie nagabywała w nieskończoność gdy user nie konwertuje).

**`UpcomingTripCard` przebudowana na 5 stanów** (`HomeView.swift`, `fileprivate enum State: Equatable`, sprawdzane w kolejności od najbardziej aktualnego): `welcomeBack` (zakończona niedawno, akcja "Create Memory" zamiast "View trip") → `startsToday` (trasa + godzina odjazdu jeśli znana) → `inProgress` ("You're in <kraj>" / fallback "Day X of Y", dzisiejsze miejsca do zobaczenia mają PIERWSZEŃSTWO nad samym numerem dnia gdy user je przypisał) → `tomorrow` → `upcoming(days:)`. Wybór "tej jednej" podróży (`featuredPlannedTrip`) rozszerzony o priorytet: w trakcie > niedawno zakończona > najwcześniejsza nadchodząca.

**Konwersja wprost z Home** — `HomeView.convertPlannedTrip(_:)`, świadomie zduplikowany krótki kod z `PlannedTripDetailView.convert()` (funkcja prywatna INNEGO widoku, nie da się jej bezpośrednio wywołać) zamiast przedwczesnej abstrakcji między dwoma miejscami.

**Pusty stan** — user: "Home zawsze ma coś aktualnego... to jest mechanizm retencji". Nowy `PlanTripPromptCard` (ten sam wizualny wzorzec) zastępuje dotychczasowe "nic tu nie ma" — "🌍 Where are you travelling next? / Plan a trip" gdy żadna podróż nie pasuje do żadnego z 5 stanów.

**Realny bug znaleziony przy kompilacji** — `fileprivate enum State` zagnieżdżony w `private struct` nie był widoczny z osobnej `extension ...: Equatable {}` na poziomie pliku mimo tego samego pliku źródłowego (Swift `private` ogranicza do zamykającej deklaracji, nie całego pliku, dla ZAGNIEŻDŻONYCH typów odwoływanych z zewnątrz) — naprawione przez `Equatable` wprost przy deklaracji enuma (`fileprivate enum State: Equatable`) zamiast osobnej extension.

**Lokalizacja** — 6 nowych kluczy × 27 języków ("Welcome back", "Your trip starts today", "Tomorrow", "You're in %@", "Where are you travelling next?", "Plan a trip"); "Create Memory" już istniało (główne CTA), reużyte.

Build → **BUILD SUCCEEDED**, zainstalowane, `devicectl` potwierdza proces żywy (PID 57541). **Do przetestowania przez usera**: appka ma dziś tylko jedną testową podróż bez realnych dat — pusty stan ("Where are you travelling next?") powinien być widoczny teraz od razu; żeby zobaczyć pozostałe 4 stany, trzeba wypełnić różne kombinacje dat (przyszła data startu → "X days to go"/"Tomorrow"; dziś → "Your trip starts today"; dziś między start/end → "You're in .../Day X of Y"; koniec w ciągu ostatnich 7 dni → "Welcome back").

## 13.08.2026, ciąg dalszy — "Around the World" z powrotem na mnożnik, "City Explorer" gamifikowany na Home

User po dalszej dyskusji o Home: "100% brzmi jak coś ukończonego... 1.0× = zrobiłem jedno okrążenie, ile zrobię dalej?" — potwierdził zakres ("lecimy z tym") po mojej rekomendacji zrobienia TYLKO tych dwóch punktów dziś (trzeci, większa przebudowa całej sekcji Lifetime w kompaktową kartę "Explorer Score", świadomie odłożony na świeższą głowę).

**"Around the World": % → × z powrotem** (`AchievementsView.swift` — hero-kafelek na Badges, ORAZ osobno `HomeView.swift`'s `lifetimeRows` — dwa niezależne miejsca liczące to samo). To DOSŁOWNIE cofnięcie zmiany z 01.08.2026 (wtedy zewnętrzny feedback: "większość ludzi nie myśli w x") — teraz świadoma decyzja usera w przeciwną stronę, gamifikacja > czysta intuicyjność formatu. Sam mnożnik (`AroundTheWorldStat.multiplier`) niezmieniony, tylko format tekstu (`"%.1f×"` zamiast `"%.0f%%"`).

**"City Explorer" na Home** — user: "masz już poziomy Bronze/Silver/Gold, więc Home może pokazywać: City Explorer, 36 cities, 14 cities to next level". Zamiast osobnej nowej logiki progów — REUŻYCIE gotowego `Achievement` (ten sam obiekt co karta "Cities" na ekranie Badges, `TravelAchievementsCalculator.achievements`) w nowym `CityExplorerRow` (pasek postępu + `achievement.progressMessage`, np. "14 cities until Silver"). `HomeView.LifetimeRow` — nowy enum (`.simple`/`.cityExplorer`) zamiast płaskiej krotki, żeby wcisnąć JEDEN bogatszy wiersz w tę samą listę bez przebudowy całej sekcji — reszta wierszy (Countries/Flights/Trips/itd.) bez zmian.

**Lokalizacja** — 1 nowy klucz × 27 języków ("City Explorer").

Build → **BUILD SUCCEEDED**, zainstalowane (dwie przejściowe utraty połączenia z telefonem przy instalacji/uruchomieniu — ta sama, znana niegroźna niestabilność tunelu `devicectl` co wcześniej dziś, trzecia próba zadziałała), `devicectl` potwierdza proces żywy (PID 57559). **Do przetestowania przez usera**: sprawdzić że "Around the World" na Badges I na Home pokazuje teraz "1.0×" (nie "100%"), i że wiersz "Cities" na Home ma teraz pasek postępu + "City Explorer" zamiast suchej liczby.

**Świadomie odłożone** (trzeci punkt z dzisiejszego feedbacku, większa przebudowa): zwinięcie całej sekcji "Lifetime" w kompaktową kartę "Explorer Score" (punkty + poziom + 3 najważniejsze statystyki + "View all →"), zamiast dzisiejszej płaskiej listy 8-10 wierszy. Zapisane do zrobienia w osobnej sesji — realna zmiana layoutu Home, nie kosmetyka.

## 13.08.2026, ciąg dalszy — Branded outro: sekwencja 4 faz zamiast jednej statycznej karty

User obejrzał pierwszą wersję i dał precyzyjny feedback: bez statystyk podróży na końcu ("PMemories ma być narzędziem do tworzenia DOWOLNYCH wspomnień, nie tylko podróży" — potwierdza wcześniejszą decyzję, nic do zmiany), ale sam branding za mały i wszystko naraz zamiast sekwencji: "0-1.5s PMemories / 1.5-3s tagline / 3-4.5s Coming soon" + fade-out na koniec, tekst "PMemories" 1.5-2× większy, bez "Coming soon to the App Store" (samo "Coming soon" — i tak już tak było, nic do poprawy).

**`PMemoriesOutroCardRenderer.swift` przebudowany** — zamiast JEDNEJ statycznej karty ze wszystkimi elementami naraz, CZTERY osobne fazy (`OutroPhase`: `.logo`/`.tagline`/`.comingSoon`/`.blackout`), każda renderowana jako osobny obrazek → osobny krótki klip. "PMemories" powiększone z 44pt do 76pt (~1.7×). Nowa faza `.blackout` (czysta czerń, 0.4s) na samym końcu — user chciał fade-out, a appka NIE MA custom silnika do fade-to-black; zamiast pisać nową logikę, wykorzystany ISTNIEJĄCY mechanizm crossfade między klipami — przejście OSTATNIEJ fazy tekstowej DO czarnego kadru wygląda dokładnie jak zanikanie, zero nowego kodu animacji.

**`EditView.performExport()`** — pętla dokładająca WSZYSTKIE cztery fazy jako kolejne `MediaItem` (każdy `mutesBackgroundMusic: true`), zamiast pojedynczego dokłejenia jak wcześniej. Płynne przejścia między fazami (i między treścią usera a pierwszą fazą) to ten sam automatyczny crossfade co między zwykłymi klipami w Studio — appka "za darmo" dostała sekwencyjny reveal bez pisania nowego silnika renderowania. `brandingOutroURL: URL?` → `brandingOutroURLs: [URL]` (sprzątanie tymczasowych plików rozszerzone na tablicę, bo teraz 4 pliki zamiast 1).

**Zero nowych tłumaczeń** — "PMemories" to nazwa marki (nie tłumaczona), "Turn your memories into stories." i "Coming soon" już istniały z poprzedniej wersji.

Całkowity czas karty: 1.5+1.5+1.5+0.4 = **4.9s** (blisko żądanych "3-4.5s" + fade, plus sam ogon czerni).

Build → **BUILD SUCCEEDED**, zainstalowane, `devicectl` potwierdza proces żywy (PID 57808). **Do przetestowania przez usera**: wyeksportować dowolne Memory i sprawdzić sekwencję na żywo — logo (duże) → tagline → Coming soon → płynne ściemnienie na koniec, bez muzyki pod spodem przez całą sekwencję.

## 13.08.2026, ciąg dalszy — "Travel Replay" całkowicie usunięta, zostaje TYLKO branding PMemories

User zauważył po eksporcie, że dalej widać podsumowanie "8 days / 49 photos / km" — wyjaśnione że to OSOBNA, wcześniejsza funkcja "Travel Replay" (30.07.2026), pokazująca się TYLKO dla filmów ręcznie połączonych z Travel Map, nie dzisiejsza karta brandingowa. Po wyjaśnieniu user zdecydował: "usuwamy to podsumowanie na końcu filmu, tak chyba jest łatwiej" — zamiast dwóch nakładających się kart (Travel Replay + PMemories branding) na końcu niektórych filmów, zostaje TYLKO jedna, uniwersalna.

**Usunięte całkowicie**: plik `TravelReplayCardRenderer.swift` skasowany; blok w `EditView.performExport()` renderujący i doklejający tę kartę usunięty razem z `outroURL`/jego `defer` sprzątaniem; `@Query private var savedTrips: [SavedTrip]` w `EditView.swift` usunięte (było potrzebne TYLKO do `TravelReplayCardRenderer.data(for:trips:)`, teraz nieużywane); `xcodegen generate` (usunięty plik źródłowy) + rebuild.

Efekt: KAŻDY eksport (podróż połączona z Travel Map czy nie) kończy się teraz WYŁĄCZNIE sekwencją PMemories (logo→tagline→Coming soon→fade-out) — jeden, spójny, uniwersalny system zamiast dwóch warunkowych.

Build → **BUILD SUCCEEDED**, zainstalowane, `devicectl` potwierdza proces żywy (PID 57850). **Do przetestowania przez usera**: wyeksportować film POŁĄCZONY z Travel Map (ten sam projekt co wcześniej) i potwierdzić że statystyki podróży już się NIE pojawiają — tylko sama sekwencja brandingowa.

## 13.08.2026, ciąg dalszy — Outro przebudowane: JEDNA ciągła scena z animowanym tekstem, nie sklejone klipy

User po zobaczeniu poprzedniej wersji (4 osobne fazy połączone crossfade między klipami): "nie o to mi chodziło... to ma być jeden końcowy ekran, tekst ma się zmieniać na tym samym ekranie, nie trzy osobne slajdy" — dokładna specyfikacja: tło/logo/layout niezmienione przez CAŁY czas trwania, tekst animuje się W MIEJSCU (PMemories → tagline → Coming soon), całość ma wyglądać jak "jedna, elegancka, ciągła animacja", nie prezentacja.

**Diagnoza własnego błędu**: poprzednia wersja renderowała 4 PEŁNE, osobne obrazy (każdy z innym tekstem WYPALONYM w środku) jako 4 osobne krótkie klipy, łączone tym samym mechanizmem co zwykłe cięcia między zdjęciami w Studio (crossfade CAŁEGO kadru) — stąd wrażenie "slajdów", mimo że tło było wizualnie takie samo w każdej fazie.

**Poprawne podejście — zejście na niższy poziom, ta sama technika co animowane napisy** (`Caption`/`CATextLayer`/`AVVideoCompositionCoreAnimationTool`, w tym projekcie już istniejąca od 27.07.2026):
- `PMemoriesOutroCardRenderer.swift` — renderuje TERAZ tylko JEDNO stałe tło (gradient + mała, trwała ikonka ✨), trzymane jako JEDEN klip przez całą długość outro (4.5s = 3 × 1.5s), zamiast 4 osobnych obrazów z wypalonym tekstem.
- `VideoComposer.swift` — `captionsAnimationTool` przemianowana na `animationTool(captions:outroStartTime:canvasSize:)`, dokłada TRZY dodatkowe `CATextLayer`e ("PMemories" → tagline → "Coming soon") w TEJ SAMEJ pozycji na ekranie, każda widoczna tylko w swoim 1.5s oknie czasowym z płynnym przenikaniem (`CAKeyframeAnimation` fade in/out 0.4s na krawędziach, zamiast twardego cięcia jak przy zwykłych napisach) — user: "smoothly replace/fade into". Nowa `outroStartTime: CMTime?` liczona przez porównanie `musicTimelineEnd < timelineEnd` (REUŻYCIE już policzonej wartości z wcześniejszej poprawki wyciszania muzyki — appka wie dokładnie gdzie zaczyna się wyciszony branding, bo to dokładnie ten sam punkt).
- `EditView.performExport()` — z powrotem JEDNO dołożenie `MediaItem` (nie pętla po 4 fazach), `duration: PMemoriesOutroCardRenderer.duration` (4.5s całości, nie osobne 1.5s).

Efekt: outro to teraz naprawdę JEDNA ciągła scena — tło/gradient/ikonka nigdy się nie zmieniają, tylko tekst przenika w miejscu. Zero nowego SILNIKA animacji — pełne reużycie istniejącego mechanizmu napisów, tylko inne źródło tekstu i czasów.

Build → **BUILD SUCCEEDED**, zainstalowane, `devicectl` potwierdza proces żywy (PID 57867). **Do przetestowania przez usera**: wyeksportować dowolne Memory i potwierdzić że teraz wygląda jak JEDNA scena (bez wrażenia cięcia między "slajdami"), z tekstem płynnie przenikającym w tym samym miejscu.

## 13.08.2026, ciąg dalszy — brak separatora tysięcy naprawiony w całej appce

User przesłał zrzut Home i zapytał "co znajdziesz nie tak" — dwie rzeczy: (1) "Londyn" zamiast "London" w karcie Upcoming Trip — to zapisane dane testowe (miasto wybrane z podpowiedzi po polsku wcześniej dziś), nie błąd w kodzie, appka nigdy nie tłumaczy nazw miast; (2) **"39955 km" bez przecinka** — realny, systemowy bug formatowania liczb.

Sprawdzone przez grep w całym projekcie (nie tylko ten jeden widoczny przypadek) — **17 miejsc** w 6 plikach robiło surową interpolację `\(Int(x))` bez separatora tysięcy dla wartości które REALNIE mogą przekroczyć 999 (km, punkty Explorer Score, metry wysokości): `HomeView.swift` (Twoja Podróż/journeyStats), `AchievementsView.swift` (Around the World, Explorer Score), `TravelAchievements.swift` (breakdown punktacji + listy szczegółów odznak), `TripPersistence.swift`, `TravelWrappedView.swift`, `LeaderboardView.swift`. Naprawione jednolicie przez dopisanie `.formatted()` do każdego `Int(...)` — wbudowany w Swift, lokalnie poprawny formatter (przecinek w angielskim, spacja w polskim itd.), zero nowej zależności. Świadomie POMINIĘTE: procenty (`%`) i temperatura (`°`) — te nigdy nie przekraczają 3 cyfr, nie potrzebują separatora.

Build → **BUILD SUCCEEDED**, zainstalowane, `devicectl` potwierdza proces żywy (PID 57904). **Do przetestowania przez usera**: sprawdzić że "39,955 km" (z przecinkiem) pokazuje się teraz wszędzie — Home, Badges, Travel Wrapped, Ranking.

## 13.08.2026, ciąg dalszy — nazwa miasta w języku APPKI (nie regionu telefonu), Countries dostaje pasek postępu

User na "Londyn": "to powinno być w zależności od języka jaki mamy ustawiony, a nie ja mam coś zmieniać" — słuszna uwaga, poprzednie wyjaśnienie ("to dane testowe") było prawdziwe ale niepełne: appka MIAŁA realny problem architektoniczny, nie tylko stare dane.

**Diagnoza**: `MKLocalSearchCompleter` (podpowiedzi podczas wpisywania miasta) zawsze zwraca tytuł w języku REGIONU TELEFONU (Ustawienia systemowe → Region), NIEZALEŻNIE od osobnego przełącznika języka appki (`AppLanguage`, Profile → Language, user 30.07.2026: "mieszkam w Anglii ale może chcę mieć po polsku"). Appka dotąd zapisywała ten surowy tytuł wprost jako `stop.cityName` — stąd "Londyn" nawet gdy appka jest po angielsku.

**Naprawa** (`CitySearchCompleter.swift`): `resolve()` dokłada DODATKOWE zapytanie `CLGeocoder().reverseGeocodeLocation(_:preferredLocale:)` z lokalizacją ustawioną na FAKTYCZNY język appki (`Bundle.main.preferredLocalizations`, ten sam sposób co `isPolishLanguageActive`) — zwraca nazwę miasta w poprawnym języku niezależnie od regionu telefonu. Oba miejsca wywołania (`TripPlanningView.swift`, `TravelMapView.swift`) nadpisują `stop.cityName` tą wersją, gdy się uda (surowy tytuł zostaje jako fallback gdy geokodowanie zawiedzie). Świadomie NIE naprawia WSTECZ już zapisanych miast (np. istniejące "Londyn" w testowej podróży) — to dotyczy tylko NOWO wybieranych miast od teraz.

**Countries — ten sam pasek postępu co Cities** — user: "mamy linię na cities, a co z countries?". `HomeView.LifetimeRow.cityExplorer(Achievement)` → generalizowane na `.progressExplorer(Achievement, title: String)`, `CityExplorerRow` → `ExplorerProgressRow` (przyjmuje tytuł jako parametr) — jedna karta obsługuje teraz zarówno "City Explorer" jak i "Country Explorer", zero duplikacji kodu.

**Lokalizacja** — 1 nowy klucz × 27 języków ("Country Explorer").

Build → **BUILD SUCCEEDED**, zainstalowane, `devicectl` potwierdza proces żywy (PID 57939). **Do przetestowania przez usera**: dodać NOWY przystanek (nie edytować istniejący "Londyn") i sprawdzić że nazwa miasta zapisuje się w języku appki; sprawdzić że "Countries" na Home ma teraz też pasek postępu ("Country Explorer", X krajów do Silver).

## 13.08.2026, ciąg dalszy — Outro: 2 stany zamiast 3, znacznie większy tekst, ✨ tylko przy pierwszym

User po zaakceptowaniu architektury ("technicznie dużo lepiej, jedna scena, trzymaj ten kierunek") doprecyzował wygląd: (1) ✨+PMemories+tagline RAZEM jako pierwszy stan (~2s), (2) potem znikają, samo "Coming soon" jako drugi stan (~2s), (3) PMemories WYRAŹNIE większe — "za dużo pustej przestrzeni, PMemories powinno być elementem który widz zapamięta", (4) ✨ TYLKO nad pierwszym stanem, nie nad każdym tekstem (poprzednia wersja miała sparkle wypalone w STAŁYM tle, więc pojawiało się też nad "Coming soon" — błąd).

**`PMemoriesOutroCardRenderer.swift`** — nowy `OutroTextSpec` (tekst/rozmiar czcionki/przesunięcie pionowe/numer fazy/przezroczystość) opisujący KAŻDY element tekstowy deklaratywnie, `VideoComposer` tylko to czyta. Tło (`PMemoriesOutroBackgroundView`) teraz CZYSTY gradient — sparkle przeniesiony z tła do systemu tekstu (faza 0), żeby poprawnie znikał razem z PMemories/tagline zamiast wisieć przez całe outro. Dwie fazy po 2.2s (4.4s łącznie): faza 0 = ✨ (50pt) + "PMemories" (108pt, było 76-80pt — realnie większe) + tagline (34pt) w tym samym oknie czasowym; faza 1 = "Coming soon" (72pt) samo.

**`VideoComposer.swift`** — `outroTextLayers` przebudowana pod `textSpecs`: elementy z TYM SAMYM `phaseIndex` dostają IDENTYCZNE okno czasowe (widoczne/znikają razem), pozycja pionowa liczona z `spec.yOffset` względem środka (konwencja `CALayer` tego kontekstu — duże Y = bliżej góry).

Build → **BUILD SUCCEEDED**, zainstalowane, `devicectl` potwierdza proces żywy (PID 58049). **Do przetestowania przez usera**: wyeksportować Memory i potwierdzić: PMemories wyraźnie większe i czytelne od razu, ✨ znika razem z tekstem (nie zostaje nad "Coming soon"), całość ~4.4s, jedna ciągła scena.

## 13.08.2026, ciąg dalszy — nazwy miast z zaimportowanej podróży w języku ODBIORCY, nie nadawcy

User zmienił język appki na polski, zauważył że stare miasta zostały po angielsku (oczekiwane, potwierdzone), po czym zapytał: "jak ktoś mi wyśle zaproszenie do podróży, ono będzie w języku tym co ktoś wyśle, czy zapisze się w tym co mam na telefonie?".

**Diagnoza**: dziś link/plik `.pmtrip` przenosi GOTOWY tekst (`TripTransferDTO.stops[].cityName`) dokładnie tak jak zapisany u NADAWCY — appka nigdy nie tłumaczy go po drodze. Odbiorca z innym językiem appki dostawał więc miasta w języku nadawcy.

**Naprawa**: `CitySearchCompleter.swift` — `localizedCityName(for:)` wydzielone z `resolve()` (ten sam mechanizm — `CLGeocoder` z `preferredLocale` ustawionym na język appki — teraz reużywalny bez wcześniejszego wyszukiwania z podpowiedzi, tylko na podstawie już znanej współrzędnej). `HomeView.finishImportingTrip` woła nowe `localizeImportedStopNames(_:)` — dla każdego przystanku z rozwiązaną współrzędną, W TLE (fire-and-forget `Task`, jeden na przystanek), dogeokodowuje nazwę w JĘZYKU ODBIORCY i nadpisuje `stop.cityName`. Zero blokowania importu — podróż pojawia się od razu, nazwy "dogrywają się" po chwili.

Build → **BUILD SUCCEEDED**, zainstalowane — telefon zablokowany w momencie instalacji, appka NIE uruchomiona zdalnie (do otwarcia ręcznie). **Do przetestowania przez usera**: wysłać sobie (albo komuś) podróż linkiem, otworzyć na urządzeniu z INNYM językiem appki niż nadawca, sprawdzić że miasta po chwili "dogrywają się" w języku odbiorcy.

**Koniec sesji na dziś** (user: "na tym dzisiaj zakończymy") — pełne podsumowanie dnia 12-13.08.2026: naprawiony realny incydent z danymi (Shared Trip/CKShare cofnięte), zbudowany Budget (loty/all-inclusive), Places to visit per dzień z checkboxem, Home "Upcoming Trip" (5 stanów) + "Explorer Score" gamifikacja (Around the World ×, City/Country Explorer), branded outro PMemories (kilka rund dopracowania — jedna ciągła scena, 2 stany, większy tekst), usunięta karta Travel Replay, naprawiony brak separatora tysięcy w 17 miejscach, naprawiona lokalizacja nazw miast (wybór z podpowiedzi + import podróży). Build 9 (1.0.2) wysłany na TestFlight, status "waiting for review".

## 13.08.2026, ciąg dalszy — build 10 (1.0.2) przygotowany lokalnie, CZEKA na sygnał (nie wysłany)

User: "przygotuj paczkę na wysłanie, to wszystko dodamy jutro jak będzie zatwierdzony 1.0.2... na tę chwilę czekamy, dam znać" — build 9 wciąż "waiting for review", user chce mieć gotową kolejną paczkę (dzisiejsze zmiany: Budget, Places to visit per dzień, Home Upcoming Trip + Explorer Score, branded outro, usunięta Travel Replay, naprawiony format liczb i lokalizacja miast) do wysłania OD RAZU po zatwierdzeniu buildu 9, bez czekania na kolejną sesję.

`project.yml`: `CFBundleVersion` 9→10 (`CFBundleShortVersionString` zostaje 1.0.2). `xcodegen generate` → `xcodebuild archive` (`build/PMemories_build10.xcarchive`) → `xcodebuild -exportArchive` (`build/export10/PMemories.ipa`, 14MB). **NIE wywołany `altool` — celowo, zgodnie z jawną prośbą usera "czekamy"**.

Sprawdzone w `ContentDelivery.log` (nie zgadywane): eksport z `destination: export` i tak tworzy rekord `buildUploads` (AWAITING_UPLOAD) po stronie App Store Connect jako standardowy krok metody `app-store-connect` — ale to TYLKO metadane, żaden bajt binarki nie został przesłany (`buildUploadFiles` puste, dokładnie ten sam wzorzec co przy buildzie 9 przed użyciem `altool`). Jutro po potwierdzeniu usera: `xcrun altool --upload-app -f build/export10/PMemories.ipa ...` dokończy WŁAŚNIE TEN rekord (`Delivery ID 81e05b43-9559-46ba-8355-40862e725794`).

**Stan na koniec sesji**: build 9 (1.0.2) — waiting for review u Apple. Build 10 (1.0.2) — gotowy lokalnie, NIE wysłany, czeka na sygnał usera po zatwierdzeniu buildu 9.

## 13.08.2026, ciąg dalszy — build 10 (1.0.2) wysłany

User: "dobra wrzucamy build 10" — `xcrun altool --upload-app` na wcześniej przygotowanym `build/export10/PMemories.ipa`, hasło z Keychain (`PMemoriesUpload`), bez pytania usera ponownie. **UPLOAD SUCCEEDED** — 14MB w 6.3s, Delivery UUID `81e05b43-9559-46ba-8355-40862e725794` (ten sam rekord zarejestrowany wczoraj przy eksporcie). Czeka na przetworzenie przez Apple.

## 13.08.2026, ciąg dalszy — Ranking pokazywał zaokrąglony dystans zamiast prawdziwego

User: "dlaczego w rankingu pokazuje mi 40000 km a na pierwszej stronie 39,955?" — nie błąd formatowania (to już naprawione wczoraj), tylko realna, inna liczba.

**Diagnoza**: `LeaderboardService.swift`'s `ExplorerScore.rawKm` odtwarzał dystans z JUŻ ZAOKRĄGLONYCH punktów Explorer Score (`points = (totalKm / 100).rounded()`, potem `rawKm = points * 100`) — dla 39 955 km: `399.55.rounded()` = 400, `400 * 100` = **40 000**. Punkty specjalnie zaokrąglają (to normalne dla punktacji), ale appka używała TEJ zaokrąglonej wartości jako wyświetlanej liczby km w rankingu, zamiast prawdziwego dystansu — dokładnie ta rozbieżność co zauważył user.

**Naprawa**: `ExplorerScore` (`TravelAchievements.swift`) dostał nowe pole `let totalKm: Double` — PRAWDZIWY, dokładny dystans liczony obok punktów (już i tak liczony wewnątrz `explorerScore(from:)`, tylko wcześniej nigdzie nie wystawiany). `rawKm` USUNIĘTE z `LeaderboardService.swift` — oba miejsca wysyłające wynik do rankingu (`LeaderboardView.refresh()`, `OnboardingView.handleSignIn()`) używają teraz `score.totalKm`/`myScore.totalKm` zamiast odtwarzania z punktów. `rawCountries`/`rawCities` NIE dotyczy tego bugu (dzielenie/mnożenie bez straty precyzji, bo liczby całkowite) — zostały bez zmian.

Build → **BUILD SUCCEEDED**, zainstalowane, `devicectl` potwierdza proces żywy (PID 61234). **Do przetestowania przez usera**: wejść w Ranking (odświeży wynik przy wejściu) i sprawdzić że pokazuje teraz "39,955 km" zamiast "40,000 km".

## 13.08.2026, ciąg dalszy — Ukryte odznaki + Publiczny profil odkrywcy

User: "wprowadźmy lokalnie ukryte odznaki i publiczny profil" — dwie z rzeczy wybranych z wczorajszej rundy feedbacku o retencji.

**Ukryte odznaki** (`TravelAchievements.swift` — `HiddenBadge`, `TravelAchievementsCalculator.hiddenBadges(from:)`): trzy binarne (odblokowana/nie, bez progów) odznaki liczone z JUŻ zapisanych `SavedTrip`/`SavedStop`, zero nowych danych: 🦉 **Night Owl** (przyjazd między północą a 4 rano — godzina z `arrivalDate`), 🌐 **Equator Crosser** (dwa KOLEJNE przystanki w tej samej podróży z różnym znakiem szerokości geograficznej — prawdziwe przekroczenie w trakcie trasy, nie tylko "był kiedyś na północy i południu"), 🦅 **Bird's Flight** (pojedynczy odcinek lotem > 10 000 km). Sekcja "🥚 Secret Badges" w `AchievementsView` renderuje się TYLKO gdy user faktycznie coś odblokował — świadomie bez szarej "do zdobycia" wersji, żeby zostały prawdziwą niespodzianką.

**Publiczny profil odkrywcy** — nowy plik `ExplorerProfileTransfer.swift` (`ExplorerProfileDTO`, `ExplorerProfileService`), ten sam wzorzec co link do współdzielenia podróży (12.08.2026): jednorazowy snapshot na VPS, nie żywe połączenie. Przycisk w `TravelPassportView.swift` (toolbar, async-prepared `ShareLink`, ten sam mechanizm co w `TripPlanningView`). Backend: `/opt/pmemories_share_server.py` na VPS rozszerzony o `/pmemories/api/profiles` (POST, bez wygasania — profil nie ma naturalnej daty ważności jak wylot) i `/pmemories/profile/<id>` (HTML z Open Graph, pieczątki paszportowe + Explorer Score + statystyki, gradient marki). Backup pliku przed edycją (`pmemories_share_server.py.bak_*`), zdeployowane, `systemctl restart`, **przetestowane round-trip przez `curl`** (POST→GET JSON→GET HTML, wszystko poprawne) ORAZ **regresja starego mechanizmu linków do podróży sprawdzona i potwierdzona nietknięta** — testowe rekordy usunięte po weryfikacji.

**Lokalizacja** — 8 nowych kluczy × 27 języków (7 dla odznak: "Night Owl", "Arrived somewhere between midnight and 4am", "Equator Crosser", "Travelled from one hemisphere to the other", "Bird's Flight", "A single flight over 10,000 km", "Secret Badges"; 1 dla profilu: "Couldn't create profile link").

Build → **BUILD SUCCEEDED**, zainstalowane, `devicectl` potwierdza proces żywy (PID 61658). **Do przetestowania przez usera**: sprawdzić Badges pod kątem ukrytych odznak (jeśli któraś z zapisanych podróży spełnia warunki, powinna się pojawić); wejść w Travel Passport i wygenerować/wysłać link publicznego profilu, otworzyć go w przeglądarce.

## 13.08.2026, ciąg dalszy — druga partia ukrytych odznak + naprawa "2 kliknięcia" przy udostępnianiu profilu

User: "które odznaki możemy zrobić to je robimy, resztę odkładamy na listę TODO, do tego zróbmy jeszcze raz test udostępniania".

**Druga partia ukrytych odznak** (`TravelAchievements.swift`, `hiddenBadges(from:projects:)` — sygnatura rozszerzona o `projects: [SavedProject]`) — 8 nowych, wszystkie liczone z JUŻ istniejących danych, zero nowych pól: 🌎 **Globetrotter** (3+ kraje w jednej podróży, liczone PER PODRÓŻ, nie życiowo jak zwykła odznaka Kraje), 🏙️ **City Hopper** (5+ miast w jednej podróży), 🔄 **Around the Block** (dowolne dwa przystanki w tej samej podróży, ta sama nazwa miasta, różnica dat przyjazdu ≤24h), 🎬 **Memory Maker** (pierwszy WYEKSPORTOWANY projekt — `exportedAssetIdentifier != nil`, niedokończone projekty się nie liczą), 🎞️ **Director's Cut** (jeden Memory ze zdjęciami I wideo I muzyką razem), 📸 **The Collector** (Memory ze 100+ elementami), ✨ **Storyteller** (10+ wyeksportowanych Memories), 🗄️ **Archivist** (Memories powiązane z 5+ różnymi podróżami przez `linkedProjectID`).

**Świadomie ODŁOŻONE do `TODO.md`** (nie dają się dziś zbudować bez dodatkowej pracy) — dokładna lista przyczyn w `Travel.md`: Red Eye/Midnight Traveler (appka nie śledzi godziny odlotu dla ODBYTYCH podróży, tylko w Trip Planning), Three Continents (brak mapowania kraj→kontynent), Coastal/Island (brak klasyfikacji geograficznej), Wrong Way (brak pojęcia "zaplanowana trasa"), Pedal Power (brak roweru jako środka transportu), Spontaneous/Last Minute/No Plan (dane `PlannedTrip` są KASOWANE po konwersji na Memory — badge oparty na nich zniknąłby wraz z konwersją, wymaga osobnego przemyślenia gdzie/kiedy to zapisać), Rare Achievement/globalna rzadkość (wymaga nowej infrastruktury CloudKit).

**Naprawiony realny bug "działa dopiero za drugim kliknięciem"** — user powtórzył test z podłączoną konsolą DWA razy, za każdym razem to samo zachowanie (konsola nic nie pokazała — appka nie ma logów dla tego przycisku, cisza nie potwierdzała ani nie wykluczała błędu). Znalezione przez analizę kodu, nie zgadywanie: wzorzec "Button → po async przygotowaniu zamienia się w ShareLink" (ten sam co przy udostępnianiu podróży w `TripPlanningView.swift`) ma ukrytą wadę — zamiana Button→ShareLink NIE otwiera automatycznie okna, user musi tapnąć PONOWNIE już w nowy, inny widok. Naprawa w `TravelPassportView.swift`: JEDEN stały przycisk, `UIActivityViewController` (`ActivityShareSheet`, nowy `UIViewControllerRepresentable`) prezentowany RĘCZNIE przez `.onChange(of: profileLinkURL)` w momencie gdy link staje się gotowy — okno otwiera się samo, bez drugiego tapnięcia. Kolejne tapnięcia (link już gotowy) otwierają arkusz od razu, bez nowego zapytania do serwera.

**Nieprzetestowane jeszcze**: czy TEN SAM utajony problem dotyczy też przycisku udostępniania podróży w `TripPlanningView.swift` (identyczny wzorzec Button→ShareLink) — nie zgłoszony jako zepsuty, ale prawdopodobnie ma tę samą wadę, po prostu niezauważoną. Do sprawdzenia/naprawienia w kolejnej sesji jeśli się potwierdzi.

Build → **BUILD SUCCEEDED**, zainstalowane — telefon zablokowany w momencie instalacji, appka NIE uruchomiona zdalnie (do otwarcia ręcznie).

## 13.08.2026, ciąg dalszy — dedykowana domena pmemories.duckdns.org

User: "czy możemy zamiast używać domeny piotrmarkowski zrobić PMemories?" — chciał osobną, dedykowaną domenę zamiast dzielenia z osobistym portfolio. Sam założył `pmemories.duckdns.org` (DuckDNS, to samo IP VPS).

**VPS**: backup nginx configu przed zmianą (`portfolio.bak_*_before_pmemories_domain`). Nowy blok `server` dla `pmemories.duckdns.org` w tym samym pliku (`/etc/nginx/sites-available/portfolio`) — TE SAME ścieżki backendu (`/pmemories/...`, proxy do `127.0.0.1:8091`), zero zmian w `pmemories_share_server.py`. Nowy plik `apple-app-site-association-pmemories` (ta sama treść co dla starej domeny, `/pmemories/trip/*`). Certyfikat SSL wygenerowany automatycznie przez `certbot --nginx -d pmemories.duckdns.org` (Let's Encrypt, wygasa 2026-11-11, auto-odnawianie skonfigurowane). Przetestowane round-trip przez `curl` — AASA (200, poprawna treść) + pełny cykl POST/GET testowej podróży przez nową domenę, testowy rekord usunięty po weryfikacji.

**App**: `project.yml` — `com.apple.developer.associated-domains` dostał DRUGI wpis (`applinks:pmemories.duckdns.org`), stara domena ZOSTAJE obok (żeby wcześniej wysłane linki nie przestały działać). `ShareLinkService`/`ExplorerProfileService` (`PlannedTripTransfer.swift`/`ExplorerProfileTransfer.swift`) — `baseURL` zmieniony na nową domenę, WSZYSTKIE nowe linki od teraz idą przez `pmemories.duckdns.org`. `HomeView.importTrip(from:)` — akceptuje OBIE domeny przy odbiorze linku (nowe i stare linki działają jednakowo).

Build → **BUILD SUCCEEDED** (jedna przejściowa blokada telefonu przerwała pierwszą próbę builda — `xcodebuild` nie może zamontować obrazu deweloperskiego na zablokowanym urządzeniu, druga próba po odblokowaniu zadziałała), zainstalowane, `devicectl` potwierdza proces żywy (PID 1509). **Do przetestowania przez usera**: wysłać nową podróż/profil linkiem i sprawdzić że URL zaczyna się teraz od `pmemories.duckdns.org` zamiast `piotrmarkowski.duckdns.org`, i że nadal poprawnie otwiera appkę (Universal Link) zamiast Safari.

## 15.08.2026 — realny bug od narzeczonej: brandowa końcówka czasem znika przy re-eksporcie

User: "moja narzeczona robiła filmik za pierwszym razem, końcówka była jak ustaliliśmy PMemories — jak edytowała i zapisała znowu, już końcówki nie było, sprawdź co może być za to odpowiedzialne, trzeba to naprawić". Pierwszy realny bug zgłoszony przez OSOBĘ TESTUJĄCĄ appkę na prawdziwym, emocjonalnym materiale (film na pierwsze urodziny dziecka dla przyjaciółki).

**Diagnoza (bez możliwości złapania na żywo — narzeczona nie testowała w tej chwili)**: przegląd kodu `EditView.performExport()` ujawnił realną lukę — dodawanie karty brandingowej PMemories było opakowane w `if let ... = renderBackgroundImage(...), let ... = try? ImageToVideoRenderer.render(...)`. Gdy KTÓREKOLWIEK z tych dwóch (renderowanie SwiftUI→obraz albo enkodowanie obrazu→wideo) zawiedzie z JAKIEGOKOLWIEK powodu (np. chwilowy brak pamięci — prawdopodobne przy re-eksporcie już otwartego, edytowanego projektu, gdzie appka ma więcej załadowanych danych w pamięci niż przy świeżym starcie), appka PO CICHU kontynuowała resztę eksportu bez karty — zero błędu, zero śladu, dokładnie pasuje do zgłoszonego objawu.

**Naprawa** — `PMemoriesOutroCardRenderer.swift`: nowa funkcja `renderOutroClip(size:)` z JEDNYM ponowieniem (2 próby łącznie) + jawny `print("⚠️ PMemories outro: ...")` przy każdej porażce, żeby przyszła diagnoza (jeśli się powtórzy) miała ślad w konsoli zamiast całkowitej ciszy. `EditView.swift` uproszczone do wywołania tej jednej funkcji zamiast inline'owej logiki z cichym `try?`.

**Uczciwie**: to NIE jest stuprocentowo potwierdzona przyczyna (nie było jak złapać na żywo na jej telefonie w momencie awarii) — to jedyne miejsce w kodzie, które może się zachować dokładnie tak jak opisano (brak błędu, brak śladu, tylko brakujący element), więc najbardziej prawdopodobny winowajca. Ponowienie + logowanie realnie zmniejsza szansę powtórki i ułatwi diagnozę, jeśli się jednak powtórzy.

## 16.08.2026 — ciąg dalszy: doprecyzowanie tego samego buga, druga przyczyna znaleziona i naprawiona

User doprecyzował TEN SAM stary filmik narzeczonej (nie nowy test): "widziałem filmik i ostatnia strona się pojawiła, ale nie wyświetliły się napisy tak jak planowaliśmy". To ZMIENIA diagnozę z 15.08.2026 — klip TŁA outro wcale nie zniknął całkowicie, wyrenderował się poprawnie; zawiodła wyłącznie WARSTWA TEKSTU nad nim.

**Druga, bardziej prawdopodobna przyczyna**: outro (od 13.08.2026) trzymało JEDEN stały klip tła i animowało tekst NAD nim przez `CATextLayer`/`AVVideoCompositionCoreAnimationTool` — dokładnie ten sam mechanizm co animowane napisy (`VideoComposer.animationTool`/`outroTextLayers`). To DRUGI, niezależny mechanizm w tej samej karcie, który może po cichu zawieść bez śladu w logach — sama nakładka tekstowa w kontekście eksportu (`AVVideoCompositionCoreAnimationTool`) jest już RAZ udokumentowanym źródłem cichych awarii w tym projekcie (patrz 31.07.2026, bug z `UIFont` zamiast `CTFont` w napisach) — teraz najwyraźniej zawiodła po raz drugi, mimo poprawnej konwersji na `CTFont`, w bardziej subtelny sposób (dokładna przyczyna nieznana — nie było jak złapać na żywo).

**Naprawa — zamiast dalej łatać zawodny mechanizm, usunięty jego zależność w tej karcie**: `PMemoriesOutroCardRenderer.swift` przepisany tak, żeby tekst KAŻDEJ fazy był wypalony bezpośrednio w pikselach przez `ImageRenderer` (ten sam, sprawdzony mechanizm co samo tło gradientowe) — zero `CATextLayer` dla outro. Dwie fazy (✨+PMemories+tagline, potem samo Coming soon) renderują się teraz jako DWA osobne krótkie klipy (`renderOutroClips(size:) -> [URL]`, każdy z własnym ponowieniem 2 prób jak wczoraj), sklejone standardowym `.crossfade` z `VideoComposer` (`MediaItem.transitionStyle`). Tło jest IDENTYCZNE piksel w piksel w obu fazach, więc przenikanie widać TYLKO jako zmianę tekstu — wizualnie nadal jedna ciągła scena, spełnia oryginalne "jeden ekran, nie sklejone slajdy" bez polegania na zawodnej nakładce tekstowej w momencie eksportu.

`VideoComposer.swift` — usunięty cały martwy kod obsługujący outro przez nakładkę (`outroStartTime`, `outroTextLayers`, wołanie `animationTool` z parametrem outro) — `animationTool` wraca do obsługi WYŁĄCZNIE napisów, które nadal używają `CATextLayer` (nie dotyczy ich ta zmiana, tylko outro).

Build → **BUILD SUCCEEDED**, zainstalowane (`devicectl install app`, potwierdzone). **Do przetestowania przez usera**: nowy eksport (najlepiej dokładnie ten sam scenariusz — stworzyć, sprawdzić końcówkę, edytować, zapisać ponownie, sprawdzić drugi raz) — tym razem tekst nie zależy już od nakładki, więc powinien pojawiać się niezawodnie razem z tłem za każdym razem.

## 16.08.2026, ciąg dalszy — żywa synchronizacja Shared Trip przez istniejący VPS

User zgłosił kolejny realny przypadek: narzeczona dodała miejsca do odwiedzenia i wpisała koszty w SWOJEJ kopii podróży, u usera się to nie pojawiło mimo restartu appki. Wyjaśnione userowi: dotychczasowe udostępnianie (`ShareLinkService`, 12.08.2026) to JEDNORAZOWA kopia JSON przez serwer — po zaimportowaniu obie strony mają NIEZALEŻNE dane, żadna edycja nigdy się nie propaguje, restart appki nic nie zmienia (to nie bug, tak było zaprojektowane). Wcześniejsza próba żywego współdzielenia przez `CKShare`/SwiftData (12.08.2026) została COFNIĘTA tego samego dnia (brak publicznego API CKShare w SwiftData + realne ryzyko utraty widoku na dane, patrz `PMemoriesAppApp.swift`).

User: "mamy server ktory moze dzialac do wymiany tych danych wiec dzialamy" — zamiast wracać do CKShare/CloudKit (duży, osobny temat), rozbudowany JUŻ ISTNIEJĄCY serwis `pmemories_share_server.py` o PUSH/PULL pod TYM SAMYM ID zamiast jednorazowego zapisu.

**VPS** (`/opt/pmemories_share_server.py`, backup przed zmianą): nowy `do_PUT` na `/pmemories/api/trips/<id>` — nadpisuje TYLKO istniejący rekord (404 gdy ID nieznane, żeby PUT nie tworzył śmieciowych wpisów pod dowolnym stringiem). Przetestowane round-trip przez `curl` (POST → GET → PUT → GET pokazuje zmianę → PUT na nieistniejące ID = 404), testowy rekord posprzątany, usługa zrestartowana.

**App**: `PlannedTrip` dostał `shareID: String?` (16.08.2026) — TO SAMO ID po obu stronach po pierwszym share/imporcie z linku (import z pliku `.pmtrip`, offline, zostaje BEZ `shareID` — nie ma z czym się synchronizować). `ShareLinkService.updateSharedTrip(id:dto:)` (PUT) + `tripURL(id:)` (budowa linku z już znanego ID bez nowego wywołania sieciowego — zapobiega tworzeniu DRUGIEGO równoległego rekordu przy kolejnym tapnięciu Share). `TripTransferDTO.makePlannedStops()` wydzielone (`fileprivate`) z `makePlannedTrip()`, reużyte w nowym `PlannedTrip.applyRemoteUpdate(_:modelContext:)` — nadpisuje ISTNIEJĄCY obiekt `@Model` na miejscu (stare przystanki kasowane kaskadowo, nowe wstawiane z DTO), żeby `@Bindable` widok się sam przemalował.

`TripPlanningView.PlannedTripDetailView`: PUSH automatyczny po "Done" (`pushShareUpdateIfNeeded`, ciche niepowodzenie + `print` przy błędzie — appka nie blokuje zamykania edycji na wywołanie sieciowe). PULL RĘCZNY nowym przyciskiem odświeżania (🔄, widoczny tylko gdy `trip.shareID != nil`) — świadomie bez auto-polling w tle. "Ostatni zapis wygrywa", zero scalania konfliktów pole-po-polu — wystarczające dla 2-3 osób planujących wspólnie.

**Lokalizacja** — 1 nowy klucz × 27 języków ("Refresh shared trip", accessibility label przycisku odświeżania).

Build → **BUILD SUCCEEDED**, zainstalowane (`devicectl install app`, potwierdzone) — telefon zablokowany w momencie instalacji, appka NIE uruchomiona zdalnie. **Do przetestowania przez usera**: udostępnić podróż narzeczonej (albo odwrotnie), jedna strona coś zmienia i zamyka edycję (Done), druga strona wchodzi w tę podróż i tapnięcie 🔄 powinno pociągnąć nowe dane.

## 16.08.2026, ciąg dalszy — auto-PULL przy wejściu w podróż

User: "nie da się zrobić żeby bez odświeżania się to zmieniało tylko w momencie jak otworzymy apkę?" — zamiast wymagać tapnięcia 🔄, `PlannedTripDetailView` dostał `.task { if !isEditing { await pullLatestSharedVersion() } }` — odpala się automatycznie za każdym wejściem w ekran podróży (nowe pchnięcie w `NavigationStack`), pomijane podczas `isEditing` (żeby nie nadpisać czyichś niezapisanych zmian w trakcie edycji zdalną wersją). Przycisk 🔄 ZOSTAJE jako dodatkowa opcja do ręcznego sprawdzenia bez wychodzenia z ekranu.

Build → **BUILD SUCCEEDED**, zainstalowane.

## 17.08.2026 — dwie drobne poprawki zgłoszone przez narzeczoną usera

**Bug: przycisk Share w Trip Planning wymagał 2 kliknięć.** DOKŁADNIE ten sam wzorzec co naprawiony 13.08.2026 w `TravelPassportView` (flagowany wtedy jako "nieprzetestowane, prawdopodobnie ta sama wada, nie zgłoszona jako zepsuta") — teraz potwierdzony przez narzeczoną usera przy udostępnianiu zaplanowanej podróży. `ActivityShareSheet` (prywatny `UIViewControllerRepresentable` w `TravelPassportView.swift`) odkryty na `internal`, reużyty w `TripPlanningView.PlannedTripDetailView`: JEDEN stały przycisk Share zamiast zamiany Button→ShareLink, `.onChange(of: shareLinkURL)` + `.sheet` otwiera okno automatycznie gdy link jest gotowy. `prepareShareLink()` dodatkowo jawnie otwiera arkusz gdy `shareLinkURL` już istnieje w bieżącej sesji widoku (`.onChange` nie odpaliłby się drugi raz na TĘ SAMĄ wartość).

**Feature: pierwszy przystanek (miejsce wylotu) nie potrzebuje noclegu.** User: "miejsce wylotu nie potrzebuje noclegu itp, przecież to jest miejsce skąd zaczynamy naszą podróż". Pola noclegu były już i tak zawsze OPCJONALNE (nikt nigdy nie musiał ich wypełniać) — problemem było samo POKAZYWANIE sekcji "Add accommodation"/dat pobytu dla miasta startowego, co sugerowało że trzeba to zrobić. `PlannedStopRow` (`TripPlanningView.swift`) — `accommodationSection`/`stayDatesSection` przeniesione pod `if !isFirst`, ten sam warunek co już istniejący dla `transportPicker`/`transportTimesSection` (ten sam duch: nic "do" pierwszego miasta nie dojeżdża/nie nocuje się w nim w ramach TEJ podróży). Dane ewentualnie już wpisane wcześniej NIE są kasowane — tylko pole znika z formularza edycji.

Build → **BUILD SUCCEEDED**, zainstalowane (`devicectl install app`, jedna przejściowa blokada tunelu przy pierwszej próbie — "device disconnected immediately after connecting", druga próba zadziałała od razu). **Do przetestowania**: Share na zaplanowanej podróży powinien otworzyć okno za PIERWSZYM tapnięciem; pierwszy przystanek w edycji nie powinien już pokazywać sekcji noclegu/dat pobytu.

**Odłożone na po pracy usera**: automatyczne śledzenie trasy GPS z przełącznikiem włącz/wyłącz w appce — omówione (research: jak działa Polarsteps — ręczny start/stop per podróż, "Always" nie jest trudne do uzasadnienia w App Store Review, ~4%/dzień baterii przy ich oszczędnym podejściu WiFi/cell). Ustalone z userem: (1) start/stop RĘCZNIE per podróż jak Polarsteps, (2) dokładniejszy prawdziwy GPS zamiast oszczędnego WiFi/cell, (3) efekt = TYLKO rysowanie realnej trasy na mapie, bez auto-tworzenia przystanków. Foreground vs background (kluczowe dla kosztu baterii przy wybranej wysokiej dokładności) — jeszcze NIE ustalone, do dograna przed implementacją.

## 17.08.2026, ciąg dalszy — build 11 (1.0.2) wysłany

User: "wrzućmy nowy build z poprawkami bez zmiany nr [wersji], zmiana nr będzie jak będzie większy update" — `CFBundleVersion` 10→11 w `project.yml`, `CFBundleShortVersionString` zostaje "1.0.2". `xcodegen generate` → archive (Release) → export (`build/export11/`, ten sam sprawdzony `ExportOptions.plist` co poprzednie buildy, `destination: export`, NIE bezpośredni upload).

**Przeszkoda po drodze**: eksport padł — sesja konta deweloperskiego w Xcode wygasła ("Your session has expired"). User zalogował się ponownie ręcznie, eksport powtórzony → **EXPORT SUCCEEDED**. Kolejna przeszkoda: zapisane w Keychain hasło aplikacji (`PMemoriesUpload`) przestało działać (`altool` error -22910, "sign in with app-specific password") — najwyraźniej unieważnione przy okazji ponownego logowania. User wygenerował NOWE hasło aplikacji na `account.apple.com` (Sign-In & Security → App-Specific Passwords — po drodze Apple raz zażądało potwierdzenia tożsamości hasłem+2FA, normalne zabezpieczenie), stare wpis w Keychain usunięty i zastąpiony nowym (`security delete-generic-password` + `add-generic-password`, ten sam `svce`/`acct` co dotąd). `altool --upload-app` → **UPLOAD SUCCEEDED**, 14MB w ~1.3s, Delivery UUID `64254c36-1cf6-480c-8e62-8f6cdc9d2890`.

**Zawartość build 11** (wszystko od build 10, 13.08.2026): precyzja km w Rankingu, druga partia ukrytych odznak, Publiczny profil odkrywcy, naprawa "2 kliknięcia" przy udostępnianiu profilu, dedykowana domena `pmemories.duckdns.org`, dwukrotna naprawa brandowej końcówki PMemories (retry przy renderowaniu, potem tekst wypalony w pikselach zamiast zawodnej nakładki `CATextLayer`), żywa synchronizacja Shared Trip (push po edycji, auto-pull przy wejściu w podróż, ręczne odświeżanie), naprawa "2 kliknięcia" przy udostępnianiu zaplanowanej podróży, pierwszy przystanek bez sekcji noclegu.

Czeka na przetworzenie przez Apple / recenzję TestFlight.

## 17/18.08.2026 — przebudowa kolejności/prezentacji formularza edycji Trip Planning

User przesłał rozbudowany, ChatGPT-owy feedback UX: funkcjonalnie appka jest OK, ale kolejność informacji w edycji jest odwrócona — user od razu po "New Trip" widzi Budget (waluta/koszty) zanim w ogóle wpisał dokąd jedzie. Zgodziłem się z sednem, ale NIE z jednym elementem feedbacku (rozbicie na osobne top-level sekcje "Route"/"Stay & activities"/"Transport details" jako równoległe listy — to byłby krok wstecz względem dzisiejszego grupowania WSZYSTKIEGO per przystanek). Zaproponowana przeze mnie minimalna wersja (tylko Budget na dół + jawna opcja "No accommodation") ODRZUCONA przez usera: **"nie nie nie, róbmy to porządnie jak ma być, nie żeby tylko było"** — zaplanowana i zbudowana pełniejsza przebudowa (`EnterPlanMode`, plan zapisany, zaakceptowany).

**Reorder `editForm`** (`TripPlanningView.swift`) — było: Tytuł/opis → **Budget** → Daty → Przystanki. Jest: Tytuł/opis → Daty → **Przystanki** → **Budget** (na koniec). Czysta zmiana kolejności trzech istniejących `Section`, zero zmian w zawartości.

**Nagłówek "kroku" w `PlannedStopRow`** — nowy parametr `stepIndex: Int` (zamiast samego `isFirst`, teraz liczone jako `stepIndex == 1`). Każdy wiersz dostał nagłówek NA GÓRZE: pierwszy przystanek "1 · 🏁 Starting point" (statyczny, bez transportu), kolejne "N ·" + PRZENIESIONY tam `transportPicker` (ta sama logika/binding co dotąd, tylko inne miejsce — tryb transportu widoczny NAJPIERW, zanim user dojdzie do nazwy miasta, zamiast być zagrzebany niżej w środku wiersza). Świadomie NIE rozbite na osobne `Section` per przystanek (złamałoby cross-item `.onMove`/`.onDelete` — SwiftUI `List` nie reorderuje między osobnymi `Section`ami tak prosto jak w jednym `ForEach`) — nadal JEDEN ciągły `ForEach`, cały wiersz z nagłówkiem przesuwa się razem przy drag-reorderze.

**"No accommodation" jako jawna opcja** (`accommodationSection`) — dawniej: `Menu` z listą typów + WARUNKOWY przycisk "Remove" widoczny tylko PO wyborze, etykieta pustego stanu "Add accommodation" (sugerowała brakujący krok mimo że pominięcie jest w pełni poprawne). Teraz: "No accommodation" jest PIERWSZĄ, zawsze widoczną pozycją menu (ta sama akcja co dawny "Remove"), etykieta pustego stanu zmieniona na "No accommodation" — uczciwie opisuje faktyczny domyślny stan.

**`summaryView`** — `budgetSummarySection` przeniesiony z pozycji przed `timelineSection` na pozycję PO niej, tuż przed `convertSection`, dla spójności z tą samą filozofią w widoku tylko-do-odczytu.

**Lokalizacja** — 2 nowe klucze × 27 języków ("No accommodation", "Starting point").

Build → **BUILD SUCCEEDED**, zainstalowane (`devicectl install app`, potwierdzone). **Do przetestowania przez usera**: nowa/istniejąca podróż w edycji — kolejność Tytuł→Daty→Przystanki (z numerem kroku + trybem transportu na górze każdego)→Budget na końcu; Menu Accommodation z "No accommodation" jako pierwszą pozycją; drag-reorder przystanków (☰ w trybie edycji) nadal działa między wszystkimi przystankami; podgląd pokazuje Budget po Itinerary, przed Convert.

## 18.08.2026, ciąg dalszy — "Places to visit" też ukryte dla pierwszego przystanku

User zauważył tę samą lukę co przy noclegu dzień wcześniej: "skoro wylatujesz z jednego miasta żeby zobaczyć inne, po co w mieście startowym mamy Places to visit — żeby zobaczyć lotnisko czy toaletę na nim?". Trafne — `placesToVisitSection` w `PlannedStopRow` była JEDYNĄ sekcją zostawioną poza `if !isFirst`, mimo że dokładnie ta sama logika (miasto startowe to punkt wylotu, nie cel zwiedzania) już zastosowana dzień wcześniej do noclegu/dat pobytu. Przeniesiona pod ten sam warunek, razem z `accommodationSection`/`stayDatesSection`. `notesField` ZOSTAJE dostępne dla pierwszego przystanku (notatki typu "zostawić auto na długoterminowym parkingu C" mają sens nawet dla punktu wylotu).

Build → **BUILD SUCCEEDED**, zainstalowane.

## 18.08.2026, ciąg dalszy — "Next city" → "Destination"

User: "zamiast next city możemy to nazwać inaczej?" — pytanie o alternatywę, nie konkretną nazwę, więc zapytany o wybór między "Destination"/"City"/"Arriving in" (`AskUserQuestion`). Wybrane: **"Destination"** — krótkie, pasuje do kontekstu nagłówka kroku nad polem (`headerRow`, "N · ✈️ Plane"), który już mówi że to KOLEJNY krok trasy, więc samo pole nie musi tego powtarzać. Zmiana TYLKO w `TripPlanningView.swift` (Trip Planning) — świadomie NIE dotknięty identyczny label w `TravelMapView.swift` (`StopRow`, Travel Map), bo to inna funkcja (trasa już odbytej podróży, bez nagłówka kroku który uzasadniałby skrócenie etykiety) i user nie zgłaszał tam problemu.

**Lokalizacja** — 1 nowy klucz × 27 języków ("Destination").

Build → **BUILD SUCCEEDED**, zainstalowane.

## 18.08.2026, ciąg dalszy — Departure time przy mieście źródłowym, Arrival przy docelowym

User: "departure time powinien być przy mieście startowym?" — trafna uwaga. Dotąd `transportTimesSection` pokazywała OBA pola (Departure + Arrival) RAZEM w wierszu miasta DOCELOWEGO, bo appka historycznie trzyma `transportDepartureTime`/`transportArrivalTime` przy przystanku do którego się dojeżdża (patrz `PlannedTrip.departureTimeToday`: "transport DO drugiego przystanku"). Zapytany o sposób rozwiązania (`AskUserQuestion`, dwie opcje: rozdzielić pola na dwa wiersze VS zostawić razem i tylko dopisać nazwę miasta źródłowego w etykiecie) — user wybrał **rozdzielenie**.

`PlannedStopRow` dostał nowy parametr `nextStop: PlannedStop?` (przekazywany z `editForm`, `nil` dla ostatniego przystanku) — używany WYŁĄCZNIE do edycji `nextStop.transportDepartureTime` z TEGO wiersza. Dawna `transportTimesSection` (jeden wspólny `HStack`) zastąpiona `transportTimesRow`: Arrival time pokazuje się gdy `!isFirst` (własne pole, bez zmian logiki), Departure time pokazuje się gdy `nextStop != nil` i edytuje pole SĄSIEDNIEGO przystanku przez ręcznie skonstruowany `Binding`. Efekt dla trasy Londyn→Tokio→Kioto: Londyn pokazuje TYLKO Departure (do Tokio), Tokio pokazuje Arrival (z Londynu) ORAZ Departure (do Kioto), Kioto (ostatni) pokazuje TYLKO Arrival. Żadnych zmian w miejscu PRZECHOWYWANIA danych (DTO/transfer/`departureTimeToday` nietknięte) — zmieniło się tylko z KTÓREGO wiersza formularza pole jest edytowane.

Build → **BUILD SUCCEEDED**, zainstalowane.

## 18.08.2026, ciąg dalszy — koszt biletu PER-ETAP trasy

User pokazał realną notatkę z planowania własnej podróży do Tajlandii — szczegółowy plan dzień-po-dniu z kosztami PER atrakcja/etap, m.in. bilety wewnętrzne Bangkok→Chiang Mai (£102) i Chiang Mai→Phuket (£200) jako OSOBNE kwoty obok głównego biletu powrotnego (£1500). Appka dotąd miała tylko JEDEN zbiorczy `PlannedTrip.flightCostAmount` na całą podróż — realna luka względem tego jak ludzie faktycznie planują wielo-etapowe trasy. Zapytany o zakres (`AskUserQuestion`: sam koszt per-etap transportu VS to + koszt per-miejsce-do-zobaczenia) — user wybrał węższy, bezpieczniejszy zakres: **koszt PRZY każdym etapie trasy**, nie per-atrakcja (to drugie zaczęłoby appkę zamieniać w pełny tracker wydatków, czego świadomie unikamy od 12.08.2026).

Nowe pole `PlannedStop.transportCostAmount: Double?` (`PlannedTripPersistence.swift`) — ten sam wzorzec co już istniejący `accommodationCostAmount`, w walucie całej podróży. Fizycznie żyje przy przystanku DOCELOWYM (spójne z `transportDepartureTime`/`transportArrivalTime`), ale edytowane z wiersza ŹRÓDŁOWEGO przez TEN SAM `nextStop` binding co Departure time (nowa `transportCostSection` w `PlannedStopRow`, tuż pod `transportTimesRow`) — w praktyce user wpisuje "£102" w tym samym miejscu co godzinę odjazdu, dokładnie jak w swojej notatce ("leaving to Chang Mai — 12:10 flight / Tickets to Chang Mai — £102").

`PlannedTrip.totalEstimatedCost` — suma dolicza teraz `transportCostAmount` WSZYSTKICH przystanków obok istniejącego `accommodationCostAmount`, poza trybem all-inclusive (bez zmian tam — jedna kwota już wszystko zawiera). `StopTransferDTO`/`transferDTO`/`makePlannedStops()` (`PlannedTripTransfer.swift`) zaktualizowane, żeby nowe pole przechodziło przez współdzielenie/synchronizację Shared Trip.

**Lokalizacja** — 1 nowy klucz × 27 języków ("Add transport cost").

Build → **BUILD SUCCEEDED**, zainstalowane.

## 18.08.2026, ciąg dalszy — "Gatwick Airport" zamieniało się w samo "Gatwick"

User: "jak wybieram Gatwick Airport w starting point, nazwa jest odrzucona i zamienia się w Gatwick". Znalezione w kodzie — `CitySearchCompleter.resolve()` (13.08.2026, naprawa "Londyn" mimo appki po angielsku) po wybraniu podpowiedzi ZAWSZE dogeokodowuje współrzędną i NADPISUJE nazwę wynikiem `CLGeocoder`'s `.locality` (miejscowość), żeby dostać nazwę w języku appki zamiast regionu telefonu. Dla zwykłych MIAST to poprawne, ale dla LOTNISK (i innych punktów zainteresowania) `.locality` to sama miejscowość obok ("Gatwick"), nie nazwa punktu ("Gatwick Airport") — relokalizacja po cichu gubiła konkretną nazwę.

Naprawa — `resolve()` sprawdza `item.pointOfInterestCategory` (dostępne z tego samego `MKLocalSearch` wyniku, zero dodatkowego zapytania): gdy wynik jest POI (lotnisko), relokalizacja jest POMIJANA, surowy tytuł z podpowiedzi zostaje bez zmian. Miasta (bez kategorii POI) zachowują się jak dotąd. Jeden punkt naprawy w `CitySearchCompleter.swift` naprawia to jednocześnie w Trip Planning i Travel Map (obie appki dzielą tę samą funkcję).

Build → **BUILD SUCCEEDED**, zainstalowane.

## 18.08.2026, ciąg dalszy — build 12 (1.0.2) wysłany

User: "wrzucamy build 12 bez zmiany 1.0.2" — `CFBundleVersion` 11→12 w `project.yml`, `CFBundleShortVersionString` zostaje "1.0.2" (ten sam wzorzec co build 11). `xcodegen generate` → archive (Release) → export (`build/export12/`, ten sam `ExportOptions.plist`) → `altool --upload-app` z hasłem z Keychain (`PMemoriesUpload`, to samo co wczoraj — sesja konta deweloperskiego i hasło aplikacji tym razem NIE wygasły, oba kroki przeszły za pierwszym razem, bez przeszkód). **UPLOAD SUCCEEDED**, 14MB w 2.8s, Delivery UUID `593c337c-973d-4212-b42a-378a81f4b797`.

**Zawartość build 12** (wszystko od build 11, 17.08.2026): przebudowa kolejności/prezentacji formularza Trip Planning (Budget na koniec, nagłówek kroku z trybem transportu, "No accommodation" jako jawna opcja), "Places to visit" ukryte dla pierwszego przystanku, "Next city" → "Destination", rozdzielenie Departure/Arrival time między przystanek źródłowy i docelowy, koszt biletu per-etap trasy (`transportCostAmount`), naprawa relokalizacji nazw lotnisk ("Gatwick Airport" nie zamienia się już w "Gatwick").

Czeka na przetworzenie przez Apple / recenzję TestFlight.

## 18.08.2026, ciąg dalszy — statyczny przegląd trasy (nowa mapa, tapnięcie = dystans/czas)

User pokazał ChatGPT-owy mockup: zdjęcia jako punkty trasy połączone stylizowanymi liniami wg środka transportu, tapnięcie punktu → "🚗 London → Sinaia · 184 km · 2h 31min". User: "to nie jest coś nowego, mapę już mamy... trzeba to tam tylko ładnie wpasować" — **sprawdzone w kodzie, tylko częściowo prawdziwe**: World Globe pokazuje wszystkie miejsca ze WSZYSTKICH podróży, ale bez linii tras; animowany przelot (`TravelMapAnimationView`/`TravelLiveMapView`) ma linie tras, ale samogrający, jeden odcinek naraz — żadna z dwóch nie jest "wszystko naraz, swobodnie przeglądalne". Zapytany który wariant rozbudować (`AskUserQuestion`) — user wybrał NOWY statyczny widok zamiast doklejania tapnięcia do samogrającego przelotu.

Zaplanowane w `EnterPlanMode` (plan zapisany, zaakceptowany) — reużycie istniejącej infrastruktury zamiast wynajdywania na nowo: `RouteProvider.route()` (te same trasy/style linii co przelot), wzorzec niezawodnego tapnięcia z `WorldGlobeView` (`Map(selection:)`+`.tag`, udokumentowany 30.07.2026 jako JEDYNY sprawdzony sposób w tym projekcie — `.onTapGesture`/`Button` wewnątrz `Annotation` przegrywają z gestem mapy), wizualny wzorzec markera z `GlobePlaceMarker`. **Świadomie ZERO zmian w modelu SwiftData** — zamiast nowego persystowanego pola na czas trwania odcinka (ryzyko migracji, patrz historia crashy 02.08/12.08.2026), nowy widok pobiera geometrię+czas KAŻDEGO odcinka NA ŻYWO przy otwarciu (dokładnie to co przelot i tak robi, tu dla wszystkich odcinków naraz).

**`RouteProvider.swift`** — `RouteResult` dostał `durationMinutes: Double`. Dla odcinków z prawdziwym trasowaniem (`MKDirections`) czytane `route.expectedTravelTime` — dane BYŁY już w odpowiedzi, po prostu wcześniej odrzucane bez użycia. Dla fallbacków bez realnego API czasu (samolot/prom/statek wycieczkowy, nazwany szlak z Overpass, ostateczny fallback geodezyjny) — nowa `estimatedSpeedKmh(for:)` z jasno oznaczonymi w komentarzu PRZYBLIŻONYMI prędkościami przelotowymi (plane 700 km/h, boat 35, cruise 30, car/train/hiking-fallback odpowiednio 60/80/4). `WaymarkedTrailProvider.swift` (realny szlak pieszy) zaktualizowany o tę samą estymację.

**Nowy plik `TravelRouteOverviewView.swift`** — `Map` z `selection`, wszystkie przystanki jako `Annotation` (miniaturka zdjęcia w kółku + numer kroku, wzorzec z `GlobePlaceMarker`), wszystkie odcinki jako `MapPolyline` stylowane `RouteProvider.lineWidth`/`lineDashPattern`. Trasy odcinków pobierane RÓWNOLEGLE (`TaskGroup`) przy otwarciu — ale współrzędne/tryb transportu wyciągnięte do zwykłych wartości PRZED rozgałęzieniem na zadania (ten sam ostrożny wzorzec co `TravelMapView.persistTrip`, tam sekwencyjnie z tego samego powodu: `SavedStop` to referencyjny model SwiftData, nie przekazywany między równoległymi zadaniami). Tapnięcie przystanku pokazuje kartę na dole: tryb transportu, miasta, dystans (`.formatted()`) i czas (`DateComponentsFormatter`, "2h 31min" styl).

**Punkt wejścia** — `TripsListView.swift`: nowa pozycja "View Route" dołączona do JUŻ istniejącego `contextMenu`/`swipeActions` (obok Edit/Delete), NIE drugi zagnieżdżony przycisk w wierszu (cały wiersz to już jeden `Button` = flythrough, konflikt gestów).

**Lokalizacja** — 1 nowy klucz × 27 języków ("View Route").

Build → jeden drobny błąd typu po drodze (`[Double]` vs `[CGFloat]` dla `dash:`, argument label w `LegInfoCard`) — oba naprawione od razu. **BUILD SUCCEEDED**, zainstalowane. **Do przetestowania przez usera**: Twoje podróże → dowolna zapisana trasa → przytrzymaj/swipe → View Route → mapa z wszystkimi przystankami+liniami naraz, tapnięcie przystanku pokazuje dystans/czas.

## 18.08.2026, ciąg dalszy — poprawka nieporozumienia: World Globe dostaje menu (Memory/Route) i styl trasy zbliżony do Polarsteps

User po zobaczeniu poprzedniej zmiany: "przecież to już było, nic się nie zmieniło" — nie chodziło mu o kartę dystans/czas, tylko o KONKRETNY WYGLĄD ze zrzutu Polarsteps (kropkowany biały ślad + zdjęcia jako duże kółka) I o to, że wejście ma być przez **tapnięcie zdjęcia na World Globe**, nie przez ukrytą akcję na liście podróży. Doprecyzowane krok po kroku w rozmowie (jedna podróż naraz wybrana kliknięciem; menu po tapnięciu zdjęcia: "Go to Memory"/"Show Route" gdy jest film, samo "Show Route" gdy nie ma; wybór KTÓREJ podróży gdy miejsce odwiedzone więcej niż raz/przejazdem) — zaplanowane ponownie w `EnterPlanMode`, plan zaakceptowany.

**`WorldGlobeView.swift`** — `GlobePlace` dostał `trips: [SavedTrip]` (deduplikowane z `SavedStop.trip` w klastrze, ten sam wzorzec co już istniejący `linkedProjectIDs` dla filmów — klaster po odległości 20km już dziś naturalnie łapie "byłem tu 2 razy"/"przejazdem", brakowało tylko referencji do PODRÓŻY, nie tylko do Memory). `select(_:)` przestało skakać wprost do Library — otwiera teraz `actionPlace`, sterujący `.confirmationDialog` z "Go to Memory" (TYLKO gdy są filmy) + "Show Route" (zawsze) + Cancel. Dawny alert "nie powiązano z filmem" USUNIĘTY — appka zawsze ma teraz coś do zaoferowania. "Show Route" nawiguje od razu gdy `place.trips.count <= 1`, inaczej pokazuje DRUGI dialog z wyborem który tytuł podróży. Nawigacja przez nowy `.navigationDestination(item:)` (ten sam wzorzec co `TripsListView`).

**`TravelRouteOverviewView.swift`** — architektura (równoległe `RouteProvider.route()` per odcinek, ostrożne trzymanie `SavedStop` poza granicami `TaskGroup`) BEZ ZMIAN, zmieniona wyłącznie warstwa rysowania: linia trasy z kolorowej/stylowanej-per-tryb-transportu na JEDNOLITY biały kropkowany ślad (`StrokeStyle(lineWidth: 5, lineCap: .round, dash: [0.1, 13])` — bardzo krótki odcinek "on" + okrągłe zakończenie = wizualnie kropki, standardowy trik). Marker powiększony z 36pt do 60pt, numer kroku w rogu USUNIĘTY (nie ma go na zrzucie usera). Świadomie POMINIĘTA pulsująca różowa obwódka "tu jesteś teraz" ze zrzutu — to wskaźnik NA ŻYWO z prawdziwego trackera, nie ma odpowiednika w appce bez GPS w tle.

Wcześniejsze wejście przez `TripsListView.swift` (swipe/context menu "View Route") ZOSTAJE nietknięte — działa równolegle jako alternatywna droga.

**Lokalizacja** — 2 nowe klucze × 27 języków ("Go to Memory", "Which trip?" — "Show Route" już istniał, reużyty).

Build → **BUILD SUCCEEDED**, zainstalowane. **Do przetestowania przez usera**: World Globe → tapnięcie zdjęcia z filmem w miejscu odwiedzonym RAZ → dialog Memory/Route; miejsce odwiedzone W RAMACH 2+ podróży → po "Show Route" drugi dialog z wyborem; zdjęcie bez filmu → tylko "Show Route"/Cancel; wygląd trasy — kropkowany ślad + duże zdjęcia zamiast poprzedniej kolorowej linii z numerkami.

## 18.08.2026, ciąg dalszy — kropkowany ślad ODRZUCONY, powrót do wyraźnej linii trasy

User po zobaczeniu kropek na prawdziwej mapie satelitarnej: "jesteśmy na mapie, co te kropki pokazują nic, mamy mieć linię jeśli samolotem/promem/statkiem, jeśli mamy samochód albo pociąg wiesz dobrze jaką trasę wykonaliśmy więc ją narysuj poprawnie". Trafne — styl kropek z abstrakcyjnej ilustracji Polarsteps nie przenosi się dobrze na PRAWDZIWĄ, szczegółową mapę satelitarną (gubi widoczność realnej trasy między rzadkimi kropkami).

`TravelRouteOverviewView.swift` — `MapPolyline` wraca do WYRAŹNEJ linii, `Palette.blue`, stylowanej per tryb transportu przez ISTNIEJĄCE `RouteProvider.lineWidth`/`lineDashPattern` (przerywana dla samolotu jak na flight-trackerach, ciągła dla auta/promu — ta sama konwencja co flythrough), rysowanej z DOKŁADNEJ geometrii `leg.route.path` (prawdziwa droga/tor dla auta/pociągu z `MKDirections`, łuk dla lotu) — czyli w praktyce powrót do PIERWSZEJ wersji linii sprzed dzisiejszego eksperymentu z kropkami, tylko z grubszą linią (+1) i zaokrąglonymi końcami dla odrobiny miękkości. Marker zdjęcia (60pt, bez numerka) ZOSTAJE bez zmian — to nie było kwestionowane.

Build → **BUILD SUCCEEDED**, zainstalowane.

## 18.08.2026, ciąg dalszy — "halo" pod linią + ikona pojazdu na trasie + podpisane markery

User po zobaczeniu samej wyraźnej linii na prawdziwej mapie: nadal "rysowanie trzylatka", i pokazał AI-wygenerowany mockup w stylu Flighty (łuk lotu na tle krzywizny Ziemi, ikona samolotu na trasie, znaczniki z flagą+nazwą, karta lotu na dole). Zapytany o zakres (`AskUserQuestion`: tylko poprawa jakości linii VS pełniejszy redesign) — user wybrał **pełniejszy redesign** (bez tła kosmosu — jawnie odrzucone jako nierealne w MapKit).

**Halo pod linią** — DWIE nakładające się `MapPolyline` per odcinek: szersza, półprzezroczysta biała "obwódka" pod spodem + cieńsza kolorowa linia na wierzchu (standardowy kartograficzny trik na czytelność na dowolnym terenie, zamiast polegać samym kolorem/dashem o kontrast) — naprawia "poszarpany" wygląd, szczególnie tam gdzie odcinki w obie strony (tam i z powrotem) nachodzą na siebie geograficznie.

**Ikona pojazdu w połowie odcinka** — REUŻYCIE 1:1 mechanizmu z żywego przelotu: `VehicleIconSet.resolve(transport:bearing:)` (wybór asset-u right/left/top + kąt obrotu, już ustalona logika per pojazd z 30.07.2026) + `RouteProvider.bearing(from:to:)` (namiar geograficzny) — zero nowej logiki rotacji, tylko SwiftUI `.rotationEffect` zamiast UIKit-owego `CGAffineTransform`. Wędrówka pomijana (brak odpowiednika w `VehicleIconSet`).

**Podpisane markery** — `RouteStopMarker` dostał etykietę pod zdjęciem: flaga + nazwa miasta na ciemnej "pigułce" (czytelne na dowolnym tle). `LegInfoCard` (karta po tapnięciu) — emoji trybu transportu w kolorowym kółku zamiast gołego tekstu, drobny polish.

Build → **BUILD SUCCEEDED**, zainstalowane.

**Zapisane na później** (`Travel.md`, świadomie NIE zaczynane teraz — user: "dokończmy najpierw to nad czym już pracuję"): user pokazał JESZCZE bardziej rozbudowany mockup — pasek statystyk (przystanki/dystans/czas/tryby), KOLOR PER ODCINEK zamiast jednolitego niebieskiego, wysuwany dołem panel "Itinerary" z listą odcinków (`.sheet` + `.presentationDetents`, potwierdzone że to standardowy, gotowy mechanizm iOS), etykiety miast z datami, i pełna nawigacja zakładkowa Map/Itinerary/Plan/Memories/Stats — ten ostatni punkt jawnie oznaczony jako osobny, duży kawałek pracy do rozważenia oddzielnie.

## 18.08.2026, ciąg dalszy — linia zwężona, kolor per tryb transportu, naprzemienne etykiety; 3D globus ŚWIADOMIE ODRZUCONY po raz drugi

User: "te linie są za grube, to wygląda strasznie" + rozbudowany, ChatGPT-owy prompt żądający pełnego "3D globe / satellite / cinematic map" z krzywizną Ziemi, głębią i "premium" oświetleniem — **jawnie skonfrontowane z historią TEGO projektu**: 01.08.2026 był już CAŁY DZIEŃ prób dokładnie tego efektu (migracja na Mapbox, `TravelMapboxLiveView.swift`, obwiednia kamery, itd.) — user SAM wtedy porównał wynik ze starym nagraniem i uznał stare za lepsze, Mapbox usunięty CAŁKOWICIE, ustalona twarda prawda: prawdziwe zdjęcia satelitarne MapKit (`.hybrid`) NIGDY nie będą wyglądać jak dron/kosmos — to natura materiału źródłowego, nie bug do naprawienia. Zapytany wprost (`AskUserQuestion`) czy chce spróbować tego jeszcze raz mimo tej historii — user potwierdził: **zostajemy przy MapKit, bierzemy tylko realne pomysły z promptu**.

**Zwężona linia** — halo z `+4` na `+1.5`, główna linia bez dodatkowej grubości (samo `RouteProvider.lineWidth`), subtelniejsza obwódka zamiast dominującej grubej kreski.

**Kolor per tryb transportu** (nowe `RouteProvider.color(for:)`) — plane niebieski (`Palette.blue`), train fioletowy (`Palette.purple`), car pomarańczowy (`Palette.accent`), boat indygo (`Palette.indigo`), cruise turkusowy (`.teal`), hiking szary — reużywa istniejącą paletę marki gdzie się da, dopełnia systemowymi kolorami dla mniej centralnych trybów zamiast rozszerzać `Palette` bez potrzeby.

**Naprzemienne etykiety miast** (góra/dół wg parzystości indeksu przystanku) — user chciał "inteligentne" rozstawienie unikające nakładania; **uczciwie wyjaśnione**: natywny SwiftUI `Map` nie daje dostępu do współrzędnych EKRANOWYCH adnotacji, więc pełne wykrywanie kolizji wymagałoby przejścia na UIKit-owy `MKMapView` (duża zmiana architektury) — naprzemienność to pragmatyczny, tani kompromis zamiast tego, realnie zmniejszający nakładanie na typowej trasie.

Build → **BUILD SUCCEEDED**, zainstalowane.

## 18.08.2026, ciąg dalszy — pasek statystyk, lepsze kolory per tryb, START/FINISH+data, wysuwana lista Itinerary

User pokazał realne zrzuty ze swojego telefonu — kolor samochodu (pomarańczowy) zlewał się z natywnymi żółto-pomarańczowymi autostradami Apple Maps, kolor pociągu (fioletowy) "praktycznie nie widać" na terenie górskim. **Ważna korekta w trakcie planowania**: wstępnie założyłem że rozwiązaniem jest kolor PER ODCINEK (cyklicznie, żeby odróżnić kilka przejazdów tym samym trybem) — user explicite poprawił: "nie, kolor zostawiamy przy środku transportu... nie będziemy oglądać innych tras jednocześnie więc nie ma potrzeby zmieniać kolory do tras". Architektura (`RouteProvider.color(for:)`, kolor PER TRYB) zostaje, zmieniły się WYŁĄCZNIE same wartości: train `.purple`→`.pink`, car `Palette.accent`→`.red`, boat `.indigo`→`.orange`, cruise `.teal`→`.yellow`, hiking `.gray`→`.brown` (konwencja map turystycznych), plane bez zmian (`Palette.blue`, nie był problemem).

Z pokazanego wcześniej mockupu, user: "to ma być odwzorowanie 100%" dla wymienionych elementów (bez krzywizny Ziemi/kosmosu — to zostało jawnie odrzucone wcześniej dziś, `AskUserQuestion`, z odniesieniem do udokumentowanej porażki Mapboxa 01.08.2026):

**Pasek statystyk** pod nagłówkiem — liczba przystanków, suma dystansu (reużyty JUŻ PERSYSTOWANY `trip.totalDistanceKm`, dostępny natychmiast bez czekania na sieć), suma czasu podróży (nowe, dopiero po `loadLegs()`), lista unikalnych trybów transportu.

**START/FINISH + data** w etykiecie markera (`RouteStopMarker`) — mały napis nad nazwą miasta dla pierwszego/ostatniego przystanku, pojedyncza data pod nazwą. **Uczciwe ograniczenie zapisane w kodzie**: `SavedStop` ma tylko `arrivalDate`, nie parę check-in/check-out jak `PlannedStop` — appka nie zna ZAKRESU dat dla odbytych podróży, tylko jeden dzień (w odróżnieniu od mockupu, który pokazywał zakresy).

**Wysuwana dołem lista "Itinerary"** — `.sheet` pokazywany OD RAZU (nie za przyciskiem), `.presentationDetents([.height(160), .large])` + `.presentationBackgroundInteraction(.enabled(upThrough: .large))` (mapa dalej przesuwalna pod częściowo otwartym panelem, jak Apple Maps/Find My) + `.interactiveDismissDisabled()` (nie do całkowitego zamknięcia, tylko zwinięcia). Lista odcinków — numerek w kolorze TRYBU tego odcinka (spójny z linią na mapie), ikona+etykieta trybu, miasta, data+czas. Tapnięcie wiersza przybliża kamerę do DWÓCH punktów TEGO odcinka (nowa generyczna `region(for:minimumDelta:)`, zastąpiła dawną `initialRegion(for:)` — ta sama logika, reużywalna też dla całej trasy na starcie).

**Lokalizacja** — 6 nowych kluczy × 27 języków (Destinations, Total distance, Total travel time, Transports, START, FINISH).

Build → **BUILD SUCCEEDED**, zainstalowane.

## 18.08.2026, ciąg dalszy — kolory "tragiczne", panel Itinerary nieprzewijalny/za duży

User na realnym zrzucie: czerwony (samochód) "tragiczny", panel Itinerary "nie da się przewijać, tylko wyskakuje cała na ekran i odstępy są na niej za duże".

**Kolory** — surowe systemowe `.red`/`.pink`/`.orange`/`.yellow`/`.brown` (druga runda dziś) zastąpione RĘCZNIE dobranymi, stonowanymi tonami w `Palette.swift` (ten sam wzorzec `rgb()` co istniejące `blue`/`indigo`/`purple`/`accent`, nie surowe kolory systemowe): `coral` (0xFF6B6B, samochód), `rose` (0xEC6FA6, pociąg), `gold` (0xE8C547, statek wycieczkowy), `tan` (0xA67C52, wędrówka) — prom reużywa już istniejący `Palette.accent`. Ta sama logika kontrastu względem tła co poprzednia runda (droga/teren/ocean), tylko w miękkiej, mniej agresywnej wersji.

**Panel Itinerary** — dwa realne problemy: (1) brak `selection:` bindingu w `.presentationDetents` sprawiał że SwiftUI samo dobierało początkowy rozmiar, nieprzewidywalnie za duży — naprawione jawnym `@State private var itineraryDetent: PresentationDetent = .height(140)` jako gwarantowany, mały start. (2) `Section`+wbudowany nagłówek `List` dokładał sporo domyślnego odstępu, a osobna kolumna z emoji+etykietą trybu po prawej stronie wiersza rozdymała wysokość bez potrzeby (ta sama informacja już jest w kolorze numerka) — zastąpione własnym tytułem NAD listą (bez nagłówka Sekcji) i jedną zwartą linią per wiersz (emoji WEWNĄTRZ tekstu miast), `.listRowInsets` dociśnięte — więcej wierszy mieści się w tej samej wysokości, realnie przewijalne.

Build → **BUILD SUCCEEDED**, zainstalowane.

## 18.08.2026, ciąg dalszy — róż pociągu też odrzucony, trzecia próba: turkus

User: "te odcienie różu też mi się nie podobają" — `Palette.rose` (0xEC6FA6) to już DRUGA odrzucona propozycja dla pociągu z tej samej rodziny barw (najpierw `Palette.purple`, potem różowy). Zamiast kolejnego odcienia różu/fioletu, zupełnie inna rodzina: nowy `Palette.teal` (0x2EC4B6, stonowany turkus) — wyraźnie odróżnialny od reszty palety tras (niebieski/koral/złoto/brąz), bez ponownego próbowania tej samej, dwukrotnie odrzuconej rodziny kolorów.

Build → **BUILD SUCCEEDED**, zainstalowane (jedna przejściowa blokada urządzenia przy pierwszej próbie builda, druga zadziałała od razu).

## 18.08.2026, ciąg dalszy — Places to visit: podpowiedzi + grupowanie po dniach

User: "czy możemy zrobić żeby miejsca do zobaczenia... wyszukiwało w taki sam sposób jak miasta czy lotniska, czyli żeby się miało podpowiedzi? do tego czy możemy dodać dni — Day 1, to to i to, później naciskamy wyświetla się Day 2". Dwie osobne rzeczy w Trip Planning (`TripPlanningView.swift`), obie w `PlannedStopRow`.

**Podpowiedzi miejsc** — nowy plik `PlaceSearchCompleter.swift`, osobna klasa od `CitySearchCompleter` (nie reużycie/rozszerzenie) — inny filtr wyników (`resultTypes = [.pointOfInterest]`, WSZYSTKIE punkty zainteresowania, nie tylko lotniska jak przy mieście) i inne przeznaczenie: `PlaceToVisit` nie przechowuje współrzędnych, więc wystarczy sam poprawny TEKST nazwy z podpowiedzi, bez kroku `resolve()`. `setRegion(center:)` wyśrodkowuje wyszukiwanie na mieście PRZYSTANKU (promień ~50km) — "Louvre" wpisane przy przystanku w Paryżu faworyzuje paryski Luwr, nie przypadkowy wynik z drugiego końca świata. Tapnięcie podpowiedzi OD RAZU dodaje miejsce (mniej dotknięć niż wpisz→zatwierdź).

**Grupowanie po dniach** — `placesToVisitSection` przebudowana z płaskiej listy (Menu wyboru dnia PRZY KAŻDYM miejscu osobno, 12.08.2026) na jawne sekcje "Day N" (nowy `DayPlacesSection`), każda z WŁASNYM polem dodawania — dzień określa się przez to POD KTÓRĄ sekcją dodano miejsce, nie osobnym wyborem po fakcie. Nowy `visibleDayCount` (lokalny stan, startuje z długości pobytu/istniejących przypisań jak dawne `maxDayCount`) rośnie o 1 po tapnięciu "+ Add Day N+1". **Uczciwe ograniczenie zapisane w kodzie**: appka nie ma osobnej encji "Day" do zapisania — pusty dzień dodany bez żadnego miejsca zniknie przy ponownym wejściu na ekran (liczony na nowo z istniejących danych). Miejsca bez przypisanego dnia (stare dane sprzed tej zmiany) — sekcja "Any day" na końcu, bez własnego pola dodawania (fallback do wyświetlania, nie równoległa droga).

Zmiana dnia PO dodaniu miejsca — dawne, zawsze widoczne Menu z wyborem dnia ZASTĄPIONE menu kontekstowym (długie przytrzymanie) na wierszu, "Move to Day N"/"Move to Any day" — rzadziej używana droga, nie musi być stale widoczna skoro dzień jest teraz oczywisty z samego miejsca w layoucie.

**Lokalizacja** — 3 nowe klucze × 27 języków (Add Day, Move to, Move to Any day).

Build → **BUILD SUCCEEDED**, zainstalowane.

## 18.08.2026, ciąg dalszy — Places to visit startuje od Day 1, nie od całej długości pobytu

User: "nie musimy mieć od razu całego tygodnia wyświetlonego, wystarczy jeden dzień z opcją dodania kolejnych" — `maxDayCount` (wartość startowa `visibleDayCount`) liczyła dawniej `stop.nights + 1`, więc 6-nocny pobyt od razu pokazywał 7 pustych sekcji dni. Uproszczone — start ZAWSZE od Day 1, user sam dokłada kolejne przyciskiem "Add Day" w swoim tempie. Jedyny zachowany wyjątek: jeśli podróż ma już przypisane miejsca poza dniem 1 (powrót do wcześniej wypełnionych danych), zakres startowy sięga tam, żeby nic nie ukryć.

Build → **BUILD SUCCEEDED**, zainstalowane.

## 18.08.2026, ciąg dalszy — pociąg pokazywał czas i ikonę samochodu

User na przykładzie Londyn→Paryż: "6h" czasu przejazdu pociągiem wyglądało podejrzanie, do tego ikona w pasku statystyk pokazywała samochodzik mimo etykiety "Train".

**Ikona paska statystyk** — była na SZTYWNO `car.fill` niezależnie od faktycznego trybu (`statsBar` w `TravelRouteOverviewView.swift`). Naprawione: nowa `transportsSummaryIcon` — jeden tryb w całej trasie dostaje WŁASNĄ ikonę (`tram.fill` dla pociągu itd.), kilka różnych trybów → neutralna `arrow.triangle.swap` (tekst obok i tak wymienia wszystkie osobno).

**Czas przejazdu pociągiem** — realny bug w `RouteProvider.route()`. `MKDirections` nie ma tras TRANSIT dla połączeń międzynarodowych przez wodę (Londyn→Paryż przez kanał La Manche) — appka spadała na fallback trasy SAMOCHODEM (przez Eurotunnel), i dziedziczyła jej REALNY czas (~6h, uwzględniający przeprawę) jako czas "pociągu", mimo że Eurostar jedzie ~2h15. Ścieżka geometrii samochodowej zostaje (pociąg jeździ mniej więcej po lądzie jak drogi, sensowne przybliżenie wizualne), ale CZAS liczony teraz z `estimatedSpeedKmh(for: .train)` na DYSTANSIE tej trasy, nie dziedziczony z auta. Stała prędkości pociągu podniesiona 80→100 km/h (bliżej realnej średniej połączeń ekspresowych w Europie z postojami) — **uczciwie zaznaczone w komentarzu**: to nadal ZGRUBNE przybliżenie, appka nie zna prawdziwych rozkładów i nie odróżni regionalnego pociągu od Eurostar/TGV.

Build → **BUILD SUCCEEDED**, zainstalowane.

## 18.08.2026, ciąg dalszy — linia prosta zamiast trasy (Bellagio→Zurych pociągiem)

User na kolejnym zrzucie: odcinek pociągiem z Bellagio do Zurychu narysowany jako gołą LINIĘ PROSTĄ przez Alpy, nie trasą. Diagnoza: `directionsRoute()` (wywoływana zarówno dla transit jak i fallbacku samochodowego przy pociągu) używała `try?` — gdy `MKDirections` zawiodło (transient błąd sieci? Bellagio geokodowane na jezioro bez dostępu do drogi? Apple po prostu nie ma trasy dla tego konkretnego zapytania?), błąd znikał BEZ ŚLADU, appka cicho spadała na geodezyjną linię prostą (poprawna ostateczność, ale bez logu nie dało się odróżnić przejściowej awarii od trwałego braku danych).

Naprawa (ten sam wzorzec co `PMemoriesOutroCardRenderer`, 15.08.2026) — JEDNO ponowienie zapytania `MKDirections` przy porażce + jawny `print` z konkretnym powodem (błąd/brak tras) przy KAŻDEJ próbie, żeby przyszła diagnoza (jeśli się powtórzy) miała realny dowód zamiast zgadywania. Nie eliminuje źródła jeśli to trwały brak danych Apple dla tego regionu, ale realnie łapie przejściowe awarie i zostawia ślad do dalszego sprawdzenia.

Build → **BUILD SUCCEEDED**, zainstalowane (jedna przejściowa blokada tunelu przy pierwszej próbie instalacji, druga zadziałała od razu).

## 18.08.2026, ciąg dalszy — build 13 (1.0.2) wysłany

User: "wrzućmy update bez zmiany nr, przejdzie szybko, nic dużego nie robiliśmy" — `CFBundleVersion` 12→13 w `project.yml`, `CFBundleShortVersionString` zostaje "1.0.2" (ten sam wzorzec co poprzednie buildy). `xcodegen generate` → archive (Release) → export (`build/export13/`, ten sam `ExportOptions.plist`) → `altool --upload-app`, wszystko za pierwszym razem bez przeszkód. **UPLOAD SUCCEEDED**, 14MB w ~2s, Delivery UUID `5e7b2dc7-5e16-4115-b219-27b901589329`.

**Zawartość build 13** (wszystko od build 12): lepsze kolory tras per tryb transportu (kilka rund poprawek — koral/turkus/złoto/brąz zamiast surowych systemowych), pasek statystyk/START-FINISH+data/wysuwana lista Itinerary w Travel Route Overview, naprawa ikony "Transports" (sztywno samochód → dynamiczna), naprawa czasu przejazdu pociągiem (dziedziczył czas auta zamiast szacunku pociągu), retry+logowanie przy zawodzącym `MKDirections` (linia prosta zamiast trasy), Places to visit z podpowiedziami POI i grupowaniem po dniach (Day 1/Add Day).

## 18.08.2026, ciąg dalszy — serduszko "Want to visit" zastąpione zakładką

User na zrzucie z Places to visit: "po co te serca? to nie aplikacja randkowa" — `PlaceVisitStatus.wantToVisit.emoji` (12.08.2026) było ❤️, czytało się jak lajk z appki randkowej, nie status na liście podróżniczej. Zmienione na 🔖 (zakładka — "zapisane do sprawdzenia"), pasuje lepiej obok ⭐ (Must see) i ✓ (Visited), bez romantycznego skojarzenia.

Build → **BUILD SUCCEEDED**, zainstalowane.

## 18.08.2026, ciąg dalszy — build 14 (1.0.2) wysłany

User: "musimy chyba zrobić build 14 bo ten z sercami poszedł" — build 13 wysłany PRZED naprawą serduszka (❤️→🔖), więc od razu kolejny build z poprawką. `CFBundleVersion` 13→14, `CFBundleShortVersionString` zostaje "1.0.2". Ten sam sprawdzony proces (`xcodegen generate` → archive → export → `altool`) — jedna różnica: `altool` przekroczył 120s timeout w pierwszej próbie, zadanie automatycznie przeniesione do tła, dokończyło się poprawnie. **UPLOAD SUCCEEDED**, Delivery UUID `02618310-6b47-4bd0-9b69-094c497f6ea9`.

**Zawartość build 14** (jedyna zmiana od build 13): "Want to visit" ❤️→🔖.

Czeka na przetworzenie przez Apple / recenzję TestFlight.
