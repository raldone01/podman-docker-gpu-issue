#!/bin/bash

set -x

create_containers() {
    echo "Creating containers..."

    BASE_PACKAGES="systemd libsystemd0 git inetutils-ping inetutils-traceroute build-essential libglib2.0-dev"

    distrobox create -n uwuntu-docker --image ubuntu:22.04 \
    --additional-packages "$BASE_PACKAGES docker docker-compose" \
    --root --no-entry --yes --init --unshare-netns --unshare-ipc --nvidia # omit the --nvidia flag if using intel or amd
    distrobox create -n uwuntu-podman --image ubuntu:22.04 \
    --additional-packages "$BASE_PACKAGES podman docker-compose" \
    --root --no-entry --yes --init --unshare-netns --unshare-ipc --nvidia # omit the --nvidia flag if using intel or amd

    echo "set -x \
    && sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml --device-name-strategy=uuid \
    && sudo nvidia-ctk runtime configure --runtime=docker \
    && sudo systemctl enable --now docker \
    && sudo usermod -aG docker $USER" |
    distrobox enter --root uwuntu-docker -- bash

    echo "set -x \
    && sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml --device-name-strategy=uuid \
    && sudo systemctl enable --now podman.socket" |
    distrobox enter --root uwuntu-podman
}

stop_containers() {
    echo "Stopping containers..."
    distrobox stop --yes uwuntu-docker
    distrobox stop --yes uwuntu-podman
}

remove_containers() {
    stop_containers
    echo "Removing containers..."
    distrobox rm -f uwuntu-docker
    distrobox rm -f uwuntu-podman
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
        create_containers
        ;;

    remove-containers)
        remove_containers
        ;;

    stop-containers)
        stop_containers
        ;;

    *)
        # If an unknown command is passed
        echo "Unknown command: $command"
        echo "Usage: ./setup_distrobox.sh <create-containers|remove-containers>"
        exit 1
        ;;
esac
