# Modern macOS Desktop App Development: Deep Research Report

## Summary

Building a polished, native-feeling macOS desktop app in 2025-2026 is firmly viable with SwiftUI as the primary framework, with targeted AppKit bridges for the remaining gaps. SwiftUI has crossed a maturity threshold—10,000-item list performance, native WebView, AttributedString in TextEditor, and new window scene types are production-ready. macOS Tahoe (26) introduces the Liquid Glass design language with first-class SwiftUI APIs. For teams without Swift expertise, Tauri 2.0 is the credible alternative: 8.6 MB binary, ~40 MB idle RAM, and native WKWebView on macOS—but it requires Rust for anything beyond basic plugins. Electron remains viable for large web-dev teams but carries a 244 MB binary and 400+ MB RAM baseline. Custom Rust+Metal (Warp/Zed approach) is only justified for frame-rate-critical rendering. Confidence: **High** across most areas; **Medium** for Liquid Glass adoption maturity (WWDC 2025, still in beta rollout).

---

## Findings

### 1. Native SwiftUI macOS Development

#### 1.1 Maturity Status in 2025-2026

SwiftUI on macOS is production-ready for the majority of applications. The key improvements since macOS 14:

**What now works without AppKit:**
- `List` with 10,000+ items—described as "snappy" in independent testing [1]
- `TextEditor` with `AttributedString` (bold, italic, underline, font size)—rich text no longer requires AppKit [1]
- `WebView(url:)` — native, no `NSViewRepresentable` around `WKWebView` needed (requires Outgoing Connections capability) [1]
- Inspector panels (`.inspector(isPresented:)`) — trailing sidebar on macOS since macOS 14
- `MenuBarExtra` scene type — persistent menu bar controls in pure SwiftUI
- `UtilityWindow` — floating panels that don't steal focus

**What still requires AppKit bridges:**
- Advanced font picker dialogs (no programmatic API in `TextEditor`) [1]
- Real-time spell checking (erratic in `TextEditor`) [1]
- Large text volume rendering for chat-style UIs — `NSTextView` via `NSViewRepresentable` still outperforms SwiftUI `Text` for streaming content [2]
- `UICollectionView`-equivalent performance for photo grids at scale [2]
- Multi-gesture tracking (CAShapeLayer-level precision) [2]
- Programmatic removal of the sidebar toggle button in `sidebarAdaptable` tab layouts [1]

**Practical recommendation:** Start with SwiftUI for all UI. Profile and surgically replace hot paths with `NSViewRepresentable` wrappers. Do not start with AppKit and bridge SwiftUI in—the inverse is significantly harder to maintain.

#### 1.2 Navigation Patterns

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
// Persist sidebar state per window
.onChange(of: columnVisibility) { _ = $sceneStorage }
```

Key patterns:
- `NavigationSplitView` — recommended over `NavigationView` for multi-column layouts. Inspector attaches to the detail column and renders as a trailing sidebar on macOS [3].
- `@SceneStorage` — persists sidebar `columnVisibility` automatically per window instance.
- `.windowLevel(.floating)` — makes a window always-on-top without UIKit/AppKit code.
- In macOS Tahoe 26, `NavigationSplitView` sidebars automatically receive Liquid Glass appearance [3].

**Gotcha:** Combining `NavigationSplitView` with the `.inspector` modifier has reported layout issues in some configurations. Test thoroughly.

#### 1.3 State Management: @Observable vs ObservableObject

Prefer `@Observable` (Swift 5.9+, iOS 17+/macOS 14+) for all new code:

```swift
@Observable
class ProjectViewModel {
    var files: [File] = []
    var selectedFile: File?
    // No @Published needed — all properties are automatically tracked
}

