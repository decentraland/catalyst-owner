
local cookieHeader = ngx.var.cookie_JWT

if (cookieHeader == nil or cookieHeader == "") then
    return "true"
else
    return ""
end
