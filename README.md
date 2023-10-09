# podman-docker-gpu-issue

This is the repository for reproducing https://github.com/containers/podman/issues/19338.

Running `./setup_distrobox.sh create-containers` will create two containers called `uwuntu-podman` and `uwuntu-docker` based on the `ubuntu:22.04` image.

### Requirements

You must have `distrobox` installed on your system.
The script assumes you have a NVIDIA GPU and the drivers installed on the host.
Minor changes may be necessary if you don't have a NVIDIA GPU.

### Undo any system changes

Running `./setup_distrobox.sh remove-containers` will delete the containers created by `create-containers`.

## Validating the issues

```bash
distrobox enter --root uwuntu-docker -- bash
uwuntu-docker# nvidia-smi -L
uwuntu-docker# docker -v
uwuntu-docker# docker-compose up
```
