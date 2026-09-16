#!/usr/bin/env bash
# ==============================================================================
# setup.sh - System Dependency & Toolchain Installer for KRS Neovim
# Supports: Termux (Android), Debian/Ubuntu/WSL, Fedora, Arch, macOS, Alpine
# ==============================================================================

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN} 🦊 KRS Neovim System Dependency & Toolchain Installer ${NC}"
echo -e "${CYAN}============================================================${NC}"

# Detect OS & Package Manager
PKG_MANAGER=""
IS_TERMUX=false
NEED_SUDO=true

if [ "$EUID" -eq 0 ]; then
  NEED_SUDO=false
fi

if [ -n "$TERMUX_VERSION" ] || [ -d "/data/data/com.termux" ] || [[ "$PREFIX" == *"com.termux"* ]]; then
  IS_TERMUX=true
  if command -v pkg >/dev/null 2>&1; then
    PKG_MANAGER="pkg"
    NEED_SUDO=false
    echo -e "${GREEN}[+] Environment detected: Termux Native (Android)${NC}"
  elif command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
    echo -e "${GREEN}[+] Environment detected: Ubuntu PRoot/Chroot on Android Termux (apt)${NC}"
  fi
elif command -v apt-get >/dev/null 2>&1; then
  PKG_MANAGER="apt"
  echo -e "${GREEN}[+] Environment detected: Debian / Ubuntu / PRoot / WSL (apt)${NC}"
elif command -v dnf >/dev/null 2>&1; then
  PKG_MANAGER="dnf"
  echo -e "${GREEN}[+] Environment detected: Fedora / RHEL (dnf)${NC}"
elif command -v pacman >/dev/null 2>&1; then
  PKG_MANAGER="pacman"
  echo -e "${GREEN}[+] Environment detected: Arch Linux (pacman)${NC}"
elif command -v brew >/dev/null 2>&1; then
  PKG_MANAGER="brew"
  NEED_SUDO=false
  echo -e "${GREEN}[+] Environment detected: macOS (brew)${NC}"
elif command -v apk >/dev/null 2>&1; then
  PKG_MANAGER="apk"
  echo -e "${GREEN}[+] Environment detected: Alpine Linux (apk)${NC}"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "mingw"* ]]; then
  echo -e "${YELLOW}[*] Windows environment detected. Delegating to setup.ps1...${NC}"
  if command -v powershell.exe >/dev/null 2>&1; then
    exec powershell.exe -ExecutionPolicy Bypass -File "$(dirname "$0")/setup.ps1"
  else
    echo -e "${RED}[!] powershell.exe not found.${NC}"
    exit 1
  fi
else
  echo -e "${RED}[!] Unable to detect supported package manager.${NC}"
  exit 1
fi

run_cmd() {
  if [ "$NEED_SUDO" = true ] && [ "$EUID" -ne 0 ]; then
    if [ -n "$SUDO_PASS" ]; then
      echo "$SUDO_PASS" | sudo -S "$@"
    else
      sudo "$@"
    fi
  else
    "$@"
  fi
}

check_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# Component installer functions
install_core() {
  echo -e "\n${BLUE}[*] Installing Core Utilities (neovim, git, ripgrep, fd, compiler, tree-sitter, chafa)...${NC}"
  case "$PKG_MANAGER" in
    pkg)
      run_cmd pkg install -y neovim git ripgrep fd clang tree-sitter chafa
      ;;
    apt)
      run_cmd apt-get update
      run_cmd apt-get install -y neovim git ripgrep fd-find build-essential tree-sitter-cli chafa
      ;;
    dnf)
      run_cmd dnf install -y neovim git ripgrep fd-find gcc gcc-c++ tree-sitter-cli chafa
      ;;
    pacman)
      run_cmd pacman -Sy --needed neovim git ripgrep fd gcc tree-sitter-cli chafa
      ;;
    brew)
      run_cmd brew install neovim git ripgrep fd gcc tree-sitter chafa
      ;;
    apk)
      run_cmd apk add neovim git ripgrep fd build-base tree-sitter chafa
      ;;
  esac
}

