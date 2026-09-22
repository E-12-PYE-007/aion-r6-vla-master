#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# setup_ag_sys1_venv.sh
#
# Builds the Python venv that ag_vla's sys1 edge adapter runs in, on the Jetson
# (jon10: aarch64, JetPack 6 / L4T r36.4, CUDA 12.6, Python 3.10).
#
# Derived from the device's fresh_venv_test.bash, which reproduced the working
# ~/venvs/asclinic_vla_action_head. Two things changed for the migrated package:
#
#   - No vint_train editable install. MultiLayerDecoder_trans is vendored as
#     ag_vla/vint_self_attention.py, and Edge_adapter as ag_vla/edge_adapter.py,
#     so the rover needs no AsyncVLA checkout and no importlib dance around
#     prismatic/__init__.py (the RLDS + tensorflow + dlimp chain).
#   - No sys2/prismatic deps (transformers, tokenizers, accelerate, ...). sys1
#     runs Edge_adapter only.
#
# Plain venv, NOT --system-site-packages: the system python has no torch to
# inherit, and rclpy/cv_bridge resolve through PYTHONPATH once
# /opt/ros/humble/setup.bash is sourced. That is how the reference venv works.
#
# Usage:
#   bash scripts/setup/setup_ag_sys1_venv.sh [--force]
#
# Overridable via env:
#   VENV_DIR      target venv dir           (default ~/venvs/ag_sys1)
#   REF_VENV      venv to diff against      (default ~/venvs/asclinic_vla_action_head)
#   PYTHON        interpreter to build from  (default /usr/bin/python3)
#   TORCH_VERSION / TORCHVISION_VERSION     (default 2.8.0 / 0.23.0)
#   JETSON_INDEX  wheel index               (default jp6/cu126)
# ------------------------------------------------------------------------------

VENV_DIR="${VENV_DIR:-$HOME/venvs/ag_sys1}"
REF_VENV="${REF_VENV:-$HOME/venvs/asclinic_vla_action_head}"
PYTHON="${PYTHON:-/usr/bin/python3}"
TORCH_VERSION="${TORCH_VERSION:-2.8.0}"
TORCHVISION_VERSION="${TORCHVISION_VERSION:-0.23.0}"
JETSON_INDEX="${JETSON_INDEX:-https://pypi.jetson-ai-lab.io/jp6/cu126}"
REQUIREMENTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/edge-requirements.txt"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

echo "=== setup_ag_sys1_venv ==="
echo "  VENV_DIR     = $VENV_DIR"
echo "  REF_VENV     = $REF_VENV"
echo "  PYTHON       = $PYTHON  ($($PYTHON --version 2>&1))"
echo "  torch        = $TORCH_VERSION / torchvision $TORCHVISION_VERSION"
echo "  index        = $JETSON_INDEX"
echo

# --- preflight ----------------------------------------------------------------
[[ -x "$PYTHON" ]] || { echo "ERROR: $PYTHON not executable"; exit 1; }
"$PYTHON" -c 'import sys; raise SystemExit(0 if sys.version_info[:2]==(3,10) else 1)' \
    || { echo "ERROR: need Python 3.10 (got $($PYTHON --version 2>&1))"; exit 1; }
"$PYTHON" -m venv --help >/dev/null 2>&1 \
    || { echo "ERROR: python3-venv missing --  sudo apt install python3-venv"; exit 1; }
[[ -f "$REQUIREMENTS" ]] || { echo "ERROR: $REQUIREMENTS not found"; exit 1; }
[[ -f /etc/nv_tegra_release ]] \
    && echo "  jetson       = $(head -1 /etc/nv_tegra_release)" \
    || echo "  [!] no /etc/nv_tegra_release -- not a Jetson? the index below expects one"

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

# --- 1. clean venv ------------------------------------------------------------
echo "[1/4] creating clean venv (no --system-site-packages) ..."
"$PYTHON" -m venv "$VENV_DIR"
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip "setuptools<80" wheel
grep -q '^include-system-site-packages = false' "$VENV_DIR/pyvenv.cfg" \
    || { echo "ERROR: venv unexpectedly has system site-packages"; exit 1; }

# --- 2. torch / torchvision from the Jetson index -----------------------------
# First, so that efficientnet_pytorch's torch dependency is already satisfied and
# pip cannot substitute a CPU-only PyPI wheel.
echo "[2/4] installing torch $TORCH_VERSION / torchvision $TORCHVISION_VERSION from $JETSON_INDEX ..."
python -m pip install --no-cache-dir \
    "torch==$TORCH_VERSION" "torchvision==$TORCHVISION_VERSION" \
    --index-url "$JETSON_INDEX"
python - <<'PY'
import torch
assert torch.cuda.is_available(), "torch built but CUDA is NOT available"
x = torch.randn(256, 256, device="cuda")
print(f"      torch {torch.__version__}  CUDA {torch.version.cuda}  "
      f"{torch.cuda.get_device_name(0)}  matmul={float((x @ x).mean()):.4f}")
PY

# --- 3. pinned sys1 deps ------------------------------------------------------
echo "[3/4] installing pinned sys1 deps ..."
python -m pip install --no-cache-dir -r "$REQUIREMENTS"

# --- 4. verify ----------------------------------------------------------------
echo "[4/4] verifying ..."
python - <<'PY'
import importlib, sys
print("      interpreter", sys.executable)
ok = True
for m in ["torch", "torchvision", "numpy", "PIL", "cv2", "efficientnet_pytorch"]:
    try:
        mod = importlib.import_module(m)
        print(f"      {m:22s} {getattr(mod, '__version__', '(no __version__)')}")
    except Exception as exc:
        ok = False
        print(f"      {m:22s} FAIL {type(exc).__name__}: {exc}")

import numpy, torch
assert numpy.__version__ == "1.26.4", numpy.__version__
assert torch.cuda.is_available()
print("      numpy pin OK, CUDA OK")

# ROS deps come from PYTHONPATH, not this venv -- they only resolve in a shell
# that has sourced /opt/ros/humble/setup.bash, which this script does not assume.
for m in ["rclpy", "cv_bridge"]:
    try:
        importlib.import_module(m)
        print(f"      {m:22s} visible via PYTHONPATH")
    except Exception:
        print(f"      {m:22s} not visible here -- source /opt/ros/humble/setup.bash, then re-check")

sys.exit(0 if ok else 1)
PY

echo
echo "--- pip freeze diff vs reference venv ($REF_VENV) ---"
if [[ -x "$REF_VENV/bin/python" ]]; then
    diff <("$REF_VENV/bin/python" -m pip freeze | sed 's/ @ .*//' | sort -f) \
         <(python -m pip freeze | sed 's/ @ .*//' | sort -f) \
      && echo "IDENTICAL to the reference venv." \
      || echo "^ '<' = only in reference (expected: sys2/prismatic deps, vint_train), '>' = only here."
else
    echo "reference venv not found -- skipping diff."
fi

echo
echo "Done."
echo "  sys1_hw's shebang must read: #!$VENV_DIR/bin/python3"
echo "  Check with: head -1 <ws>/src/ag_vla/scripts/sys1_hw"
