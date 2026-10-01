#!/bin/bash
# Builds GenomicsDB and its jar as a distributable library, runs the C++ tests, and checks what the native library
# depends on at run time and that the jar loads it. On Linux, run from the repository root inside the .github/hpgc
# image, which builds with GCC on x86-64 and clang on aarch64; the library may depend only on glibc and zlib. On
# macOS, set MACOSX_DEPLOYMENT_TARGET; the library may depend only on macOS's own libraries and must target that
# version.
#
# usage: build.sh <version> <deps dir> [cmake options...]
set -euo pipefail
VERSION=$1
DEPS_DIR=$2
shift 2
export MAVEN_ARGS="-Dgenomicsdb.version=$VERSION"
if [ "$(uname)" = Darwin ]; then
  : "${MACOSX_DEPLOYMENT_TARGET:?must be set for a distributable macOS library, e.g. to 14.0}"
  LIB=build/src/main/libtiledbgenomicsdb.dylib
  JOBS=$(sysctl -n hw.ncpu)
else
  source /opt/rh/gcc-toolset-15/enable
  if [ "$(uname -m)" = aarch64 ]; then export CC=clang CXX=clang++; else export CC=gcc CXX=g++; fi
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
  LIB=build/src/main/libtiledbgenomicsdb.so
  JOBS=$(nproc)
fi

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_JAVA=1 -DUSE_HDFS=0 -DDISABLE_MPI=1 \
  -DBUILD_DISTRIBUTABLE_LIBRARY=1 -DGENOMICSDB_DEPS_DIR="$DEPS_DIR" -DGENOMICSDB_RELEASE_VERSION="$VERSION" "$@"
cmake --build build --target "genomicsdb-$VERSION-examples" ctests api_tests -j "$JOBS" 2>&1 | tee build/build.log
(cd build/src/test/cpp && ./ctests -d yes && ./api_tests -d yes)

if [ "$(uname)" = Darwin ]; then
  unexpected=$(otool -L "$LIB" | tail -n +2 | awk '{print $1}' \
    | grep -vE '^(@rpath/libtiledbgenomicsdb|/usr/lib/|/System/Library/)' || true)
  minos=$(vtool -show-build "$LIB" | awk '/minos/ {print $2}')
  if [ "${minos%.0}" != "${MACOSX_DEPLOYMENT_TARGET%.0}" ] || grep -q 'built for newer' build/build.log; then
    echo "The native library or something linked into it targets a newer macOS than $MACOSX_DEPLOYMENT_TARGET" >&2
    exit 1
  fi
else
  unexpected=$(readelf -d "$LIB" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' \
    | grep -vxE 'libc\.so\.6|libm\.so\.6|libdl\.so\.2|libpthread\.so\.0|librt\.so\.1|ld-linux-(x86-64|aarch64)\.so\.[12]|libz\.so\.1' \
    || true)
fi
if [ -n "$unexpected" ]; then
  echo "The native library depends on libraries that may be missing at run time: $unexpected" >&2
  exit 1
fi
java -cp "build/target/genomicsdb-$VERSION-allinone-spark.jar" .github/hpgc/SmokeLoadNativeLib.java
