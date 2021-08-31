local jwt = require "resty.jwt"

local jwt_token = ngx.var.cookie_JWT
-- If it is not present, then it isn't valid either
if (jwt_token == nil or jwt_token == "") then
    return ""
end

local jwt_obj = jwt:verify(ngx.var.secret, jwt_token)
if (jwt_obj.valid and jwt_obj.verified) then
    return ""
else
    return "invalid"
end

