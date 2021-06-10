
local h = ngx.var.jwt_req_zone
if (h == nil or h == "") then
    return "true"
else
    return ""
end
