import AppKit
import Carbon
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var assistantWindow: AssistantPanel?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private let assistantViewModel = AssistantViewModel()
    private let hotKeyService = HotKeyService.shared
    private let updateService: UpdateServicing = GitHubUpdateService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupHotKey()
        Task {
            await assistantViewModel.refreshModelsFromOpenRouter()
        }
        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.async { [weak self] in
                self?.showSettings()
            }
        } else if !UserDefaults.standard.bool(forKey: Constants.onboardingCompletedDefaultsKey) {
            DispatchQueue.main.async { [weak self] in
                self?.showOnboarding()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: AppSettings.didChangeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyService.stop()
    }

    @objc private func showAssistantFromMenu() {
        showAssistant()
    }

    @objc private func toggleAssistant() {
        if let assistantWindow, assistantWindow.isVisible {
            assistantWindow.orderOut(nil)
        } else {
            showAssistant()
        }
    }

    @objc private func showSettingsFromMenu() {
        showSettings()
    }

    @objc private func showOnboardingFromMenu() {
        showOnboarding()
    }

    @objc private func checkForUpdatesFromMenu() {
        Task {
            await checkForUpdates()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func settingsDidChange() {
        assistantViewModel.reloadPreferences()
        setupHotKey()
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: Constants.appName)
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Assistant", action: #selector(showAssistantFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdatesFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Welcome Guide", action: #selector(showOnboardingFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(showSettingsFromMenu), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func setupHotKey() {
        hotKeyService.onHotKey = { [weak self] in
            self?.toggleAssistant()
        }

        do {
            try hotKeyService.start(with: AppSettings.load().shortcut)
        } catch {
            presentHotKeyError(error)
        }
    }

    private func showAssistant() {
        let window = assistantWindow ?? makeAssistantWindow()
        assistantWindow = window
        center(window: window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeAssistantWindow() -> AssistantPanel {
        let contentView = AssistantWindowView(
            viewModel: assistantViewModel,
            onOpenSettings: { [weak self] in
                self?.showSettings()
            },
            onClose: { [weak self] in
                self?.assistantWindow?.orderOut(nil)
            }
        )

        let panel = AssistantPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: contentView)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.onEscape = { [weak panel] in
            panel?.orderOut(nil)
        }

        return panel
    }

    private func showSettings() {
        if let settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(Constants.appName) Settings"
        let hostingView = NSHostingView(rootView: SettingsView().frame(width: 700, height: 760))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 13.0, *) {
            hostingView.sizingOptions = []
        }
        let containerView = NSView()
        window.contentView = containerView
        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        window.minSize = NSSize(width: 700, height: 640)
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func showOnboarding() {
        if let onboardingWindow {
            NSApp.activate(ignoringOtherApps: true)
            onboardingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let view = OnboardingView(
            onOpenSettings: { [weak self] in
                UserDefaults.standard.set(true, forKey: Constants.onboardingCompletedDefaultsKey)
                self?.onboardingWindow?.orderOut(nil)
                self?.showSettings()
            },
            onContinue: { [weak self] in
                UserDefaults.standard.set(true, forKey: Constants.onboardingCompletedDefaultsKey)
                self?.onboardingWindow?.orderOut(nil)
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to \(Constants.appName)"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func checkForUpdates() async {
        do {
            let release = try await updateService.latestRelease()
            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let hasUpdate = GitHubUpdateService.isRelease(release.tagName, newerThan: currentVersion)

            let alert = NSAlert()
            alert.messageText = hasUpdate ? "CommandNest update available" : "CommandNest is up to date"
            alert.informativeText = hasUpdate
                ? "\(release.name) is available. The release page includes the app zip and checksum."
                : "You are running \(Constants.appName) \(currentVersion). Latest release: \(release.tagName)."
            alert.alertStyle = hasUpdate ? .informational : .informational
            alert.addButton(withTitle: hasUpdate ? "Open Release" : "OK")
            if hasUpdate {
                alert.addButton(withTitle: "Cancel")
            }

            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn, hasUpdate {
                NSWorkspace.shared.open(release.pageURL)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not check for updates"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func center(window: NSWindow) {
        let screen = NSScreen.screens.first { screen in
            NSMouseInRect(NSEvent.mouseLocation, screen.frame, false)
        } ?? NSScreen.main

        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }

        let width = min(760, visibleFrame.width - 48)
        let height = min(600, visibleFrame.height - 48)
        let origin = NSPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2
        )
        window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    }

    private func presentHotKeyError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Global shortcut unavailable"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            showSettings()
        }
    }
}

final class AssistantPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onEscape?()
            return
        }

        super.keyDown(with: event)
    }
}
