import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = SettingsStore()
    private let displayController = DisplayController()
    private lazy var engine = AdaptiveEngine(settings: settings, displayController: displayController)
    private var preferences: PreferencesWindowController?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables = Set<AnyCancellable>()
    private var statusMenuItem: NSMenuItem?
    private var globalSliderView: BrightnessSliderView?
    private var displaySliderViews: [CGDirectDisplayID: BrightnessSliderView] = [:]
    private var statusBrightnessPercent: Int?
    private var displayRecoveryTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.image = BrightnessEyeIcon.image(brightness: 1)
            button.imagePosition = .imageLeading
            button.title = " Nuni"
        }

        let menu = NSMenu()
        menu.minimumWidth = 330
        menu.delegate = self
        statusItem.menu = menu

        engine.$statusText
            .sink { [weak self] statusText in self?.refreshStatusText(statusText) }
            .store(in: &cancellables)
        displayController.$lastAppliedBrightness
            .sink { [weak self] brightness in
                self?.updateStatusTitle(brightness: brightness)
                self?.globalSliderView?.setValue(brightness, unlessTracking: true)
            }
            .store(in: &cancellables)
        displayController.$appliedBrightnessByDisplay
            .dropFirst()
            .sink { [weak self] appliedBrightnessByDisplay in
                self?.refreshSliderValues(appliedBrightnessByDisplay: appliedBrightnessByDisplay)
            }
            .store(in: &cancellables)
        displayController.$controlMethods
            .sink { [weak self] controlMethods in self?.refreshControlMethods(controlMethods) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleDisplayRecovery() }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.scheduleDisplayRecovery() }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in self?.scheduleDisplayRecovery() }
            .store(in: &cancellables)

        engine.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        displayRecoveryTask?.cancel()
        engine.stop()
        displayController.restoreSoftwareAdjustments()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        displayController.refreshDisplays()
        engine.applyNow()
        rebuildMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        statusMenuItem = nil
        globalSliderView = nil
        displaySliderViews.removeAll(keepingCapacity: true)
        menu.removeAllItems()
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        statusMenuItem = nil
        globalSliderView = nil
        displaySliderViews.removeAll()
        menu.removeAllItems()

        let title = NSMenuItem(title: "Nuni", action: nil, keyEquivalent: "")
        title.attributedTitle = NSAttributedString(
            string: "Nuni",
            attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)]
        )
        title.isEnabled = false
        menu.addItem(title)

        let status = NSMenuItem(title: engine.statusText, action: nil, keyEquivalent: "")
        status.attributedTitle = NSAttributedString(
            string: engine.statusText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        status.isEnabled = false
        menu.addItem(status)
        statusMenuItem = status
        menu.addItem(.separator())

        addSectionHeader("ALL DISPLAYS", to: menu)
        let globalSlider = BrightnessSliderView(frame: NSRect(x: 0, y: 0, width: 330, height: 68))
        globalSlider.configure(
            title: "All displays",
            subtitle: settings.mode == .manual ? "Global brightness" : "Adjusting switches to Manual mode",
            symbolName: "display.2"
        )
        globalSlider.setRange(minimum: settings.boundedMinimumBrightness)
        globalSlider.setValue(displayController.lastAppliedBrightness)
        globalSlider.onChange = { [weak self] value in self?.engine.setGlobalBrightness(value) }
        globalSlider.onTrackingEnded = { [weak self] in self?.refreshSliderValues() }
        globalSliderView = globalSlider
        let globalItem = NSMenuItem()
        globalItem.view = globalSlider
        menu.addItem(globalItem)

        let modeItem = NSMenuItem(title: "Mode: \(settings.mode.title)", action: nil, keyEquivalent: "")
        modeItem.image = NSImage(systemSymbolName: settings.mode.symbolName, accessibilityDescription: nil)
        let modeMenu = NSMenu(title: "Adaptive Mode")
        for mode in AdaptiveModeKind.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: mode.title)
            item.representedObject = mode.rawValue
            item.state = settings.mode == mode ? .on : .off
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let presets = NSMenuItem(title: "Quick brightness", action: nil, keyEquivalent: "")
        presets.image = NSImage(systemSymbolName: "dial.medium", accessibilityDescription: nil)
        let presetsMenu = NSMenu(title: "Quick brightness")
        for percentage in [25, 50, 75, 100] {
            let item = NSMenuItem(title: "\(percentage)%", action: #selector(setPreset(_:)), keyEquivalent: "")
            item.target = self
            item.tag = percentage
            presetsMenu.addItem(item)
        }
        presets.submenu = presetsMenu
        menu.addItem(presets)

        menu.addItem(.separator())
        addSectionHeader("INDIVIDUAL DISPLAYS", to: menu)
        if displayController.displays.isEmpty {
            let noDisplays = NSMenuItem(title: "No displays found", action: nil, keyEquivalent: "")
            noDisplays.isEnabled = false
            menu.addItem(noDisplays)
        } else {
            for display in displayController.displays {
                let method = displayController.controlMethods[display.id] ?? "Detecting control…"
                let brightness =
                    displayController.appliedBrightnessByDisplay[display.id]
                    ?? settings.effectiveBrightness(base: displayController.lastAppliedBrightness, displayKey: display.persistentKey)
                let slider = BrightnessSliderView(frame: NSRect(x: 0, y: 0, width: 330, height: 68))
                slider.configure(
                    title: display.name,
                    subtitle: method,
                    symbolName: display.isBuiltin ? "laptopcomputer" : "display"
                )
                slider.setRange(minimum: settings.boundedMinimumBrightness)
                slider.setValue(brightness)
                slider.onChange = { [weak self] value in self?.engine.setBrightness(value, for: display) }
                slider.onTrackingEnded = { [weak self] in self?.refreshSliderValues() }
                displaySliderViews[display.id] = slider
                let item = NSMenuItem()
                item.view = slider
                menu.addItem(item)
            }

            let matchItem = NSMenuItem(title: "Match all displays", action: #selector(matchAllDisplays), keyEquivalent: "")
            matchItem.target = self
            matchItem.image = NSImage(systemSymbolName: "equal.circle", accessibilityDescription: nil)
            matchItem.isEnabled = !settings.displayAdjustments.isEmpty
            menu.addItem(matchItem)
        }

        menu.addItem(.separator())
        let githubItem = NSMenuItem(title: "Nuni on GitHub", action: #selector(openGitHub), keyEquivalent: "")
        githubItem.target = self
        githubItem.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        menu.addItem(githubItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let quit = NSMenuItem(title: "Quit Nuni", action: #selector(quitApplication), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func refreshStatusText(_ statusText: String? = nil) {
        guard let statusMenuItem else { return }
        let statusText = statusText ?? engine.statusText
        statusMenuItem.attributedTitle = NSAttributedString(
            string: statusText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
    }

    private func refreshSliderValues(
        appliedBrightnessByDisplay updatedBrightness: [CGDirectDisplayID: Double]? = nil
    ) {
        let appliedBrightnessByDisplay = updatedBrightness ?? displayController.appliedBrightnessByDisplay
        globalSliderView?.setValue(displayController.lastAppliedBrightness, unlessTracking: true)
        for display in displayController.displays {
            guard let slider = displaySliderViews[display.id] else { continue }
            let brightness =
                appliedBrightnessByDisplay[display.id]
                ?? settings.effectiveBrightness(
                    base: displayController.lastAppliedBrightness,
                    displayKey: display.persistentKey
                )
            slider.setValue(brightness, unlessTracking: true)
        }
    }

    private func refreshControlMethods(_ updatedControlMethods: [CGDirectDisplayID: String]? = nil) {
        let controlMethods = updatedControlMethods ?? displayController.controlMethods
        for display in displayController.displays {
            guard let slider = displaySliderViews[display.id] else { continue }
            slider.configure(
                title: display.name,
                subtitle: controlMethods[display.id] ?? "Detecting control…",
                symbolName: display.isBuiltin ? "laptopcomputer" : "display"
            )
        }
    }

    private func addSectionHeader(_ text: String, to menu: NSMenu) {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .kern: 0.4,
            ]
        )
        item.isEnabled = false
        menu.addItem(item)
    }

    private func scheduleDisplayRecovery() {
        displayRecoveryTask?.cancel()
        displayRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for delay in [UInt64(0), 600_000_000, 1_500_000_000] {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard !Task.isCancelled else { return }
                self.displayController.refreshDisplays()
                self.engine.applyNow()
            }
            self.displayRecoveryTask = nil
        }
    }

    private func updateStatusTitle(brightness updatedBrightness: Double? = nil) {
        guard let button = statusItem.button else { return }
        // Keep the menu bar percentage aligned with the "All displays" control.
        // Per-display adjustments are shown beside each display instead.
        let brightness = updatedBrightness ?? displayController.lastAppliedBrightness
        let boundedBrightness = AdaptiveMath.clamp(brightness)
        let percent = Int((boundedBrightness * 100).rounded())
        guard percent != statusBrightnessPercent else { return }
        statusBrightnessPercent = percent
        button.image = BrightnessEyeIcon.image(brightness: boundedBrightness)
        button.title = " \(percent)%"
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let mode = AdaptiveModeKind(rawValue: rawValue) else { return }
        settings.mode = mode
        engine.applyNow()
    }

    @objc private func setPreset(_ sender: NSMenuItem) {
        engine.setGlobalBrightness(Double(sender.tag) / 100)
    }

    @objc private func matchAllDisplays() {
        engine.matchAllDisplays()
        refreshSliderValues()
    }

    @objc private func showSettings() {
        if preferences == nil {
            preferences = PreferencesWindowController(
                settings: settings,
                displayController: displayController,
                onGlobalBrightnessChange: { [weak self] value in self?.engine.setGlobalBrightness(value) },
                onDisplayBrightnessChange: { [weak self] display, value in
                    self?.engine.setBrightness(value, for: display)
                },
                onDisplayReset: { [weak self] display in self?.engine.resetBrightness(for: display) },
                onMatchDisplays: { [weak self] in self?.engine.matchAllDisplays() },
                onClose: { [weak self] in self?.preferences = nil }
            )
        }
        NSApp.setActivationPolicy(.regular)
        preferences?.showWindow(nil)
        preferences?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(AppInformation.repositoryURL)
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}
