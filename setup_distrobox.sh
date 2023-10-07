#!/bin/bash

set -x

# Function stub for creating containers
create_containers() {
    echo "Creating containers..."

    distrobox create -n uwuntu-docker --image ubuntu:20.04 \
    --additional-packages "systemd libsystemd0 git inetutils-ping inetutils-traceroute build-essential docker docker-compose" \
    --init --unshare-netns --unshare-ipc --nvidia # omit the --nvidia flag if using intel or amd
    distrobox create -n uwuntu-podman --image ubuntu:20.04 \
    --additional-packages "systemd libsystemd0 git inetutils-ping inetutils-traceroute build-essential podman" \
    --init --unshare-netns --unshare-ipc --nvidia # omit the --nvidia flag if using intel or amd

    distrobox enter uwuntu-docker
    sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml --device-name-strategy=uuid
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl enable --now docker
    sudo usermod -aG docker $USER
    exit

    distrobox enter uwuntu-podman
    sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml --device-name-strategy=uuid
    sudo nvidia-ctk runtime configure --runtime=podman
    sudo systemctl enable --now podman.socket
    sudo usermod -aG podman $USER
    exit
}

# Function stub for removing containers
remove_containers() {
    echo "Removing containers..."
    distrobox stop uwuntu-docker
    distrobox stop uwuntu-podman
    distrobox rm uwuntu-docker
    distrobox rm uwuntu-podman
}

# Validate the number of arguments
if [ "$#" -ne 1 ]; then
    echo "Usage: ./setup_distrobox.sh <create-containers|remove-containers>"
    exit 1
fi

# Parse the command
command="$1"

# Use a case statement to handle the commands
case "$command" in
    create-containers)
        create_containers  # Call the function stub for creating containers
        ;;

    remove-containers)
        remove_containers  # Call the function stub for removing containers
        ;;

    *)
        # If an unknown command is passed
        echo "Unknown command: $command"
        echo "Usage: ./setup_distrobox.sh <create-containers|remove-containers>"
        exit 1
        ;;
esac
