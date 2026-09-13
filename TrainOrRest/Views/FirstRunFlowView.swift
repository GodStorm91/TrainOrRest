import SwiftData
import SwiftUI
import UIKit

enum FirstRunHealthAuthorizationState: Equatable {
    case explanation
    case requesting
    case denied
    case restricted
    case notDetermined
    case failed(String)
}

enum FirstRunHealthAuthorizationTransition: Equatable {
    case stay
    case advance(showSettingsGuidance: Bool)
}

struct FirstRunHealthAuthorizationFlow {
    private(set) var state: FirstRunHealthAuthorizationState = .explanation

    mutating func beginRequest() -> Bool {
        switch state {
        case .explanation, .notDetermined, .failed:
            state = .requesting
            return true
        case .requesting, .denied, .restricted:
            return false
        }
    }

    mutating func finish(
        _ outcome: HealthAuthorizationOutcome
    ) -> FirstRunHealthAuthorizationTransition {
        switch outcome {
        case .requestCompleted, .previouslyRequested:
            return .advance(showSettingsGuidance: true)
        case .denied:
            state = .denied
        case .restricted:
            state = .restricted
        case .notDetermined:
            state = .notDetermined
        case let .failed(message):
            state = .failed(message)
        }
        return .stay
    }
}
struct FirstRunFlowView: View {
    enum Step: Int {
        case language, welcome, health, race, hub, intervals, calendar, coach
    }

