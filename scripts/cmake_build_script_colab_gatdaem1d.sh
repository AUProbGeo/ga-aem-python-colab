#!/bin/sh
#
# Portable build script for ga-aem's gatdaem1d shared library, targeting
# Google Colab (and other modern x86_64 Linux systems with glibc >= 2.35).
#
# Produces a self-contained gatdaem1d.so that:
#   * is built with portable CPU flags (no -march=native), so it runs on any
#     modern x86_64 VM (Colab runs on Xeons that support AVX2 / x86-64-v3).
#   * bundles libfftw3.so.3 next to it and uses an $ORIGIN rpath, so no
#     apt install of libfftw3 is needed on the target machine.
#
# This script is idempotent: safe to re-run. It is used by the GitHub Actions
# workflow in .github/workflows/build-gatdaem1d-wheel.yml, but can also be
# run locally inside an ubuntu:22.04 docker container:
#
#   docker run --rm -v "$PWD":/work -w /work ubuntu:22.04 \
#       ./scripts/cmake_build_script_colab_gatdaem1d.sh
#
# Usage:
#   ./scripts/cmake_build_script_colab_gatdaem1d.sh [cpu_target]
#
#   cpu_target : x86-64-v3 (default, AVX2) | x86-64 (baseline fallback)
#
set -e
set -x

CPU_TARGET="${1:-x86-64-v3}"

# ---------------------------------------------------------------------------
# 1. Install build dependencies (no-op if already present)
# ---------------------------------------------------------------------------
PREFIX=
if command -v sudo >/dev/null 2>&1; then
    PREFIX=sudo
fi

$PREFIX sh -c '
    apt-get update &&
    apt-get install -y --no-install-recommends \
        build-essential libfftw3-dev libfftw3-double3 cmake pkg-config git \
        python3 python3-pip patchelf &&
    apt-get clean'

# ---------------------------------------------------------------------------
# 2. Clone ga-aem (shallow, with the C++ submodules we need)
# ---------------------------------------------------------------------------
WORKDIR="${WORKDIR:-$PWD}"
SRC_DIR="$WORKDIR/ga-aem-src"

if ! test -d "$SRC_DIR"; then
    git clone --recursive --depth 1 \
        https://github.com/GeoscienceAustralia/ga-aem.git "$SRC_DIR"
else
    echo "Reusing existing checkout at $SRC_DIR"
fi

# ---------------------------------------------------------------------------
# 3. Configure & build with portable flags
# ---------------------------------------------------------------------------
BUILD_DIR="$SRC_DIR/build-colab-$CPU_TARGET"
INSTALL_DIR="$SRC_DIR/install-colab-$CPU_TARGET"

rm -rf "$BUILD_DIR" "$INSTALL_DIR"
mkdir -p "$BUILD_DIR"

# Translate the generic CPU_TARGET into exact -march / -mtune flags.
case "$CPU_TARGET" in
    x86-64-v3) ARCH_FLAGS="-march=x86-64-v3 -mtune=haswell" ;;
    x86-64)    ARCH_FLAGS="-march=x86-64 -mtune=generic"    ;;
    *) echo "ERROR: unknown cpu_target '$CPU_TARGET' (use x86-64-v3 or x86-64)" >&2; exit 1 ;;
esac

OPT_FLAGS="-O3 $ARCH_FLAGS -DNDEBUG -ffast-math -funroll-loops"

# -Wl,-rpath,$ORIGIN makes gatdaem1d.so look for libfftw3.so.3 in its own
# directory, so bundling the lib next to the .so "just works" at import time.
RPATH_FLAG="-Wl,-rpath,\$ORIGIN"

cmake -S "$SRC_DIR" -B "$BUILD_DIR" -Wno-dev \
    -DCMAKE_C_COMPILER=gcc \
    -DCMAKE_CXX_COMPILER=g++ \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS_RELEASE="$OPT_FLAGS" \
    -DCMAKE_CXX_FLAGS_RELEASE="$OPT_FLAGS $RPATH_FLAG" \
    -DCMAKE_EXE_LINKER_FLAGS="$RPATH_FLAG" \
    -DCMAKE_SHARED_LINKER_FLAGS="$RPATH_FLAG" \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DWITH_MPI=OFF \
    -DWITH_NETCDF=OFF \
    -DWITH_GDAL=OFF \
    -DWITH_PETSC=OFF

cmake --build "$BUILD_DIR" --target python-bindings --config=Release -j"$(nproc)"
cmake --install "$BUILD_DIR" --prefix "$INSTALL_DIR"

# ---------------------------------------------------------------------------
# 4. Make the python package self-contained: bundle fftw + force rpath
# ---------------------------------------------------------------------------
PKG_DIR="$INSTALL_DIR/python/gatdaem1d"
SO_FILE="$PKG_DIR/gatdaem1d.so"

if [ ! -f "$SO_FILE" ]; then
    echo "ERROR: expected $SO_FILE not found" >&2
    exit 1
fi

# Copy the actual fftw library the .so was linked against (resolve symlinks).
FFTW_LIB=$(ldd "$SO_FILE" | awk '/libfftw3\.so/ {print $3}' | head -n1)
if [ -z "$FFTW_LIB" ]; then
    echo "ERROR: gatdaem1d.so does not link libfftw3.so.3" >&2
    exit 1
fi
cp -L "$FFTW_LIB" "$PKG_DIR/libfftw3.so.3"

# Belt-and-suspenders: force rpath to $ORIGIN even if the linker flag was
# stripped somewhere in the cmake toolchain.
patchelf --set-rpath '$ORIGIN' "$SO_FILE" || {
    echo "WARNING: patchelf failed to set rpath on $SO_FILE" >&2
}

# Sanity-check: the .so should now resolve libfftw3 from its own dir.
echo "--- ldd (after rpath + bundle) ---"
ldd "$SO_FILE" | grep -E 'libfftw3|libstdc\+\+|libc\.so' || true

# ---------------------------------------------------------------------------
# 5. Stage the python package directory ready for `pip wheel`
# Output: $WHEEL_STAGING_DIR/python  (containing pyproject.toml + gatdaem1d/)
# ---------------------------------------------------------------------------
WHEEL_STAGING_DIR="${WHEEL_STAGING_DIR:-$WORKDIR/wheel-stage-$CPU_TARGET}"
rm -rf "$WHEEL_STAGING_DIR"
mkdir -p "$WHEEL_STAGING_DIR"
cp -a "$INSTALL_DIR/python/." "$WHEEL_STAGING_DIR/python/"

echo "--- staged package contents ---"
ls -la "$WHEEL_STAGING_DIR/python/gatdaem1d/"

echo "DONE. Stage directory: $WHEEL_STAGING_DIR"
echo "Next: (cd $WHEEL_STAGING_DIR/python && pip wheel . -w $WHEEL_STAGING_DIR/wheels)"