// In view:
@State private var viewModel = ProjectViewModel()  // NOT @StateObject
```

Key behavioral difference: `@ObservableObject` re-renders the entire view when *any* published property changes. `@Observable` re-renders only views that *read* the changed property—a critical distinction for large list performance [4].

**SwiftData vs Core Data (2025):**
- SwiftData is production-ready on macOS 14+ but is built on Core Data internally (same SQLite engine, comparable performance at scale) [5].
- SwiftData is the right choice for new macOS 14+ targeted apps. Core Data for: pre-14 targets, complex migration needs, public CloudKit databases, or existing Core Data codebases.
- Hybrid is feasible—run both side-by-side during incremental migration.

**SwiftData requires `@Observable`** — not `ObservableObject`.

#### 1.4 List and Lazy Container Performance

Critical gotchas for large data sets [6]:

1. **`List` vs `LazyVStack`**: `List` recycles off-screen cells (memory-efficient). `LazyVStack` loads lazily but doesn't release (accumulates memory). For 10k+ items, prefer `List`.

2. **The `id` modifier problem**: Adding `.id(someValue)` to `List` row views forces all rows to instantiate immediately, destroying lazy loading. Safe to use in `LazyVStack`/`LazyHGrid`, not `List`.

3. **Conditional content breaks laziness**: `if`/`switch` inside `List` body produces `_ConditionalContent` which forces all rows to instantiate. Wrap in `VStack` inside the row view instead.

4. **Memory release**: Setting `Image` state to `nil` inside lazy containers doesn't immediately free memory. Use `Data` type for image storage in lazy contexts.

5. **Performance on macOS vs iOS**: macOS SwiftUI list rendering is slower than iOS. If you're hitting limits, `LazyVStack` in `ScrollView` can outperform `List` for pure display (no selection, swipe actions), despite higher memory footprint.

#### 1.5 Window Management

SwiftUI scene types available for macOS:

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands { MyCommands() }

        // Floating utility panel (new in macOS 15)
        UtilityWindow("Diagnostics", id: "diagnostics") {
            DiagnosticsView()
        }

        // Menu bar utility
        MenuBarExtra("Agent Status", systemImage: "circle.fill") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)  // or .menu

        Settings {
            SettingsView()
        }
    }
}
```

`UtilityWindow` properties: floats above other windows, doesn't steal focus on open, dismisses with Escape, hides when app deactivates.

#### 1.6 Open-Source SwiftUI macOS Apps Worth Studying

- **CodeEdit** (`CodeEditApp/CodeEdit`, ~23k stars) — pure macOS SwiftUI code editor, components extracted as reusable SPM packages [7]
- **Cork** — macOS Homebrew UI, exemplary use of NavigationSplitView
- **Mango** — MenuBarExtra patterns

---

### 2. macOS UI/UX Design Language

#### 2.1 Apple HIG Core Principles

Three foundational principles [8]:
- **Clarity**: Legible text, precise icons, meaningful negative space
- **Deference**: UI defers to content; minimize decoration that doesn't serve the user
- **Depth**: Layering and motion convey hierarchy

**2025 additions for macOS Tahoe:**
- Sidebars: inset, Liquid Glass material, content scrolls beneath them
- Toolbars: automatically group buttons on a single glass surface; remove background colors
- Inspector panels: dense `Mini`/`Small` controls using rounded rectangles, not glass [8]

#### 2.2 Liquid Glass (macOS Tahoe / iOS 26)

Introduced at WWDC 2025. The material uses "lensing"—bending and concentrating light rather than scattering it—as a physical metaphor. **Confidence: Medium** (public beta as of July 2025, developer beta from June 2025).

**SwiftUI APIs:**

```swift
// Basic glass effect
myView
    .glassEffect()                    // .regular variant (default)
    .glassEffect(.regular)
    .glassEffect(.clear)

// Button styles
Button("Edit") { }
    .buttonStyle(.glass)              // secondary action
Button("Save") { }
    .buttonStyle(.glassProminent)     // primary action, accepts tint

// CRITICAL: Use GlassEffectContainer when multiple glass elements share space
GlassEffectContainer(spacing: 30) {
    HStack {
        Button("Edit") { }.glassEffect()
        Button("Share") { }.glassEffect()
    }
}

// Morphing transitions between glass elements
.glassEffectID("toolbar-button", in: namespace)

// AppKit
button.bezelStyle = .glass
button.bezelColor = .systemBlue
```

**Apply glass to:** toolbars, tab bars, sidebars, floating action buttons, sheets, popovers, menus [9].

