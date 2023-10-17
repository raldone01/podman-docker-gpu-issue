#!/bin/bash
set -x

# set working directory to the directory of this script
cd "$(dirname "$0")"

wait_for_lxd_agent() {
  container_name="$1"
  echo "Waiting for LXD agent to start in $container_name..."
  while ! sudo lxc exec "$container_name" /bin/true > /dev/null 2>&1; do
    sleep 1
  done
  echo "LXD agent started in $container_name."
}

common_setup() {
  sudo systemctl disable --now snapd.seeded.service
  sudo apt-get update -y
  sudo apt-get install -y systemd libsystemd0 git inetutils-ping inetutils-traceroute build-essential libglib2.0-dev
  sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml --device-name-strategy=uuid
}

podman_post_setup() {
  sudo apt install -y podman
  sudo systemctl enable --now podman.socket
}

docker_post_setup() {
  sudo apt install -y docker docker-compose
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl enable --now docker
  sudo usermod -aG docker $USER
}

# 0000:0e:00.0 vga NVIDIA Corporation TU117GL [T600] [10de:1fb1] (rev a1)
# 0000:0e:00.1 audio NVIDIA Corporation Device [10de:10fa] (rev a1)
# vfio-pci.ids=10de:1fb1,10de:10fa
# echo 0000:0e:00.1 > /sys/bus/pci/devices/0000:0e:00.1/driver/unbind
# echo 0000:0e:00.0 > /sys/bus/pci/devices/0000:0e:00.0/driver/unbind
# sudo virsh nodedev-detach pci_0000_0e_00_1 pci_0000_0e_00_0

host_common_setup() {
  container_name="$1"
  sudo lxc config device add "$container_name" compose-data disk source=$(realpath .) path=/data
  sudo lxc config device set "$container_name" compose-data readonly true
  sudo lxc start "$container_name"
  wait_for_lxd_agent "$container_name"
  sudo lxc exec "$container_name" -- bash -c "$(declare -f common_setup); common_setup"
}

create_container() {
  container_name="$1"
  if [[ -z "$container_name" ]]; then
    echo "No container name provided."
    exit 1
  fi

  pci_address_of_gpu="$2"
  if [[ -z "$pci_address_of_gpu" ]]; then
    echo "No PCI address provided for the GPU."
    exit 1
  fi

  echo "Creating container $container_name..."
  # Note: set if not --vm -c nvidia.runtime=true
  sudo lxc init ubuntu:22.04 "$container_name" --vm  -c security.secureboot=false < lxc-base.yml
  echo "Adding GPU $pci_address_of_gpu to $container_name"
  sudo lxc config device add "$container_name" gpu1 gpu pci=$pci_address_of_gpu

  echo "Setting up $container_name..."
  host_common_setup "$container_name"
  if [[ "$container_name" == "uwuntu-docker" ]]; then
    sudo lxc exec "$container_name" -- bash -c "$(declare -f docker_post_setup); docker_post_setup"
  else if [[ "$container_name" == "uwuntu-podman" ]]; then
    sudo lxc exec "$container_name" -- bash -c "$(declare -f podman_post_setup); podman_post_setup"
  else
    echo "Unknown container name: $container_name"
    exit 1
  fi
  sudo lxc stop "$container_name"
}

create_containers() {
  # Extract the PCI address of the GPU from the first argument passed to create_containers
  pci_address_of_gpu="$1"

  create_container "uwuntu-docker" "$pci_address_of_gpu"
  create_container "uwuntu-podman" "$pci_address_of_gpu"
}

enter_container() {
  container_name="$1"
  if [[ -z "$container_name" ]]; then
    echo "No container name provided."
    exit 1
  fi

  # stop other containers
  if [[ "$container_name" == "uwuntu-docker" ]]; then
    sudo lxc stop --force uwuntu-podman
  else if [[ "$container_name" == "uwuntu-podman" ]]; then
    sudo lxc stop --force uwuntu-docker
  else
    echo "Unknown container name: $container_name"
    exit 1
  fi

  echo "Entering container $container_name..."
  sudo lxc start "$container_name"
  wait_for_lxd_agent "$container_name"
  sudo lxc exec "$container_name" -- bash
}

stop_containers() {
    echo "Stopping containers..."
    sudo lxc stop --force uwuntu-docker
    sudo lxc stop --force uwuntu-podman
}

remove_containers() {
    stop_containers
    echo "Removing containers..."
    sudo lxc delete -f uwuntu-docker
    sudo lxc delete -f uwuntu-podman
}

# Validate the number of arguments
if [ "$#" -lt 1 ]; then
    echo "Usage: ./setup_lxc.sh <create-containers|remove-containers> [additional_args]"
    exit 1
fi

# Parse the command
command="$1"
shift

# Use a case statement to handle the commands
case "$command" in
    create-container)
        create_container "$@"
        ;;

    enter-container)
        enter_container "$@"
        ;;

    create-containers)
        create_containers "$@"
        ;;

    remove-containers)
        remove_containers "$@"
        ;;

    stop-containers)
        stop_containers "$@"
        ;;

    *)
        # If an unknown command is passed
        echo "Unknown command: $command"
        echo "Usage: ./setup_lxc.sh <create-containers|remove-containers>"
        exit 1
        ;;
esac
