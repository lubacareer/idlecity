#!/usr/bin/env bash
set -euo pipefail
umask 077

mode=${1:?Expected trusted or untrusted mode}
destination=${2:?Expected a destination for the debug keystore}
stage_dir=$(mktemp -d)
stage_key="$stage_dir/debug.keystore"
trap 'rm -f "$stage_key"; rmdir "$stage_dir"' EXIT

case "$mode" in
  trusted)
    if [[ -z ${IDLECITY_DEBUG_KEYSTORE_BASE64:-} ]]; then
      echo 'Missing persistent debug signing key for trusted build.' >&2
      exit 1
    fi
    printf '%s' "$IDLECITY_DEBUG_KEYSTORE_BASE64" | base64 --decode > "$stage_key"
    ;;
  untrusted)
    # Fork PRs use a new temporary key, even if a secret was injected by mistake.
    unset IDLECITY_DEBUG_KEYSTORE_BASE64
    keytool -genkeypair -keystore "$stage_key" -storepass android \
      -alias androiddebugkey -keypass android -dname 'CN=Android Debug,O=Android,C=US' \
      -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
    ;;
  *)
    echo 'Unknown debug signing mode.' >&2
    exit 1
    ;;
esac

# Fail before export if the supplied keystore or alias is unusable.
keytool -list -keystore "$stage_key" -storepass android -alias androiddebugkey >/dev/null 2>&1
mv -f "$stage_key" "$destination"