install_node() {
  echo -e "\n${BLUE}[*] Installing Node.js & Web Toolchain (node, npm, prettier)...${NC}"
  case "$PKG_MANAGER" in
    pkg)
      run_cmd pkg install -y nodejs-lts
      ;;
    apt)
      run_cmd apt-get update
      run_cmd apt-get install -y nodejs npm
      ;;
    dnf)
      run_cmd dnf install -y nodejs npm
      ;;
    pacman)
      run_cmd pacman -Sy --needed nodejs npm
      ;;
    brew)
      run_cmd brew install node
      ;;
    apk)
      run_cmd apk add nodejs npm
      ;;
  esac

  if check_cmd npm; then
    echo -e "${BLUE}[*] Installing global npm formatters (prettier, prettierd)...${NC}"
    run_cmd npm install -g prettier prettierd 2>/dev/null || true
  fi
}

install_go() {
  echo -e "\n${BLUE}[*] Installing Go Toolchain...${NC}"
  case "$PKG_MANAGER" in
    pkg)
      run_cmd pkg install -y golang
      ;;
    apt)
      run_cmd apt-get update
      run_cmd apt-get install -y golang-go
      ;;
    dnf)
      run_cmd dnf install -y golang
      ;;
    pacman)
      run_cmd pacman -Sy --needed go
      ;;
    brew)
      run_cmd brew install go
      ;;
    apk)
      run_cmd apk add go
      ;;
  esac
}

install_python() {
  echo -e "\n${BLUE}[*] Installing Python Toolchain...${NC}"
  case "$PKG_MANAGER" in
    pkg)
      run_cmd pkg install -y python
      ;;
    apt)
      run_cmd apt-get update
      run_cmd apt-get install -y python3 python3-pip
      ;;
    dnf)
      run_cmd dnf install -y python3 python3-pip
      ;;
    pacman)
      run_cmd pacman -Sy --needed python python-pip
      ;;
    brew)
      run_cmd brew install python3
      ;;
    apk)
      run_cmd apk add python3 py3-pip
      ;;
  esac
}

install_lua_tools() {
  echo -e "\n${BLUE}[*] Installing Lua tools (stylua, luacheck)...${NC}"
  case "$PKG_MANAGER" in
    pkg)
      run_cmd pkg install -y stylua luacheck 2>/dev/null || true
      ;;
    pacman)
      run_cmd pacman -Sy --needed stylua luacheck 2>/dev/null || true
      ;;
    brew)
      run_cmd brew install stylua luacheck 2>/dev/null || true
      ;;
    *)
      if check_cmd cargo; then
        cargo install stylua 2>/dev/null || true
      fi
      if check_cmd luarocks; then
        luarocks install luacheck 2>/dev/null || true
      fi
      ;;
  esac
}

install_dotnet() {
  echo -e "\n${BLUE}[*] Installing .NET SDK & C# Tools (dotnet, csharp-ls)...${NC}"
  case "$PKG_MANAGER" in
    pkg)
      run_cmd pkg install -y dotnet-sdk 2>/dev/null || true
      ;;
    apt)
      run_cmd apt-get update
      run_cmd apt-get install -y dotnet-sdk-8.0 2>/dev/null || run_cmd apt-get install -y dotnet-sdk-9.0 2>/dev/null || true
      ;;
    dnf)
      run_cmd dnf install -y dotnet-sdk-8.0 2>/dev/null || true
      ;;
    pacman)
      run_cmd pacman -Sy --needed dotnet-sdk 2>/dev/null || true
      ;;
    brew)
      run_cmd brew install dotnet-sdk 2>/dev/null || true
      ;;
    apk)
      run_cmd apk add dotnet8-sdk 2>/dev/null || true
      ;;
  esac

  if check_cmd dotnet; then
    if ! check_cmd csharp-ls; then
      echo -e "${BLUE}[*] Installing csharp-ls dotnet global tool...${NC}"
      dotnet tool install -g csharp-ls 2>/dev/null || true
    fi
  fi
}

install_agy() {
  echo -e "\n${BLUE}[*] Installing Google Antigravity CLI (agy)...${NC}"
  curl -fsSL https://antigravity.google/cli/install.sh | bash
  echo -e "${GREEN}[+] Google Antigravity CLI (agy) installation finished.${NC}"
}

