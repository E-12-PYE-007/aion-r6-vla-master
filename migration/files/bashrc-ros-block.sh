# --- AION R6 ROS 2 environment -------------------------------------------------
# Appended to ~/.bashrc by migration/scripts/setup-machine.sh (idempotent).
# ROS_DOMAIN_ID MUST match every other machine on the rover network or the
# nodes will not discover each other.

export ROS_DOMAIN_ID=42
source /opt/ros/humble/setup.bash

# Isaac ROS dev workspace (VSLAM + nvblox run in a container under here).
# Set even if the container is not installed yet; harmless when absent.
export ISAAC_ROS_WS=${HOME}/workspaces/isaac_ros-dev/
# ----------------------------------------------------------------------------
