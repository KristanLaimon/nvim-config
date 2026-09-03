-- ============================================================================
-- PLUGINS: LSP -- mason, nvim-lspconfig and blink.cmp.
-- ============================================================================
-- HOW A SERVER GETS ENABLED
--   Every server's settings live in its owning language module, NOT here -- see
--   lua/krs/langs/<lang>/init.lua's `M.lsp_config`, keyed by server name (e.g.
--   lua/krs/langs/typescript/init.lua for vtsls/jsonls/biome/eslint). This file only:
--   1. Merges every language's `lsp_config` into one `opts.servers` table.
--   2. Adds settings that need a plugin only available at runtime (SchemaStore).
--   3. Merges blink.cmp capabilities into each entry and enables it.
--   A handful of generic, language-agnostic servers (taplo/yamlls/lemminx --
--   TOML/YAML/XML have no per-language buffer-default module) are defined directly
--   below instead of in a language module.
--
-- LUA
--   `lua_ls` also serves `.krsnvim` scripts: script globals (fetch, console, import,
--   krsnvim) are re-added on attach so they do not show up as undefined.
--
-- JSON / TOML SCHEMAS
--   Bundled schemas in `schemas/` are preferred over the online SchemaStore
--   copies, so validation works offline and cannot change under you.
--
-- COMPLETION
--   blink.cmp config lives at the bottom of this file. Extra sources are declared
--   in blink_sources.lua and editorconfig.lua.
-- ============================================================================

-- MSBuild project/props files are XML; registering them makes lemminx attach and
-- give IntelliSense inside .csproj and friends. `.blade.php` needs a pattern
-- rather than an extension, because the filetype depends on the double suffix.
local langs = require("krs.langs").langs

--- Generic, language-agnostic servers with no owning lua/krs/langs/<lang> module.
local function generic_servers()
	return {
		taplo = {},
		yamlls = {},
		lemminx = {
			settings = {
				xml = {
					validation = {
						enabled = true,
						noGrammar = "hint",
					},
					completion = {
						autoCloseTags = true,
					},
					fileAssociations = {
						{
							systemId = vim.fn.stdpath("config") .. "/schemas/xml/msbuild.xsd",
							pattern = "*.csproj",
						},
						{
							systemId = vim.fn.stdpath("config") .. "/schemas/xml/msbuild.xsd",
							pattern = "*.props",
						},
						{
							systemId = vim.fn.stdpath("config") .. "/schemas/xml/msbuild.xsd",
							pattern = "*.targets",
						},
						{
							systemId = vim.fn.stdpath("config") .. "/schemas/xml/msbuild.xsd",
							pattern = "*.fsproj",
						},
						{
							systemId = vim.fn.stdpath("config") .. "/schemas/xml/msbuild.xsd",
							pattern = "*.vbproj",
						},
					},
				},
			},
		},
	}
end

--- Merges every language module's `lsp_config` into one servers table.
local function build_servers()
	local servers = generic_servers()
	for _, lang in pairs(langs) do
		if lang.lsp_config then
			for name, cfg in pairs(lang.lsp_config) do
				servers[name] = cfg
			end
		end
	end
	return servers
end

vim.filetype.add({
	extension = {
		csproj = "xml",
		fsproj = "xml",
		vbproj = "xml",
		props = "xml",
		targets = "xml",
	},
	pattern = {
		[".*%.blade%.php"] = "blade",
	},
})

