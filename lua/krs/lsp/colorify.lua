-- ============================================================================
-- KRS LSP: Colorify -- Hex color extraction & NvChad completion styling.
-- ============================================================================
-- Formats completion kind icons with distinct background & accent colors per kind,
-- provides contrast-aware dynamic background colors for CSS/Tailwind hex values,
-- and formats kind name labels on the right.
-- ============================================================================

local M = {}

--- Default Nerdfont icons matching NvChad completion layout.
M.kind_icons = {
	Text = "󰉿",
	Method = "󰆧",
	Function = "󰊕",
	Constructor = "",
	Field = "󰜢",
	Variable = "󰀫",
	Class = "󰌗",
	Interface = "",
	Module = "",
	Property = "󰜢",
	Unit = "󰑭",
	Value = "󰎠",
	Enum = "",
	Keyword = "󰌋",
	Snippet = "󰩫",
	Color = "󰏘",
	File = "󰈙",
	Reference = "EF",
	Folder = "󰉋",
	EnumMember = "",
	Constant = "󰏿",
	Struct = "󰙅",
	Event = "",
	Operator = "󰆕",
	TypeParameter = "󰅲",
}

--- Kind-to-palette color mapping for default fallback highlights.
M.kind_colors = {
	Function = { bg = "#E3A70E", fg = "#151515" },
	Method = { bg = "#E3A70E", fg = "#151515" },
	Constructor = { bg = "#E3A70E", fg = "#151515" },
	Snippet = { bg = "#D233A2", fg = "#FFFFFF" },
	Variable = { bg = "#d776ae", fg = "#151515" },
	Constant = { bg = "#d776ae", fg = "#151515" },
	Value = { bg = "#d776ae", fg = "#151515" },
	Keyword = { bg = "#6d7fd4", fg = "#FFFFFF" },
	Statement = { bg = "#6d7fd4", fg = "#FFFFFF" },
	Class = { bg = "#5cd7d7", fg = "#151515" },
	Interface = { bg = "#5cd7d7", fg = "#151515" },
	Struct = { bg = "#5cd7d7", fg = "#151515" },
	TypeParameter = { bg = "#5cd7d7", fg = "#151515" },
	Enum = { bg = "#5cd7d7", fg = "#151515" },
	Field = { bg = "#62e665", fg = "#151515" },
	Property = { bg = "#62e665", fg = "#151515" },
	Operator = { bg = "#62e665", fg = "#151515" },
	Module = { bg = "#d2824e", fg = "#151515" },
	Folder = { bg = "#d2824e", fg = "#151515" },
	File = { bg = "#95acbd", fg = "#151515" },
	Text = { bg = "#5b574a", fg = "#FFFFFF" },
	Color = { bg = "#5cd7d7", fg = "#151515" },
}

