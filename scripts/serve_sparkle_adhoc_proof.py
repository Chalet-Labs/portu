#!/usr/bin/env python3

import argparse
import email.utils
import http.server
import os
import ssl
from typing import Optional
from urllib.parse import urlsplit


SCENARIO_APPCASTS = {
    "normal": "appcast.xml",
    "tampered": "tampered-appcast.xml",
    "missing": "missing-enclosure-appcast.xml",
}


class ProofRequestHandler(http.server.SimpleHTTPRequestHandler):
    scenario = "normal"
    installer_path: Optional[str] = None

    def _route_request(self) -> None:
        request_path = urlsplit(self.path).path
        if request_path == "/appcast.xml":
            self.path = f"/{SCENARIO_APPCASTS[self.scenario]}"

    def do_GET(self) -> None:
        self._route_request()
        super().do_GET()

    def do_HEAD(self) -> None:
        self._route_request()
        super().do_HEAD()

    def send_head(self):
        request_path = urlsplit(self.path).path
        if request_path == "/install.dmg":
            if self.installer_path is None:
                self.send_error(http.HTTPStatus.NOT_FOUND, "Installer is not configured")
                return None

            installer = open(self.installer_path, "rb")
            metadata = os.fstat(installer.fileno())
            self.send_response(http.HTTPStatus.OK)
            self.send_header("Content-Type", "application/x-apple-diskimage")
            self.send_header("Content-Length", str(metadata.st_size))
            self.send_header("Last-Modified", email.utils.formatdate(metadata.st_mtime, usegmt=True))
            self.end_headers()
            return installer

        return super().send_head()


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve isolated Portu Sparkle proof artifacts over HTTPS.")
    parser.add_argument("--directory", required=True)
    parser.add_argument("--cert", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--port", required=True, type=int)
    parser.add_argument("--scenario", choices=tuple(SCENARIO_APPCASTS), default="normal")
    parser.add_argument("--installer")
    args = parser.parse_args()

    directory = os.path.realpath(args.directory)
    if not os.path.isdir(directory):
        parser.error(f"directory does not exist: {directory}")
    installer_path = os.path.realpath(args.installer) if args.installer else None
    if installer_path is not None and not os.path.isfile(installer_path):
        parser.error(f"installer does not exist: {installer_path}")
    ProofRequestHandler.scenario = args.scenario
    ProofRequestHandler.installer_path = installer_path
    handler = lambda *handler_args, **handler_kwargs: ProofRequestHandler(
        *handler_args,
        directory=directory,
        **handler_kwargs,
    )
    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=args.cert, keyfile=args.key)
    server.socket = context.wrap_socket(server.socket, server_side=True)

    print(
        f"Serving {directory} at https://localhost:{args.port} ({args.scenario} scenario)",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
