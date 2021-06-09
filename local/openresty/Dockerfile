FROM openresty/openresty:alpine

RUN apk add --no-cache curl perl

WORKDIR /etc/nginx

RUN mkdir -p /etc/nginx/libs /etc/nginx/logs /etc/nginx/conf
# Download lua-resty-jwt
# LuaRocks is not officially supported on OpenResty
# The lua-resty-jwt has been removed from OPM 
RUN curl https://codeload.github.com/cdbattags/lua-resty-jwt/tar.gz/refs/tags/v0.2.3 --output /etc/nginx/libs/lua-resty-jwt-0.2.3.tar.gz
RUN tar -xvzf /etc/nginx/libs/lua-resty-jwt-0.2.3.tar.gz -C /etc/nginx/libs/
RUN rm /etc/nginx/libs/lua-resty-jwt-0.2.3.tar.gz
# Download lua-resty-hmac compatible with the version of lua-resty-jwt
RUN curl https://codeload.github.com/jkeys089/lua-resty-hmac/tar.gz/refs/tags/v0.05 --output /etc/nginx/libs/lua-resty-hmac-0.05.tar.gz
RUN tar -xvzf /etc/nginx/libs/lua-resty-hmac-0.05.tar.gz -C /etc/nginx/libs/lua-resty-jwt-0.2.3/third-party/
RUN rm /etc/nginx/libs/lua-resty-hmac-0.05.tar.gz
# Download lua-resty-openssl compatible with the version of lua-resty-jwt
RUN curl https://codeload.github.com/fffonion/lua-resty-openssl/tar.gz/refs/tags/0.7.2 --output /etc/nginx/libs/lua-resty-openssl-0.7.2.tar.gz
RUN tar -xvzf /etc/nginx/libs/lua-resty-openssl-0.7.2.tar.gz -C /etc/nginx/libs/lua-resty-jwt-0.2.3/third-party/
RUN rm /etc/nginx/libs/lua-resty-openssl-0.7.2.tar.gz
