import SwiftUI

struct GalleryDateFilter: Equatable {
    let start: Date
    let end: Date
    static func today(now: Date = Date()) -> GalleryDateFilter {
        GalleryDateFilter(start: now, end: now)
    }
    func includes(_ date: Date?, calendar: Calendar = .current) -> Bool {
        guard let date else { return false }
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: start) && day <= calendar.startOfDay(for: end)
    }
}

enum GalleryDateSelection {
    static let brazilianLocale = Locale(identifier: "pt_BR")

    static func brazilianCalendar(basedOn calendar: Calendar = .current) -> Calendar {
        var result = calendar
        result.locale = brazilianLocale
        return result
    }

    static func limited(_ next: Set<DateComponents>, previous: Set<DateComponents>) -> Set<DateComponents> {
        guard next.count > 2 else { return next }
        return next.subtracting(previous)
    }

    static func filter(from selection: Set<DateComponents>, calendar: Calendar = .current) -> GalleryDateFilter? {
        let days = selection.compactMap { calendar.date(from: $0) }.sorted()
        guard !days.isEmpty, days.count == selection.count, days.count <= 2,
              let first = days.first, let last = days.last else { return nil }
        return GalleryDateFilter(start: first, end: last)
    }
}

struct GalleryDateFilterView: View {
    @Binding var filter: GalleryDateFilter?
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<DateComponents>
    @State private var month: Date

    init(filter: Binding<GalleryDateFilter?>) {
        self._filter = filter
        let existing = filter.wrappedValue
        let calendar = GalleryDateSelection.brazilianCalendar()
        let days = existing.map { [calendar.dateComponents([.year, .month, .day], from: $0.start),
                                   calendar.dateComponents([.year, .month, .day], from: $0.end)] } ?? []
        self._selection = State(initialValue: Set(days))
        self._month = State(initialValue: existing?.start ?? Date())
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Selecione um dia ou as duas datas do intervalo") {
                    GalleryCalendarGrid(selection: $selection, month: $month)
                    if let selected = GalleryDateSelection.filter(from: selection) {
                        let format = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(GalleryDateSelection.brazilianLocale)
                        let start = selected.start.formatted(format)
                        let end = selected.end.formatted(format)
                        Text(Calendar.current.isDate(selected.start, inSameDayAs: selected.end) ? start : "\(start) – \(end)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if filter != nil {
                    Button("Limpar filtro", role: .destructive) { filter = nil; dismiss() }
                }
            }
            .onChange(of: selection) { old, new in
                let limited = GalleryDateSelection.limited(new, previous: old)
                if limited != new { selection = limited }
            }
            .navigationTitle("Filtrar por data").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") {
                        filter = GalleryDateSelection.filter(from: selection)
                        dismiss()
                    }.disabled(selection.isEmpty)
                }
            }
        }
        .environment(\.locale, GalleryDateSelection.brazilianLocale)
        .environment(\.calendar, GalleryDateSelection.brazilianCalendar())
        .preferredColorScheme(.dark)
    }
}

/// A single month stays in place while a drag selects a range. Month navigation
/// is explicit, so an existing start date remains selected across months.
private struct GalleryCalendarGrid: View {
    @Binding var selection: Set<DateComponents>
    @Binding var month: Date
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var dragAnchor: Date?
    @State private var rangeAnchor: Date?
    @State private var extendAfterMonthChange = false
    private let rowHeight: CGFloat = 44

    private var monthStart: Date { calendar.dateInterval(of: .month, for: month)?.start ?? month }
    private var leading: Int {
        (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
    }
    private var dayCount: Int { calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 0 }
    private var rows: Int { (leading + dayCount + 6) / 7 }
    private var headings: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...]) + Array(symbols[..<offset])
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Mês anterior")
                Spacer()
                Text(monthStart.formatted(.dateTime.month(.wide).year().locale(locale))).font(.headline)
                Spacer()
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Próximo mês")
            }.buttonStyle(.plain)
            HStack(spacing: 0) {
                ForEach(Array(headings.enumerated()), id: \.offset) { _, title in
                    Text(title).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }.accessibilityHidden(true)
            GeometryReader { geometry in
                let width = geometry.size.width / 7
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                    ForEach(0..<(rows * 7), id: \.self) { index in
                        if let day = date(at: index) {
                            dayCell(day).frame(height: rowHeight)
                        } else {
                            Color.clear.frame(height: rowHeight).accessibilityHidden(true)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard width > 0 else { return }
                        let column = Int(floor(value.location.x / width))
                        let row = Int(floor(value.location.y / rowHeight))
                        guard column >= 0, column < 7, row >= 0, row < rows,
                              let day = date(at: row * 7 + column) else { return }
                        if dragAnchor == nil {
                            let existing = GalleryDateSelection.filter(from: selection, calendar: calendar)
                            if extendAfterMonthChange, let first = rangeAnchor ?? existing?.start {
                                dragAnchor = first
                            } else {
                                dragAnchor = selection.count == 1 ? existing?.start : day
                            }
                            rangeAnchor = dragAnchor
                            extendAfterMonthChange = false
                        }
                        guard let anchor = dragAnchor else { return }
                        selection = Set([components(anchor), components(day)])
                    }
                    .onEnded { _ in dragAnchor = nil })
            }.frame(height: CGFloat(rows) * rowHeight)
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let interval = GalleryDateSelection.filter(from: selection, calendar: calendar)
        let selected = interval?.includes(day, calendar: calendar) ?? false
        let endpoint = selection.contains(components(day))
        return Text("\(calendar.component(.day, from: day))")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(selected && !endpoint ? Color.yellow.opacity(0.18) : .clear)
            .background { if endpoint { Circle().fill(.yellow).padding(3) } }
            .foregroundStyle(endpoint ? .black : .primary)
            .contentShape(Rectangle())
            .accessibilityLabel(day.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(locale)))
            .accessibilityAddTraits(endpoint ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction {
                let existing = GalleryDateSelection.filter(from: selection, calendar: calendar)
                if (extendAfterMonthChange || selection.count == 1), let anchor = rangeAnchor ?? existing?.start {
                    selection = Set([components(anchor), components(day)])
                    rangeAnchor = anchor
                } else { selection = [components(day)]; rangeAnchor = day }
                extendAfterMonthChange = false
            }
    }

    private func components(_ day: Date) -> DateComponents { calendar.dateComponents([.year, .month, .day], from: day) }
    private func date(at index: Int) -> Date? {
        let day = index - leading + 1
        guard (1...dayCount).contains(day) else { return nil }
        return calendar.date(byAdding: .day, value: day - 1, to: monthStart)
    }
    private func moveMonth(_ offset: Int) {
        if let next = calendar.date(byAdding: .month, value: offset, to: monthStart) {
            extendAfterMonthChange = !selection.isEmpty
            month = next
        }
    }
}
