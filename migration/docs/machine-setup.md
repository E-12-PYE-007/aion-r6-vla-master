# AION R6 — machine migration guide

How to bring a fresh machine to the same state as the original rover compute box
(`vlacap-desktop`, Jetson Orin / JetPack 6 / L4T 36.4).

The work splits in two:

| | Where |
|---|---|
| **Deterministic** — apt/pip/rosdep, udev rules, groups, env block | `migration/scripts/setup-machine.sh` (idempotent) |
| **Judgement / machine-specific** — network, Isaac ROS, which branch to build, verification | this document + `migration/files/` |

`migration/` layout:

```
migration/
  scripts/setup-machine.sh      run once, re-runnable
  docs/machine-setup.md         this file
  files/
    udev/                       *.rules -> /etc/udev/rules.d/  (script installs)
    network/                    NetworkManager profiles, REFERENCE ONLY
    bashrc-ros-block.sh         appended to ~/.bashrc (script does this)
    module_benchmarks/          perf harness + baseline numbers from the old box
```

---

## What a stock ROS 2 install + rosdep already handles

Don't re-do these — they are covered by Step 0 and by `rosdep install`:

- **ROS 2 Humble** and all build tooling (`colcon`, `rosdep`, `vcstool`, `ros-dev-tools`) — from `scripts/setup/install_ros2_humble.sh`.
- **Every dependency declared in a `package.xml`**, resolved per branch by
  `rosdep install --from-paths src --ignore-src -r -y`. That includes: `rclpy`/`rclcpp`
  and all message packages, `mavros` + `mavros_extras`, `robot_localization` (on the
  EKF branch), `cv_bridge`, `image_transport`, `camera_info_manager`,
  `diagnostic_updater`, `backward_ros`, and the Orbbec SDK system libs
  (`libgflags-dev`, `libgoogle-glog-dev`, `nlohmann-json-dev`, `libssl-dev`, `opengl`),
  plus `python3-matplotlib` / `python3-numpy` / `python3-yaml` / `python3-pytest`.
- **Submodules** (`px4_msgs`, `OrbbecSDK_ROS2`, and `px4-ros2-interface-lib` where a
  branch uses it) — from `git clone --recursive` / `git submodule update --init --recursive`.

Everything below is what that leaves out.

---

## Step 0 — base platform (prerequisites)

1. **OS**: Ubuntu 22.04 arm64, JetPack 6 / L4T 36.x (the old box: `nvidia-l4t-core 36.4.7`).
2. **ROS 2 Humble**:
   ```bash
   scripts/setup/install_ros2_humble.sh
   ```
3. **Clone the superproject with submodules**:
   ```bash
   git clone --recursive <superproject-url> ~/aion-r6-vla-master
   ```
   If already cloned without `--recursive`:
   ```bash
   git -C ~/aion-r6-vla-master submodule update --init --recursive
   ```

## Step 1 — run the deterministic setup

```bash
cd ~/aion-r6-vla-master
migration/scripts/setup-machine.sh --branch <branch-you-will-develop-on>
```

`--branch` is optional; without it the script runs `rosdep` against whatever is
currently checked out in `aion-r6-ROS`. Run it again after switching branches so
rosdep picks up that branch's packages.

What it does, section by section:

| Section | Action | Source file |
|---|---|---|
| apt extras | installs `ros-humble-robot-localization` (declared only on the EKF branch, so rosdep misses it elsewhere) | — |
| rosdep | `rosdep init`/`update`/`install` over `aion-r6-ROS/src` | the workspace's `package.xml` files |
| pip | `pip install --user -r aion-r6-ROS/src/control/requirements.txt` (→ `basicmicro`, the Roboclaw driver — not rosdep-resolvable) and `pymavlink` + `MAVProxy` (Pixhawk debug tooling) | `src/control/requirements.txt` |
| MAVROS datasets | runs `/opt/ros/humble/lib/mavros/install_geographiclib_datasets.sh` (populates `/usr/share/GeographicLib/`) — rosdep installs the mavros *packages* but not this | — |
| udev | copies `files/udev/*.rules` to `/etc/udev/rules.d/`, reloads | `migration/files/udev/` |
| groups | adds you to `dialout i2c gpio video render plugdev docker` | — |
| bashrc | appends the ROS env block if `ROS_DOMAIN_ID` isn't already set | `migration/files/bashrc-ros-block.sh` |

It performs nothing that needs a decision — those are listed as `[ ]` items when it finishes.

## Step 2 — network (manual)

The NetworkManager profiles are **not** installed by the script: they hold Wi-Fi PSKs,
must be `root:root` / `0600`, and the wired ones bind the Tegra NIC name (`enP8p1s0`).

**`migration/files/network/`** records all six profiles that were on the old box —
`README.md` has the full settings table, plus a `*.nmconnection.example` per profile
(PSK/uuid stripped). It's a record of what the rover expected, not a claim that every
profile is needed on the new machine — decide per profile.

For each one you want: recreate it with `nmcli`/GUI from the values in the README, or
copy the real `/etc/NetworkManager/system-connections/<name>.nmconnection` off the old
box, fix ownership + perms, then `sudo nmcli connection reload`.

## Step 3 — Isaac ROS (separate, out of scope here)

