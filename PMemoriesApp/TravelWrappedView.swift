import SwiftUI
import SwiftData

/// "Travel Wrapped" — roczne podsumowanie w stylu Spotify Wrapped (`Travel.
/// md`: "Year in Review"). Domyślnie pokazuje najnowszy rok z danymi, picker
/// pozwala przełączyć na wcześniejsze lata gdy jest więcej niż jeden.
struct TravelWrappedView: View {
    @Query(sort: \SavedTrip.createdAt) private var savedTrips: [SavedTrip]
    @State private var selectedYear: Int?

    private var years: [Int] {
        TravelAchievementsCalculator.wrappedYears(from: savedTrips)
    }

    private var wrapped: TravelWrapped? {
        guard let year = selectedYear ?? years.first else { return nil }
        return TravelAchievementsCalculator.wrapped(for: year, from: savedTrips)
    }

    var body: some View {
        Group {
            if years.isEmpty {
                VStack(spacing: 12) {
                    Text("📅")
                        .font(.system(size: 40))
                        .opacity(0.5)
                    Text("No trips to summarize yet")
                        .font(.title3.bold())
                    Text("Save your first trip to see a yearly recap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let wrapped {
                ScrollView {
                    VStack(spacing: 16) {
                        if years.count > 1 {
                            Picker("Year", selection: Binding(
                                get: { selectedYear ?? years.first ?? wrapped.year },
                                set: { selectedYear = $0 }
                            )) {
                                ForEach(years, id: \.self) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        }

                        WrappedHeroCard(wrapped: wrapped)
                            .padding(.horizontal)

                        WrappedStatCard(emoji: "🗺️", value: "\(wrapped.tripCount)", label: L(wrapped.tripCount == 1 ? "trip" : "trips"))
                            .padding(.horizontal)
                        WrappedStatCard(emoji: "🌐", value: "\(wrapped.countryCount)", label: L(wrapped.countryCount == 1 ? "country" : "countries"))
                            .padding(.horizontal)
                        WrappedStatCard(emoji: "🏙️", value: "\(wrapped.cityCount)", label: L(wrapped.cityCount == 1 ? "city" : "cities"))
                            .padding(.horizontal)
                        WrappedStatCard(emoji: "📏", value: "\(Int(wrapped.totalKm.rounded()).formatted())", label: L("km travelled"))
                            .padding(.horizontal)
                        if let topTrip = wrapped.topTrip, topTrip.km > 0 {
                            WrappedStatCard(emoji: "🏆", value: topTrip.title, label: "\(Int(topTrip.km.rounded()).formatted()) \(L("km — longest trip of the year"))", isTextValue: true)
                                .padding(.horizontal)
                        }

                        Text("Made with PMemories")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Travel Wrapped")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WrappedHeroCard: View {
    let wrapped: TravelWrapped

    var body: some View {
        VStack(spacing: 6) {
            Text(String(wrapped.year))
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(Palette.heroGradient)
            Text("Your year in travel")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.heroGradient.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Palette.heroGradient, lineWidth: 1.5)
        )
    }
}

private struct WrappedStatCard: View {
    let emoji: String
    let value: String
    let label: String
    var isTextValue: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Text(emoji)
                .font(.system(size: 28))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(isTextValue ? .headline : .title2.bold())
                    .lineLimit(isTextValue ? 2 : 1)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
