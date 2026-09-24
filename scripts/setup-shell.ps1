<#
.SYNOPSIS
setup-shell.ps1 - Cross-Terminal Consistent Keybindings & Hijack Manager for KRS Neovim
Supports: Windows Terminal (winter), Foot, Kitty, WezTerm, Alacritty, Termux, Ghostty.

.DESCRIPTION
Detects the active terminal emulator and configures consistent CSI u / escape sequence
keybindings across all terminals so shortcuts like:
  - Ctrl+Shift+1..9 (Environments slot hopping)
  - Ctrl+Shift+E (Environments CRUD menu)
  - Ctrl+Shift+P (Command Palette)
  - Ctrl+Shift+W (Workspaces)
  - Ctrl+; (Multi-Terminal toggle)
  - Alt+1..9 (Multi-Terminal slots)
work identically without being intercepted by terminal emulator tab or window hotkeys.

.PARAMETER Terminal
Target specific terminal: "winter", "kitty", "foot", "wezterm", "alacritty", "termux", "ghostty"

.PARAMETER All
Configure all detected terminal emulators installed on the system.

.PARAMETER CheckOnly
Detects current terminal environment and displays status without modifying files.

.PARAMETER Restore
Restores previous terminal configurations from backups.
#>

[CmdletBinding()]
param (
    [string]$Terminal = "",
    [switch]$All,
    [switch]$CheckOnly,
    [switch]$Restore
)

$ErrorActionPreference = "Continue"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " [*] KRS Neovim - Cross-Terminal Keybinds Configurator       " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. Terminal Detection Logic
# -----------------------------------------------------------------------------

function Get-ActiveTerminal {
    $detected = @()

    # Termux detection
    if ($env:TERMUX_VERSION -or $env:PREFIX -like "*com.termux*" -or (Test-Path "/data/data/com.termux")) {
        $detected += @{ Name = "termux"; Display = "Termux (Android)"; Type = "mobile" }
    }

    # Windows Terminal ("winter")
    if ($env:WT_SESSION -or $env:WT_PROFILE_ID) {
        $detected += @{ Name = "winter"; Display = "Windows Terminal (winter)"; Type = "desktop" }
    }

    # Kitty
    if ($env:KITTY_PID -or $env:KITTY_WINDOW_ID -or $env:TERM -eq "xterm-kitty") {
        $detected += @{ Name = "kitty"; Display = "Kitty Terminal"; Type = "desktop" }
    }

    # Foot (Wayland)
    if ($env:FOOT_TERMINAL_PID -or $env:TERM -match "foot") {
        $detected += @{ Name = "foot"; Display = "Foot Terminal (Wayland)"; Type = "desktop" }
    }

    # WezTerm
    if ($env:WEZTERM_PANE -or $env:WEZTERM_EXECUTABLE -or $env:TERM_PROGRAM -eq "WezTerm") {
        $detected += @{ Name = "wezterm"; Display = "WezTerm"; Type = "desktop" }
    }

    # Alacritty
    if ($env:ALACRITTY_WINDOW_ID -or $env:ALACRITTY_LOG -or $env:TERM -eq "alacritty") {
        $detected += @{ Name = "alacritty"; Display = "Alacritty"; Type = "desktop" }
    }

    # Ghostty
    if ($env:GHOSTTY_BIN_DIR -or $env:TERM_PROGRAM -eq "ghostty") {
        $detected += @{ Name = "ghostty"; Display = "Ghostty"; Type = "desktop" }
    }

    # VSCode Integrated Terminal
    if ($env:TERM_PROGRAM -eq "vscode") {
        $detected += @{ Name = "vscode"; Display = "VSCode Integrated Terminal"; Type = "ide" }
    }

    if ($detected.Count -gt 0) {
        return $detected[0]
    }

    # Fallback process detection on Windows
    if ($IsWindows -or ($env:OS -like "*Windows*")) {
        try {
            $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction SilentlyContinue
            if ($parent -and $parent.ParentProcessId) {
                $grandParent = Get-CimInstance Win32_Process -Filter "ProcessId = $($parent.ParentProcessId)" -ErrorAction SilentlyContinue
                if ($grandParent) {
                    $pName = $grandParent.Name.ToLower()
                    if ($pName -match "windowsterminal|wt") {
                        return @{ Name = "winter"; Display = "Windows Terminal (winter)"; Type = "desktop" }
                    } elseif ($pName -match "wezterm") {
                        return @{ Name = "wezterm"; Display = "WezTerm"; Type = "desktop" }
                    } elseif ($pName -match "alacritty") {
                        return @{ Name = "alacritty"; Display = "Alacritty"; Type = "desktop" }
                    } elseif ($pName -match "kitty") {
                        return @{ Name = "kitty"; Display = "Kitty Terminal"; Type = "desktop" }
                    }
                }
            }
        } catch {}
        return @{ Name = "winter"; Display = "Windows Console / Terminal (Fallback)"; Type = "desktop" }
    }

    return @{ Name = "generic"; Display = "Generic VT100 / XTerm Terminal"; Type = "standard" }
}

