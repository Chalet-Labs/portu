# Building Modern macOS Desktop Apps Like Conductor.build

## Research Report — March 2026

---

## Executive Summary

Building a polished, modern macOS desktop app in 2025–2026 is firmly viable across multiple technology stacks. **SwiftUI** has crossed a maturity threshold and is the recommended choice for macOS-focused apps — it's what Conductor.build uses (99.3% Swift, XcodeGen, xcodebuild). **Tauri 2.0** is the credible cross-platform alternative (8.6 MB binary, ~40 MB idle RAM, native WKWebView). **Electron** remains viable for large web-dev teams but carries structural limitations (244 MB binary, 400+ MB RAM). Custom **Rust + Metal** rendering (Warp, Zed) is only justified for frame-rate-critical applications.

macOS Tahoe introduces **Liquid Glass**, a new design language with first-class SwiftUI APIs — the most significant visual refresh since Big Sur. Apps recompiled with Xcode 26 get Liquid Glass automatically on toolbars, sidebars, and standard controls.

### Key Takeaways

1. **Conductor.build is native SwiftUI** — not Electron, not a web wrapper. It uses XcodeGen + xcodebuild, targets macOS 14.0+, and wraps the Claude Code CLI with a native UI.
2. **SwiftUI is production-ready** for macOS: 10k-item list performance, rich text editing, native WebView, inspector panels — all work without AppKit bridges.
3. **Tauri 2.0** is the best non-native option: 30x smaller than Electron, uses system WebKit on macOS, with Rust backend for system APIs.
4. **The "native feel" gap is real** — Electron can reach ~70-80% of native feel; Tauri ~85-90%; only Swift/AppKit hits 100%.
5. **Distribution**: direct distribution (Developer ID + notarization + Sparkle) gives full control; Mac App Store trades revenue share for built-in updates and discovery.

---

## 1. The Landscape: Real Apps and Their Tech Stacks

| App | Stack | Why It Matters |
|---|---|---|
| **Conductor.build** | SwiftUI (99.3% Swift), XcodeGen, xcodebuild | CLI wrapper with native UI — reference for this research |
| **Raycast** | Native AppKit (not SwiftUI, not Electron) | Launcher requiring extreme performance; extensions use React/TS via IPC |
| **Warp** | Rust + custom Metal GPU renderer | Terminal requiring 144+ FPS rendering; built own UI framework |
| **Zed** | Rust + GPUI (custom GPU framework) | Code editor; open-source, Metal on macOS |
| **Linear** | Electron + React | Web-first product; desktop wraps the web app |
| **Arc Browser** | Chromium-based | Browser; now in maintenance mode (Atlassian acquisition) |
| **CodeEdit** | SwiftUI + AppKit (open-source) | IDE; excellent reference for SwiftUI macOS patterns |
| **Cork** | SwiftUI (open-source) | Homebrew GUI; clean SwiftUI implementation |

**Pattern**: High-polish macOS-first apps go native (Swift/AppKit/SwiftUI). Cross-platform products use Electron or Tauri. Performance-critical rendering apps build custom Rust frameworks.

---

## 2. Native SwiftUI macOS Development

### 2.1 What's Production-Ready (macOS 14+)

| Feature | Status | Notes |
|---|---|---|
| `List` with 10k+ items | Works well | "Snappy" in 2025 testing; was broken pre-2024 |
| `TextEditor` with `AttributedString` | Works | Bold, italic, underline, font size |
| `WebView(url:)` | Native | No `NSViewRepresentable` needed |
| Inspector panels | Works | `.inspector(isPresented:)` — trailing sidebar |
| `MenuBarExtra` | Works | Menu bar app scenes |
| `UtilityWindow` | Works | Floating tool panels |
| `NavigationSplitView` | Works | Multi-column sidebar/detail/inspector |
| `@Observable` | Recommended | Per-property tracking (not whole-object) |
| SwiftData | Production-ready | Built on Core Data; requires `@Observable` |

### 2.2 What Still Needs AppKit Bridges

- Advanced font picker dialogs
- Real-time spell checking in TextEditor
- Large streaming text (chat-style UIs) — `NSTextView` via `NSViewRepresentable` outperforms
- Photo grids at extreme scale (`NSCollectionView` equivalent)
- Sidebar toggle button removal in `sidebarAdaptable` layouts

**Rule of thumb**: Start 100% SwiftUI. Profile. Surgically replace hot paths with `NSViewRepresentable`. Never start AppKit-first and bridge SwiftUI in — that's significantly harder to maintain.

### 2.3 Navigation Architecture

