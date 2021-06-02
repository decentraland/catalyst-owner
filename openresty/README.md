# NGINX with rate limit

This is a repository with the configuration of nginx using openresty to run rate limit using jwt as identifier.

- When the JWT is valid, then the token is used as key of the rate limit for `valid_jwt` (10 requests per minute with a 20 burst).
- When the JWT is not valid or absent, then the default rate limit "no_token" is applied (1 request per minute without burst).

The default secret for checking the JWT is `"lua-resty-jwt"` with `HS256` algorithm. If you want to setup a custom secret, you need to modify the DockerImage to set the environment variable `SECRET`.

The JWT is obtained from the header `x-jwt`.

The payload of the JWT is expected to have a string field `nonce` used as identifier.

### Build and run the image:
```
./run.sh
```


### Make requests to the service for testing

1. No token:
```
curl localhost:8080/verify
```

2. With Token:

```
curl localhost:8080/verify -H "Cookie:JWT=eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJjb21wbGV4aXR5IjozLCJjaGFsbGVuZ2UiOiIwODQ0MDUxYjY2MTg0ODUzYWNlNzU5NzA1YzkzYWMyN2M5NDAxYWQ3Iiwibm9uY2UiOiJhMWI5ZTRhMGMxYmI1MzljZTZmOTlmY2NiYzlhNWNlY2ViM2NhYjY0NmQ5NGZiYTdhYTFjNmQ0OGJmZDU1MDQyMWEyYjJiNDcxNDE1MTc4ODNhNzRjNDM3N2NiM2Y1YjY4NzMwODIwZDk5MzU2ZDBlNDFlYjg0ZDQ2MTJhN2U0OWU1YzFiZTk5OWEyOTQxMThiYTU1ZWM0ZTI4ZmM2OTQ3ODgzYzlkYzEyNDBmMjcwNGU5MDYyNmQ1M2RmZWIzOTFlNTg5NDJmMmI2ODU4NDUxZGQ1N2EzY2QyZjcxMzA4ZjFlMzcwOTAxNzA3Zjc4YTEyNmM0MmEwMDk5MDFhMDkyYWE4ZjAyZWJjZTAzNGM0YTAzNTlhODE0MGYzNTQyNzA1OGVkN2ExZTFkNmE5MDAxODU1ZTA5ZWE4M2JiMzQzY2YyZTIwZDY4NjI5N2QzMmYwNjc3ZTZjMDQ4OTczMDkxZTgxNGY4ZDg5MmYzMWJmNDNkZDA1NTJkYWIxZGQ0NjM2OGRjMzA0YzAyZGUwOTRhZWFlYzAyYzc4M2RkZDliOTg3OGE3MDZjNzkzMGIyMmRiMTM3NDQzZGZjY2ZjMDJjN2E1ZjJlYTI2NjYzMjM2MWY0ODE2MjhhMTdlNmE0ZjBlNWQyZGRkNTBmM2VlN2ZkM2UxMzMxYWRmMzY1ZGQzMiIsImlhdCI6MTUxNjIzOTAyMn0.baQTEm-iW6Tl6qrs3W4kZcD9StFKE-0E8GTchED5pNp5K03XcsQgBJkfwMIqNueddDUiNj_ObRKMUP373yhvCNKanY7w5VhNP7w4HEhKHSZCf2sQvIUF2NDEkI_1MdFqXvpO83s_iNDnaB1hx_OcEBE1PeMfOL70Z3TPiBReTTqpUR17UVX03v03nXMS7RzljXjcmYQPafk9zEG7fhTbAxNFWZwKBfWLnrcVUQjTkHNrpU7WL3rEWTsogWWLVoTGwfwblTIb9C4tuml19qhITNOE0tS7aJwpuRLVdu-vfJoqZkZZLiZ8Us_GRpTfkJamRD3waV79D2vwEPnMyngQGw; Expires=Fri, 04 Jun 2021 00:29:31 GMT"
```


## Why use Openresty?

OpenResty includes many carefully written Lua libraries, lots of high quality 3rd-party Nginx modules, and most of their external dependencies.


## External links

1. Libraries copied from here:

- https://github.com/SkyLothar/lua-resty-jwt

2. Documentation:

- [Open Resty](https://openresty.org/en/)
- [Nginx rate limit](https://www.nginx.com/blog/rate-limiting-nginx/)
- [Lua Directives](https://openresty-reference.readthedocs.io/en/latest/Directives/#set_by_lua)
- [Generate JWT](https://jwt.io/)
