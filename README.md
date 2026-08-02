# Caffeine Bar ⚡

A tiny, free, open source macOS menu bar app that keeps your Mac's display awake — dressed up as a drink bar that lives in your menu bar.

Click the icon in the menu bar to toggle:

- **Filled icon** — Active. Keeps your screen awake using the native macOS `caffeinate -d` command.
- **Empty icon** — Inactive. Your normal system sleep settings apply.

No account, no telemetry, no background noise.

---

## Features

- **Two icon styles, switchable anytime:**
  - **Energy Drink** — a can that fills with color and sprouts wings when activated, folding back in after a few seconds.
  - **Coffee** — a cup that fills with color and puffs steam wisps when activated.
- **Fully custom menu, not the native macOS one:** a hand-built, borderless dark panel with colored icon chips and hover-highlighted rows.
  - **Hover** the icon to open the full menu — status header, drink pickers, icon style switch, and login/quit.
  - **Right-click** for a compact menu — just Launch at Login and Quit.
- **"Get an Energy Drink":** pick a brand (Red Bull, Monster Energy, Celsius, Bang Energy, Rockstar Energy), then jump to nearby stores (Apple/Google Maps) or search delivery apps (DoorDash, Instacart).
- **"Get a Coffee":** same destination picker, aimed at nearby coffee shops.
- **Launch at login:** toggle auto-start from the menu.
- **Light & dark mode:** adapts to your macOS system theme (menu panel itself is intentionally always dark).

---

## Build from Source

Requires macOS 13.0+, Xcode Command Line Tools, and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/eli-manning/caffeine-bar.git
cd caffeine-bar
./build.sh --install
```

Since Caffeine Bar isn't notarized, macOS will block it the first time you open it. To get past this, go to **System Settings > Privacy & Security**, scroll down to the message about Caffeine Bar, and click **Open Anyway**.

---

## Credits

Forked from [Ryan Stoffel's Caffeine](https://github.com/RyanStoffel/caffeine).

## License

[MIT](LICENSE)
