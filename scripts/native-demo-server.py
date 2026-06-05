#!/usr/bin/env python3
import argparse
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = "\n".join(
            [
                f"Hostname: {socket.gethostname()}",
                "IP: 127.0.0.1",
                f"RemoteAddr: {self.client_address[0]}:{self.client_address[1]}",
                f"Host: {self.headers.get('Host', '')}",
                f"Path: {self.path}",
                "",
            ]
        ).encode("utf-8")

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format, *_args):
        return


def main():
    parser = argparse.ArgumentParser(description="EasyGate native demo HTTP server")
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
