<#
.SYNOPSIS
Configura el entorno para Neovim generando dinámicamente atajos
para Ctrl+;, Ctrl+,, Ctrl+. y TODOS los Ctrl+Shift+[A-Z] + Space.
#>

Write-Host "1. Limpiando atajos de PSReadLine..." -ForegroundColor Cyan
if (Get-Command Get-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    Get-PSReadLineKeyHandler | 
        Where-Object { $_.Key -match '^(Ctrl|Alt)' -and $_.Key -notmatch '(?i)^Ctrl\+(c|v|x|z|y|a|Backspace|Delete|LeftArrow|RightArrow)$' } | 
        ForEach-Object { 
            Remove-PSReadLineKeyHandler -Chord $_.Key 
        }
    Write-Host "   Atajos de consola purgados." -ForegroundColor Green
}

Write-Host "`n2. Configurando Windows Terminal (settings.json)..." -ForegroundColor Cyan

$SettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$BackupPath = "$SettingsPath.backup"

if (-not (Test-Path $SettingsPath)) {
    Write-Warning "No se encontró el archivo settings.json."
    exit
}

Copy-Item -Path $SettingsPath -Destination $BackupPath -Force
$Content = Get-Content -Path $SettingsPath -Raw
$Payload = ""

# --- DEFINICIÓN DE ATAJOS ---
# Array de atajos personalizados: [Código ASCII, Modificador, Combinación de teclas]
# Modificador 5u = Ctrl | Modificador 6u = Ctrl + Shift
$Atajos = @(
    @{ Codigo = 59; Mod = "5u"; Tecla = "ctrl+;" }
    @{ Codigo = 44; Mod = "5u"; Tecla = "ctrl+," }
    @{ Codigo = 46; Mod = "5u"; Tecla = "ctrl+." }
    @{ Codigo = 32; Mod = "6u"; Tecla = "ctrl+shift+space" }
)

# Generar números del 0 al 9 para Ctrl+[Número]
for ($i = 48; $i -le 57; $i++) {
    $numero = ([char]$i).ToString()
    $Atajos += @{ Codigo = $i; Mod = "5u"; Tecla = "ctrl+$numero" }
}

# Generar letras de la A a la Z para Ctrl+Shift+[Letra]
# Si quieres mandar TODO a neovim (incluso copiar/pegar de la terminal), deja esta lista vacía: $Excluir = @()
$Excluir = @("c", "v", "t") 

for ($i = 65; $i -le 90; $i++) {
    $letra = ([char]$i).ToString().ToLower()
    if ($letra -notin $Excluir) {
        $Atajos += @{ Codigo = $i; Mod = "6u"; Tecla = "ctrl+shift+$letra" }
    }
}

# --- INYECCIÓN DINÁMICA ---
foreach ($atajo in $Atajos) {
    $tecla = $atajo.Tecla
    $codigo = $atajo.Codigo
    $mod = $atajo.Mod

    # Solo agregarlo si no existe ya
    if ($Content -notmatch '"keys":\s*"' + ([regex]::Escape($tecla)) + '"') {
        $Payload += @"
        {
            "command": { "action": "sendInput", "input": "\u001b[$codigo;$mod" },
            "keys": "$tecla"
        },
"@ + "`n"
        Write-Host "   [+] Se inyectará: $tecla" -ForegroundColor Yellow
    }
}

$Changed = $false

if ($Payload -ne "") {
    if ($Content -match '"actions":\s*\[') {
        $Content = $Content -replace '("actions":\s*\[)', "`$1`n$Payload"
        $Changed = $true
    } else {
        Write-Warning "No se encontró el bloque 'actions: [' en tu archivo."
    }
} else {
    Write-Host "   Todos los atajos inyectables ya estaban configurados." -ForegroundColor Green
}

# --- CONFIGURACIÓN VISUAL ---
$OldContent = $Content
$Content = $Content -replace '(?s)\s*"useAcrylic"\s*:\s*(true|false),?', ''
$Content = $Content -replace '(?s)\s*"opacity"\s*:\s*\d+,?', ''
$Content = $Content -replace '(?s)\s*"acrylicOpacity"\s*:\s*[\d\.]+,?', ''
$Content = $Content -replace '(?s)\s*"padding"\s*:\s*"[^"]*",?', ''
$Content = $Content -replace '(?s)\s*"scrollbarState"\s*:\s*"[^"]*",?', ''

# Forzar JetBrainsMono Nerd Font en cualquier configuración de fuente existente
$Content = $Content -replace '(?i)"face"\s*:\s*"[^"]+"', '"face": "JetBrainsMono Nerd Font"'

$VisualConfig = @"
            "useAcrylic": true,
            "opacity": 25,
            "acrylicOpacity": 0.25,
            "padding": "0",
            "scrollbarState": "hidden",
"@

if ($Content -match '"defaults":\s*\{') {
    $Content = $Content -replace '("defaults":\s*\{)', "`$1`n$VisualConfig"
    if ($OldContent -ne $Content) {
        $Changed = $true
        Write-Host "   [+] Configuración visual (Blur y Padding) inyectada." -ForegroundColor Yellow
    }
}

if ($Changed) {
    Set-Content -Path $SettingsPath -Value $Content -Encoding UTF8
    Write-Host "   Configuración actualizada con éxito." -ForegroundColor Green
    Write-Host "`n¡LISTO! Cierra y vuelve a abrir Windows Terminal." -ForegroundColor Cyan
}