#!/usr/bin/env bash
# =============================================================================
# docker-install.sh — Docker Engine + Compose plugin installer
# Installs Docker Engine and Docker Compose plugin on Debian/Ubuntu
# Run as root on a fresh Debian/Ubuntu LXC
# =============================================================================

set -euo pipefail

# --- Colour helpers ----------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# --- Must run as root --------------------------------------------------------
[[ $EUID -ne 0 ]] && error "This script must be run as root."

ADMIN_USER="madmin"

# --- Verify admin user exists ------------------------------------------------
id "$ADMIN_USER" &>/dev/null || error "User '$ADMIN_USER' does not exist. Run lxc-init.sh first."

# =============================================================================
# 1. Remove any old/distro Docker packages
# =============================================================================
info "Removing any conflicting Docker packages..."
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    apt-get remove -y -qq "$pkg" 2>/dev/null || true
done

# =============================================================================
# 2. Install dependencies for adding apt repo
# =============================================================================
info "Installing apt prerequisites..."
apt-get update -qq
apt-get install -y -qq \
    ca-certificates \
    wget \
    gnupg \
    lsb-release

# =============================================================================
# 3. Add Docker's official GPG key
# =============================================================================
info "Adding Docker GPG key..."
install -m 0755 -d /etc/apt/keyrings

wget -qO /etc/apt/keyrings/docker.asc \
    https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg

chmod a+r /etc/apt/keyrings/docker.asc

# =============================================================================
# 4. Add Docker apt repository
# =============================================================================
info "Adding Docker apt repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq

# =============================================================================
# 5. Install Docker Engine + Compose plugin
# =============================================================================
info "Installing Docker Engine and Compose plugin..."
apt-get install -y -qq \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# =============================================================================
# 6. Add admin user to docker group
# =============================================================================
info "Adding '$ADMIN_USER' to docker group..."
usermod -aG docker "$ADMIN_USER"

# =============================================================================
# 7. Enable and start Docker
# =============================================================================
info "Enabling and starting Docker..."
systemctl enable docker --quiet
systemctl start docker

# =============================================================================
# 8. Verify installation
# =============================================================================
info "Verifying Docker installation..."
DOCKER_VERSION=$(docker --version)
COMPOSE_VERSION=$(docker compose version)

# =============================================================================
# Done
# =============================================================================
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN} Docker installation complete!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  $DOCKER_VERSION"
echo "  $COMPOSE_VERSION"
echo ""
echo "  '$ADMIN_USER' added to docker group"
echo ""
echo -e "${YELLOW}NOTE:${NC} Group changes take effect on next login."
echo "  Log out and back in as '$ADMIN_USER', then verify with:"
echo "  docker run hello-world"
echo ""
echo "  Note:  Unprivileged LXC requires nesting & keyctl enabled in options"
echo ""
