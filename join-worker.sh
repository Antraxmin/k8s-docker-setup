#!/bin/bash
# Worker Node Join Script

set -e

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}This script must be run with root privileges.${NC}"
  echo "Please run again with: sudo $0"
  exit 1
fi

# Ask for join command
echo -e "${YELLOW}Please enter the join command generated on the control plane node.${NC}"
echo -e "${YELLOW}You can get this command by running 'kubeadm token create --print-join-command' on the control plane.${NC}"
read -p "Join command: " JOIN_CMD

# Check if CRI socket is included
if [[ ! $JOIN_CMD == *"--cri-socket"* ]]; then
  JOIN_CMD="$JOIN_CMD --cri-socket=unix:///var/run/cri-dockerd.sock"
fi

# Execute join command
echo -e "${YELLOW}Joining the cluster...${NC}"
$JOIN_CMD

echo -e "${GREEN}Worker node has joined the cluster!${NC}"
echo -e "${YELLOW}Run 'kubectl get nodes' on the control plane to verify the status.${NC}"