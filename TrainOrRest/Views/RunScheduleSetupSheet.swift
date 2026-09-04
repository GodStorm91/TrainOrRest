import MapKit
import SwiftData
import SwiftUI

struct RunScheduleSetupSheet: View {
    enum Step: Int, CaseIterable {
        case explain
        case google
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
                case .google: googleStep
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
            Text(language.plan.runScheduleExplainBody)
                .foregroundStyle(.secondary)
        }
    }

    private var googleStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.plan.connectGoogleCalendar)
                .font(.headline)
            Text(connection.calendarName.isEmpty ? language.integrations.connectCalendarSubtitle : connection.calendarName)
                .foregroundStyle(.secondary)
            NavigationLink {
                GoogleCalendarSettingsView()
            } label: {
                Label(
                    connection.connectionStatus == .disconnected ? language.integrations.connectGoogleCalendar : language.integrations.googleCalendarTitle,
                    systemImage: "calendar"
                )
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            if connection.smartSchedulingEnabled {
                Label(language.plan.smartScheduling, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.good)
            }
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
                Button(language.plan.searchCity) {
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
                    .foregroundStyle(.secondary)
            }
            if let message = runSchedule.weatherMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.warn)
            }
        }
    }

    private var weatherStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(language.plan.rainTolerance, selection: $runSchedule.rainTolerance) {
                Text(language.plan.rainLow).tag(RainTolerance.low)
                Text(language.plan.rainMedium).tag(RainTolerance.medium)
                Text(language.plan.rainHigh).tag(RainTolerance.high)
            }
            .pickerStyle(.segmented)

            if runSchedule.isRefreshingWeather {
                ProgressView()
            } else if let sample = runSchedule.hourly.first {
                Label(
                    String(format: "%.0f°C · %d%% rain", sample.temperatureC, Int((sample.precipitationChance * 100).rounded())),
                    systemImage: "cloud.sun"
                )
            } else {
                Text(language.plan.weatherNoData)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await runSchedule.refreshWeather(force: true)
        }
    }

    private var primaryTitle: String {
        step == .weather ? language.plan.done : language.continueLabel
    }

    private var canAdvance: Bool {
        switch step {
        case .explain: true
        case .google: connection.smartSchedulingEnabled || connection.connectionStatus != .disconnected
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
