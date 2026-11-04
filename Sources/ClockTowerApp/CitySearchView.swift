import AppKit
import ClockTowerCore
import SwiftUI

@MainActor
struct CitySearchView: View {
    @ObservedObject var model: AppModel
    let cancel: () -> Void
    let add: (CityClock) -> Void
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var result: (query: String, cities: [CityClock]) = ("", [])
    @State private var submittedQuery: String?
    @State private var selection = 0

    private var isEmpty: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var pending: Bool { result.query != query }
    private var cities: [CityClock] { pending ? [] : result.cities }
    private var resultsHeight: CGFloat {
        max(84, min(280, CGFloat(result.cities.count) * 45 + 12))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: cancel) {
                    Image(systemName: "chevron.backward")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to World Clocks")
                .help("Back to World Clocks")
                Text("Add City")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            CitySearchField(query: Binding(get: { query }, set: { updateQuery($0) }), move: moveSelection, submit: addSelection, cancel: cancel)
                .frame(height: 28)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()
            if isEmpty || pending || cities.isEmpty {
                VStack(spacing: 5) {
                    if !isEmpty && !pending { Text("No matching cities").font(.headline) }
                    Text(pending && !isEmpty ? "Searching cities…" : "Search by city, country, or time zone.")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .frame(maxWidth: .infinity)
                .frame(height: isEmpty ? 84 : resultsHeight)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(Array(cities.enumerated()), id: \.element.id) { index, city in
                                resultButton(city, selected: index == selection)
                                    .id(city.id)
                            }
                        }
                        .padding(6)
                    }
                    .frame(height: resultsHeight)
                    .onChange(of: selection) { _, index in
                        if cities.indices.contains(index) {
                            proxy.scrollTo(cities[index].id)
                        }
                    }
                }
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    private func resultButton(_ city: CityClock, selected: Bool) -> some View {
        let saved = isSaved(city)
        let foreground = selected ? Color(nsColor: .alternateSelectedControlTextColor) : .primary
        return Button {
            selectCity(city)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(city.fullName)
                        .font(.body.weight(.medium))
                    Text(city.timeZoneID.replacingOccurrences(of: "_", with: " "))
                        .font(.caption)
                        .foregroundStyle(selected ? foreground : .secondary)
                }
                .lineLimit(1)
                Spacer()
                Image(systemName: saved ? "checkmark" : (selected ? "return" : "plus"))
                    .font(.callout)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(selected ? Color(nsColor: .selectedContentBackgroundColor) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(saved ? "\(city.fullName), already added" : "Add \(city.fullName)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .disabled(saved)
    }

    private func isSaved(_ city: CityClock) -> Bool {
        model.settings.clocks.contains {
            $0.id == city.id || ($0.timeZoneID == city.timeZoneID &&
                ($0.name.localizedCaseInsensitiveCompare(city.name) == .orderedSame ||
                 $0.fullName.localizedCaseInsensitiveCompare(city.fullName) == .orderedSame))
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !cities.isEmpty else { return }
        selection = min(max(selection + delta, 0), cities.count - 1)
    }

    private func addSelection() {
        if pending && !isEmpty {
            submittedQuery = query
            return
        }
        guard cities.indices.contains(selection) else { return }
        selectCity(cities[selection])
    }

    private func selectCity(_ city: CityClock) {
        guard model.isAddingCity, !isSaved(city) else { return }
        add(city)
    }

    private func updateQuery(_ input: String) {
        guard query != input else { return }
        searchTask?.cancel()
        query = input
        selection = 0
        if submittedQuery != input { submittedQuery = nil }
        guard !isEmpty else { result = (input, []); return }
        searchTask = Task { await search(input) }
    }

    private func search(_ input: String) async {
        do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
        let found = await Task.detached(priority: .userInitiated) { CityCatalog.search(input) }.value
        guard !Task.isCancelled, query == input else { return }
        result = (input, found)
        if submittedQuery == input {
            submittedQuery = nil
            addSelection()
        }
    }
}

// Keep text selection, the clear button, and input methods native while routing
// the field editor’s arrow keys and Return to the search results.
private struct CitySearchField: NSViewRepresentable {
    @Binding var query: String
    let move: (Int) -> Void
    let submit: () -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "City or time zone"
        field.setAccessibilityLabel("Search cities and time zones")
        field.delegate = context.coordinator
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.field = self
        if field.stringValue != query { field.stringValue = query }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var field: CitySearchField
        init(_ field: CitySearchField) { self.field = field }

        func controlTextDidChange(_ notification: Notification) {
            if let search = notification.object as? NSSearchField { field.query = search.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch selector {
            case #selector(NSResponder.moveUp(_:)): field.move(-1)
            case #selector(NSResponder.moveDown(_:)): field.move(1)
            case #selector(NSResponder.insertNewline(_:)): field.submit()
            case #selector(NSResponder.cancelOperation(_:)): field.cancel()
            default: return false
            }
            return true
        }
    }
}
