#!/usr/bin/env python3
"""
Local HTTPS reverse proxy on 127.0.0.1:443 for prefetch-npm-deps.

WHY THIS EXISTS
===============
qwen-code's npmDeps FOD uses `prefetch-npm-deps` (a Rust/isahc fetcher) to pull
~2400 npm tarballs + packuments. The fetcher's isahc one-shot `send()` does NOT
read http_proxy/https_proxy env vars (verified three ways: source has no proxy
call; process env had https_proxy=127.0.0.1:7890 but still connected direct;
netstat showed no 7890 connection). So it connects DIRECTLY to the registry
host. registry.npmjs.org is GFW-flaky from China (~40% TLS drops).

We can't make the fetcher use clash directly. But we CAN point it at a local
HTTPS server it CAN reach directly (127.0.0.1:443), and have THAT server fetch
npmjs through clash (which works fine for curl/urllib).

The override `{"registry.npmjs.org":"myproto://127.0.0.1"}` (non-special scheme)
makes the fetcher rewrite every registry.npmjs.org URL into
`https://127.0.0.1/<path>` (single slash, host 127.0.0.1, scheme+port kept as
https/443). The FOD build sets SSL_CERT_FILE=/no-cert-file.crt which makes isahc
use DANGER_ACCEPT_INVALID_CERTS, so it accepts this server's self-signed cert.

This server maps GET /<path> -> https://registry.npmjs.org/<path> via clash,
with aggressive retry for clash's intermittent TLS drops. It serves BOTH
tarballs (/pkg/-/pkg-ver.tgz) and packuments (/pkg) — the fetcher requests both.

Hash-stability: prefetch-npm-deps stores the LOCKFILE's resolved url
(registry.npmjs.org) in the cacache, not the override url (main.rs L458), so the
output nar hash matches the declared npmDepsHash — no re-hashing needed.

Run as root (port 443). See npm-proxy-build.sh.
"""
import http.server
import ssl
import sys
import time
import urllib.request
import urllib.error

UPSTREAM = "https://registry.npmjs.org"
PROXY = "http://127.0.0.1:7890"
CERT = "/etc/nix-darwin/scripts/npm-proxy-cert.pem"
KEY = "/etc/nix-darwin/scripts/npm-proxy-key.pem"
MAX_RETRY = 15          # clash drops TLS ~40% for npmjs; need generous retry
TIMEOUT = 120
DONE = 0
FAIL = 0

# One shared opener that always routes through clash.
_opener = urllib.request.build_opener(
    urllib.request.ProxyHandler({"http": PROXY, "https": PROXY})
)


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        global DONE, FAIL
        path = self.path
        # Collapse accidental interior double-slash (keep the leading one).
        if "//" in path[1:]:
            path = path[0] + path[1:].replace("//", "/")
        url = UPSTREAM + path
        last_err = None
        for attempt in range(1, MAX_RETRY + 1):
            try:
                req = urllib.request.Request(
                    url,
                    headers={
                        "User-Agent": "npm-proxy/1.0 (nix fetchNpmDeps helper)",
                        "Accept": "*/*",
                    },
                )
                with _opener.open(req, timeout=TIMEOUT) as r:
                    data = r.read()
                    status = r.status
                    ctype = r.headers.get("Content-Type", "application/octet-stream")
                if status != 200:
                    # Don't retry non-200 (e.g. real 404); forward as-is.
                    self._send(status, data, ctype)
                    DONE += 1
                    return
                self._send(200, data, "application/octet-stream")
                DONE += 1
                return
            except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
                last_err = e
                time.sleep(min(0.5 * attempt, 5))
            except Exception as e:
                last_err = e
                time.sleep(min(0.5 * attempt, 5))
        FAIL += 1
        msg = f"proxy: exhausted {MAX_RETRY} retries for {url}: {last_err}".encode()
        self._send(502, msg, "text/plain")
        sys.stderr.write(msg.decode() + "\n")
        sys.stderr.flush()

    def _send(self, status, data, ctype):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass  # fetcher gave up / retrying on its own

    def log_message(self, fmt, *a):
        # Only log errors/failures to keep output sane across ~5000 requests.
        if " 5" in (fmt % a) or " 4" in (fmt % a):
            sys.stderr.write("%s %s\n" % (self.address_string(), fmt % a))
            sys.stderr.flush()


class TS(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main():
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(CERT, KEY)
    httpd = TS(("127.0.0.1", 443), ProxyHandler)
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    sys.stderr.write(
        "npm-proxy listening on https://127.0.0.1:443 -> %s via %s\n"
        % (UPSTREAM, PROXY)
    )
    sys.stderr.flush()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        sys.stderr.write("\nnpm-proxy: done=%d fail=%d\n" % (DONE, FAIL))


if __name__ == "__main__":
    main()
