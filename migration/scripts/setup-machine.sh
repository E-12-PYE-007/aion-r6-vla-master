#!/usr/bin/env bash
#
# setup-machine.sh — deterministic half of the AION R6 machine migration.
#
# Reproduces everything that a plain "install ROS 2 Humble + rosdep" does NOT
# give you. Idempotent: safe to re-run. Anything that needs a human decision is
# NOT done here — it is collected and printed at the end, and covered in
# migration/docs/machine-setup.md.
#
# Usage:  migration/scripts/setup-machine.sh [--branch <name>]
#   --branch   git branch to check out in aion-r6-ROS before running rosdep
#              (default: leave the workspace on whatever is currently checked out)
#
# Prereqs (see migration/docs/machine-setup.md, "Step 0"):
#   - Ubuntu 22.04 arm64, JetPack 6 / L4T 36.x
#   - ROS 2 Humble installed (scripts/setup/install_ros2_humble.sh)
#   - superproject cloned with --recursive
set -euo pipefail

# --- locations ---------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$MIGRATION_DIR/.." && pwd)"
ROS_WS="$REPO_ROOT/aion-r6-ROS"
FILES_DIR="$MIGRATION_DIR/files"

BRANCH=""
[[ "${1:-}" == "--branch" ]] && { BRANCH="${2:-}"; shift 2 || true; }

# --- logging ---------------------------------------------------------------
c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_step=$'\e[36m'; c_off=$'\e[0m'
step()  { echo; echo "${c_step}==> $*${c_off}"; }
ok()    { echo "${c_ok}  ok:${c_off} $*"; }
warn()  { echo "${c_warn}  warn:${c_off} $*"; }
die()   { echo "${c_err}  error:${c_off} $*" >&2; exit 1; }
MANUAL=()
manual() { MANUAL+=("$*"); }

# --- sanity --------------------------------------------------------------
step "Sanity checks"
[[ $EUID -ne 0 ]] || die "run as your normal user, not root (the script calls sudo where needed)"
. /etc/os-release
[[ "${VERSION_ID:-}" == "22.04" ]] || warn "expected Ubuntu 22.04, found ${VERSION_ID:-unknown} — continuing anyway"
[[ "$(dpkg --print-architecture)" == "arm64" ]] || warn "expected arm64, found $(dpkg --print-architecture)"
[[ -d "$ROS_WS/src" ]] || die "ROS workspace not found at $ROS_WS — clone the superproject with --recursive"
if [[ ! -f /opt/ros/humble/setup.bash ]]; then
  die "ROS 2 Humble not installed. Run: $REPO_ROOT/scripts/setup/install_ros2_humble.sh"
fi
ok "Ubuntu ${VERSION_ID:-?} $(dpkg --print-architecture), ROS 2 Humble present, workspace at $ROS_WS"

# --- optional branch checkout -----------------------------------------------
if [[ -n "$BRANCH" ]]; then
  step "Checking out '$BRANCH' in aion-r6-ROS"
  git -C "$ROS_WS" fetch --quiet origin
  git -C "$ROS_WS" checkout "$BRANCH"
  git -C "$ROS_WS" submodule update --init --recursive
  ok "aion-r6-ROS on $(git -C "$ROS_WS" branch --show-current)"
else
  ok "leaving aion-r6-ROS on $(git -C "$ROS_WS" branch --show-current 2>/dev/null || echo '(detached)')"
fi