install_claude() {
  echo -e "\n${BLUE}[*] Installing Claude Code CLI (claude)...${NC}"
  if ! curl -fsSL https://claude.ai/install.sh | bash 2>/dev/null; then
    if command -v npm >/dev/null 2>&1; then
      echo -e "${YELLOW}[!] Native installer unavailable, falling back to npm install -g @anthropic-ai/claude-code...${NC}"
      run_cmd npm install -g @anthropic-ai/claude-code
    fi
  fi
  echo -e "${GREEN}[+] Claude Code CLI (claude) installation finished.${NC}"
}

install_all() {
  install_core
  install_node
  install_go
  install_python
  install_lua_tools
  install_dotnet
}

# Menu / CLI flags parsing
AUTO_ALL=false
SUDO_PASS="${SUDO_PASS:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sudo-pass)
      SUDO_PASS="$2"
      shift 2
      ;;
    --all|-y|--yes)
      AUTO_ALL=true
      shift
      ;;
    --agy)
      install_agy
      exit 0
      ;;
    --claude)
      install_claude
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

if [ ! -t 0 ]; then
  AUTO_ALL=true
fi

if [ "$AUTO_ALL" = true ]; then
  echo -e "${YELLOW}[*] Non-interactive / --all mode selected. Installing all dependencies...${NC}"
  install_all
else
  echo -e "\n${YELLOW}Select component toolchains to install from official package manager sources:${NC}\n"
  echo "  1) ALL Recommended Dependencies (Core, Node/npm, Go, Python, Lua tools, .NET/C#) [Default]"
  echo "  2) Core Utilities only (neovim, git, ripgrep, fd, compiler, tree-sitter, chafa)"
  echo "  3) Node.js & Web Toolchain (node, npm, prettier)"
  echo "  4) Go Toolchain (go)"
  echo "  5) Python Toolchain (python3, pip)"
  echo "  6) .NET & C# Toolchain (dotnet-sdk, csharp-ls)"
  echo "  7) Custom Selection (choose step-by-step)"
  echo "  Q) Quit"
  echo ""
  read -p "Enter choice [1-7, Q] (Default: 1): " CHOICE
  CHOICE="${CHOICE:-1}"

  case "$CHOICE" in
    1|[aA][lL][lL])
      install_all
      ;;
    2)
      install_core
      ;;
    3)
      install_node
      ;;
    4)
      install_go
      ;;
    5)
      install_python
      ;;
    6)
      install_dotnet
      ;;
    7)
      read -p "Install Core Utilities (neovim, git, ripgrep, fd, compiler)? [Y/n]: " C_CORE
      [[ "${C_CORE:-y}" =~ ^[Yy] ]] && install_core

      read -p "Install Node.js & npm (for JS/TS/HTML/CSS LSPs & Prettier)? [Y/n]: " C_NODE
      [[ "${C_NODE:-y}" =~ ^[Yy] ]] && install_node

      read -p "Install Go (for Go LSP & tools)? [Y/n]: " C_GO
      [[ "${C_GO:-y}" =~ ^[Yy] ]] && install_go

      read -p "Install Python (for Python LSPs & tools)? [Y/n]: " C_PY
      [[ "${C_PY:-y}" =~ ^[Yy] ]] && install_python

      read -p "Install Stylua / Lua tools? [Y/n]: " C_LUA
      [[ "${C_LUA:-y}" =~ ^[Yy] ]] && install_lua_tools

      read -p "Install .NET SDK & C# tools (csharp-ls)? [Y/n]: " C_DOTNET
      [[ "${C_DOTNET:-y}" =~ ^[Yy] ]] && install_dotnet
      ;;
    [qQ]*)
      echo "Exiting setup."
      exit 0
      ;;
    *)
      echo "Invalid selection. Running default full installation..."
      install_all
      ;;
  esac
fi

echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN} ✅ System Dependency Setup Complete! ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "You can now launch Neovim."
echo -e "Inside Neovim, if you wish to install additional LSPs or formatters, run:"
echo -e "  ${CYAN}:KrsInstallAll${NC}"
echo ""
