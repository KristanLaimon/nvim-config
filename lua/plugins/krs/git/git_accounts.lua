local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")
local path = lazy_req("krs.core.path")
local project = lazy_req("krs.core.project")

local M = {}

M.settings = {
	store_file = vim.fn.stdpath("data") .. "/git_accounts.json",
}

--- @class GitAccount
--- @field alias string
--- @field user_name string
--- @field user_email string
--- @field server string|nil

--- Loads accounts from the global store.
--- @return table { default_account = string|nil, accounts = GitAccount[] }
function M.load_accounts()
	local data = store.load(M.settings.store_file, false)
	if data and data.accounts then
		return data
	end

	-- Fallback to system global git config for the first time
	local sys_name = vim.trim(vim.fn.system("git config --global user.name") or "")
	local sys_email = vim.trim(vim.fn.system("git config --global user.email") or "")

	local default_acc = nil
	local accounts = {}
	if sys_name ~= "" and sys_email ~= "" then
		default_acc = "github"
		table.insert(accounts, {
			alias = "github",
			user_name = sys_name,
			user_email = sys_email,
			server = "github.com",
		})
	end

	local init_data = {
		default_account = default_acc,
		accounts = accounts,
	}
	M.save_accounts(init_data)
	return init_data
end

--- Saves accounts to the global store.
--- @param data table
function M.save_accounts(data)
	store.save(M.settings.store_file, data)
end

--- Sets the local git config for the current project.
--- @param account GitAccount
function M.apply_account_to_project(account)
	local root = project.root()
	if not root or not path.is_dir(path.join(root, ".git")) then
		vim.notify("Not in a git repository", vim.log.levels.WARN, { title = "Git Accounts" })
		return
	end

	vim.fn.system({ "git", "-C", root, "config", "--local", "user.name", account.user_name })
	vim.fn.system({ "git", "-C", root, "config", "--local", "user.email", account.user_email })

	if account.ssh_key and account.ssh_key ~= "" then
		local ssh_cmd = "ssh -i " .. account.ssh_key .. " -F /dev/null"
		vim.fn.system({ "git", "-C", root, "config", "--local", "core.sshCommand", ssh_cmd })
		vim.notify("Git connection auth set to SSH key: " .. account.ssh_key, vim.log.levels.INFO, { title = "Git Accounts" })
	else
		-- Remove if previously set
		vim.fn.system({ "git", "-C", root, "config", "--local", "--unset", "core.sshCommand" })
	end

	if account.http_username and account.http_username ~= "" then
		vim.fn.system({ "git", "-C", root, "config", "--local", "credential.username", account.http_username })
		vim.notify("Git HTTP username set to: " .. account.http_username, vim.log.levels.INFO, { title = "Git Accounts" })
	else
		vim.fn.system({ "git", "-C", root, "config", "--local", "--unset", "credential.username" })
	end

	if account.disable_ssl then
		vim.fn.system({ "git", "-C", root, "config", "--local", "http.sslVerify", "false" })
		vim.notify("Git SSL Verification disabled for this project", vim.log.levels.WARN, { title = "Git Accounts" })
	else
		vim.fn.system({ "git", "-C", root, "config", "--local", "--unset", "http.sslVerify" })
	end

	vim.notify(
		"Git identity set to '" .. account.alias .. "' (" .. account.user_name .. " <" .. account.user_email .. ">)",
		vim.log.levels.INFO,
		{ title = "Git Accounts" }
	)
end

