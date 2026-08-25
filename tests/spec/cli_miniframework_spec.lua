-- ============================================================================
-- tests/spec/cli_miniframework_spec.lua
-- Comprehensive unit tests for krsnvim.cli mini-framework and krsnvim.terminal.
-- ============================================================================

local t = require("krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

local krsnvim = require("krsnvim")
local cli = krsnvim.cli
local terminal = krsnvim.terminal

describe("krsnvim.cli mini-framework", function()
	it("generates ASCII title banners from single text parameter string", function()
		local banner = cli.ascii_title("KRS")
		expect(type(banner)).toBe("string")
		expect(#banner > 0).toBeTruthy()
		expect(banner:find("█")).toBeTruthy()
	end)

	it("supports color and subtitle parameters in ascii_title", function()
		cli.force_color = true
		local banner = cli.ascii_title("TEST", {
			color = cli.colors.green,
			subtitle = "Automation Suite",
		})
		cli.force_color = false
		expect(banner:find("Automation Suite")).toBeTruthy()
		expect(banner:find("\27%[%d+m")).toBeTruthy()
	end)

	it("formats box containers with title and style options", function()
		local rounded = cli.box({ "Status: Active", "Port: 8080" }, { title = "SERVER", style = "rounded" })
		expect(rounded:find("╭─ SERVER")).toBeTruthy()
		expect(rounded:find("Status: Active")).toBeTruthy()

		local double = cli.box("Single line text", { style = "double" })
		expect(double:find("╔═")).toBeTruthy()
		expect(double:find("Single line text")).toBeTruthy()
	end)

	it("formats tabular data with aligned headers and rows", function()
		local tbl = cli.table({ "ID", "Name", "Role" }, {
			{ "1", "Alice", "Admin" },
			{ "2", "Bob", "User" },
		})
		expect(tbl:find("ID")).toBeTruthy()
		expect(tbl:find("Name")).toBeTruthy()
		expect(tbl:find("Alice")).toBeTruthy()
		expect(tbl:find("Admin")).toBeTruthy()
	end)

	it("colorize wraps strings with ANSI escape sequences", function()
		cli.force_color = true
		local colored = cli.colorize("Hello", cli.colors.red)
		cli.force_color = false
		expect(colored:sub(1, #cli.colors.red)).toBe(cli.colors.red)
		expect(colored:sub(-#cli.colors.reset)).toBe(cli.colors.reset)
	end)

	it("parses CLI argument flags and positional parameters", function()
		local args = cli.parse_args({ "--env=staging", "--verbose", "-f", "deploy", "server" })
		expect(args.flags.env).toBe("staging")
		expect(args.flags.verbose).toBe(true)
		expect(args.flags.f).toBe(true)
		expect(args.positional[1]).toBe("deploy")
		expect(args.positional[2]).toBe("server")
	end)

	it("generates formatted help documentation string", function()
		local help_text = cli.help({
			name = "BUILD TOOL",
			description = "Compiles assets",
			options = { env = "Target environment" },
		})
		expect(help_text:find("Usage: BUILD TOOL")).toBeTruthy()
		expect(help_text:find("Compiles assets")).toBeTruthy()
		expect(help_text:find("--env")).toBeTruthy()
	end)

	it("executes tasks inside spinner wrapper", function()
		local ran = false
		local val = cli.spinner("Processing...", function()
			ran = true
			return 99
		end)
		expect(ran).toBeTruthy()
		expect(val).toBe(99)
	end)

	it("executes terminal shell commands cleanly via terminal.exec", function()
		local res = terminal.exec("echo test_cli_runner")
		expect(res.ok).toBeTruthy()
		expect(res.code).toBe(0)
		expect(res.output:find("test_cli_runner")).toBeTruthy()
	end)

	it("supports callable execution syntax on terminal module", function()
		local res = terminal("echo callable_test")
		expect(res.ok).toBeTruthy()
		expect(res.stdout:find("callable_test")).toBeTruthy()
	end)
end)