**Never apply glass to:** content layers (lists, cards, tables), full-screen backgrounds, multiple nested glass elements of different variants [9].

**Accessibility**: Reduce Transparency, Increase Contrast, and Reduce Motion adaptations are automatic—no additional code required [9].

#### 2.3 Vibrancy and Materials

For macOS 14 and earlier (pre-Liquid Glass):

```swift
// SwiftUI — automatic for sidebars, inspectors, sheets
List(items) { ... }
    .listStyle(.sidebar)  // Gets vibrancy automatically

// Manual material background
VStack { ... }
    .background(.ultraThinMaterial)  // or .thickMaterial, .regularMaterial

// AppKit bridge for fine-grained control
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
```

Critical distinction: SwiftUI `.background(.ultraThinMaterial)` blends *application window content*. `NSVisualEffectView` with `.behindWindow` blending mode blends what's *behind the window* (desktop, other apps). Choose based on design intent [10].

**Do not:** hardcode `NSAppearance` names to fix vibrancy holes—it bypasses Dark Mode and Reduce Transparency. Investigate the root cause instead [10].

#### 2.4 Typography

- SF Pro is the system font on macOS. macOS does **not** support Dynamic Type (iOS feature). Instead, use dynamic system font variants that match standard controls.
- macOS 11+ merges discrete optical sizes (Text/Display) into a continuous design via dynamic optical sizing.
- The system automatically adjusts tracking at each point size—do not manually set tracking on system font text.
- Use `Font.system(.body)`, `.headline`, `.caption` etc. for semantic sizing.

#### 2.5 Animation

Recommended by use case [11]:

| Use Case | API |
|---|---|
| Simple state-driven property changes | `withAnimation(.spring)` in SwiftUI |
| Multi-property sequences with precise timing | `keyframeAnimator` (macOS 14+) |
| Hero/shared-element transitions between views | `matchedGeometryEffect` |
| Existing AppKit views | `CABasicAnimation` / `NSAnimator` |
| Precise GPU-level control | Metal / `CAMetalLayer` |

```swift
// matchedGeometryEffect — hero animation pattern
@Namespace private var animation

// Source view
Image(systemName: "folder")
    .matchedGeometryEffect(id: item.id, in: animation)

// Destination view
Image(systemName: "folder")
    .resizable()
    .matchedGeometryEffect(id: item.id, in: animation)
```

Liquid Glass includes built-in `.interactive()` modifier for touch/click feedback (scale, bounce, shimmer).

#### 2.6 SF Symbols

SF Symbols 6 (macOS 15+) provides 6,000+ symbols with automatic weight/scale matching to adjacent text. Use `Label` in menus—it correctly handles both the symbol and text layout. Avoid custom images where an SF Symbol covers the concept.

---

### 3. Tauri 2.0 for macOS

#### 3.1 Architecture

Tauri 2.0 (released late 2024) architecture:
- **Rust backend**: process lifecycle, system APIs, file I/O, native plugin layer
- **Web frontend**: any JS framework (React, Vue, Svelte); runs in system WebView
- **macOS WebView**: WKWebView (WebKit/Safari engine)
- **IPC**: message-passing via Tauri commands (not Node.js IPC)

#### 3.2 Performance Numbers (Benchmarked) [12]

| Metric | Tauri | Electron |
|---|---|---|
| Binary size | **8.6 MB** | 244 MB |
| Idle RAM (6 windows) | **~172 MB** | ~409 MB |
| Startup time | ~0.5–1s | ~2–4s |
| Initial build time | ~80s (Rust compile) | ~15s |

The binary size advantage is decisive for download/distribution. Memory advantage matters for apps users keep open all day.

#### 3.3 macOS Native Feel Capabilities

**Vibrancy:**
```rust
// Rust side (in setup)
use window_vibrancy::{apply_vibrancy, NSVisualEffectMaterial};
apply_vibrancy(&window, NSVisualEffectMaterial::HudWindow, None, None)?;

// macOS Tahoe Liquid Glass (window-vibrancy 0.5+)
apply_liquid_glass(&window)?;
```

