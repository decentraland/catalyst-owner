local cjson = require "cjson"
local jwt = require "resty.jwt"
local open = io.open

local basePath = ngx.arg[1]
local path = ngx.arg[2]

local file = open('/secrets/public_key.pem', "rb") -- r read mode and b binary mode
if not file then return nil end
local secret = file:read "*a" -- *a or *all reads the whole file
file:close()

local jwt_token = ngx.var.cookie_JWT

local jwt_obj = jwt:verify(secret, jwt_token)

if (jwt_obj.valid and jwt_obj.verified) then
    return basePath + path + jwt_obj.payload.nonce
else
    return ""
end
