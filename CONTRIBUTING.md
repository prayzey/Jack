# Contributing to Jack

Thanks for helping. Jack is a solo-maintained macOS app, so small focused changes land fastest.

## Before you start

- Read `README.md` for build and run instructions.
- Read `CLAUDE.md`. It is written for AI coding agents but it is also the best map of the architecture, the window rules, and the naming policy (the product is Jack, the SwiftPM target and bundle ID stay `Gilt` so existing installs keep upgrading).
- Open an issue first for anything larger than a bug fix, so we can agree on the approach before you spend time on it.

## Making a change

1. Fork and branch from `main`.
2. Run `swift build` and `swift test` before you push. Tests that need local models are marked manual and can be skipped.
3. If you add or change user-facing copy, localize it in the same change. `Sources/Gilt/Localization/` holds the `.strings` files.
4. Keep the pull request to one topic. Describe what changed and why in a few sentences.

## Rules that keep the app working

- Never present sheets or full-screen covers on the tray window. Use a standalone `NSWindow` through `AppWindowManager`.
- Never use SwiftUI `DragGesture` for window resizing. Use `AppKitResizeHandle`.
- Do not rename the bundle ID `com.praisedev.gilt` or the `Gilt.store` filename. Both are load-bearing for upgrades.
- Do not commit secrets, signing keys, or personal data. Release signing, notarization, and upload credentials live in Keychain and local CLI profiles, never in the repo.

## Licensing

By contributing you agree that your changes are released under the MIT License in `LICENSE`.