return {
	{
		-- Its own spec so `:Mason` exists on an empty nvim too. Without this, mason
		-- is only ever pulled in as an nvim-lspconfig dependency, and setup() (which
		-- registers the command) runs on BufReadPre — no file open, no :Mason.
		"williamboman/mason.nvim",
		cmd = "Mason",
		opts = {},
	},
	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufReadPost", "BufNewFile", "FileType" },
		cmd = { "LspInfo", "LspInstall", "LspStart" },
		dependencies = {
			"williamboman/mason.nvim",
			"williamboman/mason-lspconfig.nvim",
			"b0o/schemastore.nvim",
		},
		opts = {
			servers = build_servers(),
		},
		config = function(_, opts)
			local has_blink, blink = pcall(require, "blink.cmp")

			-- 1. Initialize Mason
			require("mason").setup()
			require("mason-lspconfig").setup({
				automatic_installation = false,
				automatic_enable = false,
				ensure_installed = {},
				handlers = {
					function(server_name)
						local config = opts.servers[server_name] or {}
						if config.enabled == false then
							return
						end
						if has_blink then
							config.capabilities = blink.get_lsp_capabilities(config.capabilities)
						end

						if vim.fn.has("win32") == 1 then
							config.capabilities = config.capabilities or vim.lsp.protocol.make_client_capabilities()
							config.capabilities.workspace = config.capabilities.workspace or {}
							config.capabilities.workspace.didChangeWatchedFiles = config.capabilities.workspace.didChangeWatchedFiles
								or {}
							config.capabilities.workspace.didChangeWatchedFiles.dynamicRegistration = false
						end

						vim.lsp.config(server_name, config)
						vim.lsp.enable(server_name)
					end,
				},
			})

			-- 2. Setup configured servers in opts.servers
			for server_name, config in pairs(opts.servers) do
				if config.enabled ~= false then
					local cfg = vim.deepcopy(config)
					if has_blink then
						cfg.capabilities = blink.get_lsp_capabilities(cfg.capabilities)
					end

					if vim.fn.has("win32") == 1 then
						cfg.capabilities = cfg.capabilities or vim.lsp.protocol.make_client_capabilities()
						cfg.capabilities.workspace = cfg.capabilities.workspace or {}
						cfg.capabilities.workspace.didChangeWatchedFiles = cfg.capabilities.workspace.didChangeWatchedFiles or {}
						cfg.capabilities.workspace.didChangeWatchedFiles.dynamicRegistration = false
					end

					vim.lsp.config(server_name, cfg)
					vim.lsp.enable(server_name)
				end
			end

			-- Re-trigger FileType autocmd for loaded buffers so newly enabled LSP servers attach
			-- immediately to the buffer whose opening triggered lazy-loading of nvim-lspconfig.
			vim.schedule(function()
				for _, buf in ipairs(vim.api.nvim_list_bufs()) do
					if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype ~= "" then
						pcall(vim.api.nvim_exec_autocmds, "FileType", { buffer = buf })
					end
				end
			end)

			vim.diagnostic.config({
				virtual_text = {
					source = "if_many",
					prefix = "●",
				},
				underline = true,
				signs = true,
				severity_sort = true,
			})

			vim.api.nvim_create_autocmd("LspAttach", {
				callback = function(args)
					local client = vim.lsp.get_client_by_id(args.data.client_id)
					if client and client.name == "lua_ls" then
						local bufnr = args.buf
						local fname = vim.api.nvim_buf_get_name(bufnr)
						local ft = vim.bo[bufnr].filetype
						local is_krs = (ft == "krsnvim" or fname:match("%.krsnvim$") ~= nil)

						if is_krs then
							client.config.settings.Lua = client.config.settings.Lua or {}
							client.config.settings.Lua.diagnostics = client.config.settings.Lua.diagnostics or {}
							client.config.settings.Lua.diagnostics.globals =
								{ "vim", "fetch", "console", "import", "krsnvim", "cli", "terminal", "fs" }
							pcall(client.notify, "workspace/didChangeConfiguration", { settings = client.config.settings })
						end
					end

					local env_ok, env_mod = pcall(require, "krs.core.environment")
					local env = env_ok and env_mod.detect() or {}
					local is_mobile_or_proot = env.is_termux or env.is_proot or env.is_mobile or (vim.env.TERMUX_VERSION ~= nil)

					-- Inlay hints are kept disabled on attach by default to prevent Neovim 0.10's upstream
					-- runtime decoration provider bug (/usr/share/nvim/runtime/lua/vim/lsp/inlay_hint.lua:362)
					-- from throwing "Invalid 'col': out of range" during active edits/imports.
					-- Toggle on-demand via :ToggleInlayHints.
					if vim.lsp.inlay_hint then
						pcall(vim.lsp.inlay_hint.enable, false, { bufnr = args.buf })
					end
				end,
			})

			-- :LspInfo -- show active LSP clients for the current buffer in a float
			vim.api.nvim_create_user_command("LspInfo", function()
				local buf = vim.api.nvim_get_current_buf()
				local clients = vim.lsp.get_clients({ bufnr = buf })
				local lines = { "LSP clients attached to buffer " .. buf .. ":", "" }
				if #clients == 0 then
					table.insert(lines, "  (none)")
				else
					for _, client in ipairs(clients) do
						table.insert(lines, "  ● " .. client.name .. "  (id=" .. client.id .. ")")
						local python_path = vim.tbl_get(client, "config", "settings", "python", "pythonPath")
							or vim.tbl_get(client, "config", "settings", "basedpyright", "pythonPath")
							or (client.config.cmd and client.config.cmd[1])
						if python_path then
							table.insert(lines, "    interpreter: " .. python_path)
						end
						local root = client.config.root_dir or client.root_dir
						if root then
							table.insert(lines, "    root:        " .. root)
						end
						table.insert(lines, "")
					end
				end
				-- Open in a scratch float
				local float_buf = vim.api.nvim_create_buf(false, true)
				vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)
				vim.bo[float_buf].modifiable = false
				vim.bo[float_buf].filetype = "markdown"
				local width = math.max(50, math.min(80, vim.o.columns - 4))
				local height = math.min(#lines + 2, vim.o.lines - 4)
				local win = vim.api.nvim_open_win(float_buf, true, {
					relative = "editor",
					row = math.floor((vim.o.lines - height) / 2),
					col = math.floor((vim.o.columns - width) / 2),
					width = width,
					height = height,
					style = "minimal",
					border = "rounded",
					title = " LSP Info ",
					title_pos = "center",
				})
				vim.wo[win].wrap = false
				-- close on q / Esc
				for _, key in ipairs({ "q", "<Esc>" }) do
					vim.keymap.set("n", key, "<cmd>close<CR>", { buffer = float_buf, silent = true })
				end
			end, { desc = "Show active LSP clients for the current buffer" })

			local function toggle_inlay_hints()
				if vim.lsp.inlay_hint then
					local current = vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
					vim.lsp.inlay_hint.enable(not current, { bufnr = 0 })
					local status_msg = not current and "enabled 💡" or "disabled 🙈"
					require("krs.core.notify").notify("Inlay hints " .. status_msg, vim.log.levels.INFO, "LSP")
				end
			end

			pcall(vim.api.nvim_create_user_command, "ToggleInlayHints", toggle_inlay_hints, { desc = "Toggle LSP Inlay Hints" })
			pcall(vim.api.nvim_create_user_command, "KrsToggleInlayHints", toggle_inlay_hints, { desc = "Toggle LSP Inlay Hints" })

			-- The TS server advertises `diagnosticProvider`, so nvim pulls and refreshes
			-- diagnostics natively. A hand-rolled fetch into a private namespace only froze
			-- whatever the server happened to know a few hundred ms after attach --
			-- typically before node_modules was loaded -- and never refreshed it.

			local function get_schema_uri(category, filename)
				local path = vim.fs.normalize(vim.fn.stdpath("config") .. "/schemas/" .. category .. "/" .. filename)
				return vim.uri_from_fname(path)
			end

			local ok_schemastore, schemastore = pcall(require, "schemastore")
			if ok_schemastore then
				opts.servers.yamlls = opts.servers.yamlls or {}
				opts.servers.yamlls.settings = {
					yaml = {
						schemaStore = {
							enable = false,
							url = "",
						},
						schemas = schemastore.yaml.schemas(),
					},
				}

				opts.servers.jsonls = opts.servers.jsonls or {}
				opts.servers.jsonls.settings = {
					json = {
						schemas = schemastore.json.schemas({
							select = {
								"tsconfig.json",
								"package.json",
								"prettierrc.json",
								".eslintrc",
								"jsconfig.json",
								"babelrc.json",
								"Turborepo",
								"biome.json",
								"KrsVim Snippets Schema",
							},
							replace = {
								["tsconfig.json"] = get_schema_uri("json", "tsconfig.json"),
								["package.json"] = get_schema_uri("json", "package.json"),
								-- ["prettierrc.json"] = get_schema_uri("json", "prettierrc.json"),
								[".eslintrc"] = get_schema_uri("json", "eslintrc.json"),
								["jsconfig.json"] = get_schema_uri("json", "jsconfig.json"),
								["babelrc.json"] = get_schema_uri("json", "babelrc.json"),
								["Turborepo"] = get_schema_uri("json", "turbo.json"),
							},
							extra = {
								{
									name = "prettierrc.json",
									description = "Prettier configuration schema",
									fileMatch = { "prettierrc.json", "prettier.config.json", ".prettierrc.astro.json" },
									url = get_schema_uri("json", "prettierrc.json"),
								},
								{
									name = "biome.json",
									description = "Biome configuration schema",
									fileMatch = { "biome.json", "biome.jsonc" },
									url = get_schema_uri("json", "biome.json"),
								},
								{
									name = "KrsVim Snippets Schema",
									description = "VSCode-compatible snippet file schema",
									fileMatch = { "snippets/*.json", "snippets/**/*.json" },
									url = vim.uri_from_fname(vim.fn.stdpath("config") .. "/snippets/snippets.schema.json"),
								},
							},
						}),
						validate = { enable = true },
					},
				}
			end

			opts.servers.taplo.settings = {
				even_better_toml = {
					schema = {
						enabled = true,
						repository = false,
						associations = {
							["^bunfig\\.toml$"] = get_schema_uri("toml", "bunfig.json"),
						},
					},
				},
			}

			-- Stop all active LSP clients whenever the working directory/project changes.
			-- When you open a file in the new project, Neovim will automatically launch only the needed LSP.
			vim.api.nvim_create_autocmd("DirChanged", {
				group = vim.api.nvim_create_augroup("LspProjectAutoStop", { clear = true }),
				callback = function()
					for _, client in ipairs(vim.lsp.get_clients()) do
						client:stop()
					end
				end,
			})
		end,
	},
	{
		"saghen/blink.cmp",
		event = { "BufReadPre", "BufReadPost", "BufNewFile", "InsertEnter" },
		dependencies = { "rafamadriz/friendly-snippets" },
		version = "*",
		opts = function(_, opts)
			local is_mobile = false
			local env_ok, env_mod = pcall(require, "krs.core.environment")
			if env_ok then
				local env = env_mod.detect()
				is_mobile = env.is_termux or env.is_proot or env.is_mobile
			else
				is_mobile = vim.env.TERMUX_VERSION ~= nil or vim.fn.isdirectory("/data/data/com.termux") == 1
			end

			local merged = vim.tbl_deep_extend("force", opts or {}, {
				enabled = function()
					return vim.bo.filetype ~= "krsinputmodal" and vim.b.completion ~= false
				end,
				snippets = {
					preset = "default",
				},
				keymap = {
					preset = "default",
					["<CR>"] = { "accept", "fallback" },
					["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
					["<C-@>"] = { "show", "show_documentation", "hide_documentation" },
					["<C-l>"] = { "show", "show_documentation", "hide_documentation" },
					["<Up>"] = { "select_prev", "fallback" },
					["<Down>"] = { "select_next", "fallback" },
				},
				appearance = { nerd_font_variant = "mono" },
				completion = {
					list = {
						selection = {
							preselect = true,
							auto_insert = false,
						},
					},
					menu = {
						border = "rounded",
						max_height = is_mobile and 8 or 15,
						draw = {
							components = {
								kind_icon = {
									ellipsis = false,
									text = function(ctx)
										local colorify = require("krs.lsp.colorify")
										local hex = colorify.extract_color_from_ctx(ctx)
										if hex then
											return " ██ "
										end
										return colorify.get_kind_icon(ctx.kind)
									end,
									highlight = function(ctx)
										local colorify = require("krs.lsp.colorify")
										local hex = colorify.extract_color_from_ctx(ctx)
										if hex then
											return colorify.get_or_create_color_hl(hex)
										end
										return colorify.get_kind_hl(ctx.kind)
									end,
								},
								kind = {
									text = function(ctx)
										return require("krs.lsp.colorify").format_kind_label(ctx.kind)
									end,
								},
							},
							columns = {
								{ "kind_icon" },
								{ "label", "label_description", gap = 1 },
								{ "kind" },
							},
						},
						-- Don't auto-pop inside a freshly inserted empty pair ("{}" from autopairs).
						-- Only auto-show is suppressed: <C-space> still opens the menu there,
						-- which is what `import { | }` needs.
						auto_show = function()
							local line = vim.api.nvim_get_current_line()
							local col = vim.api.nvim_win_get_cursor(0)[2]
							local before, after = line:sub(col, col), line:sub(col + 1, col + 1)
							local pairs_map = { ["{"] = "}", ["["] = "]", ["("] = ")" }
							return pairs_map[before] ~= after
						end,
					},
					documentation = { auto_show = false },
					trigger = {
						-- "{" and "[" open bracket-pair snippets on every keystroke otherwise
						show_on_blocked_trigger_characters = { " ", "\n", "\t", "{", "[", "(" },
					},
				},
				signature = {
					enabled = not is_mobile,
					window = { border = "rounded" },
				},
				sources = {
					-- Debug repl completes from the stopped frame only, never lsp/buffer words.
					per_filetype = { ["dap-repl"] = { "dap" } },
					providers = {
						dap = { name = "DAP", module = "krs.lsp.dap_repl_source", async = true },
						snippets = {
							opts = {
								search_paths = { vim.fn.stdpath("config") .. "/snippets" },
							},
						},
					},
				},
				fuzzy = {
					implementation = is_mobile and "lua" or "prefer_rust_with_warning",
					prebuilt_binaries = {
						download = not is_mobile,
					},
					sorts = {
						-- always rank snippets (LSP kind 15) below real completions, regardless of fuzzy score
						function(a, b)
							local a_snip, b_snip = a.kind == 15, b.kind == 15
							if a_snip ~= b_snip then
								return b_snip
							end
						end,
						-- always rank struct fields, properties, enums, enum members & constants (LSP kinds 5, 10, 13, 20, 21) at top
						function(a, b)
							local priority_kinds = { [5] = true, [10] = true, [13] = true, [20] = true, [21] = true }
							local a_prio = priority_kinds[a.kind] == true
							local b_prio = priority_kinds[b.kind] == true
							if a_prio ~= b_prio then
								return a_prio
							end
						end,
						"score",
						"sort_text",
					},
				},
			})

			merged.sources = merged.sources or {}
			merged.sources.default = merged.sources.default or {}
			for _, v in ipairs({ "lsp", "path", "snippets", "buffer" }) do
				if not vim.tbl_contains(merged.sources.default, v) then
					table.insert(merged.sources.default, v)
				end
			end
			return merged
		end,
		opts_extend = { "sources.default" },
	},
}
