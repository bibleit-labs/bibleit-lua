local errors = require("bibleit.errors")
local utf8 = require("bibleit.internal.utf8")
local command = require("bibleit.command")
local util = require("bibleit.util")
local http = require("bibleit.http")
local M = {}
M.err_incomplete_term = errors.new("incomplete_term", { message = "unterminated protocol term" })
function M.parse_record(line)
   return errors.protect(function()
      util.assert(type(line) == "string" and utf8.valid_utf8(line) and not line:find("%z"), "invalid protocol record")
      local words, word, compound = {}, {}, {}
      local quoted, escaped, active = false, false, false
      local term_quote, term_escape
      local function flush()
         if active then
            words[#words + 1] = table.concat(word); word = {}; active = false
         end
      end
      local i = 1
      while i <= #line do
         local c = line:sub(i, i)
         if #compound > 0 then
            word[#word + 1] = c
            if term_escape then
               term_escape = false
            elseif term_quote then
               if c == "\\" then term_escape = true elseif c == term_quote then term_quote = nil end
            elseif c == '"' or c == "'" then
               term_quote = c
            elseif c == "{" then
               compound[#compound + 1] = "}"
            elseif c == "[" then
               compound[#compound + 1] = "]"
            elseif c == "(" then
               compound[#compound + 1] = ")"
            elseif c == "}" or c == "]" or c == ")" then
               util.assert(compound[#compound] == c, "mismatched protocol term"); compound[#compound] = nil
            end
         elseif c == "\r" or c == "\n" then
            errors.raise("newline outside an opaque protocol term")
         elseif escaped then
            local mapping = { ["\\"] = "\\", ['"'] = '"', n = "\n", r = "\r", t = "\t" }
            if c == "u" then
               local hex = line:sub(i + 1, i + 4)
               util.assert(#hex == 4 and not hex:find("[^%da-fA-F]"), "invalid protocol Unicode escape")
               local n = tonumber(hex, 16); util.assert(n < 55296 or n > 57343, "invalid protocol Unicode scalar")
               word[#word + 1] = utf8.utf8(n); i = i + 4
            else
               util.assert(mapping[c], "invalid protocol escape"); word[#word + 1] = mapping[c]
            end
            escaped = false
         elseif c == "\\" and quoted then
            escaped = true; active = true
         elseif c == '"' then
            quoted = not quoted; active = true
         elseif not quoted and (c == "{" or c == "[" or c == "(") and table.concat(word):find("=", 1, true) then
            word[#word + 1] = c; compound[#compound + 1] = ({ ["{"] = "}", ["["] = "]", ["("] = ")" })[c]; active = true
         elseif (c == " " or c == "\t") and not quoted then
            flush()
         else
            word[#word + 1] = c; active = true
         end
         i = i + 1
      end
      if #compound > 0 then error(M.err_incomplete_term, 0) end
      util.assert(not quoted and not escaped, "unterminated protocol string"); flush()
      util.assert(#words > 0, "empty protocol record")
      local record = { type = words[1]:lower(), fields = {}, order = {} }
      for n = 2, #words do
         local k, v = words[n]:match("^(.-)=(.*)$")
         if k then
            util.assert(k ~= "", "empty protocol field")
            if record.fields[k] ~= nil then
               util.assert(record.fields[k] == v, "conflicting protocol field")
            else
               record.fields[k] = v; record.order[#record.order + 1] = k
            end
         end
      end
      return record
   end)
end

local function decode(input, single_record)
   return errors.protect(function()
      if type(input) == "table" and type(input.read) == "function" then
         local v, e = http.read_all(input, 2097152); if not v then error(e, 0) end; input = v
      end
      util.assert(type(input) == "string", "protocol input must be a string or reader")
      util.assert(#input <= 2097152, "protocol response exceeds 2 MiB")
      util.assert(#input > 0 and input:sub(-1) == "\n", "incomplete protocol response")
      local result = { lines = {}, records = {} }
      local ended, server_error, pending = false, nil, nil
      for physical_line in input:gmatch("(.-)\n") do
         local line = physical_line
         if line:sub(-1) == "\r" then line = line:sub(1, -2) end
         util.assert(not ended, "unexpected data after END"); util.assert(not server_error, "unexpected data after ERR")
         if line == "END" then
            util.assert(#result.records > 0, "unexpected END"); ended = true
         else
            if pending then line = pending .. "\n" .. line end
            local record, e = M.parse_record(line)
            if e == M.err_incomplete_term then
               pending = line
            else
               if not record then error(e, 0) end
               pending = nil
               if #result.records == 0 then
                  if record.type == "err" then
                     local code = line:match("^%S+%s+(%S+)")
                     util.assert(code and not code:find("=", 1, true), "missing server error code")
                     server_error = errors.new("server", { code = code, fields = record.fields })
                  else
                     util.assert(record.type == "ok", "response must start with OK or ERR")
                  end
               else
                  util.assert(record.type ~= "ok" and record.type ~= "err" and record.type ~= "event",
                     "unexpected response envelope")
               end
               if not server_error then
                  result.lines[#result.lines + 1] = line; result.records[#result.records + 1] = record
               end
            end
         end
      end
      util.assert(not pending, "incomplete protocol response")
      if server_error then return nil, server_error end
      util.assert(#result.records > 0, "incomplete protocol response")
      if not ended then
         local fields = result.records[1].fields
         local multi = false
         for _, key in ipairs({ "count", "verses", "results", "books", "commands", "connections" }) do if fields[key] ~= nil then multi = true end end
         if fields.event == "verse" and fields.translations ~= nil then multi = true end
         util.assert(#result.records == 1 and (single_record or not multi), "incomplete protocol response")
      end
      return result
   end)
end
function M.decode_response(input) return decode(input, false) end

function M.decode_command_response(cmd, input)
   if not command.is_command(cmd) or cmd:streaming() then
      return nil,
          errors.invalid("a finite validated command is required")
   end
   return decode(input, cmd:string():find("^ACCOUNT TRANSLATION ") ~= nil)
end

return M
