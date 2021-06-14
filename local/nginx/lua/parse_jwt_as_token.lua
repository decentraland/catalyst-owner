local jwt = require "resty.jwt"

local basePath = ngx.var.jwt_base_path
local path = ngx.arg[1]

local jwt_token = ngx.var.cookie_JWT
local jwt_obj = jwt:verify(ngx.var.secret, jwt_token)

if (jwt_obj.valid and jwt_obj.verified) then
  return basePath .. path .. jwt_obj.payload.nonce
else
  return ""
end
