#!/usr/bin/env bash
# Creates a sudo admin user (madmin), gets tools, harden ssh, disables root login

# e - exit if any command fails
# u - treat unset variables as errors
# o - pipeline fail if any command fails
set -euo pipefail

# Colour helpers
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Check for root user
[[ $EUID -ne 0 ]] && error "This script must be run as root."

ADMIN_USER="madmin"

# Updates
info "Updating package lists..."
apt-get update -qq

info "Upgrading installed packages..."
apt-get upgrade -y -qq

# Get Packages
info "Installing essential packages..."
apt-get install -y -qq \
    sudo \
    curl \
    wget \
    git \
    unzip \
    ca-certificates \
    gnupg \
    lsb-release \
    openssh-server 

# Create Admin user
if id "$ADMIN_USER" &>/dev/null; then
    warn "User '$ADMIN_USER' already exists — skipping creation."
else
    info "Creating user '$ADMIN_USER'..."
    useradd -m -s /bin/bash "$ADMIN_USER"
    info "Please set a password for '$ADMIN_USER':"
    passwd "$ADMIN_USER"
    usermod -aG sudo "$ADMIN_USER"
    info "User '$ADMIN_USER' created and added to sudo group."
fi

# SSH key setup
SSH_DIR="/home/${ADMIN_USER}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
touch "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"
chown -R "${ADMIN_USER}:${ADMIN_USER}" "$SSH_DIR"

echo ""
read -rp "Do you want to add an SSH public key for '$ADMIN_USER'? [y/N]: " ADD_KEY
if [[ "$ADD_KEY" =~ ^[Yy]$ ]]; then
    echo "Paste your public key (e.g. contents of ~/.ssh/id_ed25519.pub), then press Enter:"
    read -r PUBKEY
    if [[ -n "$PUBKEY" ]]; then
        echo "$PUBKEY" >> "$AUTH_KEYS"
        info "SSH public key added."
    else
        warn "No key entered — skipping."
    fi
else
    warn "No SSH key added. Make sure you can log in as '$ADMIN_USER' before continuing."
fi

# SSH hardening
info "Hardening SSH configuration..."
SSHD_CONFIG="/etc/ssh/sshd_config"

# Back up original
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"

# Apply settings — update if present, append if not
_sshd_set() {
    local key="$1" val="$2"
    if grep -qE "^#?${key}" "$SSHD_CONFIG"; then
        sed -i "s|^#\?${key}.*|${key} ${val}|" "$SSHD_CONFIG"
    else
        echo "${key} ${val}" >> "$SSHD_CONFIG"
    fi
}

_sshd_set "PermitRootLogin"          "no"
_sshd_set "PasswordAuthentication"   "yes"   # keep yes until key login confirmed
_sshd_set "PubkeyAuthentication"     "yes"
_sshd_set "AuthorizedKeysFile"       ".ssh/authorized_keys"
_sshd_set "PermitEmptyPasswords"     "no"
_sshd_set "X11Forwarding"            "no"
_sshd_set "MaxAuthTries"             "3"
_sshd_set "LoginGraceTime"           "30"
_sshd_set "AllowUsers"               "$ADMIN_USER"

info "SSH hardened. Root login disabled."

info "Restarting SSH service..."
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || warn "Could not restart SSH — do it manually."

# Final
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN} Initial hardening complete!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  Admin user : $ADMIN_USER"
echo "  Root login : DISABLED"
echo ""
echo -e "${YELLOW}IMPORTANT — Before closing this session:${NC}"
echo "  1. Open a NEW terminal and verify you can log in as '$ADMIN_USER'"
echo "  2. Verify 'sudo -v' works for '$ADMIN_USER'"
echo "  3. Only then close this root session"
echo ""
if [[ "$ADD_KEY" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Once key login is confirmed, consider running:${NC}"
    echo "  sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config"
    echo "  systemctl restart ssh"
    echo ""
fi