```swift
NavigationSplitView(columnVisibility: $columnVisibility) {
    SidebarView()
} content: {
    ContentView()
} detail: {
    DetailView()
        .inspector(isPresented: $showInspector) {
            InspectorView()
        }
}
```

- `NavigationSplitView` replaces deprecated `NavigationView` for multi-column layouts
- `@SceneStorage` auto-persists sidebar state per window instance
- `.windowLevel(.floating)` makes always-on-top windows without AppKit
- In macOS Tahoe, sidebars automatically receive Liquid Glass appearance

### 2.4 State Management: @Observable (Not @ObservableObject)

```swift
@Observable
class ProjectViewModel {
    var files: [File] = []
    var selectedFile: File?
    // No @Published needed — all properties auto-tracked
}

// In view — use @State, NOT @StateObject
@State private var viewModel = ProjectViewModel()
```

**Critical difference**: `@ObservableObject` re-renders the *entire* view when any published property changes. `@Observable` re-renders only views that *read* the changed property. For a list of 10k items, changing item #42 re-renders only that row.

### 2.5 Window Management

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }

        UtilityWindow("Tools", id: "tools") {
            ToolsView()
        }

        MenuBarExtra("Status", systemImage: "circle.fill") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView() }
    }
}
```

### 2.6 List Performance Gotchas

1. **`List` vs `LazyVStack`**: `List` recycles off-screen cells (memory-efficient). `LazyVStack` loads lazily but never releases. For 10k+ items, use `List`.
2. **`.id()` trap**: `.id(someValue)` on `List` rows forces all rows to instantiate immediately, destroying lazy loading.
3. **Conditional content**: `if`/`switch` in `List` body produces `_ConditionalContent` which forces eager instantiation. Wrap in `VStack` inside the row view.
4. **macOS vs iOS**: macOS SwiftUI list rendering is measurably slower than iOS. Known, unfixed gap.

---

## 3. macOS UI/UX Design Language

### 3.1 Core Principles (Apple HIG)

- **Clarity**: Legible text, precise icons, purposeful layout
- **Deference**: UI serves content; minimize chrome and decoration
- **Depth**: Layers and motion convey hierarchy and relationships

### 3.2 Liquid Glass (macOS Tahoe / WWDC 2025)

Liquid Glass is a translucent material that reflects and refracts surroundings. Key difference from prior blur: it uses **lensing** (bending and concentrating light), not scattering.

```swift
// Basic glass effect
.glassEffect()                     // .regular (default)
.glassEffect(.clear)

// Multiple glass elements sharing space
GlassEffectContainer(spacing: 30) {
    HStack {
        Button("Edit") { }.glassEffect()
        Button("Share") { }.glassEffect()
    }
}

// Button styles
.buttonStyle(.glass)               // secondary
.buttonStyle(.glassProminent)      // primary, accepts tint
```

**Apply glass to**: toolbars, tab bars, sidebars, floating buttons, sheets, popovers, menus.
**Never apply glass to**: content layers (lists, cards, tables), full-screen backgrounds.

**Automatic**: When recompiled with Xcode 26, toolbars, sidebars, menu bars, dock, window controls, NSPopover, and sheets automatically get Liquid Glass.

### 3.3 Vibrancy and Materials (pre-Tahoe)

```swift
// Automatic for sidebars
List { ... }.listStyle(.sidebar)

// Manual material background
VStack { ... }
    .background(.ultraThinMaterial)

