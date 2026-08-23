# macOS in-app updates for Portu

Research date: 2026-08-11

Status: research only; no updater has been implemented or tested in Portu.

## Decision summary

**Recommendation (inference):** build a proof of concept with Sparkle 2, keep Portu's existing ad-hoc app signing, and make a separately generated Ed25519 key the update trust anchor. Publish a stable HTTPS appcast and point its enclosure at the existing GitHub Release DMG. Do not build a custom updater like Warp's.

**Verified:** Sparkle does not make Developer ID or notarization a hard requirement for an ordinary app-bundle update. Its validator accepts an update when either the archive verifies with the EdDSA key embedded in the old app or the new bundle matches the old Apple code-signing identity. The same source says ad-hoc signing can be used at minimum when an already signed app would otherwise update to an unsigned one. [Sparkle `SUUpdateValidator`](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SUUpdateValidator.m#L271-L375)

**Verified:** Sparkle nevertheless recommends HTTPS, Developer ID signing and notarization when possible, plus an EdDSA signature on every published archive. It supports DMG, ZIP, tar and Apple Archive app-bundle updates, generates RSS appcasts with `generate_appcast`, and uses `CFBundleVersion` to select newer builds. [Sparkle setup and publishing guide](https://sparkle-project.org/documentation/)

**Verified:** Apple does not accept ad-hoc signatures for the standard notarization workflow; directly distributed software must use Developer ID for that workflow. [Apple notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

**Inference:** Portu can therefore gain authenticated in-app updates without a paid Apple Developer account, but it cannot gain Apple's publisher identity, malware scan, notarization ticket, or Gatekeeper reputation. The updater's security would depend primarily on custody and continuity of the Sparkle Ed25519 private key.

**Important rollout constraint (inference):** an already installed Portu build has no updater code or embedded public key. Users must manually install the first Sparkle-enabled release once; only later releases can update it in-app.

## Portu's current release boundary

**Verified from this repository:** Portu is a non-App-Store macOS app whose release script builds a DMG with `CODE_SIGN_IDENTITY="-"`, sets the machine version from `GITHUB_RUN_NUMBER`, verifies the DMG, and uploads the DMG plus a SHA-256 file through semantic-release. It currently has no Sparkle dependency, `SUFeedURL`, or `SUPublicEDKey`. [Project definition](../../project.yml), [packaging script](../../scripts/package_release_dmg.sh), [semantic-release configuration](../../.releaserc.json), [release workflow](../../.github/workflows/release.yml), [Info.plist](../../Sources/Portu/Resources/Info.plist)

**Verified from this repository:** Portu's entitlements declare network client/server access but do not enable `com.apple.security.app-sandbox`, so Sparkle's sandbox-only XPC configuration is not currently required. [Project definition](../../project.yml), [Sparkle sandboxing guide](https://sparkle-project.org/documentation/sandboxing/)

**Inference:** the existing DMG can remain the release asset. Sparkle supports a DMG containing the replacement `.app`, so there is no inherent need to introduce a second ZIP artifact. A real Portu DMG still needs an end-to-end test because packaging details, permissions, quarantine state and nested helper signatures affect installation. [Sparkle publishing guide](https://sparkle-project.org/documentation/publishing/)

**Verified:** Sparkle requires an incrementing, properly formatted `CFBundleVersion`. Portu's CI run number is monotonic within the repository and is already written to `CURRENT_PROJECT_VERSION`, making it a suitable machine version; the semantic release version can remain the user-facing `CFBundleShortVersionString`. [Sparkle setup guide](https://sparkle-project.org/documentation/), [Portu packaging script](../../scripts/package_release_dmg.sh)

## Open-source implementations surveyed

| App | Updater and discovery | Artifact authentication | Installation and relaunch | Portu relevance |
| --- | --- | --- | --- | --- |
| [CodexBar](https://github.com/steipete/CodexBar) | Sparkle 2 through SwiftPM; `SPUStandardUpdaterController`; raw-GitHub appcast; stable/beta channels; automatic checks and downloads. [Package](https://github.com/steipete/CodexBar/blob/main/Package.swift#L41-L48), [controller](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBar/CodexbarApp.swift#L155-L328), [appcast](https://github.com/steipete/CodexBar/blob/main/appcast.xml) | Every enclosure has `sparkle:edSignature`; its production flow also uses Developer ID and notarization. [appcast](https://github.com/steipete/CodexBar/blob/main/appcast.xml), [release configuration](https://github.com/steipete/CodexBar/blob/main/.mac-release.env#L13-L30) | Saves Sparkle's prepared-install callback and exposes a restart/apply action once the update is ready. [controller](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBar/CodexbarApp.swift#L199-L328) | Useful UX and feed example, but **not directly reusable**: CodexBar explicitly disables in-app updates unless its installed bundle is Developer-ID signed. [guard](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBar/CodexbarApp.swift#L330-L366) |
| [Warp](https://github.com/warpdotdev/warp) | Custom Rust updater; polls Warp's version API, downloads a channel/architecture DMG from Warp's release service, and does not use Sparkle. [poll and version fetch](https://github.com/warpdotdev/warp/blob/master/app/src/autoupdate/mod.rs#L211-L278), [DMG download](https://github.com/warpdotdev/warp/blob/master/app/src/autoupdate/mac.rs#L512-L557) | Verifies both staged bundle and executable with `codesign`, requiring Warp's Apple Team ID. [signature verification](https://github.com/warpdotdev/warp/blob/master/app/src/autoupdate/mac.rs#L309-L331) | Mounts the DMG read-only, copies the app, atomically swaps bundles with `renamex_np`, preserves the running executable until shutdown, then relaunches using `open -n`. [install](https://github.com/warpdotdev/warp/blob/master/app/src/autoupdate/mac.rs#L350-L426), [relaunch](https://github.com/warpdotdev/warp/blob/master/app/src/autoupdate/mac.rs#L134-L168) | Strong reference for failure handling, but a poor fit: Portu has no Apple Team ID, and owning custom download, authorization, atomic replacement and relaunch code would duplicate Sparkle. |
| [Rectangle](https://github.com/rxhanson/Rectangle) | Sparkle standard controller, a website-hosted appcast, manual checks, scheduled checks and gentle update reminders. [app delegate](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AppDelegate.swift), [Info.plist](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/Info.plist) | Embeds `SUPublicEDKey` and uses an HTTPS appcast. [Info.plist](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/Info.plist) | Sparkle owns install/relaunch; Rectangle changes its menu to “Update Available…” for a non-intrusive menu-bar experience. [app delegate](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AppDelegate.swift) | Good minimal UI reference for Portu's Settings/About surfaces. |
| [MonitorControl](https://github.com/MonitorControl/MonitorControl) | Sparkle 2.x via SwiftPM, website-hosted appcast and an updater delegate that enables a beta channel. [project](https://github.com/MonitorControl/MonitorControl/blob/main/MonitorControl.xcodeproj/project.pbxproj#L1047-L1075), [delegate](https://github.com/MonitorControl/MonitorControl/blob/main/MonitorControl/Support/UpdaterDelegate.swift) | Embeds `SUPublicEDKey`. [Info.plist](https://github.com/MonitorControl/MonitorControl/blob/main/MonitorControl/Info.plist) | Standard Sparkle install/relaunch. | Useful channel example if Portu later serves `alpha` builds to opted-in users. |
| [OpenDisplay](https://github.com/peetzweg/opendisplay) | Sparkle through SwiftPM; custom-domain/Pages appcast; GitHub Release DMG. [project.yml](https://github.com/peetzweg/opendisplay/blob/main/project.yml#L3-L12), [feed configuration](https://github.com/peetzweg/opendisplay/blob/main/project.yml#L58-L69) | CI writes the private key to a temporary file, runs `generate_appcast --ed-key-file`, and publishes an EdDSA-signed enclosure pointing at the GitHub Release DMG. Its app is also Developer-ID signed and notarized. [release workflow](https://github.com/peetzweg/opendisplay/blob/main/.github/workflows/release.yml#L65-L169), [appcast](https://github.com/peetzweg/opendisplay/blob/main/public/appcast.xml) | Standard Sparkle install/relaunch. | Closest pipeline topology to Portu; omit its paid signing/notarization steps but keep the feed/Release split and EdDSA generation pattern. |
| [IINA](https://github.com/iina/iina) | Sparkle with an HTTPS appcast and standard in-app update UI. [Info.plist](https://github.com/iina/iina/blob/develop/iina/Info.plist#L639-L644) | Embeds both legacy DSA and current EdDSA public keys. [Info.plist](https://github.com/iina/iina/blob/develop/iina/Info.plist#L639-L644) | Standard Sparkle install/relaunch. | Evidence that the same appcast model scales to a mature, widely distributed macOS app; its legacy DSA migration is irrelevant to a new Portu integration. |

### What CodexBar and Warp establish

**Verified:** CodexBar demonstrates the off-the-shelf Sparkle path: a small Swift controller, a static appcast, GitHub Release ZIPs, EdDSA enclosure signatures, automatic download, and a prepared “restart now” callback. It deliberately requires Developer ID in its own policy. [CodexBar controller](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBar/CodexbarApp.swift#L199-L366), [CodexBar appcast](https://github.com/steipete/CodexBar/blob/main/appcast.xml)

**Verified:** Warp demonstrates the custom path: API polling, architecture-specific DMGs, write-permission checks, Apple Team-ID verification, staged extraction, atomic swap, cleanup and an explicit relaunch bridge. Warp's own support documentation notes that it falls back to a manual update when it cannot replace the installed app. [Warp macOS updater](https://github.com/warpdotdev/warp/blob/master/app/src/autoupdate/mac.rs), [Warp update support](https://docs.warp.dev/support-and-community/troubleshooting-and-support/updating-warp)

**Inference:** Sparkle is preferable for Portu because it already supplies the difficult parts visible in Warp's implementation: update scheduling, user consent, archive verification, authorization, atomic replacement, install-on-quit and relaunch. Portu has no unusual daemon, system extension or package-installer requirement that justifies owning those mechanisms. [Sparkle features](https://github.com/sparkle-project/Sparkle), [Sparkle package-update guidance](https://sparkle-project.org/documentation/package-updates/)

## Security model with ad-hoc signing

### What is actually protected

**Verified:** Sparkle's `generate_keys` creates an Ed25519 key pair; the public key is embedded as `SUPublicEDKey`, while `generate_appcast` signs the update archive and emits `sparkle:edSignature` and the byte length in the feed. Sparkle requires cryptographic signatures for updates and recommends generating them rather than hand-editing the appcast. [Sparkle security setup](https://sparkle-project.org/documentation/), [publishing guide](https://sparkle-project.org/documentation/publishing/)

**Verified:** for an ordinary `.app` update, successful verification with the **old installed app's** EdDSA public key is sufficient even when Apple code-signing identity matching does not pass. Sparkle also rejects removing the public key from a later update. [Sparkle validator](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SUUpdateValidator.m#L271-L375)

**Inference:** with Portu's ad-hoc signature, Ed25519 is the effective publisher identity. HTTPS and GitHub permissions are additional layers, but possession of the Ed25519 private key is what authorizes executable updates to already installed copies.

### What is not protected

**Verified:** Apple's normal notarization path requires Developer ID and explicitly excludes ad-hoc signing. A notarization ticket tells Gatekeeper that Apple scanned the Developer-ID-signed software and accepted it. [Apple notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

**Verified:** ad-hoc signing records code integrity but carries no third-party signing identity. Apple's code-signing documentation explains that a designated requirement is how macOS recognizes future versions as the same program; Developer ID supplies a durable external anchor, while ad-hoc code does not supply that publisher identity. [Apple code-signing services](https://developer.apple.com/documentation/security/code-signing-services), [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)

**Inference:** in-app updating will not remove the first-install Gatekeeper bypass users already face, will not add Apple's malware scan or certificate revocation, and may not preserve identity-sensitive macOS permissions as reliably as Developer-ID-signed updates.

**Verified:** Sparkle's Developer-ID fallback can recover from an archive-signing/key-rotation problem only when the archive is Developer-ID signed with a Team ID matching the old bundle. An ad-hoc Portu build has no such Team ID. [Sparkle archive fallback](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SUUpdateValidator.m#L54-L86), [code-signing verifier](https://github.com/sparkle-project/Sparkle/blob/2.x/Autoupdate/SUCodeSigningVerifier.m)

**Inference:** if the Sparkle private key is lost before a transition update can be signed with the old key, installed Portu copies cannot securely accept a replacement key in-app. Keep at least one encrypted offline backup in addition to the protected CI copy; never commit the private key or print it in workflow logs.

### Notarization is separate from updater correctness

**Verified:** a Sparkle maintainer states that notarizing the update is not required when old and new apps use the same EdDSA keys, although Sparkle can reject a broken code signature. [Sparkle discussion #2477](https://github.com/sparkle-project/Sparkle/discussions/2477)

**Inference:** “Sparkle accepts and installs the update” and “macOS treats the app as a notarized identified-developer build” are different outcomes. Portu can plausibly achieve the first under the current no-paid-account policy, but not the second.

## Recommended Portu design

### Application integration

1. Add Sparkle 2 as an XcodeGen SwiftPM package and an app-target dependency, then regenerate `Portu.xcodeproj`. Sparkle recommends `SPUStandardUpdaterController` for new applications. [Sparkle setup](https://sparkle-project.org/documentation/), [Portu project definition](../../project.yml)
2. Add `SUFeedURL` and `SUPublicEDKey` to Portu's Info.plist. Keep the same public key in every future build unless a transition release is signed by the old private key. [Sparkle setup](https://sparkle-project.org/documentation/)
3. Add a normal “Check for Updates…” command and a Settings toggle backed by Sparkle's `automaticallyChecksForUpdates`; start with user-confirmed installation rather than silent updates. Sparkle's defaults and runtime properties support this without a custom user driver. [Sparkle customization](https://sparkle-project.org/documentation/customization/)
4. Let Sparkle own installation and relaunch. If Portu later wants CodexBar's “update ready, restart now” affordance, retain `willInstallUpdateOnQuit`'s `immediateInstallationBlock` and invoke it from the UI. [Sparkle updater delegate](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html), [CodexBar example](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBar/CodexbarApp.swift#L259-L328)

### Feed and release integration

1. Generate one Sparkle Ed25519 key pair outside CI. Put the public key in the app and keep the private key in a protected CI secret plus an encrypted offline backup. Sparkle's tooling supports an exported private-key file for CI signing. [Sparkle setup](https://sparkle-project.org/documentation/)
2. After `package_release_dmg.sh` builds the release DMG, run Sparkle's official `generate_appcast` against it with `--ed-key-file` and a GitHub Release download URL prefix. The result must contain the DMG byte length, `CFBundleVersion`, short version and `sparkle:edSignature`. [Sparkle publishing guide](https://sparkle-project.org/documentation/publishing/), [OpenDisplay workflow](https://github.com/peetzweg/opendisplay/blob/main/.github/workflows/release.yml#L129-L149)
3. Publish the appcast at a stable HTTPS URL and keep the enclosure on `https://github.com/Chalet-Labs/portu/releases/download/v<version>/Portu-<version>.dmg`. A raw repository file or GitHub Pages is sufficient static hosting; CodexBar uses the former and OpenDisplay the latter. [CodexBar feed configuration](https://github.com/steipete/CodexBar/blob/main/docs/sparkle.md), [OpenDisplay feed publication](https://github.com/peetzweg/opendisplay/blob/main/.github/workflows/release.yml#L112-L169)
4. Publish the feed only after the corresponding GitHub Release asset is available. Preserve prior appcast items so installed older builds retain a valid upgrade path, and serialize feed publication with the existing non-cancelling release concurrency. [Portu release workflow](../../.github/workflows/release.yml), [Sparkle appcast documentation](https://sparkle-project.org/documentation/publishing/)

**Recommendation (inference):** make stable `master` releases the first supported channel. Keep `alpha` updates manual in the initial version, then add a separate alpha feed or Sparkle channel after the stable path is proven. This prevents prerelease publication from accidentally replacing the feed seen by stable users. Sparkle supports named channels when that second phase is wanted. [Sparkle features](https://github.com/sparkle-project/Sparkle)

**Hardening option (verified capability, implementation choice):** `SUVerifyUpdateBeforeExtraction` verifies the archive before extraction. Sparkle 2.9 can additionally require a signed feed and signed release notes with `SURequireSignedFeed`; that setting requires `SUVerifyUpdateBeforeExtraction`. [Sparkle security settings](https://sparkle-project.org/documentation/customization/)

**Recommendation (inference):** enable verification before extraction. Consider requiring a signed feed only after the release/recovery procedure is rehearsed, because Portu has no Developer-ID recovery anchor if key custody fails.

## Proof gates before shipping

The following are **required verification work**, not verified outcomes:

1. Build two genuine ad-hoc release DMGs, `N` and `N+1`, embedding the same public Ed25519 key; sign the `N+1` DMG with the matching private key and serve it from a test appcast.
2. On a clean macOS 15 user account, download `N` through a browser, perform the normal first-install Gatekeeper approval, move it to `/Applications`, and update to `N+1` from inside the app.
3. Repeat from a user-writable `~/Applications` location and from `/Applications` as a non-admin user; confirm Sparkle either installs or presents the expected authorization UI. Sparkle documents authorization prompts when the installed bundle is not writable. [Sparkle user-driver API](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUserDriver.html)
4. Verify the app quits, the bundle is replaced atomically, the new version relaunches, portfolio data and Keychain credentials remain available, and no duplicate Portu process remains.
5. Tamper with one byte of the DMG and confirm installation fails on EdDSA validation. Replace the appcast signature/URL and confirm the chosen signed-feed policy behaves as designed.
6. Exercise rollback/recovery: unavailable feed, missing Release asset, interrupted download, insufficient disk space, app open during install, and a release whose appcast is published late.
7. Inspect the actual release bundle with `codesign --verify --deep --strict`, run Sparkle's update flow with Console logging, and confirm the embedded helpers load under Portu's final release settings. Sparkle specifically recommends a genuine old/new release test because signing policies may differ from development builds. [Sparkle testing guide](https://sparkle-project.org/documentation/)

Until these gates pass, the precise claim should be: **Sparkle with EdDSA is source-supported and architecturally feasible for ad-hoc Portu releases, but ad-hoc install/relaunch behavior has not yet been verified on Portu.**

## Bottom line

Sparkle 2 is the only surveyed approach that combines a small native integration with a maintained security and installation model while remaining technically usable without Developer ID. CodexBar is the best UI reference, OpenDisplay is the closest GitHub feed/release workflow reference, Rectangle and MonitorControl show conventional Sparkle integration, and Warp is useful mainly as evidence of how much security-sensitive machinery a custom updater would force Portu to own.

Under Portu's personal-app policy, the acceptable design is: **ad-hoc code signature + Sparkle Ed25519 archive signature + HTTPS appcast + GitHub Release DMG + one-time manual bootstrap install**. This is authenticated self-update, but it is not notarized distribution and should never be presented as equivalent to Developer ID.
