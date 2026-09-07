#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# fresh_venv_test.bash
#
# Build a fresh, self-contained Python venv for the AsyncVLA action-head / sys1
# node on this Jetson (jon10: aarch64, JetPack 6 / L4T r36.4, CUDA 12.6, Py 3.10).
#
# This reproduces, from scratch, the recipe that produced the working
# ~/venvs/asclinic_vla_action_head (bash-history lines 1392-1451, 1601, 1929):
#
#   1. plain `python3 -m venv`  --  NO --system-site-packages.
#      (the system python on this box has no torch to inherit anyway)
#   2. torch / torchvision from the jetson-ai-lab index (not on PyPI for aarch64)
#   3. inference deps pinned to the EXACT versions in the working venv
#   4. vint_train installed editable, --no-deps
#
# It builds into a SEPARATE directory (default ~/venvs/fresh_venv_test) so your
# current venv is never touched, then diffs `pip freeze` against the reference
# venv so you can confirm the two match.
#
# Usage:
#   bash tools/fresh_venv_test.bash [--force]
#
# Overridable via env:
#   VENV_DIR      target venv dir            (default ~/venvs/fresh_venv_test)
#   ASYNCVLA_DIR  AsyncVLA repo checkout     (default ~/asyncvla-test/AsyncVLA)
#   REF_VENV      venv to diff against       (default ~/venvs/asclinic_vla_action_head)
#   PYTHON        interpreter to build from  (default /usr/bin/python3)
# ------------------------------------------------------------------------------

VENV_DIR="${VENV_DIR:-$HOME/venvs/fresh_venv_test}"
ASYNCVLA_DIR="${ASYNCVLA_DIR:-$HOME/asyncvla-test/AsyncVLA}"
REF_VENV="${REF_VENV:-$HOME/venvs/asclinic_vla_action_head}"
PYTHON="${PYTHON:-/usr/bin/python3}"
JETSON_INDEX="https://pypi.jetson-ai-lab.io/jp6/cu126"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

VINT_TRAIN_DIR="$ASYNCVLA_DIR/visualnav-transformer/train"

echo "=== fresh_venv_test ==="
echo "  VENV_DIR     = $VENV_DIR"
echo "  ASYNCVLA_DIR = $ASYNCVLA_DIR"
echo "  REF_VENV     = $REF_VENV"
echo "  PYTHON       = $PYTHON  ($($PYTHON --version 2>&1))"
echo

# --- preflight -----------------------------------------------------------------
[[ -x "$PYTHON" ]] || { echo "ERROR: $PYTHON not executable"; exit 1; }
"$PYTHON" -c 'import sys; raise SystemExit(0 if sys.version_info[:2]==(3,10) else 1)' \
    || { echo "ERROR: need Python 3.10 (got $($PYTHON --version 2>&1))"; exit 1; }
"$PYTHON" -m venv --help >/dev/null 2>&1 \
    || { echo "ERROR: python3-venv missing --  sudo apt install python3-venv"; exit 1; }
[[ -f "$VINT_TRAIN_DIR/setup.py" ]] \
    || { echo "ERROR: $VINT_TRAIN_DIR/setup.py not found."; \
         echo "       git -C \"$ASYNCVLA_DIR\" submodule update --init --recursive"; exit 1; }

if [[ "$VENV_DIR" -ef "$REF_VENV" ]] 2>/dev/null; then
    echo "ERROR: VENV_DIR resolves to the reference venv. Pick a different path."; exit 1
fi
if [[ -e "$VENV_DIR" ]]; then
    if [[ "$FORCE" == "1" ]]; then
        echo "[!] removing existing $VENV_DIR  (--force)"; rm -rf "$VENV_DIR"
    else
        echo "ERROR: $VENV_DIR already exists.  Re-run with --force to replace it."; exit 1
    fi
fi

# --- 1. clean venv -----------------------------------------------------------
echo "[1/5] creating clean venv (no --system-site-packages) ..."
"$PYTHON" -m venv "$VENV_DIR"
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip "setuptools<80" wheel
grep -q '^include-system-site-packages = false' "$VENV_DIR/pyvenv.cfg" \
    || { echo "ERROR: venv unexpectedly has system site-packages"; exit 1; }

# --- 2. torch / torchvision from the Jetson index ---------------------------
echo "[2/5] installing torch 2.8.0 / torchvision 0.23.0 from $JETSON_INDEX ..."
python -m pip install --no-cache-dir \
    torch==2.8.0 torchvision==0.23.0 \
    --index-url "$JETSON_INDEX"