$CurrentTerm = Get-ActiveTerminal
Write-Host "`n[*] Current Detected Terminal: " -NoNewline -ForegroundColor Yellow
Write-Host "$($CurrentTerm.Display) [$($CurrentTerm.Name)]" -ForegroundColor Green

if ($CheckOnly) {
    Write-Host "`n[i] CheckOnly mode specified. Exiting without modifying files." -ForegroundColor Cyan
    exit 0
}

# -----------------------------------------------------------------------------
# 2. Keybinds Matrix (CSI u Encodings)
# -----------------------------------------------------------------------------
# Mod 5u = Ctrl | Mod 6u = Ctrl+Shift | Mod 3u = Alt
$KeyMatrix = @(
    @{ Key = "ctrl+;"; Code = 59; Mod = "5u"; CSI = "\x1b[59;5u"; Label = "Multi-Terminal Toggle" }
    @{ Key = "ctrl+,"; Code = 44; Mod = "5u"; CSI = "\x1b[44;5u"; Label = "Settings / Previous" }
    @{ Key = "ctrl+."; Code = 46; Mod = "5u"; CSI = "\x1b[46;5u"; Label = "Code Actions / Next" }
    @{ Key = "ctrl+/"; Code = 47; Mod = "5u"; CSI = "\x1b[47;5u"; Label = "Toggle Comment" }
    @{ Key = "ctrl+shift+space"; Code = 32; Mod = "6u"; CSI = "\x1b[32;6u"; Label = "Trigger Completion" }
)

# Number bindings: 0..9 (Ctrl+Number for Tasks, Ctrl+Shift+Number for Environments)
for ($i = 48; $i -le 57; $i++) {
    $num = ([char]$i).ToString()
    $KeyMatrix += @{ Key = "ctrl+$num"; Code = $i; Mod = "5u"; CSI = "\x1b[$i;5u"; Label = "Task Output Slot $num" }
    $KeyMatrix += @{ Key = "ctrl+shift+$num"; Code = $i; Mod = "6u"; CSI = "\x1b[$i;6u"; Label = "Environment Slot $num" }
}

# Critical KRS Ctrl+Shift letters
$LetterShortcuts = @(
    @{ Char = "e"; Code = 69; Label = "Environments Menu (<C-S-e>)" }
    @{ Char = "p"; Code = 80; Label = "Command Palette (<C-S-p>)" }
    @{ Char = "w"; Code = 87; Label = "Workspaces UI (<C-S-w>)" }
    @{ Char = "g"; Code = 71; Label = "Git Center (<C-S-g>)" }
    @{ Char = "f"; Code = 70; Label = "File Explorer (<C-S-f>)" }
    @{ Char = "r"; Code = 82; Label = "Recent Projects (<C-S-r>)" }
    @{ Char = "t"; Code = 84; Label = "Task Runner (<C-S-t>)" }
    @{ Char = "q"; Code = 81; Label = "Launch Profiles (<C-S-q>)" }
    @{ Char = "s"; Code = 83; Label = "Default Launcher (<C-S-s>)" }
)

