# PadLink

Forward a wired USB-C controller on an iPhone to a Windows 11 PC as a virtual
Xbox 360 controller over a low-latency UDP link (no Bluetooth).

- `iOS/` – SwiftUI app. Generate the Xcode project with `xcodegen` (`cd iOS && xcodegen`), set your signing team, run on a device.
- `Windows/` – Python receiver using ViGEmBus. See `Windows/README.md`.
- `PROTOCOL.md` – 16-byte packet format.

Untested: written without Xcode or Windows access. Expect to fix small build issues.

## No Mac? Build in the cloud and sideload from Windows

1. On GitHub: Actions → "PadLink iOS (unsigned IPA)" → Run workflow (runs on a GitHub-hosted Mac).
2. Download the `PadLink-unsigned-ipa` artifact and unzip to get `PadLink.ipa`.
3. On Windows, install Sideloadly (or AltStore), plug in the iPhone, and install the IPA with your Apple ID.
   A free Apple ID's app expires after 7 days and must be re-installed; a paid developer account lasts a year.
