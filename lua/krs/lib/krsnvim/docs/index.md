# 🦊 krsnvimscript Wiki & Documentation

Bienvenido a la documentación interactiva de **krsnvimscript** (`krsnvim.*`).

**krsnvimscript** es una suite de utilidades diseñada para facilitar la creación de scripts de consola, automatización de tareas, scripts de build y herramientas CLI en Lua utilizando Neovim.

---

## 🎹 Atajos de Teclado Principales

- **`Ctrl + ,`** (`<C-,>`): Ejecuta y guarda inmediatamente el script `.lua` actual dentro de Neovim o abre Launch Profiles.
- **`Ctrl + Shift + ,`** (`<C-S-,>`): Abre esta ventana flotante de **Documentación Wiki**.

---

## 📦 Módulos Disponibles en `krsnvim.*`

1. **`import(...)`**: Carga rápida de módulos y archivos JSON, YAML o TOML.
2. **`krsnvim.terminal`** (`$ "command"`): Ejecución de comandos de terminal cross-platform.
3. **`krsnvim.json`**: Parser, encoder y operaciones de archivo JSON.
4. **`krsnvim.yaml`**: Parser y encoder YAML nativo en Lua.
5. **`krsnvim.toml`**: Parser y encoder TOML nativo en Lua.
6. **`krsnvim.cli`**: Parseo de argumentos `--help` y menús numéricos interactivos.
7. **`krsnvim.fs`**: Helper para lectura, escritura y manipulación de archivos.
8. **`krsnvim.fetch`**: API tipo `fetch` para peticiones HTTP/HTTPS en Lua puro (sin curl).
9. **`krsnvim.test`**: Librería de testing tipo Vitest / Bun:test (`describe`, `test`, `expect`).
10. **`krsnvim.krsnvimtranspiler`**: Transpilador automático de `.krsnvim` a scripts equivalentes `.sh` (Bash) y `.ps1` (PowerShell) con CLI nativos.
11. **`krsnvim.async`** (`concurrent`, `parallel`): Concurrencia, paralelismo multinúcleo en OS threads y primitivas async/await.

---

## ⚡ Ejemplo Rápido

```lua
local $ = require("krs.lib.krsnvim.terminal")
local json = import("krsnvim.json")
local config = import("config.yaml")

print("=== Running Build Script ===")
local res = $("git status")
print(res.stdout)
```
