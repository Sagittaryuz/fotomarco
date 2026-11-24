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

struct GalleryDateFilterView: View {
    @Binding var filter: GalleryDateFilter?
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var range: Bool

    init(filter: Binding<GalleryDateFilter?>) {
        self._filter = filter
        let existing = filter.wrappedValue
        self._start = State(initialValue: existing?.start ?? Date())
        self._end = State(initialValue: existing?.end ?? Date())
        self._range = State(initialValue: existing.map { !Calendar.current.isDate($0.start, inSameDayAs: $0.end) } ?? false)
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Período", selection: $range) {
                    Text("Um dia").tag(false)
                    Text("Intervalo").tag(true)
                }.pickerStyle(.segmented)
                Section(range ? "Data inicial" : "Selecione a data") {
                    DatePicker("Data inicial", selection: $start, displayedComponents: .date)
                        .datePickerStyle(.graphical).labelsHidden()
                }
                if range {
                    Section("Data final") {
                        DatePicker("Data final", selection: $end, in: Calendar.current.startOfDay(for: start)..., displayedComponents: .date)
                            .datePickerStyle(.graphical).labelsHidden()
                    }
                }
                if filter != nil {
                    Button("Limpar filtro", role: .destructive) { filter = nil; dismiss() }
                }
            }
            .onChange(of: start) { _, value in if end < Calendar.current.startOfDay(for: value) { end = value } }
            .navigationTitle("Filtrar por data").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") {
                        filter = GalleryDateFilter(start: start, end: range ? max(start, end) : start)
                        dismiss()
                    }
                }
            }
        }.preferredColorScheme(.dark)
    }
}
