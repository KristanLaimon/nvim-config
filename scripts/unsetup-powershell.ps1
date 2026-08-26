<#
.SYNOPSIS
Deshace las configuraciones inyectadas para Neovim.
Elimina iterativamente todos los Ctrl+Shift+algo generados.
#>

Write-Host "1. Restaurando atajos de PSReadLine..." -ForegroundColor Cyan
if (Get-Module -Name PSReadLine) {
    Remove-Module PSReadLine
    Import-Module PSReadLine
    Write-Host "   Atajos de PSReadLine restaurados." -ForegroundColor Green
}

Write-Host "`n2. Restaurando Windows Terminal (settings.json)..." -ForegroundColor Cyan

$SettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$BackupPath = "$SettingsPath.undo_backup"

if (-not (Test-Path $SettingsPath)) {
    Write-Warning "No se encontró settings.json."
    exit
}

Copy-Item -Path $SettingsPath -Destination $BackupPath -Force
$Content = Get-Content -Path $SettingsPath -Raw
$OriginalContent = $Content

# Recreamos la misma lista para saber qué buscar y destruir
$Atajos = @(
    @{ Codigo = 59; Mod = "5u"; Tecla = "ctrl+;" }
    @{ Codigo = 44; Mod = "5u"; Tecla = "ctrl+," }
    @{ Codigo = 46; Mod = "5u"; Tecla = "ctrl+." }
    @{ Codigo = 32; Mod = "6u"; Tecla = "ctrl+shift+space" }
)

# Agregamos TODAS las letras (sin excluir ninguna, para limpiar todo por si acaso)
for ($i = 65; $i -le 90; $i++) {
    $letra = ([char]$i).ToString().ToLower()
    $Atajos += @{ Codigo = $i; Mod = "6u"; Tecla = "ctrl+shift+$letra" }
}

# --- ELIMINACIÓN DINÁMICA ---
foreach ($atajo in $Atajos) {
    $tecla = $atajo.Tecla
    $codigo = $atajo.Codigo
    $mod = $atajo.Mod

    # Construimos la expresión regular exacta para este bloque JSON
    $EscapedKey = [regex]::Escape($tecla)
    $Pattern = '(?s)\s*\{\s*"command":\s*\{\s*"action":\s*"sendInput",\s*"input":\s*"\\u001b\[' + $codigo + ';' + $mod + '"\s*\},\s*"keys":\s*"' + $EscapedKey + '"\s*\},?'

    if ($Content -match '"keys":\s*"' + $EscapedKey + '"') {
        $Content = $Content -replace $Pattern, ''
        Write-Host "   [-] Atajo eliminado: $tecla" -ForegroundColor Yellow
    }
}

# --- ELIMINACIÓN DE CONFIGURACIÓN VISUAL ---
$Content = $Content -replace '(?s)\s*"useAcrylic"\s*:\s*(true|false),?', ''
$Content = $Content -replace '(?s)\s*"opacity"\s*:\s*\d+,?', ''
$Content = $Content -replace '(?s)\s*"acrylicOpacity"\s*:\s*[\d\.]+,?', ''
$Content = $Content -replace '(?s)\s*"padding"\s*:\s*"[^"]*",?', ''
$Content = $Content -replace '(?s)\s*"scrollbarState"\s*:\s*"[^"]*",?', ''

if ($OriginalContent -ne $Content) {
    Set-Content -Path $SettingsPath -Value $Content -Encoding UTF8
    Write-Host "   Configuración limpiada con éxito (atajos y visual)." -ForegroundColor Green
    Write-Host "`n¡LISTO! Cierra y vuelve a abrir Windows Terminal." -ForegroundColor Cyan
} else {
    Write-Host "   No se encontraron configuraciones de Neovim que eliminar." -ForegroundColor Green
}