import AppKit
import SwiftUI

enum MenuBarActions {
    static func reloadFromICloud() async {
        do {
            let snapshot = try await CloudKitReadService.shared.fetchSnapshot()
            await LocalCloudSnapshotStore.shared.save(snapshot: snapshot)
            await MainActor.run {
                NotificationCenter.default.post(name: .menuBarSnapshotDidReload, object: snapshot)
            }
        } catch {
            await MainActor.run {
                NotificationCenter.default.post(name: .menuBarSnapshotReloadFailed, object: error)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var statusIconHostingView: NSHostingView<MenuBarIconView>?
    private var statusItemLengthTimer: Timer?

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
        configurePopover()
        configureStatusItem()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .environment(\.locale, Locale(identifier: "de_DE"))
        )
        popover.contentSize = NSSize(width: 360, height: 420)
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        let hostingView = NSHostingView(rootView: MenuBarIconView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)
        button.toolTip = "PayScope"

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])

        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        self.statusItem = statusItem
        self.statusIconHostingView = hostingView
        updateStatusItemLength()
        statusItemLengthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateStatusItemLength()
        }
    }

    private func updateStatusItemLength() {
        guard let statusItem, let hostingView = statusIconHostingView else { return }

        hostingView.layoutSubtreeIfNeeded()
        let fittingWidth = ceil(hostingView.fittingSize.width)
        statusItem.length = min(max(fittingWidth, 28), 150)
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
            popover.performClose(nil)
        } else {
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
