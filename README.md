# ansible-setup

One command sets up a new machine the way I like it: an i3 workstation on
Ubuntu, a headless server, or (soon) a Mac. Ansible does the system work,
[mise](https://mise.jdx.dev) pins the GitHub-release tools, and the dotfiles
come from [joellidin/dotfiles](https://github.com/joellidin/dotfiles).

## Quick start

```bash
curl -fsSL https://get.lidin.xyz/bootstrap | sh
```

The bootstrap script installs git, curl and uv, clones this repository to
`~/ansible-setup`, lets you pick a profile and the roles you want in a small
TUI, and runs the playbook. Non-interactive variants:

```bash
curl -fsSL https://get.lidin.xyz/bootstrap | sh -s -- --profile dev --yes
BOOTSTRAP_REF=v1.0.0 curl -fsSL https://get.lidin.xyz/bootstrap | sh
```

Profiles live in `profiles.conf`. Re-run `~/ansible-setup/bootstrap.sh update`
at any time to pull the repository and update everything you installed.

### Manual run

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
git clone https://github.com/joellidin/ansible-setup.git ~/ansible-setup
cd ~/ansible-setup
uvx --from 'ansible-core>=2.22,<2.23' ansible-galaxy collection install -r requirements.yml -p collections
uvx --from 'ansible-core>=2.22,<2.23' ansible-playbook local.yml --ask-become-pass
```

Always run Ansible through uvx. Ubuntu 26.04 uses sudo-rs, and the ansible-core
Ubuntu packages (2.20) cannot read its password prompt, so every privileged task
times out. ansible-core 2.22 handles it.

## Requirements

- Ubuntu 24.04 or 26.04 (the reference machine runs 26.04); macOS support is
  planned, see the plan in the repository history
- A user with sudo
- For GitHub-authenticated roles (private password store): `gh auth login`
  before running, or let `bootstrap.sh` do it

## How it fits together

| Layer | Tool | What it covers |
|-------|------|----------------|
| System | Ansible roles | apt packages and deb822 repositories, Docker, source builds (neovim, tmux, picom, i3lock-color), GPG and YubiKey, zsh, dotfiles checkout |
| Tool versions | mise | go, node, zig, delta, gh, kubectl, vault, gopass from GitHub releases, verified against release checksums, pinned in `mise.lock` |
| Dotfiles | bare git repo | `~/.config` including `~/.config/mise/config.toml` and `mise.lock` |
| Front door | `docs/bootstrap` + `bootstrap.sh` | the curl one-liner, the TUI, the update command |

Roles never pin tool versions. Source builds track their upstream branch, and
`mise upgrade` (run by `--tags update`) moves the release tools forward and
rewrites `mise.lock`, which you then commit in the dotfiles.

## Roles

| Role | Description | Runs on `--tags update` |
|------|-------------|--------------------------|
| `browser` | Zen or Brave browser | yes (Zen) |
| `claude_code` | Claude Code CLI via its native installer | yes |
| `core` | Build dependencies and fonts | no |
| `desktop` | i3, rofi and the X11 desktop tool set, git from the git-core PPA | no |
| `docker` | Docker Engine, Buildx and Compose from Docker's repository | no |
| `dotfiles` | Dotfiles bare repository checkout | no |
| `ghostty` | Ghostty terminal from the mkasberg deb releases | yes |
| `gopass` | zsh completion and password store for the mise-installed gopass | no |
| `gpg` | Public key import, trust, YubiKey packages and check | no |
| `herdr` | herdr, installed once; it updates itself with `herdr update --handoff` | no |
| `i3blocks` | i3blocks status bar from source | no |
| `i3lock_color` | i3lock-color from source plus betterlockscreen and xss-lock | yes |
| `mise` | mise itself and every tool in `~/.config/mise/config.toml` | yes |
| `neovim` | Neovim master from source | yes |
| `picom` | picom compositor from source | yes |
| `python` | Python via uv | yes |
| `rust` | Rust via rustup | yes |
| `tmux` | tmux master from source | yes |
| `zsh` | zsh, Oh My Zsh, plugins and Starship | no |

### Tags

- `--tags <role>` runs one role, for example `--tags neovim`.
- `--tags update` runs only the tasks that bring installed tools forward:
  `mise upgrade`, source rebuilds when upstream moved, Ghostty and Zen
  releases, rustup and uv self-updates.
- `--tags <role>-update` limits that to one role.
- `--check` works; version checks are marked check-mode safe.

### Configuration

Shared paths and a few choices live in `group_vars/all.yml`:

```yaml
browser_choice: "zen"   # brave, zen or none
force_rebuild: false    # rebuild source packages even when up to date
```

The tool list for mise is in the dotfiles at `~/.config/mise/config.toml`.
`roles/mise/files/config.toml` is only installed when that file is missing.

## Repository layout

```
.
├── docs/bootstrap          # POSIX stub served at get.lidin.xyz/bootstrap
├── bootstrap.sh            # TUI, profiles and the ansible invocation
├── profiles.conf           # profile -> roles mapping used by the TUI
├── local.yml               # the playbook
├── inventory/localhost.yml # the only target
├── group_vars/all.yml      # shared variables
├── requirements.yml        # collections, installed into ./collections
├── roles/                  # one directory per role, defaults/tasks/meta
└── molecule/default/       # container test on ubuntu:resolute
```

## Development

```bash
uvx --with 'ansible-core>=2.22,<2.23' ansible-lint --profile production
uvx --from 'ansible-core>=2.22,<2.23' ansible-playbook local.yml --syntax-check
uvx --with ansible --with 'molecule-plugins[docker]' --with docker molecule test
uvx pre-commit install   # gitleaks secret scan before every commit
```

CI runs gitleaks, yamllint, ansible-lint, the syntax check and shellcheck on
every push and pull request.

## License

MIT
