# 🐘 PHP & Laravel Development Suite

[← Back to Wiki Index](../index.md) | [← Back to Languages Overview](../languages.md)

KrsVim provides a complete development environment for **PHP** and **Laravel** applications, including Blade template highlighting, component autocompletion, Xdebug debugging, and automated code formatting.

---

## 🛠️ Toolchain Summary

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| **Language Server (LSP)** | `intelephense` | Serves both `.php` and `.blade.php` files; loaded with Laravel, PHPUnit & core stubs and a 5 MB file-index limit for Laravel Composer metadata |
| **Formatters (Conform)** | `pint`, `php-cs-fixer`, `blade-formatter` | `pint` or `php-cs-fixer` for PHP; `blade-formatter` for `.blade.php` |
| **Treesitter Parsers** | `php`, `phpdoc`, `blade` | Syntax trees for highlighting, indentation, and structure |
| **Autocompletion** | `blink.cmp` + `blade-nav.nvim` | Intelephense LSP + Laravel routes, views, components, livewire, config, env, & translations |
| **Debug Adapter (DAP)** | `php-debug-adapter` (Xdebug) | Listening on port `9003` for web server & CLI debugging |
| **Local Vendor Scripts** | `vendor/bin` | Automatically prepended to `PATH` on launch & directory change for local Composer scripts |

`blade-nav.nvim` supplies Laravel-aware routes, views, component, Livewire, config, environment, and translation completions through Blink. Its unused `nvim-cmp` integration is disabled, so opening a Blade buffer does not produce a misleading `nvim-cmp not found` warning.

---

## 🧰 Ex Commands & Command Palette Actions

All commands below are registered in the **Command Palette** (`<C-S-p>` or `:CommandPalette`):

* `:PHPCheckTools` – Runs an environment check modal reporting PHP CLI, Composer, and WSL availability.
* `:BladeNavClearCache` – Clears cached Laravel routes, views, config, env, and translation entries.
* `:BladeNavToggleShowValues` – Toggles inline config/env/translation virtual text annotations.
* `:BladeNavInstallArtisanCommand` – Copies the helper artisan command to `app/Console/Commands/BladeNav.php`.
* `:FormatDocument` (or `:ConformFormat`) – Formats active `.php` or `.blade.php` buffer using Pint / PHP-CS-Fixer / blade-formatter.
* `:LanguageManager` – Opens the interactive UI manager to install or uninstall the PHP & Laravel language bundle.

---

## 🐞 Xdebug Debugger Profiles (`<F5>`)

Press `<F5>` (`:DapContinue`) to launch the Debug Adapter Protocol (DAP) launcher:

1. **`🐘 Listen for Xdebug (Vanilla PHP / Laravel Web / Herd)`**: Listens on port `9003` for incoming requests from web servers (Laravel Herd, Nginx, Apache, PHP built-in server).
2. **`📄 Launch Current Script (Vanilla PHP CLI)`**: Executes current `.php` file under PHP CLI with Xdebug enabled.
3. **`🚀 Debug Laravel Artisan Command`**: Prompts for artisan command (e.g., `migrate`, `queue:work`) and executes under Xdebug.
4. **`🌐 Debug Laravel App (artisan serve)`**: Launches `php artisan serve` with Xdebug enabled.

> 🔴 **Blade Breakpoints**: Breakpoints can be toggled inside `.blade.php` files (`<A-b>` or `:DapToggleBreakpoint`), and Xdebug will pause execution during view rendering.
