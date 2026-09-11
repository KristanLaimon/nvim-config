#!/usr/bin/env bash
# ==============================================================================
# omarchy-backup.sh - Omarchy Configuration Exporter & Importer
# Strictly compatible with Omarchy systems only.
# ==============================================================================
set -euo pipefail

SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="omarchy-backup.sh"

# Colors for terminal output
BOLD=$'\e[1m'
RED=$'\e[0;31m'
GREEN=$'\e[0;32m'
YELLOW=$'\e[0;33m'
BLUE=$'\e[0;34m'
MAGENTA=$'\e[0;35m'
CYAN=$'\e[0;36m'
GRAY=$'\e[0;90m'
RESET=$'\e[0m'

msg() {
  echo -e "${BOLD}${BLUE}==>${RESET} ${BOLD}$1${RESET}"
}

info() {
  echo -e "  ${CYAN}•${RESET} $1"
}

success() {
  echo -e "${BOLD}${GREEN}✔${RESET} $1"
}

warn() {
  echo -e "${BOLD}${YELLOW}▲ [WARNING]${RESET} $1"
}

error() {
  echo -e "${BOLD}${RED}✖ [ERROR]${RESET} $1" >&2
}

die() {
  error "$1"
  exit 1
}

# ==============================================================================
# 1. System Compatibility Check
# ==============================================================================
check_omarchy() {
  local is_omarchy=0

  # Check /etc/os-release
  if [[ -f /etc/os-release ]]; then
    if grep -Eiq '^(ID|ID_LIKE|NAME)=.*omarchy' /etc/os-release; then
      is_omarchy=1
    fi
  fi

  # Check omarchy CLI tool
  if command -v omarchy >/dev/null 2>&1; then
    is_omarchy=1
  fi

  # Check /usr/share/omarchy system directory
  if [[ -d /usr/share/omarchy ]]; then
    is_omarchy=1
  fi

  if [[ $is_omarchy -eq 0 ]]; then
    echo -e "\n${BOLD}${RED}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${RED}║                 INCOMPATIBLE SYSTEM DETECTED                         ║${RESET}"
    echo -e "${BOLD}${RED}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
    echo -e "${RED}This script is designed and verified ONLY for Omarchy Linux systems.${RESET}"
    echo -e "${RED}Omarchy core components were not detected on this machine.${RESET}"
    echo -e "${RED}Aborting to protect system integrity and prevent config corruption.${RESET}\n"
    exit 1
  fi
}

