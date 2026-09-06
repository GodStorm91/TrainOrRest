import MapKit
import SwiftData
import SwiftUI

struct RunScheduleSetupSheet: View {
    enum Step: Int, CaseIterable {
        case explain
        case location
        case weather
    }

    @EnvironmentObject private var runSchedule: RunScheduleController
    @EnvironmentObject private var googleCalendar: GoogleCalendarSyncService
    @Environment(\.dismiss) private var dismiss
    @Query private var connections: [GoogleCalendarConnection]
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @State private var step: Step = .explain
    @State private var cityQuery = ""
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var isWorking = false

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }
    private var connection: GoogleCalendarConnection { connections.first ?? googleCalendar.connection() }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .explain: explainStep
                case .location: locationStep
                case .weather: weatherStep
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.bg)
            .navigationTitle(language.plan.runSchedule)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.cancelLabel) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    if step != .explain {
                        Button(language.backLabel) {
                            step = Step(rawValue: step.rawValue - 1) ?? .explain
                        }
                        .buttonStyle(.bordered)
                    }
                    Button(primaryTitle) {
                        advance()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvance || isWorking)
                }
                .padding()
                .background(Theme.card)
            }
        }
        .onAppear {
            if let location = runSchedule.location {
                mapPosition = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                ))
            }
        }
    }

    private var explainStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.plan.runScheduleExplainTitle)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(language.plan.runScheduleExplainBody)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var locationStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.plan.setRunLocation)
                .font(.headline)
            Button {
                Task {
                    isWorking = true
                    defer { isWorking = false }
                    await runSchedule.captureCurrentLocation()
                    if let location = runSchedule.location {
                        mapPosition = .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                        ))
                    }
                }
            } label: {
                Label(language.plan.currentLocation, systemImage: "location.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)

            HStack {
                TextField(language.plan.searchCity, text: $cityQuery)
                    .textFieldStyle(.roundedBorder)
                Button(language.plan.search) {
                    Task {
                        isWorking = true
                        defer { isWorking = false }
                        await runSchedule.searchPlace(cityQuery)
                    }
                }
                .disabled(cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Map(position: $mapPosition) {
                if let location = runSchedule.location {
                    Marker(location.name, coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude))
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if let location = runSchedule.location {
                Text(location.name)
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
            }
            if let message = runSchedule.weatherUserMessage {
                Text(language.plan.weatherCopy(message))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var weatherStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.plan.rainTolerance)
                .font(.headline)
            Picker(language.plan.rainTolerance, selection: $runSchedule.rainTolerance) {
                Text(language.plan.rainStanceLabel(.low)).tag(RainTolerance.low)
                Text(language.plan.rainStanceLabel(.medium)).tag(RainTolerance.medium)
                Text(language.plan.rainStanceLabel(.high)).tag(RainTolerance.high)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(language.plan.rainTolerance)

            Text(language.plan.rainToleranceCaption(runSchedule.rainTolerance))
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)

            weatherPreview

            NavigationLink {
                GoogleCalendarSettingsView()
            } label: {
                Label(language.plan.findTimeWithCalendar, systemImage: "calendar")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.bordered)
            if connection.smartSchedulingEnabled {
                Label(language.plan.smartScheduling, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.good)
            }
        }
        .task {
            await runSchedule.refreshWeather(force: true)
        }
    }

    @ViewBuilder
    private var weatherPreview: some View {
        if runSchedule.isRefreshingWeather {
            HStack(spacing: 8) {
                ProgressView()
                Text(language.plan.updatingForecast)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityLabel(language.plan.updatingForecast)
        } else if let failure = runSchedule.weatherUserMessage {
            Button {
                Task { await runSchedule.refreshWeather(force: true) }
            } label: {
                Label(language.plan.weatherCopy(failure), systemImage: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .foregroundStyle(Theme.warn)
        } else if let sample = runSchedule.hourly.first {
            let preview = HourlyWeatherSample(
                hourStart: sample.hourStart,
                temperatureC: sample.temperatureC,
                precipitationChance: sample.precipitationChance,
                windKmh: sample.windKmh
            )
            Label(
                language.plan.slotWeatherSummary(
                    SlotWeather(
                        samples: [preview],
                        temperatureRangeC: preview.temperatureC...preview.temperatureC,
                        precipitationMax: preview.precipitationChance,
                        windMaxKmh: preview.windKmh,
                        glyph: RunScheduleWeather.dayGlyph(
                            hourly: runSchedule.hourly,
                            on: Date(),
                            rainTolerance: runSchedule.rainTolerance
                        )
                    )
                ),
                systemImage: "cloud.sun"
            )
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(language.plan.weatherOnNoForecast)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.dim)
        }
    }

    private var primaryTitle: String {
        step == .weather ? language.plan.done : language.continueLabel
    }

    private var canAdvance: Bool {
        switch step {
        case .explain: true
        case .location: runSchedule.location != nil
        case .weather: true
        }
    }

    private func advance() {
        if step == .weather {
            runSchedule.markSetupCompleted()
            dismiss()
            return
        }
        step = Step(rawValue: step.rawValue + 1) ?? .weather
    }
}
