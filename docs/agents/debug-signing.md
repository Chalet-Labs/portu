# Debug Signing

How Debug builds are signed, and why that decides whether macOS asks for keychain access after a rebuild. Release signing is covered in `production-signing.md`; developer setup steps are in the README.

## How it works

- `Configs/Debug.xcconfig` is the project's Debug base config. It keeps ad hoc signing (`CODE_SIGN_STYLE = Automatic`, no team) and then runs `#include? "Local.xcconfig"`.
- `just signing-setup` (`script/setup_local_signing.sh`) writes the untracked `Configs/Local.xcconfig`: Manual style, the `Apple Development` identity, the team ID read from the certificate, and an empty `PROVISIONING_PROFILE_SPECIFIER`. A free Apple ID in Xcode is enough.
- `project.yml` sets `CODE_SIGN_STYLE: Automatic` only in the Release config. A target-level value would override the project xcconfig and with it `Local.xcconfig`.

## Why builds prompt

For an app without an Apple team ID, each keychain item's partition list records the build's `cdhash`. Every rebuild has a new hash, so "Always Allow" never holds. An Apple Development identity carries a team ID, so the item records `teamid:<TEAM>` and access holds across rebuilds. A self-signed certificate has no team ID and cannot fix this.

## Per checkout

`Local.xcconfig` belongs to one checkout. Each git worktree or clone needs its own `just signing-setup` (or a copy of the file); without it, its Debug builds are ad hoc signed and prompt again. A secret first stored by an ad hoc build stays tied to that build until a team-signed build is allowed once.

## Guardrails

- Keep `Configs/Local.xcconfig` untracked; it names one developer's team.
- Keep Debug signing profile-free. A provisioning profile adds an `application-identifier` entitlement, which moves `KeychainService` to the data protection keychain, where the existing items do not live.
- Keep the developer's Apple Development signing key on their machine. With team signing, keychain access follows that key rather than one exact build, so it is never exported or shared.
