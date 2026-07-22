# GemmaTrans 2.0 App Store screenshots

Final Simplified Chinese macOS screenshots are exported as 2560 × 1600 JPEGs
without alpha, in this order:

1. `01-main-dark.jpg` — completed translation in the main window
2. `03-panel-light.jpg` — pinned quick-translation panel
3. `04-settings-general-light.jpg` — appearance and translation preferences
4. `05-settings-models-light.jpg` — four on-device models and automatic source fallback
5. `06-settings-integrations-light.jpg` — local API and shortcut integrations

The product UI is captured from the fresh Debug build using deterministic,
Debug-only fixture data. `script/prepare_store_screenshot.swift` adds the store
canvas and feature caption. For Computer Use captures, only the small title-bar
area containing automation overlays is replaced from the deterministic fixture;
the rest of the window remains the native rendered UI.

Apple accepts 2560 × 1600 as a 16:10 macOS screenshot size. See the
[App screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).
