local open = io.open

local file = open('/secrets/public_key.pem', "rb") -- r read mode and b binary mode
if not file then return nil end
local secret = file:read "*a" -- *a or *all reads the whole file
file:close()

return secret
