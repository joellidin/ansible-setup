#!/usr/bin/env bash
# bootstrap.sh: pick a profile and roles, then run the Ansible playbook.
#
# Usage:
#   bootstrap.sh [install] [--profile NAME] [--yes] [--dry-run]
#   bootstrap.sh update [--profile NAME] [--dry-run]
#
# install (default)
#   Screen 1 picks a profile from profiles.conf, screen 2 toggles roles with the
#   profile's roles preselected, screen 3 confirms. --profile (or the env var
#   BOOTSTRAP_PROFILE) skips screen 1, --yes skips screens 2 and 3 and takes
#   the profile's default roles. The choice is saved to
#   ~/.config/bootstrap/profile and the playbook runs with --tags <roles>.
# update
#   git pull --ff-only, then the playbook with --tags update, skipping every
#   role that is not in the saved selection.
# --dry-run prints the git and ansible commands instead of running them.
#
# Normally started by docs/bootstrap (curl -fsSL https://get.lidin.xyz/bootstrap | sh)
# but it can be run directly from a checkout. Needs uv on PATH or in ~/.local/bin.
# The TUI uses gum: on Linux a pinned release is downloaded to ~/.cache/bootstrap
# and verified by sha256, on macOS it comes from Homebrew. gum is only fetched
# when a screen is actually shown, so "--profile X --yes" works without a TUI.
#
# Must keep working on macOS /bin/bash 3.2: no associative arrays, no mapfile,
# no ${var,,}, and no "${array[@]}" on possibly empty arrays.

set -euo pipefail

GUM_VERSION="2.0.2"
# sha256 of checksums.txt from https://github.com/charmbracelet/gum/releases/tag/v2.0.2
# It covers every per-arch tarball; bump both values together when upgrading gum.
GUM_CHECKSUMS_SHA256="297d032d04b71082c1d3c3614c8ffffce9b096a854e97fa363818e64e7652b7d"
ANSIBLE_SPEC="ansible-core>=2.22,<2.23"

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILES_FILE="$REPO_DIR/profiles.conf"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bootstrap"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bootstrap"
STATE_FILE="$CONFIG_DIR/profile"

CMD=install
PROFILE="${BOOTSTRAP_PROFILE:-}"
YES=0
DRY_RUN=0
OS=""
GUM_ARCH=""
GUM=""
CATALOGUE=""
SAVED_PROFILE=""
SAVED_ROLES=""
TMP_DIR=""

log() { printf '==> %s\n' "$*"; }
die() { printf 'bootstrap: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

cleanup() {
  if [ -n "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}

# Run a command, or print it when --dry-run is active.
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

quote_cmd() {
  printf '%q ' "$@" | sed 's/ $//'
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      install | update) CMD="$1" ;;
      --profile)
        [ $# -ge 2 ] || die "--profile needs a name"
        PROFILE="$2"
        shift
        ;;
      --profile=*) PROFILE="${1#--profile=}" ;;
      -y | --yes) YES=1 ;;
      --dry-run) DRY_RUN=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) die "unknown argument '$1' (see --help)" ;;
    esac
    shift
  done
}

detect_platform() {
  case "$(uname -s)" in
    Linux) OS=linux ;;
    Darwin) OS=darwin ;;
    *) die "unsupported operating system: $(uname -s)" ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) GUM_ARCH=x86_64 ;;
    aarch64 | arm64) GUM_ARCH=arm64 ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}

ensure_uvx() {
  export PATH="$HOME/.local/bin:$PATH"
  command -v uvx >/dev/null ||
    die "uvx not found; install uv first: https://docs.astral.sh/uv/getting-started/installation/"
}

# ---------------------------------------------------------------------------
# gum
# ---------------------------------------------------------------------------

sha256_of() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

verify_sha256() {
  local actual
  actual="$(sha256_of "$1")"
  [ "$actual" = "$2" ] ||
    die "checksum mismatch for $(basename "$1"): expected $2, got $actual"
}