**Transparent titlebar:**
```rust
// tauri.conf.json
{
  "windows": [{
    "titleBarStyle": "Transparent",
    "transparent": true
  }]
}
```

**Gotcha**: Custom titlebars lose system features (window alignment, double-click to zoom). Use `TitleBarStyle::Transparent` (keeps traffic lights) rather than fully custom titlebars where possible [13].

**System tray, notifications, file associations, drag-and-drop, deep links**: all supported via Tauri plugins.

#### 3.4 Known macOS-Specific Issues

- Universal binary (arm64 + x86_64) creation causes double codesigning issues; workaround exists but adds CI complexity [14]
- WebKit-only rendering means CSS/JS behaviors may diverge from Chrome—test against Safari, not Chrome
- Some CSS features (backdrop-filter performance, certain font rendering) differ between WKWebView and Chromium

#### 3.5 When to Choose Tauri

- Web-dev team that needs native-like feel and performance
- App with Rust backend requirements (audio, video, WebRTC, native binaries)
- When binary size and startup time are marketing requirements
- Cross-platform (macOS + Windows + Linux) from a single codebase
- **Not**: when you need macOS-only deep integration (e.g., full Liquid Glass, precise NSWindow customization, tight sandboxing for MAS)

---

### 4. Electron for macOS

#### 4.1 State in 2025

Electron remains dominant for cross-platform apps from web teams (VS Code, Slack, Discord, Figma, Linear). Its advantages are ecosystem depth and zero context-switching for JS teams.

**Honest disadvantages in 2025:**
- 244 MB minimum binary; 400+ MB RAM at idle [12]
- No access to WKWebView on macOS—Chromium only; misses Safari-engine native feel
- Battery drain on MacBooks (multiple renderer processes)
- Increasing competition from Tauri and Flutter

#### 4.2 Techniques to Make Electron Feel Native on macOS [15]

```javascript
// 1. Hidden titlebar with native traffic lights
const win = new BrowserWindow({
  titleBarStyle: 'hidden',       // keeps traffic light buttons
  // OR: 'hiddenInset' for more inset
  trafficLightPosition: { x: 16, y: 16 }
})

// 2. Prevent blank flash on startup
win.once('ready-to-show', () => win.show())

// 3. Dark mode reactive background
nativeTheme.on('updated', () => {
  win.setBackgroundColor(
    nativeTheme.shouldUseDarkColors ? '#1a1a1a' : '#ffffff'
  )
})

// 4. Window state persistence
const windowState = windowStateKeeper({ defaultWidth: 1280, defaultHeight: 800 })
```

**CSS patterns:**
```css
/* System font */
body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 13px; }

/* Draggable titlebar region */
.titlebar { -webkit-app-region: drag; }
.titlebar-button { -webkit-app-region: no-drag; }

/* Non-selectable UI chrome */
.sidebar { user-select: none; cursor: default; }
```

**Focus state desaturation** (apps like Finder grey out when unfocused):
```javascript
// Main process
win.on('focus', () => win.webContents.send('focus', true))
win.on('blur', () => win.webContents.send('focus', false))
```

#### 4.3 Electron Alternatives

- **Neutralino.js**: Lighter than Electron (no Node.js runtime), uses OS webview like Tauri but less mature ecosystem
- **Wails** (Go): Tauri equivalent for Go backends, macOS WebKit
- **Flutter**: Google's cross-platform framework, native rendering, growing macOS support—viable for design-system-heavy apps

---

### 5. Custom Rendering: Rust + Metal (GPUI / Warp Approach)

#### 5.1 The Warp Architecture [16]

Warp chose Rust + Metal after briefly evaluating Electron. Core architecture:

1. **Rendering layer**: Three primitives only—rectangles, images, glyphs (via texture atlas). ~200 lines of Metal shader code.
2. **Composition layer**: Primitives compose into higher-level elements (snackbar, context menu, block)
3. **UI framework layer**: Entity-Component-System (ECS) model—centralized ownership via `EntityId`, avoiding Rust ownership conflicts with traditional component tree models
4. **Performance**: 144+ FPS on 4K, 1.9ms average screen redraw

