local bibleit = require("bibleit")
-- Pass a credential explicitly; the SDK never reads environment/configuration.
local token = assert(arg[1], "usage: lua examples/read.lua TOKEN ACCOUNT_ID")
local account_id = assert(arg[2], "account ID is required")
local client = assert(bibleit.new_client(token))
local response, err = client:get_personal_identity()
if not response then error(tostring(err), 0) end
local identity, decode_err = response:decode()
response:close()
if not identity then error(tostring(decode_err), 0) end
print(identity.id)
local pages = client:read_personal_book_pages(account_id, "web", "19", { query = { limit = "100" } })
while true do
   local page, page_err = pages()
   if page_err then error(tostring(page_err), 0) end
   if not page then break end
   for _, verse in ipairs(page.verses) do print(verse.chapter, verse.verse, verse.text) end
end
