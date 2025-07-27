#!/bin/bash

# Proxmox VE Helper Script for ha-fusion LXC Container
# https://github.com/your-username/proxmox-ha-fusion
# WARNING: Inspect this script before running. Run at your own risk.
# Dependencies: bash, curl, wget, pct (Proxmox VE 8.x), Debian 12 LXC template
# Created by: [Your GitHub Username]
# Last Updated: July 27, 2025
# Description: Sets up an LXC container with ha-fusion for Home Assistant.

# Exit on error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fixed defaults
VMID=100
HOSTNAME="ha-fusion"
STORAGE="local-lvm"
DISK_SIZE="8"
MEMORY=512
CORES=1
NETWORK="name=eth0,bridge=vmbr0,ip=dhcp"
CONTAINER_TEMPLATE="debian-12-standard"
HASS_URL="http://192.168.1.241:8123"
TIMEZONE="Europe/Stockholm"
PORT="5050"

# Header
header() {
    echo -e "${GREEN}=== ha-fusion LXC Setup ===${NC}"
    echo -e "${YELLOW}Sets up ha-fusion for Home Assistant in an LXC container.${NC}"
    echo -e "${RED}WARNING: Review this script before running: https://github.com/your-username/proxmox-ha-fusion${NC}"
    echo ""
}

# Check root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: Run as root.${NC}"
        exit 1
    fi
}

# Check Proxmox VE
check_proxmox() {
    if ! command -v pveversion >/dev/null 2>&1; then
        echo -e "${RED}Error: Proxmox VE not detected.${NC}"
        exit 1
    fi
}

# Check LXC template
check_template() {
    if [ ! -f "/var/lib/vz/template/cache/${CONTAINER_TEMPLATE}.tar.gz" ]; then
        echo -e "${RED}Error: Debian 12 template missing. Run 'pveam update' and 'pveam download local ${CONTAINER_TEMPLATE}'.${NC}"
        exit 1
    fi
}

# Validate VMID
check_vmid() {
    if ! [[ "$VMID" =~ ^[0-9]+$ ]] || [ "$VMID" -lt 100 ] || [ "$VMID" -gt 999999 ]; then
        echo -e "${RED}Error: VMID must be a number between 100 and 999999.${NC}"
        exit 1
    fi
    if pct status "$VMID" >/dev/null 2>&1; then
        echo -e "${RED}Error: VMID $VMID already in use.${NC}"
        exit 1
    fi
}

# Prompt for minimal configuration
prompt_config() {
    echo -e "${YELLOW}Enter VMID (default: $VMID) and Home Assistant URL.${NC}"
    read -p "VMID [$VMID]: " input_vmid
    VMID=${input_vmid:-$VMID}
    check_vmid
    read -p "Home Assistant URL [$HASS_URL]: " input_hass_url
    HASS_URL=${input_hass_url:-$HASS_URL}
}

# Create LXC container
create_lxc() {
    echo -e "${GREEN}Creating LXC container (VMID $VMID)...${NC}"
    pct create "$VMID" "local:vztmpl/${CONTAINER_TEMPLATE}.tar.gz" \
        --hostname "$HOSTNAME" \
        --storage "$STORAGE" \
        --rootfs "${STORAGE}:${DISK_SIZE}" \
        --memory "$MEMORY" \
        --cores "$CORES" \
        --net0 "$NETWORK" \
        --features nesting=1 \
        --unprivileged 1 \
        --start 1 || { echo -e "${RED}Error: Failed to create LXC container.${NC}"; exit 1; }
}

# Install Docker and ha-fusion
install_hafusion() {
    echo -e "${GREEN}Installing ha-fusion...${NC}"
    sleep 5
    pct exec "$VMID" -- bash -c "
        set -e
        apt-get update && apt-get install -y curl wget docker.io docker-compose
        mkdir -p /ha-fusion
        cat > /ha-fusion/docker-compose.yml <<EOF
version: '3'
services:
  ha-fusion:
    image: ghcr.io/matt8707/ha-fusion:latest
    container_name: ha-fusion
    network_mode: bridge
    ports:
      - '${PORT}:5050'
    volumes:
      - /ha-fusion:/app/data
    environment:
      - TZ=${TIMEZONE}
      - HASS_URL=${HASS_URL}
    restart: always
EOF
        cd /ha-fusion
        docker-compose up -d ha-fusion
    " || { echo -e "${RED}Error: Failed to install ha-fusion.${NC}"; exit 1; }
    CONTAINER_IP=$(pct exec "$VMID" -- ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    echo -e "${GREEN}ha-fusion running at http://${CONTAINER_IP}:${PORT}${NC}"
    echo -e "${YELLOW}Ensure Home Assistant is at ${HASS_URL}.${NC}"
}

# Main
header
check_root
check_proxmox
check_template
prompt_config
create_lxc
install_hafusion

echo -e "${GREEN}Done!${NC}"
echo -e "${YELLOW}Check logs: pct exec $VMID -- docker logs ha-fusion${NC}"
echo -e "${YELLOW}Update: pct exec $VMID -- bash -c 'cd /ha-fusion && docker-compose pull ha-fusion && docker-compose up -d ha-fusion'${NC}"
