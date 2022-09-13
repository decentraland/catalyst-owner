# Metrics

Metrics are exposed in the following endpoints:

- `/comms_metrics` - communications server
- `/content_metrics` - content server
- `/lambdas_metrics` - lambdas
- `/explorer_bff_metrics` - explorer-bff server
- `/system_metrics` - cadvisor
- `/postgres_metrics` - postgres exporter
- `/nats_metrics` - NATS exporter
- `/pow_auth_metrics` - POW auth server

Metrics are protected under basic auth since prometheus scrappers can handle it by default. System metrics (cadvisor + postgres) have a special set of .htpasswd credentials: .htpasswd-system.

To add an user and password to that basic auth execute:

```bash
# for catalyst metrics:
htpasswd -b local/nginx/auth/.htpasswd-metrics [username] [password]
# for system metrics (container + postgres):
htpasswd -b local/nginx/auth/.htpasswd-system [username] [password]
```

Notice: by default, a user named `decentraland-crawler` is added to scrape metrics to help the Decentraland Foundation members to debug production issues. Feel free to remove it.

