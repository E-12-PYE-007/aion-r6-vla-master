# Pixhawk Sensor Interface

This doc covers how to bring up the MAVROS bridge to the Pixhawk and what each resulting IMU/GPS/magnetometer topic represents, so they can be wired into a ROS 2 Kalman filter (e.g. in the `localisation` package) with the right frames, units, and covariance assumptions.

This is the MAVROS-based sensor path (serial link to the Pixhawk), separate from the uXRCE-DDS `/fmu/...` topics used for mode control — see [ros2-px4-setup.md](ros2-px4-setup.md) and [edge-launch-requirements.md](edge-launch-requirements.md) for that side.

---
## Launch

```bash
source /opt/ros/humble/setup.bash
source install/setup.bash   # from aion-r6-ROS workspace root
ros2 launch bringup mavros-test.py
```

This starts `mavros_node` (named `mavros_fcu`) against `/dev/pixhawk` at 57600 baud, using:
- `src/bringup/config/mavros_pluginlists.yaml` — which MAVROS plugins are active (`sys_status`, `sys_time`, `imu`, `global_position`, `command`)
- `src/bringup/config/mavros_config.yaml` — per-plugin settings (frame IDs, stdevs, tf behavior)

The launch file also issues a `SET_MESSAGE_INTERVAL` command for MAVLink message id `105` (`HIGHRES_IMU`) at 10000µs (100 Hz), via a raw `ros2 service call` rather than MAVROS's `set_message_interval` service — that service has a known naming bug in this MAVROS version, so the launch file bypasses it.

**Note:** MAVROS holds `/dev/pixhawk` exclusively. Don't try to open it with a second tool (e.g. `pymavlink`/`mavproxy.py`) while `mavros_node` is running — both readers will get corrupted MAVLink streams. Stop MAVROS first if you need direct serial access for debugging.

---
## Topics

All topics below are published under the `/mavros_fcu/mavros_fcu/` namespace (node name `mavros_fcu` nested under itself due to how MAVROS composes its namespace with the node name given in the launch file).

There is no separate magnetometer plugin — the `mag` topic comes from the same `imu` plugin as the IMU topics, since PX4 carries mag data as extra fields on the same `HIGHRES_IMU` MAVLink message.

### IMU

| Topic | Type | Rate | Notes |
|---|---|---|---|
| `data_raw` | `sensor_msgs/Imu` | ~100 Hz | Raw, **unfused** accel + gyro. **Use this one for your own Kalman filter.** |
| `data` | `sensor_msgs/Imu` | ~100 Hz | Fused — includes PX4's own onboard attitude estimate. Feeding this into a second (Jetson-side) EKF double-counts PX4's fusion against your own. |

- `frame_id`: `base_link`
- Linear acceleration / angular velocity covariance is **not** measured live — it's hardcoded in `mavros_config.yaml` via `linear_acceleration_stdev` / `angular_velocity_stdev` (currently `0.0003` for both). These are estimates, not datasheet or empirically-derived values — see [Covariance](#covariance) below.

### GPS

| Topic | Type | Rate | Notes |
|---|---|---|---|
| `raw/fix` | `sensor_msgs/NavSatFix` | GPS update rate | Raw fix. **Use this one**, for the same double-fusion reason as IMU `data_raw` above. |
| `global` | `sensor_msgs/NavSatFix` | GPS update rate | PX4's fused global position estimate. |

- `frame_id`: `map`, `child_frame_id`: `base_link` (per the `global_position` plugin config)
- `tf.send` is disabled in `mavros_config.yaml` — the Jetson-side EKF (in `localisation`) owns the `map -> base_link` transform, not MAVROS. Don't re-enable this without also removing whatever publishes that tf downstream, or you'll get two publishers fighting over the same transform.
- `use_relative_alt: true` — altitude is relative to home/takeoff point, not absolute MSL.

### Magnetometer

| Topic | Type | Rate | Notes |
|---|---|---|---|
| `mag` | `sensor_msgs/MagneticField` | ~14-15 Hz | See below. |

- `frame_id`: `base_link`
- Units: Tesla (per `sensor_msgs/MagneticField` convention — PX4/MAVLink also reports in Tesla-equivalent, no conversion needed).
- **Rate is capped by the sensor, not MAVROS config.** `HIGHRES_IMU` streams at 100 Hz (accel/gyro), but the message carries a `fields_updated` bitmask, and the mag fields only refresh when the compass chip itself has a new sample. Typical I2C magnetometers used on GPS+compass modules (and similar internal parts) have a ~15 Hz output data rate regardless of how fast the containing message is streamed. This is normal and doesn't need "fixing" — 15 Hz is generally sufficient for yaw/heading correction in an EKF, since it's a slow drift-correction reference, not something requiring high bandwidth like gyro integration.
- **Two physical sensors exist on this vehicle**: one internal (built into the Pixhawk's IMU package) and one external (on the GPS/compass module, mounted away from ESC/power interference). PX4's sensor voter automatically selects which one feeds this topic based on priority (`CAL_MAG0_PRIO` / `CAL_MAG1_PRIO`) and health — this is not configurable from ROS/MAVROS, and there's no ROS-side indication of which physical instance is currently active. To check instance mapping or priority directly, use `mavproxy.py --master=/dev/pixhawk --baudrate=57600` (with MAVROS stopped first — see the port note above) and:
  ```
  param show CAL_MAG0_ROT   # -1 = internal; 0+ = external, value is mounting rotation
  param show CAL_MAG1_ROT
  param show CAL_MAG0_PRIO  # -1 = disabled; higher = preferred
  param show CAL_MAG1_PRIO
  ```

---
## Covariance

Before wiring any of these into a Kalman filter, check what covariance each topic is actually publishing — don't assume it's meaningful just because the field is populated:

- **IMU**: covariance is filled in, but it's a hand-set estimate (`mavros_config.yaml`), not measured. Reasonable to use as a starting point, but worth validating/tuning against real static-sensor variance if the filter's behavior looks off.
- **Magnetometer**: `magnetic_field_covariance` comes back as `[-1, 0, 0, 0, 0, 0, 0, 0, 0]` — this is the standard "covariance unknown" convention (element `[0]` = `-1`), **not** an actual measurement. PX4 doesn't transmit mag variance over MAVLink at all, so MAVROS has nothing to put there. A Kalman filter that expects a real covariance matrix (e.g. `robot_localization`) will need this replaced before the mag input is trustworthy.

**Testing is required to establish a real magnetometer covariance if one can't be sourced elsewhere** (e.g. from the specific compass chip's datasheet noise spec). The straightforward approach: with the vehicle stationary and away from magnetic interference, log `mag` for a reasonable window and compute the sample variance per axis; use `diag(var_x, var_y, var_z)` as the covariance. This needs to be patched in downstream (e.g. a small republishing node, or directly in whatever config the Kalman filter uses to consume this topic) since MAVROS itself has no parameter for magnetic field covariance the way it does for IMU stdevs.

Also confirm PX4's own compass calibration (hard/soft-iron) has actually been performed on the vehicle — this doc assumes it has. Raw `mag` values are calibrated by PX4 before being sent, so an un-calibrated compass will bias every downstream fusion result regardless of covariance tuning.

---
## Quick verification

```bash
ros2 topic list | grep mavros_fcu          # confirm topics are up
ros2 topic hz /mavros_fcu/mavros_fcu/data_raw   # ~100 Hz expected
ros2 topic hz /mavros_fcu/mavros_fcu/mag        # ~14-15 Hz expected
ros2 topic echo /mavros_fcu/mavros_fcu/mag      # sanity-check values + covariance field
```