VSLAM + nvblox run in NVIDIA's Isaac ROS container under
`$ISAAC_ROS_WS` (`~/workspaces/isaac_ros-dev/`), consuming the Orbbec IR/depth/IMU
topics published by `aion-r6-ROS` `localisation/launch/front_camera.launch.py`.
Set up per NVIDIA's Isaac ROS docs on matching JetPack 6 / L4T 36.x. Handled outside
this guide. The `.bashrc` block already exports `ISAAC_ROS_WS` so the rest of the
stack is ready for it.

## Step 4 — build

```bash
cd ~/aion-r6-vla-master/aion-r6-ROS
colcon build --symlink-install
source install/setup.bash
```

Note: packages are split across feature branches — no single branch is the whole
stack. Build the branch you're working on; run `setup-machine.sh --branch <name>`
again first if you switched, so its `package.xml` deps are satisfied.

---

## `migration/files/` reference

| Path | What it is | Where it goes / how it's used |
|---|---|---|
| `udev/99-cube-black.rules` | `SUBSYSTEM=="tty", idVendor 26ac, idProduct 0011 → SYMLINK pixhawk` — creates `/dev/pixhawk` for the Cube FCU (mavros uses `/dev/pixhawk:57600`) | `setup-machine.sh` installs to `/etc/udev/rules.d/` |
| `udev/99-obsensor-libusb.rules` | Orbbec camera USB access + `/dev/CAM-*`, `/dev/Gemini_*` symlinks (`MODE=0666`, group `video`). Also regenerable from `aion-r6-ROS/src/OrbbecSDK_ROS2/orbbec_camera/scripts/install_udev_rules.sh` — this is a pinned copy | `setup-machine.sh` installs to `/etc/udev/rules.d/` |
| `network/README.md` | All six NetworkManager profiles from the old box — settings table + copy/recreate instructions | read it for Step 2 |
| `network/*.nmconnection.example` | One reference reconstruction per profile (`campus-eth`, `direct-link`, `Hotspot`, `rover-hotspot`, `UniEquip`, `TP-Link_8BA9`), PSK/uuid stripped | recreate or adapt per profile; do **not** copy verbatim |
| `bashrc-ros-block.sh` | `ROS_DOMAIN_ID=42`, `source /opt/ros/humble/setup.bash`, `ISAAC_ROS_WS` | `setup-machine.sh` appends to `~/.bashrc` if absent |
| `module_benchmarks/tegra_bench.sh` | Benchmark harness — runs a launch config while logging `tegrastats` | run manually on the new box to compare against the baselines |
| `module_benchmarks/parse_tegrastats.py` | Turns a `tegrastats` log into `results.csv` (CPU/GPU/EMC/power) | called by `tegra_bench.sh` |
| `module_benchmarks/{cam_only,cam_vslam,nvblox1}/` | Baseline runs from the **old** box (logs + `results.csv`) — the numbers to reproduce | reference; keep for comparison |

---

## Verification checklist

After Steps 1–4, with the Cube, Orbbec camera and Roboclaw connected:

```bash
# env
echo $ROS_DOMAIN_ID                 # -> 42
ros2 doctor --report | head         # RMW = rmw_fastrtps_cpp, domain 42

# devices
ls -l /dev/pixhawk                  # symlink present (Cube plugged in)
ls /dev/serial/by-id/ | grep -i roboclaw   # usb-Basicmicro_Inc._USB_Roboclaw_2x45A-if00
ls /dev/ | grep -Ei 'CAM-|Gemini'  # Orbbec symlink present

# groups (after re-login)
id -nG | tr ' ' '\n' | grep -E 'dialout|video|docker'

# stack — from aion-r6-ROS with install/ sourced
ros2 launch localisation front_camera.launch.py     # camera comes up, topics publish
ros2 run control roboclaw_for_motors                # connects to the Roboclaw
ros2 launch bringup mavros-test.py                  # mavros_fcu connects to /dev/pixhawk

# pip tooling
python3 -c 'import basicmicro; print("basicmicro ok")'
~/.local/bin/mavproxy.py --version
```

## Notes / gotchas

- **`ROS_DOMAIN_ID=42`** must match on every machine on the rover network (the Jetson,
  any dev laptop, the Isaac ROS container). Mismatch = nodes silently don't see each other.
- **NIC names**: `direct-link` / `campus-eth` bind `enP8p1s0` (Tegra naming on this
  carrier board). If the new board enumerates differently, edit `interface-name` in
  those profiles or drop the field.
- **Orbbec is built from the workspace submodule**, not apt. Do **not**
  `apt install ros-humble-orbbec-camera*` — the workspace `src/OrbbecSDK_ROS2` (v2.9.3,
  with in-tree prebuilt `libOrbbecSDK.so` for arm64) is the source of truth and would
  be shadowed anyway.
- **Roboclaw** needs no udev rule — the code targets
  `/dev/serial/by-id/usb-Basicmicro_Inc._USB_Roboclaw_2x45A-if00`, which the kernel
  creates automatically from the USB descriptors. Access just needs `dialout`.
- **`basicmicro`** is intentionally kept in `src/control/requirements.txt` only, not
  `package.xml` (no rosdep rule exists for it). The script installs it from there.
- **XRCE-DDS Agent** and **PX4 SITL / Gazebo** are documented in `docs/ros2-px4-setup.md`
  but are **not** part of the rover runtime and are not set up by this migration.
