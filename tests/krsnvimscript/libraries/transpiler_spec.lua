-- ============================================================================
-- tests/krsnvimscript/libraries/transpiler_spec.lua -- Spec tests for krsnvimtranspiler
-- ============================================================================
local t = require("krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local transpiler = require("krsnvim.krsnvimtranspiler")

describe("krsnvimtranspiler bash generation", function()
	it("transpiles basic print and variable assignments", function()
		local lua_code = 'local name = "KRS"\nprint("Hello", name)'
		local sh = transpiler.to_sh(lua_code)
		expect(sh).toContain('name="KRS"')
		expect(sh).toContain('echo "Hello" "${name}"')
	end)

	it("transpiles string concatenation", function()
		local lua_code = 'local path = dir .. "/file.txt"'
		local sh = transpiler.to_sh(lua_code)
		expect(sh).toContain('path="${dir}/file.txt"')
	end)

	it("transpiles fs module operations", function()
		local lua_code = 'if not fs.exists("dir") then\n  fs.mkdir("dir")\nend\nfs.write("dir/f.txt", "data")'
		local sh = transpiler.to_sh(lua_code)
		expect(sh).toContain('if [[ ! -e "dir" ]]; then')
		expect(sh).toContain('mkdir -p "dir"')
		expect(sh).toContain('echo "data" > "dir/f.txt"')
	end)

	it("transpiles numeric for loops", function()
		local lua_code = "for i = 1, 5 do\n  print(i)\nend"
		local sh = transpiler.to_sh(lua_code)
		expect(sh).toContain("for ((i=1; i<=5; i+=1)); do")
	end)

	it("transpiles function definitions and calls", function()
		local lua_code = "function add(a, b)\n  return a + b\nend\nadd(2, 3)"
		local sh = transpiler.to_sh(lua_code)
		expect(sh).toContain("add() {")
		expect(sh).toContain('local a="$1"')
		expect(sh).toContain("add 2 3")
	end)
end)

describe("krsnvimtranspiler powershell generation", function()
	it("transpiles basic print and variable assignments", function()
		local lua_code = 'local name = "KRS"\nprint("Hello", name)'
		local ps1 = transpiler.to_ps1(lua_code)
		expect(ps1).toContain('$name = "KRS"')
		expect(ps1).toContain('Write-Host "Hello" $name')
	end)

	it("transpiles string concatenation", function()
		local lua_code = 'local path = dir .. "/file.txt"'
		local ps1 = transpiler.to_ps1(lua_code)
		expect(ps1).toContain('$path = $dir + "/file.txt"')
	end)

	it("transpiles fs module operations", function()
		local lua_code = 'if not fs.exists("dir") then\n  fs.mkdir("dir")\nend'
		local ps1 = transpiler.to_ps1(lua_code)
		expect(ps1).toContain('if (-not (Test-Path "dir")) {')
		expect(ps1).toContain('New-Item -ItemType Directory -Force -Path "dir"')
	end)

	it("transpiles conditionals with logical operators", function()
		local lua_code = 'if a >= 10 and b < 5 then\n  print("yes")\nend'
		local ps1 = transpiler.to_ps1(lua_code)
		expect(ps1).toContain("if ($a -ge 10 -and $b -lt 5) {")
	end)

	it("transpiles function definitions and calls", function()
		local lua_code = 'function greet(user)\n  print("Hi", user)\nend\ngreet("Alice")'
		local ps1 = transpiler.to_ps1(lua_code)
		expect(ps1).toContain("function greet($user) {")
		expect(ps1).toContain('greet "Alice"')
	end)
end)
