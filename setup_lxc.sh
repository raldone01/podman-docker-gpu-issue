#!/bin/bash
set -x

# set working directory to the directory of this script
cd "$(dirname "$0")" || exit

# distro="ubuntu"
# distro_slug="ubuntu:22.04"

distro="debian"
distro_slug="images:debian/12"

display_help() {
    echo "Usage: $0 COMMAND [OPTIONS]"
    echo
    echo "Commands:"
    echo "  create-container CONTAINER_NAME PCI_ADDRESS      Create a container with the specified name and PCI address."
    echo "  enter-container CONTAINER_NAME                  Enter the container with the specified name."
    echo "  create-containers PCI_ADDRESS                   Create containers (uwuntu-docker, uwuntu-podman) with the specified PCI address."
    echo "  remove-containers                               Remove the containers (uwuntu-docker, uwuntu-podman)."
    echo "  stop-containers                                 Stop the containers (uwuntu-docker, uwuntu-podman)."
    echo "  help                                            Show this help message."
    echo
    echo "Options:"
    echo "  CONTAINER_NAME    The name of the container."
    echo "  PCI_ADDRESS       The PCI address of the GPU."
    echo
    echo "Example:"
    echo "  ./setup_lxc.sh create-container my-container 0000:0e:00.0"
}

wait_for_lxd_agent() {
  container_name="$1"
  echo "Waiting for LXD agent to start in $container_name..."
  # not working: lxc-wait -n "$container_name" -s RUNNING
  while ! sudo lxc exec "$container_name" /bin/true > /dev/null 2>&1; do
    sleep 1
  done
  echo "LXD agent started in $container_name."
}

common_setup() {
  sudo apt-get update -y
  sudo apt-get install -y systemd libsystemd0 git inetutils-ping inetutils-traceroute build-essential libglib2.0-dev curl gnupg

  if [[ "$distro" == "ubuntu" ]]; then
    sudo systemctl disable --now snapd.seeded.service
    sudo apt-get install -y --no-install-recommends nvidia-headless-535 nvidia-utils-535
    # sudo apt-get install -y ubuntu-drivers-common
    # sudo ubuntu-drivers autoinstall
  elif [[ "$distro" == "debian" ]]; then
    echo "deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware" | sudo tee /etc/apt/sources.list

    sudo apt-get update -y
    export DEBIAN_FRONTEND=noninteractive
    sudo -E apt-get install -y -f firmware-misc-nonfree nvidia-driver-bin nvidia-kernel-dkms linux-headers-amd64 nvidia-smi libcuda1
    sudo modprobe -r nouveau
    sudo modprobe nvidia-current
  else
    echo "Unknown distro: $distro"
    exit 1
  fi

  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list \
  && \
    sudo apt-get update -y

  sudo apt-get install -y nvidia-container-toolkit

  sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml --device-name-strategy=uuid
}

podman_post_setup() {
  sudo apt install -y podman python3-pip pipx
  sudo systemctl enable --now podman.socket
  pipx install podman-compose
  pipx ensurepath
}

run_cmd_in_container() {
  container_name="$1"
  cmd="$2"
  sudo lxc exec "$container_name" -- bash -c "distro=$distro; distro_slug=$distro_slug; $cmd"
}

docker_post_setup() {
  # https://docs.docker.com/engine/install/ubuntu/
  # Add Docker's official GPG key:
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/$distro/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  # Add the repository to Apt sources:
  echo \
    "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$distro \
    "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -y

  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-compose

  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl enable --now docker
  sudo usermod -aG docker "$USER"
}

# 0000:0e:00.0 vga NVIDIA Corporation TU117GL [T600] [10de:1fb1] (rev a1)
# 0000:0e:00.1 audio NVIDIA Corporation Device [10de:10fa] (rev a1)
# vfio-pci.ids=10de:1fb1,10de:10fa
# echo 0000:0e:00.1 > /sys/bus/pci/devices/0000:0e:00.1/driver/unbind
# echo 0000:0e:00.0 > /sys/bus/pci/devices/0000:0e:00.0/driver/unbind
# sudo virsh nodedev-detach pci_0000_0e_00_1 pci_0000_0e_00_0

host_common_setup() {
  container_name="$1"
  sudo lxc config device add "$container_name" compose-data disk source="$(realpath .)" path=/data
  sudo lxc config device set "$container_name" compose-data readonly true
  sudo lxc start "$container_name"
  wait_for_lxd_agent "$container_name"
  run_cmd_in_container "$container_name" "$(declare -f common_setup); common_setup"
}

stop_other_containers() {
  container_name="$1"

  if [[ "$container_name" != "uwuntu-docker" ]]; then
    sudo lxc stop --force uwuntu-docker
  fi
  if [[ "$container_name" != "uwuntu-podman" ]]; then
    sudo lxc stop --force uwuntu-podman
  fi
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

  stop_other_containers "$container_name"

  echo "Creating container $container_name..."
  # Note: set if not --vm -c nvidia.runtime=true
  sudo lxc init "$distro_slug" "$container_name" --vm  -c security.secureboot=false < lxc-base.yml
  echo "Adding GPU $pci_address_of_gpu to $container_name"
  sudo lxc config device add "$container_name" gpu1 gpu pci="$pci_address_of_gpu"

  echo "Setting up $container_name..."
  host_common_setup "$container_name"
  if [[ "$container_name" == "uwuntu-docker" ]]; then
    run_cmd_in_container "$container_name" "$(declare -f docker_post_setup); docker_post_setup"
  elif [[ "$container_name" == "uwuntu-podman" ]]; then
    run_cmd_in_container "$container_name" "$(declare -f podman_post_setup); podman_post_setup"
  else
    echo "Unknown container name: $container_name"
    exit 1
  fi
  # sudo lxc stop "$container_name" hangs indefinitely
  run_cmd_in_container "$container_name" "sudo systemctl poweroff"
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

  stop_other_containers "$container_name"

  echo "Entering container $container_name..."
  sudo lxc start "$container_name"
  wait_for_lxd_agent "$container_name"
  sudo lxc exec "$container_name" -- bash -c "cd /data && bash"
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
    display_help
    exit 1
fi

# Parse the command
command="$1"
shift

# Use a case statement to handle the commands
case "$command" in
    create-container)
        create_container "$@"
        exit 0
        ;;

    enter-container)
        enter_container "$@"
        exit 0
        ;;

    create-containers)
        create_containers "$@"
        exit 0
        ;;

    remove-containers)
        remove_containers "$@"
        exit 0
        ;;

    stop-containers)
        stop_containers "$@"
        exit 0
        ;;

    help)
        display_help
        exit 0
        ;;
    *)
        echo "Unknown command: $command"
        display_help
        exit 1
        ;;
esac
