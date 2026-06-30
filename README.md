# ga-aem-python-colab

Prebuilt `gatdaem1d` Python wheels for **Google Colab** (and other modern
x86_64 Linux systems with glibc >= 2.35).

`gatdaem1d` is the time-domain airborne electromagnetic forward-modelling
library from [GeoscienceAustralia/ga-aem](https://github.com/GeoscienceAustralia/ga-aem).
The upstream project ships a source build that requires a compiler and FFTW.
This repo packages **prebuilt, self-contained wheels** so that on Colab you can
just `pip install` and `import` — no `apt install`, no compiler.

**PyPI name:** `ga-aem-forward-linux`  **Import name:** `gatdaem1d`

## Install

### From PyPI (recommended — works on Colab and any modern Linux)
```bash
pip install ga-aem-forward-linux
```
pip automatically picks the AVX2 wheel (build `-1-`) on capable hosts.

### From GitHub Release (direct URL — for Colab notebooks or pinning a version)
Open a Colab notebook and run **one** of these in a cell:

**Recommended (AVX2 / x86-64-v3 — fastest, works on all modern Colab VMs):**
```python
!pip install https://github.com/AUProbGeo/ga-aem-python-colab/releases/latest/download/ga_aem_forward_linux-2.0.3-1-py3-none-manylinux_2_35_x86_64.whl
```

**Fallback (baseline x86-64 — use only if the AVX2 wheel crashes with `SIGILL`):**
```python
!pip install https://github.com/AUProbGeo/ga-aem-python-colab/releases/latest/download/ga_aem_forward_linux-2.0.3-0-py3-none-manylinux_2_35_x86_64.whl
```

> The `latest` URL redirects to the most recent `gatdaem1d-v*` release. To pin a
> specific version, replace `latest/download` with
> `download/gatdaem1d-v2.0.3`.

## Verify

```python
import gatdaem1d
print(gatdaem1d.__file__)
```

A quick functional test:
```python
import gatdaem1d
import numpy as np

earth = gatdaem1d.Earth(conductivity=[0.001, 0.01, 0.1], thickness=[20.0, 40.0])
geometry = gatdaem1d.Geometry(tx_height=30.0)
# see the upstream examples/ directory for full usage
```

## Why two wheels?

| Wheel | CPU target | When to use |
|-------|------------|-------------|
| `-1-` (default) | `x86-64-v3` (AVX2, Haswell) | Modern Colab VMs (Xeons). Fastest. |
| `-0-` (fallback) | `x86-64` (SSE2 baseline) | Exotic/old VMs where AVX2 is absent and the default wheel raises `SIGILL`. |

`pip` picks the higher build number by default, so `pip install ga-aem-forward-linux`
automatically gets the AVX2 variant.

## What's bundled

Each wheel contains, inside `gatdaem1d/`:
- `__init__.py` — the upstream ctypes wrapper
- `gatdaem1d.so` — the compiled forward-modelling library (portable flags, no `-march=native`)
- `libfftw3.so.3` — bundled FFTW, loaded via `$ORIGIN` rpath (no system FFTW needed)

External dependencies that remain (all present on Colab by default): glibc,
libstdc++, libgcc_s, libm.

## How the wheels are built

The GitHub Actions workflow (`.github/workflows/build-gatdaem1d-wheel.yml`)
runs on `ubuntu-22.04` (matching Colab's glibc 2.35):

1. Clone ga-aem shallow + recursive submodules.
2. `cmake` build with `-O3 -march=x86-64-v3 -ffast-math` (or `-march=x86-64` for fallback).
3. `patchelf --set-rpath '$ORIGIN'` on `gatdaem1d.so` and copy `libfftw3.so.3` next to it.
4. `pip wheel` → `auditwheel repair` (tags `manylinux_2_35_x86_64`, bundles libstdc++).
5. Import test in a clean venv **without** FFTW installed (proves self-containment).
6. On `gatdaem1d-v*` tags: creates a GitHub Release with both wheels and publishes to PyPI via Trusted Publishing.

## Building locally (for testing)

You don't need to run CI to test the build — use Docker to match Colab exactly:

```bash
# AVX2 wheel
docker run --rm -v "$PWD":/work -w /work ubuntu:22.04 \
    bash scripts/cmake_build_script_colab_gatdaem1d.sh x86-64-v3

# Baseline wheel
docker run --rm -v "$PWD":/work -w /work ubuntu:22.04 \
    bash scripts/cmake_build_script_colab_gatdaem1d.sh x86-64
```

Then build the wheel from the staging dir:
```bash
pip install wheel auditwheel
(cd wheel-stage-x86-64-v3/python && pip wheel . -w ../wheels --no-deps)
auditwheel repair --plat manylinux_2_35_x86_64 wheel-stage-x86-64-v3/wheels/*.whl
```

## Releasing a new version

1. The version is read from upstream's `pyproject.toml` (currently `2.0.3`).
   To override, patch it in `scripts/cmake_build_script_colab_gatdaem1d.sh`
   (the `sed` line under "2b. Patch upstream pyproject.toml").
2. Tag and push:
   ```bash
   git tag gatdaem1d-v2.0.3
   git push origin gatdaem1d-v2.0.3
   ```
3. The workflow builds both wheels, publishes a GitHub Release, and uploads to PyPI via Trusted Publishing (one-time setup on pypi.org — see below). The `latest` install URL automatically points to it.

## Publishing to PyPI

PyPI name: `ga-aem-forward-linux`. Two ways to publish:

### CI auto-publish (Trusted Publishing — recommended)
One-time setup on https://pypi.org/manage/account/publishing/ → "Add a pending publisher":
- PyPI project name: `ga-aem-forward-linux`
- Owner: `AUProbGeo`
- Repository: `ga-aem-python-colab`
- Workflow: `build-gatdaem1d-wheel.yml`
- Environment: `pypi`

After this, every `gatdaem1d-v*` tag push auto-publishes to PyPI. No API tokens needed.

### Local manual publish (`pypi_build_script`)
For the first upload (before Trusted Publishing is configured) or manual control:
```bash
./pypi_build_script                 # downloads wheels from latest Release
./pypi_build_script gatdaem1d-v2.0.3 # specific tag
```
Prompts for TestPyPI then PyPI. Requires `twine` and credentials in `~/.pypirc`.

## Source build fallback (non-Colab Linux)

If you're on a Linux where no prebuilt wheel fits (different arch, older glibc),
build from source the upstream way:

```bash
git clone --recursive https://github.com/GeoscienceAustralia/ga-aem.git
cd ga-aem
bash cmake_build_script_DebianUbuntu_gatdaem1d.sh
```

## Credits

- `gatdaem1d` C++ library and Python wrapper: **Ross C. Brodie**, GeoscienceAustralia — see [upstream licence](https://github.com/GeoscienceAustralia/ga-aem/blob/master/LICENCE.txt) (GPLv2).
- This packaging repo: AUProbGeo.