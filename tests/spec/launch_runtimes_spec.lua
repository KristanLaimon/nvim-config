-- ============================================================================
-- tests/spec/launch_runtimes_spec.lua -- Runtime registry contracts.
-- ============================================================================
-- This is the table you edit to add a language, so the tests pin what a runtime
-- entry must produce: a terminal command line and a DAP configuration.
-- Anything that shells out (`node -v`, dotnet globs) is avoided or sandboxed.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local runtimes = require("krs.launch.runtimes")

local ROOT = "C:/proj"

--- Minimal profile for the runtime under test.
local function profile(runtime, overrides)
	return vim.tbl_extend("force", {
		id = "p1",
		name = "Test",
		runtime = runtime,
		entry_point = "src/index.js",
		args = {},
		mode = "debug",
	}, overrides or {})
end

describe("runtimes.build_command", function()
	it("prefixes the entry point with the runtime executable", function()
		expect(runtimes.build_command(profile("bun"), ROOT)).toBe("bun src/index.js")
		expect(runtimes.build_command(profile("python"), ROOT)).toBe("python src/index.js")
		expect(runtimes.build_command(profile("go", { entry_point = "main.go" }), ROOT)).toBe("go run main.go")
		expect(runtimes.build_command(profile("php"), ROOT)).toBe("php src/index.js")
		expect(runtimes.build_command(profile("deno"), ROOT)).toBe("deno run -A src/index.js")
	end)

	it("normalizes incompatible entry points for Go", function()
		local tmp = vim.fn.tempname()
		vim.fn.mkdir(tmp, "p")
		local main_go = tmp .. "/main.go"
		local f = io.open(main_go, "w")
		if f then
			f:write("package main\nfunc main() {}\n")
			f:close()
		end

		local cmd = runtimes.build_command(profile("go", { entry_point = "src/index.ts" }), tmp)
		expect(cmd).toBe("go run main.go")
		vim.fn.delete(tmp, "rf")
	end)

	it("targets the project, not the file, for dotnet", function()
		local cmd = runtimes.build_command(profile("dotnet", { entry_point = "Api/Api.csproj" }), ROOT)

		expect(cmd).toBe("dotnet run --project Api/Api.csproj")
	end)

	it("appends arguments after the entry point", function()
		local cmd = runtimes.build_command(profile("node", { args = { "--watch", "--port=3000" } }), ROOT)

		expect(cmd).toBe("node src/index.js --watch --port=3000")
	end)

	it("routes TypeScript entry points through npx tsx", function()
		expect(runtimes.build_command(profile("node", { entry_point = "src/main.ts" }), ROOT)).toBe("npx tsx src/main.ts")
	end)

	it("runs the entry point as-is for the custom runtime", function()
		expect(runtimes.build_command(profile("custom", { entry_point = "./run.sh" }), ROOT)).toBe("./run.sh")
	end)

	it("falls back to the custom runtime for unknown names", function()
		expect(runtimes.build_command(profile("cobol", { entry_point = "main.cob" }), ROOT)).toBe("main.cob")
	end)

	it("returns no command for runtimes that execute themselves", function()
		local cmd = runtimes.build_command(profile("krsnvimtranspiler"), ROOT)

		expect(cmd).toBeNil()
		expect(runtimes.get("krsnvimtranspiler").execute).toBeDefined()
	end)

	it("also returns the launch context for reuse", function()
		local _, ctx = runtimes.build_command(profile("bun", { entry_point = "src/main.ts" }), ROOT)

		expect(ctx.root).toBe(ROOT)
		expect(ctx.full_entry).toBe("C:/proj/src/main.ts")
		expect(ctx.is_ts).toBeTruthy()
	end)
end)

describe("runtimes.build_dap_config", function()
	it("uses the adapter each language registers", function()
		expect(runtimes.build_dap_config(profile("go"), ROOT).type).toBe("go")
		expect(runtimes.build_dap_config(profile("python"), ROOT).type).toBe("python")
		expect(runtimes.build_dap_config(profile("php"), ROOT).type).toBe("php")
		expect(runtimes.build_dap_config(profile("bun"), ROOT).type).toBe("bun")
		expect(runtimes.build_dap_config(profile("krsnvimscript"), ROOT).type).toBe("krsnvimscript")
	end)

	it("defaults to js-debug for node and unknown runtimes", function()
		expect(runtimes.build_dap_config(profile("node"), ROOT).type).toBe("pwa-node")
		expect(runtimes.build_dap_config(profile("cobol"), ROOT).type).toBe("pwa-node")
	end)

	it("points the program at the absolute entry point", function()
		local cfg = runtimes.build_dap_config(profile("python", { entry_point = "app/main.py" }), ROOT)

		expect(cfg.program).toBe("C:/proj/app/main.py")
		expect(cfg.cwd).toBe(ROOT)
	end)

	it("keeps js-debug out of node internals", function()
		expect(runtimes.build_dap_config(profile("node"), ROOT).skipFiles).toEqual(
			require("krs.langs.typescript").js_skip_files
		)
	end)

	it("attaches deno to its inspector port", function()
		local cfg = runtimes.build_dap_config(profile("deno"), ROOT)

		expect(cfg.runtimeExecutable).toBe("deno")
		expect(cfg.attachSimplePort).toBe(require("krs.langs.typescript").deno_inspect_port)
	end)

	it("waits for xdebug to connect back on the configured port", function()
		local cfg = runtimes.build_dap_config(profile("php"), ROOT)

		expect(cfg.port).toBe(require("krs.langs.php").php_debug_port)
		expect(cfg.pathMappings["/var/www/html"]).toBe(ROOT)
	end)

	it("returns nil when a dotnet build is missing, rather than a broken config", function()
		local cfg = runtimes.build_dap_config(profile("dotnet", { entry_point = "Api/Api.csproj" }), vim.fn.tempname())

		expect(cfg).toBeNil()
	end)

	it("accepts a pre-built dll as the entry point", function()
		local cfg = runtimes.build_dap_config(profile("dotnet", { entry_point = "bin/App.dll" }), ROOT)

		expect(cfg.type).toBe("coreclr")
		expect(cfg.program).toBe("C:/proj/bin/App.dll")
	end)
end)

describe("runtimes registry integrity", function()
	it("lists every registered runtime in the form cycle order", function()
		for _, name in ipairs(runtimes.order) do
			expect(runtimes.registry[name]).toBeDefined()
		end
		expect(#runtimes.order).toBe(vim.tbl_count(runtimes.registry))
	end)

	it("gives every runtime a way to start: command or execute", function()
		for name, def in pairs(runtimes.registry) do
			local runnable = def.command ~= nil or def.execute ~= nil
			expect({ name = name, runnable = runnable }).toEqual({ name = name, runnable = true })
		end
	end)
end)
