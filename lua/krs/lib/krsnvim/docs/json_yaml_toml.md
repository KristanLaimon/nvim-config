# 📄 Formatos de Datos: JSON, YAML, TOML

`krsnvim` proporciona parsers y serializadores unificados para los formatos de configuración y datos más populares.

## JSON (`krsnvim.json`)

```lua
local json = require("krs.lib.krsnvim.json")

-- Parsear y serializar
local data = json.decode('{"name": "krs", "version": 1}')
local str = json.encode(data)

-- Leer y guardar archivos
local config = json.load("config.json")
json.save("out.json", { status = "ok" })
```

## YAML (`krsnvim.yaml`)

```lua
local yaml = require("krs.lib.krsnvim.yaml")

local data = yaml.load("settings.yaml")
yaml.save("output.yaml", { app = "nvim", mode = "dark" })
```

## TOML (`krsnvim.toml`)

```lua
local toml = require("krs.lib.krsnvim.toml")

local data = toml.load("Cargo.toml")
print(data.package and data.package.name)
```
