#!/bin/bash
# Makes the bundle the Maven Central Portal takes for com.tfenne:genomicsdb: the jar, its pom and its sources and
# javadoc jars in Maven's repository layout, each signed with GPG and with MD5 and SHA-1 checksums. GPG_KEY_ID, if
# set, picks the signing key, else GPG's default key signs. GPG_PASSPHRASE, if set, unlocks the key; otherwise
# gpg-agent asks for the passphrase.
#
# usage: central_bundle.sh <version> <dir with genomicsdb-<version>{.jar,.pom,-sources.jar,-javadoc.jar}> <bundle.zip>
set -euo pipefail
VERSION=$1
IN=$(cd "$2" && pwd)
BUNDLE=$(cd "$(dirname "$3")" && pwd)/$(basename "$3")
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

gpg_options=(--batch --yes --armor --detach-sign)
if [ -n "${GPG_KEY_ID:-}" ]; then gpg_options+=(--local-user "$GPG_KEY_ID"); fi
if [ -n "${GPG_PASSPHRASE:-}" ]; then gpg_options+=(--pinentry-mode loopback --passphrase "$GPG_PASSPHRASE"); fi

DIR="$STAGE/com/tfenne/genomicsdb/$VERSION"
mkdir -p "$DIR"
for suffix in .jar .pom -sources.jar -javadoc.jar; do
  file="genomicsdb-$VERSION$suffix"
  cp "$IN/$file" "$DIR/$file"
  gpg "${gpg_options[@]}" --output "$DIR/$file.asc" "$DIR/$file"
  gpg --batch --verify "$DIR/$file.asc" "$DIR/$file"
  for algorithm in md5 sha1; do
    openssl dgst "-$algorithm" -r "$DIR/$file" | cut -d' ' -f1 > "$DIR/$file.$algorithm"
  done
done
rm -f "$BUNDLE"
(cd "$STAGE" && zip -q -r "$BUNDLE" com)
unzip -l "$BUNDLE"
