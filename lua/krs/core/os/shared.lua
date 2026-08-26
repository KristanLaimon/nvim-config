-- ============================================================================
-- KRS OS: Cross-platform interface -- same function, OS-picked implementation
-- ============================================================================
-- WHAT IT DOES
--   Some operations behave identically everywhere in *intent* but need a
--   different tool underneath per OS (Win32 API vs. a POSIX one, PowerShell vs.
--   curl/python). Callers use ONE function here; this file decides which OS
--   implementation actually runs it.
--
-- WHERE OS-SPECIFIC CODE LIVES
--   lua/krs/core/os/windows.lua   Windows-only logic (Win32 API, PowerShell).
--   lua/krs/core/os/linux.lua     Linux-only logic, if a function ever needs one.
--   lua/krs/core/os/mac.lua       macOS-only logic, if a function ever needs one.
--   This file                     The dispatch + whatever is identical on every
--                                 non-Windows OS (most POSIX tooling is), so it
--                                 doesn't need its own linux.lua/mac.lua split.
--
-- ADDING A NEW CROSS-PLATFORM OPERATION
--   1. Add a function here that branches on `M.is_windows`/`M.is_mac`/`M.is_linux`.
--   2. Put the Windows-only branch in windows.lua (and require it lazily inside
--      the branch, not at this file's top level).
--   3. Only split a linux.lua/mac.lua out once that branch itself needs to
--      differ between Linux and macOS -- until then, keep the shared POSIX
--      implementation right here.
-- ============================================================================

local M = {}

--- Detected once per session; these never change while Neovim is running.
M.is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
M.is_mac = vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1
M.is_linux = not M.is_windows and not M.is_mac

-- ============================================================================
-- CAPS LOCK STATE
-- ============================================================================

--- True when Caps Lock is toggled on.
--- ponytail: only Windows has an implementation (Win32 `GetKeyState`). Linux/macOS
--- have no portable no-dependency equivalent from inside Neovim; add a linux.lua/
--- mac.lua implementation (X11 XkbGetIndicatorState / IOKit) if this is ever needed
--- there -- until then this always reports off.
--- @return boolean
function M.is_caps_lock_on()
	if M.is_windows then
		return require("krs.core.os.windows").is_caps_lock_on()
	end
	return false
end

-- ============================================================================
-- HTTPS REQUEST (no curl binary dependency)
-- ============================================================================
-- Windows uses PowerShell's HttpWebRequest; Linux and macOS both ship Python 3
-- with urllib, so one POSIX branch covers both -- no linux.lua/mac.lua split
-- needed unless that ever stops being true.

--- Performs a single HTTPS request via whatever TLS-capable tool the OS ships,
--- with no external binary (curl, wget) required.
--- @param url string Target URL.
--- @param method string HTTP method, upper-case.
--- @param headers table<string, string> Request headers.
--- @param body string Request body (may be empty).
--- @param timeout_ms number Request timeout in milliseconds.
--- @return boolean ok
--- @return table result `{ status, statusText, headers, body }` on success, `{ status=500, statusText=<message> }` on failure.
function M.https_request(url, method, headers, body, timeout_ms)
	if M.is_windows then
		return require("krs.core.os.windows").https_request(url, method, headers, body, timeout_ms)
	end

	local py_script = string.format(
		[[
import urllib.request, json, ssl
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
headers = %s
data = %s
req = urllib.request.Request('%s', data=data.encode() if data else None, headers=headers, method='%s')
try:
    with urllib.request.urlopen(req, context=ctx, timeout=%d) as resp:
        res_headers = dict(resp.headers)
        body = resp.read().decode('utf-8', errors='replace')
        print(json.dumps({'status': resp.status, 'statusText': resp.reason, 'headers': res_headers, 'body': body}))
except urllib.error.HTTPError as e:
    body = e.read().decode('utf-8', errors='replace')
    print(json.dumps({'status': e.code, 'statusText': e.reason, 'headers': dict(e.headers), 'body': body}))
except Exception as e:
    print(json.dumps({'status': 500, 'statusText': str(e), 'headers': {}, 'body': ''}))
]],
		vim.json.encode(headers),
		vim.json.encode(body or ""),
		url,
		method:upper(),
		math.floor((timeout_ms or 15000) / 1000)
	)

	local res = vim.fn.system({ "python3", "-c", py_script })
	local json = require("krs.lib.krsnvim.json")
	local ok, parsed = pcall(json.decode, res)
	if ok and type(parsed) == "table" and parsed.status then
		return true, parsed
	end
	return false, { status = 500, statusText = "Execution Error", headers = {}, body = tostring(res) }
end

return M
