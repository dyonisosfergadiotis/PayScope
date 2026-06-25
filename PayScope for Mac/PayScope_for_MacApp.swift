import AppKit
import SwiftUI

enum MenuBarActions {
    static func reloadFromICloud() async {
        print("PayScopeMac CloudReload: start")
        do {
            let snapshot = try await CloudKitReadService.shared.fetchSnapshot()
            print("PayScopeMac CloudReload: fetched settings=\(snapshot.settings != nil) entries=\(snapshot.dayEntries.count) netConfigs=\(snapshot.netWageConfigs.count) holidays=\(snapshot.holidays.count)")
            await LocalCloudSnapshotStore.shared.save(snapshot: snapshot)
            await MainActor.run {
                print("PayScopeMac CloudReload: posting success notification")
                NotificationCenter.default.post(name: .menuBarSnapshotDidReload, object: snapshot)
            }
        } catch {
            await MainActor.run {
                print("PayScopeMac CloudReload: failed \(error)")
                NotificationCenter.default.post(name: .menuBarSnapshotReloadFailed, object: error)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var snapshotReloadTimer: Timer?
    private var statusItemDiagnosticsTimer: Timer?
    private var statusItemDiagnosticsTick = 0

    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self

        let reloadItem = NSMenuItem(title: "Reload", action: #selector(reloadFromICloud), keyEquivalent: "")
        reloadItem.target = self
        menu.addItem(reloadItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("PayScopeMac AppDelegate: applicationDidFinishLaunching")
        print("PayScopeMac AppDelegate: pid=\(ProcessInfo.processInfo.processIdentifier) bundleID=\(Bundle.main.bundleIdentifier ?? "<nil>") activationPolicy=\(NSApp.activationPolicy().rawValue)")
        print("PayScopeMac AppDelegate: screens=\(NSScreen.screens.map { "frame=\($0.frame) visible=\($0.visibleFrame)" }.joined(separator: " | "))")
        configurePopover()
        configureStatusItem()
    }

    private func configurePopover() {
        print("PayScopeMac Popover: configure start")
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .environment(\.locale, Locale(identifier: "de_DE"))
        )
        popover.contentSize = NSSize(width: 360, height: 420)
        print("PayScopeMac Popover: configured size=\(popover.contentSize)")
    }

    private func configureStatusItem() {
        print("PayScopeMac StatusItem: configure start")
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else {
            print("PayScopeMac StatusItem: missing button")
            return
        }
        print("PayScopeMac StatusItem: button created frame=\(button.frame)")

        button.toolTip = "PayScope"
        button.imagePosition = .imageLeft
        button.alignment = .center

        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        self.statusItem = statusItem
        applyNativeStatusItem(icon: "clock.badge.checkmark", text: nil, reason: "initial")
        loadCachedSnapshotForStatusItem(reason: "launch")
        snapshotReloadTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.loadCachedSnapshotForStatusItem(reason: "timer")
        }
        statusItemDiagnosticsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.printStatusItemDiagnostics(reason: "timer")
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSnapshotDidReload(_:)),
            name: .menuBarSnapshotDidReload,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSnapshotReloadFailed(_:)),
            name: .menuBarSnapshotReloadFailed,
            object: nil
        )
        print("PayScopeMac StatusItem: configured initialLength=\(statusItem.length)")
        DispatchQueue.main.async { [weak self] in
            self?.printStatusItemDiagnostics(reason: "main-async")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.printStatusItemDiagnostics(reason: "after-0.25s")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.printStatusItemDiagnostics(reason: "after-2s")
        }
    }

    private func loadCachedSnapshotForStatusItem(reason: String) {
        print("PayScopeMac StatusItem: load cached snapshot reason=\(reason)")
        Task {
            let envelope = await LocalCloudSnapshotStore.shared.load()
            await MainActor.run {
                guard let envelope else {
                    print("PayScopeMac StatusItem: no cached snapshot for native button")
                    applyNativeStatusItem(icon: "clock.badge.checkmark", text: nil, reason: "cache-empty")
                    return
                }
                print("PayScopeMac StatusItem: native cache loaded savedAt=\(envelope.savedAt) entries=\(envelope.snapshot.dayEntries.count)")
                applySnapshotToNativeStatusItem(envelope.snapshot, reason: reason)
            }
        }
    }

    private func applySnapshotToNativeStatusItem(_ snapshot: CloudSnapshot, reason: String) {
        let now = Date()
        if let active = snapshot.dayEntries.first(where: { entry in
            guard entry.type == .work || entry.type == .manual else { return false }
            guard let start = entry.shiftStart, let end = entry.shiftEnd, end > start else { return false }
            return now >= start && now < end
        }) {
            applyNativeStatusItem(
                icon: active.type.icon,
                text: countdownText(until: active.shiftEnd ?? now, referenceDate: now),
                reason: "\(reason)-active"
            )
            return
        }

        applyNativeStatusItem(icon: "clock.badge.checkmark", text: nil, reason: "\(reason)-fallback")
    }

    private func applyNativeStatusItem(icon: String, text: String?, reason: String) {
        guard let button = statusItem?.button else {
            print("PayScopeMac StatusItem: cannot apply native item, missing button reason=\(reason)")
            return
        }

        let image = NSImage(systemSymbolName: icon, accessibilityDescription: "PayScope")
            ?? NSImage(systemSymbolName: "clock.badge.checkmark", accessibilityDescription: "PayScope")
        image?.isTemplate = true
        button.image = image
        button.title = text.map { " \($0)" } ?? " PayScope"
        button.font = .systemFont(ofSize: 11, weight: .semibold)
        button.contentTintColor = nil
        button.sizeToFit()

        let targetLength = min(max(ceil(button.intrinsicContentSize.width) + 8, 70), 150)
        statusItem?.length = targetLength
        print("PayScopeMac StatusItem: applied native icon=\(icon) imageNil=\(image == nil) text=\(text ?? "<none>") title=\(button.title) reason=\(reason) intrinsic=\(button.intrinsicContentSize) buttonFrame=\(button.frame) length=\(statusItem?.length ?? 0)")
        printStatusItemDiagnostics(reason: "after-apply-\(reason)")
    }

    private func printStatusItemDiagnostics(reason: String) {
        statusItemDiagnosticsTick += 1
        if statusItemDiagnosticsTick > 12, reason == "timer" {
            statusItemDiagnosticsTimer?.invalidate()
            statusItemDiagnosticsTimer = nil
            print("PayScopeMac Diagnostics: stopped periodic status item diagnostics")
            return
        }

        guard let statusItem else {
            print("PayScopeMac Diagnostics[\(reason)]: missing statusItem")
            return
        }
        guard let button = statusItem.button else {
            print("PayScopeMac Diagnostics[\(reason)]: missing button length=\(statusItem.length)")
            return
        }

        let imageDescription: String
        if let image = button.image {
            imageDescription = "size=\(image.size) template=\(image.isTemplate)"
        } else {
            imageDescription = "<nil>"
        }

        let windowDescription: String
        if let window = button.window {
            windowDescription = "windowFrame=\(window.frame) visible=\(window.isVisible) alpha=\(window.alphaValue) screen=\(String(describing: window.screen?.frame))"
        } else {
            windowDescription = "window=<nil>"
        }

        print(
            "PayScopeMac Diagnostics[\(reason)]: " +
            "statusLength=\(statusItem.length) " +
            "buttonFrame=\(button.frame) bounds=\(button.bounds) " +
            "hidden=\(button.isHidden) alpha=\(button.alphaValue) " +
            "title='\(button.title)' attributedTitleLength=\(button.attributedTitle.string.count) " +
            "image=\(imageDescription) " +
            "superview=\(String(describing: type(of: button.superview))) " +
            "\(windowDescription) " +
            "mouse=\(NSEvent.mouseLocation)"
        )
    }

    private func countdownText(until end: Date, referenceDate: Date) -> String {
        let remainingSeconds = max(0, Int(end.timeIntervalSince(referenceDate)))
        let hours = remainingSeconds / 3_600
        let minutes = (remainingSeconds % 3_600) / 60
        let seconds = remainingSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    @objc
    private func handleSnapshotDidReload(_ notification: Notification) {
        print("PayScopeMac StatusItem: received reload notification")
        if let snapshot = notification.object as? CloudSnapshot {
            applySnapshotToNativeStatusItem(snapshot, reason: "notification")
        } else {
            loadCachedSnapshotForStatusItem(reason: "notification-cache")
        }
    }

    @objc
    private func handleSnapshotReloadFailed(_ notification: Notification) {
        print("PayScopeMac StatusItem: received reload failure \(String(describing: notification.object))")
        applyNativeStatusItem(icon: "exclamationmark.icloud", text: nil, reason: "reload-failed")
    }

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        let isRightClick = event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
        if isRightClick {
            showContextMenu()
        } else {
            togglePopover(from: sender)
        }
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            print("PayScopeMac Popover: close")
            popover.performClose(nil)
        } else {
            print("PayScopeMac Popover: show from buttonFrame=\(button.frame)")
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu() {
        if popover.isShown {
            popover.performClose(nil)
        }
        statusItem?.menu = contextMenu
        statusItem?.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }

    @objc
    private func reloadFromICloud() {
        print("PayScopeMac StatusItem: reload menu clicked")
        Task { await MenuBarActions.reloadFromICloud() }
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}

@main
struct PayScope_for_MacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        SwiftUI.Settings {
            EmptyView()
        }
    }
}

#Preview("App Menu Preview") {
    ContentView()
}
