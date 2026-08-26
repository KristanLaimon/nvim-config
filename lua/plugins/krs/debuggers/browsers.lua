-- ============================================================================
-- 🌐 Browsers — Chrome / Edge (js-debug) and Firefox (firefox-debug-adapter)
-- ============================================================================
-- Two shapes per browser:
--   Launch  — starts the dev server if nothing is serving yet, then opens the
--             browser on it. `url` is a function; nvim-dap resolves config
--             values inside a coroutine, so it can wait for the port.
--   Attach  — never starts anything. Chromium needs to have been started with
--             --remote-debugging-port=9222 for this to find it.
-- ============================================================================

local shared = require("plugins.krs.debuggers._shared")

local function dev()
	return require("plugins.krs.dev.dev_server").url()
end

local function existing()
	return require("plugins.krs.dev.dev_server").existing_url()
end

return function(dap)
	shared.js_debug(dap)

	local configs = {}

	-- ponytail: no sourceMapPathOverrides. js-debug's defaults already resolve
	-- vite's /@fs/ and webpack:// layouts; add overrides only if a framework
	-- shows unbound (⭕) breakpoints.
	for _, browser in ipairs({
		{ type = "pwa-chrome", icon = "🌐", label = "Chrome" },
		{ type = "pwa-msedge", icon = "🔷", label = "Edge" },
	}) do
		table.insert(configs, {
			type = browser.type,
			request = "launch",
			name = browser.icon .. " Launch " .. browser.label .. " + Dev Server",
			url = dev,
			webRoot = "${workspaceFolder}",
			sourceMaps = true,
			skipFiles = shared.js_skip,
			-- false = use the real profile instead of a throwaway one, so the
			-- session, extensions and logins are the ones already set up.
			userDataDir = false,
		})
		table.insert(configs, {
			type = browser.type,
			request = "attach",
			name = browser.icon .. " Attach to running " .. browser.label .. " (port 9222)",
			port = 9222,
			url = existing,
			webRoot = "${workspaceFolder}",
			sourceMaps = true,
			skipFiles = shared.js_skip,
		})
	end

	-- Firefox has no CDP, so js-debug cannot drive it — this is the separate
	-- firefox-debug-adapter. reAttach reuses an already-open Firefox instead of
	-- spawning a second one, which is the closest it gets to "attach".
	table.insert(configs, {
		type = "firefox",
		request = "launch",
		name = "🦊 Launch Firefox + Dev Server",
		reAttach = true,
		url = dev,
		webRoot = "${workspaceFolder}",
		firefoxExecutable = vim.fn.exepath("firefox"),
	})

	shared.add(dap, shared.web_filetypes, configs)
end
