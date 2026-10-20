local json = require("dkjson")
local util = require("bibleit.util")
local errors = require("bibleit.errors")
local schemas = require("bibleit.internal.schemas_generated")
local M = {}
local array_mt, object_mt = { __jsontype = "array" }, { __jsontype = "object" }
function M.names()
   local out = {}; for name in pairs(schemas) do out[#out + 1] = name end; table.sort(out); return out
end

function M.schema(name)
   if not schemas[name] then return nil, errors.invalid("unknown schema") end
   return util.copy(schemas[name])
end

-- Like Go structs, constructors describe representation, not server validation.
-- Union variants share wire tables; no extra JSON wrapper is introduced.
function M.new(name, value)
   if not schemas[name] then return nil, errors.invalid("unknown schema") end
   local schema = schemas[name]
   if schema.type == "object" or schema.properties or schema.oneOf or schema.anyOf then
      if type(value) ~= "table" or value == json.null or util.is_array(value) then
         return nil,
             errors.invalid("schema value must be an object")
      end
      return setmetatable(util.copy(value), object_mt)
   end
   if schema.type == "array" then
      if type(value) ~= "table" or value == json.null then return nil, errors.invalid("schema value must be an array") end
      return setmetatable(util.copy(value), array_mt)
   end
   return util.copy(value)
end

-- Union member selection accepts a referenced schema name or 1-based inline index.
function M.as(name, variant, value)
   local schema = schemas[name]
   local variants = schema and (schema.oneOf or schema.anyOf)
   if not variants then return nil, errors.invalid("schema is not a union") end
   for index, member in ipairs(variants) do
      local reference = member["$ref"] and member["$ref"]:match("/([^/]+)$")
      if variant == index or reference and variant == reference then
         if reference then return M.new(reference, value) end
         if type(value) ~= "table" or value == json.null then return nil, errors.invalid("union value must be an object") end
         return setmetatable(util.copy(value), object_mt)
      end
   end
   return nil, errors.invalid("unknown union member")
end

M.from = M.as
local function merge_patch(target, patch)
   if type(patch) ~= "table" or patch == json.null or util.is_array(patch) then
      return util
          .copy(patch)
   end
   if type(target) ~= "table" or target == json.null or util.is_array(target) then
      target =
          setmetatable({}, object_mt)
   end
   for key, value in pairs(patch) do
      if value == json.null then target[key] = nil else target[key] = merge_patch(target[key], value) end
   end
   return target
end
function M.merge(name, variant, current, patch)
   local value, err = M.as(name, variant, patch)
   if not value then return nil, err end
   return merge_patch(util.copy(current), value)
end

for name in pairs(schemas) do
   local schema_name = name
   M[name] = function(value)
      if value == nil then value = {} end; return M.new(schema_name, value)
   end
end
return M
