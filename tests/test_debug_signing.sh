#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -f "$test_dir"/*.keystore; rmdir "$test_dir"' EXIT
helper="$repo_root/scripts/prepare_debug_keystore.sh"

keytool -genkeypair -keystore "$test_dir/source.keystore" -storepass android \
  -alias androiddebugkey -keypass android -dname 'CN=Android Debug,O=Android,C=US' \
  -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
export IDLECITY_DEBUG_KEYSTORE_BASE64
IDLECITY_DEBUG_KEYSTORE_BASE64=$(base64 < "$test_dir/source.keystore" | tr -d '\n')

bash "$helper" trusted "$test_dir/trusted-one.keystore"
bash "$helper" trusted "$test_dir/trusted-two.keystore"
cmp "$test_dir/source.keystore" "$test_dir/trusted-one.keystore"
cmp "$test_dir/trusted-one.keystore" "$test_dir/trusted-two.keystore"

# A fork must never consume the persistent key, even if one is present.
bash "$helper" untrusted "$test_dir/fork.keystore"
if cmp -s "$test_dir/source.keystore" "$test_dir/fork.keystore"; then
  echo 'Fork build unexpectedly reused the trusted key' >&2
  exit 1
fi
keytool -list -keystore "$test_dir/fork.keystore" -storepass android \
  -alias androiddebugkey >/dev/null

unset IDLECITY_DEBUG_KEYSTORE_BASE64
if bash "$helper" trusted "$test_dir/missing.keystore" >/dev/null 2>&1; then
  echo 'Trusted signing accepted a missing key' >&2
  exit 1
fi
test ! -e "$test_dir/missing.keystore"

export IDLECITY_DEBUG_KEYSTORE_BASE64='not-a-valid-keystore'
if bash "$helper" trusted "$test_dir/invalid.keystore" >/dev/null 2>&1; then
  echo 'Trusted signing accepted an invalid key' >&2
  exit 1
fi
test ! -e "$test_dir/invalid.keystore"
echo 'PASS: debug signing isolation and key reuse'