// AppKit bridge for behind-window blending
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
```

### 3.4 What Makes a macOS App Look "Modern"

| Pattern | Implementation |
|---|---|
| Translucent sidebar | `.listStyle(.sidebar)` — automatic |
| Material backgrounds | `.background(.ultraThinMaterial)` |
| Dark mode | Use semantic colors; never hardcode hex values |
| SF Symbols | `Image(systemName: "folder")` — 5000+ icons |
| System font | `Font.system(.body)` — SF Pro with auto optical sizing |
| Inset grouped lists | `.listStyle(.insetGrouped)` |
| Toolbar integration | `.toolbar { }` modifier |
| Inspector panels | `.inspector(isPresented:)` |
| Smooth animations | `withAnimation(.spring)`, `matchedGeometryEffect` |

---

## 4. Tauri 2.0 — The Cross-Platform Alternative

### 4.1 Architecture

- **Rust backend**: process lifecycle, file I/O, system APIs, plugin layer
- **Web frontend**: any JS framework (React, Vue, Svelte), runs in system WebView
- **macOS**: uses WKWebView (native WebKit), not bundled Chromium
- **IPC**: typed message-passing via Tauri commands

### 4.2 Performance vs Electron

| Metric | Tauri | Electron |
|---|---|---|
| Binary size | **8.6 MB** | 244 MB |
| Idle RAM (6 windows) | **~172 MB** | ~409 MB |
| Cold startup | ~0.5–1s | ~2–4s |
| Initial build time | ~80s (Rust compile) | ~15s |

### 4.3 macOS Native Feel

```rust
// Vibrancy via window-vibrancy crate
use window_vibrancy::{apply_vibrancy, NSVisualEffectMaterial};
apply_vibrancy(&window, NSVisualEffectMaterial::HudWindow, None, None)?;
```

```json
// tauri.conf.json — transparent titlebar (keeps traffic lights)
{ "windows": [{ "titleBarStyle": "Transparent" }] }
```

- Native `.dmg` installer generation
- Code signing and notarization built-in
- Mac App Store submission supported (universal binary: arm64 + x86_64)
- System permissions plugin for macOS-specific capabilities

### 4.4 When to Choose Tauri over SwiftUI

| Choose Tauri when... | Choose SwiftUI when... |
|---|---|
| Cross-platform (macOS + Windows + Linux) | macOS-only |
| Web dev team, no Swift experience | Swift/iOS team |
| Binary size is a marketing requirement | Deep system integration needed |
| Rust backend for performance-critical logic | Full Liquid Glass adoption |
| Rapid prototyping from web app | Mac App Store with sandboxing |

---

## 5. Electron — The Incumbent

### 5.1 Making Electron Feel Native on macOS

```javascript
new BrowserWindow({
    titleBarStyle: 'hidden',
    trafficLightPosition: { x: 16, y: 16 },
    vibrancy: 'sidebar',
    backgroundColor: '#00000000'
})
```

```css
body {
    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
    font-size: 13px;
}
.sidebar { user-select: none; cursor: default; }
.titlebar { -webkit-app-region: drag; }
```

These techniques bring Electron to ~70-80% of native feel. The remaining gap (system WebView rendering, precise window material integration, energy efficiency) is **structurally unresolvable** with Electron's architecture.

### 5.2 When Electron Still Makes Sense

- Large existing React/web codebase to wrap
- Team has zero native development experience and needs to ship fast
- Cross-platform consistency matters more than native feel
- You're building the next Linear (web-first, desktop as wrapper)

---

## 6. Custom Rendering: Rust + Metal

### 6.1 The Warp Approach

- Briefly evaluated Electron, immediately pivoted to Rust + Metal
- Rendering primitives: rectangles, images, glyphs via texture atlas (~200 lines of Metal shader)
- Custom UI framework using Entity-Component-System (ECS) to work around Rust's ownership model
- Performance: **144+ FPS on 4K, 1.9ms average screen redraw**
- Same codebase ships to macOS, Linux, Windows

### 6.2 GPUI (Zed Editor)

- Open-source GPU UI framework in Rust
- Metal on macOS, targeting 120 FPS
- Available as `gpui` crate; `gpui-component` provides 60+ pre-built widgets
- Powers Zed in production

### 6.3 When Custom Rendering Is Justified

**Only when**: frame-rate-critical display IS the product (terminal, code editor, game), rendering is the competitive differentiator, and you have 6–12 months for framework infrastructure.

**For everything else**: SwiftUI or Tauri.

---

## 7. Distribution and Shipping

### 7.1 Mac App Store vs Direct Distribution

| Factor | Mac App Store | Direct (Developer ID) |
|---|---|---|
| Sandbox | Mandatory | Optional |
| File system access | Restricted | Unrestricted |
| Review time | 1–7 days | None (notarization: minutes) |
| Revenue | 70–85% to developer | 100% |
| Auto-updates | Built-in | Sparkle framework |
| Trials / paid upgrades | Not supported | Full control |
| Payment | Apple handles | You handle (Stripe/Paddle/LemonSqueezy) |

Conductor.build uses **direct distribution** — free app, no App Store needed.

### 7.2 Code Signing and Notarization

```bash
# Notarize
xcrun notarytool submit MyApp.dmg \
  --apple-id "dev@example.com" \
  --team-id "ABCDE12345" \
  --password "@keychain:AC_PASSWORD" \
  --wait