--- Tailwind CSS default color palette lookup table (v3 & v4).
M.tailwind_colors = {
	slate = {
		["50"] = "#f8fafc",
		["100"] = "#f1f5f9",
		["200"] = "#e2e8f0",
		["300"] = "#cbd5e1",
		["400"] = "#94a3b8",
		["500"] = "#64748b",
		["600"] = "#475569",
		["700"] = "#334155",
		["800"] = "#1e293b",
		["900"] = "#0f172a",
		["950"] = "#020617",
	},
	gray = {
		["50"] = "#f9fafb",
		["100"] = "#f3f4f6",
		["200"] = "#e5e7eb",
		["300"] = "#d1d5db",
		["400"] = "#9ca3af",
		["500"] = "#6b7280",
		["600"] = "#4b5563",
		["700"] = "#374151",
		["800"] = "#1f2937",
		["900"] = "#111827",
		["950"] = "#030712",
	},
	zinc = {
		["50"] = "#fafafa",
		["100"] = "#f4f4f5",
		["200"] = "#e4e4e7",
		["300"] = "#d4d4d8",
		["400"] = "#a1a1aa",
		["500"] = "#71717a",
		["600"] = "#52525b",
		["700"] = "#3f3f46",
		["800"] = "#27272a",
		["900"] = "#18181b",
		["950"] = "#09090b",
	},
	neutral = {
		["50"] = "#fafafa",
		["100"] = "#f5f5f5",
		["200"] = "#e5e5e5",
		["300"] = "#d4d4d4",
		["400"] = "#a3a3a3",
		["500"] = "#737373",
		["600"] = "#525252",
		["700"] = "#404040",
		["800"] = "#262626",
		["900"] = "#171717",
		["950"] = "#0a0a0a",
	},
	stone = {
		["50"] = "#fafaf9",
		["100"] = "#f5f5f4",
		["200"] = "#e7e5e4",
		["300"] = "#d6d3d1",
		["400"] = "#a8a29e",
		["500"] = "#78716c",
		["600"] = "#57534e",
		["700"] = "#44403c",
		["800"] = "#292524",
		["900"] = "#1c1917",
		["950"] = "#0c0a09",
	},
	red = {
		["50"] = "#fef2f2",
		["100"] = "#fee2e2",
		["200"] = "#fecaca",
		["300"] = "#fca5a5",
		["400"] = "#f87171",
		["500"] = "#ef4444",
		["600"] = "#dc2626",
		["700"] = "#b91c1c",
		["800"] = "#991b1b",
		["900"] = "#7f1d1d",
		["950"] = "#450a0a",
	},
	orange = {
		["50"] = "#fff7ed",
		["100"] = "#ffedd5",
		["200"] = "#fed7aa",
		["300"] = "#fdba74",
		["400"] = "#fb923c",
		["500"] = "#f97316",
		["600"] = "#ea580c",
		["700"] = "#c2410c",
		["800"] = "#9a3412",
		["900"] = "#7c2d12",
		["950"] = "#431407",
	},
	amber = {
		["50"] = "#fffbeb",
		["100"] = "#fef3c7",
		["200"] = "#fde68a",
		["300"] = "#fcd34d",
		["400"] = "#fbbf24",
		["500"] = "#f59e0b",
		["600"] = "#d97706",
		["700"] = "#b45309",
		["800"] = "#92400e",
		["900"] = "#78350f",
		["950"] = "#451a03",
	},
	yellow = {
		["50"] = "#fefce8",
		["100"] = "#fef9c3",
		["200"] = "#fef08a",
		["300"] = "#fde047",
		["400"] = "#facc15",
		["500"] = "#eab308",
		["600"] = "#ca8a04",
		["700"] = "#a16207",
		["800"] = "#854d0e",
		["900"] = "#713f12",
		["950"] = "#422006",
	},
	lime = {
		["50"] = "#f7fee7",
		["100"] = "#ecfccb",
		["200"] = "#d9f99d",
		["300"] = "#bef264",
		["400"] = "#a3e635",
		["500"] = "#84cc16",
		["600"] = "#65a30d",
		["700"] = "#4d7c0f",
		["800"] = "#3f6212",
		["900"] = "#365314",
		["950"] = "#1a2e05",
	},
	green = {
		["50"] = "#f0fdf4",
		["100"] = "#dcfce7",
		["200"] = "#bbf7d0",
		["300"] = "#86efac",
		["400"] = "#4ade80",
		["500"] = "#22c55e",
		["600"] = "#16a34a",
		["700"] = "#15803d",
		["800"] = "#166534",
		["900"] = "#14532d",
		["950"] = "#052e16",
	},
	emerald = {
		["50"] = "#ecfdf5",
		["100"] = "#d1fae5",
		["200"] = "#a7f3d0",
		["300"] = "#6ee7b7",
		["400"] = "#34d399",
		["500"] = "#10b981",
		["600"] = "#059669",
		["700"] = "#047857",
		["800"] = "#065f46",
		["900"] = "#064e3b",
		["950"] = "#022c22",
	},
	teal = {
		["50"] = "#f0fdfa",
		["100"] = "#ccfbf1",
		["200"] = "#99f6e4",
		["300"] = "#5eead4",
		["400"] = "#2dd4bf",
		["500"] = "#14b8a6",
		["600"] = "#0d9488",
		["700"] = "#0f766e",
		["800"] = "#115e59",
		["900"] = "#134e4a",
		["950"] = "#042f2e",
	},
	cyan = {
		["50"] = "#ecfeff",
		["100"] = "#cffaff",
		["200"] = "#a5f3fc",
		["300"] = "#67e8f9",
		["400"] = "#22d3ee",
		["500"] = "#06b6d4",
		["600"] = "#0891b2",
		["700"] = "#0e7490",
		["800"] = "#155e75",
		["900"] = "#164e63",
		["950"] = "#083344",
	},
	sky = {
		["50"] = "#f0f9ff",
		["100"] = "#e0f2fe",
		["200"] = "#bae6fd",
		["300"] = "#7dd3fc",
		["400"] = "#38bdf8",
		["500"] = "#0ea5e9",
		["600"] = "#0284c7",
		["700"] = "#0369a1",
		["800"] = "#075985",
		["900"] = "#0c4a6e",
		["950"] = "#082f49",
	},
	blue = {
		["50"] = "#eff6ff",
		["100"] = "#dbeafe",
		["200"] = "#bfdbfe",
		["300"] = "#93c5fd",
		["400"] = "#60a5fa",
		["500"] = "#3b82f6",
		["600"] = "#2563eb",
		["700"] = "#1d4ed8",
		["800"] = "#1e40af",
		["900"] = "#1e3a8a",
		["950"] = "#172554",
	},
	indigo = {
		["50"] = "#eef2ff",
		["100"] = "#e0e7ff",
		["200"] = "#c7d2fe",
		["300"] = "#a5b4fc",
		["400"] = "#818cf8",
		["500"] = "#6366f1",
		["600"] = "#4f46e5",
		["700"] = "#4338ca",
		["800"] = "#3730a3",
		["900"] = "#312e81",
		["950"] = "#1e1b4b",
	},
	violet = {
		["50"] = "#f5f3ff",
		["100"] = "#ede9fe",
		["200"] = "#ddd6fe",
		["300"] = "#c4b5fd",
		["400"] = "#a78bfa",
		["500"] = "#8b5cf6",
		["600"] = "#7c3aed",
		["700"] = "#6d28d9",
		["800"] = "#5b21b6",
		["900"] = "#4c1d95",
		["950"] = "#2e1065",
	},
	purple = {
		["50"] = "#faf5ff",
		["100"] = "#f3e8ff",
		["200"] = "#e9d5ff",
		["300"] = "#d8b4fe",
		["400"] = "#c084fc",
		["500"] = "#a855f7",
		["600"] = "#9333ea",
		["700"] = "#7e22ce",
		["800"] = "#6b21a8",
		["900"] = "#581c87",
		["950"] = "#3b0764",
	},
	fuchsia = {
		["50"] = "#fdf4ff",
		["100"] = "#fae8ff",
		["200"] = "#f5d0fe",
		["300"] = "#f0abfc",
		["400"] = "#e879f9",
		["500"] = "#d946ef",
		["600"] = "#c026d3",
		["700"] = "#a21caf",
		["800"] = "#86198f",
		["900"] = "#701a75",
		["950"] = "#4a044e",
	},
	pink = {
		["50"] = "#fdf2f8",
		["100"] = "#fce7f3",
		["200"] = "#fbcfe8",
		["300"] = "#f9a8d4",
		["400"] = "#f472b6",
		["500"] = "#ec4899",
		["600"] = "#db2777",
		["700"] = "#be185d",
		["800"] = "#9d174d",
		["900"] = "#831843",
		["950"] = "#500724",
	},
	rose = {
		["50"] = "#fff1f2",
		["100"] = "#ffe4e6",
		["200"] = "#fecdd3",
		["300"] = "#fda4af",
		["400"] = "#fb7185",
		["500"] = "#f43f5e",
		["600"] = "#e11d48",
		["700"] = "#be123c",
		["800"] = "#9f1239",
		["900"] = "#881337",
		["950"] = "#4c0519",
	},
}

