local jwt = require "resty.jwt"

local basePath = ngx.arg[1]
local path = ngx.arg[2]

local jwt_token = ngx.var.cookie_JWT
local jwt_obj = jwt:verify(ngx.var.secret, jwt_token)

if (jwt_obj.valid and jwt_obj.verified) then
  return basePath .. path .. jwt_obj.payload.nonce
else
  return ""
end
