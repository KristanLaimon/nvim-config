local t = require("krs.lib.krsnvim.test")
local cs = require("krs.langs.csharp")
local cli = require("krs.lib.krsnvim.cli")
local root, buf, menu, notify

t.describe("C# file creation", function()
	t.beforeEach(function()
		root = vim.fn.tempname()
		vim.fn.mkdir(root .. "/Models", "p")
		vim.fn.writefile(
			{ "<Project><PropertyGroup><RootNamespace>Acme.App</RootNamespace></PropertyGroup></Project>" },
			root .. "/App.csproj"
		)
		buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, root .. "/Models/Customer.cs")
		menu, notify = cli.menu, vim.notify
	end)

	t.afterEach(function()
		cli.menu, vim.notify = menu, notify
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
		vim.fn.delete(root, "rf")
	end)

	t.it("uses the project's namespace and relative folders for internal types", function()
		t.expect(cs.type_lines(root .. "/Models/Customer.cs", "Class")).toEqual({
			"namespace Acme.App.Models",
			"{",
			"    internal class Customer",
			"    {",
			"    }",
			"}",
		})
		for _, kind in ipairs(cs.type_templates) do
			local code = table.concat(cs.type_lines(root .. "/Models/Customer.cs", kind), "\n")
			if kind == "Empty file" then
				t.expect(code).toBe("")
			else
				t.expect(code).toContain("internal ")
			end
		end
	end)

	t.it("uses the nearest project and falls back to its name", function()
		vim.fn.writefile({ "<Project />" }, root .. "/Models/Nested.csproj")
		t.expect(cs.file_namespace(root .. "/Models/Customer.cs")).toBe("Nested")
		vim.fn.writefile(
			{ "<Project><RootNamespace>$(MSBuildProjectName).Types</RootNamespace></Project>" },
			root .. "/Models/Nested.csproj"
		)
		t.expect(cs.file_namespace(root .. "/Models/Customer.cs")).toBe("Nested.Types")
	end)

	t.it("escapes keywords and sanitizes names while allowing standalone files", function()
		t.expect(table.concat(cs.type_lines(root .. "/Models/class.cs", "Interface"), "\n"))
			.toContain("internal interface @class")
		t.expect(table.concat(cs.type_lines(root .. "/Models/2-bad.cs", "Class"), "\n")).toContain("internal class _2_bad")
		vim.fn.delete(root .. "/App.csproj")
		t.expect(cs.type_lines(root .. "/Models/Customer.cs", "Delegate")).toEqual({ "internal delegate void Customer();" })
	end)

	t.it("cancels cleanly, avoids duplicate menus, and preserves edits made during selection", function()
		local callback, calls = nil, 0
		cli.menu = function(_, _, cb)
			callback, calls = cb, calls + 1
		end
		cs.new_type(buf)
		cs.new_type(buf)
		t.expect(calls).toBe(1)
		callback(nil)
		cs.new_type(buf)
		t.expect(calls).toBe(2)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "// user's work" })
		callback("Class")
		t.expect(vim.api.nvim_buf_get_lines(buf, 0, -1, false)).toEqual({ "// user's work" })
	end)

	t.it("applies selection to the original buffer even after focus changes", function()
		local callback
		cli.menu = function(_, _, cb)
			callback = cb
		end
		cs.new_type(buf)
		callback("Record")
		t.expect(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")).toContain("internal record Customer")
	end)

	t.it("opens the real floating menu and allows reopening after Escape", function()
		local list_uis = vim.api.nvim_list_uis
		vim.api.nvim_list_uis = function()
			return { {} }
		end
		local ok, err = pcall(function()
			cs.new_type(buf)
			local popup = vim.api.nvim_get_current_buf()
			local popup_win = vim.api.nvim_get_current_win()
			t.expect(vim.bo[popup].filetype).toBe("krsmenu")
			for _, keymap in ipairs(vim.api.nvim_buf_get_keymap(popup, "n")) do
				if keymap.lhs == "<Esc>" then
					keymap.callback()
					break
				end
			end
			t.expect(vim.b[buf].csharp_template_pending).toBeNil()
			t.expect(vim.api.nvim_win_is_valid(popup_win)).toBe(false)
			cs.new_type(buf)
			popup = vim.api.nvim_get_current_buf()
			popup_win = vim.api.nvim_get_current_win()
			for _, keymap in ipairs(vim.api.nvim_buf_get_keymap(popup, "n")) do
				if keymap.lhs == "<CR>" then
					keymap.callback()
					break
				end
			end
			t.expect(vim.api.nvim_win_is_valid(popup_win)).toBe(false)
			t.expect(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")).toContain("internal class Customer")
		end)
		vim.api.nvim_list_uis = list_uis
		assert(ok, err)
	end)

	t.it("removes the popup before creating the type when window close fails", function()
		local list_uis, close_win = vim.api.nvim_list_uis, vim.api.nvim_win_close
		vim.api.nvim_list_uis = function()
			return { {} }
		end
		local ok, err = pcall(function()
			vim.api.nvim_set_current_buf(buf)
			cs.new_type(buf)
			local popup = vim.api.nvim_get_current_buf()
			vim.api.nvim_win_close = function()
				error("window close failed")
			end
			for _, keymap in ipairs(vim.api.nvim_buf_get_keymap(popup, "n")) do
				if keymap.lhs == "<CR>" then
					keymap.callback()
					break
				end
			end
		end)
		vim.api.nvim_win_close, vim.api.nvim_list_uis = close_win, list_uis
		assert(ok, err)
		t.expect(vim.api.nvim_get_current_buf() == buf).toBe(true)
		t.expect(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")).toContain("internal class Customer")
	end)

	t.it("connects new buffers and explorer creation events to the popup", function()
		local callback, calls = nil, 0
		cli.menu = function(_, _, cb)
			callback, calls = cb, calls + 1
		end
		local was_setup = vim.fn.exists("#KrsCsharp") == 1
		cs.setup()
		local ok, err = pcall(function()
			vim.api.nvim_exec_autocmds("BufNewFile", { buffer = buf })
			t.expect(vim.wait(1000, function()
				return calls == 1
			end)).toBe(true)
			callback(nil)
			vim.b[buf].csharp_template_offered = nil
			t.expect(require("krs.core.new_file").create(vim.api.nvim_buf_get_name(buf))).toBe(true)
			t.expect(vim.wait(1000, function()
				return calls == 2
			end)).toBe(true)
			callback("Interface")
			t.expect(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
				.toContain("internal interface Customer")
		end)
		if was_setup then
			cs.setup()
		else
			vim.api.nvim_del_augroup_by_name("KrsCsharp")
			vim.api.nvim_del_user_command("CsharpNewType")
		end
		assert(ok, err)
	end)

	t.it("offers templates once when opening an empty file already created on disk", function()
		local callback, calls = nil, 0
		cli.menu = function(_, _, cb)
			callback, calls = cb, calls + 1
		end
		local was_setup = vim.fn.exists("#KrsCsharp") == 1
		cs.setup()
		local ok, err = pcall(function()
			local filename = vim.api.nvim_buf_get_name(buf)
			vim.api.nvim_buf_delete(buf, { force = true })
			vim.fn.writefile({}, filename)
			vim.cmd("edit " .. vim.fn.fnameescape(filename))
			buf = vim.api.nvim_get_current_buf()
			t.expect(vim.wait(1000, function()
				return calls == 1
			end)).toBe(true)
			callback(nil)
			vim.cmd("edit!")
			vim.wait(20, function()
				return false
			end)
			t.expect(calls).toBe(1)
			vim.cmd("CsharpNewType")
			t.expect(calls).toBe(2)
			callback("Class")
		end)
		if was_setup then
			cs.setup()
		else
			vim.api.nvim_del_augroup_by_name("KrsCsharp")
			vim.api.nvim_del_user_command("CsharpNewType")
		end
		assert(ok, err)
	end)

	t.it("creates nested files exclusively and emits creation only on success", function()
		local path = root .. "/New/Deep/Item.txt"
		local events = 0
		local autocmd = vim.api.nvim_create_autocmd("User", {
			pattern = "KrsFileCreated",
			callback = function()
				events = events + 1
			end,
		})
		vim.notify = function() end
		local create = require("krs.core.new_file").create
		local ok = create(path)
		vim.fn.writefile({ "keep me" }, path)
		local duplicate = create(path)
		vim.api.nvim_del_autocmd(autocmd)
		t.expect(ok).toBe(true)
		t.expect(duplicate).toBe(false)
		t.expect(events).toBe(1)
		t.expect(vim.fn.readfile(path)).toEqual({ "keep me" })
	end)
end)

t.describe("project configuration search", function()
	t.it("finds editorconfig or formatter configuration in one upward walk", function()
		local langs = require("krs.langs")
		local dir = vim.fn.tempname()
		vim.fn.mkdir(dir .. "/src", "p")
		local buffer = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buffer, dir .. "/src/sample.ts")
		local markers = { "biome.json" }
		vim.fn.writefile({ "{}" }, dir .. "/biome.json")
		local formatter = langs.has_project_config(buffer, markers)
		vim.fn.delete(dir .. "/biome.json")
		vim.fn.writefile({ "root = true" }, dir .. "/.editorconfig")
		local editorconfig = langs.has_project_config(buffer, markers)
		vim.api.nvim_buf_delete(buffer, { force = true })
		vim.fn.delete(dir, "rf")
		t.expect(formatter).toBe(true)
		t.expect(editorconfig).toBe(true)
		t.expect(markers).toEqual({ "biome.json" })
	end)
end)