--- Standard named CSS colors lookup.
M.named_colors = {
	black = "#000000",
	white = "#ffffff",
	red = "#ff0000",
	green = "#008000",
	blue = "#0000ff",
	yellow = "#ffff00",
	cyan = "#00ffff",
	magenta = "#ff00ff",
	gray = "#808080",
	grey = "#808080",
	orange = "#ffa500",
	purple = "#800080",
	pink = "#ffc0cb",
	lime = "#00ff00",
	teal = "#008080",
	navy = "#000080",
	indigo = "#4b0082",
	violet = "#ee82ee",
	gold = "#ffd700",
	silver = "#c0c0c0",
	sky = "#87ceeb",
	amber = "#ffbf00",
	emerald = "#50c878",
	rose = "#ff007f",
	slate = "#708090",
	zinc = "#71717a",
	neutral = "#737373",
	stone = "#78716c",
}

--- Calculates contrasting foreground text color (black or white) for a given hex background.
--- @param hex string e.g. "#ff0055"
--- @return string fg "#151515" or "#ffffff"
function M.get_contrast_fg(hex)
	if not hex or #hex < 7 then
		return "#ffffff"
	end
	local r = tonumber(hex:sub(2, 3), 16) or 255
	local g = tonumber(hex:sub(4, 5), 16) or 255
	local b = tonumber(hex:sub(6, 7), 16) or 255
	local luminance = (0.299 * r + 0.587 * g + 0.114 * b)
	if luminance > 140 then
		return "#151515"
	end
	return "#ffffff"
end

