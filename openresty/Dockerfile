FROM openresty/openresty:alpine

EXPOSE 8080

WORKDIR /nginx

RUN mkdir -p /nginx/logs /nginx/conf
COPY nginx.conf /nginx/conf/nginx.conf
COPY libs /nginx/


RUN apk add --no-cache curl perl


CMD ["nginx", "-p", "/nginx" , "-g", "daemon off;"]