    let health: HealthKitService
    let onFinished: () -> Void

    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @State private var step: Step = .language
    @State private var healthAuthorization = FirstRunHealthAuthorizationFlow()
    @State private var showHealthSettingsGuidance = false
    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }

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
        .environment(\.locale, language.uiLocale)
        .interactiveDismissDisabled()
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(barColor(index))
                    .frame(height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(language.onboarding.progressStep(barIndex + 1, of: 5))
    }

    private var barIndex: Int {
        switch step {
        case .language: 0
        case .welcome: 1
        case .health: 2
        case .race: 3
        case .hub, .intervals, .calendar, .coach: 4
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
        case .language:
            languageStep
        case .welcome:
            welcome
        case .health:
            healthStep
        case .race:
            FirstRunRaceStep(
                language: language,
                showHealthSettingsGuidance: showHealthSettingsGuidance,
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
            setupHost(title: language.onboarding.coachSetupTitle, back: .hub) {
                CoachProviderSettingsView()
            }
        }
    }

    private var languageStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TrainOrRest")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.faint)
                .padding(.bottom, 8)
            Text(language.onboarding.languageChoiceTitle)
                .font(.torHeading(28, .bold))
                .foregroundStyle(Theme.text)
                .padding(.bottom, 12)
            Text(language.onboarding.languageChoiceSubtitle)
                .font(.system(size: 16))
                .foregroundStyle(Theme.dim)
                .padding(.bottom, 20)
            VStack(spacing: 8) {
                ForEach(CoachLanguage.allCases) { option in
                    Button {
                        languageRaw = option.rawValue
                    } label: {
                        HStack(spacing: 12) {
                            Text(option.flag)
                                .font(.system(size: 22))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.nativeName)
                                    .foregroundStyle(Theme.text)
                                Text(option.englishName)
                                    .font(.caption)
                                    .foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            if option == language {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    option == language ? Theme.accent : Theme.border,
                                    lineWidth: 1
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.nativeName)
                    .accessibilityValue(option == language ? language.onboarding.selected : option.englishName)
                    .accessibilityAddTraits(option == language ? [.isSelected] : [])
                }
            }
            Spacer()
            primaryButton(language.onboarding.startSetupLabel) { step = .welcome }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TrainOrRest")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.faint)
                .padding(.bottom, 8)
            Text(language.onboarding.welcomeHeadline)
                .font(.torHeading(28, .bold))
                .foregroundStyle(Theme.text)
                .padding(.bottom, 12)
            Text(language.onboarding.welcomeDescription)
                .font(.system(size: 16))
                .foregroundStyle(Theme.dim)
                .padding(.bottom, 12)
            Text(language.onboarding.welcomeDuration)
                .font(.system(size: 13))
                .foregroundStyle(Theme.faint)
            Spacer()
            primaryButton(language.onboarding.connectAppleHealth) { step = .health }
        }
    }

    private var healthStep: some View {
        Group {
            switch healthAuthorization.state {
            case .explanation, .requesting:
                healthExplanation
            case .denied, .restricted, .notDetermined, .failed:
                healthFeedback
            }
        }
    }

    private var healthExplanation: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(language.onboarding.connectAppleHealth)
                .font(.torHeading(28, .bold))
                .foregroundStyle(Theme.text)
                .padding(.bottom, 12)
            Text(language.onboarding.healthDescription)
                .font(.system(size: 16))
                .foregroundStyle(Theme.dim)
                .padding(.bottom, 16)
            VStack(alignment: .leading, spacing: 10) {
                permitRow(language.onboarding.healthReadPermission, allowed: true)
                permitRow(language.onboarding.healthNoWritePermission, allowed: false)
                permitRow(language.onboarding.healthNoAccountPermission, allowed: false)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            Spacer()
            primaryButton(
                healthAuthorization.state == .requesting ? nil : language.continueLabel
            ) {
                requestHealth()
            }
        }
    }

    private var healthFeedback: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: healthFeedbackSymbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.bottom, 16)
            Text(healthFeedbackTitle)
                .font(.torHeading(28, .bold))
                .foregroundStyle(Theme.text)
                .padding(.bottom, 12)
            Text(healthFeedbackDescription)
                .font(.system(size: 16))
                .foregroundStyle(Theme.dim)
            Spacer()
            healthFeedbackActions
        }
    }

    private var healthFeedbackSymbol: String {
        switch healthAuthorization.state {
        case .denied: "heart.slash"
        case .restricted: "lock.shield"
        case .notDetermined, .failed: "exclamationmark.triangle"
        case .explanation, .requesting: "heart"
        }
    }

    private var healthFeedbackTitle: String {
        switch healthAuthorization.state {
        case .denied: language.onboarding.healthAccessDeniedTitle
        case .restricted: language.onboarding.healthAccessRestrictedTitle
        case .notDetermined: language.onboarding.healthAccessNotDeterminedTitle
        case .failed: language.onboarding.healthAccessErrorTitle
        case .explanation, .requesting: language.onboarding.connectAppleHealth
        }
    }

    private var healthFeedbackDescription: String {
        switch healthAuthorization.state {
        case .denied:
            language.onboarding.healthAccessDeniedDescription
        case .restricted:
            language.onboarding.healthAccessRestrictedDescription
        case .notDetermined:
            language.onboarding.healthAccessNotDeterminedDescription
        case let .failed(message):
            language.onboarding.healthAccessErrorDescription(message)
        case .explanation, .requesting:
            language.onboarding.healthDescription
        }
    }

    @ViewBuilder
    private var healthFeedbackActions: some View {
        switch healthAuthorization.state {
        case .denied:
            openHealthSettingsButton
            textButton(language.continueLabel) {
                advanceAfterHealth(showSettingsGuidance: true)
            }
        case .restricted:
            primaryButton(language.continueLabel) {
                advanceAfterHealth(showSettingsGuidance: false)
            }
        case .notDetermined:
            primaryButton(language.continueLabel) {
                requestHealth()
            }
        case .failed:
            primaryButton(language.retryLabel) {
                requestHealth()
            }
            textButton(language.continueLabel) {
                advanceAfterHealth(showSettingsGuidance: true)
            }
        case .explanation, .requesting:
            EmptyView()
        }
    }

    private var openHealthSettingsButton: some View {
        Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
            Text(language.onboarding.openHealthSettings)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 20)
    }

    private var hub: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(language.onboarding.hubTitle)
                .font(.torHeading(28, .bold))
                .foregroundStyle(Theme.text)
                .padding(.bottom, 12)
            Text(language.onboarding.hubDescription)
                .font(.system(size: 16))
                .foregroundStyle(Theme.dim)
                .padding(.bottom, 16)
            VStack(spacing: 12) {
                setupCard(
                    title: language.onboarding.watchWorkoutsTitle,
                    subtitle: language.onboarding.watchWorkoutsSubtitle,
                    symbol: "applewatch"
                ) { step = .intervals }
                setupCard(
                    title: "Google Calendar",
                    subtitle: language.onboarding.googleCalendarSubtitle,
                    symbol: "calendar"
                ) { step = .calendar }
                setupCard(
                    title: language.onboarding.coachSetupTitle,
                    subtitle: language.onboarding.coachSetupSubtitle,
                    symbol: "sparkles"
                ) { step = .coach }
            }
            Spacer()
            primaryButton(language.onboarding.openCalendar, action: finish)
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
        Button(language.backLabel, action: action)
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
        guard healthAuthorization.beginRequest() else { return }
        Task {
            let outcome = await health.requestAuthorization()
            switch healthAuthorization.finish(outcome) {
            case .stay:
                break
            case let .advance(showSettingsGuidance):
                advanceAfterHealth(showSettingsGuidance: showSettingsGuidance)
            }
        }
    }

    private func advanceAfterHealth(showSettingsGuidance: Bool) {
        self.showHealthSettingsGuidance = showSettingsGuidance
        step = .race
    }

    private func finish() {
        OnboardingGate.markCompleted()
        onFinished()
    }
}

