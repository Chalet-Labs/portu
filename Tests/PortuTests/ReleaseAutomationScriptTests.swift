import Foundation
import Testing

extension ReleaseAutomationTests {
    @Test func `proof versions exclude suffixes and full proof excludes localhost`() throws {
        let prerelease = try runScript(
            "scripts/prepare_sparkle_adhoc_proof.sh",
            arguments: [
                "--base-url", "https://works-macbook-pro-1.tailb38892.ts.net:8444",
                "--origin-port", "8443",
                "--n-version", "79.0.0-alpha.1",
                "--n-build", "79000",
                "--next-version", "79.0.1-alpha.1",
                "--next-build", "79001",
                "--output", ".build/updater-proof",
                "--plan-only"
            ])
        #expect(prerelease.status == 2)
        #expect(prerelease.error.contains("plain semantic versions"))

        let untrustedLocalhost = try runScript(
            "scripts/prepare_sparkle_adhoc_proof.sh",
            arguments: [
                "--base-url", "https://localhost:8443",
                "--n-version", "79.0.0",
                "--n-build", "79000",
                "--next-version", "79.0.1",
                "--next-build", "79001",
                "--output", "/tmp/portu-updater-proof"
            ])
        #expect(untrustedLocalhost.status == 2)
        #expect(untrustedLocalhost.error.contains("full proof requires a Tailscale HTTPS hostname"))
    }

    @Test func `script runner drains stdout and stderr while the child is running`() throws {
        let result = try runScript(
            "Tests/Fixtures/ReleaseAutomation/emit_large_output.py",
            arguments: [])

        #expect(result.status == 0)
        #expect(result.output == "stdout-complete\n")
        #expect(result.error.utf8.count == 2 * 1024 * 1024)
    }

    @Test func `proof HTTPS server selects immutable negative appcast scenarios`() throws {
        let help = try runScript(
            "scripts/serve_sparkle_adhoc_proof.py",
            arguments: ["--help"])

        #expect(help.status == 0)
        #expect(help.output.contains("--scenario {normal,tampered,missing}"))
        #expect(help.output.contains("--installer INSTALLER"))

        let missingDirectory = try runScript(
            "scripts/serve_sparkle_adhoc_proof.py",
            arguments: [
                "--directory", ".build/missing-proof-directory",
                "--cert", ".build/missing-proof-cert.pem",
                "--key", ".build/missing-proof-key.pem",
                "--port", "8443"
            ])
        #expect(missingDirectory.status == 2)
        #expect(missingDirectory.error.contains("directory does not exist"))

        let server = try string("scripts/serve_sparkle_adhoc_proof.py")
        let preparer = try string("scripts/prepare_sparkle_adhoc_proof.sh")
        let playbook = try string("docs/agents/sparkle-adhoc-proof.md")
        #expect(server.contains("tampered-appcast.xml"))
        #expect(server.contains("missing-enclosure-appcast.xml"))
        #expect(server.contains("if request_path == \"/appcast.xml\""))
        #expect(server.contains("if request_path == \"/install.dmg\""))
        #expect(server.contains("def do_HEAD(self)"))
        #expect(server.contains("ThreadingHTTPServer((\"127.0.0.1\", args.port)"))
        #expect(server.contains("except KeyboardInterrupt:"))
        #expect(preparer.contains("--installer '$RELEASES_DIR/Portu-$N_VERSION.dmg'"))
        #expect(playbook.contains("SERVE_STATUS=\"$(tailscale serve status --json)\" ||"))
        #expect(playbook.contains("PORT_IN_USE=\"$(jq -r"))
        #expect(playbook.contains("Could not parse Tailscale Serve configuration"))
        #expect(playbook.contains("[[ \"$PORT_IN_USE\" != \"false\" ]]"))
        #expect(playbook.contains("tailscale serve --https=\"$TAILSCALE_SERVE_PORT\" --set-path=/ off"))
        #expect(!playbook.contains("tailscale serve reset"))
    }

    @Test func `local run script uses a stable development signing identity`() throws {
        let runScript = try string("script/build_and_run.sh")
        let signingScript = try string("script/ensure_local_signing_identity.sh")

        #expect(runScript.contains("ensure_local_signing_identity.sh"))
        #expect(runScript.contains("CODE_SIGN_IDENTITY=\"$CODE_SIGN_IDENTITY_NAME\""))
        #expect(runScript.contains("CODE_SIGN_STYLE=Manual"))
        #expect(signingScript.contains("security find-identity"))
        #expect(signingScript.contains("CA:FALSE"))
        #expect(!signingScript.contains("keyCertSign"))
        #expect(signingScript.contains("extendedKeyUsage=codeSigning"))
        #expect(signingScript.contains("-r trustAsRoot"))
        #expect(signingScript.contains("security delete-identity"))
        #expect(signingScript.contains("-T /usr/bin/codesign"))
    }

    @Test func `app version is supplied by xcode build settings`() throws {
        let infoPlist = try string("Sources/Portu/Resources/Info.plist")
        let project = try string("project.yml")

        #expect(infoPlist.contains("<string>$(MARKETING_VERSION)</string>"))
        #expect(infoPlist.contains("<string>$(CURRENT_PROJECT_VERSION)</string>"))
        #expect(project.range(of: #"MARKETING_VERSION: "\d+\.\d+\.\d+""#, options: .regularExpression) != nil)
        #expect(project.range(of: #"CURRENT_PROJECT_VERSION: "\d+""#, options: .regularExpression) != nil)
    }
}
