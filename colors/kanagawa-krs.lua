-- ============================================================================
-- COLORSCHEME: kanagawa-krs -- Static KrsVim port of Omarchy's Kanagawa palette.
-- ============================================================================
-- This colorscheme is self-contained: it does not read Omarchy state files or
-- require the Omarchy theme adapter. It is based on the Kanagawa palette that
-- was active in Omarchy when this file was created.
--
-- Usage: :colorscheme kanagawa-krs
-- ============================================================================

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
	vim.cmd("syntax reset")
end

vim.o.background = "dark"
vim.g.colors_name = "kanagawa-krs"

local p = {
	bg = "#1f1f28",
	bg_dark = "#17171e",
	bg_deep = "#111116",
	bg_highlight = "#223249",
	bg_selected = "#363646",
	fg = "#dcd7ba",
	fg_muted = "#c8c093",
	comment = "#727169",

	red = "#c34043",
	orange = "#c17158",
	yellow = "#c0a36e",
	green = "#76946a",
	cyan = "#6a9589",
	blue = "#7e9cd8",
	magenta = "#957fb8",
	bright_red = "#e82424",
	bright_yellow = "#e6c384",
	bright_green = "#98bb6c",
	bright_cyan = "#7aa89f",
	bright_blue = "#7fb4ca",
	bright_magenta = "#938aa9",
	none = "NONE",
}

