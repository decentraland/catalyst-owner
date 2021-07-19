local ck = require "resty.cookie"
local cookie, err = ck:new()

if not cookie then
    ngx.log(ngx.ERR, err)
end

local ok, err = cookie:set({key = "JWT", value = ""});

if not ok then
    ngx.log(ngx.ERR, err)
end


-- It does not return an error code
ngx.status = 0
return ngx.exit(400)