**Why ECS over component trees:**
Rust's single-ownership model conflicts with traditional UI parent-child mutation patterns. ECS sidesteps this by having the framework own all components via ID references, not direct pointers.

**Tradeoffs accepted:**
- No hot-reloading (Rust compile cycle)
- Tree traversal less intuitive than React-style component models
- `RefCell` runtime borrow panics in some concurrent scenarios

#### 5.2 GPUI (Zed Editor)

GPUI is Zed's open-source GPU-accelerated UI framework in Rust [17]:
- Uses Metal on macOS for rendering
- Targets 120 FPS
- State managed via `AppContext`-owned models
- Available as `gpui` crate on crates.io
- `gpui-component` library (~60+ components)

#### 5.3 Rust GUI Landscape Comparison

| Framework | Model | macOS Backend | Maturity |
|---|---|---|---|
| GPUI (Zed) | Retained + GPU | Metal | Production (Zed ships it) |
| egui | Immediate mode | wgpu/Metal | Stable, actively developed |
| iced | Elm-inspired retained | wgpu/Metal | Beta, growing |
| Tauri (web layer) | Web + Rust backend | WKWebView | Production (2.0 stable) |

#### 5.4 When Custom Rendering Makes Sense

Only pursue custom Rust+Metal when:
- Frame-rate-critical display (terminal emulator, code editor with 120fps scrolling)
- Rendering is the primary product differentiator
- You have 6–12 months to invest in framework infrastructure
- Cross-platform rendering consistency is more important than native OS widget feel

For everything else: SwiftUI (native) or Tauri (web teams) are lower-risk.

---

### 6. Distribution and Shipping

#### 6.1 Mac App Store vs Direct Distribution

| Factor | Mac App Store | Direct (Developer ID) |
|---|---|---|
| Sandbox required | Yes (mandatory) | Optional |
| File system access | Restricted, entitlement-gated | Unrestricted |
| Review cycle | 1–7 days | None (notarization: ~minutes) |
| Revenue split | 30% (15% for small devs) | 100% |
| Auto-updates | Built-in | Manual (Sparkle) |
| Trial support | None | Full control |
| Paid upgrades | Not supported | Full control |
| Discovery | App Store search | SEO / word of mouth |

**Verdict**: Direct distribution is better for power-user developer tools (like Conductor). MAS is better for consumer apps needing discovery. Many apps ship both [18].

#### 6.2 Notarization Workflow

Notarization is required for both channels since macOS Catalina. The workflow:

```bash
# 1. Archive in Xcode → Product > Archive
# 2. Distribute with Developer ID method (Xcode handles signing)

# 3. Or via CLI:
xcodebuild -exportArchive \
  -archivePath MyApp.xcarchive \
  -exportPath ./build \
  -exportOptionsPlist ExportOptions.plist

# 4. Notarize
xcrun notarytool submit MyApp.dmg \
  --apple-id "you@example.com" \
  --team-id "TEAM_ID" \
  --password "@keychain:AC_PASSWORD" \
  --wait

# 5. Staple
xcrun stapler staple MyApp.dmg
```

#### 6.3 Sparkle Auto-Update Setup

Sparkle is the standard for direct-distributed macOS auto-updates. Critical requirements [19]:

**Never use `--deep` for codesigning.** Sign in this order:
1. XPC service bundles first (`Sparkle.framework/Versions/B/XPCServices/`)
2. Sparkle framework
3. App bundle last (without `--deep`)

**Required entitlements for Sparkle XPC:**
```xml
<key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
<array>
    <string>com.yourcompany.yourapp-spks</string>  <!-- InstallerLauncher -->
    <string>com.yourcompany.yourapp-spki</string>  <!-- Installer -->
</array>
```

**Appcast versioning**: Sparkle uses `CFBundleVersion` (build number), not `CFBundleShortVersionString` (marketing version). Build numbers must always increment.

**Update distribution**: GitHub Releases + raw GitHub URLs for appcast.xml works well for indie developers—eliminates hosting costs [19].

#### 6.4 DMG Creation

Tools: **DMG Canvas** (GUI, handles notarization pipeline) or **create-dmg** (CLI, CI-friendly):

