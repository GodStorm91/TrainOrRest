import SwiftData
import SwiftUI
import UIKit

/// Run History: an overview card of real aggregates over the selected period,
/// then the run list. Reached from Profile → Run history.
struct ActivityListView: View {
    @Query(sort: \CompletedActivity.date, order: .reverse) private var activities: [CompletedActivity]
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    @State private var period: Period = .calendarMonth
    @State private var selectedMonth: Date = Calendar.current.startOfMonth(for: .now)
    @State private var selectedYear: Int = Calendar.current.component(.year, from: .now)
    @State private var showingMonthPicker = false
    @State private var isChangingPeriod = false

    private var calendar: Calendar { Calendar.current }
    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }
    private var locale: Locale {
        switch language {
        case .en: Locale(identifier: "en_US")
        case .ja: Locale(identifier: "ja_JP")
        case .vi: Locale(identifier: "vi_VN")
        }
    }

    enum Period: String, CaseIterable, Identifiable {
        case rolling30 = "30d"
        case calendarMonth = "Month"
        case calendarYear = "Year"
        var id: Self { self }
    }

    private var filtered: [CompletedActivity] {
        let range = selectedRange
        return activities
            .filter { $0.date >= range.start && $0.date < range.end }
            .sorted { $0.date > $1.date }
    }

    private var selectedRange: (start: Date, end: Date) {
        switch period {
        case .rolling30:
            let end = Date()
            let start = calendar.date(byAdding: .day, value: -30, to: end) ?? .distantPast
            return (start, end)
        case .calendarMonth:
            let start = calendar.startOfMonth(for: selectedMonth)
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? .distantFuture
            return (start, end)
        case .calendarYear:
            let start = calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1)) ?? .distantPast
            let end = calendar.date(from: DateComponents(year: selectedYear + 1, month: 1, day: 1)) ?? .distantFuture
            return (start, end)
        }
    }

    var body: some View {
        ScrollViewReader { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    periodToggle
                    if period != .rolling30 {
                        periodNavigator
                    }

                    if isChangingPeriod {
                        loadingSkeleton
                    } else if filtered.isEmpty {
                        emptyState
                    } else {
                        OverviewCard(summary: RunHistorySummary(activities: filtered), eyebrow: summaryTitle)
                        TorEyebrow("Activities").tracking(2)
                        LazyVStack(spacing: 10) {
                            ForEach(filtered) { activity in
                                NavigationLink {
                                    ActivityDetailView(activity: activity)
                                } label: {
                                    ActivityRow(activity: activity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .torReadableColumn()
            }
        }
        .background(Theme.bg)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 82)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Run History")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMonthPicker) {
            MonthYearPickerSheet(
                selectedMonth: $selectedMonth,
                locale: locale,
                calendar: calendar,
                onSelect: { announcePeriodChange() }
            )
        }
        .onChange(of: activities.count) { _, _ in
            clampFutureSelections()
        }
        .animation(.easeOut(duration: 0.22), value: filtered.count)
        .animation(.easeOut(duration: 0.18), value: period)
    }

    private var periodToggle: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(Period.allCases) { option in
                    Button {
                        guard !isChangingPeriod else { return }
                        selectPeriod(option)
                    } label: {
                        let selected = option == period
                        Text(option.rawValue)
                            .font(.torHeading(12, selected ? .bold : .semibold))
                            .foregroundStyle(selected ? Color.white : Theme.faint)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .frame(minHeight: 44)
                            .background(
                                selected ? Theme.accent : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(selected ? Theme.accent.opacity(0.9) : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.accessibilityLabel)
                    .accessibilityAddTraits(option == period ? [.isSelected] : [])
                }
            }
            .padding(3)
            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var periodNavigator: some View {
        HStack(spacing: 10) {
            Button {
                navigatePeriod(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.text)
            .accessibilityLabel(previousAccessibilityLabel)

            if period == .calendarMonth {
                Button {
                    showingMonthPicker = true
                } label: {
                    Text(monthYearTitle)
                        .font(.torHeading(17, .bold))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select month and year. Current selection \(monthYearTitle)")
            } else {
                Text(String(selectedYear))
                    .font(.torHeading(17, .bold))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .accessibilityAddTraits(.isHeader)
            }

            Button {
                navigatePeriod(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canNavigateForward ? Theme.text : Theme.faint.opacity(0.5))
            .disabled(!canNavigateForward)
            .accessibilityLabel(nextAccessibilityLabel)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                .frame(height: 186)
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.card2)
                    .frame(height: 64)
            }
        }
        .redacted(reason: .placeholder)
        .transition(.opacity)
        .accessibilityLabel("Loading selected run history period")
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ContentUnavailableView(
                emptyTitle,
                systemImage: "figure.run",
                description: Text(emptyDescription)
            )
            if period == .calendarMonth && !calendar.isDate(selectedMonth, equalTo: Date(), toGranularity: .month) {
                Button {
                    selectedMonth = calendar.startOfMonth(for: .now)
                    announcePeriodChange()
                } label: {
                    Text("Go to current month")
                        .font(.callout.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 34)
    }

    private func selectPeriod(_ option: Period) {
        guard option != period else { return }
        withLoadingPulse {
            period = option
            clampFutureSelections()
        }
        announcePeriodChange()
    }

    private func navigatePeriod(by value: Int) {
        guard period != .rolling30 else { return }
        withLoadingPulse {
            switch period {
            case .rolling30:
                break
            case .calendarMonth:
                if let next = calendar.date(byAdding: .month, value: value, to: selectedMonth) {
                    selectedMonth = minMonth(next, calendar.startOfMonth(for: .now))
                }
            case .calendarYear:
                selectedYear = min(selectedYear + value, currentYear)
            }
            clampFutureSelections()
        }
        announcePeriodChange()
    }

    private func withLoadingPulse(_ work: () -> Void) {
        guard !isChangingPeriod else { return }
        isChangingPeriod = true
        work()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            isChangingPeriod = false
        }
    }

    private func clampFutureSelections() {
        selectedMonth = minMonth(calendar.startOfMonth(for: selectedMonth), calendar.startOfMonth(for: .now))
        selectedYear = min(selectedYear, currentYear)
    }

    private func announcePeriodChange() {
        UIAccessibility.post(notification: .announcement, argument: summaryTitle)
    }

    private var currentYear: Int { calendar.component(.year, from: .now) }

    private var canNavigateForward: Bool {
        switch period {
        case .rolling30:
            return false
        case .calendarMonth:
            return calendar.startOfMonth(for: selectedMonth) < calendar.startOfMonth(for: .now)
        case .calendarYear:
            return selectedYear < currentYear
        }
    }

    private var summaryTitle: String {
        switch period {
        case .rolling30:
            "LAST 30 DAYS"
        case .calendarMonth:
            monthYearTitle.uppercased(with: locale)
        case .calendarYear:
            String(selectedYear)
        }
    }

    private var emptyTitle: String {
        switch period {
        case .rolling30:
            "No runs in the last 30 days"
        case .calendarMonth:
            "No runs in \(monthYearTitle)"
        case .calendarYear:
            "No runs in \(selectedYear)"
        }
    }

    private var emptyDescription: String {
        switch period {
        case .rolling30:
            "Your completed runs for this period will appear here."
        case .calendarMonth:
            "Your completed runs for this month will appear here."
        case .calendarYear:
            "Your completed runs for this year will appear here."
        }
    }

    private var monthYearTitle: String {
        monthYearFormatter.string(from: selectedMonth)
    }

    private var monthYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }

    private var previousAccessibilityLabel: String {
        switch period {
        case .rolling30:
            return "Previous period"
        case .calendarMonth:
            let destination = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
            return "Previous month, \(monthYearFormatter.string(from: destination))"
        case .calendarYear:
            return "Previous year, \(selectedYear - 1)"
        }
    }

    private var nextAccessibilityLabel: String {
        switch period {
        case .rolling30:
            return "Next period"
        case .calendarMonth:
            let destination = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
            return canNavigateForward ? "Next month, \(monthYearFormatter.string(from: destination))" : "Next month unavailable"
        case .calendarYear:
            return canNavigateForward ? "Next year, \(selectedYear + 1)" : "Next year unavailable"
        }
    }

    private func minMonth(_ lhs: Date, _ rhs: Date) -> Date {
        lhs <= rhs ? lhs : rhs
    }
}

private struct MonthYearPickerSheet: View {
    @Binding var selectedMonth: Date
    let locale: Locale
    let calendar: Calendar
    let onSelect: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var visibleYear: Int = Calendar.current.component(.year, from: .now)

    private var currentMonthStart: Date { calendar.startOfMonth(for: .now) }
    private var currentYear: Int { calendar.component(.year, from: .now) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                yearNavigator
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(1...12, id: \.self) { month in
                        monthButton(month)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .torReadableColumn()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Select Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                visibleYear = calendar.component(.year, from: selectedMonth)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var yearNavigator: some View {
        HStack(spacing: 10) {
            Button {
                visibleYear -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous year, \(visibleYear - 1)")

            Text(String(visibleYear))
                .font(.torHeading(22, .bold))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            Button {
                visibleYear = min(visibleYear + 1, currentYear)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(visibleYear >= currentYear)
            .foregroundStyle(visibleYear >= currentYear ? Theme.faint.opacity(0.5) : Theme.text)
            .accessibilityLabel(visibleYear >= currentYear ? "Next year unavailable" : "Next year, \(visibleYear + 1)")
        }
    }

    private func monthButton(_ month: Int) -> some View {
        let date = calendar.date(from: DateComponents(year: visibleYear, month: month, day: 1)) ?? selectedMonth
        let disabled = date > currentMonthStart
        let selected = calendar.isDate(date, equalTo: selectedMonth, toGranularity: .month)
        return Button {
            selectedMonth = calendar.startOfMonth(for: date)
            onSelect()
            dismiss()
        } label: {
            Text(monthName(month))
                .font(.callout.weight(selected ? .bold : .semibold))
                .foregroundStyle(selected ? Color.white : disabled ? Theme.faint.opacity(0.45) : Theme.text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(
                    selected ? Theme.accent : Theme.card,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(selected ? Theme.accent.opacity(0.95) : Theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel("\(monthName(month)) \(visibleYear)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        return formatter.monthSymbols[max(0, month - 1)].capitalized(with: locale)
    }
}

/// Aggregates card — distance headline plus pace / time / longest chips.
private struct OverviewCard: View {
    let summary: RunHistorySummary
    let eyebrow: String
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass


    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TorEyebrow(eyebrow).tracking(1.6).foregroundStyle(Theme.dim)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", summary.totalDistanceMeters / 1000))
                    .font(.torNumber(44, .bold))
                    .foregroundStyle(Theme.text)
                Text("km")
                    .font(.torHeading(16, .semibold))
                    .foregroundStyle(Theme.dim)
            }
            Text("total distance · \(summary.runCount) \(summary.runCount == 1 ? "run" : "runs")")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.faint)

            summaryMetrics
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    @ViewBuilder
    private var summaryMetrics: some View {
        if horizontalSizeClass == .regular {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                stat(paceText, "AVG PACE", Theme.text)
                stat(Formatters.duration(summary.totalDurationSeconds), "TOTAL TIME", Theme.text)
                stat(longestText, "LONGEST km", Theme.good)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    stat(paceText, "AVG PACE", Theme.text)
                    stat(Formatters.duration(summary.totalDurationSeconds), "TOTAL TIME", Theme.text)
                    stat(longestText, "LONGEST km", Theme.good)
                }
                VStack(alignment: .leading, spacing: 10) {
                    stat(paceText, "AVG PACE", Theme.text)
                    stat(Formatters.duration(summary.totalDurationSeconds), "TOTAL TIME", Theme.text)
                    stat(longestText, "LONGEST km", Theme.good)
                }
            }
        }
    }

    private var paceText: String {
        guard let pace = summary.averagePaceSecondsPerKm else { return "–" }
        return Formatters.pace(pace).replacingOccurrences(of: " /km", with: "")
    }

    private var longestText: String {
        guard let meters = summary.longestDistanceMeters else { return "–" }
        return String(format: "%.1f", meters / 1000)
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.torHeading(17, .bold)).foregroundStyle(color)
            Text(label).font(.system(size: 9.5, weight: .semibold)).tracking(0.5).foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private extension ActivityListView.Period {
    var accessibilityLabel: String {
        switch self {
        case .rolling30: "Last 30 days"
        case .calendarMonth: "Month"
        case .calendarYear: "Year"
        }
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components).map(startOfDay(for:)) ?? startOfDay(for: date)
    }
}