# ==============================================================================
# 2. Helper Functions
# ==============================================================================
copy_item_clean() {
  local src="$1"
  local dest="$2"

  if [[ ! -e "$src" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "$dest")"

  if [[ -d "$src" ]]; then
    mkdir -p "$dest"
    if command -v rsync >/dev/null 2>&1; then
      rsync -a \
        --exclude='*.bak*' \
        --exclude='*~' \
        --exclude='*.tmp' \
        --exclude='*.swp' \
        --exclude='*.log' \
        --exclude='.git' \
        --exclude='cache' \
        "$src/" "$dest/"
    else
      cp -a "$src"/* "$dest/" 2>/dev/null || true
    fi
  else
    cp -a "$src" "$dest"
  fi
}

get_omarchy_version() {
  if [[ -f /usr/share/omarchy/version ]]; then
    cat /usr/share/omarchy/version
  elif command -v omarchy >/dev/null 2>&1; then
    omarchy version 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

get_active_theme() {
  local theme_file="$HOME/.local/state/omarchy/current/theme.name"
  if [[ -f "$theme_file" ]]; then
    tr -d '\n' < "$theme_file"
  elif command -v omarchy >/dev/null 2>&1; then
    omarchy theme current 2>/dev/null | tr -d '\n' || echo ""
  else
    echo ""
  fi
}

get_active_background() {
  local bg_link="$HOME/.local/state/omarchy/current/background"
  if [[ -L "$bg_link" ]]; then
    readlink -f "$bg_link" || echo ""
  else
    echo ""
  fi
}

# ==============================================================================
# 3. Export Subcommand
# ==============================================================================
do_export() {
  local output_file="${1:-}"
  local this_script
  this_script="$(readlink -f "${BASH_SOURCE[0]}")"

  # Default output filename if not provided
  if [[ -z "$output_file" ]]; then
    output_file="$HOME/omarchy-config-backup.zip"
  fi

  # Ensure absolute path
  if [[ "$output_file" != /* ]]; then
    output_file="$(pwd)/$output_file"
  fi

  # Dependency check
  command -v zip >/dev/null 2>&1 || die "'zip' command is required for export. Please install it with 'sudo pacman -S zip'."

  echo -e "\n${BOLD}${MAGENTA}┌─────────────────────────────────────────────────────────────┐${RESET}"
  echo -e "${BOLD}${MAGENTA}│           OMARCHY CONFIGURATION EXPORT UTILITY              │${RESET}"
  echo -e "${BOLD}${MAGENTA}└─────────────────────────────────────────────────────────────┘${RESET}\n"

  msg "Inspecting Omarchy configuration and assets..."

  local active_theme active_bg om_version
  active_theme="$(get_active_theme)"
  active_bg="$(get_active_background)"
  om_version="$(get_omarchy_version)"

  info "Detected Omarchy version: ${BOLD}${om_version}${RESET}"
  info "Detected Active theme:    ${BOLD}${active_theme:-None}${RESET}"
  if [[ -n "$active_bg" ]]; then
    info "Detected Active wallpaper:${CYAN} ${active_bg}${RESET}"
  fi

  # Create temporary staging directory
  local staging_dir
  staging_dir="$(mktemp -d -t omarchy-export-XXXXXX)"
  trap 'rm -rf "${staging_dir:-}"' EXIT

  local payload_dir="$staging_dir/payload"
  mkdir -p "$payload_dir/config" "$payload_dir/state" "$payload_dir/local_share"

  msg "Packaging configurations..."

  # 1. Omarchy core directory (~/.config/omarchy)
  if [[ -d "$HOME/.config/omarchy" ]]; then
    info "Exporting Omarchy core (~/.config/omarchy):"
    info "  - Quickshell plugins (~/.config/omarchy/plugins)"
    info "  - User themes & overrides (~/.config/omarchy/themes)"
    info "  - Theme wallpapers (~/.config/omarchy/backgrounds)"
    info "  - Bar layout & idle rules (~/.config/omarchy/shell.json, shell.toml)"
    info "  - Extensions, menu & hooks (~/.config/omarchy/extensions, ~/.config/omarchy/hooks)"
    info "  - Custom templates & branding (~/.config/omarchy/themed, ~/.config/omarchy/branding)"
    copy_item_clean "$HOME/.config/omarchy" "$payload_dir/config/omarchy"
  fi

  # 2. Hyprland configuration (~/.config/hypr)
  if [[ -d "$HOME/.config/hypr" ]]; then
    info "Exporting Hyprland configuration (~/.config/hypr):"
    info "  - hyprland.lua, bindings.lua, looknfeel.lua, autostart.lua"
    info "  - monitors.lua, input.lua, hyprsunset.conf, xdph.conf"
    copy_item_clean "$HOME/.config/hypr" "$payload_dir/config/hypr"
  fi

  # 3. Terminal configurations
  local terminals=(alacritty foot kitty ghostty)
  for term in "${terminals[@]}"; do
    if [[ -d "$HOME/.config/$term" ]]; then
      info "Exporting terminal configuration: ~/.config/$term"
      copy_item_clean "$HOME/.config/$term" "$payload_dir/config/$term"
    fi
  done

  # 4. CLI, prompt, and system styling tools
  local cli_tools=(starship.toml fastfetch fontconfig btop lazygit tmux imv chromium-flags.conf hyprland-preview-share-picker gtk-3.0 gtk-4.0)
  for item in "${cli_tools[@]}"; do
    if [[ -e "$HOME/.config/$item" ]]; then
      info "Exporting CLI/styling configuration: ~/.config/$item"
      copy_item_clean "$HOME/.config/$item" "$payload_dir/config/$item"
    fi
  done

  # 5. Local state (active theme, workspace layouts, toggles)
  if [[ -d "$HOME/.local/state/omarchy" ]]; then
    info "Exporting Omarchy state (~/.local/state/omarchy):"
    info "  - Active theme marker & workspace layouts & config toggles"
    mkdir -p "$payload_dir/state/omarchy"
    if [[ -d "$HOME/.local/state/omarchy/current" ]]; then
      mkdir -p "$payload_dir/state/omarchy/current"
      if [[ -f "$HOME/.local/state/omarchy/current/theme.name" ]]; then
        cp -a "$HOME/.local/state/omarchy/current/theme.name" "$payload_dir/state/omarchy/current/"
      fi
    fi
    copy_item_clean "$HOME/.local/state/omarchy/workspace-layouts" "$payload_dir/state/omarchy/workspace-layouts"
    copy_item_clean "$HOME/.local/state/omarchy/toggles" "$payload_dir/state/omarchy/toggles"
  fi

  # 6. Custom user fonts (~/.local/share/fonts) if any
  if [[ -d "$HOME/.local/share/fonts" ]] && [[ -n "$(ls -A "$HOME/.local/share/fonts" 2>/dev/null)" ]]; then
    info "Exporting custom user fonts: ~/.local/share/fonts"
    copy_item_clean "$HOME/.local/share/fonts" "$payload_dir/local_share/fonts"
  fi

  # 7. Custom user icons (~/.local/share/icons) if any
  if [[ -d "$HOME/.local/share/icons" ]] && [[ -n "$(ls -A "$HOME/.local/share/icons" 2>/dev/null)" ]]; then
    info "Exporting custom user icons: ~/.local/share/icons"
    copy_item_clean "$HOME/.local/share/icons" "$payload_dir/local_share/icons"
  fi

  # 8. Create metadata manifest
  cat > "$payload_dir/manifest.env" <<EOF
BACKUP_SPEC_VERSION="1.0"
EXPORT_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SOURCE_USER="$USER"
SOURCE_HOSTNAME="$(hostname 2>/dev/null || echo "omarchy")"
OMARCHY_VERSION="$om_version"
ACTIVE_THEME="$active_theme"
ACTIVE_BACKGROUND="$active_bg"
EOF

  # 9. Bundle a copy of this script inside the payload for convenience
  if [[ -f "$this_script" ]]; then
    cp "$this_script" "$payload_dir/$SCRIPT_NAME"
    chmod +x "$payload_dir/$SCRIPT_NAME"
  fi

  msg "Creating compressed archive..."
  mkdir -p "$(dirname "$output_file")"
  rm -f "$output_file"

  (
    cd "$payload_dir"
    zip -r -q "$output_file" .
  )

  local zip_size
  zip_size="$(du -h "$output_file" | cut -f1)"

  echo ""
  success "Export completed successfully!"
  echo -e "  ${BOLD}Archive:${RESET}   ${GREEN}$output_file${RESET}"
  echo -e "  ${BOLD}Size:${RESET}      ${CYAN}$zip_size${RESET}"
  echo -e "  ${BOLD}Script:${RESET}    ${YELLOW}$this_script${RESET}"
  echo ""
  echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${BLUE}║                    NEXT STEPS TO MIGRATE                             ║${RESET}"
  echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
  echo -e "1. Transfer both the script and zip to your new Omarchy machine:"
  echo -e "   ${BOLD}scp $output_file $this_script <username>@<new-computer>:~/${RESET}"
  echo -e "   ${GRAY}(Or copy both to a USB drive and place them in your home directory)${RESET}"
  echo ""
  echo -e "2. On your new Omarchy computer, run:"
  echo -e "   ${BOLD}bash ~/$SCRIPT_NAME import ~/${output_file##*/}${RESET}"
  echo ""
  echo -e "   ${CYAN}Note:${RESET} The zip file also contains a copy of this script inside it."
  echo ""

  rm -rf "${staging_dir:-}"
  trap - EXIT
}