```bash
create-dmg \
  --volname "MyApp" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "MyApp.app" 200 190 \
  --app-drop-link 600 185 \
  "MyApp-1.0.0.dmg" \
  "build/MyApp.app"
```

#### 6.5 Build Tooling

**XcodeGen** (`yonaskolb/XcodeGen`) — YAML-driven `.xcodeproj` generation. Eliminates merge conflicts in project files. Used by Conductor. Pattern:
```yaml
# project.yml
name: MyApp
targets:
  MyApp:
    type: application
    platform: macOS
    deploymentTarget: "14.0"
    sources: [Sources]
    dependencies:
      - package: SomeSPMPackage
```

**Fastlane** for CI/CD automation: `build_app`, `run_tests`, `notarize`. Cache SPM packages with `clonedSourcePackagesDirPath` to avoid re-downloading on CI.

---

### 7. Project Architecture and Tooling

#### 7.1 Architecture Patterns

**@Observable + environment injection** (preferred for most apps):
```swift
@Observable class AppState {
    var selectedProject: Project?
    var settings: Settings = Settings()
}

// App level
@State private var appState = AppState()
ContentView()
    .environment(appState)

// Any descendant view
@Environment(AppState.self) private var appState
```

**TCA (The Composable Architecture)** — choose when:
- State spans multiple screens and must be testable in isolation
- You need time-travel debugging
- Team is experienced with Redux/Elm patterns
- Long-term: scalability outweighs onboarding cost [20]

**TCA tradeoffs:**
- Significant learning curve (reducer protocol, effects, stores)
- Fights SwiftUI's natural data flow in some cases
- Recent versions (1.x) integrate `@Observable`, improving ergonomics

**Verdict**: For a small team building a focused developer tool (like Conductor), `@Observable` + environment + feature-level view models is simpler and sufficient. Reach for TCA if you need strong cross-module state testing guarantees.

#### 7.2 Testing

**Swift Testing framework** (Swift 5.10+, Xcode 16) — modern replacement for XCTest:
```swift
import Testing

@Test func parseClaudeOutput() async throws {
    let result = try await parser.parse(sampleOutput)
    #expect(result.tokens.count == 42)
}

@Suite("Output parsing") struct ParserTests {
    @Test("handles empty input")
    func emptyInput() { ... }
}
```

**Snapshot testing** — `pointfreeco/swift-snapshot-testing` (supports Swift Testing as of v1.17.0 in beta). Necessary for SwiftUI because you cannot inspect the view tree at runtime:
```swift
assertSnapshot(of: MyView(), as: .image(size: CGSize(width: 800, height: 600)))
```

For macOS, use `NSHostingController` instead of `UIHostingController` when bridging to the snapshot framework.

#### 7.3 Swift Package Manager

SPM is the correct dependency manager for macOS apps in 2025—CocoaPods is legacy. Define dependencies in `project.yml` (XcodeGen) or directly in `Package.swift` for library targets. `xcodebuild` resolves SPM packages automatically during build; no pre-resolution step needed in CI.

---

### 8. Decision Framework

#### 8.1 Framework Selection Matrix

| Scenario | Recommended | Rationale |
|---|---|---|
| macOS-only app, Swift team | **SwiftUI** | Full platform integration, Liquid Glass, future-proof |
| macOS-only, mixed/no Swift experience | **SwiftUI** still — hire or learn | Long-term maintenance costs of non-native are higher |
| Cross-platform (mac + win + linux), web team | **Tauri 2.0** | 35% YoY adoption growth, native WebKit on macOS |
| Cross-platform, large JS ecosystem dependency | **Electron** | Proven at scale, Node.js ecosystem, consistency |
| Terminal/editor with 120fps rendering requirement | **Rust + GPUI/Metal** | Only justified for frame-rate-critical display |
| Prototype / validate product fast | **Electron** | Fastest initial iteration for web teams |
| Developer tool wrapping a CLI (like Conductor) | **SwiftUI** | Native integration, window management, menu bar |

#### 8.2 Team Skill Implications

