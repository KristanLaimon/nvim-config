# 🌬️ Tailwind Organizer (`plugins.krs.editor.tailwind_organizer`)

[← Back to Wiki Index](index.md)

Sorts `class="…"` / `className="…"` attributes into stable, readable rows — on save, or on demand.

The point isn't alphabetising for its own sake: it's that a 30-class element becomes diffable and scannable, with layout on one row, looks on the next, and each breakpoint on its own.

---

## ⌨️ Shortcuts & commands

| Shortcut / Command | Action |
| :--- | :--- |
| `<leader>tw` / `:TailwindOrganize` | Organize the current buffer now |
| `<leader>tt` / `:TailwindOrganizerToggle` | Toggle organize-on-save |
| `:TailwindOrganizerStatus` | Report whether it's active |
| `:TailwindOrganizerReload` | Hot-reload the module in-memory (for editing the rules) |

All three of the first commands also register themselves into the [Command Palette](command-palette.md) under the **Tailwind** category.

---

## 📐 The row layout

| Row | Contents | Order |
| :--- | :--- | :--- |
| **1** | Size, position and core layout — `flex`, `grid`, `absolute`, `w-*`, `h-*`, `z-*`, `items-*`, `justify-*`, display and position values | Sorted, layout keywords first |
| **2** | Aesthetics — colours, typography, padding/margin, borders, text alignment | Alphabetical |
| **3+** | One row per breakpoint — `sm:`, `md:`, `lg:`, `xl:`, `2xl:`, then `max-*`, then `portrait` / `landscape` | Breakpoint order, alphabetical within each |

Example:

```html
<div class="absolute flex h-12 w-full items-center justify-between z-10
            bg-slate-900 border-b border-slate-700 px-4 text-sm text-slate-200
            sm:px-6
            lg:h-16 lg:px-8">
```

### When it stays on one line

Multi-row formatting only kicks in when it earns its keep:

- fewer than `min_classes_for_multiline` classes (default **9**) → single line
- only one row would be produced, and `force_multiline` is off (default) → single line

Both knobs live in `M.config` at the top of the module, along with `auto_format_on_save`.

---

## 🧠 How it edits

It rewrites the buffer as **one full-text pass**, not line by line — a class attribute can already span several lines, so a per-line transform can't see it.

Because the rewrite can add or remove lines above the cursor, the module counts the byte offsets of the cursor line and the top visible line *before* organizing, then shifts the saved view by however many lines were inserted above each and restores it with `winrestview`. Cursor and scroll position survive a save that reflows the file above you.

Nothing is written when the organized text is identical to what's there — `:TailwindOrganize` says "already organized" instead of dirtying the buffer.

---

## ⚙️ On save

A `BufWritePre` autocmd (pattern `*`) runs the organizer when `M.enabled` is true — every filetype, since the attribute pattern is what decides whether there's anything to do.

Toggling with `<leader>tt` is session-scoped, not persisted — a file you don't want reflowed is one `<leader>tt` away, and the next session comes back on.
