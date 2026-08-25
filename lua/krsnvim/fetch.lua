--- @module "krsnvim.fetch"
--- Pure Lua Fetch-like HTTP and HTTPS client for `krsnvimscript`.
--- Provides a zero-dependency, lightweight, web-standard `fetch` interface with automatic JSON encoding/decoding,
--- case-insensitive headers, URL parameter formatting, and cross-platform network execution.
---
--- @example
--- local fetch = import("fetch")
--- local res = fetch("https://api.github.com/zen")
--- print("GitHub Zen:", res:text())
---
--- local post_res = fetch.post("https://httpbin.org/post", { name = "Neovim" })
--- local data = post_res:json()
--- print(data.json.name)
local M = {}

--- @class FetchResponse
--- @field status number HTTP status code (e.g., 200, 404, 500).
--- @field statusText string HTTP status reason phrase (e.g., "OK", "Not Found").
--- @field ok boolean `true` if HTTP status code is within 200–299 range.
--- @field headers table<string, string> Case-insensitive table of HTTP response headers.
--- @field body string Raw text body of the HTTP response.
--- @field url string The full target URL requested.
local Response = {}
Response.__index = Response

local function make_case_insensitive_headers(raw_headers)
	local normalized = {}
	if type(raw_headers) == "table" then
		for k, v in pairs(raw_headers) do
			if type(k) == "string" then
				normalized[k:lower()] = tostring(v)
			end
		end
	end
	return setmetatable(normalized, {
		__index = function(tbl, key)
			if type(key) == "string" then
				return rawget(tbl, key:lower())
			end
			return rawget(tbl, key)
		end,
		__newindex = function(tbl, key, val)
			if type(key) == "string" then
				rawset(tbl, key:lower(), tostring(val))
			else
				rawset(tbl, key, tostring(val))
			end
		end,
	})
end

--- Constructs a new `FetchResponse` object.
--- @param opts table Initial response fields (`status`, `statusText`, `headers`, `body`, `url`).
--- @return FetchResponse
function Response.new(opts)
	opts = opts or {}
	local status = tonumber(opts.status) or 200
	local self = setmetatable({
		status = status,
		statusText = opts.statusText or (status >= 200 and status < 300 and "OK" or "Error"),
		ok = (status >= 200 and status < 300),
		headers = make_case_insensitive_headers(opts.headers),
		body = opts.body or "",
		url = opts.url or "",
	}, Response)
	return self
end

--- Returns the raw string body of the HTTP response.
--- @return string text Raw body string.
function Response:text()
	return self.body or ""
end

--- Safely parses and decodes the response body as JSON into a native Lua table.
--- @return table|nil data Parsed Lua table structure, or `nil` on failure/empty body.
--- @return string|nil err Error message if JSON decoding fails.
---
--- @example
--- local data, err = res:json()
--- if data then
---     print(data.items[1].name)
--- end
function Response:json()
	if not self.body or self.body == "" then
		return nil, "Empty body"
	end
	local json = require("krsnvim.json")
	local ok, res = pcall(json.decode, self.body)
	if ok then
		return res
	end
	return nil, res
end

M.Response = Response

-- ----------------------------------------------------------------------------
-- URL & Encoding Helpers
-- ----------------------------------------------------------------------------

