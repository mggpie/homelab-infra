#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Proxmox VE VM provisioner
#
# Creates a KVM VM with Debian 12 (unattended) and runs Ansible
# to install Proxmox VE on top.
#
# Usage:
#   make proxmox             Full run (recommended)
#   make proxmox-ansible     Ansible only
#   make proxmox-destroy     Tear down VM
# ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANSIBLE_DIR="$REPO_ROOT/ansible"

VM_NAME="proxmox"
VM_RAM=8192          # MB
VM_CPUS=4
VM_DISK=80           # GB
VM_NETWORK="default" # libvirt network (NAT with DHCP)
VM_IP="192.168.122.10"
VM_MAC="52:54:00:ab:cd:10"  # fixed MAC -> fixed DHCP lease
ISO_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.9.0-amd64-netinst.iso"
CACHE_DIR="$REPO_ROOT/.cache"
ISO_FILE="$CACHE_DIR/debian-12-netinst.iso"
PRESEED_SRC="$ANSIBLE_DIR/files/preseed.cfg"
PRESEED_TMP="$CACHE_DIR/preseed.cfg"
SECRETS_FILE="$ANSIBLE_DIR/secrets.yml"
VAULT_PASS_FILE="$ANSIBLE_DIR/.vault_pass"
SSH_KEY_FILE="$HOME/.ssh/id_ed25519"
DISK_PATH="/var/lib/libvirt/images/${VM_NAME}.qcow2"

RED='[0;31m'
GREEN='[0;32m'
YELLOW='[1;33m'
NC='[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[x]${NC} $*" >&2; exit 1; }

# --- Destroy -------------------------------------------------
destroy_vm() {
    log "Destroying VM: $VM_NAME"
    virsh destroy "$VM_NAME" 2>/dev/null || true
    virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
    log "VM destroyed"
    exit 0
}

# --- Prerequisites -------------------------------------------
check_deps() {
    local deps=(virsh virt-install qemu-img ansible-playbook ansible-vault curl openssl)
    for cmd in "${deps[@]}"; do
        command -v "$cmd" &>/dev/null || die "Missing: $cmd"
    done
    [[ -f "$VAULT_PASS_FILE" ]] || die "Missing ansible/.vault_pass file"
    [[ -f "$SSH_KEY_FILE.pub" ]] || die "Missing SSH public key: ${SSH_KEY_FILE}.pub"
}

# --- Read secret from vault ----------------------------------
vault_get() {
    local key="$1"
    ansible-vault view "$SECRETS_FILE" --vault-password-file "$VAULT_PASS_FILE"         | grep "^${key}:" | sed "s/^${key}: *//" | tr -d '"'
}

# --- DHCP reservation ----------------------------------------
setup_dhcp() {
    if ! virsh net-dumpxml "$VM_NETWORK" | grep -q "$VM_MAC"; then
        log "Adding DHCP reservation: $VM_MAC -> $VM_IP"
        virsh net-update "$VM_NETWORK" add ip-dhcp-host             "<host mac='$VM_MAC' name='$VM_NAME' ip='$VM_IP'/>"             --live --config 2>/dev/null || true
    fi
}

# --- Download Debian ISO -------------------------------------
download_iso() {
    mkdir -p "$CACHE_DIR"
    if [[ -f "$ISO_FILE" ]]; then
        log "Debian ISO already cached"
        return
    fi
    log "Downloading Debian 12 netinst ISO..."
    curl -L -o "$ISO_FILE" "$ISO_URL"
    log "ISO downloaded"
}

# --- Prepare preseed -----------------------------------------
prepare_preseed() {
    local root_pw user_pw ssh_pub
    root_pw="$(vault_get vault_root_password)"
    user_pw="$(vault_get vault_user_password)"
    ssh_pub="$(cat "${SSH_KEY_FILE}.pub")"

    local root_hash user_hash
    root_hash="$(openssl passwd -6 "$root_pw")"
    user_hash="$(openssl passwd -6 "$user_pw")"

    mkdir -p "$CACHE_DIR"
    sed         -e "s|ROOTPW_PLACEHOLDER|${root_hash}|"         -e "s|USERPW_PLACEHOLDER|${user_hash}|"         -e "s|SSHKEY_PLACEHOLDER|${ssh_pub}|"         "$PRESEED_SRC" > "$PRESEED_TMP"

    log "Preseed prepared with hashed passwords + SSH key"
}

# --- Create VM -----------------------------------------------
create_vm() {
    if virsh dominfo "$VM_NAME" &>/dev/null; then
        warn "VM '$VM_NAME' already exists -- skipping creation"
        if [[ "$(virsh domstate "$VM_NAME" 2>/dev/null)" != "running" ]]; then
            virsh start "$VM_NAME"
        fi
        return
    fi

    log "Creating VM: $VM_NAME (${VM_CPUS} vCPU, ${VM_RAM}MB RAM, ${VM_DISK}GB disk)"

    virt-install         --name "$VM_NAME"         --ram "$VM_RAM"         --vcpus "$VM_CPUS"         --cpu host-passthrough         --os-variant debian12         --disk "path=${DISK_PATH},size=${VM_DISK},format=qcow2,bus=virtio,cache=writeback"         --network "network=${VM_NETWORK},mac=${VM_MAC},model=virtio"         --graphics none         --console pty,target_type=serial         --location "$ISO_FILE"         --initrd-inject "$PRESEED_TMP"         --extra-args "auto=true priority=critical preseed/file=/preseed.cfg console=ttyS0,115200n8"         --noreboot         --wait -1

    log "Debian installation complete -- starting VM"
    virsh start "$VM_NAME"
}

# --- Wait for SSH --------------------------------------------
wait_ssh() {
    log "Waiting for SSH on $VM_IP..."
    local tries=0
    while ! ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -i "$SSH_KEY_FILE" me@"$VM_IP" true 2>/dev/null; do
        tries=$((tries + 1))
        [[ $tries -ge 60 ]] && die "SSH timeout after 60 attempts"
        sleep 5
    done
    log "SSH is up"
}

# --- Run Ansible ---------------------------------------------
run_ansible() {
    log "Running Ansible playbook..."
    cd "$ANSIBLE_DIR"
    ansible-playbook playbook.yml "$@"
    log "Proxmox VE deployment complete!"
    echo
    echo -e "${GREEN}===================================================${NC}"
    echo -e "${GREEN}  Proxmox VE Web UI: https://${VM_IP}:8006${NC}"
    echo -e "${GREEN}  User: me@pam${NC}"
    echo -e "${GREEN}  SSH:  ssh me@${VM_IP}${NC}"
    echo -e "${GREEN}===================================================${NC}"
}

# --- Main ----------------------------------------------------
main() {
    case "${1:-full}" in
        destroy)  destroy_vm ;;
        ansible)  check_deps; run_ansible "${@:2}" ;;
        full|"")  check_deps; setup_dhcp; download_iso; prepare_preseed; create_vm; wait_ssh; run_ansible ;;
        *)        echo "Usage: $0 [full|ansible|destroy]"; exit 1 ;;
    esac
}

main "$@"
