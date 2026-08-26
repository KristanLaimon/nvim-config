-- ============================================================================
-- tests/spec/folding_spec.lua
-- Unit tests for plugins/krs/folding.lua (HTML, functions, scope folding & persistence).
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach

local folding = require("plugins.krs.editor.folding")

describe("plugins.krs.editor.folding", function()
	local buf

	beforeEach(function()
		buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, "test_component.tsx")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
			"function MyComponent() {",
			"  return (",
			"    <div>",
			"      <h1>Hello World</h1>",
			"    </div>",
			"  );",
			"}",
		})
		vim.api.nvim_set_current_buf(buf)
	end)

	afterEach(function()
		if buf and vim.api.nvim_buf_is_valid(buf) then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end)

	it("applies fold options for code buffer", function()
		folding.apply_fold_options(buf)
		expect(vim.wo.foldmethod).toBe("expr")
		expect(vim.wo.foldexpr).toBe("v:lua.vim.treesitter.foldexpr()")
		expect(vim.wo.foldenable).toBeTruthy()
		expect(vim.wo.foldcolumn).toBe("1")
	end)

	it("registers user commands for folding and view persistence", function()
		folding.setup()

		expect(vim.fn.exists(":FoldToggle")).toBe(2)
		expect(vim.fn.exists(":FoldOpenAll")).toBe(2)
		expect(vim.fn.exists(":FoldCloseAll")).toBe(2)
		expect(vim.fn.exists(":FoldFunctions")).toBe(2)
		expect(vim.fn.exists(":FoldHTML")).toBe(2)
		expect(vim.fn.exists(":FoldScopes")).toBe(2)
		expect(vim.fn.exists(":FoldSave")).toBe(2)
		expect(vim.fn.exists(":FoldRestore")).toBe(2)
		expect(vim.fn.exists(":FoldClearViews")).toBe(2)
	end)

	it("resolves folds storage directory inside .krsnvim", function()
		local dir = folding.get_folds_dir()
		expect(dir:find(".krsnvim", 1, true)).toBeTruthy()
	end)

	it("executes fold level helper functions without error", function()
		folding.fold_functions()
		expect(vim.wo.foldlevel).toBe(1)

		folding.fold_html()
		expect(vim.wo.foldlevel).toBe(1)

		folding.fold_scopes()
		expect(vim.wo.foldlevel).toBe(2)

		folding.open_all()
		folding.close_all()
	end)

	it("toggles fold cleanly via toggle_fold()", function()
		folding.apply_fold_options(buf)
		vim.api.nvim_win_set_cursor(0, { 1, 0 })

		local ok = pcall(folding.toggle_fold)
		expect(ok).toBeTruthy()
	end)

	it("handles fold view save and restore cleanly", function()
		expect(pcall(folding.save_fold_view, buf)).toBeTruthy()
		expect(pcall(folding.restore_fold_view, buf)).toBeTruthy()
		expect(pcall(folding.clear_stored_folds)).toBeTruthy()
	end)
end)