local highlights = {
	-- Base editor
	Normal = { fg = p.fg, bg = p.bg },
	NormalNC = { fg = p.fg, bg = p.bg },
	NormalFloat = { fg = p.fg, bg = p.bg_dark },
	FloatBorder = { fg = p.fg, bg = p.bg_dark },
	FloatTitle = { fg = p.fg, bg = p.bg_dark, bold = true },
	Cursor = { fg = p.bg, bg = p.fg },
	CursorLine = { bg = p.bg_highlight },
	CursorColumn = { bg = p.bg_highlight },
	ColorColumn = { bg = p.bg_dark },
	LineNr = { fg = "#54546d" },
	CursorLineNr = { fg = p.bright_yellow, bold = true },
	VertSplit = { fg = p.bg_deep, bg = p.none },
	WinSeparator = { fg = p.bg_deep, bg = p.none },
	MatchParen = { fg = p.bright_yellow, bg = p.bg_selected, bold = true },
	NonText = { fg = "#54546d" },
	Whitespace = { fg = "#363646" },
	EndOfBuffer = { fg = p.bg },

	-- Selection, search, and messages
	Visual = { bg = p.bg_selected },
	VisualNOS = { bg = p.bg_selected },
	Search = { fg = p.bg, bg = p.yellow },
	IncSearch = { fg = p.bg, bg = p.bright_yellow, bold = true },
	CurSearch = { fg = p.bg, bg = p.bright_yellow, bold = true },
	Substitute = { fg = p.bg, bg = p.orange, bold = true },
	ErrorMsg = { fg = p.bright_red },
	WarningMsg = { fg = p.bright_yellow },
	ModeMsg = { fg = p.fg },
	MoreMsg = { fg = p.green },
	Question = { fg = p.cyan },

	-- Statusline, tabs, and popup menu
	StatusLine = { fg = p.fg, bg = p.bg_dark },
	StatusLineNC = { fg = p.comment, bg = p.bg_dark },
	TabLine = { fg = p.comment, bg = p.bg_dark },
	TabLineFill = { bg = p.bg_dark },
	TabLineSel = { fg = p.fg, bg = p.bg, bold = true },
	Pmenu = { fg = p.fg, bg = p.bg_dark },
	PmenuSel = { fg = p.fg, bg = p.bg_selected, bold = true },
	PmenuSbar = { bg = p.bg_dark },
	PmenuThumb = { bg = p.blue },

	-- Legacy syntax
	Comment = { fg = p.comment, italic = true },
	Constant = { fg = p.orange },
	String = { fg = p.green },
	Character = { fg = p.green },
	Number = { fg = p.orange },
	Boolean = { fg = p.magenta, bold = true },
	Float = { fg = p.orange },
	Identifier = { fg = p.fg },
	Function = { fg = p.blue, bold = true },
	Statement = { fg = p.magenta, bold = true },
	Conditional = { fg = p.magenta, bold = true },
	Repeat = { fg = p.magenta, bold = true },
	Label = { fg = p.magenta },
	Operator = { fg = p.cyan },
	Keyword = { fg = p.magenta, bold = true },
	Exception = { fg = p.red, bold = true },
	PreProc = { fg = p.bright_magenta },
	Include = { fg = p.magenta },
	Define = { fg = p.magenta },
	Macro = { fg = p.magenta },
	Type = { fg = p.yellow, bold = true },
	StorageClass = { fg = p.magenta, bold = true },
	Structure = { fg = p.yellow },
	Typedef = { fg = p.yellow },
	Special = { fg = p.bright_magenta },
	SpecialChar = { fg = p.bright_magenta },
	Tag = { fg = p.cyan },
	Delimiter = { fg = p.fg },
	SpecialComment = { fg = p.bright_magenta, italic = true },
	Debug = { fg = p.red },
	Underlined = { underline = true },
	Bold = { bold = true },
	Italic = { italic = true },
	Error = { fg = p.bright_red, bold = true },
	Todo = { fg = p.bg, bg = p.yellow, bold = true },

	-- Treesitter
	["@comment"] = { fg = p.comment, italic = true },
	["@variable"] = { fg = p.fg },
	["@variable.builtin"] = { fg = p.magenta, italic = true },
	["@variable.parameter"] = { fg = p.fg_muted },
	["@function"] = { fg = p.blue, bold = true },
	["@function.builtin"] = { fg = p.blue, bold = true },
	["@function.call"] = { fg = p.blue },
	["@function.method"] = { fg = p.blue },
	["@function.method.call"] = { fg = p.blue },
	["@constructor"] = { fg = p.yellow },
	["@keyword"] = { fg = p.magenta, bold = true },
	["@keyword.function"] = { fg = p.magenta, bold = true },
	["@keyword.return"] = { fg = p.magenta, bold = true },
	["@keyword.conditional"] = { fg = p.magenta, bold = true },
	["@keyword.repeat"] = { fg = p.magenta, bold = true },
	["@keyword.import"] = { fg = p.magenta, bold = true },
	["@keyword.operator"] = { fg = p.magenta },
	["@string"] = { fg = p.green },
	["@string.escape"] = { fg = p.cyan },
	["@number"] = { fg = p.orange },
	["@boolean"] = { fg = p.magenta, bold = true },
	["@type"] = { fg = p.yellow, bold = true },
	["@type.builtin"] = { fg = p.yellow, italic = true },
	["@property"] = { fg = p.fg },
	["@field"] = { fg = p.fg },
	["@operator"] = { fg = p.cyan },
	["@punctuation.delimiter"] = { fg = p.fg },
	["@punctuation.bracket"] = { fg = p.fg },
	["@module"] = { fg = p.yellow },
	["@tag"] = { fg = p.red },
	["@tag.attribute"] = { fg = p.yellow },

	-- Diagnostics and diffs
	DiagnosticError = { fg = p.red },
	DiagnosticWarn = { fg = p.yellow },
	DiagnosticInfo = { fg = p.blue },
	DiagnosticHint = { fg = p.cyan },
	DiagnosticUnderlineError = { underline = true, sp = p.red },
	DiagnosticUnderlineWarn = { underline = true, sp = p.yellow },
	DiagnosticUnderlineInfo = { underline = true, sp = p.blue },
	DiagnosticUnderlineHint = { underline = true, sp = p.cyan },
	GitSignsAdd = { fg = p.green },
	GitSignsChange = { fg = p.yellow },
	GitSignsDelete = { fg = p.red },
	DiffAdd = { bg = "#1d2b22", fg = p.green },
	DiffChange = { bg = "#2b2a20", fg = p.yellow },
	DiffDelete = { bg = "#332126", fg = p.red },

	-- Common plugins
	NeoTreeNormal = { fg = p.fg, bg = p.bg_dark },
	NeoTreeNormalNC = { fg = p.fg, bg = p.bg_dark },
	NeoTreeDirectoryName = { fg = p.blue, bold = true },
	NeoTreeDirectoryIcon = { fg = p.blue },
	NeoTreeFileName = { fg = p.fg },
	TelescopeNormal = { fg = p.fg, bg = p.bg_dark },
	TelescopeBorder = { fg = p.blue, bg = p.bg_dark },
	TelescopePromptBorder = { fg = p.blue, bg = p.bg_dark },
	TelescopePromptTitle = { fg = p.bg, bg = p.blue, bold = true },
	TelescopeResultsTitle = { fg = p.bg, bg = p.yellow, bold = true },
	TelescopePreviewTitle = { fg = p.bg, bg = p.green, bold = true },
	TelescopeSelection = { fg = p.fg, bg = p.bg_selected, bold = true },
	AlphaHeader = { fg = p.fg, bold = true },
	AlphaHeaderTheme = { fg = p.fg, bold = true },
	AlphaHeaderOrange = { fg = p.orange, bold = true },
}

local completion_kinds = {
	Function = p.blue,
	Method = p.blue,
	Constructor = p.blue,
	Snippet = p.bright_magenta,
	Variable = p.orange,
	Constant = p.orange,
	Value = p.orange,
	Keyword = p.magenta,
	Statement = p.magenta,
	Class = p.yellow,
	Interface = p.yellow,
	Struct = p.yellow,
	TypeParameter = p.yellow,
	Enum = p.yellow,
	Field = p.cyan,
	Property = p.cyan,
	Operator = p.cyan,
	Module = p.blue,
	Folder = p.blue,
	File = p.green,
	Color = p.yellow,
}

for kind, color in pairs(completion_kinds) do
	highlights["CmpKindBg_" .. kind] = { fg = p.bg, bg = color, bold = true }
	highlights["CmpItemKind" .. kind] = { fg = p.bg, bg = color, bold = true }
end
highlights.CmpKindBg_Text = { fg = p.fg, bg = p.bg_highlight, bold = true }
highlights.CmpItemKindText = { fg = p.fg, bg = p.bg_highlight, bold = true }

for group, spec in pairs(highlights) do
	vim.api.nvim_set_hl(0, group, spec)
end
