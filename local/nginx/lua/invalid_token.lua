local jwt = require "resty.jwt"

local jwt_token = ngx.var.cookie_JWT
local jwt_obj = jwt:verify(ngx.var.secret, jwt_token)

if (jwt_obj.valid and jwt_obj.verified) then
    return ""
else
    return "invalid"
end
