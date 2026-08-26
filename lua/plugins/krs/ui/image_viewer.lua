-- ============================================================================
-- KRS PLUGIN: Media Viewer -- open media outside nvim, or preview it inside.
-- ============================================================================
-- WHAT IT DOES
--   <C-S-CR>   Opens the current file (or the project root) with the OS default
--              application -- the reliable way to view images and video.
--   <leader>i  Renders the image inside a floating terminal with `chafa`, for a
--              quick look without leaving the editor.
--   Opening a media file also notifies you that <C-S-CR> exists.
--
-- PLATFORMS
--   Windows `cmd /c start`, WSL `explorer.exe` (with a UNC path rewrite),
--   macOS `open`, everything else `xdg-open`.
--
-- REQUIREMENTS
--   `chafa` on PATH, for the in-terminal preview only.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local ui = lazy_req("krs.core.ui")
local path = lazy_req("krs.core.path")

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Extensions that count as media, used for the "press <C-S-CR>" hint.
	--- ADD FORMATS HERE.
	media_extensions = {
		-- Images
		"png",
		"jpg",
		"jpeg",
		"gif",
		"webp",
		"bmp",
		"ico",
		"svg",
		"tiff",
		"avif",
		"heic",
		-- Video
		"mp4",
		"mkv",
		"avi",
		"mov",
		"wmv",
		"flv",
		"webm",
		"m4v",
		"3gp",
		"ogv",
	},

	--- Size of the chafa preview float, as a fraction of the editor.
	preview_width_ratio = 0.8,
	preview_height_ratio = 0.8,

	--- Renderer used by the in-editor preview. `%dx%d` receives width and height.
	preview_command = "chafa --size=%dx%d %s",

	--- Notification titles.
	notify_title = "Media Viewer",
	preview_notify_title = "KRS Image Viewer",

	keys = {
		--- Open with the OS default application, from any mode.
		open_external = { "<C-S-CR>", "<C-S-Enter>", "<C-S-Return>" },
		--- Render the image inside the editor.
		preview = "<leader>i",
		--- Dismiss the preview float.
		close_preview = { "q", "<Esc>" },
	},
}

--- Extension lookup built once from `M.settings.media_extensions`.
local media_exts = {}
for _, ext in ipairs(M.settings.media_extensions) do
	media_exts[ext] = true
end

-- ============================================================================
-- HELPERS
-- ============================================================================

--- True when the path has a media extension.
--- @param filepath string|nil
--- @return boolean
local function is_media_file(filepath)
	if not filepath or filepath == "" then
		return false
	end
	return media_exts[vim.fn.fnamemodify(filepath, ":e"):lower()] == true
end

--- True when the path exists as a file or a directory.
--- @param p string|nil
--- @return boolean
local function path_exists(p)
	return p ~= nil and p ~= "" and (path.is_file(p) or path.is_dir(p))
end

--- First real file shown in the current tab, skipping neo-tree and scratch
--- buffers. Used when the active buffer is not a file itself.
--- @return string filepath Empty string when nothing suitable is open.
local function first_visible_file()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].filetype ~= "neo-tree" and vim.bo[buf].buftype == "" then
			local name = vim.api.nvim_buf_get_name(buf)
			if path_exists(name) then
				return name
			end
		end
	end
	return ""
end

--- Translates a WSL path into the Windows UNC path explorer.exe understands.
--- @param linux_path string
--- @return string|nil unc_path nil when not running inside WSL.
local function windows_path_for_wsl(linux_path)
	local distro = os.getenv("WSL_DISTRO_NAME")
	if not distro then
		return nil
	end
	return "\\\\wsl.localhost\\" .. distro .. "\\" .. linux_path:gsub("^/", ""):gsub("/", "\\")
end

--- The platform's "open this with whatever handles it" command.
--- @param filepath string
--- @return string[] cmd
local function system_open_command(filepath)
	local abs_path = vim.fn.fnamemodify(filepath, ":p")
	if #abs_path > 1 and not abs_path:match("^%a:[/\\]?$") then
		abs_path = abs_path:gsub("[/\\]+$", "")
	end

	if vim.fn.has("win32") == 1 then
		local win_path = abs_path:gsub("/", "\\")
		return { "cmd.exe", "/c", "start", "", win_path }
	end
	if vim.fn.has("wsl") == 1 then
		return { "explorer.exe", windows_path_for_wsl(abs_path) or abs_path }
	end
	if vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1 then
		return { "open", abs_path }
	end
	return { "xdg-open", abs_path }
