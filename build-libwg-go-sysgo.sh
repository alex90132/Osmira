#!/usr/bin/env bash
# Builds libwg-go.so with the SYSTEM Go toolchain (no download), cross-compiling
# via the Android NDK clang. Optionally uses a boottime-patched GOROOT if present.
# Output: staging/jniLibs/<abi>/libwg-go.so
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LIBWG_SRC="$HERE/refs/amneziawg-android/tunnel/tools/libwg-go"
NDK="${ANDROID_NDK:-$HOME/Android/sdk/ndk/27.0.12077973}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
SYSROOT="$TOOLCHAIN/sysroot"
CLANG="$TOOLCHAIN/bin/clang"
API=24
PKG="osmi.awg2"
OUT="$HERE/staging/jniLibs"

# Prefer a locally patched GOROOT if we managed to build one; else system Go.
if [ -x "$HERE/.goroot-patched/bin/go" ]; then
  export GOROOT="$HERE/.goroot-patched"
  GO="$HERE/.goroot-patched/bin/go"
  echo "Using boottime-patched GOROOT: $GOROOT"
else
  GO="$(command -v go)"
  echo "Using system Go: $GO ($($GO version))"
fi

export GOMODCACHE="$HERE/.gomodcache"
export CGO_ENABLED=1
export GOOS=android

declare -A GOARCH_MAP=( [arm64-v8a]=arm64 [x86_64]=amd64 [armeabi-v7a]=arm )
declare -A TRIPLE=( [arm64-v8a]=aarch64-linux-android$API [x86_64]=x86_64-linux-android$API [armeabi-v7a]=armv7a-linux-androideabi$API )

ABIS=("$@"); [ "$#" -eq 0 ] && ABIS=(arm64-v8a x86_64)

cd "$LIBWG_SRC"
echo "== go mod tidy (system go) =="
"$GO" mod tidy || true

for abi in "${ABIS[@]}"; do
  echo "==================== building $abi ===================="
  dest="$OUT/$abi"; mkdir -p "$dest"
  triple="${TRIPLE[$abi]}"
  clangflags="--target=$triple --sysroot=$SYSROOT"
  export GOARCH="${GOARCH_MAP[$abi]}"
  [ "$abi" = "armeabi-v7a" ] && export GOARM=7 || unset GOARM
  export CC="$CLANG"
  export CGO_CFLAGS="$clangflags"
  export CGO_LDFLAGS="$clangflags -Wl,-soname=libwg-go.so"
  "$GO" build -tags linux \
     -ldflags="-X github.com/amnezia-vpn/amneziawg-go/ipc.socketDirectory=/data/data/$PKG/cache/amneziawg -buildid=" \
     -trimpath -buildvcs=false \
     -o "$dest/libwg-go.so" -buildmode=c-shared
  rm -f "$dest/libwg-go.h"
  echo "-> $dest/libwg-go.so"; file "$dest/libwg-go.so"
done
echo "ALL_DONE"
