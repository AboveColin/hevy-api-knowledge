#!/usr/bin/env bash
# Tripwire against leaking real account data into the published references.
# Correct content never touches these patterns. Scoped to skills/ because the
# repo owner's GitHub handle legitimately appears in README and LICENSE.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
fail=0

check() {
  local label="$1" pattern="$2"
  local hits
  hits=$(grep -rniE "$pattern" skills/ 2>/dev/null) || return 0
  printf '%s\n' "BLOCKED: $label"
  printf '%s\n' "$hits" | head -5
  fail=1
}

check "bearer token"            'Bearer [A-Za-z0-9+/=_-]{16,}'
check "auth-token header value" 'auth-token: *[0-9a-f]{8}-'
check "live access token"       '"(access_token|refresh_token|secret)": *"[A-Za-z0-9+/=_-]{16,}"'
# Matches the shape of the client's static key (a multi-word snake_case
# literal on the x-api-key row) rather than the string itself, so this file
# does not publish the value it exists to keep out.
check "app API key literal"     'x-api-key.*[a-z]{4,}_[a-z]{4,}_[a-z]{3,}'
check "profile image CDN path"  'cloudfront\.net/profile-images'
check "real email"              '[a-z0-9._%+-]+@(gmail|hotmail|outlook|icloud|proton|yahoo)\.'

if [ "$fail" -ne 0 ]; then
  echo
  echo "Scrub check failed. Replace the values above with placeholders."
  exit 1
fi
echo "scrub-check: clean"
