import ClockTowerCore
import SwiftUI

/// Saved clocks keep the time column aligned, including cities that share a time.
/// The containing panel owns scrolling so the rename field stays in the same flow.
@MainActor
struct ClockListView: View {
    @ObservedObject var model: AppModel
    let addCity: () -> Void
    let revealEditor: (UUID) -> Void

    @State private var renamingID: UUID?
    @State private var draftName = ""
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var renameFocused: Bool
    @FocusState private var focusedActions: UUID?

    private var displayedDate: Date { model.preview ?? model.now }

    var body: some View {
        VStack(spacing: 0) {
            if model.settings.clocks.isEmpty {
                emptyState
            } else {
                ForEach(model.settings.clocks) { clock in
                    VStack(spacing: 0) {
                        clockRow(clock)
                        if renamingID == clock.id {
                            renameEditor(clock)
                        }
                    }
                    .id(clock.id)
                    if clock.id != model.settings.clocks.last?.id {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.willCloseNotification)) { _ in
            finishRename(restoreFocus: false)
        }
        .onDisappear { finishRename(restoreFocus: false) }
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Text("No clocks yet")
                .font(.headline)
            Text("Add a city, then pin its clock to the menu bar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add a city", systemImage: "plus", action: addCity)
                .controlSize(.regular)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
    }

    private func clockRow(_ clock: CityClock) -> some View {
        let zone = TimeZone(identifier: clock.timeZoneID)!
        let difference = ClockTime.dayDifference(at: displayedDate, in: zone)
        let relativeDay = dayDescription(difference)
        let date = cityDate(zone)
        let abbreviation = zone.abbreviation(for: displayedDate) ?? clock.timeZoneID
        let offset = offsetDescription(zone)
        let detail = model.settings.showDate ? date : (difference == 0 ? nil : relativeDay)
        let time = ClockTime.text(displayedDate, zone: clock.timeZoneID, use24Hour: model.settings.use24Hour)
        let isDay = ClockTime.isDay(displayedDate, zone: clock.timeZoneID)
        return HStack(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                timeColumn(time, isDay: isDay, detail: detail)
                VStack(alignment: .leading, spacing: 4) {
                    Text(clock.fullName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(model.settings.compact ? 1 : 2)
                        .help(clock.fullName)
                    ViewThatFits(in: .horizontal) {
                        Text("\(abbreviation) · \(offset)")
                        Text(offset)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    if model.settings.showDate && difference != 0 {
                        Text(relativeDay)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(clock.fullName), \(time), \(isDay ? "Daytime" : "Nighttime"), \(abbreviation), \(offset) relative to local time, \(relativeDay), \(date)")
            .accessibilityAddTraits(.isStaticText)
            .help("\(clock.fullName)\n\(clock.timeZoneID.replacingOccurrences(of: "_", with: " "))\n\(offset) relative to local time")

            HStack(spacing: 1) {
                Button {
                    updateClock(clock.id) { $0.isPinned.toggle() }
                } label: {
                    Image(systemName: clock.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 12))
                        .foregroundStyle(clock.isPinned ? Color.primary : Color.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(clock.isPinned ? "Unpin" : "Pin") \(clock.fullName) \(clock.isPinned ? "from" : "to") menu bar")
                .help(clock.isPinned ? "Remove from menu bar" : "Show in menu bar")

                PanelMenuButton(title: "Actions for \(clock.fullName)", symbol: "ellipsis") {
                    clockActions(clock)
                }
                .frame(width: 28, height: 28)
                .focused($focusedActions, equals: clock.id)
                .help("Rename, reorder, or remove \(clock.fullName)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, model.settings.compact ? 7 : 12)
        .frame(minHeight: model.settings.compact ? 46 : 64)
        .contentShape(Rectangle())
        .contextMenu { clockActions(clock) }
        .accessibilityElement(children: .contain)
    }

    private func timeColumn(_ time: String, isDay: Bool, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: isDay ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(dayPeriodColor(isDay: isDay))
                    .frame(width: 16, height: 18)
                Text(time)
                    .font(.system(size: model.settings.compact ? 15 : 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .fixedSize()
            }
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: model.settings.use24Hour ? 76 : 102, alignment: .leading)
    }

    private func dayPeriodColor(isDay: Bool) -> Color {
        if colorScheme == .dark {
            return isDay ? Color(red: 0.98, green: 0.76, blue: 0.27)
                : Color(red: 0.65, green: 0.77, blue: 1)
        }
        return isDay ? Color(red: 0.62, green: 0.36, blue: 0)
            : Color(red: 0.25, green: 0.35, blue: 0.68)
    }

    @ViewBuilder
    private func clockActions(_ clock: CityClock) -> some View {
        Button("Rename…") { beginRename(clock) }
        Divider()
        Button("Move Up") { move(clock.id, by: -1) }
            .disabled(model.settings.clocks.first?.id == clock.id)
        Button("Move Down") { move(clock.id, by: 1) }
            .disabled(model.settings.clocks.last?.id == clock.id)
        Divider()
        Button("Remove Clock", role: .destructive) {
            if renamingID == clock.id { cancelRename(restoreFocus: false) }
            model.settings.clocks.removeAll { $0.id == clock.id }
        }
    }

    private func renameEditor(_ clock: CityClock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Clock name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .focused($renameFocused)
                .accessibilityLabel("Name for \(clock.fullName)")
                .onSubmit { finishRename() }
                .onExitCommand { cancelRename() }
            HStack(spacing: 8) {
                Text("Panel and menu bar name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Cancel") { cancelRename() }
                Button("Save") { finishRename() }
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .task(id: clock.id) {
            revealEditor(clock.id)
            await Task.yield()
            renameFocused = true
        }
    }

    private func offsetDescription(_ zone: TimeZone) -> String {
        let difference = zone.secondsFromGMT(for: displayedDate) - TimeZone.current.secondsFromGMT(for: displayedDate)
        guard difference != 0 else { return "Same time" }
        let hours = abs(difference) / 3_600
        let minutes = abs(difference) % 3_600 / 60
        let amount = minutes == 0 ? "\(hours)h" : hours == 0 ? "\(minutes)m" : "\(hours)h \(minutes)m"
        return "\(amount) \(difference > 0 ? "ahead" : "behind")"
    }

    private func dayDescription(_ difference: Int) -> String {
        switch difference {
        case -1: return "Yesterday"
        case 0: return "Today"
        case 1: return "Tomorrow"
        case let days where days < 0: return "\(-days) days earlier"
        case let days: return "\(days) days later"
        }
    }

    private func cityDate(_ zone: TimeZone) -> String {
        var format = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        format.timeZone = zone
        return displayedDate.formatted(format)
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
        finishRename(restoreFocus: false)
        draftName = clock.fullName
        renamingID = clock.id
    }

    private func finishRename(restoreFocus: Bool = true) {
        guard let id = renamingID else { return }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty,
           let clock = model.settings.clocks.first(where: { $0.id == id }),
           name != clock.fullName {
            updateClock(id) {
                $0.name = name
                $0.fullName = name
            }
        }
        cancelRename(restoreFocus: restoreFocus)
    }

    private func cancelRename(restoreFocus: Bool = true) {
        let id = renamingID
        renamingID = nil
        draftName = ""
        renameFocused = false
        if restoreFocus { focusedActions = id }
    }
}
