# Pixahawk Setup \& Configuration

This guide covers PX4 installation, as well as setup for XRCE-DDS Agent to handlepassing of messages between MAVROS (Pixahawk) and ROS2 (Edge).

**Reference repo:** [ARK-Electronics/ROS2_PX4_Offboard_Example](https://github.com/ARK-Electronics/ROS2_PX4_Offboard_Example) is the example/reference for the ROS2 <-> PX4 integration.

---
## PX4 Install (Dev Environment Only)
**Note:** Not required for edge device - only for running PX4 simulatofor development 

### 1. Clone PX4-Autopilot

```bash
git clone https://github.com/PX4/PX4-Autopilot.git --recursive -b release/1.17
```

Skip this if `~/PX4-Autopilot` already exists.

---

### 2. Pin setuptools and packaging before installing dependencies

```bash
pip3 install --user "setuptools==65.5.0" "packaging<24"
```

Do this **before** running PX4's dependency installer, not after. `empy==3.3.4` (a PX4 build dependency) uses a legacy `setup.py egg_info` build that breaks on `setuptools` newer than ~65.5.0, and separately `colcon-core` requires `setuptools<80,>=30.3.0`. `65.5.0` is the version that satisfies both.

> **Keep this pinned going forward.** Any later `pip install --user -U ...setuptools` (unpinned) — including dependency commands from other setup guides like the ROS2_PX4_Offboard_Example README — will silently upgrade `setuptools` again and reintroduce this exact conflict. If you ever need to run one of those commands, add `setuptools==65.5.0` explicitly to the package list rather than leaving it unpinned.

---

### 3. Run PX4's dependency installer

```bash
bash ./PX4-Autopilot/Tools/setup/ubuntu.sh
```

If you skipped step 2, this will fail while installing `empy` with:
```
TypeError: canonicalize_version() got an unexpected keyword argument 'strip_trailing_zero'
```
If that happens, run step 2 and re-run this command.

---

### 4. Build SITL to verify

```bash
cd PX4-Autopilot
make px4_sitl
```

A successful build completes all 1029 steps. You may see a `ModuleNotFoundError: No module named 'symforce'` early in the log — that's non-fatal and doesn't stop the build.

---

### 5. Install ROS2-side Python dependencies

```bash
pip install --user -U empy==3.3.4 pyros-genmsg setuptools==65.5.0
```

Keep `setuptools` pinned here too, per the note in step 2.

---
## XRCE-DDS Agent Setup
ROS2 is able to communicate with PX4 via XRCE-DDS. This requires an agent to run on the companion computer (Orin) to receive messages over serial from the client (PX4).

To build the agent:

~~~
cd Micro-XRCE-DDS-Agent
mkdir build
cd build
cmake ..
make
sudo make install
sudo ldconfig /usr/local/lib/
~~~

