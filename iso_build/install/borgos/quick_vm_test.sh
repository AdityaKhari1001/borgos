#!/bin/bash
# Quick VM test using Docker and QEMU

echo "Starting BorgOS VM test..."

# Simple QEMU in Docker
docker run -it --rm \
  --name borgos-test \
  --platform linux/amd64 \
  -v "$(pwd)/iso_output:/iso:ro" \
  -p 5901:5901 \
  -p 2222:22 \
  -p 6969:6969 \
  tianon/qemu:latest \
  qemu-system-x86_64 \
    -m 4096 \
    -cdrom /iso/BorgOS-Live-amd64.iso \
    -boot d \
    -vnc :1 \
    -nographic \
    -monitor stdio \
    -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::6969-:6969 \
    -device e1000,netdev=net0

# Access:
# VNC: localhost:5901
# SSH: localhost:2222
# WebUI: localhost:6969