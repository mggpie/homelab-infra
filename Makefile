.PHONY: help proxmox proxmox-ansible proxmox-destroy lint clean

SHELL := /bin/bash

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ─── Proxmox VE ─────────────────────────────────────────────

proxmox: ## Provision VM + install Proxmox VE (full run)
	@scripts/proxmox-vm.sh full

proxmox-ansible: ## Run Ansible only (VM already exists)
	@scripts/proxmox-vm.sh ansible

proxmox-destroy: ## Tear down Proxmox VM completely
	@scripts/proxmox-vm.sh destroy

# ─── Monitoring (future) ────────────────────────────────────

# monitoring:
# 	@echo "Not implemented yet"

# ─── Kubernetes (future) ────────────────────────────────────

# k8s-apply:
# 	@echo "Not implemented yet"

# ─── Utilities ──────────────────────────────────────────────

lint: ## Run ansible-lint on all playbooks
	@cd ansible && ansible-lint playbook.yml

clean: ## Remove cached files (ISO, temp preseed)
	@rm -rf .cache
	@echo "Cache cleaned"

vault-edit: ## Edit encrypted secrets
	@cd ansible && ansible-vault edit secrets.yml

vault-encrypt: ## Encrypt secrets file
	@cd ansible && ansible-vault encrypt secrets.yml

vault-view: ## View encrypted secrets
	@cd ansible && ansible-vault view secrets.yml
