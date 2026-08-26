local M = {}

function M.run()
	local fetch = require("krs.lib.krsnvim.fetch")
	assert(type(fetch.fetch) == "function", "fetch function should be available")
	assert(type(fetch.get) == "function", "fetch.get should be available")
	assert(type(fetch.post) == "function", "fetch.post should be available")
	assert(type(fetch.url_encode) == "function", "fetch.url_encode should be available")

	-- Test URL encoding
	assert(fetch.url_encode("hello world") == "hello%20world", "url_encode spaces")
	assert(fetch.url_encode("foo&bar=1") == "foo%26bar%3D1", "url_encode special chars")

	-- Test Response object construction
	local res = fetch.Response.new({
		status = 200,
		statusText = "OK",
		headers = { ["Content-Type"] = "application/json" },
		body = '{"success":true}',
		url = "http://example.com",
	})

	assert(res.ok == true, "res.ok should be true for 200")
	assert(res.status == 200, "res.status should be 200")
	assert(res.headers["content-type"] == "application/json", "headers case-insensitive lookup lower")
	assert(res.headers["Content-Type"] == "application/json", "headers case-insensitive lookup exact")
	assert(res:text() == '{"success":true}', "res:text() should return body")

	local json_data = res:json()
	assert(json_data and json_data.success == true, "res:json() should decode JSON body")

	print("  ✅ fetch_spec passed")
end

return M
