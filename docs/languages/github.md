# 🐙 GitHub Actions Toolchain Guide

This document provides setup instructions and details for GitHub Actions workflow & action tooling in **KrsVim**.

---

## 📦 1. Installed Components

The **GitHub Actions** bundle (`🐙 GitHub Actions`) is an optional, opt-in bundle in the Language Tooling Manager (`:LanguageManager`).

| Tool | Type | Component Name | Command / Executable |
|---|---|---|---|
| **gh-actions-language-server** | LSP | `gh-actions-language-server` | `gh-actions-language-server` |
| **actionlint** | Linter / Static Checker | `actionlint` | `actionlint` |

---

## ⚙️ 2. Features

- **Workflow Autocompletion & Validation**: Automatically attaches to `.github/workflows/*.yml` and `.github/actions/*.yml` files.
- **Actionlint Linter**: Validates expression syntax, runner compatibility, and workflow rules.