--- Percent-encodes a string according to RFC 3986 URL guidelines.
---
--- @param str string|any Input string to URL-encode.
--- @return string encoded Percent-encoded URL string.
---
--- @example
--- print(fetch.url_encode("hello world & foo=bar"))
--- -- Output: "hello%20world%20%26%20foo%3Dbar"
function M.url_encode(str)
	if str == nil then
		return ""
	end
	if type(str) ~= "string" then
		str = tostring(str)
	end
	return (str:gsub("([^%w%-%_%.%~])", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function build_query(params)
	if not params then
		return ""
	end
	if type(params) == "string" then
		return params:sub(1, 1) == "?" and params or ("?" .. params)
	end
	if type(params) ~= "table" then
		return ""
	end

	local parts = {}
	for k, v in pairs(params) do
		table.insert(parts, M.url_encode(k) .. "=" .. M.url_encode(v))
	end
	if #parts == 0 then
		return ""
	end
	return "?" .. table.concat(parts, "&")
end

local function parse_url(url_str)
	local scheme, rest = url_str:match("^(https?)://(.+)$")
	if not scheme then
		scheme = "http"
		rest = url_str
	end
	scheme = scheme:lower()

	local host_and_port, path_and_query = rest:match("^([^/]+)(.*)$")
	if not path_and_query or path_and_query == "" then
		path_and_query = "/"
	end

	local host, port_str = host_and_port:match("^([^:]+):(%d+)$")
	local port
	if host then
		port = tonumber(port_str)
	else
		host = host_and_port
		port = (scheme == "https") and 443 or 80
	end

	return {
		scheme = scheme,
		host = host,
		port = port,
		path = path_and_query,
		full_url = url_str,
	}
end

-- ----------------------------------------------------------------------------
-- Pure Lua HTTP Engine via vim.uv TCP Socket
-- ----------------------------------------------------------------------------
local function decode_chunked_body(body)
	local result = {}
	local pos = 1
	local len = #body
	while pos <= len do
		local line_end = body:find("\r\n", pos, true)
		if not line_end then
			break
		end
		local hex = body:sub(pos, line_end - 1):match("^%x+")
		if not hex then
			break
		end
		local chunk_len = tonumber(hex, 16)
		if not chunk_len or chunk_len == 0 then
			break
		end
		pos = line_end + 2
		table.insert(result, body:sub(pos, pos + chunk_len - 1))
		pos = pos + chunk_len + 2
	end
	return table.concat(result)
end

local function parse_raw_http(raw, requested_url)
	local header_end = raw:find("\r\n\r\n", 1, true)
	local raw_head, raw_body
	if header_end then
		raw_head = raw:sub(1, header_end - 1)
		raw_body = raw:sub(header_end + 4)
	else
		raw_head = raw
		raw_body = ""
	end

	local lines = vim.split(raw_head, "\r\n", { plain = true })
	local status_line = lines[1] or "HTTP/1.1 200 OK"
	local status_code = tonumber(status_line:match("HTTP/%d+%.%d+%s+(%d+)")) or 200
	local status_text = status_line:match("HTTP/%d+%.%d+%s+%d+%s*(.*)$") or "OK"

	local headers = {}
	for i = 2, #lines do
		local k, v = lines[i]:match("^([^:]+):%s*(.*)$")
		if k and v then
			headers[k:lower()] = v
		end
	end

	if headers["transfer-encoding"] and headers["transfer-encoding"]:find("chunked") then
		raw_body = decode_chunked_body(raw_body)
	end

	return Response.new({
		status = status_code,
		statusText = status_text,
		headers = headers,
		body = raw_body,
		url = requested_url,
	})
end

local function http_tcp_request(parsed_url, req_method, req_headers, req_body, timeout_ms, callback)
	local uv = vim.uv or vim.loop
	local host = parsed_url.host
	local port = parsed_url.port

	uv.getaddrinfo(host, tostring(port), { socktype = "stream" }, function(err, res)
		if err or not res or #res == 0 then
			callback("DNS lookup failed for host '" .. tostring(host) .. "': " .. tostring(err), nil)
			return
		end

		local ip = res[1].addr
		local client = uv.new_tcp()
		local chunks = {}
		local timer = nil
		local closed = false

		local function cleanup()
			if closed then
				return
			end
			closed = true
			if timer then
				timer:stop()
				timer:close()
			end
			pcall(function()
				client:read_stop()
			end)
			pcall(function()
				client:close()
			end)
		end

		if timeout_ms and timeout_ms > 0 then
			timer = uv.new_timer()
			timer:start(timeout_ms, 0, function()
				cleanup()
				callback("Request timeout after " .. tostring(timeout_ms) .. "ms", nil)
			end)
		end

		client:connect(ip, port, function(connect_err)
			if connect_err then
				cleanup()
				callback("TCP connection failed to " .. host .. ":" .. port .. ": " .. tostring(connect_err), nil)
				return
			end

			local req_lines = {}
			table.insert(req_lines, string.format("%s %s HTTP/1.1", req_method, parsed_url.path))
			table.insert(req_lines, "Host: " .. host)
			table.insert(req_lines, "User-Agent: krsnvim-fetch/1.0")
			table.insert(req_lines, "Accept: */*")
			table.insert(req_lines, "Connection: close")

			for k, v in pairs(req_headers) do
				local lk = k:lower()
				if lk ~= "host" and lk ~= "connection" then
					table.insert(req_lines, string.format("%s: %s", k, v))
				end
			end

			if req_body and #req_body > 0 then
				table.insert(req_lines, "Content-Length: " .. tostring(#req_body))
			end

			local payload = table.concat(req_lines, "\r\n") .. "\r\n\r\n" .. (req_body or "")

			client:write(payload, function(write_err)
				if write_err then
					cleanup()
					callback("Socket write error: " .. tostring(write_err), nil)
					return
				end

				client:read_start(function(read_err, chunk)
					if read_err then
						cleanup()
						callback("Socket read error: " .. tostring(read_err), nil)
						return
					end

					if chunk then
						table.insert(chunks, chunk)
					else
						cleanup()
						local raw_data = table.concat(chunks)
						local response = parse_raw_http(raw_data, parsed_url.full_url)
						callback(nil, response)
					end
				end)
			end)
		end)
	end)
end

-- ----------------------------------------------------------------------------
-- Cross-Platform HTTPS Engine (No curl binary dependency)
-- ----------------------------------------------------------------------------
-- The actual per-OS request (PowerShell's HttpWebRequest on Windows, Python's
-- urllib elsewhere) lives in lua/krs/core/os/shared.lua -- this just wraps its
-- plain result table into a FetchResponse.
local function exec_https(target_url, method, headers, body, timeout_ms)
	local _, result = require("krs.core.os.shared").https_request(target_url, method, headers, body, timeout_ms)
	return Response.new({
		status = result.status,
		statusText = result.statusText,
		headers = result.headers,
		body = result.body,
		url = target_url,
	})
end

-- ----------------------------------------------------------------------------
-- Main Fetch Function
-- ----------------------------------------------------------------------------

--- @class FetchOptions
--- @field method string|nil HTTP method ("GET", "POST", "PUT", "DELETE", "PATCH", "HEAD"). Defaults to "GET".
--- @field headers table<string, string>|nil Key-value HTTP request headers.
--- @field body table|string|nil Body payload string or table. Tables auto-encode to JSON with `Content-Type: application/json`.
--- @field query table<string, string|number>|string|nil URL query parameters table or string (`{ page = 1 }` -> `?page=1`).
--- @field timeout number|nil Request timeout in milliseconds (default: 15000ms).
--- @field callback function|nil Optional async callback `callback(err, response)`.

--- Makes an HTTP or HTTPS request using a fetch-like interface.
---
--- @param url string Target URL to fetch.
--- @param opts FetchOptions|nil Request configuration options.
--- @return FetchResponse response Response object containing `status`, `ok`, `headers`, `body`, `:json()`, and `:text()`.
---
--- @note Edge Cases:
--- - `opts.body` as a table automatically encodes as JSON and sets `Content-Type: application/json`.
--- - `opts.query` automatically percent-encodes parameters and appends them to the URL.
--- - Works with `http://` (pure Lua TCP sockets) and `https://` (native OS TLS engine, zero external binaries needed).
---
--- @see krsnvim.fetch.get
--- @see krsnvim.fetch.post
--- @see krsnvim.fetch.json
---
--- @example
--- local res = fetch("https://api.github.com/zen")
--- print(res.status, res:text())
function M.fetch(url, opts)
	opts = opts or {}
	if type(url) ~= "string" or url == "" then
		error("krsnvim.fetch: URL must be a non-empty string")
	end

	local method = (opts.method or "GET"):upper()
	local headers = {}
	if opts.headers and type(opts.headers) == "table" then
		for k, v in pairs(opts.headers) do
			headers[k] = tostring(v)
		end
	end

	-- Apply query parameter options if present
	if opts.query then
		local q_str = build_query(opts.query)
		if q_str ~= "" then
			if url:find("%?") then
				url = url .. "&" .. q_str:sub(2)
			else
				url = url .. q_str
			end
		end
	end

	-- Auto-encode JSON body if table
	local body = opts.body
	if type(body) == "table" then
		local json = require("krsnvim.json")
		body = json.encode(body)
		local has_ct = false
		for k, _ in pairs(headers) do
			if k:lower() == "content-type" then
				has_ct = true
				break
			end
		end
		if not has_ct then
			headers["Content-Type"] = "application/json"
		end
	elseif body ~= nil and type(body) ~= "string" then
		body = tostring(body)
	end

	local timeout_ms = opts.timeout or 15000
	local parsed_url = parse_url(url)

	if parsed_url.scheme == "https" then
		return exec_https(url, method, headers, body or "", timeout_ms)
	else
		-- HTTP via Pure Lua TCP Socket Engine
		local response = nil
		local err_msg = nil
		local done = false

		http_tcp_request(parsed_url, method, headers, body, timeout_ms, function(err, res)
			err_msg = err
			response = res
			done = true
		end)

		if opts.callback then
			return nil
		end

		-- Sync wait
		vim.wait(timeout_ms + 2000, function()
			return done
		end, 10)

		if not done then
			return Response.new({
				status = 504,
				statusText = "Gateway Timeout",
				body = "Request timed out waiting for socket response",
				url = url,
			})
		end

		if err_msg and not response then
			return Response.new({
				status = 500,
				statusText = "Network Error",
				body = tostring(err_msg),
				url = url,
			})
		end

		return response
	end
end

-- Metatable setup for fetch(url, opts)
setmetatable(M, {
	__call = function(_, url, opts)
		return M.fetch(url, opts)
	end,
})

-- ----------------------------------------------------------------------------
-- Convenience HTTP Methods
-- ----------------------------------------------------------------------------

--- Performs an HTTP GET request.
--- @param url string Target URL.
--- @param opts FetchOptions|nil Additional request options.
--- @return FetchResponse
--- @see krsnvim.fetch.post
function M.get(url, opts)
	opts = opts or {}
	opts.method = "GET"
	return M.fetch(url, opts)
end

--- Performs an HTTP POST request.
--- @param url string Target URL.
--- @param body_or_opts table|string|FetchOptions Payload table/string, or options table containing body.
--- @param opts FetchOptions|nil Additional options if body was passed as 2nd parameter.
--- @return FetchResponse
--- @see krsnvim.fetch.get
function M.post(url, body_or_opts, opts)
	opts = opts or {}
	if
		type(body_or_opts) == "table"
		and not body_or_opts.method
		and not body_or_opts.headers
		and not body_or_opts.body
	then
		opts.body = body_or_opts
	elseif type(body_or_opts) == "string" then
		opts.body = body_or_opts
	elseif type(body_or_opts) == "table" then
		opts = body_or_opts
	end
	opts.method = "POST"
	return M.fetch(url, opts)
end

--- Performs an HTTP PUT request.
--- @param url string Target URL.
--- @param body_or_opts table|string|FetchOptions Payload table/string, or options table.
--- @param opts FetchOptions|nil Additional options.
--- @return FetchResponse
function M.put(url, body_or_opts, opts)
	opts = opts or {}
	if
		type(body_or_opts) == "table"
		and not body_or_opts.method
		and not body_or_opts.headers
		and not body_or_opts.body
	then
		opts.body = body_or_opts
	elseif type(body_or_opts) == "string" then
		opts.body = body_or_opts
	elseif type(body_or_opts) == "table" then
		opts = body_or_opts
	end
	opts.method = "PUT"
	return M.fetch(url, opts)
end

--- Performs an HTTP DELETE request.
--- @param url string Target URL.
--- @param opts FetchOptions|nil Request options.
--- @return FetchResponse
function M.delete(url, opts)
	opts = opts or {}
	opts.method = "DELETE"
	return M.fetch(url, opts)
end

--- Performs an HTTP PATCH request.
--- @param url string Target URL.
--- @param body_or_opts table|string|FetchOptions Payload or options table.
--- @param opts FetchOptions|nil Additional options.
--- @return FetchResponse
function M.patch(url, body_or_opts, opts)
	opts = opts or {}
	if
		type(body_or_opts) == "table"
		and not body_or_opts.method
		and not body_or_opts.headers
		and not body_or_opts.body
	then
		opts.body = body_or_opts
	elseif type(body_or_opts) == "string" then
		opts.body = body_or_opts
	elseif type(body_or_opts) == "table" then
		opts = body_or_opts
	end
	opts.method = "PATCH"
	return M.fetch(url, opts)
end

--- Performs an HTTP HEAD request.
--- @param url string Target URL.
--- @param opts FetchOptions|nil Request options.
--- @return FetchResponse
function M.head(url, opts)
	opts = opts or {}
	opts.method = "HEAD"
	return M.fetch(url, opts)
end

_G.fetch = M

return M
