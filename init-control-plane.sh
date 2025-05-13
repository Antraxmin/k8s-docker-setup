#!/bin/bash
# Kubernetes Control Plane Initialization Script

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

# Find user's home directory
CURRENT_USER=$(logname 2>/dev/null || echo ${SUDO_USER:-${USER}})
USER_HOME=$(eval echo ~$CURRENT_USER)

# Auto-detect network interface and IP address
IFACE=$(ip -o -4 route show to default | awk '{print $5}')
IP_ADDR=$(ip -o -4 addr list $IFACE | awk '{print $4}' | cut -d/ -f1)

echo -e "${YELLOW}Initializing Kubernetes control plane...${NC}"
echo -e "${YELLOW}Using network interface: $IFACE${NC}"
echo -e "${YELLOW}IP address: $IP_ADDR${NC}"

# Confirm IP address with user
read -p "Is this IP address correct? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  read -p "Enter the IP address to use: " IP_ADDR
fi

# (Optional) Set Pod CIDR range
POD_CIDR="10.32.0.0/12"         # Weave Net default
read -p "Do you want to change the Pod CIDR range? (default: $POD_CIDR) (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  read -p "Enter the Pod CIDR range to use: " POD_CIDR
fi

# Run kubeadm init
echo -e "${YELLOW}Running kubeadm init command...${NC}"
kubeadm init --pod-network-cidr=$POD_CIDR --apiserver-advertise-address=$IP_ADDR --cri-socket=unix:///var/run/cri-dockerd.sock

# Set up kubeconfig
echo -e "${YELLOW}Configuring kubeconfig...${NC}"
mkdir -p $USER_HOME/.kube
cp -i /etc/kubernetes/admin.conf $USER_HOME/.kube/config
chown $CURRENT_USER:$CURRENT_USER $USER_HOME/.kube/config

# Install Weave Net
echo -e "${YELLOW}Installing Weave Net network plugin...${NC}"
su - $CURRENT_USER -c "kubectl apply -f \"https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s-1.11.yaml\""

# Save join token
echo -e "${YELLOW}Generating worker node join command...${NC}"
JOIN_CMD=$(kubeadm token create --print-join-command)
echo "$JOIN_CMD --cri-socket=unix:///var/run/cri-dockerd.sock" > $USER_HOME/worker-join.sh
chmod +x $USER_HOME/worker-join.sh
chown $CURRENT_USER:$CURRENT_USER $USER_HOME/worker-join.sh

echo -e "${GREEN}Control plane initialization complete!${NC}"
echo -e "${YELLOW}Worker node join command:${NC}"
echo -e "${GREEN}$JOIN_CMD --cri-socket=unix:///var/run/cri-dockerd.sock${NC}"
echo -e "${YELLOW}This command has been saved to $USER_HOME/worker-join.sh${NC}"
echo -e "${YELLOW}To check node status: kubectl get nodes${NC}"