import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var iconView: CoffeeIconView!
    private var caffeinate: Process?
    private var activeStartDate: Date?

    private var isActive: Bool { caffeinate?.isRunning ?? false }

    private var iconStyle: IconStyle {
        get { IconStyle(rawValue: UserDefaults.standard.string(forKey: "iconStyle") ?? "") ?? .energyDrink }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "iconStyle")
            iconView.style = newValue
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: 32)
        statusItem.button?.action = #selector(handleClick)
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        if let button = statusItem.button {
            iconView = CoffeeIconView(frame: button.bounds)
            iconView.autoresizingMask = [.width, .height]
            iconView.style = iconStyle
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
        menu.autoenablesItems = false

        // Status header — custom view instead of a plain disabled text item.
        let headerItem = NSMenuItem()
        headerItem.isEnabled = false
        let header = StatusHeaderView(frame: NSRect(x: 0, y: 0, width: 230, height: 40))
        let detail: String
        if isActive, let start = activeStartDate {
            detail = "Active for \(formatDuration(Int(Date().timeIntervalSince(start))))"
        } else {
            detail = "Currently inactive"
        }
        header.configure(title: "Caffeine", detail: detail, dotColor: isActive ? .systemGreen : .tertiaryLabelColor)
        headerItem.view = header
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        // Get an Energy Drink / Get a Coffee
        let energyItem = NSMenuItem(title: "Get an Energy Drink", action: nil, keyEquivalent: "")
        energyItem.image = symbolImage("bolt.fill")
        energyItem.submenu = energyDrinkMenu()
        menu.addItem(energyItem)

        let coffeeItem = NSMenuItem(title: "Get a Coffee", action: nil, keyEquivalent: "")
        coffeeItem.image = symbolImage("cup.and.saucer.fill")
        coffeeItem.submenu = coffeeMenu()
        menu.addItem(coffeeItem)

        menu.addItem(NSMenuItem.separator())

        // Icon Style
        let styleItem = NSMenuItem(title: "Icon Style", action: nil, keyEquivalent: "")
        styleItem.image = symbolImage("paintbrush.fill")
        styleItem.submenu = iconStyleMenu()
        menu.addItem(styleItem)

        // Launch at Login Toggle
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.image = symbolImage("power")
        if #available(macOS 13.0, *) {
            loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Caffeine", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = symbolImage("xmark.circle")
        menu.addItem(quitItem)

        self.statusItem.menu = menu
        self.statusItem.button?.performClick(nil)
        self.statusItem.menu = nil
    }

    private func symbolImage(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    // MARK: - Icon Style

    private func iconStyleMenu() -> NSMenu {
        let menu = NSMenu()

        let coffeeItem = NSMenuItem(title: "Coffee", action: #selector(selectIconStyle(_:)), keyEquivalent: "")
        coffeeItem.target = self
        coffeeItem.tag = 0
        coffeeItem.image = symbolImage("cup.and.saucer.fill")
        coffeeItem.state = iconStyle == .coffee ? .on : .off
        menu.addItem(coffeeItem)

        let energyItem = NSMenuItem(title: "Energy Drink", action: #selector(selectIconStyle(_:)), keyEquivalent: "")
        energyItem.target = self
        energyItem.tag = 1
        energyItem.image = symbolImage("bolt.fill")
        energyItem.state = iconStyle == .energyDrink ? .on : .off
        menu.addItem(energyItem)

        return menu
    }

    @objc private func selectIconStyle(_ sender: NSMenuItem) {
        iconStyle = sender.tag == 0 ? .coffee : .energyDrink
    }

    // MARK: - Get a Drink

    /// Brands shown under "Get an Energy Drink" — each opens its own destination submenu.
    private let energyDrinkBrands = ["Red Bull", "Monster Energy", "Celsius", "Bang Energy", "Rockstar Energy"]

    private func energyDrinkMenu() -> NSMenu {
        let menu = NSMenu()
        for brand in energyDrinkBrands {
            let item = NSMenuItem(title: brand, action: nil, keyEquivalent: "")
            item.submenu = destinationMenu(
                mapQuery: "gas station OR convenience store OR grocery store",
                searchTerm: brand.lowercased()
            )
            menu.addItem(item)
        }
        return menu
    }

    private func coffeeMenu() -> NSMenu {
        destinationMenu(mapQuery: "coffee shop", searchTerm: "coffee")
    }

    /// Search-only destinations — no checkout automation, no order placement.
    /// DoorDash/Instacart don't publish a stable search API; these are
    /// best-effort URL patterns captured by hand and may break if either
    /// site changes its URL structure. Maps searches places, not products, so
    /// `mapQuery` targets the kind of store that carries the drink rather than
    /// the drink itself.
    private func destinationMenu(mapQuery: String, searchTerm: String) -> NSMenu {
        let menu = NSMenu()

        func addItem(_ title: String, symbol: String, url: URL?) {
            let item = NSMenuItem(title: title, action: #selector(openDestination(_:)), keyEquivalent: "")
            item.target = self
            item.image = symbolImage(symbol)
            item.representedObject = url
            item.isEnabled = url != nil
            menu.addItem(item)
        }

        var appleMaps = URLComponents(string: "maps://")!
        appleMaps.queryItems = [URLQueryItem(name: "q", value: mapQuery)]
        addItem("Nearby Stores (Apple Maps)", symbol: "map.fill", url: appleMaps.url)

        var googleMaps = URLComponents(string: "https://www.google.com/maps/search/")!
        googleMaps.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: "\(mapQuery) near me"),
        ]
        addItem("Nearby Stores (Google Maps)", symbol: "map", url: googleMaps.url)

        menu.addItem(.separator())

        var doorDash = URLComponents()
        doorDash.scheme = "https"
        doorDash.host = "www.doordash.com"
        doorDash.path = "/search/store/\(searchTerm)/"
        addItem("Find on DoorDash", symbol: "bag.fill", url: doorDash.url)

        var instacart = URLComponents(string: "https://www.instacart.com/store/s")!
        instacart.queryItems = [URLQueryItem(name: "k", value: searchTerm)]
        addItem("Find on Instacart", symbol: "cart", url: instacart.url)

        return menu
    }

    @objc private func openDestination(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
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
