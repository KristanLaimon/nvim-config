# 🛠️ krsnvim.cli (Menú y Flags CLI)

`krsnvim.cli` simplifica la creación de herramientas de línea de comandos e interfaces de selección numérica en scripts de consola.

## Menú Numérico Interactivo

```lua
local cli = require("krs.lib.krsnvim.cli")

cli.menu("Elige una acción de build:", {
    "1. Compilar proyecto",
    "2. Ejecutar tests",
    "3. Limpiar directorio dist",
    "4. Salir"
}, function(choice, idx)
    print("Seleccionaste opción", idx, ":", choice)
end)
```

## Parseo de Argumentos

```lua
local cli = require("krs.lib.krsnvim.cli")

local args = cli.parse_args({ "--verbose", "--env=prod", "input.txt" })
-- args.flags.verbose = true
-- args.flags.env = "prod"
-- args.positional[1] = "input.txt"
```
