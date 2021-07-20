
## NGINX with rate limit

This is a repository with the configuration of nginx using openresty to run rate limit using jwt as identifier.

- When the JWT is valid, then the token is used as key of the rate limit for `valid_jwt` (10 requests per minute with a 20 burst).
- When the JWT is not valid or absent, then the default rate limit "no_token" is applied (1 request per minute without burst).

The default secret for checking the JWT is located at `"/secrets/public_key.pem"` with `HS256` algorithm. If you want to setup a custom secret, you need to modify the DockerImage to set the variable `secret` differently.

The JWT is obtained from the cookie `JWT`. If the JWT sent in the cookie is invalid, then we are removing it by sending the header "Set-Cookie" with an empty value for the JWT.

The payload of the JWT is expected to have a string field `nonce` used as identifier + the base path of the application.