# ==============================================================================
# 4. Import Subcommand
# ==============================================================================
do_import() {
  local input_file="${1:-}"
  local this_dir
  this_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

  # Dependency check
  command -v unzip >/dev/null 2>&1 || die "'unzip' command is required for import. Please install it with 'sudo pacman -S unzip'."

  # Auto-discovery if no file specified
  if [[ -z "$input_file" ]]; then
    local candidates=(
      "$(pwd)/omarchy-config-backup.zip"
      "$this_dir/omarchy-config-backup.zip"
      "$HOME/omarchy-config-backup.zip"
    )
    for c in "${candidates[@]}"; do
      if [[ -f "$c" ]]; then
        input_file="$c"
        break
      fi
    done

    if [[ -z "$input_file" ]]; then
      # Check for any omarchy*.zip in current directory
      local zips=()
      while IFS= read -r -d $'\0' file; do
        zips+=("$file")
      done < <(find . -maxdepth 1 -name "omarchy*.zip" -print0 2>/dev/null)

      if [[ ${#zips[@]} -eq 1 && -f "${zips[0]}" ]]; then
        input_file="$(readlink -f "${zips[0]}")"
      fi
    fi
  fi

  if [[ -z "$input_file" || ! -f "$input_file" ]]; then
    echo -e "${RED}Error: Backup zip file not found.${RESET}"
    echo -e "Usage: ${BOLD}$SCRIPT_NAME import <path/to/backup.zip>${RESET}"
    exit 1
  fi

  # Resolve absolute path
  input_file="$(readlink -f "$input_file")"

  echo -e "\n${BOLD}${MAGENTA}┌─────────────────────────────────────────────────────────────┐${RESET}"
  echo -e "${BOLD}${MAGENTA}│           OMARCHY CONFIGURATION IMPORT UTILITY              │${RESET}"
  echo -e "${BOLD}${MAGENTA}└─────────────────────────────────────────────────────────────┘${RESET}\n"

  msg "Inspecting backup archive: ${CYAN}$input_file${RESET}..."

  # Validate zip integrity
  if ! unzip -t -q "$input_file" >/dev/null 2>&1; then
    die "Archive is corrupt or not a valid zip file."
  fi

  # Create temporary extraction directory
  local staging_dir
  staging_dir="$(mktemp -d -t omarchy-import-XXXXXX)"
  trap 'rm -rf "${staging_dir:-}"' EXIT

  unzip -q "$input_file" -d "$staging_dir"

  # Validate backup manifest
  if [[ ! -f "$staging_dir/manifest.env" ]]; then
    die "The specified archive does not appear to be an Omarchy backup (missing manifest.env)."
  fi

  # Source metadata
  local EXPORT_TIMESTAMP="" SOURCE_USER="" SOURCE_HOSTNAME="" OMARCHY_VERSION="" ACTIVE_THEME="" ACTIVE_BACKGROUND=""
  # shellcheck source=/dev/null
  source "$staging_dir/manifest.env"

  info "Archive details:"
  info "  - Exported at:     ${BOLD}${EXPORT_TIMESTAMP:-Unknown}${RESET}"
  info "  - Origin host:     ${BOLD}${SOURCE_USER:-user}@${SOURCE_HOSTNAME:-omarchy}${RESET}"
  info "  - Omarchy version: ${BOLD}${OMARCHY_VERSION:-Unknown}${RESET}"
  info "  - Theme to restore:${BOLD} ${ACTIVE_THEME:-None}${RESET}"

  # ----------------------------------------------------------------------------
  # Safety backup of existing configurations on target system
  # ----------------------------------------------------------------------------
  msg "Creating safety backup of current configs on this machine..."
  local pre_backup_tar="$HOME/.omarchy_pre_import_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
  local items_to_prebackup=()
  for dir in "$HOME/.config/omarchy" "$HOME/.config/hypr" "$HOME/.config/alacritty" "$HOME/.config/foot" "$HOME/.config/kitty" "$HOME/.config/ghostty" "$HOME/.config/starship.toml" "$HOME/.config/fastfetch"; do
    if [[ -e "$dir" ]]; then
      items_to_prebackup+=("$dir")
    fi
  done

  if [[ ${#items_to_prebackup[@]} -gt 0 ]]; then
    tar -czf "$pre_backup_tar" "${items_to_prebackup[@]}" 2>/dev/null || true
    info "Pre-import backup saved at: ${YELLOW}$pre_backup_tar${RESET}"
  fi

  # ----------------------------------------------------------------------------
  # Restoring configurations
  # ----------------------------------------------------------------------------
  msg "Restoring configurations..."

  # Special handling for monitors.lua: preserve existing monitor setup if different hardware
  if [[ -f "$HOME/.config/hypr/monitors.lua" && -f "$staging_dir/config/hypr/monitors.lua" ]]; then
    cp -a "$HOME/.config/hypr/monitors.lua" "$HOME/.config/hypr/monitors.lua.target-orig"
    info "Saved current machine's display config as: ~/.config/hypr/monitors.lua.target-orig"
  fi

  # Restore ~/.config items
  if [[ -d "$staging_dir/config" ]]; then
    for item in "$staging_dir/config"/*; do
      [[ -e "$item" ]] || continue
      local base
      base="$(basename "$item")"
      info "Restoring ~/.config/$base"
      mkdir -p "$HOME/.config"
      copy_item_clean "$item" "$HOME/.config/$base"
    done
  fi

  # Restore ~/.local/state items
  if [[ -d "$staging_dir/state" ]]; then
    for item in "$staging_dir/state"/*; do
      [[ -e "$item" ]] || continue
      local base
      base="$(basename "$item")"
      info "Restoring ~/.local/state/$base"
      mkdir -p "$HOME/.local/state"
      copy_item_clean "$item" "$HOME/.local/state/$base"
    done
  fi

  # Restore ~/.local/share items (fonts, icons)
  if [[ -d "$staging_dir/local_share/fonts" ]]; then
    info "Restoring fonts to ~/.local/share/fonts"
    mkdir -p "$HOME/.local/share/fonts"
    copy_item_clean "$staging_dir/local_share/fonts" "$HOME/.local/share/fonts"
    if command -v fc-cache >/dev/null 2>&1; then
      info "Updating font cache (fc-cache)..."
      fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true
    fi
  fi

  if [[ -d "$staging_dir/local_share/icons" ]]; then
    info "Restoring icons to ~/.local/share/icons"
    mkdir -p "$HOME/.local/share/icons"
    copy_item_clean "$staging_dir/local_share/icons" "$HOME/.local/share/icons"
  fi

  # Fix permissions on scripts and hooks
  msg "Setting executable permissions for plugins and hooks..."
  if [[ -d "$HOME/.config/omarchy/plugins" ]]; then
    find "$HOME/.config/omarchy/plugins" -type f -path '*/bin/*' -exec chmod +x {} + 2>/dev/null || true
  fi
  if [[ -d "$HOME/.config/omarchy/hooks" ]]; then
    find "$HOME/.config/omarchy/hooks" -type f \( -name '*.hook' -o -name '*.sh' \) -exec chmod +x {} + 2>/dev/null || true
  fi

  # ----------------------------------------------------------------------------
  # Theme and Service Reloading
  # ----------------------------------------------------------------------------
  msg "Applying theme and refreshing Omarchy services..."

  if [[ -n "$ACTIVE_THEME" ]] && command -v omarchy >/dev/null 2>&1; then
    info "Applying active theme: ${BOLD}$ACTIVE_THEME${RESET}..."
    omarchy theme set "$ACTIVE_THEME" || warn "Theme '$ACTIVE_THEME' set returned non-zero code. Configuration was still placed."
  fi

  # Reload Hyprland if running
  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v hyprctl >/dev/null 2>&1; then
    info "Reloading Hyprland configuration (hyprctl reload)..."
    hyprctl reload >/dev/null 2>&1 || true
  fi

  # Restart Omarchy Quickshell
  if command -v omarchy >/dev/null 2>&1; then
    info "Restarting Omarchy shell (omarchy restart shell)..."
    omarchy restart shell >/dev/null 2>&1 || true
    info "Restarting terminals (omarchy restart terminal)..."
    omarchy restart terminal >/dev/null 2>&1 || true
  fi

  echo ""
  success "Import completed successfully!"
  echo -e "  All Omarchy themes, Quickshell plugins, and Hyprland ricing configurations are in place."
  if [[ -f "$HOME/.config/hypr/monitors.lua.target-orig" ]]; then
    warn "Notice: If your monitors/displays do not match the old computer's ports, check:"
    echo -e "          ${BOLD}~/.config/hypr/monitors.lua${RESET}"
    echo -e "          (Your new computer's original config was saved as ${BOLD}monitors.lua.target-orig${RESET})"
  fi
  echo -e "\n  Safety backup of previous setup: ${CYAN}$pre_backup_tar${RESET}\n"

  rm -rf "${staging_dir:-}"
  trap - EXIT
}

# ==============================================================================
# 5. Usage / Help
# ==============================================================================
show_help() {
  cat <<EOF
${BOLD}Omarchy Configuration Transfer Tool (v${SCRIPT_VERSION})${RESET}
Compatible strictly with Omarchy systems only.

${BOLD}USAGE:${RESET}
    $SCRIPT_NAME <command> [arguments]

${BOLD}COMMANDS:${RESET}
    ${BOLD}export${RESET} [destination.zip]
        Packages all Omarchy ricing, themes, custom Quickshell plugins, Hyprland
        configurations, terminal profiles, and system styling into a zip file.
        Also packages this script inside the zip.
        Default destination: ${CYAN}\$HOME/omarchy-config-backup.zip${RESET}

    ${BOLD}import${RESET} [source.zip]
        Restores all Omarchy user configurations on the new computer, fixes
        executable permissions, restores the active theme, and reloads the
        Hyprland compositor and Omarchy shell.
        Default source: automatically looks for ${CYAN}omarchy-config-backup.zip${RESET}

    ${BOLD}-h, --help${RESET}
        Show this help message and exit.

${BOLD}INCLUDED CONFIGURATIONS:${RESET}
    • Omarchy Core:      ~/.config/omarchy/ (themes, plugins, backgrounds, shell.json,
                         shell.toml, hooks, extensions, themed templates)
    • Hyprland:          ~/.config/hypr/ (hyprland.lua, bindings.lua, looknfeel.lua,
                         autostart.lua, monitors.lua, input.lua, hyprsunset.conf)
    • Terminals:         ~/.config/alacritty/, foot/, kitty/, ghostty/
    • CLI & Styling:     starship.toml, fastfetch, fontconfig, btop, lazygit, tmux, imv
    • State & Themes:    Active theme, custom backgrounds, workspace layouts, toggles
    • Custom Assets:     ~/.local/share/fonts, ~/.local/share/icons (if present)

${BOLD}MIGRATION QUICKSTART:${RESET}
    1. On this computer:
       ${GREEN}bash ~/$SCRIPT_NAME export${RESET}

    2. Copy ${CYAN}~/omarchy-config-backup.zip${RESET} and ${CYAN}~/$SCRIPT_NAME${RESET} to your new computer.

    3. On the new computer (already running Omarchy):
       ${GREEN}bash ~/$SCRIPT_NAME import${RESET}

EOF
}

# ==============================================================================
# 6. Main Entrypoint
# ==============================================================================
main() {
  # Strictly verify Omarchy system compatibility first
  check_omarchy

  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    export)
      do_export "$@"
      ;;
    import)
      do_import "$@"
      ;;
    -h|--help|help|"")
      show_help
      ;;
    *)
      error "Unknown command: '$cmd'"
      echo ""
      show_help
      exit 1
      ;;
  esac
}

main "$@"