# Staple the ticket
xcrun stapler staple MyApp.dmg
```

Requirements: Apple Developer Program membership ($99/year), Developer ID Application certificate.

### 7.3 Sparkle Auto-Updates

Sparkle is the de facto standard for macOS auto-updates outside the App Store.

**Critical rules**:
1. Never use `codesign --deep` — sign components individually in order: XPC services → Sparkle.framework → app bundle
2. Sparkle uses `CFBundleVersion` (build number), not marketing version — build numbers must always increment
3. GitHub Releases + raw GitHub URLs for `appcast.xml` is a viable zero-cost hosting strategy

### 7.4 Build Tooling

| Tool | Purpose |
|---|---|
| **XcodeGen** | Generate .xcodeproj from YAML — eliminates merge conflicts (used by Conductor) |
| **Swift Package Manager** | Dependency management — integrated with Xcode |
| **Fastlane** | CI automation: `build_app`, `notarize`, `run_tests` |
| **create-dmg** | Beautiful DMG installer creation |
| **xcodebuild** | CLI builds for CI/CD |

---

## 8. Architecture and Testing

### 8.1 Recommended Architecture: @Observable + Environment

```swift
@Observable class AppState {
    var selectedProject: Project?
    var settings = Settings()
}

// Inject at app root
@State private var appState = AppState()
ContentView().environment(appState)

// Consume anywhere
@Environment(AppState.self) private var appState
```

**When to use TCA (The Composable Architecture)**: state spans modules and must be tested in isolation, you need time-travel debugging, team is experienced with Redux/Elm. TCA's onboarding cost is real.

### 8.2 Testing

```swift
import Testing

@Test func parseOutput() async throws {
    let result = try await parser.parse(sampleInput)
    #expect(result.tokens.count == 42)
}
```

- **Swift Testing** (new): `@Test` attribute, `#expect` macro, async/throws support
- **Snapshot testing**: `pointfreeco/swift-snapshot-testing` — uses `NSHostingController` on macOS
- **UI testing**: XCTest UI testing framework

---

## 9. Decision Framework

### Framework Selection Matrix

| Scenario | Recommended | Rationale |
|---|---|---|
| macOS-only, Swift team | **SwiftUI** | Full integration, Liquid Glass, future-proof |
| macOS-only, no Swift experience | **SwiftUI** (learn/hire) | Long-term non-native maintenance costs are higher |
| Cross-platform, web team | **Tauri 2.0** | 8.6 MB binary, WebKit on macOS, growing ecosystem |
| Cross-platform, large Node ecosystem | **Electron** | Proven at scale, consistent rendering |
| 120fps rendering IS the product | **Rust + GPUI/Metal** | Only for frame-rate-critical display |
| CLI wrapper (like Conductor) | **SwiftUI** | Native window mgmt, menu bar, system integration |

### Timeline Estimates

| Framework | Working Prototype | Polished, Native-Feeling |
|---|---|---|
| SwiftUI (new to Swift) | 1–2 weeks | 2–4 months |
| Tauri (web skills) | Days | 6–10 weeks |
| Electron (web skills) | Days | 4–8 weeks (never fully native) |
| Rust + Metal custom | 3–6 months (framework only) | 12–18 months |

---

## 10. Open-Source References Worth Studying

