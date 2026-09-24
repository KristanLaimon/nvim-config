#!/usr/bin/env bash
# ==============================================================================
# unsetup-bash.sh - Cross-Terminal Revert & Cleanup Manager for KRS Neovim
# Reverts injected keybindings and restores original terminal configurations.
# Supports: Kitty, Foot, WezTerm, Alacritty, Termux, Windows Terminal
# ==============================================================================

set -e

COLOR_CYAN='\033[0;36m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_GRAY='\033[0;90m'
COLOR_NC='\033[0m'

echo -e "${COLOR_CYAN}============================================================${COLOR_NC}"
echo -e "${COLOR_CYAN} [*] KRS Neovim - Terminal Keybindings Uninstaller (Bash)   ${COLOR_NC}"
echo -e "${COLOR_CYAN}============================================================${COLOR_NC}"

RESTORE_BACKUP=false
TARGET_TERM=""

for arg in "$@"; do
    case "$arg" in
        --restore)
            RESTORE_BACKUP=true
            ;;
        --term=*|-t=*)
            TARGET_TERM="${arg#*=}"
            ;;
        kitty|foot|wezterm|alacritty|termux|winter|wt)
            TARGET_TERM="$arg"
            ;;
    esac
done

clean_block() {
    local file="$1"
    local start_pattern="$2"
    local end_pattern="$3"
    local term_name="$4"

    if [ ! -f "$file" ]; then
        return
    fi

    echo -e "\n[*] Cleaning $term_name configuration in $file..."

    if [ "$RESTORE_BACKUP" = true ] && [ -f "$file.backup" ]; then
        cp -f "$file.backup" "$file"
        echo -e "   ${COLOR_GREEN}[+] Restored from backup: $file.backup${COLOR_NC}"
        return
    fi

    if grep -q "$start_pattern" "$file" 2>/dev/null; then
        sed -i "/$start_pattern/,/$end_pattern/d" "$file"
        echo -e "   ${COLOR_GREEN}[+] Removed KRS keybinding block successfully.${COLOR_NC}"
    else
        echo -e "   ${COLOR_GRAY}[i] No KRS keybindings found in $file.${COLOR_NC}"
    fi
}

# --- Kitty ---
clean_kitty() {
    local kitty_file="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
    clean_block "$kitty_file" "# >>> KRS NEOVIM CONSISTENT KEYBINDINGS >>>" "# <<< KRS NEOVIM CONSISTENT KEYBINDINGS <<<" "Kitty"
}

# --- Foot ---
clean_foot() {
    local foot_file="${XDG_CONFIG_HOME:-$HOME/.config}/foot/foot.ini"
    clean_block "$foot_file" "# >>> KRS NEOVIM FOOT BINDINGS >>>" "# <<< KRS NEOVIM FOOT BINDINGS <<<" "Foot"
}

# --- WezTerm ---
clean_wezterm() {
    local wez1="$HOME/.wezterm.lua"
    local wez2="${XDG_CONFIG_HOME:-$HOME/.config}/wezterm/wezterm.lua"
    clean_block "$wez1" "\-\- >>> KRS NEOVIM WEZTERM BINDINGS >>>" "\-\- <<< KRS NEOVIM WEZTERM BINDINGS <<<" "WezTerm (~/.wezterm.lua)"
    clean_block "$wez2" "\-\- >>> KRS NEOVIM WEZTERM BINDINGS >>>" "\-\- <<< KRS NEOVIM WEZTERM BINDINGS <<<" "WezTerm (.config/wezterm)"
}

# --- Alacritty ---
clean_alacritty() {
    local alacritty_file="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml"
    clean_block "$alacritty_file" "# >>> KRS NEOVIM ALACRITTY BINDINGS >>>" "# <<< KRS NEOVIM ALACRITTY BINDINGS <<<" "Alacritty"
}

# --- Termux ---
clean_termux() {
    local termux_file="$HOME/.termux/termux.properties"
    clean_block "$termux_file" "# >>> KRS NEOVIM TERMUX SHORTCUTS >>>" "# <<< KRS NEOVIM TERMUX SHORTCUTS <<<" "Termux"
    if [ -f "$termux_file" ]; then
        echo -e "   ${COLOR_CYAN}[i] Run 'termux-reload-settings' to reload original Termux properties.${COLOR_NC}"
    fi
}

# --- Windows Terminal ---
clean_winter() {
    if command -v powershell.exe >/dev/null 2>&1; then
        echo -e "\n[*] Invoking PowerShell unsetup bridge for Windows Terminal..."
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$script_dir/unsetup-powershell.ps1"
    fi
}

# Execution Dispatch
if [ -n "$TARGET_TERM" ]; then
    case "$TARGET_TERM" in
        kitty) clean_kitty ;;
        foot) clean_foot ;;
        wezterm) clean_wezterm ;;
        alacritty) clean_alacritty ;;
        termux) clean_termux ;;
        winter|wt) clean_winter ;;
        *) echo -e "${COLOR_RED}Unknown terminal '$TARGET_TERM'.${COLOR_NC}" ;;
    esac
else
    # Clean all supported terminal configurations
    clean_kitty
    clean_foot
    clean_wezterm
    clean_alacritty
    clean_termux
    [ -n "$WT_SESSION" ] && clean_winter
fi

echo -e "\n${COLOR_GREEN}============================================================${COLOR_NC}"
echo -e "${COLOR_GREEN} [OK] Terminal configuration reverted to normal state!      ${COLOR_NC}"
echo -e "${COLOR_GREEN}============================================================${COLOR_NC}"
echo -e "Restart your terminal emulator or reload its configuration to apply."
