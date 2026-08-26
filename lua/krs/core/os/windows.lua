-- ============================================================================
-- KRS OS: Windows-only implementations
-- ============================================================================
-- WHAT IT DOES
--   Holds every bit of logic that only exists because Windows has no other way
--   to do it (a Win32 API call, a PowerShell script). Never require this file
--   directly from feature code -- go through lua/krs/core/os/shared.lua, which
--   picks the right implementation for the running OS.
-- ============================================================================

local M = {}

-- ============================================================================
-- CAPS LOCK STATE (user32.dll GetKeyState)
-- ============================================================================

local ffi_ok, ffi = pcall(require, "ffi")
local user32 = nil

if ffi_ok then
	pcall(function()
		ffi.cdef([[ short GetKeyState(int nVirtKey); ]])
		user32 = ffi.load("user32")
	end)
end

--- Zero-overhead Caps Lock state query via the Win32 API.
--- @return boolean
function M.is_caps_lock_on()
	if not user32 then
		return false
	end
	local ok, res = pcall(function()
		return user32.GetKeyState(0x14)
	end)
	if ok and res then
		return bit.band(res, 1) ~= 0
	end
	return false
end

-- ============================================================================
-- HTTPS REQUEST (System.Net.HttpWebRequest via PowerShell)
-- ============================================================================
-- No curl binary dependency: PowerShell's own .NET runtime does the TLS work.

--- Performs a single HTTPS request and returns the parsed response.
--- @param url string Target URL.
--- @param method string HTTP method, upper-case.
--- @param headers table<string, string> Request headers.
--- @param body string Request body (may be empty).
--- @param timeout_ms number Request timeout in milliseconds.
--- @return boolean ok
--- @return table result `{ status, statusText, headers, body }` on success, `{ status=500, statusText=<message> }` on failure.
function M.https_request(url, method, headers, body, timeout_ms)
	local header_lines = {}
	local has_ua = false

	for k, v in pairs(headers) do
		local lk = k:lower()
		local esc_v = tostring(v):gsub("'", "''")
		if lk == "content-type" then
			table.insert(header_lines, "$req.ContentType = '" .. esc_v .. "'")
		elseif lk == "user-agent" then
			has_ua = true
			table.insert(header_lines, "$req.UserAgent = '" .. esc_v .. "'")
		elseif lk ~= "host" and lk ~= "content-length" and lk ~= "connection" then
			table.insert(header_lines, "$req.Headers.Add('" .. k:gsub("'", "''") .. "', '" .. esc_v .. "')")
		end
	end

	if not has_ua then
		table.insert(header_lines, "$req.UserAgent = 'krsnvim-fetch/1.0'")
	end

	local body_block = ""
	if body and body ~= "" then
		local esc_body = body:gsub("'", "''"):gsub("`", "``"):gsub("\r\n", "\n"):gsub("\n", "`n")
		body_block = [[
$bytes = [System.Text.Encoding]::UTF8.GetBytes(']] .. esc_body .. [[')
$req.ContentLength = $bytes.Length
$stream = $req.GetRequestStream()
$stream.Write($bytes, 0, $bytes.Length)
$stream.Close()
]]
	end

	local headers_code = table.concat(header_lines, "\n")
	if headers_code ~= "" then
		headers_code = headers_code .. "\n"
	end

	local ps_script = [=[
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$req = [System.Net.HttpWebRequest]::Create(']=] .. url:gsub("'", "''") .. [=[')
$req.Method = ']=] .. method:upper() .. [=['
$req.Timeout = ]=] .. (timeout_ms or 15000) .. [=[

]=] .. headers_code .. body_block .. [=[

try {
	$resp = $req.GetResponse()
	$reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
	$b = $reader.ReadToEnd()
	$st = [int]$resp.StatusCode
	$stText = $resp.StatusDescription
	$hdrs = @{}
	foreach ($key in $resp.Headers.AllKeys) { if ($key) { $hdrs[$key] = $resp.Headers[$key] } }
	@{ status = $st; statusText = $stText; headers = $hdrs; body = $b } | ConvertTo-Json -Depth 5 -Compress
} catch [System.Net.WebException] {
	if ($_.Exception.Response) {
		$resp = $_.Exception.Response
		$reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
		$b = $reader.ReadToEnd()
		$st = [int]$resp.StatusCode
		$stText = $resp.StatusDescription
		$hdrs = @{}
		foreach ($key in $resp.Headers.AllKeys) { if ($key) { $hdrs[$key] = $resp.Headers[$key] } }
		@{ status = $st; statusText = $stText; headers = $hdrs; body = $b } | ConvertTo-Json -Depth 5 -Compress
	} else {
		@{ status = 500; statusText = $_.Exception.Message; headers = @{}; body = "" } | ConvertTo-Json -Compress
	}
}
]=]
	local res = vim.fn.system({ "powershell", "-NoProfile", "-NonInteractive", "-Command", ps_script })
	local json = require("krs.lib.krsnvim.json")
	local ok, parsed = pcall(json.decode, res)
	if ok and type(parsed) == "table" and parsed.status then
		return true, parsed
	end
	return false, { status = 500, statusText = "Execution Error", headers = {}, body = tostring(res) }
end

return M
