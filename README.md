# homelab-infra

Infrastructure monorepo for a personal homelab. Currently runs Proxmox VE as a KVM/QEMU virtual machine on a Void Linux host — provisioned from zero to production with a single `make proxmox`.

The repo is structured to grow: Terraform for cloud resources, Kubernetes manifests, monitoring stack, and policy enforcement all have their place.

## Quick Start

```sh
git clone https://github.com/mggpie/homelab-infra.git
cd homelab-infra
echo "your-vault-password" > ansible/.vault_pass

# Edit secrets (root password, user password)
make vault-edit

# Full deploy: download Debian → install VM → install Proxmox
make proxmox
```

## What Happens

1. **Downloads** Debian 12 netinst ISO (cached in `.cache/`)
2. **Creates** a KVM VM via `virt-install` with:
   - 4 vCPUs (host-passthrough), 8GB RAM, 80GB virtio disk
   - Fixed MAC → static DHCP lease (192.168.122.10)
   - Nested virtualization enabled
3. **Installs Debian unattended** via preseed (SSH key injected, passwordless sudo)
4. **Runs Ansible** to install Proxmox VE:
   - Proxmox kernel + reboot
   - `proxmox-ve` metapackage
   - Bridge networking (`vmbr0`) — VMs get IPs from the same network
   - PAM user `me` with Administrator role
   - Subscription nag removed

After deploy: **https://192.168.122.10:8006** (login: `me@pam`)

## Architecture

```
┌─────────────────────────────────────────────┐
│  Void Linux host (KVM/QEMU + libvirt)       │
│                                             │
│  ┌───────────────────────────────────────┐  │
│  │  VM: proxmox (192.168.122.10)         │  │
│  │  Debian 12 + Proxmox VE 8             │  │
│  │  Bridge: vmbr0 ← enp1s0              │  │
│  │                                       │  │
│  │  ┌─────────┐  ┌─────────┐            │  │
│  │  │  VM 1   │  │  VM 2   │  ...       │  │
│  │  │ (vmbr0) │  │ (vmbr0) │            │  │
│  │  └─────────┘  └─────────┘            │  │
│  └───────────────────────────────────────┘  │
│                                             │
│  libvirt default network (192.168.122.0/24) │
└─────────────────────────────────────────────┘
```

## Commands

```sh
make help               # Show all available targets

make proxmox            # Full run: provision VM + install Proxmox
make proxmox-ansible    # Ansible only (VM already exists)
make proxmox-destroy    # Tear down VM completely

make vault-edit         # Edit encrypted secrets
make vault-view         # View encrypted secrets
make lint               # Run ansible-lint
make clean              # Remove cached files (ISO, temp preseed)
```

## Repository Structure

```
├── Makefile                         # Entry point — all commands
├── ansible/                         # Configuration management
│   ├── ansible.cfg
│   ├── playbook.yml
│   ├── secrets.yml                  # Vault-encrypted passwords
│   ├── inventory/hosts.yml
│   ├── files/preseed.cfg            # Debian unattended install
│   └── roles/proxmox/
│       ├── defaults/main.yml        # Default variables
│       ├── handlers/main.yml        # Service handlers
│       ├── tasks/
│       │   ├── hostname.yml         # Hostname + /etc/hosts
│       │   ├── repositories.yml     # APT repos + PVE GPG key
│       │   ├── install.yml          # Kernel swap + PVE packages
│       │   ├── network.yml          # Bridge (vmbr0) setup
│       │   ├── user.yml             # PVE user + ACL
│       │   └── post-install.yml     # Cleanup + hardening
│       └── templates/
│           ├── hosts.j2
│           └── interfaces.j2
├── terraform/                       # Infrastructure provisioning (planned)
├── kubernetes/                      # K8s manifests (planned)
│   ├── manifests/
│   ├── helm/
│   └── argocd/
├── monitoring/                      # Observability stack (planned)
│   ├── prometheus/
│   ├── grafana/
│   └── loki/
├── policies/                        # OPA / Kyverno (planned)
├── scripts/                         # Provisioning scripts
│   └── proxmox-vm.sh
└── docs/
```

## Secrets

```sh
make vault-edit       # Edit passwords
make vault-view       # View passwords
make vault-encrypt    # Encrypt plaintext secrets.yml
```

Required secrets: `vault_root_password`, `vault_user_password`.

## License

[MIT](LICENSE)

## Related

- [dotfiles](https://github.com/mggpie/dotfiles) — Ansible-managed Void Linux desktop
- [void-installer](https://github.com/mggpie/void-installer) — Void Linux installer with LUKS encryption
