#!/usr/bin/env bash
# Builds libwg-go.so (amneziawg-go c-shared + JNI bridge) for Android ABIs.
# Output: staging/jniLibs/<abi>/libwg-go.so
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LIBWG_SRC="$HERE/refs/amneziawg-android/tunnel/tools/libwg-go"
NDK="${ANDROID_NDK:-$HOME/Android/sdk/ndk/27.0.12077973}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
SYSROOT="$TOOLCHAIN/sysroot"
CLANG="$TOOLCHAIN/bin/clang"
API=24
PKG="com.awg2.client"
export GRADLE_USER_HOME="$HERE/.gohome"   # go tarball is cached here by the Makefile
OUT="$HERE/staging/jniLibs"

mkdir -p "$OUT"

# ABI -> (ANDROID_ARCH_NAME, clang target triple)
declare -A ARCH=( [arm64-v8a]=arm64 [x86_64]=x86_64 [armeabi-v7a]=arm )
declare -A TRIPLE=( [arm64-v8a]=aarch64-linux-android$API [x86_64]=x86_64-linux-android$API [armeabi-v7a]=armv7a-linux-androideabi$API )

ABIS=("${@:-arm64-v8a x86_64}")
# allow space-separated single arg
if [ "$#" -eq 0 ]; then ABIS=(arm64-v8a x86_64); fi

for abi in "${ABIS[@]}"; do
  echo "==================== building $abi ===================="
  arch="${ARCH[$abi]}"
  triple="${TRIPLE[$abi]}"
  dest="$OUT/$abi"
  build="$HERE/staging/build-$abi"
  mkdir -p "$dest" "$build"
  # -z max-page-size=16384 aligns the ELF LOAD segments to 16 KB so the lib
  # is compatible with Android 15's 16 KB page-size devices (NDK r27 still
  # defaults to 4 KB).
  make -C "$LIBWG_SRC" \
     ANDROID_ARCH_NAME="$arch" \
     ANDROID_PACKAGE_NAME="$PKG" \
     GRADLE_USER_HOME="$GRADLE_USER_HOME" \
     CC="$CLANG" \
     CFLAGS="" \
     LDFLAGS="-Wl,-z,max-page-size=16384,-z,common-page-size=16384" \
     SYSROOT="$SYSROOT" \
     TARGET="$triple" \
     DESTDIR="$dest" \
     BUILDDIR="$build"
  echo "-> $dest/libwg-go.so"
  ls -la "$dest"
  file "$dest/libwg-go.so" || true
done
echo "ALL_DONE"
