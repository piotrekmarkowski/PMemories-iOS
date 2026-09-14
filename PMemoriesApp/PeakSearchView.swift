import SwiftUI
import CoreLocation

/// Wyszukiwanie szczytu górskiego PO NAZWIE, bez wymogu żywego GPS —
/// dopełnienie `TravelMapView`'s "Add peak from my location" (09.09.2026,
/// user: "nie mozna wybrac na liscie szczytow jesli sie chodzi po
/// gorach... dzien pozniej sie chce stworzyc mape albo po wyprawie nie
/// mozna wybrac gdzie sie bylo" — ten przycisk działa TYLKO stojąc
/// fizycznie na szczycie, więc dobudowanie trasy później albo z domu było
/// niemożliwe). Ten sam Overpass/OSM co wykrywanie po GPS
/// (`PeakDetector.searchPeaks`), tylko szukane po nazwie.
///
/// Szukanie NA ŻĄDANIE (submit pola wyszukiwania), nie na każde naciśnięcie
/// klawisza — Overpass to darmowe, współdzielone API, nie tak tanie/szybkie
/// jak lokalna baza Apple Maps za `CitySearchCompleter`.
struct PeakSearchView: View {
    let onSelect: (PeakDetector.DetectedPeak) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [PeakDetector.DetectedPeak] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var hasSearched = false

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if let searchError {
                    Text(searchError)
                        .foregroundStyle(.secondary)
                } else if hasSearched && results.isEmpty {
                    ContentUnavailableView(
                        L("No peaks found"), systemImage: "mountain.2",
                        description: Text(L("Try a different spelling, or a nearby well-known peak."))
                    )
                } else {
                    ForEach(Array(results.enumerated()), id: \.offset) { _, peak in
                        Button {
                            onSelect(peak)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(peak.name)
                                    .foregroundStyle(.primary)
                                if let country = peak.country {
                                    Text(country)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: L("Peak name, e.g. Rysy"))
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle(L("Search for a peak"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
        }
    }

    private func search() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        searchError = nil
        defer {
            isSearching = false
            hasSearched = true
        }
        do {
            results = try await PeakDetector.searchPeaks(named: query)
        } catch {
            searchError = error.localizedDescription
            results = []
        }
    }
}
