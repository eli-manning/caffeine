import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var iconView: CoffeeIconView!
    private var caffeinate: Process?
    private var activeStartDate: Date?

    private var isActive: Bool { caffeinate?.isRunning ?? false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: 32)
        statusItem.button?.action = #selector(handleClick)
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        if let button = statusItem.button {
            iconView = CoffeeIconView(frame: button.bounds)
            iconView.autoresizingMask = [.width, .height]
            button.addSubview(iconView)
        }
        updateIcon(animated: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        isActive ? stop() : start()
        updateIcon(animated: true)
        return false
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            isActive ? stop() : start()
            updateIcon(animated: true)
        }
    }

    private func start() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-d"]
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.caffeinate = nil
                self?.activeStartDate = nil
                self?.updateIcon(animated: true)
            }
        }
        do {
            try process.run()
            caffeinate = process
            activeStartDate = Date()
        } catch {
            caffeinate = nil
            activeStartDate = nil
        }
    }

    private func stop() {
        caffeinate?.terminate()
        caffeinate = nil
        activeStartDate = nil
    }

    private func updateIcon(animated: Bool) {
        let description = isActive ? "Caffeine: Active (display awake)" : "Caffeine: Inactive"
        iconView.setFilled(isActive, animated: animated)
        statusItem.button?.toolTip = description
        statusItem.button?.setAccessibilityLabel(description)
        statusItem.button?.setAccessibilityHelp("Click to toggle display sleep assertion")
    }

    private func showMenu() {
        let menu = NSMenu()

        // Active Status Header
        let statusTitle: String
        if isActive, let start = activeStartDate {
            let elapsed = Int(Date().timeIntervalSince(start))
            statusTitle = "☕ Caffeine: Active (\(formatDuration(elapsed)))"
        } else {
            statusTitle = "☕ Caffeine: Inactive"
        }
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        // Get a Red Bull
        let redBullItem = NSMenuItem(title: "Get a Red Bull", action: nil, keyEquivalent: "")
        redBullItem.submenu = redBullMenu()
        menu.addItem(redBullItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at Login Toggle
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        if #available(macOS 13.0, *) {
            loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Caffeine", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        self.statusItem.menu = menu
        self.statusItem.button?.performClick(nil)
        self.statusItem.menu = nil
    }

    // MARK: - Get a Red Bull

    /// Search-only destinations — no checkout automation, no order placement.
    /// DoorDash/Instacart don't publish a stable search API; these are
    /// best-effort URL patterns captured by hand and may break if either
    /// site changes its URL structure.
    private struct RedBullDestination {
        let title: String
        let url: () -> URL?
    }

    private var redBullDestinations: [RedBullDestination] {
        [
            // Maps searches for places/businesses, not products — "Red Bull" as a query
            // returns nothing useful. Search broadly across the store types that
            // typically carry it, since a single query can't express a real category OR.
            RedBullDestination(title: "Nearby Stores (Apple Maps)") {
                var components = URLComponents(string: "maps://")!
                components.queryItems = [URLQueryItem(name: "q", value: "gas station OR convenience store OR grocery store")]
                return components.url
            },
            RedBullDestination(title: "Nearby Stores (Google Maps)") {
                var components = URLComponents(string: "https://www.google.com/maps/search/")!
                components.queryItems = [
                    URLQueryItem(name: "api", value: "1"),
                    URLQueryItem(name: "query", value: "gas station OR convenience store OR grocery store near me"),
                ]
                return components.url
            },
            RedBullDestination(title: "Find on DoorDash") {
                var components = URLComponents()
                components.scheme = "https"
                components.host = "www.doordash.com"
                components.path = "/search/store/red bull/"
                return components.url
            },
            RedBullDestination(title: "Find on Instacart") {
                var components = URLComponents(string: "https://www.instacart.com/store/s")!
                components.queryItems = [URLQueryItem(name: "k", value: "red bull")]
                return components.url
            },
        ]
    }

    private func redBullMenu() -> NSMenu {
        let menu = NSMenu()
        let destinations = redBullDestinations

        for (index, destination) in destinations.enumerated() {
            let item = NSMenuItem(title: destination.title, action: #selector(openRedBullDestination(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
            if index == 1 {
                menu.addItem(NSMenuItem.separator())
            }
        }
        return menu
    }

    @objc private func openRedBullDestination(_ sender: NSMenuItem) {
        let destinations = redBullDestinations
        guard destinations.indices.contains(sender.tag), let url = destinations[sender.tag].url() else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                print("Failed to toggle launch at login: \(error)")
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            let mins = seconds / 60
            return "\(mins)m"
        } else {
            let hrs = seconds / 3600
            let mins = (seconds % 3600) / 60
            return "\(hrs)h \(mins)m"
        }
    }
}
