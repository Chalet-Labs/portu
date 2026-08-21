# Sparkle ad-hoc update proof

Use this playbook for the issue #79 go/no-go gate. It builds two genuine universal Release DMGs with credential-free ad-hoc Apple signing and a disposable Sparkle Ed25519 key. A localhost-only HTTPS origin serves the artifacts, and Tailscale Serve exposes that origin at the developer Mac's trusted, tailnet-only HTTPS hostname.

Do not use real provider or exchange credentials. Do not commit anything below `.build/`. Do not close the gate while any `manual_results` value in `manifest.json` is `null`; every result must be `true` except `duplicate_processes`, which must be `false`.

## Prepare the artifacts

Both Macs must be connected to the same tailnet. From the repository root on the developer Mac, get its HTTPS hostname:

```bash
TAILSCALE_DNS_NAME="$(tailscale status --json | jq -r '.Self.DNSName | rtrimstr(".")')"
TAILSCALE_SERVE_PORT=8444
ORIGIN_PORT=8443
echo "$TAILSCALE_DNS_NAME"
```

The name must end in `.ts.net`. Tailscale HTTPS publishes this machine name in Certificate Transparency, so rename the machine first if its name is sensitive.

Prepare the artifacts with that hostname embedded in N and N+1:

```bash
./scripts/prepare_sparkle_adhoc_proof.sh \
  --base-url "https://$TAILSCALE_DNS_NAME:$TAILSCALE_SERVE_PORT" \
  --origin-port "$ORIGIN_PORT" \
  --n-version 79.0.0 \
  --n-build 79000 \
  --next-version 79.0.1 \
  --next-build 79001 \
  --output .build/updater-proof-79
```

The command prints and records the tailnet `install_url` and `feed_url`, localhost `origin_url`, and Tailscale Serve command. It fails unless both DMGs are universal, ad-hoc signed, configured with the same disposable public update key, and configured to verify the archive before extraction. Sparkle's own tools generate and verify the appcast signature. The disposable private update key exists only in process memory and standard input; it is not written to the proof directory or command line.

Keep these generated files as the non-secret automated evidence:

- `manifest.json`
- `releases/Portu-79.0.0.dmg` and its checksum
- `server/Portu-79.0.1.dmg` and its checksum
- `server/appcast.xml`
- `negative/Portu-79.0.1-tampered.dmg`

## Serve the proof to the tailnet

Leave this terminal running on the developer Mac:

```bash
ORIGIN_PORT="$(jq -r '.origin_url | capture(":(?<port>[0-9]+)$").port' .build/updater-proof-79/manifest.json)"
./scripts/serve_sparkle_adhoc_proof.py \
  --directory .build/updater-proof-79/server \
  --cert .build/updater-proof-79/tls/server-cert.pem \
  --key .build/updater-proof-79/tls/server-key.pem \
  --installer .build/updater-proof-79/releases/Portu-79.0.0.dmg \
  --port "$ORIGIN_PORT" \
  --scenario normal
```

The origin deliberately binds only to `127.0.0.1`. In a second terminal, confirm the proof's dedicated HTTPS port is unused before configuring it:

```bash
TAILSCALE_SERVE_PORT="$(jq -r '.tailscale_serve_https_port' .build/updater-proof-79/manifest.json)"
ORIGIN_PORT="$(jq -r '.origin_url | capture(":(?<port>[0-9]+)$").port' .build/updater-proof-79/manifest.json)"
SERVE_STATUS="$(tailscale serve status --json)" || {
  echo "Could not inspect Tailscale Serve configuration; refusing to change it." >&2
  exit 1
}
PORT_IN_USE="$(jq -r --arg port "$TAILSCALE_SERVE_PORT" '(.TCP[$port]? != null) or ([((.Web? // {}) | to_entries[]) | select(.key | endswith(":" + $port))] | length > 0)' <<< "$SERVE_STATUS")" || {
  echo "Could not parse Tailscale Serve configuration; refusing to change it." >&2
  exit 1
}
if [[ "$PORT_IN_USE" == "true" ]]; then
  echo "Tailscale Serve HTTPS port $TAILSCALE_SERVE_PORT is already in use; choose another unused port, set TAILSCALE_SERVE_PORT to it, and rebuild the proof." >&2
  exit 1
fi
if [[ "$PORT_IN_USE" != "false" ]]; then
  echo "Unexpected Tailscale Serve configuration result; refusing to change it." >&2
  exit 1
fi
tailscale serve --bg --https="$TAILSCALE_SERVE_PORT" --set-path=/ "https+insecure://localhost:$ORIGIN_PORT"
tailscale serve status
```