end

-- ============================================================================
-- API
-- ============================================================================

--- Opens a file or directory with the OS default application.
--- @param filepath string|nil Defaults to the current buffer, then any open file.
function M.open_with_system_app(filepath)
	local ok, err = pcall(function()
		if not filepath or filepath == "" then
			filepath = vim.api.nvim_buf_get_name(0)
		end
		if not filepath or filepath == "" or not path_exists(filepath) then
			filepath = first_visible_file()
		end
		if not filepath or filepath == "" or not path_exists(filepath) then
			vim.notify("No valid file or folder found to open", vim.log.levels.WARN, {
				title = M.settings.notify_title,
			})
			return
		end

		local abs_path = vim.fn.fnamemodify(filepath, ":p")
		if #abs_path > 1 and not abs_path:match("^%a:[/\\]?$") then
			abs_path = abs_path:gsub("[/\\]+$", "")
		end

		local is_directory = path.is_dir(abs_path)
		local cmd = system_open_command(abs_path)
		vim.system(cmd, { detach = true, stdout = false, stderr = false })

		local name = vim.fn.fnamemodify(abs_path, ":t")
		if name == "" then
			name = abs_path
		end
		local msg = is_directory and ("📂 Opening folder in File Explorer: " .. name)
			or ("🎬 Opening with OS default program: " .. name)

		vim.notify(msg, vim.log.levels.INFO, {
			title = M.settings.notify_title,
		})
	end)

	if not ok then
		vim.notify("Reveal in system explorer failed: " .. tostring(err), vim.log.levels.ERROR, {
			title = M.settings.notify_title,
		})
	end
end

--- Renders the current image inside a floating terminal using chafa.
function M.view_current_image()
	local filepath = vim.api.nvim_buf_get_name(0)
	if filepath == "" or not path.is_file(filepath) or vim.bo.filetype == "neo-tree" then
		filepath = first_visible_file()
	end

	if filepath == "" then
		vim.notify("No valid file to display", vim.log.levels.WARN, { title = M.settings.preview_notify_title })
		return
	end

	local width = ui.resolve_size(M.settings.preview_width_ratio, vim.o.columns)
	local height = ui.resolve_size(M.settings.preview_height_ratio, vim.o.lines)
	local buf, win = ui.float({ width = width, height = height, modifiable = true })

	vim.fn.termopen(string.format(M.settings.preview_command, width, height, vim.fn.shellescape(filepath)))
	ui.close_on_keys(buf, win, M.settings.keys.close_preview)
end

--- Opens the project root in the OS file explorer.
function M.open_project_root_in_explorer()
	local project = require("krs.core.project")
	local root = project.root()
	if not root or root == "" then
		root = vim.fn.getcwd()
	end
	M.open_with_system_app(root)
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Registers `:OpenRootInExplorer`, the keymaps, and the media-file hint.
function M.setup()
	vim.api.nvim_create_user_command("OpenRootInExplorer", function()
		M.open_project_root_in_explorer()
	end, { desc = "Open current project root in the OS file explorer" })

	if M.settings.keys.preview and M.settings.keys.preview ~= "" then
		vim.keymap.set("n", M.settings.keys.preview, M.view_current_image, {
			noremap = true,
			silent = true,
			desc = "View image with Chafa",
		})
	end

	for _, key in ipairs(M.settings.keys.open_external) do
		vim.keymap.set({ "n", "i", "v", "t" }, key, function()
			if vim.fn.mode() == "t" then
				vim.cmd("stopinsert")
			end
			M.open_with_system_app()
		end, { noremap = true, silent = true, desc = "Open Media with OS Default App" })
	end

	vim.api.nvim_create_autocmd("BufReadPost", {
		pattern = "*",
		callback = function(ev)
			local name = vim.api.nvim_buf_get_name(ev.buf)
			if is_media_file(name) then
				vim.notify(
					"🖼️ Media file opened: "
						.. vim.fn.fnamemodify(name, ":t")
						.. "\nPress <Ctrl + Shift + Enter> to open with OS default program.",
					vim.log.levels.INFO,
					{ title = M.settings.notify_title }
				)
			end
		end,
	})
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.ImageViewer = M

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "image_viewer",
	dir = require("krs.core.lazyspec").for_module(),
	event = "VeryLazy",
	config = M.setup,
}, { __index = M })
