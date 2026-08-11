# Sparkle ad-hoc update proof

Use this playbook for the issue #79 go/no-go gate. It builds two genuine universal Release DMGs with credential-free ad-hoc Apple signing and a disposable Sparkle Ed25519 key, then serves the signed update over isolated localhost HTTPS.

Do not use real provider or exchange credentials. Do not commit anything below `.build/`. Do not close the gate while any `manual_results` value in `manifest.json` is `null`; every result must be `true` except `duplicate_processes`, which must be `false`.

## Prepare the artifacts

From the repository root on the developer account:

```bash
./scripts/prepare_sparkle_adhoc_proof.sh \
  --base-url https://localhost:8443 \
  --n-version 79.0.0 \
  --n-build 79000 \
  --next-version 79.0.1 \
  --next-build 79001 \
  --output .build/updater-proof-79
```

The command fails unless both DMGs are universal, ad-hoc signed, configured with the same disposable public update key, and configured to verify the archive before extraction. Sparkle's own tools generate and verify the appcast signature. The disposable private update key exists only in process memory and standard input; it is not written to the proof directory or command line.

Keep these generated files as the non-secret automated evidence:

- `manifest.json`
- `releases/Portu-79.0.0.dmg` and its checksum
- `server/Portu-79.0.1.dmg` and its checksum
- `server/appcast.xml`
- `negative/Portu-79.0.1-tampered.dmg`

## Prepare a clean macOS 15 account

Create or use a clean local macOS 15 account that has never launched Portu. The developer account cannot substitute for this gate because its application data and Keychain may hide continuity failures.

1. Leave the developer account logged in and start the normal feed:

   ```bash
   ./scripts/serve_sparkle_adhoc_proof.py \
     --directory .build/updater-proof-79/server \
     --cert .build/updater-proof-79/tls/server-cert.pem \
     --key .build/updater-proof-79/tls/server-key.pem \
     --installer .build/updater-proof-79/releases/Portu-79.0.0.dmg \
     --port 8443 \
     --scenario normal
   ```

2. The clean account cannot traverse the developer account's home directory. Copy only the public CA certificate to the shared folder:

   ```bash
   mkdir -p /Users/Shared/Portu-Updater-Proof-79
   cp .build/updater-proof-79/tls/ca-cert.pem /Users/Shared/Portu-Updater-Proof-79/
   ```

3. In the clean account, import `/Users/Shared/Portu-Updater-Proof-79/ca-cert.pem` into that account's login Keychain with Keychain Access and trust it for SSL. This CA is disposable and valid for two days.
4. In Safari, download `https://localhost:8443/install.dmg`. Open the downloaded N DMG in Finder, drag `Portu.app` to `/Applications`, and launch it using the normal Gatekeeper flow shown by macOS. Record every Gatekeeper step rather than bypassing quarantine with `xattr` or disabling Gatekeeper.
5. Confirm About reports `79.0.0 (79000)`.
6. Add a recognizable manual portfolio position, change one visible setting such as display currency, and save a disposable value such as `issue-79-disposable` in Settings > API Keys > CoinGecko. Confirm the Keychain field can be revealed before updating.

## Prove N to N+1

1. Choose Portu > Check for Updates.
2. Before choosing Install, confirm the server log has requested `appcast.xml` but has not requested `Portu-79.0.1.dmg`. Record this as `no_download_before_approval`.
3. Choose Install. Record the explicit approval, download, replacement, and relaunch.
4. Confirm all of the following:

   - About reports `79.0.1 (79001)`.
   - `/Applications/Portu.app` is the replaced bundle and there is no second installed Portu bundle.
   - `pgrep -x Portu` prints exactly one process ID after relaunch.
   - The manual portfolio position remains.
   - The changed setting remains.
   - The disposable CoinGecko value remains readable from Keychain through the app.

Set the matching `manual_results` values in `manifest.json` to `true`, except set `duplicate_processes` to `false`. Record timestamps, screenshots, and the secret-free server log beside the manifest. Never capture the API-key field while it is revealed.

## Negative scenarios

Quit Portu and reinstall N before each scenario. Preserve the clean account's existing Portu data and Keychain so each run also checks non-destructive recovery.

For a tampered archive, restart the server with `--scenario tampered`. The one-byte-modified DMG must be rejected, `/Applications/Portu.app` must remain N, and the app must remain launchable.

For a missing enclosure, restart with `--scenario missing`. The update UI must report a recoverable download failure, keep N installed, and allow a later manual Check for Updates.

For an unavailable feed, stop the server before Check for Updates. The UI must report a recoverable feed failure, keep N installed, and allow a later manual Check for Updates after the server returns.

Record each outcome in `manifest.json`. A failed replacement, lost data or Keychain item, duplicate process, automatic DMG request, or unrecoverable error is a no-go: leave issue #79 open and stop updater rollout.

## Cleanup

After evidence is captured, quit Portu in the clean account, remove the disposable localhost CA from that account's login Keychain, and remove `/Users/Shared/Portu-Updater-Proof-79`. Remove the clean test account only if its owner approves. The proof artifacts under `.build/` are ignored by Git and may be deleted after the issue evidence has been preserved.