The Serve port must match the port embedded in `--base-url`. The first Serve command may open a Tailscale consent page if tailnet HTTPS is not enabled. Do not use Tailscale Funnel; the proof must remain private to the tailnet.

Verify from the second Mac, copying the exact URLs printed during preparation or recorded in `manifest.json`:

```bash
INSTALL_URL="<install_url from manifest.json>"
FEED_URL="<feed_url from manifest.json>"
curl --fail --head "$INSTALL_URL"
curl --fail "$FEED_URL"
```

These requests must succeed without importing the disposable localhost CA. If the hostname does not resolve, enable MagicDNS and confirm both Macs are connected to the same tailnet and allowed by its access rules.

## Prepare a clean account on the target Mac

Create or use a clean account on the target Mac that has never launched Portu. The developer account cannot substitute for this gate because its application data and Keychain may hide continuity failures.

1. In Safari, open the exact `install_url` from `.build/updater-proof-79/manifest.json`.
2. Open the downloaded N DMG in Finder, drag `Portu.app` to `/Applications`, and launch it using the normal Gatekeeper flow shown by macOS. Record every Gatekeeper step rather than bypassing quarantine with `xattr` or disabling Gatekeeper.
3. Confirm About reports `79.0.0 (79000)`.
4. Add a recognizable manual portfolio position, change one visible setting such as display currency, and save a disposable value such as `issue-79-disposable` in Settings > API Keys > CoinGecko. Confirm the Keychain field can be revealed before updating.

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

For a tampered archive, restart only the localhost origin with `--scenario tampered`; the Tailscale Serve configuration remains active. The one-byte-modified DMG must be rejected, `/Applications/Portu.app` must remain N, and the app must remain launchable.

For a missing enclosure, restart with `--scenario missing`. The update UI must report a recoverable download failure, keep N installed, and allow a later manual Check for Updates.

For an unavailable feed, stop the server before Check for Updates. The UI must report a recoverable feed failure, keep N installed, and allow a later manual Check for Updates after the server returns.

Record each outcome in `manifest.json`. A failed replacement, lost data or Keychain item, duplicate process, automatic DMG request, or unrecoverable error is a no-go: leave issue #79 open and stop updater rollout.

## Cleanup

After evidence is captured, quit Portu on the second Mac and remove the tailnet exposure on the developer Mac:

```bash
TAILSCALE_DNS_NAME="$(tailscale status --json | jq -r '.Self.DNSName | rtrimstr(".")')"
TAILSCALE_SERVE_PORT="$(jq -r '.tailscale_serve_https_port' .build/updater-proof-79/manifest.json)"
ORIGIN_PORT="$(jq -r '.origin_url | capture(":(?<port>[0-9]+)$").port' .build/updater-proof-79/manifest.json)"
CURRENT_PROXY="$(tailscale serve status --json | jq -r --arg host "$TAILSCALE_DNS_NAME:$TAILSCALE_SERVE_PORT" '.Web[$host].Handlers["/"].Proxy // empty')"
if [[ "$CURRENT_PROXY" != "https+insecure://localhost:$ORIGIN_PORT" ]]; then
  echo "Tailscale Serve root no longer points to this proof; inspect it instead of removing it automatically." >&2
  exit 1
fi
tailscale serve --https="$TAILSCALE_SERVE_PORT" --set-path=/ off
```

No certificate was imported on the second Mac. Remove the clean test account only if its owner approves. The proof artifacts under `.build/` are ignored by Git and may be deleted after the issue evidence has been preserved.
