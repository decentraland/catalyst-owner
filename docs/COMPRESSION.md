# Compression

By default, the nginx of Catalyst is configured to compress requests greater than 30kb. This compression can be CPU intensive, but it is necessary to ensure load times are as small as possible.

But if clients won't be requesting directly to the Catalyst, it could be convenient to turn the compression off to reduce CPU usage (for instance, if you put the Catalyst behind Cloudflare or other CDN).

To turn off compression, simply edit the configuration in [local/nginx/nginx.conf](local/nginx/nginx.conf) and comment/delete the following lines:

```
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript application/octet-stream;
    gzip_min_length 30000;
```