python - <<'PY'
import torch
assert torch.cuda.is_available(), "torch built but CUDA is NOT available"
x = torch.randn(256, 256, device="cuda")
print(f"      torch {torch.__version__}  CUDA {torch.version.cuda}  "
      f"{torch.cuda.get_device_name(0)}  matmul={float((x @ x).mean()):.4f}")
PY

# --- 3. pinned inference deps ---------------------------------------------------
echo "[3/5] installing pinned inference deps ..."
REQ="$(mktemp)"
cat > "$REQ" <<'REQS'
accelerate==1.13.0
annotated-doc==0.0.4
anyio==4.13.0
certifi==2026.5.20
charset-normalizer==3.4.7
click==8.4.1
draccus==0.11.5
eclipse-zenoh==1.9.0
efficientnet-pytorch==0.7.1
einops==0.8.2
exceptiongroup==1.3.1
filelock==3.29.1
fsspec==2026.4.0
h11==0.16.0
hf-xet==1.5.0
httpcore==1.0.9
httpx==0.28.1
huggingface-hub==0.29.1
idna==3.18
inquirerpy==0.3.4
Jinja2==3.1.6
markdown-it-py==4.2.0
MarkupSafe==3.0.3
mdurl==0.1.2
mergedeep==1.3.4
mpmath==1.3.0
mypy_extensions==1.1.0
networkx==3.4.2
numpy==1.26.4
opencv-python-headless==4.11.0.86
packaging==26.2
pfzy==0.3.4
pillow==12.2.0
prompt_toolkit==3.0.52
psutil==7.2.2
Pygments==2.20.0
PyYAML==6.0.3
pyyaml-include==1.4.1
regex==2026.5.9
requests==2.34.2
rich==15.0.0
safetensors==0.7.0
sentencepiece==0.2.1
shellingham==1.5.4
sympy==1.14.0
timm==0.9.10
tokenizers==0.19.1
toml==0.10.2
tqdm==4.67.3
transformers==4.40.1
typer==0.25.1
typing-inspect==0.9.0
typing_extensions==4.15.0
urllib3==2.7.0
wcwidth==0.7.0
REQS
python -m pip install --no-cache-dir -r "$REQ"
rm -f "$REQ"

# --- 4. vint_train (editable, no deps) ----------------------------------------
echo "[4/5] installing vint_train (editable, --no-deps) ..."
python -m pip install --no-deps -e "$VINT_TRAIN_DIR"

# --- 5. verify + consistency check ------------------------------------------
echo "[5/5] verifying ..."
python - <<'PY'
import importlib
mods = ["torch", "torchvision", "numpy", "cv2", "transformers", "tokenizers",
        "timm", "accelerate", "safetensors", "sentencepiece", "einops",
        "efficientnet_pytorch", "draccus", "zenoh", "huggingface_hub", "vint_train"]
for m in mods:
    mod = importlib.import_module(m)
    print(f"      {m:22s} {getattr(mod, '__version__', '(no __version__)')}")
import numpy, torch
assert numpy.__version__ == "1.26.4", numpy.__version__
assert torch.cuda.is_available()
# the one thing small_head.py actually pulls from vint_train:
from vint_train.models.vint.self_attention import MultiLayerDecoder_trans  # noqa
print("      vint_train.models.vint.self_attention.MultiLayerDecoder_trans  OK")
print("      numpy pin OK, CUDA OK")
PY

echo
echo "--- pip freeze diff vs reference venv ($REF_VENV) ---"
if [[ -x "$REF_VENV/bin/python" ]]; then
    diff <("$REF_VENV/bin/python" -m pip freeze | sed 's/ @ .*//' | sort -f) \
         <(python -m pip freeze | sed 's/ @ .*//' | sort -f) \
      && echo "IDENTICAL — fresh venv matches the reference package-for-package." \
      || echo "^ '<' = only in reference, '>' = only in fresh venv (editable paths differ, that's expected)."
else
    echo "reference venv not found — skipping diff."
fi

echo
echo "Done.  Activate with:"
echo "  source $VENV_DIR/bin/activate"
echo
echo "NOTE: 'from prismatic.models.small_head import Edge_adapter' will still fail"
echo "with ModuleNotFoundError: dlimp — that is expected and identical to the"
echo "reference venv. sys1.py / the runtime loads Edge_adapter via importlib to"
echo "bypass prismatic/__init__.py (the RLDS+tensorflow+dlimp chain)."
