#!/bin/sh

set -eu

case "${RESEED_URL:-}" in
  "")
    set -- \
      'https://reseed-fr.i2pd.xyz/i2pseeds.su3?netid=2' \
      'https://reseed2.i2p.net/i2pseeds.su3?netid=2' \
      'https://reseed.diva.exchange/i2pseeds.su3?netid=2'
    ;;
  https://*) set -- "$RESEED_URL" ;;
  *) echo "RESEED_URL must use HTTPS." >&2; exit 1 ;;
esac

tor_dir=$(mktemp -d)
bundle_tmp=
tor_pid=
cleanup() {
  if [ -n "$tor_pid" ]; then
    kill "$tor_pid" 2>/dev/null || true
    wait "$tor_pid" 2>/dev/null || true
  fi
  if [ -n "$bundle_tmp" ]; then
    rm -f "$bundle_tmp"
  fi
  rm -rf "$tor_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

bootstrap_log="$tor_dir/bootstrap.log"
touch "$tor_dir/torrc" "$bootstrap_log"
tor -f "$tor_dir/torrc" --ClientOnly 1 --DataDirectory "$tor_dir" \
  --SocksPort 127.0.0.1:9050 --Log 'notice stdout' >"$bootstrap_log" 2>&1 &
tor_pid=$!

bootstrap_timeout=120
echo "Waiting up to ${bootstrap_timeout}s for Tor to bootstrap."
elapsed=0
next_line=1
while :; do
  last_line=$(wc -l < "$bootstrap_log")
  if [ "$last_line" -ge "$next_line" ]; then
    messages=$(sed -n "${next_line},${last_line}p" "$bootstrap_log")
    printf '%s\n' "$messages"
    next_line=$((last_line + 1))
    case "$messages" in
      *'Bootstrapped 100%'*) break ;;
    esac
  fi

  if ! kill -0 "$tor_pid" 2>/dev/null; then
    echo "Tor exited before finishing bootstrap." >&2
    exit 1
  fi
  if [ "$elapsed" -ge "$bootstrap_timeout" ]; then
    echo "Tor bootstrap timed out after ${bootstrap_timeout}s." >&2
    exit 1
  fi
  if [ "$elapsed" -gt 0 ] && [ "$((elapsed % 15))" -eq 0 ]; then
    echo "Still waiting for Tor to bootstrap (${elapsed}s/${bootstrap_timeout}s)."
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

echo "Tor is ready."
bundle_tmp=$(mktemp /reseed/.i2pseeds.su3.XXXXXX)
for url do
  printf 'Downloading the reseed bundle through Tor from %s\n' "$url"
  : > "$bundle_tmp"
  # Ignore curl config and proxy-bypass variables. Resolve the hostname through Tor.
  if ! curl -q --globoff --fail --silent --show-error --proto '=https' \
    --http1.1 --user-agent 'Wget/1.11.4' \
    --proxy socks5h://127.0.0.1:9050 --noproxy '' \
    --connect-timeout 30 --max-time 60 --output "$bundle_tmp" -- "$url"; then
    continue
  fi

  if [ "$(head -c 6 "$bundle_tmp")" != I2Psu3 ]; then
    echo "The download is not an SU3 bundle." >&2
    continue
  fi

  # i2pd verifies the signature before importing the bundle.
  chmod 0644 "$bundle_tmp"
  mv -fT "$bundle_tmp" /reseed/i2pseeds.su3
  echo "Reseed bundle saved. i2pd will verify it when it needs peers."
  exit 0
done

echo "Could not download an SU3 bundle through Tor." >&2
exit 1
