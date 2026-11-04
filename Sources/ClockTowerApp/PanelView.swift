import AppKit
import ClockTowerCore
import SwiftUI

/// A native, deliberately quiet replacement for Hovrly's web panel.
/// Clocks remain visible when controls collapse. Row actions use native menus,
/// search offers several keyboard-selectable matches, and scrolling bounds the
/// panel on laptop screens. Settings use system controls and follow appearance.
@MainActor
struct PanelView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var submittedQuery: String?
    @State private var searchResult: (query: String, cities: [CityClock]) = ("", [])
    @State private var selectedResult = 0
    @State private var renamingID: UUID?
    @State private var draftName = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case search
        case rename
    }

    private var displayedDate: Date { model.preview ?? model.now }
    private var searchPending: Bool { isSearching && searchResult.query != query }
    private var results: [CityClock] {
        guard searchResult.query == query else { return [] }
        return Array(searchResult.cities.filter { !contains($0) }.prefix(8))
    }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var rowHeight: CGFloat { model.settings.compact ? 42 : 60 }
    private var contentHeight: CGFloat {
        let clockHeight = max(70, CGFloat(model.settings.clocks.count) * rowHeight)
        let renameHeight: CGFloat = renamingID == nil ? 0 : 70
        let issueHeight: CGFloat = model.message == nil ? 0 : 62
        if model.settings.collapsed { return min(420, clockHeight + renameHeight + issueHeight + 24) }
        let resultHeight: CGFloat = isSearching ? max(40, CGFloat(results.count) * 43) + 22 : 0
        return min(540, clockHeight + renameHeight + issueHeight + resultHeight + 334)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        clocks
                        if let message = model.message {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .accessibilityLabel("Notice. \(message)")
                        }
                        if !model.settings.collapsed {
                            Divider().padding(.horizontal, 14)
                            search
                            Divider().padding(.horizontal, 14)
                            preview
                            Divider().padding(.horizontal, 14)
                            preferences
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onChange(of: selectedResult) { _, _ in
                    if results.indices.contains(selectedResult) {
                        proxy.scrollTo(results[selectedResult].id, anchor: .center)
                    }
                }
            }
            .frame(height: contentHeight)
            Divider()
            footer
        }
        .frame(width: 400)
        .background(.regularMaterial)
        .onChange(of: query) { _, _ in
            if submittedQuery != query { submittedQuery = nil }
            selectedResult = 0
        }
        .task(id: query) { [query] in await searchCities(query) }
        .onDisappear { model.preview = nil }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Clock Tower")
                .font(.headline)
            Spacer()
            if model.preview != nil {
                Text("Preview")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Button {
                model.settings.collapsed.toggle()
                if model.settings.collapsed {
                    model.preview = nil
                    focusedField = nil
                }
            } label: {
                Image(systemName: model.settings.collapsed ? "chevron.down" : "chevron.up")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(model.settings.collapsed ? "Show controls" : "Hide controls")
            .help(model.settings.collapsed ? "Show search, time preview, and settings" : "Hide controls and keep clocks visible")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var clocks: some View {
        if model.settings.clocks.isEmpty {
            VStack(spacing: 8) {
                Text("Your world, at a glance")
                    .font(.headline)
                Text("Add a city below. Pin a clock to show it in the menu bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if model.settings.collapsed {
                    Button("Add a city") {
                        model.settings.collapsed = false
                        focusedField = .search
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
        } else {
            VStack(spacing: 0) {
                ForEach(model.settings.clocks) { clock in
                    clockRow(clock)
                    if renamingID == clock.id { renameEditor(clock) }
                }
            }
        }
    }

    private func clockRow(_ clock: CityClock) -> some View {
        let isDay = ClockTime.isDay(displayedDate, zone: clock.timeZoneID)
        return HStack(spacing: 10) {
            Image(systemName: isDay ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 15))
                .foregroundStyle(isDay ? Color.orange : Color.secondary)
                .frame(width: 18)
                .accessibilityLabel(isDay ? "Daytime" : "Nighttime")
            VStack(alignment: .leading, spacing: 3) {
                Text(clock.fullName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .help(clock.fullName)
                if !model.settings.compact {
                    Text(cityDetail(clock))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(ClockTime.text(displayedDate, zone: clock.timeZoneID, use24Hour: model.settings.use24Hour))
                    .font(.system(size: model.settings.compact ? 15 : 19, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .fixedSize()
                if model.settings.showDate && !model.settings.compact {
                    Text(cityDate(clock))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Button {
                updateClock(clock.id) { $0.isPinned.toggle() }
            } label: {
                Image(systemName: clock.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(clock.isPinned ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(clock.isPinned ? "Unpin" : "Pin") \(clock.fullName) \(clock.isPinned ? "from" : "to") menu bar")
            .help(clock.isPinned ? "Remove from menu bar" : "Show in menu bar")
            Menu {
                Button("Rename…") { beginRename(clock) }
                Divider()
                Button("Move Up") { move(clock.id, by: -1) }
                    .disabled(model.settings.clocks.first?.id == clock.id)
                Button("Move Down") { move(clock.id, by: 1) }
                    .disabled(model.settings.clocks.last?.id == clock.id)
                Divider()
                Button("Remove Clock", role: .destructive) {
                    model.settings.clocks.removeAll { $0.id == clock.id }
                    if renamingID == clock.id { renamingID = nil }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 22, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Actions for \(clock.fullName)")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: rowHeight)
        .accessibilityElement(children: .contain)
    }

    private func renameEditor(_ clock: CityClock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Clock name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .rename)
                .onSubmit { saveRename(clock.id) }
                .onExitCommand { cancelRename() }
            HStack {
                Text("Used in the panel and menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { cancelRename() }
                Button("Save") { saveRename(clock.id) }
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var search: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Add a city or time zone", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .search)
                    .accessibilityLabel("Search cities and time zones")
                    .onSubmit { addSelectedResult() }
                    .onMoveCommand { direction in
                        guard !results.isEmpty else { return }
                        switch direction {
                        case .down: selectedResult = min(selectedResult + 1, results.count - 1)
                        case .up: selectedResult = max(selectedResult - 1, 0)
                        default: break
                        }
                    }
                    .onExitCommand { query = "" }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(9)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            if isSearching {
                if results.isEmpty {
                    Text(searchPending ? "Searching cities…" : "No matching cities. Try a city, country, or time zone.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, city in
                            Button { add(city) } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(city.fullName)
                                            .font(.system(size: 13, weight: .medium))
                                            .lineLimit(1)
                                        Text(city.timeZoneID.replacingOccurrences(of: "_", with: " "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: index == selectedResult ? "return" : "plus")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                                .background(index == selectedResult ? Color.accentColor.opacity(0.12) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                            .id(city.id)
                            .accessibilityLabel("Add \(city.fullName), \(city.timeZoneID)")
                            .accessibilityAddTraits(index == selectedResult ? .isSelected : [])
                        }
                    }
                    Text("↑ ↓ to choose · Return to add · Search works offline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
    }

    private var preview: some View {
        let range = ClockTime.previewRange(for: model.now)
        let localZone = TimeZone.current.identifier
        return VStack(spacing: 7) {
            HStack {
                Text("Time preview")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(ClockTime.text(displayedDate, zone: localZone, use24Hour: model.settings.use24Hour))
                    .font(.system(size: 12))
                    .monospacedDigit()
                Button("Now") { model.preview = nil }
                    .controlSize(.mini)
                    .disabled(model.preview == nil)
                    .accessibilityLabel("Return to current time")
            }
            Slider(value: Binding(
                get: { min(max(ClockTime.minute(of: displayedDate), range.lowerBound), range.upperBound) },
                set: { model.preview = ClockTime.preview(on: model.now, minute: $0) }
            ), in: range, step: 1) { editing in
                if !editing { model.preview = nil }
            }
            .accessibilityAdjustableAction { direction in
                let move: Double
                switch direction {
                case .increment: move = 1
                case .decrement: move = -1
                @unknown default: return
                }
                model.preview = ClockTime.preview(on: model.now, minute: ClockTime.minute(of: displayedDate) + move)
            }
            .accessibilityLabel("Preview times across your local day")
            .accessibilityValue(ClockTime.text(displayedDate, zone: localZone, use24Hour: model.settings.use24Hour))
            HStack {
                Text(ClockTime.text(ClockTime.preview(on: model.now, minute: range.lowerBound), zone: localZone, use24Hour: model.settings.use24Hour))
                Spacer()
                Text(TimeZone.current.abbreviation(for: displayedDate) ?? "Local time")
                Spacer()
                Text(ClockTime.text(ClockTime.preview(on: model.now, minute: range.upperBound), zone: localZone, use24Hour: model.settings.use24Hour))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("Drag to compare. Release to return to now.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
    }

    private func preference(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(title).frame(maxWidth: .infinity, alignment: .leading) }
    }

    private var preferences: some View {
        VStack(spacing: 10) {
            preference("24-hour time", isOn: $model.settings.use24Hour)
            preference("Compact view", isOn: $model.settings.compact)
            preference("Show date", isOn: $model.settings.showDate)
            preference("Open at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
            if model.loginNeedsApproval {
                HStack(alignment: .firstTextBaseline) {
                    Text("Allow Clock Tower in Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings…") { model.openLoginSettings() }
                        .controlSize(.small)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 12))
        .padding(14)
    }

    private var footer: some View {
        HStack {
            Link(destination: URL(string: "https://github.com/frankstallone/clock-tower/releases/latest")!) {
                Label("View Releases", systemImage: "arrow.up.right.square")
            }
            .help("Open the latest release in your browser for manual updates")
            Spacer()
            Button("Quit Clock Tower") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .buttonStyle(.borderless)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func cityDetail(_ clock: CityClock) -> String {
        let abbreviation = TimeZone(identifier: clock.timeZoneID)?.abbreviation(for: displayedDate) ?? clock.timeZoneID
        let difference = (TimeZone(identifier: clock.timeZoneID)?.secondsFromGMT(for: displayedDate) ?? 0)
            - TimeZone.current.secondsFromGMT(for: displayedDate)
        guard difference != 0 else { return "\(abbreviation) · Same as local time" }
        let hours = abs(difference) / 3_600
        let minutes = abs(difference) % 3_600 / 60
        let amount = minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        return "\(abbreviation) · \(amount) \(difference > 0 ? "ahead" : "behind")"
    }

    private func cityDate(_ clock: CityClock) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: clock.timeZoneID)
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter.string(from: displayedDate)
    }

    private func updateClock(_ id: UUID, change: (inout CityClock) -> Void) {
        guard let index = model.settings.clocks.firstIndex(where: { $0.id == id }) else { return }
        change(&model.settings.clocks[index])
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = model.settings.clocks.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard model.settings.clocks.indices.contains(destination) else { return }
        model.settings.clocks.swapAt(index, destination)
    }

    private func beginRename(_ clock: CityClock) {
        draftName = clock.fullName
        renamingID = clock.id
        focusedField = .rename
    }

    private func saveRename(_ id: UUID) {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        updateClock(id) {
            $0.name = name
            $0.fullName = name
        }
        cancelRename()
    }

    private func cancelRename() {
        renamingID = nil
        draftName = ""
        focusedField = nil
    }

    private func searchCities(_ searchQuery: String) async {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResult = (searchQuery, [])
            return
        }
        // Loading and scanning the offline catalog must never block typing.
        do { try await Task.sleep(nanoseconds: 80_000_000) }
        catch { return }
        let found = await Task.detached(priority: .userInitiated) {
            CityCatalog.search(searchQuery, limit: 16)
        }.value
        guard !Task.isCancelled, query == searchQuery else { return }
        searchResult = (searchQuery, found)
        if submittedQuery == searchQuery {
            submittedQuery = nil
            if let first = results.first { add(first) }
        }
    }

    private func contains(_ candidate: CityClock) -> Bool {
        model.settings.clocks.contains {
            $0.id == candidate.id ||
            ($0.timeZoneID == candidate.timeZoneID &&
             ($0.name.localizedCaseInsensitiveCompare(candidate.name) == .orderedSame ||
              $0.fullName.localizedCaseInsensitiveCompare(candidate.fullName) == .orderedSame))
        }
    }

    private func addSelectedResult() {
        if searchPending && isSearching {
            submittedQuery = query
            return
        }
        guard results.indices.contains(selectedResult) else { return }
        add(results[selectedResult])
    }

    private func add(_ city: CityClock) {
        guard !contains(city) else { return }
        model.settings.clocks.append(city)
        query = ""
        focusedField = .search
    }
}
