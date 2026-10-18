import AppKit
import SwiftUI

private struct PreferenceCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
            )
    }
}

private struct StableBrightnessSlider: View {
    let value: Double
    var minimumValue = 0.0
    var maximumValue = 1.0
    let onChange: (Double) -> Void

    @State private var dragValue: Double?

    private var displayedValue: Double {
        min(maximumValue, max(minimumValue, dragValue ?? value))
    }

    private var progress: Double {
        let range = max(0.001, maximumValue - minimumValue)
        return (displayedValue - minimumValue) / range
    }

    var body: some View {
        GeometryReader { geometry in
            let knobSize = 18.0
            let travel = max(0, geometry.size.width - knobSize)
            let knobCenter = (knobSize / 2) + (travel * progress)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .quaternaryLabelColor))
                    .frame(height: 6)
                    .padding(.horizontal, knobSize / 2)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: knobCenter, height: 6)

                Circle()
                    .fill(Color(nsColor: .controlAccentColor))
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: travel * progress)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { gesture in
                        updateValue(for: gesture.location.x, width: geometry.size.width)
                    }
                    .onEnded { gesture in
                        updateValue(for: gesture.location.x, width: geometry.size.width)
                        DispatchQueue.main.async { dragValue = nil }
                    }
            )
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue(Text(displayedValue, format: .percent.precision(.fractionLength(0))))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.05 : -0.05
            commit(displayedValue + step)
            DispatchQueue.main.async { dragValue = nil }
        }
    }

    private func updateValue(for x: CGFloat, width: CGFloat) {
        let knobSize = 18.0
        let travel = max(1, width - knobSize)
        let progress = min(1, max(0, (x - (knobSize / 2)) / travel))
        commit(minimumValue + (progress * (maximumValue - minimumValue)))
    }

    private func commit(_ newValue: Double) {
        let clamped = min(maximumValue, max(minimumValue, newValue))
        dragValue = clamped
        onChange(clamped)
    }
}