- **Swift team of 2+**: SwiftUI is the clear choice. Ramp-up time for macOS-specific patterns is days, not weeks.
- **Web-only team**: Tauri is better than Electron for new apps in 2026. Basic Tauri requires minimal Rust—most logic lives in JS. Rust becomes necessary only for custom plugins and performance-critical backend code.
- **Go team**: Wails is the Tauri equivalent—Go backend, WebKit on macOS.
- **No dedicated team**: Consider Electron+React if you must ship fast. Technical debt is real but shippable.

#### 8.3 Timeline and Budget

| Framework | Time to first working prototype | Time to polished, native-feeling app |
|---|---|---|
| SwiftUI | 1–2 weeks (new to Swift) | 2–4 months |
| Tauri | Days (web skills) | 6–10 weeks |
| Electron | Days (web skills) | 4–8 weeks (never fully "native") |
| Rust+Metal custom | 3–6 months (framework only) | 12–18 months |

#### 8.4 Cross-Platform Assessment

If shipping macOS-only: **SwiftUI, no contest**. If needing Windows/Linux too:
- Tauri 2.0 gives you a 90% native-feeling macOS app with cross-platform capability
- Electron gives you a 70–80% native-feeling macOS app with broader ecosystem and faster CI
- Flutter is an emerging third option with strong design system support

#### 8.5 Long-Term Maintenance

- **SwiftUI**: Apple actively invests; API improvements every WWDC. Breaking changes are rare and well-communicated. SwiftUI 6 (macOS 15) is a major improvement.
- **Tauri**: Rapid growth, 2.0 is stable. Rust ecosystem still maturing. Windows/Linux parity sometimes lags macOS.
- **Electron**: Stable, large community, but no fundamental architecture improvements on the horizon. Resource consumption will remain a criticism.
- **Custom Rust+Metal**: You own the framework. Bug fixes, platform API changes (Metal API updates, new macOS window behaviors) are your team's responsibility.

---

## Conflicting Information

1. **SwiftUI list performance on macOS**: Apple's own developer forums from 2021-2022 documented severe performance issues. Independent testing from 2025 [1] reports 10,000-item lists as "snappy." This is a genuine improvement, but macOS SwiftUI still performs slower than iOS SwiftUI for equivalent lists—confirmed across multiple sources.

2. **Tauri startup time**: Some sources claim "negligible" startup time difference vs Electron [12]; others cite 0.5s vs 2–4s advantage. The discrepancy likely depends on app complexity. Both agree Tauri is faster.

3. **SwiftData production readiness**: Sources agree it's stable on iOS 17+/macOS 14+, but some warn the API "is expected to drastically change" in future releases. Core Data's 15-year stability record is a legitimate counterargument for complex persistence needs.

---

## Knowledge Gaps

1. **Liquid Glass on macOS Tahoe production stability**: The API was announced at WWDC June 2025 with developer beta. Final behavior on production hardware and edge cases (e.g., interaction with custom `NSWindow` subclasses, performance on older Apple Silicon) is not yet fully documented.

2. **Tauri 2.0 universal binary CI**: The double-codesigning issue for macOS universal binaries (arm64 + x86_64) was noted as unresolved in late 2025. Current status of official fix is unclear.

3. **GPUI external adoption maturity**: While GPUI powers Zed in production, `gpui-component` for third-party apps is newer (~2024). Real-world adoption outside Zed is limited.

4. **SwiftUI + Metal shader integration**: macOS Tahoe supports Metal shaders directly in SwiftUI animations, but production patterns and performance ceiling are not yet well-documented in community resources.

---

## Sources

