#!/bin/bash
# instead of archiso_script use the name of the container
sudo podman run --privileged --rm --mount type=bind,source="$(pwd)"/dev,target=/home/dev -it localhost/archiso_script bash