# --- apt: things rosdep will not pull -------------------------------------
step "apt packages not declared in any package.xml"
# robot_localization: declared only on the robot-localization-ekf branch, so
# rosdep misses it on the others. Cheap to always have.
APT_EXTRA=(ros-humble-robot-localization)
missing=()
for p in "${APT_EXTRA[@]}"; do dpkg -s "$p" &>/dev/null || missing+=("$p"); done
if ((${#missing[@]})); then
  sudo apt-get update -qq
  sudo apt-get install -y "${missing[@]}"
  ok "installed: ${missing[*]}"
else
  ok "already present: ${APT_EXTRA[*]}"
fi

# --- rosdep: everything declared in package.xml --------------------------
step "rosdep — declared workspace dependencies"
if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
  sudo rosdep init
fi
rosdep update
# ROS setup scripts are not always `set -u` clean
set +u
# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash
set -u
rosdep install --from-paths "$ROS_WS/src" --ignore-src -r -y
ok "rosdep satisfied for $(git -C "$ROS_WS" branch --show-current 2>/dev/null || echo 'current tree')"

# --- pip (user site): not resolvable by rosdep ---------------------------
step "pip user packages"
REQ="$ROS_WS/src/control/requirements.txt"
if [[ -f "$REQ" ]]; then
  python3 -m pip install --user -r "$REQ"
  ok "installed from $REQ ($(tr '\n' ' ' <"$REQ"))"
else
  warn "$REQ not present on this branch — skipping (basicmicro only needed when the 'control' package is built)"
fi
# MAVLink debug tooling (docs/pixhawk-sensor-interface.md). Not a stack dep.
python3 -m pip install --user pymavlink MAVProxy
ok "installed: pymavlink MAVProxy  (-> ~/.local/bin/mavproxy.py, mavlogdump.py, ...)"

# --- MAVROS GeographicLib datasets -------------------------------------
step "MAVROS GeographicLib datasets"
GEO_SCRIPT=/opt/ros/humble/lib/mavros/install_geographiclib_datasets.sh
if [[ -f /usr/share/GeographicLib/geoids/egm96-5.pgm ]]; then
  ok "datasets already installed under /usr/share/GeographicLib"
elif [[ -f "$GEO_SCRIPT" ]]; then
  sudo "$GEO_SCRIPT"
  ok "ran $GEO_SCRIPT"
else
  warn "$GEO_SCRIPT missing — is ros-humble-mavros installed? (rosdep should have done it)"
  manual "Install ros-humble-mavros ros-humble-mavros-extras, then run $GEO_SCRIPT"
fi

# --- udev rules ---------------------------------------------------------
step "udev rules"
udev_changed=0
for rule in "$FILES_DIR"/udev/*.rules; do
  dest="/etc/udev/rules.d/$(basename "$rule")"
  if [[ -f "$dest" ]] && cmp -s "$rule" "$dest"; then
    ok "$(basename "$rule") already in place"
  else
    sudo install -m 0644 -o root -g root "$rule" "$dest"
    ok "installed $(basename "$rule")"
    udev_changed=1
  fi
done
if ((udev_changed)); then
  sudo udevadm control --reload-rules
  sudo udevadm trigger
  ok "reloaded udev  (/dev/pixhawk on Cube connect; /dev/CAM-*, /dev/Gemini_* for Orbbec)"
fi
ok "Roboclaw needs no rule — code uses /dev/serial/by-id/usb-Basicmicro_Inc._USB_Roboclaw_2x45A-if00 (kernel-generated)"

# --- user groups ------------------------------------------------------
step "user groups"
WANT_GROUPS=(dialout i2c gpio video render plugdev docker)
add=()
for g in "${WANT_GROUPS[@]}"; do
  getent group "$g" >/dev/null || { warn "group '$g' does not exist on this machine — skipping"; continue; }
  id -nG "$USER" | tr ' ' '\n' | grep -qx "$g" || add+=("$g")
done
if ((${#add[@]})); then
  sudo usermod -aG "$(IFS=,; echo "${add[*]}")" "$USER"
  ok "added $USER to: ${add[*]}"
  manual "Log out and back in (or reboot) for the new group membership to take effect"
else
  ok "already in: ${WANT_GROUPS[*]}"
fi

# --- ~/.bashrc ROS block --------------------------------------------
step "~/.bashrc ROS environment"
if grep -q 'ROS_DOMAIN_ID=42' "$HOME/.bashrc"; then
  ok "ROS block already present in ~/.bashrc"
else
  { echo; cat "$FILES_DIR/bashrc-ros-block.sh"; } >> "$HOME/.bashrc"
  ok "appended ROS block to ~/.bashrc (ROS_DOMAIN_ID=42, source humble, ISAAC_ROS_WS)"
  manual "Open a new shell (or 'source ~/.bashrc') to pick up ROS_DOMAIN_ID"
fi

# --- manual follow-up -------------------------------------------------
step "Deterministic setup complete — manual follow-up"
manual "Network: recreate the NetworkManager profiles (rover-hotspot AP jetsontest/10.42.0.1, direct-link 192.168.50.1) — see migration/files/network/README.md"
manual "Isaac ROS: set up the container workspace at \$ISAAC_ROS_WS separately (VSLAM + nvblox)"
manual "Build the workspace:  cd $ROS_WS && colcon build --symlink-install"
manual "Verify: migration/docs/machine-setup.md -> 'Verification checklist'"
echo
for m in "${MANUAL[@]}"; do echo "  ${c_warn}[ ]${c_off} $m"; done
echo
ok "done"
