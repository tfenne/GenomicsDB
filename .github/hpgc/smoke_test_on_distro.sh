#!/bin/sh
# Runs in a plain Linux distribution image: installs a JDK, checks that every library the jar's native library for
# this machine depends on is present, and loads it in a JVM.
#
# usage: smoke_test_on_distro.sh <jar with its dependencies, e.g. genomicsdb-<version>-allinone-spark.jar>
set -e
JAR=$1
if command -v dnf >/dev/null; then
  if grep -q "Amazon Linux" /etc/os-release; then JDK=java-17-amazon-corretto-devel; else JDK=java-17-openjdk-devel; fi
  dnf -y -q install "$JDK" unzip >/dev/null
else
  apt-get -qq update >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get -qq install -y openjdk-17-jdk-headless unzip >/dev/null
fi
. /etc/os-release
echo "$PRETTY_NAME, $(ldd --version | head -1)"
platform="linux-$(uname -m)"
unzip -q -o "$JAR" "$platform/libtiledbgenomicsdb.so" -d /tmp/native
if ldd "/tmp/native/$platform/libtiledbgenomicsdb.so" | grep "not found"; then
  exit 1
fi
java -cp "$JAR" "$(dirname "$0")/SmokeLoadNativeLib.java"
