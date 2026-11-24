import SwiftUI

struct GalleryDateFilter: Equatable {
    let start: Date
    let end: Date
    func includes(_ date: Date?, calendar: Calendar = .current) -> Bool {
        guard let date else { return false }
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: start) && day <= calendar.startOfDay(for: end)
    }
}

enum GalleryDateSelection {
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

    init(filter: Binding<GalleryDateFilter?>) {
        self._filter = filter
        let existing = filter.wrappedValue
        let calendar = Calendar.current
        let days = existing.map { [calendar.dateComponents([.year, .month, .day], from: $0.start),
                                   calendar.dateComponents([.year, .month, .day], from: $0.end)] } ?? []
        self._selection = State(initialValue: Set(days))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Selecione um dia ou as duas datas do intervalo") {
                    MultiDatePicker("Datas", selection: $selection).labelsHidden()
                    if let selected = GalleryDateSelection.filter(from: selection) {
                        let start = selected.start.formatted(date: .abbreviated, time: .omitted)
                        let end = selected.end.formatted(date: .abbreviated, time: .omitted)
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
        }.preferredColorScheme(.dark)
    }
}
