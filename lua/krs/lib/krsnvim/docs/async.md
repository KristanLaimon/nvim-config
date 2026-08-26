# ⚡ krsnvim.async (Concurrency & Multi-Threading Suite)

`krsnvim.async` (también importable como `concurrent` o `parallel`) añade soporte de **concurrencia**, **paralelismo multinúcleo en OS threads** y primitivas **async/await** para scripts Neovim (`krsnvimscript`).

---

## 💡 Ejemplos de uso rápido

### 1. Ejecutar 2 cosas "al mismo tiempo" (Concurrencia con Callback o Corrutina)

```lua
local async = import("async") -- o import("concurrent") / import("parallel")

-- Opción A: Con callback
async.parallel({
  function()
    async.sleep(100)
    return "Tarea 1 completada"
  end,
  function()
    async.sleep(50)
    return "Tarea 2 completada"
  end
}, function(err, results)
  print(results[1]) -- "Tarea 1 completada"
  print(results[2]) -- "Tarea 2 completada"
end)

-- Opción B: Async / Await sintaxis limpia
async.run(function()
  local results = async.await(async.parallel({
    function() return "Proceso A" end,
    function() return "Proceso B" end,
  }))
  print("Resultados:", results[1], results[2])
end)
```

---

### 2. Paralelismo Multinúcleo (OS Worker Threads real)

Para tareas pesadas de cálculo CPU sin congelar la interfaz UI de Neovim:

```lua
async.thread(function(n)
  -- Esta función se ejecuta en un thread separado del sistema operativo
  local sum = 0
  for i = 1, n do sum = sum + i end
  return sum
end, { 1000000 }, function(err, total)
  print("Suma pesada calculada en background thread:", total)
end)
```

---

### 3. Mapeo Concurrente con Límite (`async.map` / `async.parallel_map`)

```lua
local urls = { "url1", "url2", "url3", "url4", "url5" }

async.map(urls, function(url)
  return fetch.get(url):text()
}, { concurrency = 2 }, function(err, responses)
  print("Procesadas", #responses, "respuestas concurrentemente")
end)
```

---

### 4. Canales de Mensajes Go-style (`async.channel`)

```lua
local ch = async.channel()

-- Enviar mensaje al canal
ch:send("Datos desde tarea A")

-- Recibir mensaje
local msg = ch:receive()
print("Recibido:", msg)
```

---

## 📑 API Reference

| Método | Descripción |
| :--- | :--- |
| `async.parallel(tasks, [cb])` | Ejecuta un array de tareas concurrentemente y devuelve sus resultados en orden. |
| `async.race(tasks, [cb])` | Ejecuta tareas concurrentemente y resuelve con el **primer** resultado en terminar. |
| `async.thread(fn, args, [cb])` | Ejecuta `fn` en un Worker Thread OS background (`vim.uv.new_work`). |
| `async.map(items, worker_fn, [opts], [cb])` | Mapea elementos concurrentemente con opción `concurrency = N`. |
| `async.series(tasks, [cb])` | Ejecuta tareas secuencialmente en serie. |
| `async.waterfall(tasks, [cb])` | Ejecuta tareas en serie pasando los valores de retorno de una tarea a la siguiente. |
| `async.sleep(ms, [cb])` | Sleep no-bloqueante usando temporizador Libuv. |
| `async.run(fn)` | Ejecuta una corrutina gestionada permitiendo `async.await(...)`. |
| `async.await(task)` | Espera el resultado de un `Task` / promesa dentro de `async.run()`. |
| `async.channel([capacity])` | Crea un canal de comunicación thread-safe / corrutina. |