ensure_gum() {
  [ -z "$GUM" ] || return 0
  if [ "$OS" = darwin ]; then
    if ! command -v gum >/dev/null; then
      command -v brew >/dev/null || die "gum not found; install Homebrew, then: brew install gum"
      brew install gum
    fi
    GUM="$(command -v gum)"
    return 0
  fi

  GUM="$CACHE_DIR/bin/gum"
  if [ -x "$GUM" ]; then
    case "$("$GUM" --version 2>/dev/null || true)" in
      "gum version v$GUM_VERSION "*) return 0 ;;
    esac
  fi

  local asset base expected
  asset="gum_${GUM_VERSION}_Linux_${GUM_ARCH}.tar.gz"
  base="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}"
  TMP_DIR="$(mktemp -d)"
  log "Downloading gum $GUM_VERSION"
  curl -fsSL "$base/checksums.txt" -o "$TMP_DIR/checksums.txt"
  curl -fsSL "$base/$asset" -o "$TMP_DIR/$asset"
  # The downloaded checksums.txt must match the hash pinned above, and the
  # tarball must match the entry in it. Anything else aborts.
  verify_sha256 "$TMP_DIR/checksums.txt" "$GUM_CHECKSUMS_SHA256"
  expected="$(awk -v f="$asset" '$2 == f { print $1 }' "$TMP_DIR/checksums.txt")"
  [ -n "$expected" ] || die "$asset is not listed in checksums.txt"
  verify_sha256 "$TMP_DIR/$asset" "$expected"
  tar -xzf "$TMP_DIR/$asset" -C "$TMP_DIR" "${asset%.tar.gz}/gum"
  mkdir -p "$CACHE_DIR/bin"
  mv "$TMP_DIR/${asset%.tar.gz}/gum" "$GUM"
  chmod 755 "$GUM"
  cleanup
  TMP_DIR=""
}

# ---------------------------------------------------------------------------
# profiles.conf
# ---------------------------------------------------------------------------

# Profiles available on this OS, one per line: name|description|roles
list_profiles() {
  awk -F'|' -v os="$OS" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^[ \t]*(#|$)/ { next }
    { for (i = 1; i <= NF; i++) $i = trim($i) }
    $1 == "roles" { next }
    index("," $2 ",", "," os ",") { print $1 "|" $3 "|" $4 }
  ' "$PROFILES_FILE"
}

# Role catalogue for this OS, space separated.
os_roles() {
  awk -F'|' -v os="$OS" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^[ \t]*(#|$)/ { next }
    trim($1) == "roles" && trim($2) == os { print trim($3); exit }
  ' "$PROFILES_FILE"
}

profile_exists() {
  list_profiles | awk -F'|' -v n="$1" '$1 == n { found = 1 } END { exit !found }'
}

profile_roles() {
  local roles
  roles="$(list_profiles | awk -F'|' -v n="$1" '$1 == n { print $3; exit }')"
  if [ "$roles" = ALL ]; then
    roles="$CATALOGUE"
  fi
  printf '%s\n' "$roles"
}

validate_roles() {
  local r
  for r in $1; do
    case " $CATALOGUE " in
      *" $r "*) ;;
      *) die "role '$r' is not in the $OS role list of profiles.conf (saved selection out of date? re-run install)" ;;
    esac
  done
}

join_comma() {
  printf '%s\n' "$1" | tr -s ' ' ','
}

# Roles in the catalogue that are not in $1, comma separated (for --skip-tags).
skip_list() {
  local r skip=""
  for r in $CATALOGUE; do
    case " $1 " in
      *" $r "*) ;;
      *) skip="$skip${skip:+,}$r" ;;
    esac
  done
  printf '%s\n' "$skip"
}

# ---------------------------------------------------------------------------
# saved selection
# ---------------------------------------------------------------------------

load_state() {
  [ -f "$STATE_FILE" ] || return 1
  SAVED_PROFILE="$(sed -n 's/^profile=//p' "$STATE_FILE")"
  SAVED_ROLES="$(sed -n 's/^roles=//p' "$STATE_FILE")"
  [ -n "$SAVED_PROFILE" ] && [ -n "$SAVED_ROLES" ]
}

