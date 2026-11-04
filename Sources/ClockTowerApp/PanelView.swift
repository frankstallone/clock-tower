import AppKit
import ClockTowerCore
import SwiftUI

@MainActor
struct PanelView: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void

    @State private var addedClock: UUID?
    @State private var listHeight: CGFloat = 120
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if model.isAddingCity {
                CitySearchView(model: model, cancel: { model.isAddingCity = false }) { city in
                    model.settings.clocks.append(city)
                    addedClock = city.id
                    model.isAddingCity = false
                }
            } else {
                header
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        ClockListView(model: model, addCity: showSearch, revealEditor: { id in
                            proxy.scrollTo(id, anchor: .bottom)
                        })
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                    }
                    .frame(height: min(ceil(listHeight), 330))
                    .onAppear {
                        if let addedClock {
                            proxy.scrollTo(addedClock, anchor: .bottom)
                            self.addedClock = nil
                        }
                    }
                }
                if !model.settings.clocks.isEmpty {
                    Divider()
                    TimeComparisonView(model: model)
                }
            }
            if let message = model.message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .allowsWindowActivationEvents()
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: model.settings.collapsed)

    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("World Clocks")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(model.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: showSearch) {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add City")
            .help("Add a city (⌘N)")
            PanelMenuButton(title: "Clock Tower Options", symbol: "ellipsis.circle") {
                Button("Settings…", action: openSettings)
                Link("View Releases", destination: URL(string: "https://github.com/frankstallone/clock-tower/releases/latest")!)
                Divider()
                Button("Quit Clock Tower") { NSApp.terminate(nil) }
            }
            .frame(width: 28, height: 28)
            .help("Clock Tower options")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func showSearch() {
        model.preview = nil
        model.isAddingCity = true
    }
}

@MainActor
private struct TimeComparisonView: View {
    @ObservedObject var model: AppModel

    private var date: Date { model.preview ?? model.now }
    private func localTime(_ date: Date) -> String {
        ClockTime.text(date, zone: TimeZone.current.identifier, use24Hour: model.settings.use24Hour)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    model.settings.collapsed.toggle()
                    model.preview = nil
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: model.settings.collapsed ? "chevron.right" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Text("Compare Times")
                            .font(.headline)
                    }
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(model.settings.collapsed ? "Collapsed" : "Expanded")
                .help(model.settings.collapsed ? "Show time slider" : "Hide time slider")
                Spacer()
                if model.preview != nil {
                    Button("Now") { model.preview = nil }
                        .controlSize(.small)
                        .accessibilityLabel("Return to current time")
                }
                Text(localTime(date))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(model.preview == nil ? .secondary : .primary)
                    .accessibilityLabel("Local time, " + localTime(date))
            }
            if !model.settings.collapsed {
                let range = ClockTime.previewRange(for: model.now)
                Slider(value: Binding(
                    get: { min(ClockTime.minute(of: date), range.upperBound) },
                    set: { model.preview = ClockTime.preview(on: model.now, minute: $0) }
                ), in: range) { editing in
                    if !editing { model.preview = nil }
                }
                .accessibilityLabel("Compare times across your local day")
                .accessibilityValue(localTime(date))
                .accessibilityAdjustableAction { direction in
                    let step: Double
                    switch direction {
                    case .increment: step = 1
                    case .decrement: step = -1
                    @unknown default: return
                    }
                    model.preview = ClockTime.preview(on: model.now, minute: ClockTime.minute(of: date) + step)
                }
                .help("Drag to compare city times. Release to return to now.")
                HStack {
                    Text(localTime(ClockTime.preview(on: model.now, minute: range.lowerBound)))
                    Spacer()
                    Text(model.preview == nil ? "Local time" : "Local time preview")
                    Spacer()
                    Text(localTime(ClockTime.preview(on: model.now, minute: range.upperBound)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