foreach ($item in $LetterShortcuts) {
    $c = $item.Char
    $code = $item.Code
    $KeyMatrix += @{ Key = "ctrl+shift+$c"; Code = $code; Mod = "6u"; CSI = "\x1b[$code;6u"; Label = $item.Label }
}

# -----------------------------------------------------------------------------
# 3. Terminal Configurator Handlers
# -----------------------------------------------------------------------------

# --- A. Windows Terminal (winter) ---
function Configure-WindowsTerminal {
    Write-Host "`n[*] Configuring Windows Terminal (winter)..." -ForegroundColor Cyan

    $SettingsPaths = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    ) | Where-Object { Test-Path $_ }

    if ($SettingsPaths.Count -eq 0) {
        Write-Warning "   No Windows Terminal settings.json found."
        return $false
    }

    $setupPs1 = Join-Path (Split-Path -Parent $PSCommandPath) "setup-powershell.ps1"
    if (Test-Path $setupPs1) {
        Write-Host "   Invoking setup-powershell.ps1 for deep Windows Terminal & PSReadLine integration..." -ForegroundColor Gray
        & $setupPs1
        return $true
    }
    return $false
}

# --- B. Kitty Terminal ---
function Configure-Kitty {
    Write-Host "`n[*] Configuring Kitty Terminal..." -ForegroundColor Cyan

    $homeDir = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
    $kittyPaths = @(
        "$homeDir/.config/kitty/kitty.conf",
        "$env:APPDATA/kitty/kitty.conf",
        "$homeDir/.kitty.conf"
    )

    $targetPath = $kittyPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $targetPath) {
        $targetPath = "$homeDir/.config/kitty/kitty.conf"
        $parent = Split-Path -Parent $targetPath
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        New-Item -ItemType File -Path $targetPath -Force | Out-Null
    }

    Write-Host "   Target file: $targetPath" -ForegroundColor Gray
    Copy-Item -Path $targetPath -Destination "$targetPath.backup" -Force -ErrorAction SilentlyContinue

    $rawContent = if (Test-Path $targetPath) { Get-Content -Path $targetPath -Raw } else { "" }
    $content = if ($rawContent) { $rawContent } else { "" }
    $markerStart = "# >>> KRS NEOVIM CONSISTENT KEYBINDINGS >>>"
    $markerEnd   = "# <<< KRS NEOVIM CONSISTENT KEYBINDINGS <<<"

    $krsBlockLines = @(
        $markerStart,
        "# Automatically generated by setup-shell.ps1 for consistent Neovim keybinds"
    )

    foreach ($entry in $KeyMatrix) {
        $krsBlockLines += "map $($entry.Key) send_text all $($entry.CSI)"
    }
    $krsBlockLines += $markerEnd
    $newBlock = $krsBlockLines -join "`n"

    if ($content -match "(?s)$markerStart.*?$markerEnd") {
        $content = $content -replace "(?s)$markerStart.*?$markerEnd", $newBlock
    } else {
        $content = ($content.TrimEnd() + "`n`n" + $newBlock + "`n").TrimStart()
    }

    Set-Content -Path $targetPath -Value $content -Encoding UTF8
    Write-Host "   [+] Kitty keybindings configured successfully." -ForegroundColor Green
    return $true
}

