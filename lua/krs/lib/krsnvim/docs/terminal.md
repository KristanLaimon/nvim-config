# 💻 krsnvim.terminal ($)

El módulo `krsnvim.terminal` permite ejecutar comandos del sistema operativo usando sintaxis callable simple.

## Uso Básico

```lua
local $ = require("krs.lib.krsnvim.terminal")

-- Ejecutar comando directo
local res = $("echo Hello World")

print("Exit Code:", res.code)
print("Output:", res.stdout)
print("Is OK?:", res.ok)
```

## Detección Automática de SO

- **Windows**: Utiliza `cmd.exe /C <command>`
- **Linux / macOS**: Utiliza `bash -c <command>`

## Estructura del Resultado

`$(cmd)` retorna una tabla con los siguientes campos:
- `code`: (number) Código de salida (0 = éxito).
- `ok`: (boolean) `true` si el código de salida es 0.
- `stdout`: (string) Salida estándar capturada.
- `stderr`: (string) Mensajes de error.
- `output`: (string) Alias de `stdout`.
