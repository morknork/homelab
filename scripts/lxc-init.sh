#!/usr/bin/env bash
# =============================================================================
# lxc-init.sh — Initial LXC hardening script
# Creates a sudo admin user (madmin), hardens SSH, disables root login,
# installs zsh + oh-my-zsh + tldr
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

# =============================================================================
# 1. Set Locale & System update
# =============================================================================
# Guard the append: every unguarded >> in an idempotent script is a bug.
grep -qxF "en_AU.UTF-8 UTF-8" /etc/locale.gen 2>/dev/null \
    || echo "en_AU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

# Export BEFORE update-locale so its perl process runs in a sane env.
# LC_ALL overrides whatever LANG leaked in from the pct enter / SSH session.
export LANG=en_AU.UTF-8 LC_ALL=en_AU.UTF-8
update-locale LANG=en_AU.UTF-8

info "Updating package lists..."
apt-get update -qq

info "Upgrading installed packages..."
apt-get upgrade -y -qq

# =============================================================================
# 2. Install essentials
# =============================================================================
info "Installing essential packages..."
apt-get install -y -qq \
    curl \
    sudo \
    wget \
    ca-certificates \
    git \
    gnupg \
    lsb-release \
    openssh-server \
    zsh \
    pipx \
    command-not-found

info "Building command-not-found database..."
# cnf's apt hooks only exist after the package is installed, so the metadata
# is only fetched by an update run AFTER installation.
apt-get update -qq
update-command-not-found

# =============================================================================
# 3. Create admin user
# =============================================================================
if id "$ADMIN_USER" &>/dev/null; then
    warn "User '$ADMIN_USER' already exists — skipping creation."
else
    info "Creating user '$ADMIN_USER'..."
    useradd -m -s /bin/zsh "$ADMIN_USER"
    info "Please set a password for '$ADMIN_USER':"
    passwd "$ADMIN_USER" < /dev/tty
    usermod -aG sudo "$ADMIN_USER"
    info "User '$ADMIN_USER' created and added to sudo group."
fi

# =============================================================================
# 4. Lock root account
# =============================================================================
info "Locking root account..."
passwd -l root
info "Root account locked."

# =============================================================================
# 5. SSH key setup (optional but strongly recommended)
# =============================================================================
SSH_DIR="/home/${ADMIN_USER}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
touch "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"
chown -R "${ADMIN_USER}:${ADMIN_USER}" "$SSH_DIR"

echo ""
read -rp "Do you want to add an SSH public key for '$ADMIN_USER'? [y/N]: " ADD_KEY < /dev/tty
if [[ "$ADD_KEY" =~ ^[Yy]$ ]]; then
    echo "Paste your public key (e.g. contents of ~/.ssh/id_ed25519.pub), then press Enter:"
    read -r PUBKEY < /dev/tty
    if [[ -n "$PUBKEY" ]]; then
        grep -qxF "$PUBKEY" "$AUTH_KEYS" || echo "$PUBKEY" >> "$AUTH_KEYS"
        info "SSH public key added."
    else
        warn "No key entered — skipping."
    fi
else
    warn "No SSH key added. Make sure you can log in as '$ADMIN_USER' before continuing."
fi

# =============================================================================
# 6. Harden SSH config (drop-in, not sed)
# =============================================================================
# Debian's sshd_config Includes /etc/ssh/sshd_config.d/*.conf at the TOP of
# the file, and in OpenSSH the FIRST occurrence of a keyword wins. A drop-in
# named 00-* therefore beats both other drop-ins and the main config body.
# Rewriting the whole file each run is idempotent by construction.
info "Hardening SSH configuration..."
SSHD_DROPIN="/etc/ssh/sshd_config.d/00-hardening.conf"

cat > "$SSHD_DROPIN" <<EOF
# Managed by lxc-init.sh — edits here are overwritten on re-run
PermitRootLogin no
PasswordAuthentication yes
# keep PasswordAuthentication yes until key login confirmed
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers ${ADMIN_USER}
EOF
chmod 600 "$SSHD_DROPIN"

# Validate before we ever restart — a bad config plus a restart is a lockout.
if sshd -t 2>/dev/null; then
    info "sshd config valid."
else
    rm -f "$SSHD_DROPIN"
    error "sshd config validation failed — drop-in removed, sshd untouched."
fi

info "SSH hardened. Root login disabled."

# =============================================================================
# 7. Install oh-my-zsh + write .zshrc
# =============================================================================
info "Installing oh-my-zsh for '$ADMIN_USER'..."
su - "$ADMIN_USER" -c \
    'sh -c "$(wget -qO- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended' \
    < /dev/tty || warn "oh-my-zsh install encountered an issue — check manually."

info "Getting .zshrc for '$ADMIN_USER'..."
su - "$ADMIN_USER" -c \
    'wget -q -O "$HOME/.zshrc" "https://raw.githubusercontent.com/morknork/homelab/main/config/.zshrc"' \
    || warn "Failed to fetch .zshrc — leaving oh-my-zsh default."
info ".zshrc written."

# =============================================================================
# 8. Install tldr via pipx
# =============================================================================
info "Installing tldr via pipx for '$ADMIN_USER'..."
su - "$ADMIN_USER" -c 'pipx install tldr' < /dev/tty \
    || warn "tldr install encountered an issue — check manually."

info "Adding ~/.local/bin to PATH for '$ADMIN_USER'..."
su - "$ADMIN_USER" -c 'pipx ensurepath' \
    || warn "pipx ensurepath failed — add ~/.local/bin to PATH manually."

info "Updating tldr cache..."
# Run as the user it was installed for, via explicit path — the PATH change
# from ensurepath only applies to NEW login shells, not this one.
su - "$ADMIN_USER" -c '"$HOME/.local/bin/tldr" --update' \
    || warn "tldr cache update failed — run 'tldr -u' manually as $ADMIN_USER."
info "tldr installed."

# =============================================================================
# 9. Restart SSH
# =============================================================================
info "Restarting SSH service..."
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || warn "Could not restart SSH — do it manually."

# =============================================================================
# Done
# =============================================================================
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN} Initial hardening complete!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  Admin user   : $ADMIN_USER"
echo "  Shell        : zsh + oh-my-zsh"
echo "  tldr         : installed via pipx"
echo "  SSH config   : $SSHD_DROPIN"
echo "  Root login   : DISABLED"
echo "  Root account : LOCKED"
echo ""
echo -e "${YELLOW}IMPORTANT — Before closing this session:${NC}"
echo "  1. Open a NEW terminal and verify you can log in as '$ADMIN_USER'"
echo "  2. Verify 'sudo -v' works for '$ADMIN_USER'"
echo "  3. Only then close this root session"
echo ""
if [[ "$ADD_KEY" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Once key login is confirmed, disable password auth:${NC}"
    echo "  sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' $SSHD_DROPIN"
    echo "  systemctl restart ssh"
    echo ""
fi
