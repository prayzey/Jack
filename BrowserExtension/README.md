# Jack Tab Volume

A browser extension that lets Jack's menu bar sound panel list the tabs playing sound and set each tab's volume and mute state. It works in Chromium browsers: Aside, Chrome, Brave, Arc, Edge, and others (version 116 or later).

## Install

1. Open the browser's extensions page (`chrome://extensions`, or `aside://extensions`, `brave://extensions`, `edge://extensions`).
2. Turn on **Developer mode**.
3. Click **Load unpacked** and choose this folder. In a packaged Jack it is at `Jack.app/Contents/Resources/BrowserExtension`.
4. Reload tabs that were already open. The volume hook only reaches pages loaded after the extension; mute works everywhere right away.

## How it works

- `background.js` (service worker) connects to `ws://127.0.0.1:51723/jack-tabs`, a WebSocket server Jack runs on loopback (`Sources/Gilt/Services/Sound/BrowserTabBridge.swift`). It reports tabs that are audible, muted, or not at full volume, and applies the changes Jack sends. When Jack isn't running it retries with backoff and, while the worker is asleep, every 30 seconds through an alarm.
- Mute uses the browser's own tab mute.
- Volume is a per-tab gain. `bridge.js` passes it into the page, where `page-volume.js` multiplies it into every media element's volume and routes each `AudioContext` through a gain node. Sites still see the volume they set themselves.

## Wire protocol (JSON text frames)

Extension to Jack: `hello` (`version`, `browser`), `tabs` (`id`, `title`, `url`, `favIconUrl`, `audible`, `muted`, `volume`), and `ping` every 20 seconds.
Jack to extension: `setVolume` (`tabId`, `volume`), `setMuted` (`tabId`, `muted`), `requestTabs`.