save_state() {
  mkdir -p "$CONFIG_DIR"
  printf '# written by bootstrap.sh on %s, read by "bootstrap.sh update"\nprofile=%s\nroles=%s\n' \
    "$(date '+%Y-%m-%d %H:%M')" "$1" "$2" > "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# TUI screens
# ---------------------------------------------------------------------------

# Screen 1: pick a profile. $1 is the name to put the cursor on.
choose_profile() {
  local items first
  items="$(list_profiles | awk -F'|' '{ printf "%-12s %s|%s\n", $1, $2, $1 }')"
  [ -n "$items" ] || die "profiles.conf has no profile for $OS"
  first="$(printf '%s\n' "$items" | head -n 1 | sed 's/.*|//')"
  printf '%s\n' "$items" |
    "$GUM" choose --header "Profile" --label-delimiter='|' --selected="${1:-$first}"
}

# Screen 2: toggle roles. $1 is the space separated preselection.
choose_roles() {
  local count
  count="$(printf '%s\n' "$CATALOGUE" | wc -w | tr -d ' ')"
  printf '%s\n' "$CATALOGUE" | tr ' ' '\n' |
    "$GUM" choose --no-limit --height "$((count + 1))" \
      --header "Roles (x or tab toggles, ctrl+a toggles all, enter confirms)" \
      --selected="$(join_comma "$1")" |
    tr '\n' ' ' | sed 's/ *$//'
}

# Screen 3: summary and confirmation.
confirm_run() {
  "$GUM" style --border rounded --padding "0 1" --margin "0 0 1 0" \
    "Profile   $1" \
    "Roles     $2" \
    "" \
    "$3"
  "$GUM" confirm "Run the playbook now?"
}

# ---------------------------------------------------------------------------
# ansible
# ---------------------------------------------------------------------------

playbook_cmd() {
  if [ -n "${2:-}" ]; then
    quote_cmd uvx --from "$ANSIBLE_SPEC" ansible-playbook local.yml -K --tags "$1" --skip-tags "$2"
  else
    quote_cmd uvx --from "$ANSIBLE_SPEC" ansible-playbook local.yml -K --tags "$1"
  fi
}

# collections/ is gitignored and uvx ansible-core ships no collections, so
# install them from requirements.yml unless both required ones are present.
ensure_collections() {
  if [ -d collections/ansible_collections/community/general ] &&
    [ -d collections/ansible_collections/ansible/posix ]; then
    return 0
  fi
  log "Installing Ansible collections from requirements.yml into collections/"
  run uvx --from "$ANSIBLE_SPEC" ansible-galaxy collection install -r requirements.yml -p collections
}

run_playbook() {
  cd "$REPO_DIR"
  ensure_collections
  log "Running the playbook (Ansible asks for your sudo password as BECOME password)"
  if [ -n "${2:-}" ]; then
    run uvx --from "$ANSIBLE_SPEC" ansible-playbook local.yml -K --tags "$1" --skip-tags "$2"
  else
    run uvx --from "$ANSIBLE_SPEC" ansible-playbook local.yml -K --tags "$1"
  fi
}

# ---------------------------------------------------------------------------
# subcommands
# ---------------------------------------------------------------------------

cmd_install() {
  local profile roles preselect
  load_state || true

  if [ -n "$PROFILE" ]; then
    profile_exists "$PROFILE" ||
      die "unknown profile '$PROFILE' for $OS; available: $(list_profiles | cut -d'|' -f1 | tr '\n' ' ')"
    profile="$PROFILE"
  else
    ensure_gum
    profile="$(choose_profile "$SAVED_PROFILE")" || die "aborted"
  fi

  roles="$(profile_roles "$profile")"
  if [ "$YES" != 1 ]; then
    ensure_gum
    preselect="$roles"
    if [ "$profile" = "$SAVED_PROFILE" ]; then
      preselect="$SAVED_ROLES"
    fi
    roles="$(choose_roles "$preselect")" || die "aborted"
    [ -n "$roles" ] || die "no roles selected"
    confirm_run "$profile" "$roles" "$(playbook_cmd "$(join_comma "$roles")")" || die "aborted"
  fi
  validate_roles "$roles"

  save_state "$profile" "$roles"
  log "Profile '$profile', roles: $roles"
  run_playbook "$(join_comma "$roles")"

  log "Done. Installed roles: $roles"
  log "Selection saved to $STATE_FILE; run '$0 update' to update these roles later."
  log "Log out and back in (or reboot) so the new shell, group memberships and desktop session take effect."
}

cmd_update() {
  if [ -n "$PROFILE" ]; then
    profile_exists "$PROFILE" ||
      die "unknown profile '$PROFILE' for $OS; available: $(list_profiles | cut -d'|' -f1 | tr '\n' ' ')"
    SAVED_PROFILE="$PROFILE"
    SAVED_ROLES="$(profile_roles "$PROFILE")"
    save_state "$SAVED_PROFILE" "$SAVED_ROLES"
  else
    load_state || die "no saved selection in $STATE_FILE; run '$0 install' first"
  fi
  validate_roles "$SAVED_ROLES"

  log "Updating $REPO_DIR"
  run git -C "$REPO_DIR" pull --ff-only --quiet ||
    die "git pull failed (uncommitted changes, detached HEAD or diverged branch?)"
  log "Profile '$SAVED_PROFILE', roles: $SAVED_ROLES"
  run_playbook update "$(skip_list "$SAVED_ROLES")"
  log "Done. Updated roles: $SAVED_ROLES"
}

main() {
  parse_args "$@"
  detect_platform
  [ -f "$PROFILES_FILE" ] || die "$PROFILES_FILE not found"
  CATALOGUE="$(os_roles)"
  [ -n "$CATALOGUE" ] || die "profiles.conf has no 'roles|$OS|...' line"
  ensure_uvx
  trap cleanup EXIT
  case "$CMD" in
    install) cmd_install ;;
    update) cmd_update ;;
  esac
}

main "$@"
