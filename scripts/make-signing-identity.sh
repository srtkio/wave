#!/bin/bash
# One-time: create a self-signed "Wave Local Signing" code-signing identity in the login keychain.
# build.sh signs with it so macOS remembers Camera/Accessibility permission across rebuilds.
set -euo pipefail
if security find-identity -p codesigning | grep -q "Wave Local Signing"; then echo "already set up"; exit 0; fi
t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
openssl req -x509 -newkey rsa:2048 -keyout "$t/key.pem" -out "$t/cert.pem" -days 3650 -nodes \
  -subj "/CN=Wave Local Signing" \
  -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false"
openssl pkcs12 -export -legacy -out "$t/wave.p12" -inkey "$t/key.pem" -in "$t/cert.pem" \
  -name "Wave Local Signing" -passout pass:wave
security import "$t/wave.p12" -k ~/Library/Keychains/login.keychain-db -P wave -T /usr/bin/codesign
echo "created 'Wave Local Signing'"