function M.open_menu()
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local themes = require("telescope.themes")

	local data = M.load_accounts()
	local entries = data.accounts or {}

	local function make_display(entry)
		local is_default = entry.alias == data.default_account
		local tag = is_default and " ⭐ [DEFAULT]" or ""
		local server = entry.server and (" (" .. entry.server .. ")") or ""
		return entry.alias .. server .. " -> " .. entry.user_name .. " <" .. entry.user_email .. ">" .. tag
	end

	if #entries == 0 then
		vim.ui.input({ prompt = "No accounts. Create one (Alias): " }, function(alias)
			if not alias or alias == "" then
				return
			end
			vim.ui.input({ prompt = "User Name: " }, function(name)
				if not name or name == "" then
					return
				end
				vim.ui.input({ prompt = "User Email: " }, function(email)
					if not email or email == "" then
						return
					end
					table.insert(entries, { alias = alias, user_name = name, user_email = email })
					data.default_account = alias
					M.save_accounts(data)
					M.open_menu()
				end)
			end)
		end)
		return
	end

	pickers
		.new(themes.get_dropdown({
			prompt_title = " 👤 Git Accounts | [d]=Default [a]=Add [e]=Edit [x]=Delete ",
			finder = finders.new_table({
				results = entries,
				entry_maker = function(entry)
					local display = make_display(entry)
					return {
						value = entry,
						display = display,
						ordinal = display,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				local function selected()
					local selection = action_state.get_selected_entry()
					return selection and selection.value or nil
				end

				local function save_and_reopen()
					M.save_accounts(data)
					actions.close(prompt_bufnr)
					vim.schedule(M.open_menu)
				end

				local function map_action(norm_key, ctrl_key, fn)
					map("n", norm_key, fn)
					if ctrl_key then
						map({ "n", "i" }, ctrl_key, fn)
					end
				end

				actions.select_default:replace(function()
					local value = selected()
					actions.close(prompt_bufnr)
					if value then
						M.apply_account_to_project(value)
					end
				end)

				local action_default = function()
					local value = selected()
					if value then
						data.default_account = value.alias
						save_and_reopen()
						vim.notify(
							"⭐ Default Git Account set to " .. value.alias,
							vim.log.levels.INFO,
							{ title = "Git Accounts" }
						)
					end
				end

				local action_add = function()
					actions.close(prompt_bufnr)
					vim.schedule(function()
						vim.ui.input({ prompt = "New Account Alias (e.g. gitlab-work): " }, function(alias)
							if not alias or alias == "" then
								return
							end
							vim.ui.input({ prompt = "User Name: " }, function(name)
								if not name or name == "" then
									return
								end
								vim.ui.input({ prompt = "User Email: " }, function(email)
									if not email or email == "" then
										return
									end
									vim.ui.input({ prompt = "Server URL (optional): " }, function(server)
										vim.ui.input({ prompt = "SSH Key Path (optional, e.g. ~/.ssh/id_rsa_gitlab): " }, function(ssh_key)
											vim.ui.input({ prompt = "HTTP Username (for Token Auth, optional): " }, function(http_username)
												vim.ui.input({ prompt = "Disable SSL Verify? (true/false, default: false): " }, function(disable_ssl)
													local ssl_val = disable_ssl == "true" or disable_ssl == "y" or disable_ssl == "yes" or disable_ssl == "1"
													table.insert(data.accounts, {
														alias = alias,
														user_name = name,
														user_email = email,
														server = server ~= "" and server or nil,
														ssh_key = ssh_key ~= "" and ssh_key or nil,
														http_username = http_username ~= "" and http_username or nil,
														disable_ssl = ssl_val
													})
													M.save_accounts(data)
													M.open_menu()
												end)
											end)
										end)
									end)
								end)
							end)
						end)
					end)
				end

				local action_edit = function()
					local value = selected()
					if not value then
						return
					end
					actions.close(prompt_bufnr)
					vim.schedule(function()
						vim.ui.input({ prompt = "Edit Alias: ", default = value.alias }, function(alias)
							if not alias or alias == "" then
								return
							end
							vim.ui.input({ prompt = "Edit User Name: ", default = value.user_name }, function(name)
								if not name or name == "" then
									return
								end
								vim.ui.input({ prompt = "Edit User Email: ", default = value.user_email }, function(email)
									if not email or email == "" then
										return
									end
									vim.ui.input({ prompt = "Edit Server URL: ", default = value.server or "" }, function(server)
										vim.ui.input({ prompt = "Edit SSH Key Path: ", default = value.ssh_key or "" }, function(ssh_key)
											vim.ui.input({ prompt = "Edit HTTP Username: ", default = value.http_username or "" }, function(http_username)
												local cur_ssl = value.disable_ssl and "true" or "false"
												vim.ui.input({ prompt = "Disable SSL Verify? (true/false): ", default = cur_ssl }, function(disable_ssl)
													local ssl_val = disable_ssl == "true" or disable_ssl == "y" or disable_ssl == "yes" or disable_ssl == "1"
													if data.default_account == value.alias then
														data.default_account = alias
													end
													value.alias = alias
													value.user_name = name
													value.user_email = email
													value.server = server ~= "" and server or nil
													value.ssh_key = ssh_key ~= "" and ssh_key or nil
													value.http_username = http_username ~= "" and http_username or nil
													value.disable_ssl = ssl_val
													M.save_accounts(data)
													M.open_menu()
												end)
											end)
										end)
									end)
								end)
							end)
						end)
					end)
				end

				local action_delete = function()
					local value = selected()
					if not value then
						return
					end
					if data.default_account == value.alias then
						data.default_account = nil
					end
					local kept = {}
					for _, acc in ipairs(data.accounts) do
						if acc.alias ~= value.alias then
							table.insert(kept, acc)
						end
					end
					data.accounts = kept
					save_and_reopen()
				end

				map_action("d", "<C-d>", action_default)
				map_action("a", "<C-a>", action_add)
				map_action("e", "<C-e>", action_edit)
				map("n", "r", action_edit)
				map_action("x", "<C-x>", action_delete)

				return true
			end,
		}))
		:find()
end

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	vim.api.nvim_create_user_command("GitAccounts", function()
		M.open_menu()
	end, { desc = "Open Git Accounts Manager" })

	local ok_cp, cp = pcall(require, "plugins.krs.tools.command_palette")
	if ok_cp and cp and cp.add_command then
		cp.add_command({
			name = "👤 Git Accounts Manager (Select Identity)",
			cmd = "GitAccounts",
			category = "Git",
		})
	end
end

return setmetatable({
	name = "krs_git_accounts",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = { "GitAccounts" },
	dependencies = { "nvim-telescope/telescope.nvim" },
	config = function()
		M.setup()
	end,
}, { __index = M })
