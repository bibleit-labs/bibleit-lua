local errors = require("bibleit.errors")
local M = {}
local mt = {}; mt.__index = mt
function M.new(options)
   options = options or {}
   return setmetatable({ deadline = options.deadline, clock = options.clock or os.time }, mt)
end

function mt:cancel() self.cancelled = true end

function mt:err()
   if self.cancelled then return errors.new("cancelled", { message = "request cancelled" }) end
   if self.deadline and self.clock() >= self.deadline then
      return errors.new("deadline",
         { message = "request deadline exceeded" })
   end
end

function M.check(ctx) return ctx and ctx:err() end

return M
