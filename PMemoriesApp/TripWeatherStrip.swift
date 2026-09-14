import SwiftUI
import CoreLocation

/// Pasek dni prowadzący do dnia wyprawy (12.09.2026, user: "jak miejsce
/// docelowe bedzie np rysy zeby pokazywalo nam tem na rysach max do dnia
/// wyprawy") — pokazuje prognozę KAŻDEGO dnia od dziś do dnia przyjazdu na
/// dany przystanek, z wyróżnionym dniem samej wyprawy. Ten sam duch co
/// pojedyncza prognoza na Home (`TravelTimeMachineProvider.
/// forecastTemperature`), tylko cały pasek prowadzący do celu, nie tylko
/// jeden dzień. Działa dla KAŻDEGO przystanku z rozwiązaną lokalizacją
/// (szczyt znaleziony przez `PeakSearchView` albo zwykłe miasto) — appka
/// nie odróżnia szczytu od miasta, obu dotyczy ten sam mechanizm.
///
/// Puste (nic nie pokazuje) gdy dzień wyprawy jest poza zasięgiem Open-Meteo
/// Forecast (~16 dni w przód) albo w przeszłości — appka nie zgaduje.
struct TripWeatherStrip: View {
    let coordinate: CLLocationCoordinate2D
    let tripDate: Date

    @State private var days: [TravelTimeMachineProvider.DailyForecast] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 50)
            } else if !days.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(days) { day in
                            dayChip(day)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .task(id: taskID) {
            isLoading = true
            days = await TravelTimeMachineProvider.dailyForecasts(at: coordinate, through: tripDate)
            isLoading = false
        }
    }

    private var taskID: String {
        "\(coordinate.latitude),\(coordinate.longitude),\(tripDate.timeIntervalSince1970)"
    }

    private func dayChip(_ day: TravelTimeMachineProvider.DailyForecast) -> some View {
        let isTripDay = Calendar.current.isDate(day.date, inSameDayAs: tripDate)
        return VStack(spacing: 2) {
            Text(day.date, format: .dateTime.weekday(.abbreviated))
                .font(.system(size: 11, weight: isTripDay ? .bold : .regular))
            Text("\(Int(day.maxC.rounded()))°")
                .font(.system(size: 13, weight: .semibold))
            Text("\(Int(day.minC.rounded()))°")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(isTripDay ? Palette.blue : .primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isTripDay ? Palette.blue.opacity(0.15) : Color(.tertiarySystemFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isTripDay ? Palette.blue : .clear, lineWidth: 1.5)
        )
    }
}
