# Metrics

Metrics are exposed in the following endpoints:

- `/comms_metrics` - Communications server
- `/content_metrics` - Content server
- `/lambdas_metrics` - Lambdas server
- `/system_metrics` - cAdvisor
- `/postgres_metrics` - Postgres exporter

Metrics are protected under basic auth since Prometheus scrappers can handle it by default. System metrics (cAdvisor + Postgres) have a special set of `.htpasswd` credentials: `.htpasswd-system`.

To add a user and password to that basic auth execute:

```bash
# for catalyst metrics:
htpasswd -b local/nginx/auth/.htpasswd-metrics [username] [password]
# for system metrics (container + postgres):
htpasswd -b local/nginx/auth/.htpasswd-system [username] [password]
```

Notice: by default, a user named `decentraland-crawler` is added to scrape metrics to help the Decentraland Foundation members to debug production issues. Feel free to remove it.