private struct FirstRunRaceStep: View {
    let language: CoachLanguage
    let showHealthSettingsGuidance: Bool
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
                Text(language.onboarding.raceSetupTitle)
                    .font(.torHeading(28, .bold))
                    .foregroundStyle(Theme.text)
                Text(language.onboarding.raceSetupDescription)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.dim)

                if showHealthSettingsGuidance {
                    healthSettingsGuidance
                }

                labeled(language.onboarding.distance) {
                    Picker(language.onboarding.distance, selection: $distance) {
                        ForEach(RaceDistance.allCases) { Text(language.name($0)).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .padding(.horizontal, 14)
                    .background(Theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                DatePicker(
                    language.onboarding.raceDate,
                    selection: $raceDate,
                    in: calendar.date(byAdding: .day, value: 1, to: .now)!...,
                    displayedComponents: .date
                )
                .frame(minHeight: 48)

                labeled(language.onboarding.targetTime) {
                    HStack {
                        Picker(language.onboarding.hours, selection: $targetHours) {
                            ForEach(0..<8, id: \.self) { Text(language.onboarding.targetHour($0)).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        Picker(language.onboarding.minutes, selection: $targetMinutes) {
                            ForEach(0..<60, id: \.self) { Text(language.onboarding.targetMinute($0)).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(language.onboarding.runningDays)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                    HStack(spacing: 6) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            dayToggle(day)
                        }
                    }
                    Text(language.onboarding.runningDaysHint)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                }

                labeled(language.onboarding.longRunDay) {
                    Picker(language.onboarding.longRunDay, selection: $longRunDay) {
                        ForEach(selectedDays.sorted(), id: \.self) { Text(language.shortName($0)).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                }

                if fitness == nil {
                    labeled(language.onboarding.comfortablePace) {
                        HStack {
                            Picker(language.onboarding.minutesAbbreviation, selection: $comfortablePaceMinutes) {
                                ForEach(3..<10, id: \.self) { Text($0.formatted(.number.locale(language.uiLocale))).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            Text(":")
                            Picker(language.onboarding.secondsAbbreviation, selection: $comfortablePaceSeconds) {
                                ForEach([0, 15, 30, 45], id: \.self) {
                                    Text($0.formatted(.number.precision(.integerLength(2)).locale(language.uiLocale))).tag($0)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    }
                    Stepper(
                        language.onboarding.weeklyVolume(manualWeeklyKm),
                        value: $manualWeeklyKm,
                        in: 10...80,
                        step: 5
                    )
                    .frame(minHeight: 44)
                }

                if let saveError {
                    Text(saveError).foregroundStyle(Theme.bad)
                }

                Button(language.onboarding.checkRace) { didCheck = true }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(!isValid)
                    .padding(.top, 8)
                Button(language.onboarding.later, action: onLater)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var healthSettingsGuidance: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(language.onboarding.healthAccessDecidedTitle, systemImage: "heart.text.square")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(language.onboarding.healthAccessDecidedDescription)
                .font(.system(size: 14))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            Link(
                language.onboarding.openHealthSettings,
                destination: URL(string: UIApplication.openSettingsURLString)!
            )
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(minHeight: 44)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private func feasibility(_ assessment: FeasibilityCheck.Assessment) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(language.backLabel) { didCheck = false }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44, alignment: .leading)
            Text(
                assessment.verdict == .unrealistic
                    ? language.onboarding.tightDateTitle
                    : language.onboarding.realisticRaceTitle
            )
            .font(.torHeading(28, .bold))
            .foregroundStyle(Theme.text)
            Text(summaryLine)
                .font(.system(size: 16))
                .foregroundStyle(Theme.dim)
            VStack(alignment: .leading, spacing: 6) {
                Text(language.onboarding.feasibility)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
                Text(language.onboarding.feasibilityVerdict(assessment.verdict))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(assessment.verdict.firstRunColor)
                Text(
                    language.onboarding.feasibilityHint(
                        assessment.verdict,
                        goal: Int(assessment.goalVDOT.rounded()),
                        projected: Int(assessment.projectedVDOT.rounded())
                    )
                )
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
            Button(
                assessment.verdict == .unrealistic
                    ? language.onboarding.editRace
                    : language.onboarding.createPlan
            ) {
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
                Button(language.onboarding.createPlanAnyway, action: save)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                Button(language.onboarding.editRace) { didCheck = false }
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
        return Button(language.shortName(day)) {
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
        .accessibilityLabel(language.shortName(day))
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
        language.onboarding.raceSummary(
            distance: language.name(distance),
            date: language.shortDate(raceDate),
            targetTime: Formatters.duration(targetTimeSeconds),
            runningDays: selectedDays.count,
            longRunDay: language.shortName(longRunDay)
        )
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
            saveError = language.onboarding.goalSaveError
            didCheck = false
        }
    }
}

private extension FeasibilityVerdict {
    var firstRunColor: Color {
        switch self {
        case .ok: Theme.verdictTrain
        case .stretch: Theme.verdictEasy
        case .unrealistic: Theme.verdictRest
        }
    }
}
