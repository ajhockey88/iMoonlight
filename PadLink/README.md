# PadLink

Forward a wired USB-C controller on an iPhone to a Windows 11 PC as a virtual
Xbox 360 controller over a low-latency UDP link (no Bluetooth).

- `iOS/` – SwiftUI app. Generate the Xcode project with `xcodegen` (`cd iOS && xcodegen`), set your signing team, run on a device.
- `Windows/` – Python receiver using ViGEmBus. See `Windows/README.md`.
- `PROTOCOL.md` – 16-byte packet format.

Untested: written without Xcode or Windows access. Expect to fix small build issues.
