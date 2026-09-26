# 🎯 C# / .NET / Blazor Development Suite

[← Back to Wiki Index](../index.md) | [← Back to Languages Overview](../languages.md)

KrsVim provides a full **C#**, **.NET**, and **Blazor** development environment, supporting solution files (`.sln`), project files (`.csproj`), NuGet package management, formatting with CSharpier, and debugging via `netcoredbg`.

---

## 🛠️ Toolchain Summary

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| **Language Server (LSP)** | `omnisharp`, `lemminx` | `omnisharp` for C# source files; `lemminx` for XML validation in `.csproj`, `.props`, `.targets` |
| **Formatters (Conform)** | `csharpier` | Code formatting for `.cs` files |
| **Treesitter Parsers** | `c_sharp` | Syntax highlighting for C# and Razor/Blazor constructs |
| **Autocompletion** | `blink.cmp` | IntelliSense completion, Roslyn analyzers, and auto-imports |
| **Debug Adapter (DAP)** | `netcoredbg` (`coreclr`) | Debug adapter for .NET Core / .NET 8/9, Blazor Server, and CLI apps |
| **Project Utilities** | `dotnet_creator`, `nuget` | Interactive project template creator and NuGet package search |

---

## 🧰 Ex Commands & Command Palette Actions

Accessible via **Command Palette** (`<C-S-p>` / `:CommandPalette`):

* `:CsharpNewType` – Reopen the type template popup for the current empty `.cs` buffer.
* `:DotnetNew` – Interactive `.NET` project creator (`dotnet new` template picker).
* `:NugetManager` – Open NuGet package manager to search and add package references to `.csproj`.
* `:FormatDocument` – Format active `.cs` file using CSharpier or LSP fallback.
* `:LanguageManager` – Install or uninstall the C# / .NET language bundle.

---

## New C# files

Creating a `.cs` file through Neo-tree, the desktop file explorer, or `:edit NewType.cs`
opens a floating template menu. Opening an empty `.cs` file created by another tool
also offers the menu once per buffer. Choose with `j`/`k` or the arrow keys and press Enter.
Escape cancels; `:CsharpNewType` (also in the Command Palette) opens it again.

Templates include class, interface, record, struct, record struct, enum, static class,
abstract class, sealed class, delegate, and an empty file. Every generated type uses
explicit `internal` access and takes its name from the filename. Records require
C# 9+, and record structs require C# 10+.

The nearest ancestor `.csproj` supplies `RootNamespace`, falling back to the project
filename. Subfolders become namespace segments. For example, `Models/Customer.cs`
in a project with `RootNamespace` set to `Acme.App` produces:

```csharp
namespace Acme.App.Models
{
    internal class Customer
    {
    }
}
```

Templates use block namespaces for compatibility with older projects. Without a
project, the type is created in the global namespace. Keywords are escaped with
`@`; punctuation and non-ASCII characters in generated identifiers become `_`.
Namespace detection reads a literal `RootNamespace` and expands
`$(MSBuildProjectName)`; it does not evaluate imported properties, conditions, or
`Directory.Build.props`. With multiple projects in one folder, the first discovered
project is used. Adjust the generated namespace for those layouts.

The template is inserted into the buffer; save it normally. Existing content and
edits made while the menu is open are preserved. Creating a file with an existing
name reports an error without overwriting it.

---

## 🐞 Debugger Profiles (`<F5>`)

1. **`🎯 Launch .NET Assembly DLL (C#)`**: Auto-detects or prompts for compiled `.dll` inside `bin/Debug/net8.0/` or `net9.0/`.
2. **`🌐 Launch & Debug Blazor Server App`**: Launches Blazor Server application DLL with `ASPNETCORE_ENVIRONMENT=Development`.
3. **`🔌 Attach to Running .NET / Blazor Process`**: Pick running `dotnet` process ID to attach `netcoredbg`.