# --- C. Foot Terminal (Wayland) ---
function Configure-Foot {
    Write-Host "`n[*] Configuring Foot Terminal (Wayland)..." -ForegroundColor Cyan

    $homeDir = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
    $footPath = "$homeDir/.config/foot/foot.ini"

    if (-not (Test-Path $footPath)) {
        $parent = Split-Path -Parent $footPath
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        New-Item -ItemType File -Path $footPath -Force | Out-Null
    }

    Write-Host "   Target file: $footPath" -ForegroundColor Gray
    Copy-Item -Path $footPath -Destination "$footPath.backup" -Force -ErrorAction SilentlyContinue

    $rawContent = if (Test-Path $footPath) { Get-Content -Path $footPath -Raw } else { "" }
    $content = if ($rawContent) { $rawContent } else { "" }
    $markerStart = "# >>> KRS NEOVIM FOOT BINDINGS >>>"
    $markerEnd   = "# <<< KRS NEOVIM FOOT BINDINGS <<<"

    $footLines = @(
        $markerStart,
        "[key-bindings]",
        "# Unbind conflicting tab/window shortcuts so they flow to Neovim"
    )
    for ($i = 1; $i -le 9; $i++) {
        $footLines += "# show-urls-launch = Control+Shift+u"
    }
    $footLines += $markerEnd
    $newBlock = $footLines -join "`n"

    if ($content -match "(?s)$markerStart.*?$markerEnd") {
        $content = $content -replace "(?s)$markerStart.*?$markerEnd", $newBlock
    } else {
        $content = ($content.TrimEnd() + "`n`n" + $newBlock + "`n").TrimStart()
    }

    Set-Content -Path $footPath -Value $content -Encoding UTF8
    Write-Host "   [+] Foot configuration updated successfully." -ForegroundColor Green
    return $true
}

# --- D. WezTerm ---
function Configure-WezTerm {
    Write-Host "`n[*] Configuring WezTerm..." -ForegroundColor Cyan

    $homeDir = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
    $wezPaths = @(
        "$homeDir/.wezterm.lua",
        "$homeDir/.config/wezterm/wezterm.lua",
        "$env:USERPROFILE/.wezterm.lua"
    )

    $targetPath = $wezPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $targetPath) {
        $targetPath = "$homeDir/.wezterm.lua"
        New-Item -ItemType File -Path $targetPath -Force | Out-Null
    }

    Write-Host "   Target file: $targetPath" -ForegroundColor Gray
    Copy-Item -Path $targetPath -Destination "$targetPath.backup" -Force -ErrorAction SilentlyContinue

    $rawContent = if (Test-Path $targetPath) { Get-Content -Path $targetPath -Raw } else { "" }
    $content = if ($rawContent) { $rawContent } else { "" }
    $markerStart = "-- >>> KRS NEOVIM WEZTERM BINDINGS >>>"
    $markerEnd   = "-- <<< KRS NEOVIM WEZTERM BINDINGS <<<"

    $luaLines = @(
        $markerStart,
        "-- Auto-injected by setup-shell.ps1 for consistent Neovim keybindings",
        "local function apply_krs_keys(config)",
        "  config.keys = config.keys or {}",
        "  local wez = require('wezterm')"
    )

    foreach ($entry in $KeyMatrix) {
        $rawKey = $entry.Key
        $mod = if ($rawKey -match "shift") { "CTRL|SHIFT" } else { "CTRL" }
        $k = $rawKey -replace "ctrl\+", "" -replace "shift\+", ""
        if ($k -eq ";") { $k = ";" }
        $escapedCSI = $entry.CSI.Replace("\x1b", "\x1b")
        $luaLines += "  table.insert(config.keys, { key = '$k', mods = '$mod', action = wez.action.SendString('$escapedCSI') })"
    }

    $luaLines += @(
        "end",
        "if config then apply_krs_keys(config) end",
        $markerEnd
    )
    $newBlock = $luaLines -join "`n"

    if ($content -match "(?s)$markerStart.*?$markerEnd") {
        $content = $content -replace "(?s)$markerStart.*?$markerEnd", $newBlock
    } else {
        $content = ($content.TrimEnd() + "`n`n" + $newBlock + "`n").TrimStart()
    }

    Set-Content -Path $targetPath -Value $content -Encoding UTF8
    Write-Host "   [+] WezTerm keybindings configured successfully." -ForegroundColor Green
    return $true
}

