#!/bin/bash

# Kubernetes with Docker Setup Script
# Configures Docker as container runtime with modern Kubernetes (1.24+)
# Uses CRI-Docker integration

set -e

# Define colors for output
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'        # No Color

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}This script must be run with root privileges.${NC}"
  echo "Please run again with: sudo $0"
  exit 1
fi

echo -e "${YELLOW}Starting Kubernetes with Docker installation script...${NC}"

# Update system packages
echo -e "${YELLOW}Updating system packages...${NC}"
apt update
apt install -y apt-transport-https ca-certificates curl software-properties-common

# Install Docker
echo -e "${YELLOW}Installing Docker...${NC}"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Detect Ubuntu version and add appropriate repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# If version is not supported, use mantic
if [ $? -ne 0 ] || ! apt-cache policy docker-ce > /dev/null 2>&1; then
  echo -e "${YELLOW}Repository for $VERSION_CODENAME may not be supported yet. Using mantic repository instead.${NC}"
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    mantic stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
fi

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add current user to docker group
CURRENT_USER=$(logname 2>/dev/null || echo ${SUDO_USER:-${USER}})
usermod -aG docker $CURRENT_USER

# Configure Docker daemon
echo -e "${YELLOW}Configuring Docker daemon...${NC}"
cat << EOT > /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOT

mkdir -p /etc/systemd/system/docker.service.d
systemctl daemon-reload
systemctl restart docker
systemctl enable docker

# Prepare for Kubernetes installation
echo -e "${YELLOW}Preparing for Kubernetes installation...${NC}"
swapoff -a
sed -i '/swap/d' /etc/fstab

cat << EOT > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOT

modprobe overlay
modprobe br_netfilter

cat << EOT > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOT

sysctl --system

# Install CRI-Docker
echo -e "${YELLOW}Installing CRI-Docker...${NC}"
VER=$(curl -s https://api.github.com/repos/Mirantis/cri-dockerd/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//g')
wget -q https://github.com/Mirantis/cri-dockerd/releases/download/v${VER}/cri-dockerd-${VER}.amd64.tgz
tar xvf cri-dockerd-${VER}.amd64.tgz
mv cri-dockerd/cri-dockerd /usr/local/bin/
rm -rf cri-dockerd-${VER}.amd64.tgz cri-dockerd

# Install systemd services
wget -q https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.service
wget -q https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.socket
mv cri-docker.socket cri-docker.service /etc/systemd/system/
sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service

# Start services
systemctl daemon-reload
systemctl enable cri-docker.service
systemctl enable --now cri-docker.socket

# Install Kubernetes components
echo -e "${YELLOW}Installing Kubernetes components...${NC}"
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

apt update
apt install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

echo -e "${GREEN}Installation complete!${NC}"
echo -e "${YELLOW}On the control plane node, run init-control-plane.sh next.${NC}"
echo -e "${YELLOW}On worker nodes, run join-worker.sh.${NC}"