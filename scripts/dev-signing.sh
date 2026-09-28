#!/usr/bin/env bash
# Project-local code signing identity for development builds.
#
# Why: an ad-hoc signature ("-") changes with every build, and macOS then treats each build as
# a new app, so the Accessibility permission has to be granted again after every rebuild.
# Signing with a fixed (self-signed) certificate gives a stable designated requirement
#   identifier "com.alencup.MonitorHop" and certificate leaf = H"…"
# so the permission survives rebuilds.
#
# Everything lives in ./.signing (git-ignored): a dedicated keychain with a random password.
# Nothing is added to your login keychain and no trust settings are changed.
#
#   scripts/dev-signing.sh ensure          create the identity if missing, print its SHA-1
#   scripts/dev-signing.sh sign <path>...  sign bundles with it
#   scripts/dev-signing.sh remove          delete ./.signing
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/.signing"
KEYCHAIN="$DIR/MonitorHop-dev.keychain-db"
PASSWORD_FILE="$DIR/keychain-password"
NAME="MonitorHop Local Signing"
BUNDLE_ID="com.alencup.MonitorHop"
OPENSSL=/usr/bin/openssl   # LibreSSL: writes PKCS#12 files that `security import` understands

identity_hash() {
    security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | awk -v n="\"$NAME\"" 'index($0, n) {print $2; exit}'
}

ensure() {
    if [ -f "$KEYCHAIN" ] && [ -f "$PASSWORD_FILE" ] && [ -n "$(identity_hash)" ]; then
        identity_hash
        return
    fi
    rm -rf "$DIR"
    mkdir -p "$DIR"
    chmod 700 "$DIR"
    local tmp password
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    password="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
    printf '%s' "$password" > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"

    cat > "$tmp/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF
    "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" \
        -keyout "$tmp/key.pem" -out "$tmp/cert.pem" >/dev/null 2>&1
    "$OPENSSL" pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$NAME" \
        -out "$tmp/identity.p12" -passout "pass:$password" >/dev/null 2>&1

    security create-keychain -p "$password" "$KEYCHAIN"
    security set-keychain-settings "$KEYCHAIN"            # never auto-lock
    security unlock-keychain -p "$password" "$KEYCHAIN"
    security import "$tmp/identity.p12" -k "$KEYCHAIN" -P "$password" -T /usr/bin/codesign >/dev/null
    # Let codesign use the key without a GUI prompt.
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$KEYCHAIN" >/dev/null
    local hash
    hash="$(identity_hash)"
    [ -n "$hash" ] || { echo "error: failed to create signing identity" >&2; exit 1; }
    echo "$hash"
}

sign() {
    local hash password original
    hash="$(ensure)"
    password="$(cat "$PASSWORD_FILE")"
    security unlock-keychain -p "$password" "$KEYCHAIN"
    # codesign only finds private keys in keychains on the search list: add ours temporarily.
    original="$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')"
    restore() {
        # shellcheck disable=SC2086
        eval security list-keychains -d user -s $(printf '%q ' $original)
    }
    trap restore EXIT
    # shellcheck disable=SC2086
    eval security list-keychains -d user -s $(printf '%q ' $original) "$(printf '%q' "$KEYCHAIN")"
    for path in "$@"; do
        codesign --force --sign "$hash" --identifier "$BUNDLE_ID" "$path"
    done
    restore
    trap - EXIT
}

case "${1:-}" in
    ensure) ensure ;;
    sign) shift; sign "$@" ;;
    remove) rm -rf "$DIR"; echo "removed $DIR" ;;
    *) echo "usage: $0 ensure | sign <bundle>... | remove" >&2; exit 2 ;;
esac