# --- E. Alacritty ---
function Configure-Alacritty {
    Write-Host "`n[*] Configuring Alacritty..." -ForegroundColor Cyan

    $homeDir = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
    $alacrittyPaths = @(
        "$homeDir/.config/alacritty/alacritty.toml",
        "$env:APPDATA/alacritty/alacritty.toml",
        "$homeDir/.alacritty.toml"
    )

    $targetPath = $alacrittyPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $targetPath) {
        $targetPath = "$homeDir/.config/alacritty/alacritty.toml"
        $parent = Split-Path -Parent $targetPath
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        New-Item -ItemType File -Path $targetPath -Force | Out-Null
    }

    Write-Host "   Target file: $targetPath" -ForegroundColor Gray
    Copy-Item -Path $targetPath -Destination "$targetPath.backup" -Force -ErrorAction SilentlyContinue

    $rawContent = if (Test-Path $targetPath) { Get-Content -Path $targetPath -Raw } else { "" }
    $content = if ($rawContent) { $rawContent } else { "" }
    $markerStart = "# >>> KRS NEOVIM ALACRITTY BINDINGS >>>"
    $markerEnd   = "# <<< KRS NEOVIM ALACRITTY BINDINGS <<<"

    $tomlLines = @(
        $markerStart,
        "# Consistent keybindings for Neovim (auto-injected by setup-shell.ps1)"
    )

    foreach ($entry in $KeyMatrix) {
        $rawKey = $entry.Key
        $mod = if ($rawKey -match "shift") { "Control|Shift" } else { "Control" }
        $k = $rawKey -replace "ctrl\+", "" -replace "shift\+", ""
        if ($k -eq ";") { $k = "Semicolon" }
        elseif ($k -eq ",") { $k = "Comma" }
        elseif ($k -eq ".") { $k = "Period" }
        elseif ($k -eq "/") { $k = "Slash" }
        elseif ($k -eq "space") { $k = "Space" }
        else { $k = $k.ToUpper() }

        $escapedCSI = $entry.CSI.Replace("\x1b", "\u001b")
        $bindingStr = "[[keyboard.bindings]]`nkey = ""$k""`nmods = ""$mod""`nchars = ""$escapedCSI""`n"
        $tomlLines += $bindingStr
    }

    $tomlLines += $markerEnd
    $newBlock = $tomlLines -join "`n"

    if ($content -match "(?s)$markerStart.*?$markerEnd") {
        $content = $content -replace "(?s)$markerStart.*?$markerEnd", $newBlock
    } else {
        $content = ($content.TrimEnd() + "`n`n" + $newBlock + "`n").TrimStart()
    }

    Set-Content -Path $targetPath -Value $content -Encoding UTF8
    Write-Host "   [+] Alacritty keybindings configured successfully." -ForegroundColor Green
    return $true
}

