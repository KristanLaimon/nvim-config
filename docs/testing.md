# 🧪 Testing

[← Back to Wiki Index](index.md)

This configuration has a test suite. It exists because a Neovim config fails at
the worst possible moment — on startup, in the middle of something else — and a
typo in a plugin file is invisible until then.

---

## 🏃 Running the tests

| Command | What it checks | Speed |
| :--- | :--- | :--- |
| `nvim -l tests/syntax_check.lua` | Every `.lua` file parses | instant |
| `nvim -l tests/run.lua` | Unit specs, no plugins loaded | ~1s |
| `nvim -l tests/run.lua tasks` | Only specs whose name contains "tasks" | ~1s |
| `nvim --headless -S tests/integration/run.lua` | Specs that need the real editor | a few seconds |
| `:KrsTest` | The unit specs, from inside the editor | ~1s |
| `:KrsTest git` | Filtered, from inside the editor | ~1s |

All of them exit non-zero on failure, so they work unchanged in CI or a git hook.

---

## 🗂️ Layout

```
tests/
├── run.lua              Unit runner: loads every tests/spec/*_spec.lua, prints one summary
├── syntax_check.lua     Compiles (never runs) every Lua file in the repository
├── spec/                Unit specs -- pure logic, no plugins loaded (one file per feature)
├── integration/         Specs that need plugins and a real UI (run.lua + a handful of *_spec.lua)
└── krsnvimscript/       .krsnvim example scripts used as fixtures for lua/krsnvim/tests
```

`tests/spec/` has one `*_spec.lua` per feature (`tasks_spec.lua`, `git_status_spec.lua`,
`wiki_modal_spec.lua`, and so on) — the filename always matches the module it pins down, so
if you're editing `lua/plugins/krs/tasks.lua`, its test is `tests/spec/tasks_spec.lua`. This
list grows constantly, so don't trust a snapshot of it here — `nvim -l tests/run.lua` prints
every spec currently in the suite, and `ls tests/spec/` shows the files directly.

The `krsnvimscript` library keeps its own suite in `lua/krsnvim/tests/`, run with
`require("krs.lib.krsnvim.tests").run_all()`.

---

## ✍️ Writing a spec

Both runners use the same framework, `krsnvim.test` — the Vitest-style
`describe` / `it` / `expect` already shipped with the krsnvimscript library.

```lua
-- ============================================================================
-- tests/spec/my_feature_spec.lua -- What this file pins down.
-- ============================================================================
-- Why these particular cases matter.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local feature = require("krs.core.path")

describe("krs.core.path.normalize", function()
    it("converts backslashes to forward slashes", function()
        expect(feature.normalize([[C:\a\b]])).toBe("C:/a/b")
    end)
end)
```

Available matchers: `toBe`, `toEqual` (deep), `toBeTruthy`, `toBeFalsy`,
`toBeNil`, `toBeDefined`, `toContain`, `toHaveLength`, `toBeGreaterThan`,
`toBeGreaterThanOrEqual`, `toBeLessThan`, `toBeLessThanOrEqual`, `toThrow`, and
`not_` to invert any of them (`expect(x).not_.toBe(y)` — `not` is a Lua keyword,
so it cannot be used with a dot).

Lifecycle hooks: `beforeEach`, `afterEach`, `beforeAll`, `afterAll`.

### Rules

1. **Specs must be side-effect free.** No keymaps, no writes outside
   `vim.fn.tempname()`, no changing the working directory. Clean up in
   `afterEach`.
2. **Unit specs must not need a plugin.** If it needs telescope or nvim-dap, it
   belongs in `tests/integration/`, which boots the full config.
3. **Test the contract, not the implementation.** A spec that breaks whenever the
   code is reorganized is worse than no spec.
4. **Name the case, not the function.** `it("returns the fallback for malformed
   JSON")` beats `it("works")`.

---

## 🎯 What is covered

A sample of what's pinned down, to show the *kind* of thing a spec checks (see
[Layout](#🗂️-layout) above for how to find the full, current list):

| Area | Spec | What it pins |
| :--- | :--- | :--- |
| Paths | `core_path_spec` | Drive letters, trailing slashes, case rules, relative paths |
| Project config | `core_project_spec` | `.krsnvim` → `.krslocal` → `.nvimkrs` lookup ORDER |
| Task runner | `tasks_spec` | Chain resolution, `depends_on`, discovery, legacy files |
| Git | `git_status_spec`, `git_diff_spec` | Porcelain parsing, diff formatting and highlight tags |
| WSL | `wsl_spec` | UNC path parsing and the `wsl.exe --cd` command |
| Wiki keymaps | `wiki_modal_spec` | The open key doesn't collide with another feature's key, and always has a non-Ctrl+Shift fallback |
| Public surface | `commands_spec` (integration) | Every user command and keymap still registers |
| Debug adapters | `dap_adapters_spec` (integration) | Every language still registers its configurations |

UI-heavy flows (pickers, modals in use, terminal execution) are deliberately not
covered: they need a driven UI, and the checks would be brittle. The logic behind
them is factored out into `lua/krs/`, which IS covered.

---

## 🔧 "I edited a plugin file — do I need a test?"

Short version: if the change is logic (parsing, ordering, a conditional, a keymap
that must not collide with another one), yes — a few lines in the matching spec
pays for itself the first time a later edit breaks it silently. If it's pure UI
layout (window size, border color, title text), skip it; see the note above.

1. **Find its spec.** Filename mirrors the module: editing
   `lua/plugins/krs/tasks.lua` → open `tests/spec/tasks_spec.lua`. Nothing there
   yet? Copy the shape from [Writing a spec](#✍️-writing-a-spec) above and create
   `tests/spec/<module>_spec.lua` — `tests/run.lua` picks up every file in that
   folder automatically, no registration step.
2. **Write the case in plain language first**, then the assertion:
   `it("does not share its open key with LSP go-to-definition", ...)` reads as a
   sentence on its own, before you ever look at the `expect(...)` line.
3. **Run just that spec while you iterate**: `nvim -l tests/run.lua tasks` (or
   `:KrsTest tasks` inside the editor) filters by filename substring, so you're
   not waiting on the whole suite every save.
4. **Run everything once before you're done**: `nvim -l tests/run.lua` — a change
   in a shared module (`lua/krs/core/*.lua`) can break a spec for a completely
   different feature that happens to depend on it.
