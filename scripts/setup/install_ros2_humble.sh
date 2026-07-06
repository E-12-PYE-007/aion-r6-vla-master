#!/usr/bin/env bash
# ROS 2 Humble install (Ubuntu 22.04 "jammy") via Debian packages.
# Based on https://docs.ros.org/en/humble/Installation/Ubuntu-Install-Debs.html
set -euo pipefail

# Ask for the sudo password once up front, then keep the sudo timestamp
# refreshed in the background so later sudo calls in this script don't re-prompt.
sudo -v
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT

# 1. Locale (UTF-8)
sudo apt update
sudo apt install -y locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8

# 2. Enable the Ubuntu Universe repository
sudo apt install -y software-properties-common
sudo add-apt-repository universe -y

# 3. Add the ROS 2 apt repository
sudo apt update
sudo apt install -y curl
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
  -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo "$UBUNTU_CODENAME") main" \
  | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null

# 4. Update apt and upgrade existing packages
sudo apt update
sudo apt upgrade -y

# 5. Install ROS 2 Humble (desktop = full install with GUI/demos/rviz)
sudo apt install -y ros-humble-desktop

# 6. Dev tools (colcon, rosdep, vcstool, etc.)
sudo apt install -y ros-dev-tools

# 7. Environment setup — source on every new shell
if ! grep -Fxq "source /opt/ros/humble/setup.bash" ~/.bashrc; then
  echo "source /opt/ros/humble/setup.bash" >> ~/.bashrc
fi

echo
echo "ROS 2 Humble installed. Run 'source ~/.bashrc' or open a new terminal to start using it."