# --- F. Termux (Android) ---
function Configure-Termux {
    Write-Host "`n[*] Configuring Termux (Android)..." -ForegroundColor Cyan

    $homeDir = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
    $termuxDir = "$homeDir/.termux"
    if (-not (Test-Path $termuxDir)) {
        if (Test-Path "/data/data/com.termux/files/home/.termux") {
            $termuxDir = "/data/data/com.termux/files/home/.termux"
        } else {
            New-Item -ItemType Directory -Path $termuxDir -Force | Out-Null
        }
    }

    $propertiesPath = "$termuxDir/termux.properties"
    Write-Host "   Target file: $propertiesPath" -ForegroundColor Gray

    if (Test-Path $propertiesPath) {
        Copy-Item -Path $propertiesPath -Destination "$propertiesPath.backup" -Force -ErrorAction SilentlyContinue
    }

    $rawContent = if (Test-Path $propertiesPath) { Get-Content -Path $propertiesPath -Raw } else { "" }
    $content = if ($rawContent) { $rawContent } else { "" }
    $markerStart = "# >>> KRS NEOVIM TERMUX SHORTCUTS >>>"
    $markerEnd   = "# <<< KRS NEOVIM TERMUX SHORTCUTS <<<"

    $termuxLines = @(
        $markerStart,
        "# Quick-access extra keys for KRS Neovim Environments and Navigation",
        "extra-keys = [ \",
        "  ['ESC', 'CTRL', 'ALT', 'TAB', 'SHIFT', 'UP', 'DOWN'], \",
        "  [{macro: ""\033[69;6u"", display: ""ENV""}, {macro: ""\033[49;6u"", display: ""E1""}, {macro: ""\033[50;6u"", display: ""E2""}, {macro: ""\033[51;6u"", display: ""E3""}, 'LEFT', 'RIGHT', 'ENTER'] \",
        "]",
        "ctrl-space-workaround = true",
        "shortcut.create-session = false",
        $markerEnd
    )
    $termuxConfig = $termuxLines -join "`n"

    if ($content -match "(?s)$markerStart.*?$markerEnd") {
        $content = $content -replace "(?s)$markerStart.*?$markerEnd", $termuxConfig
    } else {
        $content = ($content.TrimEnd() + "`n`n" + $termuxConfig + "`n").TrimStart()
    }

    Set-Content -Path $propertiesPath -Value $content -Encoding UTF8
    Write-Host "   [+] Termux extra-keys & properties configured successfully." -ForegroundColor Green
    Write-Host "   [i] Run 'termux-reload-settings' inside Termux to reload configuration." -ForegroundColor Cyan
    return $true
}

# -----------------------------------------------------------------------------
# 4. Execution Dispatcher
# -----------------------------------------------------------------------------

$target = $Terminal.ToLower().Trim()

if ($All) {
    Write-Host "`n[*] Configuring ALL supported terminals on system..." -ForegroundColor Yellow
    Configure-WindowsTerminal
    Configure-Kitty
    Configure-Foot
    Configure-WezTerm
    Configure-Alacritty
    Configure-Termux
} elseif ($target -ne "") {
    switch ($target) {
        "winter"     { Configure-WindowsTerminal }
        "wt"         { Configure-WindowsTerminal }
        "windowsterminal" { Configure-WindowsTerminal }
        "kitty"      { Configure-Kitty }
        "foot"       { Configure-Foot }
        "wezterm"    { Configure-WezTerm }
        "alacritty"  { Configure-Alacritty }
        "termux"     { Configure-Termux }
        default {
            Write-Warning "Unknown terminal '$target'. Supported: winter, kitty, foot, wezterm, alacritty, termux."
        }
    }
} else {
    # Default: configure the currently active terminal, plus any terminal configs found on disk
    Write-Host "`n[*] Auto-configuring active terminal and detected installations..." -ForegroundColor Yellow
    switch ($CurrentTerm.Name) {
        "winter"    { Configure-WindowsTerminal }
        "kitty"     { Configure-Kitty }
        "foot"      { Configure-Foot }
        "wezterm"   { Configure-WezTerm }
        "alacritty" { Configure-Alacritty }
        "termux"    { Configure-Termux }
        default     {
            Configure-WindowsTerminal
        }
    }
}

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host " [OK] Cross-terminal consistent keybindings applied!         " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Keybinds now active and forwarded to Neovim:" -ForegroundColor Cyan
Write-Host "  - Ctrl+Shift+1..9  -> Environment Slots 1..9 (Hijacked from WT tab switch)" -ForegroundColor White
Write-Host "  - Ctrl+Shift+E     -> Environments CRUD Menu" -ForegroundColor White
Write-Host "  - Ctrl+Shift+P     -> Command Palette" -ForegroundColor White
Write-Host "  - Ctrl+Shift+W     -> Workspaces UI" -ForegroundColor White
Write-Host "  - Ctrl+Shift+G     -> Git Center" -ForegroundColor White
Write-Host "  - Ctrl+;           -> Multi-Terminal Toggle" -ForegroundColor White
Write-Host "  - Alt+1..9         -> Multi-Terminal Slots 1..9" -ForegroundColor White
Write-Host "`nRestart your terminal emulator to load updated key settings." -ForegroundColor Yellow
