<#
.SYNOPSIS
Configura el entorno para Neovim generando dinámicamente atajos
para Ctrl+;, Ctrl+,, Ctrl+., Ctrl+Shift+[0-9] (Environments),
Ctrl+[0-9] (Tasks) y TODOS los Ctrl+Shift+[A-Z] + Space.
Hijackea atajos nativos de Windows Terminal (como switchToTab0..8)
para que fluyan directamente hacia Neovim.
#>

Write-Host "1. Limpiando atajos de PSReadLine..." -ForegroundColor Cyan
if (Get-Command Get-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    Get-PSReadLineKeyHandler | 
        Where-Object { 
            ($_.Key -match '^(Ctrl|Alt)' -and $_.Key -notmatch '(?i)^Ctrl\+(c|v|x|z|y|a|Backspace|Delete|LeftArrow|RightArrow)$') -or
            $_.Key -match '(?i)^Ctrl\+Shift\+[0-9]'
        } | 
        ForEach-Object { 
            Remove-PSReadLineKeyHandler -Chord $_.Key 
        }
    Write-Host "   Atajos de consola purgados." -ForegroundColor Green
}

Write-Host "`n2. Configurando Windows Terminal (settings.json)..." -ForegroundColor Cyan

$SettingsPaths = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
) | Where-Object { Test-Path $_ }

if ($SettingsPaths.Count -eq 0) {
    Write-Warning "No se encontró ningún archivo settings.json de Windows Terminal."
    exit
}

# --- DEFINICIÓN DE ATAJOS ---
# Array de atajos personalizados: [Código ASCII, Modificador, Combinación de teclas]
# Modificador 5u = Ctrl | Modificador 6u = Ctrl + Shift
$Atajos = @(
    @{ Codigo = 59; Mod = "5u"; Tecla = "ctrl+;" }
    @{ Codigo = 44; Mod = "5u"; Tecla = "ctrl+," }
    @{ Codigo = 46; Mod = "5u"; Tecla = "ctrl+." }
    @{ Codigo = 32; Mod = "6u"; Tecla = "ctrl+shift+space" }
    @{ Codigo = 47; Mod = "5u"; Tecla = "ctrl+/" }
    @{ Codigo = 63; Mod = "6u"; Tecla = "ctrl+shift+/" }
    @{ Codigo = 63; Mod = "5u"; Tecla = "ctrl+?" }
    @{ Codigo = 31; Mod = "5u"; Tecla = "ctrl+_" }
)

# Generar números del 0 al 9 para Ctrl+[Número] (Mod 5u) y Ctrl+Shift+[Número] (Mod 6u)
for ($i = 48; $i -le 57; $i++) {
    $numero = ([char]$i).ToString()
    $Atajos += @{ Codigo = $i; Mod = "5u"; Tecla = "ctrl+$numero" }
    $Atajos += @{ Codigo = $i; Mod = "6u"; Tecla = "ctrl+shift+$numero" }
}

# Generar letras de la A a la Z para Ctrl+Shift+[Letra]
$Excluir = @("c", "v", "t") 

for ($i = 65; $i -le 90; $i++) {
    $letra = ([char]$i).ToString().ToLower()
    if ($letra -notin $Excluir) {
        $Atajos += @{ Codigo = $i; Mod = "6u"; Tecla = "ctrl+shift+$letra" }
    }
}

foreach ($SettingsPath in $SettingsPaths) {
    Write-Host "`n   Procesando: $SettingsPath" -ForegroundColor Cyan
    $BackupPath = "$SettingsPath.backup"
    Copy-Item -Path $SettingsPath -Destination $BackupPath -Force
    $Content = Get-Content -Path $SettingsPath -Raw
    $Payload = ""
    $Changed = $false

    # --- INYECCIÓN Y HIJACK DINÁMICO ---
    foreach ($atajo in $Atajos) {
        $tecla = $atajo.Tecla
        $codigo = $atajo.Codigo
        $mod = $atajo.Mod
        $escapedKey = [regex]::Escape($tecla)

        $patternExisting = '(?s)\{\s*"command":\s*[^}]+,\s*"keys":\s*"' + $escapedKey + '"\s*\},?'
        $patternSendInput = '(?s)\{\s*"command":\s*\{\s*"action":\s*"sendInput",\s*"input":\s*"\\u001b\[' + $codigo + ';' + $mod + '"\s*\},\s*"keys":\s*"' + $escapedKey + '"\s*\}'

        if ($Content -match $patternSendInput) {
            # Ya configurado correctamente
            continue
        }

        if ($Content -match '"keys":\s*"' + $escapedKey + '"') {
            # Existe pero con otra acción (como switchToTab de Windows Terminal) -> Hijack!
            $newAction = @"
        {
            "command": { "action": "sendInput", "input": "\u001b[$codigo;$mod" },
            "keys": "$tecla"
        },
"@
            $Content = $Content -replace $patternExisting, $newAction
            $Changed = $true
            Write-Host "   [HIJACK] Overriding shortcut: $tecla -> sendInput \u001b[$codigo;$mod" -ForegroundColor Yellow
        } else {
            # No existe -> Inyectar al principio de actions
            $Payload += @"
        {
            "command": { "action": "sendInput", "input": "\u001b[$codigo;$mod" },
            "keys": "$tecla"
        },
"@ + "`n"
            Write-Host "   [+] Injecting: $tecla" -ForegroundColor Yellow
        }
    }

    if ($Payload -ne "") {
        if ($Content -match '"actions":\s*\[') {
            $Content = $Content -replace '("actions":\s*\[)', "`$1`n$Payload"
            $Changed = $true
        } else {
            Write-Warning "No se encontro el bloque 'actions: [' en tu archivo."
        }
    }

    # --- CONFIGURACION VISUAL ---
    $OldContent = $Content
    $Content = $Content -replace '(?s)\s*"useAcrylic"\s*:\s*(true|false),?', ''
    $Content = $Content -replace '(?s)\s*"opacity"\s*:\s*\d+,?', ''
    $Content = $Content -replace '(?s)\s*"acrylicOpacity"\s*:\s*[\d\.]+,?', ''
    $Content = $Content -replace '(?s)\s*"padding"\s*:\s*"[^"]*",?', ''
    $Content = $Content -replace '(?s)\s*"scrollbarState"\s*:\s*"[^"]*",?', ''

    # Forzar JetBrainsMono Nerd Font en cualquier configuracion de fuente existente
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
            Write-Host "   [+] Configuracion visual (Blur y Padding) inyectada." -ForegroundColor Yellow
        }
    }

    if ($Changed) {
        Set-Content -Path $SettingsPath -Value $Content -Encoding UTF8
        Write-Host "   Configuracion actualizada con exito en $SettingsPath." -ForegroundColor Green
    } else {
        Write-Host "   Todos los atajos ya estaban correctamente configurados." -ForegroundColor Green
    }
}

Write-Host "`n[OK] Listo! Cierra y vuelve a abrir Windows Terminal." -ForegroundColor Cyan