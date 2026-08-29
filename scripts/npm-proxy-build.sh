#!/usr/bin/env bash
#
# Build qwen-code with a local HTTPS proxy bridging prefetch-npm-deps to npmjs
# via clash. The fetcher ignores proxy env vars, so we give it a local HTTPS
# server it can reach directly (127.0.0.1:443) that itself fetches through clash.
#
# Usage:  sudo bash /etc/nix-darwin/scripts/npm-proxy-build.sh
#
# What it does:
#   1. generate a self-signed cert (CN=127.0.0.1) if missing
#   2. start npm-proxy.py on https://127.0.0.1:443  (background, root)
#   3. sanity-check it can reach npmjs via clash (curl /lodash)
#   4. darwin-rebuild switch   <- FOD fetcher hits 127.0.0.1:443 for ~5000 reqs
#   5. stop the proxy
#
set -euo pipefail

DIR=/etc/nix-darwin/scripts
CERT="$DIR/npm-proxy-cert.pem"
KEY="$DIR/npm-proxy-key.pem"
PYBIN="${PYTHON:-/usr/bin/python3}"

echo "==> [1/5] clash proxy at 127.0.0.1:7890 reachable?"
if ! curl -sS -x http://127.0.0.1:7890 -o /dev/null -m 15 -w 'http=%{http_code}\n' \
     https://registry.npmjs.org/lodash; then
  echo "ERROR: clash at 127.0.0.1:7890 not reachable / npmjs via clash failed."
  echo "       Start clash first, then re-run."
  exit 1
fi

echo "==> [2/5] self-signed cert"
if [ ! -f "$CERT" ] || [ ! -f "$KEY" ]; then
  openssl req -x509 -newkey rsa:2048 -keyout "$KEY" -out "$CERT" -days 3650 \
    -nodes -subj '/CN=127.0.0.1' -addext 'subjectAltName=IP:127.0.0.1' 2>/dev/null
  chmod 600 "$KEY"
  echo "    generated $CERT"
else
  echo "    reuse existing $CERT"
fi

echo "==> [3/5] start npm-proxy on https://127.0.0.1:443"
"$PYBIN" "$DIR/npm-proxy.py" 2>"$DIR/npm-proxy.log" &
PROXY_PID=$!
trap 'kill $PROXY_PID 2>/dev/null || true' EXIT INT TERM

# wait until the proxy answers a packument request (returns 200 JSON)
for i in $(seq 1 20); do
  code=$(curl -sk -o /dev/null -m 30 -w '%{http_code}' https://127.0.0.1/lodash 2>/dev/null || echo 000)
  [ "$code" = "200" ] && break
  sleep 0.5
done
if [ "$code" != "200" ]; then
  echo "ERROR: proxy self-test returned $code (expected 200). Proxy log:"
  tail -20 "$DIR/npm-proxy.log" 2>/dev/null || true
  kill $PROXY_PID 2>/dev/null || true
  exit 1
fi
echo "    proxy up (pid $PROXY_PID), self-test 200 for /lodash"
echo "    (live proxy log: tail -f $DIR/npm-proxy.log)"

echo "==> [4/5] darwin-rebuild switch"
echo "    fetcher will pull ~2400 tarballs + ~2400 packuments through the proxy."
echo "    expect 5-15 min. The build runs in the nix daemon; proxy runs here."
REBUILD=darwin-rebuild
if ! command -v $REBUILD >/dev/null 2>&1; then
  REBUILD="/run/current-system/sw/bin/darwin-rebuild"
fi
if ! $REBUILD switch --flake /etc/nix-darwin#dok4ever-mac; then
  echo "ERROR: darwin-rebuild switch failed. Proxy log tail:"
  tail -30 "$DIR/npm-proxy.log" 2>/dev/null || true
  exit 1
fi

echo "==> [5/5] stop proxy"
kill $PROXY_PID 2>/dev/null || true
trap - EXIT INT TERM
echo
echo "DONE. claude-code / gemini-cli / qwen-code now in the system profile."
echo "proxy final stats:"
tail -2 "$DIR/npm-proxy.log" 2>/dev/null || true
