# Ansible Development Environment Bootstrap

Ansible playbook for bootstrapping a complete development environment on Ubuntu.

## Features

- **22 modular roles** for installing and configuring development tools
- **Update mechanism** with `--tags update` to keep tools current
- **XDG Base Directory** compliant paths
- **Molecule testing** with Docker for CI validation

## Quick Start

```bash
# Install Ansible
sudo apt update && sudo apt install -y ansible

# Clone this repository
git clone https://github.com/joellidin/ansible-setup.git
cd ansible-setup

# Run the playbook
ansible-playbook local.yml --ask-become-pass
```

## Requirements

- Ubuntu 22.04 (Jammy) or 24.04 (Noble)
- Ansible 2.14+
- sudo access

## Configuration

All configuration is centralized in `group_vars/all.yml`:

```yaml
# Tool versions
go_version: "1.23.4"
kubectl_version: "v1.31"
node_version: "20"

# Application choices
browser_choice: "zen"  # Options: brave, zen, none

# Update behavior
force_rebuild: false
```

## Usage

### Full Installation

```bash
ansible-playbook local.yml --ask-become-pass
```

### Install Specific Roles

```bash
# Single role
ansible-playbook local.yml --tags neovim

# Multiple roles
ansible-playbook local.yml --tags "rust,go,python"
```

### Update Installed Tools

```bash
# Update all tools
ansible-playbook local.yml --tags update

# Update specific tool
ansible-playbook local.yml --tags neovim-update
```

### Dry Run

```bash
ansible-playbook local.yml --check
```

## Roles

| Role | Description | Update Tag |
|------|-------------|------------|
| `browser` | Zen or Brave browser | `zen-update` |
| `claude_code` | Claude Code CLI | `claude-code-update` |
| `core` | Build dependencies, fonts, productivity tools | - |
| `docker` | Docker Engine and compose | - |
| `dotfiles` | Personal dotfiles via stow | - |
| `gh` | GitHub CLI with config | - |
| `ghostty` | Ghostty terminal emulator | `ghostty-update` |
| `go` | Go programming language | `go-update` |
| `gopass` | Password manager | `gopass-update` |
| `gpg` | GPG and YubiKey support | - |
| `herdr` | Herdr agent runtime | `herdr-update` |
| `i3blocks` | i3blocks status bar | `i3blocks-update` |
| `kubectl` | Kubernetes CLI | - |
| `neovim` | Neovim from source | `neovim-update` |
| `node` | Node.js via n version manager | `node-update` |
| `python` | Python via uv | `python-update` |
| `regolith` | Regolith desktop environment | - |
| `rust` | Rust via rustup | `rust-update` |
| `tmux` | Tmux from source | `tmux-update` |
| `vault` | HashiCorp Vault | - |
| `zig` | Zig programming language | `zig-update` |
| `zsh` | Zsh with Oh My Zsh | - |

## Role Structure

All roles follow a consistent pattern:

```
roles/<name>/
├── defaults/main.yml   # Configurable variables (versions, paths)
├── tasks/main.yml      # Installation and configuration tasks
└── meta/main.yml       # Role metadata and dependencies
```

- **Install tags**: `<role>` (e.g., `--tags neovim`)
- **Update tags**: `<role>-update` (e.g., `--tags neovim-update`)
- **Global update**: `--tags update` runs all update tasks

## Directory Structure

```
.
├── local.yml              # Main playbook
├── group_vars/
│   └── all.yml            # Centralized configuration
├── roles/
│   ├── browser/           # Browser installation
│   ├── claude_code/       # Claude Code CLI
│   ├── core/              # Build deps, fonts, tools
│   ├── docker/            # Docker Engine
│   ├── dotfiles/          # Dotfiles management
│   ├── gh/                # GitHub CLI
│   ├── ghostty/           # Ghostty terminal
│   ├── go/                # Go language
│   ├── gopass/            # Password manager
│   ├── gpg/               # GPG/YubiKey
│   ├── herdr/             # Herdr agent runtime
│   ├── i3blocks/          # Status bar
│   ├── kubectl/           # Kubernetes CLI
│   ├── neovim/            # Neovim editor
│   ├── node/              # Node.js
│   ├── python/            # Python/uv
│   ├── regolith/          # Desktop environment
│   ├── rust/              # Rust language
│   ├── tmux/              # Terminal multiplexer
│   ├── vault/             # HashiCorp Vault
│   ├── zig/               # Zig language
│   └── zsh/               # Shell configuration
├── molecule/
│   └── default/           # Molecule test scenario
└── tasks/                 # Additional task files
```

## Testing

Run Molecule tests with Docker:

```bash
# Full test (create, converge, idempotence, verify, destroy)
uvx --with ansible --with 'molecule-plugins[docker]' --with docker molecule test

# Just converge (useful during development)
uvx --with ansible --with 'molecule-plugins[docker]' --with docker molecule converge
```

## Linting

Run ansible-lint to check for issues:

```bash
uvx ansible-lint
```

## Customization

### Adding a New Tool Version

Edit `group_vars/all.yml`:

```yaml
go_version: "1.24.0"  # Update version
```

### Changing Browser

```yaml
browser_choice: "brave"  # or "zen" or "none"
```

### Force Rebuild

```bash
ansible-playbook local.yml --tags neovim -e "force_rebuild=true"
```

## License

MIT
