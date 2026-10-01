#!/bin/bash
# Makes the bundle the Maven Central Portal takes for com.tfenne:genomicsdb: the jar, its pom and its sources and
# javadoc jars in Maven's repository layout, each signed with the default GPG key and with MD5 and SHA-1 checksums.
# GPG_PASSPHRASE, if set, unlocks the key.
#
# usage: central_bundle.sh <version> <dir with genomicsdb-<version>{.jar,.pom,-sources.jar,-javadoc.jar}> <bundle.zip>
set -euo pipefail
VERSION=$1
IN=$(cd "$2" && pwd)
BUNDLE=$(cd "$(dirname "$3")" && pwd)/$(basename "$3")
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

DIR="$STAGE/com/tfenne/genomicsdb/$VERSION"
mkdir -p "$DIR"
for suffix in .jar .pom -sources.jar -javadoc.jar; do
  file="genomicsdb-$VERSION$suffix"
  cp "$IN/$file" "$DIR/$file"
  gpg --batch --yes --pinentry-mode loopback ${GPG_PASSPHRASE:+--passphrase "$GPG_PASSPHRASE"} \
    --armor --detach-sign --output "$DIR/$file.asc" "$DIR/$file"
  for algorithm in md5 sha1; do
    openssl dgst "-$algorithm" -r "$DIR/$file" | cut -d' ' -f1 > "$DIR/$file.$algorithm"
  done
done
rm -f "$BUNDLE"
(cd "$STAGE" && zip -q -r "$BUNDLE" com)
unzip -l "$BUNDLE"
