-- ============================================================================
-- KRS RUBY: Centralized Ruby Language Configuration
-- ============================================================================
-- WHAT IT DOES
--   Configures solargraph LSP server, rubocop formatter/linter, and launch profile
--   runtimes for Ruby.
-- ============================================================================

---@type KrsLangModule
local M = {}

M.lsp_server = { "solargraph" }

---@type table<string, vim.lsp.Config>
M.lsp_config = {
  solargraph = {
    filetypes = { "ruby" },
    settings = {
      solargraph = {
        diagnostics = true,
      },
    },
  },
}

M.mason = {
  solargraph = { mason = "solargraph", lang = "Ruby", type = "lsp", cmd = "solargraph" },
  rubocop = { mason = "rubocop", name = "rubocop", type = "formatter", cmd = "rubocop" },
}

M.mason_order = { "solargraph", "rubocop" }

M.bundle_name = "💎 Ruby"
M.requires = {
  { cmd = "ruby", name = "Ruby runtime", hint = "https://www.ruby-lang.org" },
}
M.treesitter = { "ruby" }

M.formatters_by_ft = {
  ruby = { "rubocop" },
}

M.conform_formatters = {
  rubocop = {
    condition = function()
      return vim.fn.executable("rubocop") == 1
    end,
  },
}

M.launch_runtimes = {
  ruby = {
    command = "ruby",
  },
}

M.defaults = {
  expandtab = true,
  shiftwidth = 2,
  tabstop = 2,
  softtabstop = 2,
  autoindent = true,
}

function M.apply_defaults(buf)
  local ok, langs = pcall(require, "krs.langs")
  if ok and not langs.has_editorconfig(buf) then
    for option, val in pairs(M.defaults) do
      vim.bo[buf][option] = val
    end
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "ruby",
    callback = function(args)
      M.apply_defaults(args.buf)
    end,
  })
end

return M
