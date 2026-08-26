# 🧪 krsnvim.test (Vitest / Bun:test inspired Testing Library)

`krsnvim.test` es una librería de pruebas unitarias inspirada en **Vitest** y **bun:test** para scripts en Lua. Proporciona `describe`, `test`/`it` y `expect` de forma global en `_G` y como módulo exportado (`krsnvim.test`).

---

## ⚡ Formas de Uso

```lua
-- `describe`, `test`, `it` y `expect` están disponibles globalmente tras cargar krsnvim:
describe("Math Operations", function()
    it("works", function()
        expect(1 + 1).toBe(2)
    end)
end)

-- O importándolos explícitamente:
local t = import("test")
local describe, it, expect = t.describe, t.it, t.expect
```

---

## 📝 Estructura de un Test

```lua
local t = import("test")
local describe, it, expect = t.describe, t.it, t.expect

describe("Modulo de Usuarios", function()
    t.beforeEach(function()
        -- Setup antes de cada test
    end)

    it("calcula la edad correctamente", function()
        expect(2026 - 2000).toBe(26)
        expect({ name = "Lua" }).toEqual({ name = "Lua" })
        expect("neovim").toContain("vim")
    end)

    it("despacha errores en entradas invalidas", function()
        expect(function()
            error("Invalid ID")
        end).toThrow("Invalid ID")
    end)
end)

-- Ejecutar la suite
t.run()
```

---

## 🎯 Matchers Disponibles (`expect(val)`)

- **`.toBe(expected)`**: Igualdad estricta (`val == expected`).
- **`.toEqual(expected)`**: Comparación profunda (deep equality) para tablas y arreglos.
- **`.toBeTruthy()`**: Verifica que el valor sea `true` o no nulo.
- **`.toBeFalsy()`**: Verifica que el valor sea `false` o `nil`.
- **`.toBeNil()`** / **`.toBeNull()`** / **`.toBeUndefined()`**: Verifica que el valor sea `nil`.
- **`.toBeDefined()`**: Verifica que el valor no sea `nil`.
- **`.toContain(item)`**: Verifica si un string contiene un substring o una tabla contiene un elemento.
- **`.toHaveLength(len)`**: Verifica que `#val` sea igual a `len`.
- **`.toBeGreaterThan(n)`** / **`.toBeLessThan(n)`**: Comparación numérica.
- **`.toThrow(expected_err)`**: Verifica que una función lance una excepción.
- **`["not"]`** / **`.isNot`**: Inversión de cualquier matcher (ej: `expect(val).isNot.toBe(5)`).

---

## 🔄 Lifecycle Hooks

- **`t.beforeEach(fn)`**: Ejecuta `fn` antes de cada `test()` en la suite actual.
- **`t.afterEach(fn)`**: Ejecuta `fn` después de cada `test()`.
- **`t.beforeAll(fn)`**: Ejecuta `fn` una vez antes de iniciar la suite.
- **`t.afterAll(fn)`**: Ejecuta `fn` una vez al finalizar la suite.
