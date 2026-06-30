# Next steps

## 1. Create the empty repo on GitHub

Don't init with README on github.com — let our local commit be the first commit.

Using the `gh` CLI (run from inside `ga-aem-python-colab/`):
```bash
gh repo create AUProbGeo/ga-aem-python-colab --public --source . --remote origin --push
```

Or create it manually on github.com and then:
```bash
git remote add origin git@github.com:AUProbGeo/ga-aem-python-colab.git
git push -u origin main
```

## 2. Trigger a test build (no release)

Push to `main` → watch the Actions tab. Both wheels appear as downloadable
artifacts. Confirm the import test passes (the workflow runs
`python -c "import gatdaem1d"` in a clean venv with no FFTW installed).

## 3. Cut the first release

```bash
git tag gatdaem1d-v2.0.3
git push origin gatdaem1d-v2.0.3
```
→ workflow creates a Release with both wheels + the install URLs pre-filled
in the release body.

## 4. Test on Colab

Paste this into a Colab notebook cell:
```python
!pip install https://github.com/AUProbGeo/ga-aem-python-colab/releases/latest/download/ga_aem_forward_linux-2.0.3-1-py3-none-manylinux_2_35_x86_64.whl
import gatdaem1d
print(gatdaem1d.__file__)
```

If the AVX2 wheel crashes with `SIGILL`, swap to the baseline fallback
(the `-0-` build):
```python
!pip install https://github.com/AUProbGeo/ga-aem-python-colab/releases/latest/download/ga_aem_forward_linux-2.0.3-0-py3-none-manylinux_2_35_x86_64.whl
```

## 5. Publish to PyPI

PyPI name: `ga-aem-forward-linux`  (import: `gatdaem1d`)

### Option A — CI auto-publish (Trusted Publishing, recommended)
One-time setup on https://pypi.org/manage/account/publishing/ → "Add a pending publisher":
- PyPI project name: `ga-aem-forward-linux`
- Owner: `AUProbGeo`
- Repository: `ga-aem-python-colab`
- Workflow: `build-gatdaem1d-wheel.yml`
- Environment: `pypi`

After this, every `gatdaem1d-v*` tag push auto-publishes to PyPI. No API tokens needed.

> Note: Trusted Publishing requires the PyPI project to exist first for the
> publisher to be "activated". For the very first release, either:
> - create the project on PyPI manually via `pypi_build_script` (Option B), then
>   add the Trusted Publisher, or
> - add the publisher as "pending" before the first release — PyPI will create
>   the project automatically on first publish.

### Option B — Local manual publish (first upload / manual control)
```bash
./pypi_build_script                 # downloads wheels from latest Release
./pypi_build_script gatdaem1d-v2.0.3 # specific tag
```
Prompts for TestPyPI then PyPI. Requires `twine` and credentials in `~/.pypirc`.

After PyPI publish, install with:
```bash
pip install ga-aem-forward-linux
```

## Caveats to be aware of

- **The build script was not run locally** (no Docker on this machine) — the
  shell script and YAML are syntax-checked only. First CI run is the real test.
  If `auditwheel` complains about the `$ORIGIN` rpath (it sometimes does), the
  workflow has a fallback step that manually retags the wheel — the bundling
  already happened via the build script, so the wheel is still self-contained.

- **Wheel filename**: `py3-none-manylinux_2_35_x86_64` assumes auditwheel
  succeeds. If the fallback path runs, the platform tag is still
  `manylinux_2_35_x86_64` (set manually). The `-1-`/`-0-` build numbers are
  what differentiate AVX2 vs baseline in pip's resolver.

- **Version `2.0.3`** comes from upstream's `pyproject.toml`. To bump it,
  either patch it in the build script after clone, or fork ga-aem and point the
  build script at your fork (`scripts/cmake_build_script_colab_gatdaem1d.sh`,
  the `git clone` line).