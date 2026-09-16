param (
    [switch]$Agy,
    [switch]$Claude
)

if ($Agy) {
    Write-Host "`n[*] Installing Google Antigravity CLI (agy)..." -ForegroundColor Cyan
    irm https://antigravity.google/cli/install.ps1 | iex
    exit 0
}

if ($Claude) {
    Write-Host "`n[*] Installing Claude Code CLI (claude)..." -ForegroundColor Cyan
    irm https://claude.ai/install.ps1 | iex
    exit 0
}

$ErrorActionPreference = "Stop"

Write-Host "🦊 Checking dependencies for krsnvim..." -ForegroundColor Cyan

# 1. Check & Install Scoop if needed
$scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
if (-not $scoopCmd) {
    Write-Host "[*] Scoop is not installed. Installing Scoop from ground up..." -ForegroundColor Yellow
    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
        Write-Host "[+] Scoop installed successfully." -ForegroundColor Green
    } catch {
        Write-Host "[!] Failed to install Scoop automatically: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[+] Scoop is already installed. Proceeding..." -ForegroundColor Green
}

# Ensure Scoop shims directory is in PATH for the current session
$ScoopShims = "$env:USERPROFILE\scoop\shims"
if ($env:PATH -notlike "*$ScoopShims*") {
    $env:PATH = "$ScoopShims;$env:PATH"
}

# 2. Add required buckets (main & extras) if missing
$InstalledBuckets = @()
try {
    $InstalledBuckets = scoop bucket list | Select-Object -ExpandProperty Name -ErrorAction SilentlyContinue
} catch {}

foreach ($bucket in @("main", "extras")) {
    if ($InstalledBuckets -notcontains $bucket) {
        Write-Host "[*] Adding Scoop bucket: $bucket..." -ForegroundColor Yellow
        scoop bucket add $bucket 2>$null
    }
}

# 3. External dependencies for krsnvim (excluding Mason / internal Neovim packages)
$Dependencies = @(
    @{ Package = "neovim";     Cmd = "nvim" },
    @{ Package = "git";        Cmd = "git" },
    @{ Package = "ripgrep";    Cmd = "rg" },
    @{ Package = "fd";         Cmd = "fd" },
    @{ Package = "chafa";      Cmd = "chafa" },
    @{ Package = "gcc";        Cmd = "gcc" },
    @{ Package = "tree-sitter"; Cmd = "tree-sitter" },
    @{ Package = "stylua";     Cmd = "stylua" },
    @{ Package = "luacheck";   Cmd = "luacheck" },
    @{ Package = "nodejs-lts"; Cmd = "node" },
    @{ Package = "bun";        Cmd = "bun" },
    @{ Package = "go";         Cmd = "go" },
    @{ Package = "dotnet-sdk"; Cmd = "dotnet" }
)

$InstalledCount = 0
$MissingCount = 0

foreach ($dep in $Dependencies) {
    $pkg = $dep.Package
    $cmd = $dep.Cmd

    $cmdExists = Get-Command $cmd -ErrorAction SilentlyContinue
    if (-not $cmdExists) {
        Write-Host "[*] Missing dependency detected: $pkg ($cmd). Installing..." -ForegroundColor Yellow
        try {
            scoop install $pkg
            $InstalledCount++
        } catch {
            Write-Host "[!] Warning: Failed to install $pkg via Scoop." -ForegroundColor Red
        }
    } else {
        Write-Host "  - $pkg ($cmd): Already installed" -ForegroundColor Gray
    }
}

# 4. C# / .NET global tools
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    if (-not (Get-Command csharp-ls -ErrorAction SilentlyContinue)) {
        Write-Host "[*] Installing csharp-ls dotnet global tool..." -ForegroundColor Yellow
        try {
            dotnet tool install -g csharp-ls
            Write-Host "[+] csharp-ls installed successfully." -ForegroundColor Green
            $InstalledCount++
        } catch {
            Write-Host "[!] Warning: Failed to install csharp-ls." -ForegroundColor Red
        }
    } else {
        Write-Host "  - csharp-ls: Already installed" -ForegroundColor Gray
    }
}

# 5. Final summary
if ($InstalledCount -eq 0) {
    Write-Host "`n[+] Nothing to install: all dependencies are synced!" -ForegroundColor Green
} else {
    Write-Host "`n[+] Setup complete! Installed $InstalledCount missing dependency package(s)." -ForegroundColor Green
}
