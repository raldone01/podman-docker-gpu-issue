# podman-docker-gpu-issue

This is the repository for reproducing https://github.com/containers/podman/issues/19338.

Running `./setup_lxc.sh create-containers` will create two containers called `uwuntu-podman` and `uwuntu-docker` based on the `ubuntu:22.04` image.

### Requirements

You must have `libvirt lxd qemu-full libvirt edk2-ovmf` installed on your system.
Follow the specific instructions for your distribution.
The script assumes you have a NVIDIA GPU and the drivers installed on the host.
The script must be adapted for non NVIDIA GPUs.
You must pass one of your GPUs to vfio-pci this can be done by adding the following kernel parameter:
`vfio-pci.ids=10de:1fb1,10de:10fa`
The ids are the `vendor:device` ids of your GPU.
Usually the GPUs consist of two devices, the GPU itself and the audio device.
To find the device ids of all your GPUs run `lspci -nn | grep -i nvidia`.

### Undo any system changes

Running `./setup_lxc.sh remove-containers` will delete the containers created by `create-containers`.
Don't forget to remove the kernel parameter `vfio-pci.ids=10de:1fb1,10de:10fa` if you added it.

## Validating the issues

```bash
distrobox enter --root uwuntu-docker -- bash
uwuntu-docker# nvidia-smi -L
uwuntu-docker# docker -v
uwuntu-docker# sudo docker-compose up
```

* `reservation_test`
* `nvidia_runtime_test`
* `cdi_device`
