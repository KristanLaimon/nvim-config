# 🌐 krsnvim.fetch (Pure Lua Fetch API)

`krsnvim.fetch` proporciona una API basada en objetos tipo `fetch` para realizar peticiones HTTP y HTTPS en Lua puro sin depender de la herramienta CLI `curl` ni librerías externas.

---

## ⚡ Formas de Uso

```lua
local fetch = import("fetch")
-- O alternativamente:
-- local fetch = require("krs.lib.krsnvim.fetch")
```

### 1. Petición GET simple

```lua
local res = fetch("https://api.github.com/zen")

print("Status:", res.status) -- 200
print("OK:", res.ok)         -- true
print("Texto:", res:text())
```

### 2. Petición POST con Body JSON

```lua
local res = fetch.post("https://httpbin.org/post", {
    name = "Neovim",
    status = "Active"
})

local data = res:json()
print("Recibido:", data.json.name)
```

### 3. Petición con Query Params y Headers Personalizados

```lua
local res = fetch("https://api.example.com/search", {
    method = "GET",
    query = { q = "neovim", limit = 10 },
    headers = {
        ["Authorization"] = "Bearer MY_TOKEN",
        ["Accept"] = "application/json"
    }
})

print(res.headers["content-type"])
```

---

## 🛠️ API de Respuesta (`Response`)

Objeto retornado por `fetch(...)`:

- **`res.status`** `(number)`: Código de estado HTTP (ej: `200`, `404`, `500`).
- **`res.statusText`** `(string)`: Mensaje de estado (ej: `"OK"`, `"Not Found"`).
- **`res.ok`** `(boolean)`: `true` si el código de estado está entre `200` y `299`.
- **`res.headers`** `(table)`: Tabla con acceso insensible a mayúsculas/minúsculas para los encabezados.
- **`res.url`** `(string)`: URL de la petición realizada.
- **`res.body`** `(string)`: Cuerpo raw de la respuesta.
- **`res:text()`**: Retorna el cuerpo en formato `string`.
- **`res:json()`**: Decodifica automáticamente el cuerpo JSON a una tabla Lua.

---

## 🎯 Métodos Convenientes

- `fetch.get(url, opts)`
- `fetch.post(url, body, opts)`
- `fetch.put(url, body, opts)`
- `fetch.delete(url, opts)`
- `fetch.patch(url, body, opts)`
- `fetch.head(url, opts)`
