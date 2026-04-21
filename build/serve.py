#!/usr/bin/env python3
"""Development server with Cross-Origin Isolation headers.

Required for SharedArrayBuffer used by the WASM SSH client.

Usage: python3 build/serve.py [port]
"""

import http.server
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
DIST = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "dist")


class COOPCOEPHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIST, **kwargs)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()


print(f"Serving {DIST} at http://localhost:{PORT}")
print("Press Ctrl+C to stop.")
httpd = http.server.HTTPServer(("", PORT), COOPCOEPHandler)
httpd.serve_forever()
