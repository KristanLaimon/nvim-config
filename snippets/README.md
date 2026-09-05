# 📋 Snippets Guide: How to Create Snippets & Identify Language Names

This guide explains how to create custom snippets in **KrsVim** using standard **VSCode JSON format** and how to find the exact `<lang>` filetype identifier Neovim expects for `<lang>.json` files inside the `snippets/` directory.

---

## 🔍 How to Identify Neovim's `<lang>` Identifier

Snippets in KrsVim are stored as `snippets/<lang>.json`. The `<lang>` string MUST match the exact **Neovim Filetype** (`vim.bo.filetype`), which is not always the same as the file extension.

### Method 1: Ask Neovim Directly (Recommended)
Open any file in Neovim and run one of these commands:
```vim
:set filetype?
```
or in Lua command line:
```vim
:lua print(vim.bo.filetype)
```
The output string (e.g. `typescriptreact`, `cs`, `sh`, `ps1`, `cpp`) is the exact name for `<lang>.json`.

### Method 2: Use the Built-in Snippet Manager Commands
KrsVim automatically auto-detects the current file's filetype identifier:
- Run `:KrsSnippetEdit` (or `:SnippetManager` → *Edit Snippets for Current Filetype*).
- Neovim will automatically resolve and open `snippets/<lang>.json` for the file you are currently editing.

---

## 🌐 Common Language Identifier Reference Table

| Language / Technology | File Extension(s) | Neovim `<lang>` Identifier | Snippet File Path |
| :--- | :--- | :--- | :--- |
| **Lua** | `.lua` | `lua` | `snippets/lua.json` |
| **TypeScript** | `.ts` | `typescript` | `snippets/typescript.json` |
| **TypeScript React (TSX)** | `.tsx` | `typescriptreact` | `snippets/typescriptreact.json` |
| **JavaScript** | `.js`, `.mjs`, `.cjs` | `javascript` | `snippets/javascript.json` |
| **JavaScript React (JSX)** | `.jsx` | `javascriptreact` | `snippets/javascriptreact.json` |
| **Python** | `.py` | `python` | `snippets/python.json` |
| **PHP** | `.php` | `php` | `snippets/php.json` |
| **Blade (Laravel)** | `.blade.php` | `blade` | `snippets/blade.json` |
| **Go** | `.go` | `go` | `snippets/go.json` |
| **C# / .NET** | `.cs` | `cs` | `snippets/cs.json` |
| **C** | `.c`, `.h` | `c` | `snippets/c.json` |
| **C++** | `.cpp`, `.hpp`, `.cc` | `cpp` | `snippets/cpp.json` |
| **Rust** | `.rs` | `rust` | `snippets/rust.json` |
| **Zig** | `.zig` | `zig` | `snippets/zig.json` |
| **Shell / Bash** | `.sh`, `.bash`, `.zsh` | `sh` | `snippets/sh.json` |
| **PowerShell** | `.ps1`, `.psm1`, `.psd1` | `ps1` | `snippets/ps1.json` |
| **HTML** | `.html`, `.htm` | `html` | `snippets/html.json` |
| **CSS** | `.css` | `css` | `snippets/css.json` |
| **SCSS / SASS** | `.scss`, `.sass` | `scss` | `snippets/scss.json` |
| **JSON / JSONC** | `.json`, `.jsonc` | `json`, `jsonc` | `snippets/json.json` |
| **YAML** | `.yaml`, `.yml` | `yaml` | `snippets/yaml.json` |
| **TOML** | `.toml` | `toml` | `snippets/toml.json` |
| **Markdown** | `.md` | `markdown` | `snippets/markdown.json` |
| **Dockerfile** | `Dockerfile`, `.dockerfile` | `dockerfile` | `snippets/dockerfile.json` |
| **SQL** | `.sql` | `sql` | `snippets/sql.json` |

---

## 📝 How to Create Snippets

### 1. Snippet File Structure
Every file in `snippets/` is a JSON object where **each top-level key is the snippet name** (displayed in completion menus). Include `"$schema": "./snippets.schema.json"` at the top for live IntelliSense, autocompletion, and validation while editing snippets.

```json
{
  "$schema": "./snippets.schema.json",

  "Console Log": {
    "prefix": "clog",
    "body": [
      "console.log('${1:label}:', ${2:value});",
      "${0}"
    ],
    "description": "Log value with label to browser/node console"
  }
}
```

### 2. Snippet Schema Property Reference

| Property | Required | Type | Description |
| :--- | :---: | :--- | :--- |
| `prefix` | ✅ | `string` or `string[]` | Trigger word(s) typed in the editor to activate completion |
| `body` | ✅ | `string` or `string[]` | Code content inserted on expansion (use array of strings for multi-line) |
| `description` | — | `string` | Explanation displayed in the doc detail popup |
| `scope` | — | `string` | Sub-language filter (optional) |

---

## ⚡ Body Formatting & Variables

### Tabstops (`$1`, `$2`, `$0`)
Navigate between tabstops using `<Tab>` (forward) and `<S-Tab>` (backward).
- `$1`, `$2`, `$3` define the cursor stopping sequence.
- `$0` defines the **final cursor position** after exiting all tabstops.

```json
"body": [
  "function ${1:fnName}(${2:params}) {",
  "\t${0}",
  "}"
]
```

### Placeholders (`${1:default_text}`)
Placeholders provide default text that can be edited immediately or accepted by pressing `<Tab>`.
```json
"body": "const [${1:state}, set${1/(.*)/${1:/capitalize}/}] = useState(${2:initialState});"
```

### Choice Pickers (`${1|option1,option2,option3|}`)
Renders a choices dropdown selection during snippet expansion.
```json
"body": "const mode = '${1|development,staging,production|}';"
```

### Useful VSCode Snippet Variables

| Variable | Output | Example |
| :--- | :--- | :--- |
| `$TM_FILENAME` | Active filename with extension | `main.ts` |
| `$TM_FILENAME_BASE` | Active filename without extension | `main` |
| `$TM_DIRECTORY` | Absolute path of current folder | `/home/user/project/src` |
| `$CLIPBOARD` | Current system clipboard content | *(pasted text)* |
| `$CURRENT_YEAR` | Current 4-digit year | `2026` |
| `$CURRENT_MONTH` | Current 2-digit month | `09` |
| `$LINE_COMMENT` | Language line comment symbol | `//` or `#` or `--` |

---

## 🛠️ Snippet Commands in KrsVim

You can manage all snippets directly from Neovim:

| Command | Palette Entry (`<C-S-p>`) | Action |
| :--- | :--- | :--- |
| `:SnippetManager` | **Snippets: Open Snippet Manager** | Opens interactive GUI menu |
| `:KrsSnippetEdit [lang]` | **Snippets: Edit Snippets for Language** | Opens `snippets/<lang>.json` |
| `:KrsSnippetAdd [lang]` | **Snippets: Add New Snippet** | Interactive prompt to create a snippet |
| `:KrsSnippetReload` | **Snippets: Reload Snippets** | Hot-reloads definitions into `blink.cmp` |

Saved snippet changes apply **immediately** upon saving (`:w`) without restarting Neovim!
