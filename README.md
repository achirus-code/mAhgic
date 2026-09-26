# mAhgic

A small macOS app that shows the real battery health of your Mac – and of your iPhone and iPad, by cable or over Wi‑Fi.

- Full-charge vs. design capacity, charge cycles, temperature, power in/out, manufacture date
- iPhone and iPad via `usbmuxd`/`lockdownd` (USB or Wi‑Fi sync), no app on the device
- History per device with monthly averages; imports coconutBattery history, exports CSV
- All raw IORegistry battery values behind the `{ }` button
- Everything stays local in `~/Library/Application Support/mAhgic`

## Build

Requires macOS 14+ on Apple silicon and the Swift toolchain (Command Line Tools are enough, no Xcode project).

```sh
./build.sh                 # → build/mAhgic.app (release, ad-hoc signed)
swift run mahcli mac       # developer CLI: mac | raw | list | read [udid] [--wifi]
```

## Wi‑Fi readout

1. Connect the iPhone/iPad once by USB and tap “Trust”.
2. In Finder, enable showing the device when on Wi‑Fi.
3. Keep Mac and device on the same network.

## Website

`website/page.html` is the landing page (German/English). `website/build.sh` wraps it into a standalone `website/index.html` and zips the app into `website/downloads/`.

## Layout

| Path | Contents |
|---|---|
| `Sources/mAhgicCore` | Battery reading (IOKit), usbmuxd/lockdown/TLS client, history store |
| `Sources/mAhgic` | SwiftUI app |
| `Sources/mahcli` | Command-line tool for testing |
| `scripts/make_icon.swift` | Renders the app icon |