struct NuniPreferencesView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var displayController: DisplayController
    @StateObject private var launchAtLogin = LaunchAtLoginManager()

    let onGlobalBrightnessChange: (Double) -> Void
    let onDisplayBrightnessChange: (ManagedDisplay, Double) -> Void
    let onDisplayReset: (ManagedDisplay) -> Void
    let onMatchDisplays: () -> Void

    private var wakeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: settings.wakeMinute / 60, minute: settings.wakeMinute % 60)) ?? Date()
            },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                settings.wakeMinute = (parts.hour ?? 8) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private var sleepBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: settings.sleepMinute / 60, minute: settings.sleepMinute % 60)) ?? Date()
            },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                settings.sleepMinute = (parts.hour ?? 20) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private func actualBrightness(for display: ManagedDisplay) -> Double {
        displayController.appliedBrightnessByDisplay[display.id]
            ?? settings.effectiveBrightness(
                base: displayController.lastAppliedBrightness,
                displayKey: display.persistentKey
            )
    }

    var body: some View {
        TabView {
            displaysTab
                .tabItem { Label("Displays", systemImage: "display.2") }

            automationTab
                .tabItem { Label("Automation", systemImage: "wand.and.stars") }

            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding(18)
        .frame(minWidth: 650, idealWidth: 680, minHeight: 560, idealHeight: 610)
    }

    private var displaysTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Display brightness")
                        .font(.title2.weight(.semibold))
                    Text("Adjust everything together, or tune each display independently.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("Saved automatically", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            PreferenceCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("All displays", systemImage: "display.2")
                            .font(.headline)
                        Spacer()
                        Text(displayController.lastAppliedBrightness, format: .percent.precision(.fractionLength(0)))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "sun.min")
                            .foregroundStyle(.secondary)
                        StableBrightnessSlider(
                            value: displayController.lastAppliedBrightness,
                            minimumValue: settings.boundedMinimumBrightness,
                            onChange: onGlobalBrightnessChange
                        )
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.secondary)
                    }
                    Text(
                        settings.mode == .manual
                            ? "Controls the base brightness for every display." : "Changing this control switches to Manual mode."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            PreferenceCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Safety minimum", systemImage: "shield.lefthalf.filled")
                            .font(.headline)
                        Spacer()
                        Text(settings.boundedMinimumBrightness, format: .percent.precision(.fractionLength(0)))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                    }
                    HStack(spacing: 10) {
                        Text("5%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        StableBrightnessSlider(
                            value: settings.boundedMinimumBrightness,
                            minimumValue: 0.05,
                            maximumValue: 0.5,
                            onChange: setSafetyMinimum
                        )
                        Text("50%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Brightness controls and macOS sync cannot go below this level.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Connected displays")
                    .font(.headline)
                Spacer()
                Button("Match all") { onMatchDisplays() }
                    .disabled(settings.displayAdjustments.isEmpty)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if displayController.displays.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "display.trianglebadge.exclamationmark")
                                .font(.system(size: 30))
                                .foregroundStyle(.secondary)
                            Text("No displays found")
                                .font(.headline)
                            Text("Reconnect a display, then reopen this window.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ForEach(displayController.displays, id: \.id) { display in
                            displayCard(display)
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(4)
    }

    private func displayCard(_ display: ManagedDisplay) -> some View {
        let isSyncSource = settings.mode == .sync && display.isBuiltin
        let hasAdjustment = !isSyncSource && abs(settings.displayAdjustments[display.persistentKey] ?? 0) >= 0.005
        let method = displayController.controlMethods[display.id] ?? "Detecting control…"
        let brightness = actualBrightness(for: display)

        return PreferenceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                        .font(.system(size: 20))
                        .frame(width: 28)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(display.name)
                            .font(.headline)
                        Text(method)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isSyncSource || hasAdjustment {
                        Text(isSyncSource ? "Source" : "Custom")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(.tint)
                    }
                    Text(brightness, format: .percent.precision(.fractionLength(0)))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }

                HStack(spacing: 10) {
                    Image(systemName: "sun.min")
                        .foregroundStyle(.secondary)
                    StableBrightnessSlider(
                        value: brightness,
                        minimumValue: settings.boundedMinimumBrightness,
                        onChange: { onDisplayBrightnessChange(display, $0) }
                    )
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(.secondary)
                    Button("Reset") { onDisplayReset(display) }
                        .disabled(!hasAdjustment)
                }
            }
        }
    }

    private var automationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Automatic brightness")
                        .font(.title2.weight(.semibold))
                    Text("Choose what Nuni should follow throughout the day.")
                        .foregroundStyle(.secondary)
                }

                PreferenceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Mode")
                            .font(.headline)
                        Picker("Mode", selection: $settings.mode) {
                            ForEach(AdaptiveModeKind.allCases, id: \.self) { mode in
                                Label(mode.title, systemImage: mode.symbolName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        Label(settings.mode.detail, systemImage: settings.mode.symbolName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if settings.mode != .manual {
                    PreferenceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Adaptive range")
                                .font(.headline)
                            brightnessRangeRow(
                                "Maximum",
                                value: $settings.maximumBrightness,
                                minimum: settings.boundedMinimumBrightness
                            )
                            Text("The minimum is the Safety minimum configured on the Displays tab.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                sourceConfiguration

                PreferenceCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Control")
                            .font(.headline)
                        Toggle("Use macOS hardware brightness when available", isOn: $settings.preferHardware)
                        HStack {
                            Text("Refresh interval")
                            Slider(value: $settings.refreshSeconds, in: 0.5...10, step: 0.5)
                            Text("\(settings.refreshSeconds, specifier: "%.1f") s")
                                .monospacedDigit()
                                .frame(width: 42, alignment: .trailing)
                        }
                        Text(
                            "In Manual and Sync modes, macOS brightness changes update the all-displays level. Unsupported displays use software dimming."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(4)
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("General")
                    .font(.title2.weight(.semibold))
                Text("Choose how Nuni behaves when you use your Mac.")
                    .foregroundStyle(.secondary)
            }

            PreferenceCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "power.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.tint)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Start Nuni at login")
                                .font(.headline)
                            Text("Keep display brightness control ready after signing in.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle(
                            "Start Nuni at login",
                            isOn: Binding(
                                get: { launchAtLogin.isEnabled },
                                set: { launchAtLogin.setEnabled($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    Divider()

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: launchAtLogin.requiresApproval ? "exclamationmark.circle" : "info.circle")
                            .foregroundStyle(launchAtLogin.requiresApproval ? .orange : .secondary)
                        Text(launchAtLogin.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if launchAtLogin.requiresApproval {
                            Button("Open Login Items") {
                                launchAtLogin.openLoginItemsSettings()
                            }
                        }
                    }
                }
            }

            PreferenceCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Nuni")
                                .font(.headline)
                            Text(AppInformation.versionText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text("Open-source display brightness control for macOS.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Link(destination: AppInformation.repositoryURL) {
                            Label("View on GitHub", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Divider()

                    HStack {
                        Label("MIT License", systemImage: "checkmark.seal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Link("github.com/myoh0623/Nuni", destination: AppInformation.repositoryURL)
                            .font(.caption)
                    }
                }
            }

            Text(
                "Nuni uses the macOS login-item service. You can review or remove it at any time in System Settings → General → Login Items."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(4)
        .onAppear { launchAtLogin.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
    }

    @ViewBuilder
    private var sourceConfiguration: some View {
        switch settings.mode {
        case .manual, .sync:
            EmptyView()

        case .sensor:
            PreferenceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ambient sensor")
                        .font(.headline)
                    valueFieldRow("Dark room", value: $settings.minimumLux, unit: "lux")
                    valueFieldRow("Bright room", value: $settings.maximumLux, unit: "lux")
                }
            }

        case .location:
            PreferenceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Location")
                        .font(.headline)
                    valueFieldRow("Latitude", value: $settings.latitude, unit: "°")
                    valueFieldRow("Longitude", value: $settings.longitude, unit: "°")
                }
            }

        case .clock:
            PreferenceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Daily schedule")
                        .font(.headline)
                    HStack(spacing: 20) {
                        DatePicker("Day starts", selection: wakeBinding, displayedComponents: .hourAndMinute)
                        DatePicker("Night starts", selection: sleepBinding, displayedComponents: .hourAndMinute)
                    }
                }
            }
        }
    }

    private func setSafetyMinimum(_ value: Double) {
        settings.minimumBrightness = value
        if settings.maximumBrightness < value {
            settings.maximumBrightness = value
        }
    }

    private func brightnessRangeRow(
        _ title: String,
        value: Binding<Double>,
        minimum: Double = 0,
        maximum: Double = 1
    ) -> some View {
        HStack {
            Text(title)
                .frame(width: 74, alignment: .leading)
            StableBrightnessSlider(
                value: value.wrappedValue,
                minimumValue: minimum,
                maximumValue: maximum,
                onChange: { value.wrappedValue = $0 }
            )
            Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func valueFieldRow(_ title: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
        }
    }
}

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(
        settings: SettingsStore,
        displayController: DisplayController,
        onGlobalBrightnessChange: @escaping (Double) -> Void,
        onDisplayBrightnessChange: @escaping (ManagedDisplay, Double) -> Void,
        onDisplayReset: @escaping (ManagedDisplay) -> Void,
        onMatchDisplays: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        let controller = NSHostingController(
            rootView: NuniPreferencesView(
                settings: settings,
                displayController: displayController,
                onGlobalBrightnessChange: onGlobalBrightnessChange,
                onDisplayBrightnessChange: onDisplayBrightnessChange,
                onDisplayReset: onDisplayReset,
                onMatchDisplays: onMatchDisplays
            )
        )
        let window = NSWindow(contentViewController: controller)
        window.title = "Nuni"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 650, height: 560)
        window.setContentSize(NSSize(width: 680, height: 610))
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        onClose()
    }
}