--- Converts HSL color values to hex string.
--- @param h number|string hue 0..360
--- @param s number|string saturation 0..100
--- @param l number|string lightness 0..100
--- @return string hex
function M.hsl_to_hex(h, s, l)
	local nh = (tonumber(h) or 0) / 360
	local ns = (tonumber(s) or 0) / 100
	local nl = (tonumber(l) or 0) / 100

	local r, g, b
	if ns == 0 then
		r, g, b = nl, nl, nl
	else
		local function hue2rgb(p, q, t)
			if t < 0 then
				t = t + 1
			end
			if t > 1 then
				t = t - 1
			end
			if t < 1 / 6 then
				return p + (q - p) * 6 * t
			end
			if t < 1 / 2 then
				return q
			end
			if t < 2 / 3 then
				return p + (q - p) * (2 / 3 - t) * 6
			end
			return p
		end
		local q = nl < 0.5 and nl * (1 + ns) or nl + ns - nl * ns
		local p = 2 * nl - q
		r = hue2rgb(p, q, nh + 1 / 3)
		g = hue2rgb(p, q, nh)
		b = hue2rgb(p, q, nh - 1 / 3)
	end
	return string.format("#%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

--- Converts OKLCH color values to hex string.
--- @param l number|string lightness 0..1
--- @param c number|string chroma
--- @param h number|string hue angle
--- @return string hex
function M.oklch_to_hex(l, c, h)
	local nl = tonumber(l) or 0
	local nc = tonumber(c) or 0
	local nh = tonumber(h) or 0

	local rad = nh * math.pi / 180
	local a_ = nc * math.cos(rad)
	local b_ = nc * math.sin(rad)

	local l_ = nl + 0.3963377774 * a_ + 0.2158037573 * b_
	local m_ = nl - 0.1055613458 * a_ - 0.0638541728 * b_
	local s_ = nl - 0.0894841775 * a_ - 1.2914855480 * b_

	local l3 = l_ * l_ * l_
	local m3 = m_ * m_ * m_
	local s3 = s_ * s_ * s_

	local r = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
	local g = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
	local b = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3

	local function clamp(val)
		if val <= 0.0031308 then
			val = 12.92 * val
		else
			val = 1.055 * math.pow(val, 1 / 2.4) - 0.055
		end
		return math.floor(math.max(0, math.min(255, val * 255)) + 0.5)
	end

	return string.format("#%02x%02x%02x", clamp(r), clamp(g), clamp(b))
end

--- Parses a hex/rgb/hsl/oklch color string from input text.
--- @param str string|nil
--- @return string|nil hex_code e.g. "#ef4444"
function M.extract_hex_color(str)
	if not str or type(str) ~= "string" or #str < 3 then
		return nil
	end

	-- 6 or 8-digit hex (#abcdef or #abcdef00)
	local hex6 = str:match("#(%x%x%x%x%x%x)")
	if hex6 then
		return "#" .. hex6:lower()
	end

	-- 3-digit hex (#f00 -> #ff0000)
	local hex3 = str:match("#(%x%x%x)")
	if hex3 then
		local r, g, b = hex3:sub(1, 1), hex3:sub(2, 2), hex3:sub(3, 3)
		return ("#" .. r .. r .. g .. g .. b .. b):lower()
	end

	-- rgb(r, g, b) or rgba(r, g, b, a)
	local r, g, b = str:match("rgba?%s*%((%d+)%s*[,%s]%s*(%d+)%s*[,%s]%s*(%d+)")
	if r and g and b then
		local nr, ng, nb = tonumber(r), tonumber(g), tonumber(b)
		if nr and ng and nb and nr <= 255 and ng <= 255 and nb <= 255 then
			return string.format("#%02x%02x%02x", nr, ng, nb)
		end
	end

	-- hsl(h, s%, l%) or hsla(h, s%, l%, a)
	local h, s, l = str:match("hsla?%s*%((%d+%.?%d*)%s*[,%s]%s*(%d+%.?%d*)%%%s*[,%s]%s*(%d+%.?%d*)%%")
	if h and s and l then
		return M.hsl_to_hex(h, s, l)
	end

	-- oklch(L C H) or oklch(L% C H)
	local ol, oc, oh = str:match("oklch%s*%((%d+%.?%d*)%%%s+(%d+%.?%d*)%s+(%d+%.?%d*)")
	if ol and oc and oh then
		return M.oklch_to_hex(tonumber(ol) / 100, oc, oh)
	end
	ol, oc, oh = str:match("oklch%s*%((%d+%.?%d*)%s+(%d+%.?%d*)%s+(%d+%.?%d*)")
	if ol and oc and oh then
		return M.oklch_to_hex(ol, oc, oh)
	end

	return nil
end

--- Extracts color hex from Tailwind class names or named CSS colors.
--- @param str string|nil
--- @return string|nil hex_code
function M.extract_color_by_name(str)
	if not str or type(str) ~= "string" or #str < 3 then
		return nil
	end

	local s = str:lower()

	-- Check Tailwind class name pattern e.g. "bg-red-500", "hover:text-sky-400", "border-emerald-600/50"
	local color_name, shade = s:match("([a-z]+)%-(%d+)")
	if color_name and shade and M.tailwind_colors[color_name] then
		local hex = M.tailwind_colors[color_name][shade]
		if hex then
			return hex
		end
	end

	-- Check special Tailwind names e.g. "bg-black", "text-white"
	if s:find("black") then
		return "#000000"
	end
	if s:find("white") then
		return "#ffffff"
	end

	-- Check exact named colors e.g. "red", "black", "white"
	for name, hex in pairs(M.named_colors) do
		if s == name or s:find("%f[%w]" .. name .. "%f[%W]") then
			if hex ~= "transparent" then
				return hex
			end
		end
	end

	return nil
end

--- Extract hex color from blink.cmp context object.
--- Inspects label, description, detail, documentation, labelDetails.
--- @param ctx table|nil
--- @return string|nil hex_code
function M.extract_color_from_ctx(ctx)
	if not ctx then
		return nil
	end

	local candidates = {}

	if ctx.label and type(ctx.label) == "string" then
		table.insert(candidates, ctx.label)
	end
	if ctx.label_description and type(ctx.label_description) == "string" then
		table.insert(candidates, ctx.label_description)
	end

	if ctx.item then
		if ctx.item.detail and type(ctx.item.detail) == "string" then
			table.insert(candidates, ctx.item.detail)
		end

		if ctx.item.documentation then
			if type(ctx.item.documentation) == "string" then
				table.insert(candidates, ctx.item.documentation)
			elseif type(ctx.item.documentation) == "table" and type(ctx.item.documentation.value) == "string" then
				table.insert(candidates, ctx.item.documentation.value)
			end
		end

		if ctx.item.labelDetails then
			if type(ctx.item.labelDetails.description) == "string" then
				table.insert(candidates, ctx.item.labelDetails.description)
			end
			if type(ctx.item.labelDetails.detail) == "string" then
				table.insert(candidates, ctx.item.labelDetails.detail)
			end
		end
	end

	-- Step 1: Try hex/rgb/hsl/oklch extraction across all candidate strings
	for _, str in ipairs(candidates) do
		local hex = M.extract_hex_color(str)
		if hex then
			return hex
		end
	end

	-- Step 2: Try Tailwind class or CSS named color extraction
	for _, str in ipairs(candidates) do
		local hex = M.extract_color_by_name(str)
		if hex then
			return hex
		end
	end

	return nil
end

--- Generates or reuses a Neovim highlight group for a color hex string with background color.
--- @param hex string
--- @return string hl_name
function M.get_or_create_color_hl(hex)
	if not hex or type(hex) ~= "string" then
		return "Normal"
	end
	local sanitized = hex:gsub("#", "")
	local hl_name = "CmpColor_" .. sanitized
	pcall(vim.api.nvim_set_hl, 0, hl_name, { fg = hex, bg = hex, bold = true })
	return hl_name
end

--- Gets or initializes highlight group for a completion item kind with background and accent color.
--- @param kind string|nil
--- @return string hl_name
function M.get_kind_hl(kind)
	if not kind or kind == "" then
		kind = "Text"
	end

	local hl_name = "CmpKindBg_" .. kind
	local existing = vim.api.nvim_get_hl(0, { name = hl_name })
	if existing and (existing.bg or existing.fg) then
		return hl_name
	end

	-- Fallback highlight setup if theme hasn't declared CmpKindBg_<Kind>
	local spec = M.kind_colors[kind] or M.kind_colors.Text
	pcall(vim.api.nvim_set_hl, 0, hl_name, { fg = spec.fg, bg = spec.bg, bold = true })
	return hl_name
end

--- Formats completion item kind text on the right side of completion list (e.g. `<Snippet>`, `<Function>`).
--- @param kind string|nil
--- @return string formatted
function M.format_kind_label(kind)
	if not kind or kind == "" then
		return "<Item>"
	end
	return "<" .. kind .. ">"
end

--- Gets icon string for a completion item kind with NvChad-style padding.
--- @param kind string|nil
--- @return string icon
function M.get_kind_icon(kind)
	if not kind then
		return " 󰉿 "
	end
	local icon = M.kind_icons[kind] or "󰉿"
	return " " .. icon .. " "
end

return M
