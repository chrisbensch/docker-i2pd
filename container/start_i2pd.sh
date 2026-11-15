#!/bin/sh

set -e

datadir=/var/lib/i2pd
mkdir -p "$datadir"

for file in i2pd.conf subscriptions.txt tunnels.conf; do
  destination="$datadir/$file"
  if [ ! -e "$destination" ]; then
    cp "/etc/i2pd/$file" "$destination.tmp"
    mv "$destination.tmp" "$destination"
  fi
done

case "${PARAMS:-}" in
  ""|none|0) ;;
  *)
    # Keep support for whitespace-separated options without expanding globs.
    set -f
    set -- $PARAMS "$@"
    ;;
esac

exec i2pd --service --datadir="$datadir" --conf="$datadir/i2pd.conf" \
  --certsdir=/usr/share/i2pd/certificates "$@"
