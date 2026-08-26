# 🖨️ `krsnvim.console`

Human-readable Console Logging, Object Inspection, and Pretty-JSON Debugging library for `krsnvimscript`.

---

## 🚀 Quick Usage

```lua
require("krs.lib.krsnvim")

-- 1. Use global console or import("console")
console.log("User Data:", { name = "Kristan", role = "Developer", tags = { "lua", "nvim" } })

-- 3. Directly call console(...) or console.dir(...)
console({ status = "ok", count = 42 })

-- 4. Level-based log functions
console.info("Server started on port 8080")
console.warn("High memory usage detected")
console.error("Failed to connect to database")
console.debug("Session payload:", { token = "xyz" })
```

---

## 🛠️ API Reference

### `console.log(...)` / `console(...)` / `krsnvim.debug.log(...)`
Accepts any number of arguments. Strings and numbers are printed space-separated; any tables/objects are automatically pretty-printed as indented JSON.

```lua
console.log("Product:", { id = 101, title = "Widget" }, "In stock:", true)
```

### `console.dir(obj)` / `console.dump(obj)`
Pretty-prints an object or table to the console formatted as multi-line indented JSON.

```lua
console.dir({ config = { mode = "debug", port = 3000 } })
```

### `console.json(obj, indent)`
Returns a human-readable JSON string representation of `obj` without printing it.

```lua
local str = console.json({ a = 1, b = 2 }, "  ")
```

### `console.info(...)` / `console.warn(...)` / `console.error(...)` / `console.debug(...)`
Log methods prefixed with level badges (`ℹ️ [INFO]`, `⚠️ [WARN]`, `❌ [ERROR]`, `🐛 [DEBUG]`).
