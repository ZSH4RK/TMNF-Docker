# TMNF-Docker
TMNF-Docker is a Linux-based Docker environment for running [TrackMania Nations Forever](https://www.trackmaniaforever.com/) with [TMLoader](https://tomashu.dev/software/tmloader/) 
using headless GPU rendering. The game runs inside the container through Wine with support for both Vulkan (via [DXVK](https://github.com/doitsujin/dxvk)) and OpenGL-based(via [VirtualGL](https://virtualgl.org/)) rendering. A VNC server can be enabled to view
the graphical output of the container. In addition the container includes a default TrackMania profile, allowing the game to be used immediately out of the box without additional 
configuration.

This project was originally designed for AI training workflows, but it can also be used for regular gameplay, testing, or experimentation. Special thanks go to the creators of [egl-docker](https://github.com/jeasinema/egl-docker), 
which provided important foundations for the GPU handling used in this setup.

---

## Table of Contents
- [TMNF-Docker](#tmnf-docker)
  * [Prerequisites](#prerequisites)
  * [Build the Container](#build-the-container)
    + [Build the Base Image](#build-the-base-image)
    + [Build the Vulkan Image](#build-the-vulkan-image)
  * [Running the Container](#running-the-container)
    + [VNC](#vnc)
    + [Rendering Options](#rendering-options)
      - [VirtualGL](#virtualgl)
      - [Vulkan (DXVK)](#vulkan--dxvk-)
  ---
## Prerequisites
If you are on Linux, you should use Docker Engine instead of Docker Desktop, as Docker Desktop does not support GPU-related workloads on Linux. For more information, see this 
[forum thread](https://forums.docker.com/t/cant-start-containers-with-gpu-access-on-linux-mint/144606/3). Additionally, you may need to install the NVIDIA Container Toolkit 
if you have not done so already.

---

## Build the Container
This repository provides two Dockerfiles: `docker/Dockerfile.base` and `docker/Dockerfile.vulkan`. The Base file acts as the primary image, building the entire environment including the game and 
all necessary software, utilizing VirtualGL for rendering. The Vulkan Dockerfile builds on top of the base image and serves as an extension that installs Vulkan and DXVK into the 
environment. It sets DXVK as the default rendering backend when running TMNF through Wine.

Regardless of which variant you build, the container starts as the predefined user `wineuser`. The Wine prefix 
automatically corresponds to the `.wine/` directory located in the `wineuser` home folder.

### Build the Base Image
Clone the repository and build the image by running:
```bash
git clone https://github.com/SgSiegens/TMNF-Docker 
cd TMNF-Docker
docker build -t <container_name>:<tag> -f docker/Dockerfile.base .
```

### Build the Vulkan Image
If you wish to also build the Vulkan image, you must first build the base image as described above, and then run:
```bash
docker build --build-arg BASE_IMAGE=<name_of_the_base_image_built_earlier>:<tag> -t <container_name>:<tag> -f docker/Dockerfile.vulkan .

```
## Running the Container
To start the container, simply run:
```bash
docker run --gpus all -it <container_name>:<tag> /bin/bash
```
--- 
### VNC
If you also want to enable VNC access, you need to expose the VNC port:
```bash
docker run -p <port:port> --gpus all -it <container_name>:<tag> /bin/bash
```
By default, the container uses port **5900:5900** for VNC. After the container is running, start the VNC server by executing the `start-vnc.sh` script from outside the container:
```bash
docker exec -it <container_id> start-vnc.sh
```
You can find the `<container_id>` by running `docker ps`. Once the script starts, it will display the IP address where you can access the VNC session using your VNC viewer. 
After that, you will be prompted to enter the VNC password configured for the user. By default, the password is `mypasswd`.

--- 
### Rendering Options

#### VirtualGL
The Base image supports rendering via VirtualGL, allowing the game to run using OpenGL with hardware acceleration. To use this, first check the detected EGL devices inside the container:
```bash
/opt/VirtualGL/bin/eglinfo -e
```
The output lists EGL devices and their associated `/dev/dri` card paths. Select the GPU you want to use and test hardware-accelerated OpenGL rendering with:
```bash
vglrun -d /dev/dri/card1 /opt/VirtualGL/bin/glxspheres64
```
or, if necessary:
```bash
vglrun -d egl1 /opt/VirtualGL/bin/glxspheres64
```
If the renderer shown in the output matches your GPU, then hardware acceleration is working correctly. You can also double-check this by opening a VNC session to view the desktop and confirming GPU usage 
on the host system (e.g. using the `nvidia-smi` command on NVIDIA hardware). Applications can be run with GPU-accelerated OpenGL by prefixing the command with `vglrun`, for example:
```bash
vglrun -d <eglx_or_dri_device_path> <your_command>
```
A few additional notes apply if you are using `vglrun` in a Python-based workflow, for example when training a TMNF agent using PyTorch. In such cases you may encounter errors such as:
```bash
Unable to load any of {libcudnn_graph.so.9.1.0, libcudnn_graph.so.9.1, libcudnn_graph.so.9, libcudnn_graph.so}
Invalid handle. Cannot load symbol cudnnCreate
```
The simplest workaround is not to run your entire Python script through `vglrun` and instead wrap only the game-launching command inside your script with `vglrun`. If that is not possible, you can dynamically 
load the required CUDA libraries by providing an additional `-ld` parameter to VirtualGL, as described [here](https://github.com/MorphoCloud/MorphoCloudWorkflow/issues/111#issuecomment-2864789501) and [here](https://github.com/VirtualGL/virtualgl/issues/227):

```bash
vglrun -d <eglx_or_dri_device_path> -ld <cuda_lib_path> <your_command>
```
For reference in a Conda environment we have found the required CUDA libraries under: 
```bash
/opt/conda/pkgs/pytorch-2.4.0-py3.11_cuda12.4_cudnn9.1.0_0/lib/python3.11/site-packages/torch/lib
```
If you are unsure where the CUDA libraries are located, you can search for them with:

```bash
find / -name "libcudnn_graph*.so*" 2>/dev/null
```

#### Vulkan (DXVK)
The Vulkan container utilizes DXVK by default, which translates DirectX calls into the Vulkan API for enhanced performance. You can verify that the Vulkan driver is correctly configured and detect your hardware by running:
```bash
vulkaninfo --summary
```
To test actual 3D rendering, run the following command inside the container:
```bash
vkcube
```
You can view the graphical output through a VNC session and confirm active GPU utilization on the host system using the `nvidia-smi` command. To run the game, simply launch it through Wine as you normally would. 
No additional prefixes are required for DXVK to function.
In the Vulkan container, you have the option to fall back on OpenGL to run the game. However, since this container enables DXVK by default, you must explicitly disable it to force OpenGL rendering. This is done 
by setting the following environment variable:
```bash
export WINEDLLOVERRIDES="d3d9=b;d3d10=b;d3d10_1=b;d3d10core=b;d3d11=b;dxgi=b"
```
Once DXVK is disabled, you should prefix your game command with `vglrun` as described in the OpenGL section.

