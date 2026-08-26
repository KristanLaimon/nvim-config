local settings = {
	--- Extension -> filetype registrations.
	filetypes = { krsnvim = "krsnvim" },

	--- Filetypes that borrow another language's syntax and Treesitter parser.
	syntax_aliases = { krsnvim = "lua" },
}

local M = {}

function M.setup()
	vim.filetype.add({ extension = settings.filetypes })

	for filetype, language in pairs(settings.syntax_aliases) do
		-- Treesitter needs the alias registered; `syntax` is the fallback highlighter.
		pcall(function()
			vim.treesitter.language.register(language, filetype)
		end)
		vim.api.nvim_create_autocmd("FileType", {
			pattern = filetype,
			callback = function()
				vim.bo.syntax = language
			end,
		})
	end
end

return M