| Project | Stack | What to Learn |
|---|---|---|
| [CodeEdit](https://github.com/CodeEditApp/CodeEdit) | SwiftUI + AppKit | IDE-class app architecture, window management |
| [Cork](https://github.com/buresdv/Cork) | SwiftUI | Clean SwiftUI macOS patterns |
| [Zed](https://github.com/zed-industries/zed) | Rust + GPUI | Custom GPU rendering framework |
| [GPUI Components](https://crates.io/crates/gpui-component) | Rust | 60+ pre-built GPU-rendered widgets |
| [Conductor](https://github.com/MeriaApp/conductor) | SwiftUI | CLI wrapper with native UI |
| [Swiftcord](https://github.com/SwiftcordApp/Swiftcord) | SwiftUI | Discord client — real-world SwiftUI macOS app |
| [LiquidGlassReference](https://github.com/conorluddy/LiquidGlassReference) | Swift | Liquid Glass API reference and patterns |
| [awesome-swift-macos-apps](https://github.com/jaywcjlove/awesome-swift-macos-apps) | — | Curated list of open-source macOS Swift apps |
| [swiftui-macos-resources](https://github.com/stakes/swiftui-macos-resources) | — | SwiftUI macOS-focused examples |

---

## 11. Known Gaps and Caveats

1. **Liquid Glass production stability**: Developer beta (WWDC June 2025). Edge cases with custom `NSWindow` subclasses and older Apple Silicon are undocumented.
2. **Tauri universal binary codesigning**: Double-codesigning issue for arm64+x86_64 macOS builds noted as unresolved in late 2025.
3. **GPUI third-party adoption**: Powers Zed in production but external adoption is new and community patterns are limited.
4. **SwiftUI macOS vs iOS gap**: macOS list rendering is measurably slower than iOS for equivalent workloads. Known, unfixed.
5. **SwiftData API stability**: Production-ready but some practitioners warn the API "is expected to drastically change." Core Data's 15-year stability is a legitimate argument for complex persistence.

---

## Sources & References

### SwiftUI & macOS Development
- [SwiftUI for Mac 2025 - TrozWare](https://troz.net/post/2025/swiftui-mac-2025/)
- [SwiftUI 2025: What's Fixed, What's Not](https://juniperphoton.substack.com/p/swiftui-2025-whats-fixed-whats-not)
- [SwiftUI vs AppKit vs Mac Catalyst](https://www.hendoi.in/blog/swiftui-vs-appkit-vs-mac-catalyst-which-framework-us-startup-choose-macos-app)
- [@Observable Macro - Jesse Squires](https://www.jessesquires.com/blog/2024/09/09/swift-observable-macro/)
- [SwiftData vs Core Data 2025](https://distantjob.com/blog/core-data-vs-swiftdata/)
- [Tips for Lazy Containers - Fatbobman](https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
- [How to Build macOS Apps with SwiftUI](https://oneuptime.com/blog/post/2026-02-02-swiftui-macos-applications/view)
- [Modern MVVM in SwiftUI 2025](https://medium.com/@minalkewat/modern-mvvm-in-swiftui-2025-the-clean-architecture-youve-been-waiting-for-72a7d576648e)

### Design & UI
- [Apple Human Interface Guidelines - macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- [Get to know the new design system - WWDC25](https://developer.apple.com/videos/play/wwdc2025/356/)
- [Build a SwiftUI app with the new design - WWDC25](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Liquid Glass Best Practices](https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo)
- [iOS 26 Liquid Glass Reference](https://github.com/conorluddy/LiquidGlassReference)
- [Build a macOS SwiftUI App with Tahoe-Style Liquid Glass](https://medium.com/@dorangao/build-a-macos-swiftui-app-with-a-tahoe-style-liquid-glass-ui-fecb8029b2d8)
- [macOS Tahoe Developer's Ultimate Guide](https://macos-tahoe.com/blog/macos-tahoe-developer-ultimate-guide-2025/)
- [Vibrancy on macOS - Ohanaware](https://ohanaware.com/swift/macOSVibrancy.html)

### Tauri
- [Tauri 2.0 Official](https://v2.tauri.app/)
- [Tauri vs Electron - DoltHub](https://www.dolthub.com/blog/2025-11-13-electron-vs-tauri/)
- [Tauri vs Electron - Hopp App](https://www.gethopp.app/blog/tauri-vs-electron)
- [Why Tauri over Electron - Aptabase](https://aptabase.com/blog/why-chose-to-build-on-tauri-instead-electron)
- [Tauri macOS Bundle](https://v2.tauri.app/distribute/macos-application-bundle/)

### Electron
- [Making Electron Feel Native on Mac](https://dev.to/vadimdemedes/making-electron-apps-feel-native-on-mac-52e8)
- [Electron Official](https://www.electronjs.org/)

### Custom Rendering
- [How Warp Works](https://www.warp.dev/blog/how-warp-works)
- [Why is Building UI in Rust So Hard? - Warp](https://www.warp.dev/blog/why-is-building-a-ui-in-rust-so-hard)
- [GPUI Technical Overview](https://beckmoulton.medium.com/gpui-a-technical-overview-of-the-high-performance-rust-ui-framework-powering-zed-ac65975cda9f)

### Distribution
- [Code Signing, Notarization, Sparkle - Peter Steinberger (2025)](https://steipete.me/posts/2025/code-signing-and-notarization-sparkle-and-tears)
- [Sparkle Documentation](https://sparkle-project.org/documentation/)
- [Escaping the Mac App Store - Fatbobman](https://fatbobman.com/en/posts/zipic-2-selling-and-distribution)
- [macOS Distribution Guide - rsms](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5)

### Architecture
- [TCA 3-Year Experience](https://rodschmidt.com/posts/composable-architecture-experience/)
- [Clean Architecture for SwiftUI](https://nalexn.github.io/clean-architecture-swiftui/)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Reference Apps
- [Conductor - GitHub](https://github.com/MeriaApp/conductor)
- [CodeEdit - GitHub](https://github.com/CodeEditApp/CodeEdit)
- [Raycast API & Extensions](https://www.raycast.com/blog/how-raycast-api-extensions-work)
- [Awesome Swift macOS Apps](https://github.com/jaywcjlove/awesome-swift-macos-apps)
