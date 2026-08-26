# 📤 krsnvimtranspiler (Transpiler to .sh and .ps1)

`krsnvimtranspiler` transprueba scripts `.krsnvim` escritos en Lua a scripts nativos equivalente 100% en Bash (`.sh`) y PowerShell (`.ps1`).

Permite que tus scripts locales en Neovim se conviertan en scripts ejecutables en servidores Linux, CI/CD runners o maquinas Windows sin necesidad de empaquetar Neovim ni runtime de Lua extra.

---

## 🛠️ Comandos de Neovim

- `:KrsExport [sh|ps1|both] [output_file]` - Exporta el archivo `.krsnvim` activo a `.sh`, `.ps1` o ambos.
- `:KrsExportSh` - Exporta el archivo `.krsnvim` activo a `.sh` (Bash).
- `:KrsExportPs1` - Exporta el archivo `.krsnvim` activo a `.ps1` (PowerShell).

---

## 💻 Ejemplo de Uso en Lua

```lua
local transpiler = import("krsnvimtranspiler")

-- Convertir directamente un archivo
transpiler.export_both("build.krsnvim")

-- O convertir snippets programmaticamente
local bash_script = transpiler.to_sh([[
    function download_data(url)
        print("Downloading from:", url)
        local res = fetch.json(url)
        return res
    end

    local fs = import("fs")
    fs.mkdir("dist")
    download_data("https://api.example.com/data")
]])

print(bash_script)
```

---

## 🔄 Mapeo Completo de Funciones a CLI Nativos

| krsnvim (Lua) | Bash (`.sh`) | PowerShell (`.ps1`) |
|---|---|---|
| `function fn(a, b)` | `fn() { local a="$1"; local b="$2";` | `function fn($a, $b) {` |
| `print(...)` | `echo ...` | `Write-Host ...` |
| `assert(cond, msg)` | `[ cond ] &#124;&#124; { echo msg >&2; exit 1; }` | `if (-not (cond)) { throw msg }` |
| `error(msg)` | `echo msg >&2; exit 1` | `throw msg` |
| `fs.exists(path)` | `[ -e "path" ]` | `Test-Path "path"` |
| `fs.mkdir(path)` | `mkdir -p "path"` | `New-Item -ItemType Directory -Force ...` |
| `fs.read(path)` | `cat "path"` | `Get-Content -Raw "path"` |
| `fs.write(path, content)` | `echo "content" > "path"` | `Set-Content -Path "path" -Value ...` |
| `fetch.get(url)` | `curl -sSL "url"` | `Invoke-WebRequest -Uri "url"` |
| `fetch.json(url)` | `curl -sSL "url"` | `Invoke-RestMethod -Uri "url"` |
| `yaml.load(file)` | `python3 -c "import yaml..." file` | `Get-Content -Raw file &#124; ConvertFrom-Json` |
| `json.encode(obj)` | `echo "obj" &#124; jq -c .` | `@(...) &#124; ConvertTo-Json -Compress` |
| `json.load(file)` | `cat "file" &#124; jq .` | `Get-Content -Raw "file" &#124; ConvertFrom-Json` |
| `$ "cmd"` | `cmd` | `cmd` |
| `for i = 1, 10 do` | `for ((i=1; i<=10; i++)); do` | `for ($i=1; $i -le 10; $i++) {` |
| `for _, item in ipairs(list) do` | `for item in "${list[@]}"; do` | `foreach ($item in $list) {` |
| `while cond do` | `while [ cond ]; do` | `while (cond) {` |