1. [SwiftUI for Mac 2025 - TrozWare](https://troz.net/post/2025/swiftui-mac-2025/) — Author maintains a macOS SwiftUI app; detailed first-hand testing of new APIs
2. [SwiftUI 2025: What's Fixed, What's Not - JuniorPhoton/Substack](https://juniperphoton.substack.com/p/swiftui-2025-whats-fixed-whats-not) — Developer of PhotonCam camera app; practical hybrid UIKit+SwiftUI approach
3. [Presenting an Inspector with SwiftUI - CreateWithSwift](https://www.createwithswift.com/presenting-an-inspector-with-swiftui/) — Community tutorial on NavigationSplitView + inspector patterns
4. [@Observable vs ObservableObject - Jesse Squires](https://www.jessesquires.com/blog/2024/09/09/swift-observable-macro/) — Nuanced comparison of behavioral differences; respected iOS/macOS developer
5. [SwiftData vs Core Data: Which Should You Use in 2025? - DistantJob](https://distantjob.com/blog/core-data-vs-swiftdata/) — Comparative analysis with migration guidance
6. [Tips for Lazy Containers in SwiftUI - Fatbobman](https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/) — Highly detailed technical analysis of lazy container edge cases
7. [CodeEdit App - GitHub](https://github.com/CodeEditApp/CodeEdit) — Production SwiftUI macOS app; open source reference implementation
8. [Get to know the new design system - WWDC25](https://developer.apple.com/videos/play/wwdc2025/356/) — Apple first-party; authoritative for Tahoe design language
9. [Liquid Glass in Swift: Official Best Practices - DEV Community](https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo) — Synthesizes Apple WWDC documentation with code examples
10. [Vibrancy, NSAppearance, and Visual Effects - Philz Blog](https://philz.blog/vibrancy-nsappearance-and-visual-effects-in-modern-appkit-apps/) — Deep technical dive into macOS appearance system
11. [Through the Ages: Apple Animation APIs - Jacob Bartlett](https://blog.jacobstechtavern.com/p/through-the-ages-apple-animation) — Historical and practical guide to Apple animation API evolution
12. [Tauri vs. Electron: performance, bundle size - Hopp App Blog](https://www.gethopp.app/blog/tauri-vs-electron) — Concrete benchmark numbers from a real app migration
13. [Window Customization - Tauri v2 Docs](https://v2.tauri.app/learn/window-customization/) — Official Tauri documentation
14. [Electron vs. Tauri - DoltHub Blog](https://www.dolthub.com/blog/2025-11-13-electron-vs-tauri/) — Real-world migration experience with macOS-specific pain points documented
15. [Making Electron Apps Feel Native on Mac - DEV Community](https://dev.to/vadimdemedes/making-electron-apps-feel-native-on-mac-52e8) — Widely cited practical guide; specific API patterns
16. [How Warp Works - Warp Blog](https://www.warp.dev/blog/how-warp-works) — First-party technical architecture post from Warp team
17. [GPUI - Technical Overview - Beck Moulton/Medium](https://beckmoulton.medium.com/gpui-a-technical-overview-of-the-high-performance-rust-ui-framework-powering-zed-ac65975cda9f) — Technical analysis of Zed's GPUI framework
18. [Escaping the Mac App Store - Fatbobman](https://fatbobman.com/en/posts/zipic-2-selling-and-distribution) — First-hand account of full independent distribution stack setup
19. [Code Signing, Notarization, Sparkle and Tears - Peter Steinberger](https://steipete.me/posts/2025/code-signing-and-notarization-sparkle-and-tears) — 2025 hands-on debugging of Sparkle + notarization; specific entitlement patterns
20. [TCA: My 3 Year Experience - Rod Schmidt](https://rodschmidt.com/posts/composable-architecture-experience/) — Long-term practitioner perspective on TCA tradeoffs
21. [Tauri vs Electron 2025 - Raftlabs](https://www.raftlabs.com/blog/tauri-vs-electron-pros-cons/) — Aggregated comparison with adoption statistics
22. [Make your Mac app more accessible - WWDC25](https://developer.apple.com/videos/play/wwdc2025/229/) — Apple first-party; accessibility focus on macOS 26
23. [Why is building a UI in Rust so hard? - Warp Blog](https://www.warp.dev/blog/why-is-building-a-ui-in-rust-so-hard) — First-party post on ECS architecture decision for custom Rust UI
24. [Sparkle Documentation](https://sparkle-project.org/documentation/) — Official Sparkle framework docs
25. [Human Interface Guidelines - Apple Developer](https://developer.apple.com/design/human-interface-guidelines) — Authoritative Apple HIG; primary design reference
