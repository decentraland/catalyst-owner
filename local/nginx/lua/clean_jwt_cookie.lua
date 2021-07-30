local ck = require "resty.cookie"
local cookie, err = ck:new()

if not cookie then
    ngx.log(ngx.ERR, err)
end

-- Set empty with an expires in the past
local ok, err = cookie:set({key = "JWT", value = "; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT"});


if not ok then
    ngx.log(ngx.ERR, err)
end


-- It does not return an error code
ngx.status = 0
return ngx.exit(400)
