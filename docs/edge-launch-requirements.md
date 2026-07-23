# Edge Launch Requirements
This doc is intended as a scratch pad to list the basic steps required in launching the complete end to end AION R6 system, to aid in writing a launch file later.

This doc assumes all modules and dependencies are already installed.

Tasks should be **high level** and point to docs/ for explanation or scripts/ where required.

---
## Tasks
- [ ] Launch PX4 SITL **(Simulation only)**
- [ ] Launch XRCE-DDS Agent
- [ ] Launch XRCE-DDS Client
- [ ] Launch ROS 2 mode node (`hw_interface`)
- [ ] Activate the flight mode

---
### Launch PX4 SITL **(Simulation only)**

Not required on the edge device — this stands in for the real Pixhawk when developing/testing off-vehicle. Requires Gazebo **Harmonic**

```
cd ~/PX4-Autopilot
make px4_sitl gz_r1_rover
```

This drops you into the `pxh>` console in the same terminal once boot completes — that's PX4's interactive shell, used below to arm and to check mode registration. PX4 auto-starts its XRCE-DDS client at boot (see below), so no extra step is needed to connect it to the agent.

---
### Launch XRCE-DDS Agent

Runs on the edge device (Orin) for Pixahawk <-> ROS2 communication.

For simulator, run the below command from `Micro-XRCE-DDS-Agent/build`
```
MicroXRCEAgent udp4 -p 8888
```
Then:
```

```

For deployment, run the below command from `Micro-XRCE-DDS-Agent/build`
```
    ./MicroXRCEAgent serial [OPTIONS]
```
*See [here](https://micro-xrce-dds.docs.eprosima.com/en/latest/agent.html#agent-cli) for details*

---
### Launch XRCE-DDS Client
*Information available [here](https://docs.px4.io/v1.17/en/middleware/uxrce_dds)*

PX4 starts this itself on boot (`uxrce_dds_client start -t udp -p 8888`, from `rcS`) — on **both** SITL and real hardware, so no manual step is needed here as long as the Agent (above) is already running on the matching port.

---
### Launch ROS 2 mode node (`hw_interface`)

```
source /opt/ros/humble/setup.bash
source install/setup.bash   # from aion-r6-ROS workspace root
ros2 run hw_interface px4_mode_node
```

With debug output enabled, confirms registration with PX4:
```
[DEBUG] [rover_position_mode]: Registering 'Rover Position Mode' (arming check: 1, mode: 1, mode executor: 0)
[DEBUG] [rover_position_mode]: Got RegisterExtComponentReply
```
Registering only makes PX4 aware the mode exists — it does not activate it (see next step).

---
### Activate the flight mode

Registration doesn't select the mode — something must explicitly request the switch, same as picking it from a GCS dropdown.

**1. Find the mode's assigned ID** (`nav_state`), via the `pxh>` console:
```
commander status
```
Look for a line like:
```
INFO  [commander] External Mode 1: nav_state: 23, name: Rover Position Mode
```

**2. Arm** (`pxh>` console):
```
commander arm
```

**3. Send the mode switch**, from a ROS 2 terminal — replace `23.0` with the number from step 1:
```
ros2 topic pub --once /fmu/in/vehicle_command px4_msgs/msg/VehicleCommand "{command: 100001, param1: 23.0, target_system: 1, target_component: 1}"
```
`command: 100001` is `VEHICLE_CMD_SET_NAV_STATE` — "switch mode to the nav_state in param1". This works identically on real hardware; a GCS (e.g. QGroundControl) is the more common way to do this but is not required — PX4's own `px4_ros2_cpp` integration tests use this exact command to switch modes without any GCS involved.

Confirm with `commander status` again (`navigation mode:` should now show the custom mode) or watch for `Mode 'Rover Position Mode' activated` in the node's log.