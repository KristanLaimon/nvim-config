local M = {}

--- Toolchain directories prepended to PATH when they exist.
--- ADD A TOOLCHAIN HERE if a GUI launch cannot find your runtime.
--- Entries may be nil (an unset environment variable); they are filtered out
--- before use, so the list never ends early on a missing variable.
local path_candidates = {
	windows = function(env)
		return {
			env.APPDATA .. "\\fnm\\aliases\\default",
			env.NVM_SYMLINK,
			env.NVM_HOME,
			"C:\\Program Files\\nodejs",
			"C:\\Program Files (x86)\\nodejs",
			env.APPDATA .. "\\npm",
			env.PNPM_HOME,
			env.LOCALAPPDATA .. "\\pnpm",
			env.APPDATA .. "\\pnpm",
			env.VOLTA_HOME and (env.VOLTA_HOME .. "\\bin"),
			env.LOCALAPPDATA .. "\\volta\\bin",
			env.USERPROFILE .. "\\.volta\\bin",
			env.USERPROFILE .. "\\scoop\\shims",
			env.USERPROFILE .. "\\scoop\\apps\\nodejs\\current",
			env.USERPROFILE .. "\\scoop\\apps\\nodejs-lts\\current",
			"C:\\ProgramData\\chocolatey\\bin",
			env.USERPROFILE .. "\\.bun\\bin",
			env.USERPROFILE .. "\\.deno\\bin",
			env.LOCALAPPDATA .. "\\Yarn\\bin",
			env.USERPROFILE .. "\\.cargo\\bin",
			env.USERPROFILE .. "\\go\\bin",
		}
	end,
	unix = function()
		local home = vim.fn.expand("~")
		return {
			"/data/data/com.termux/files/usr/bin",
			"/opt/homebrew/bin",
			"/usr/local/bin",
			home .. "/.local/share/fnm/current/bin",
			home .. "/.nvm/current/bin",
			home .. "/.local/share/pnpm",
			home .. "/.volta/bin",
			home .. "/.local/share/mise/shims",
			home .. "/.asdf/shims",
			home .. "/.bun/bin",
			home .. "/.deno/bin",
			home .. "/.cargo/bin",
			home .. "/go/bin",
			home .. "/.local/bin",
		}
	end,
}

--- Prepends every existing toolchain directory to PATH, once per session.
--- `vim.g._path_setup_done` guards against a config reload doing it twice.
function M.setup()
	if vim.g._path_setup_done then
		return
	end
	vim.g._path_setup_done = true

	local is_windows = vim.fn.has("win32") == 1
	local uv = vim.uv or vim.loop
	local separator = is_windows and ";" or ":"
	local current_path = vim.env.PATH or ""

	local env = {
		APPDATA = vim.env.APPDATA or "",
		LOCALAPPDATA = vim.env.LOCALAPPDATA or "",
		USERPROFILE = vim.env.USERPROFILE or "",
		NVM_SYMLINK = vim.env.NVM_SYMLINK,
		NVM_HOME = vim.env.NVM_HOME,
		PNPM_HOME = vim.env.PNPM_HOME,
		VOLTA_HOME = vim.env.VOLTA_HOME,
	}

	local candidates = is_windows and path_candidates.windows(env) or path_candidates.unix(env)

	local seen = {}
	local valid_paths = {}

	for _, candidate in pairs(candidates) do
		if type(candidate) == "string" and candidate ~= "" then
			local normalized = is_windows and candidate:gsub("/", "\\") or candidate
			if not seen[normalized] then
				seen[normalized] = true
				if not current_path:find(normalized, 1, true) then
					local stat = uv.fs_stat(normalized)
					if stat and stat.type == "directory" then
						table.insert(valid_paths, normalized)
					end
				end
			end
		end
	end

	if #valid_paths > 0 then
		vim.env.PATH = table.concat(valid_paths, separator) .. separator .. current_path
	end
end

return M
