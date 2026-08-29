import SwiftData
import SwiftUI

struct FirstRunFlowView: View {
    enum Step: Int {
        case welcome, health, race, hub, intervals, calendar, coach
    }

    let health: HealthKitService
    let onFinished: () -> Void

    @State private var step: Step = .welcome
    @State private var isRequestingHealth = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                progress
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                screen
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Theme.accent)
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(barColor(index))
                    .frame(height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(barIndex + 1) of 4")
    }

    private var barIndex: Int {
        switch step {
        case .welcome: 0
        case .health: 1
        case .race: 2
        case .hub, .intervals, .calendar, .coach: 3
        }
    }

    private func barColor(_ index: Int) -> Color {
        if index < barIndex { return Theme.accent.opacity(0.45) }
        if index == barIndex { return Theme.accent }
        return Theme.card2
    }

    @ViewBuilder
    private var screen: some View {
        switch step {
        case .welcome:
            welcome
        case .health:
            healthStep
        case .race:
            FirstRunRaceStep(
                onCreated: { step = .hub },
                onLater: finish
            )
        case .hub:
            hub
        case .intervals:
            setupHost(title: "intervals.icu", back: .hub) {
                IntervalsConnectionSettingsView()
            }
        case .calendar:
            setupHost(title: "Google Calendar", back: .hub) {
                GoogleCalendarSettingsView()
            }
        case .coach:
            setupHost(title: "Coach", back: .hub) {
                CoachProviderSettingsView()
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TrainOrRest")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.faint)
                .padding(.bottom, 8)
            Text("What should I do in the next 12 hours?")
                .font(.torHeading(28, .bold))
                .foregroundStyle(Theme.text)
                .padding(.bottom, 12)
            Text("Enter the race you signed up for. Get a plan, then a daily call to train, go easy, or rest. Health data stays on this iPhone.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.dim)
                .padding(.bottom, 12)
            Text("About 3 minutes to a plan. Watch, calendar, and Coach can wait.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.faint)
            Spacer()
            primaryButton("Connect Apple Health") { step = .health }
            textButton("Explore first", action: finish)
        }
    }

    private var healthStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            backButton { step = .welcome }
            Text("Connect Apple Health")
                .font(.torHeading(28, .bold))
                .foregroundStyle(Theme.text)
                .padding(.bottom, 12)
            Text("Garmin runs, sleep, HRV, and resting heart rate arrive through Apple Health. TrainOrRest only reads. It does not write back.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.dim)
                .padding(.bottom, 16)
            VStack(alignment: .leading, spacing: 10) {
                permitRow("Workouts, heart rate, HRV, sleep, resting HR", allowed: true)
                permitRow("No writes to Apple Health or Garmin", allowed: false)
                permitRow("No account. Later connections stay optional.", allowed: false)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            Text("Without Health, Today can still name a session but cannot show readiness receipts.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.dim)
                .padding(.top, 12)
            Spacer()
            primaryButton(isRequestingHealth ? nil : "Allow Health access") {
                requestHealth()
            }
            textButton("Continue without it") { step = .race }
        }
    }

    private var hub: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Today already has a session")
                .font(.torHeading(28, .bold))
                .foregroundStyle(Theme.text)
                .padding(.bottom, 12)
            Text("Watch, Google Calendar, and Coach are optional. Open a card or go to Calendar.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.dim)
                .padding(.bottom, 16)
            VStack(spacing: 12) {
                setupCard(
                    title: "Watch workouts",
                    subtitle: "Send sessions to Garmin through intervals.icu",
                    symbol: "applewatch"
                ) { step = .intervals }
                setupCard(
                    title: "Google Calendar",
                    subtitle: "See workouts next to work and life",
                    symbol: "calendar"
                ) { step = .calendar }
                setupCard(
                    title: "Coach",
                    subtitle: "Explains today and proposes edits you approve.",
                    symbol: "sparkles"
                ) { step = .coach }
            }
            Spacer()
            primaryButton("Open Calendar", action: finish)
        }
    }

    private func setupHost<Content: View>(
        title: String,
        back: Step,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            backButton { step = back }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func setupCard(title: String, subtitle: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 42, height: 42)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    private func permitRow(_ text: String, allowed: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(allowed ? "+" : "-")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(allowed ? Theme.verdictTrain : Theme.faint)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 44, alignment: .leading)
    }

    private func backButton(_ action: @escaping () -> Void) -> some View {
        Button("Back", action: action)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(minHeight: 44, alignment: .leading)
    }

    private func primaryButton(_ title: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let title {
                    Text(title)
                } else {
                    ProgressView()
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(title == nil)
        .padding(.top, 20)
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, minHeight: 48)
    }

    private func requestHealth() {
        isRequestingHealth = true
        Task {
            defer { isRequestingHealth = false }
            try? await health.requestAuthorization()
            step = .race
        }
    }

    private func finish() {
        OnboardingGate.markCompleted()
        onFinished()
    }
}

private struct FirstRunRaceStep: View {
    let onCreated: () -> Void
    let onLater: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var distance: RaceDistance = .halfMarathon
    @State private var targetHours = 1
    @State private var targetMinutes = 45
    @State private var raceDate = Calendar.current.date(byAdding: .weekOfYear, value: 12, to: .now) ?? .now
    @State private var selectedDays: Set<Weekday> = [.tuesday, .thursday, .saturday, .sunday]
    @State private var longRunDay: Weekday = .sunday
    @State private var fitness: FitnessProfile?
    @State private var comfortablePaceMinutes = 6
    @State private var comfortablePaceSeconds = 0
    @State private var manualWeeklyKm = 25.0
    @State private var saveError: String?
    @State private var didCheck = false

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if didCheck, let assessment {
                feasibility(assessment)
            } else {
                raceForm
            }
        }
        .task {
            fitness = try? PlanStore.currentFitness(in: modelContext, today: .now, calendar: calendar)
        }
    }

    private var raceForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Set the race you entered")
                    .font(.torHeading(28, .bold))
                    .foregroundStyle(Theme.text)
                Text("Your plan is built backward from race day: distance, date, and target time.")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.dim)

                labeled("Distance") {
                    Picker("Distance", selection: $distance) {
                        ForEach(RaceDistance.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .padding(.horizontal, 14)
                    .background(Theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                DatePicker(
                    "Race date",
                    selection: $raceDate,
                    in: calendar.date(byAdding: .day, value: 1, to: .now)!...,
                    displayedComponents: .date
                )
                .frame(minHeight: 48)

                labeled("Target time (h:mm)") {
                    HStack {
                        Picker("Hours", selection: $targetHours) {
                            ForEach(0..<8, id: \.self) { Text("\($0) h").tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        Picker("Minutes", selection: $targetMinutes) {
                            ForEach(0..<60, id: \.self) { Text(String(format: "%02d m", $0)).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Running days")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                    HStack(spacing: 6) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            dayToggle(day)
                        }
                    }
                    Text("Hard sessions are spaced across these days.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                }

                labeled("Long run day") {
                    Picker("Long run day", selection: $longRunDay) {
                        ForEach(selectedDays.sorted(), id: \.self) { Text($0.shortName).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                }

                if fitness == nil {
                    labeled("Comfortable pace /km") {
                        HStack {
                            Picker("Min", selection: $comfortablePaceMinutes) {
                                ForEach(3..<10, id: \.self) { Text("\($0)").tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            Text(":")
                            Picker("Sec", selection: $comfortablePaceSeconds) {
                                ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    }
                    Stepper(
                        "Weekly volume: \(Int(manualWeeklyKm)) km",
                        value: $manualWeeklyKm,
                        in: 10...80,
                        step: 5
                    )
                    .frame(minHeight: 44)
                }

                if let saveError {
                    Text(saveError).foregroundStyle(Theme.bad)
                }

                Button("Check this race") { didCheck = true }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(!isValid)
                    .padding(.top, 8)
                Button("Later", action: onLater)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func feasibility(_ assessment: FeasibilityCheck.Assessment) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Button("Back") { didCheck = false }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44, alignment: .leading)
            Text(assessment.verdict == .unrealistic ? "This date is tight" : "This race looks realistic")
                .font(.torHeading(28, .bold))
                .foregroundStyle(Theme.text)
            Text(summaryLine)
                .font(.system(size: 16))
                .foregroundStyle(Theme.dim)
            VStack(alignment: .leading, spacing: 6) {
                Text("Feasibility")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
                Text(assessment.verdict.firstRunTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(assessment.verdict.firstRunColor)
                Text(assessment.firstRunHint)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.dim)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            Spacer()
            Button(assessment.verdict == .unrealistic ? "Edit race" : "Create plan") {
                if assessment.verdict == .unrealistic {
                    didCheck = false
                } else {
                    save()
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if assessment.verdict == .unrealistic {
                Button("Create plan anyway", action: save)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                Button("Edit race") { didCheck = false }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
            }
        }
    }

    private func dayToggle(_ day: Weekday) -> some View {
        let on = selectedDays.contains(day)
        return Button(String(day.shortName.prefix(1))) {
            if on {
                if selectedDays.count > 3 { selectedDays.remove(day) }
            } else {
                selectedDays.insert(day)
            }
            if !selectedDays.contains(longRunDay), let fallback = selectedDays.sorted().last {
                longRunDay = fallback
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(on ? Theme.text : Theme.dim)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(
            on ? Theme.accentSoft : Theme.card2,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityLabel(day.shortName)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.dim)
            content()
        }
    }

    private var targetTimeSeconds: Double {
        Double(targetHours * 3600 + targetMinutes * 60)
    }

    private var effectiveFitness: FitnessProfile {
        fitness ?? FitnessEstimator.profile(
            comfortablePaceSecondsPerKm: Double(comfortablePaceMinutes * 60 + comfortablePaceSeconds),
            weeklyVolumeKm: manualWeeklyKm
        )
    }

    private var isValid: Bool {
        targetTimeSeconds > 0
            && (3...7).contains(selectedDays.count)
            && selectedDays.contains(longRunDay)
            && calendar.startOfDay(for: raceDate) > calendar.startOfDay(for: .now)
    }

    private var assessment: FeasibilityCheck.Assessment? {
        guard isValid else { return nil }
        return FeasibilityCheck.assess(
            goal: currentSpec, fitness: effectiveFitness, today: .now, calendar: calendar
        )
    }

    private var currentSpec: GoalSpec {
        GoalSpec(
            distance: distance,
            targetTimeSeconds: targetTimeSeconds,
            raceDate: raceDate,
            availableDays: selectedDays,
            longRunDay: longRunDay
        )
    }

    private var summaryLine: String {
        let days = selectedDays.count
        return "\(distance.displayName) on \(raceDate.formatted(date: .abbreviated, time: .omitted)) at \(Formatters.duration(targetTimeSeconds)). \(days) run days. Long run \(longRunDay.shortName)."
    }

    private func save() {
        do {
            try PlanStore.replaceGoal(
                spec: currentSpec,
                fitness: effectiveFitness,
                today: .now,
                calendar: calendar,
                in: modelContext
            )
            NotificationCenter.default.post(name: .planDidChange, object: nil)
            onCreated()
        } catch {
            saveError = "Could not save goal: \(error.localizedDescription)"
            didCheck = false
        }
    }
}

private extension FeasibilityVerdict {
    var firstRunTitle: String {
        switch self {
        case .ok: "On track"
        case .stretch: "Stretch"
        case .unrealistic: "Too soon"
        }
    }

    var firstRunColor: Color {
        switch self {
        case .ok: Theme.verdictTrain
        case .stretch: Theme.verdictEasy
        case .unrealistic: Theme.verdictRest
        }
    }
}

private extension FeasibilityCheck.Assessment {
    var firstRunHint: String {
        let goal = Int(goalVDOT.rounded())
        let projected = Int(projectedVDOT.rounded())
        switch verdict {
        case .ok:
            return "Target needs about VDOT \(goal). You project \(projected). The plan keeps hard sessions to two a week."
        case .stretch:
            return "Target needs about VDOT \(goal). You project \(projected). The plan can try, with more easy volume and fewer quality days."
        case .unrealistic:
            return "This date is too close for that time. Edit the race or pick a later event."
        }
    }
}
