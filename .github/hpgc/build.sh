#!/bin/bash
# Builds GenomicsDB and its jar as a distributable library, runs the C++ tests, and checks that the native library
# depends at run time only on glibc and zlib and that the jar loads it. Uses GCC on x86-64 and clang on aarch64.
# Run from the repository root inside the .github/hpgc image.
#
# usage: build.sh <version> <deps dir> [cmake options...]
set -euo pipefail
VERSION=$1
DEPS_DIR=$2
shift 2
source /opt/rh/gcc-toolset-15/enable
if [ "$(uname -m)" = aarch64 ]; then export CC=clang CXX=clang++; else export CC=gcc CXX=g++; fi
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export MAVEN_ARGS="-Dgenomicsdb.version=$VERSION"

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_JAVA=1 -DUSE_HDFS=0 -DDISABLE_MPI=1 \
  -DBUILD_DISTRIBUTABLE_LIBRARY=1 -DGENOMICSDB_DEPS_DIR="$DEPS_DIR" -DGENOMICSDB_RELEASE_VERSION="$VERSION" "$@"
cmake --build build --target "genomicsdb-$VERSION-examples" ctests api_tests -j "$(nproc)"
(cd build/src/test/cpp && ./ctests -d yes && ./api_tests -d yes)
unexpected=$(readelf -d build/src/main/libtiledbgenomicsdb.so | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' \
  | grep -vxE 'libc\.so\.6|libm\.so\.6|libdl\.so\.2|libpthread\.so\.0|librt\.so\.1|ld-linux-(x86-64|aarch64)\.so\.[12]|libz\.so\.1' \
  || true)
if [ -n "$unexpected" ]; then
  echo "The native library depends on more than glibc and zlib: $unexpected" >&2
  exit 1
fi
java -cp "build/target/genomicsdb-$VERSION-allinone-spark.jar" .github/hpgc/SmokeLoadNativeLib.java
