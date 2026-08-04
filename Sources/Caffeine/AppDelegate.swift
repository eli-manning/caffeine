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

    /// When on, closing the lid won't sleep the Mac while Caffeine Bar is active — a
    /// hardware-level lid-close sleep assertion that `caffeinate -d` alone doesn't cover.
    /// Applied via `pmset -a disablesleep`, which needs admin privileges.
    private var preventSleepOnLidClose: Bool {
        get { UserDefaults.standard.bool(forKey: "preventSleepOnLidClose") }
        set { UserDefaults.standard.set(newValue, forKey: "preventSleepOnLidClose") }
    }

    /// Tracks whether we're the ones currently holding `disablesleep 1`, so we only
    /// ever issue the matching `disablesleep 0` we're responsible for.
    private var lidSleepDisabled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: 32)
        statusItem.button?.action = #selector(handleClick)
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        if let button = statusItem.button {
            iconView = CoffeeIconView(frame: button.bounds)
            iconView.autoresizingMask = [.width, .height]
            iconView.style = iconStyle
            iconView.onHoverEnter = { [weak self] in self?.handleHoverEnter() }
            iconView.onHoverExit = { [weak self] in self?.handleHoverExit() }
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
            presentCompactMenu()
        } else {
            isActive ? stop() : start()
            updateIcon(animated: true)
        }
    }

    // MARK: - Hover-to-open

    private var pendingHoverShow: DispatchWorkItem?
    private var pendingHoverHide: DispatchWorkItem?

    private func handleHoverEnter() {
        pendingHoverHide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.presentFullMenu(hoverPresented: true) }
        pendingHoverShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func handleHoverExit() {
        pendingHoverShow?.cancel()
        scheduleHoverHide()
    }

    private func scheduleHoverHide() {
        guard menuWindow.isHoverPresented else { return }
        let work = DispatchWorkItem { [weak self] in self?.menuWindow.hide() }
        pendingHoverHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
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
        applyLidSleepState()
    }

    private func stop() {
        caffeinate?.terminate()
        caffeinate = nil
        activeStartDate = nil
        applyLidSleepState()
    }

    /// Reconciles the `pmset disablesleep` assertion with whether it should currently
    /// be on (active + the setting enabled). Safe to call any time either input changes.
    private func applyLidSleepState() {
        let shouldDisable = isActive && preventSleepOnLidClose
        guard shouldDisable != lidSleepDisabled else { return }
        lidSleepDisabled = shouldDisable
        let script = "do shell script \"/usr/bin/pmset -a disablesleep \(shouldDisable ? 1 : 0)\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.terminationHandler = { proc in
            if proc.terminationStatus != 0 {
                DispatchQueue.main.async { [weak self] in
                    // The privileged command was cancelled or failed — don't leave our
                    // bookkeeping claiming an assertion we don't actually hold.
                    self?.lidSleepDisabled = !shouldDisable
                }
            }
        }
        do {
            try process.run()
        } catch {
            lidSleepDisabled = !shouldDisable
        }
    }

    private func updateIcon(animated: Bool) {
        let description = isActive ? "Caffeine Bar: Active (display awake)" : "Caffeine Bar: Inactive"
        iconView.setFilled(isActive, animated: animated)
        statusItem.button?.toolTip = description
        statusItem.button?.setAccessibilityLabel(description)
        statusItem.button?.setAccessibilityHelp("Click to toggle display sleep assertion")
    }

    /// Brands shown under "Get an Energy Drink" — each opens its own destination picker.
    private let energyDrinkBrands = ["Red Bull", "Monster Energy", "Celsius", "Bang Energy", "Rockstar Energy"]

    private lazy var menuWindow: CustomMenuWindow = {
        let window = CustomMenuWindow()
        window.energyDrinkBrands = energyDrinkBrands
        window.destinationsProvider = { [weak self] mapQuery, searchTerm in
            self?.drinkDestinations(mapQuery: mapQuery, searchTerm: searchTerm) ?? []
        }
        window.onOpenURL = { url in NSWorkspace.shared.open(url) }
        window.onSelectIconStyle = { [weak self] style in
            self?.iconStyle = style
            self?.menuWindow.iconStyle = style
        }
        window.onToggleLaunchAtLogin = { [weak self] in
            self?.toggleLaunchAtLogin()
            if #available(macOS 13.0, *) {
                self?.menuWindow.setLaunchAtLoginEnabled(SMAppService.mainApp.status == .enabled)
            }
        }
        window.onTogglePreventSleepOnLidClose = { [weak self] in
            guard let self else { return }
            self.preventSleepOnLidClose.toggle()
            self.menuWindow.preventSleepOnLidClose = self.preventSleepOnLidClose
            self.applyLidSleepState()
        }
        window.onQuit = { NSApp.terminate(nil) }
        window.onClose = { [weak self] in self?.statusItem.button?.highlight(false) }
        window.onHoverEnter = { [weak self] in self?.pendingHoverHide?.cancel() }
        window.onHoverExit = { [weak self] in self?.scheduleHoverHide() }
        return window
    }()

    private func refreshMenuState() {
        menuWindow.isActive = isActive
        menuWindow.iconStyle = iconStyle
        menuWindow.preventSleepOnLidClose = preventSleepOnLidClose
        if #available(macOS 13.0, *) {
            menuWindow.launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }
        menuWindow.activeDetail = ""
        if isActive, let start = activeStartDate {
            menuWindow.activeDetail = formatDuration(Int(Date().timeIntervalSince(start)))
        }
    }

    private func presentFullMenu(hoverPresented: Bool) {
        guard let button = statusItem.button else { return }
        refreshMenuState()
        button.highlight(true)
        menuWindow.present(relativeTo: button, mode: .full, hoverPresented: hoverPresented)
    }

    private func presentCompactMenu() {
        guard let button = statusItem.button else { return }
        refreshMenuState()
        button.highlight(true)
        menuWindow.present(relativeTo: button, mode: .compact, hoverPresented: false)
    }

    // MARK: - Get a Drink

    /// Search-only destinations — no checkout automation, no order placement.
    /// DoorDash/Instacart don't publish a stable search API; these are
    /// best-effort URL patterns captured by hand and may break if either
    /// site changes its URL structure. Maps searches places, not products, so
    /// `mapQuery` targets the kind of store that carries the drink rather than
    /// the drink itself.
    private func drinkDestinations(mapQuery: String, searchTerm: String) -> [DrinkDestination] {
        var appleMaps = URLComponents(string: "maps://")!
        appleMaps.queryItems = [URLQueryItem(name: "q", value: mapQuery)]

        var googleMaps = URLComponents(string: "https://www.google.com/maps/search/")!
        googleMaps.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: "\(mapQuery) near me"),
        ]

        var doorDash = URLComponents()
        doorDash.scheme = "https"
        doorDash.host = "www.doordash.com"
        doorDash.path = "/search/store/\(searchTerm)/"

        var instacart = URLComponents(string: "https://www.instacart.com/store/s")!
        instacart.queryItems = [URLQueryItem(name: "k", value: searchTerm)]

        return [
            DrinkDestination(title: "Nearby Stores (Apple Maps)", symbol: "map.fill", url: appleMaps.url),
            DrinkDestination(title: "Nearby Stores (Google Maps)", symbol: "map", url: googleMaps.url),
            DrinkDestination(title: "Find on DoorDash", symbol: "bag.fill", url: doorDash.url),
            DrinkDestination(title: "Find on Instacart", symbol: "cart", url: instacart.url),
        ]
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
