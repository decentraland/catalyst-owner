# Catalyst Management

Welcome to the Catalyst management tool!

Here you will find everything you need to set up you our Catalyst node.

# Important notice!

This repository is prepared to be auto updated with cron jobs. The updated branches are `development` and `master`. Where `development` is the canary release to test a configuration and `master` branch is the "stable" configuration for the catalysts.

It is _highly recommended_ that you use a fork of this repository to avoid any security issues since it may run code directly in your catalyst.

We actively mix canary and stable configurations in several catalysts for Ropsten (dev) and Mainnet (prod).

## Set up

### Requirements

- You will need to have [docker](https://docs.docker.com/install/) installed.
- You will to have [docker-compose](https://docs.docker.com/compose/install/) installed.
- The initialization script runs on Bash. It has not been tested on Windows.

In order to run a public server, you will also need to:

- Have a public domain pointing to your server.
- Your server will need to have the HTTPS port open (443).

### What you will need to configure

To configure your node, you will have to set three variables in the [.env](.env) file:

| Name                   | Description                                                                                                                                                                                                                        | Default  | Required |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------: | :------: |
| EMAIL                  | Needed to handle the TLS certificates. For example, you will be notified when they are about to expire.                                                                                                                            |    -     |   yes    |
| CONTENT_SERVER_STORAGE | The path to the directory where the content will be stored. Path must be absolute.                                                                                                                                                 |    -     |   yes    |
| CATALYST_URL           | The public domain of the node. For example `https://peer.decentraland.org`. It is really important that you add `https://` at the beginning of the URL. If you are running your node locally, then simply write `http://localhost` |    -     |   yes    |
| CATALYST_OWNER_CHANNEL | Which update channel in the cloud bootstrap configurations to use `stable` or `latest`.                                                                                                                                            | `latest` |    no    |
| SQS_QUEUE_NAME         | Which Amazon SQS to consume in `crontab.sh`                                                                                                                                                                                        |    -     |    no    |
| MOUNT_DISK             | Useful to mount a disk to the folder `$CONTENT_SERVER_STORAGE` when working with persistent storage in cloud instances.                                                                                                            |    -     |    no    |

There is also some advanced configuration in the [.env-advanced](.env-advanced) file. Normally, it shouldn't be modified.

| Name        | Description                                                                                                                                                                                                                                                                                                   | Default | Required |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :-----: | :------: |
| ETH_NETWORK | Which Ethereum network you want to use. Usually is `ropsten` for testing or `mainnet` for production                                                                                                                                                                                                          | mainnet |   yes    |
| REGENERATE  | This will instruct the script to regenerate the certs. `0` will keep the certificates, `1` will ask for certificate renewal. If there are no certificates, the initialization script will generate them automatically, regardless of this value. For more information, look at FAQ questions (2), (3) and (4) |    0    |    no    |
| RATE_LIMIT_ENABLED  | This will enable/disable nginx rate-limiting. `0` for false, `1` for true. |    0    |    no    |
| RATE_LIMIT_NGINX_VAR  | This is the variable that nginx will used to limit the requests, see http://nginx.org/en/docs/http/ngx_http_core_module.html#variables for available variables. By default, the value holds a binary representation of a client’s IP address. In case that the Catalyst is behind a reverse proxy, usually some HTTP headers are set, you could use any of that headers like this `http_<HEADER_NAME>` . For example, when the widely used `X-Forwarded-For` header is set, you could set `http_x-forwarded-for` |    binary_remote_addr    |    no    |


## Running your Catalyst

After you have configured everything, all you need to do is run:

```
./init.sh
```

#### How to make sure that your Catalyst is running

Once you started your Catalyst server, after a few seconds you should be able to test the different services by accessing:

- Content: `CATALYST_URL/content/status`
- Comms: `CATALYST_URL/comms/status`
- Lambdas: `CATALYST_URL/lambdas/status`

## Updating your Catalyst

To update your Catalyst to a newer version, you can do the same as above:

```
./init.sh
```

## Stopping your Catalyst node

To stop a specific container on your node:

```
./stop.sh
```

## Stopping a specific container from a Catalyst node

To stop a specific container on your node:

```
./stop.sh [ nginx | lambdas | content-server | comms-server ]
```

## FAQ

### 1. How are TLS certificates managed?

We are using [Let's Encrypt](https://letsencrypt.org/) for certificates. We automatically generate the certificates the first time you start your server. We will also handle the renewal of the server for you!

### 2. When issuing a certificate, if fails the first time, the script won't try to issue a new one.

One of the steps in issuing a certificate is the creation of auto signed certs. The script checks if there are any certs already created. If they exist, then no new certificates are created.

To force a certificate regeneration you will need to change the `REGENERATE` entry on the `.env` file to `1` and then execute the script again.

**IT'S IMPORTANT** to roll back this value to `0`. If you don't, a new certificate will be issued on each run and you will hit the Let's Encrypt ratio limit. It this happens, your domain will be banned.

### 3. How many certs I can issue?

This is tied to Let's Encrypt ratio limit. To know about Let's Encrypt ratio limit look [here](https://letsencrypt.org/docs/staging-environment/)

### 4. How can I can check the amount of certificates I already issued?

You can take a look on this [site](https://crt.sh/), entering the domain you want to check.

## SNS workflow

To automate the update of catalyst servers, a message to a SNS topic is sent when a new docker image is available, SNS send messages to a different SQS queues for each catalyst which consume the message and update the server if necessary.

The Architecture Decisions are available [here](https://decentraland.github.io/adr/docs/ADR-21-update-cycle-of-catalysts.html).

### Format of the SNS message

```json
{
  "version": "latest",
  "region": "eu-west-1"
}
```

Messages sent to the SNS are composed of

- `version` which is required and represent the docker tag to be used by catalysts
- `region` which is optional and represent the AWS region to be updated (if not specified, all regions will be updated)

## Metrics

Metrics are exposed in the following endpoints:

- `/comms_metrics` - communications server
- `/content_metrics` - content server
- `/lambdas_metrics` - lambdas
- `/system_metrics` - cadvisor
- `/postgres_metrics` - postgres exporter
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

## Compression

By default, the nginx of Catalyst is configured to compress requests greater than 30kb. This compression can be CPU intensive, but it is necessary to ensure load times are as small as possible.

But if clients won't be requesting directly to the Catalyst, it could be convenient to turn the compression off to reduce CPU usage (for instance, if you put the Catalyst behind Cloudflare or other CDN).

To turn off compression, simply edit the configuration in [local/nginx/nginx.conf](local/nginx/nginx.conf) and comment/delete the following lines:

```
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript application/octet-stream;
    gzip_min_length 30000;
```

## Logs

All the logs of catalyst-owner are configured to be redirected to the syslog. Please make sure you have a way to redirect the syslog to a place where you can read it (there are useful services like cloudwatch, splunk, sumologic that can help you organize your logs).

## `userdata.sh`

Base file to run in the `user data` section of a cloud-init enabled instance like AWS EC2.

It configures the minimum necessary environment to run the catalyst.

## `bootstrap.sh`

This file is automatically configured by `userdata.sh` to run when the instance starts. It mounts the volumes if necessary (MOUNT_DISK env var) and starts the services.

## `mount.sh`

This file must be executed as root. Its only responsibiliy is to mount the MOUNT_DISK volume to the CONTENT_SERVER_STORAGE folder if necessary.
