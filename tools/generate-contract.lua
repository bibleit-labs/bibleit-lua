-- Regenerate schema and REST operation metadata from the pinned public contract.
local version = _VERSION:match("(%d+%.%d+)")
package.path = "./lua_modules/share/lua/" .. version .. "/?.lua;./lua_modules/share/lua/" .. version .. "/?/init.lua;" .. package.path
local json = require("dkjson")
local file = assert(io.open("contract/openapi.json", "rb"))
local source = file:read("*a"); file:close()
local contract, _, err = json.decode(source, 1, json.null)
assert(contract, err)
local check = arg[1] == "--check"
assert(arg[1] == nil or check, "usage: lua tools/generate-contract.lua [--check]")
local function sorted_keys(value)
   local keys = {}; for key in pairs(value) do keys[#keys + 1] = key end
   table.sort(keys); return keys
end
local function literal(value)
   local kind = type(value)
   if value == json.null then return 'require("dkjson").null' end
   if kind == "string" then return string.format("%q", value) end
   if kind == "number" or kind == "boolean" then return tostring(value) end
   assert(kind == "table", "unsupported JSON value")
   local values = {}
   if (getmetatable(value) or {}).__jsontype == "array" then
      for _, item in ipairs(value) do values[#values + 1] = literal(item) end
      if #values == 0 then return "setmetatable({}, array_mt)" end
      return "setmetatable({ " .. table.concat(values, ", ") .. " }, array_mt)"
   end
   for _, key in ipairs(sorted_keys(value)) do
      values[#values + 1] = "[" .. string.format("%q", key) .. "] = " .. literal(value[key])
   end
   if #values == 0 then return 'setmetatable({}, { __jsontype = "object" })' end
   return "{ " .. table.concat(values, ", ") .. " }"
end
local function render(values)
   local lines = {"-- Generated from contract/openapi.json. Do not edit.", "local array_mt = { __jsontype = \"array\" }"}
   local entries = {}
   for _, key in ipairs(sorted_keys(values)) do
      entries[#entries + 1] = "   [" .. string.format("%q", key) .. "] = " .. literal(values[key]) .. ","
   end
   lines[#lines + 1] = "return {"
   for _, entry in ipairs(entries) do lines[#lines + 1] = entry end
   lines[#lines + 1] = "}"
   return table.concat(lines, "\n") .. "\n"
end
local methods = {get=true, post=true, put=true, patch=true, delete=true, options=true, head=true, trace=true}
local operations = {}
for path, item in pairs(contract.paths) do
   for method, operation in pairs(item) do
      if methods[method] and operation["x-fern-server-name"] == "rest" then
         local parameters = setmetatable({}, {__jsontype="array"})
         for name in path:gmatch("{([^}]+)}") do parameters[#parameters + 1] = name end
         assert(not operations[operation.operationId], "duplicate REST operation")
         operations[operation.operationId] = {method=method:upper(), path=path, summary=operation.summary, parameters=parameters}
      end
   end
end
local function output(path, contents)
   if check then
      local existing = assert(io.open(path, "rb")); local actual = existing:read("*a"); existing:close()
      assert(actual == contents, path .. " needs regeneration")
   else
      local destination = assert(io.open(path, "wb")); assert(destination:write(contents)); assert(destination:close())
   end
end
output("src/bibleit/internal/schemas_generated.lua", render(contract.components.schemas))
output("src/bibleit/internal/operations_generated.lua", render(operations))
