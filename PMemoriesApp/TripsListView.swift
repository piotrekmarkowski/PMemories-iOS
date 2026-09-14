import SwiftUI
import SwiftData

/// Lista odbytych podróży — przeniesiona z góry ekranu Travel Map do Badges
/// (03.08.2026, user: przy ~50 zapisanych podróżach nikt nie będzie chciał
/// przewijać przez to wszystko, żeby dotrzeć do formularza budowania nowej
/// trasy). Dokładnie ta sama zawartość wiersza (play/edit/delete) co
/// wcześniej w `TravelMapView`, tylko na osobnym ekranie dostępnym z Badges.
struct TripsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedTrip.createdAt, order: .reverse) private var savedTrips: [SavedTrip]
    /// Wywoływane po tapnięciu "Edit" — rodzic (aż do `TravelMapView`) ładuje
    /// przystanki tej podróży do formularza i zamyka wszystkie ekrany
    /// pomiędzy `TravelMapView` a tym miejscem (patrz `AchievementsView`).
    let onEditTrip: (SavedTrip) -> Void

    @State private var resolvedStops: [TripStop] = []
    @State private var isShowingAnimation = false
    /// Statyczny przegląd trasy (18.08.2026) — druga, osobna od flythroughu
    /// akcja na wierszu podróży. Dołączona do JUŻ istniejącego `contextMenu`/
    /// `swipeActions` (obok Edit/Delete) zamiast drugiego zagnieżdżonego
    /// przycisku w tym samym wierszu — cały wiersz jest już jednym `Button`
    /// (tap = flythrough), drugi przycisk w środku ryzykowałby konflikt
    /// gestów (ten sam problem, inne rozwiązanie już sprawdzone w
    /// `WorldGlobeView` przez `selection`, nie warto go tu odtwarzać w
    /// nowej formie).
    @State private var routeOverviewTrip: SavedTrip?

    /// Historia od najbliższej do najdalszej (26.08.2026, user: "trip
    /// powinny się wyświetlać od najbliższej do późniejszej... będziemy
    /// mieć historię") — wg `effectiveDate` (data SAMEJ podróży), nie
    /// `createdAt` z `@Query` powyżej (kiedy podróż trafiła do appki).
    /// Sortowanie w pamięci, nie w `@Query`, bo `effectiveDate` jest
    /// liczone (najwcześniejszy `arrivalDate` przystanku), nie zwykłym
    /// polem SwiftData.
    private var sortedTrips: [SavedTrip] {
        savedTrips.sorted { $0.effectiveDate > $1.effectiveDate }
    }

    var body: some View {
        List {
            if savedTrips.isEmpty {
                Text("No trips saved yet — build a route on the Travel Map to see it here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedTrips) { trip in
                    Button {
                        resolvedStops = trip.asTripStops
                        isShowingAnimation = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(trip.title)
                                        .foregroundStyle(.primary)
                                    // 12.09.2026: "ulubiona podróż" — punkt 5
                                    // hierarchii rarity score na plakacie
                                    // "My Travel Journey" (`TravelRarityScore`),
                                    // appka wcześniej nie miała gdzie tego
                                    // oznaczyć. Samo serduszko w wierszu, bez
                                    // osobnego ekranu — akcja żyje w
                                    // `contextMenu`/`swipeActions` niżej.
                                    if trip.isFavorite {
                                        Image(systemName: "heart.fill")
                                            .font(.caption)
                                            .foregroundStyle(.pink)
                                    }
                                }
                                Text(trip.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.circle")
                                .foregroundStyle(Palette.blue)
                        }
                    }
                    .contextMenu {
                        Button {
                            toggleFavorite(trip)
                        } label: {
                            Label(trip.isFavorite ? L("Remove from Favorites") : L("Add to Favorites"), systemImage: trip.isFavorite ? "heart.slash" : "heart")
                        }
                        Button {
                            routeOverviewTrip = trip
                        } label: {
                            Label(L("View Route"), systemImage: "map")
                        }
                        Button {
                            onEditTrip(trip)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        // "Podziel się jako szablon" (26.08.2026) — patrz
                        // `SavedTrip.templateTransferDTO`: odbiorca dostaje
                        // tylko miasta/kolejność/transport, BEZ dat tej
                        // konkretnej wyprawy, jako nową pozycję we własnym
                        // Trip Planning.
                        ShareLink(item: trip.templateTransferDTO, preview: SharePreview(trip.title)) {
                            Label(L("Share as Template"), systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            deleteTrip(trip)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteTrip(trip)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            onEditTrip(trip)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(Palette.purple)
                        Button {
                            routeOverviewTrip = trip
                        } label: {
                            Label(L("View Route"), systemImage: "map")
                        }
                        .tint(Palette.blue)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            toggleFavorite(trip)
                        } label: {
                            Label(trip.isFavorite ? L("Remove from Favorites") : L("Add to Favorites"), systemImage: trip.isFavorite ? "heart.slash" : "heart")
                        }
                        .tint(.pink)
                        ShareLink(item: trip.templateTransferDTO, preview: SharePreview(trip.title)) {
                            Label(L("Share as Template"), systemImage: "square.and.arrow.up")
                        }
                        .tint(Palette.purple)
                    }
                }
            }
        }
        .navigationTitle("Your Trips")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isShowingAnimation) {
            TravelMapAnimationView(stops: resolvedStops, speedMultiplier: 1.0, mapTheme: .satellite)
        }
        .navigationDestination(item: $routeOverviewTrip) { trip in
            TravelRouteOverviewView(trip: trip)
        }
    }

    private func deleteTrip(_ trip: SavedTrip) {
        modelContext.delete(trip)
        try? modelContext.save()
    }

    private func toggleFavorite(_ trip: SavedTrip) {
        trip.isFavorite.toggle()
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack {
        TripsListView(onEditTrip: { _ in })
    }
}
