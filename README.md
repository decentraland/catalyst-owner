# Catalyst Management

Welcome to the Catalyst management tool!

Here you will find everything you need to set up you our Catalyst node.

# Important notice!

This repository is prepared to be auto updated with cron jobs. The updated branches are `development` and `master`. Where `development` is the canary release to test a configuration and `master` branch is the stable configuration for the catalysts.

It is _highly recommended_ that you use a fork of this repository to avoid any security issues since it may run code directly in your catalyst.

We actively mix canary and stable configurations in several catalysts for Goerli (dev) and Mainnet (prod).

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

| Name             | Description                                                                                                                                                                                                                                                                                                   | Default | Required |
|------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------| :-----: | :------: |
| ETH_NETWORK      | Which Ethereum network you want to use. Usually is `goerli` for testing or `mainnet` for production                                                                                                                                                                                                           | mainnet |   yes    |
| REGENERATE       | This will instruct the script to regenerate the certs. `0` will keep the certificates, `1` will ask for certificate renewal. If there are no certificates, the initialization script will generate them automatically, regardless of this value. For more information, look at FAQ questions (2), (3) and (4) |    0    |    no    |
| MAINTENANCE_MODE | This will instruct to run maintenance tasks in the Catalyst and then stop. `0` will run the Catalyst normally , `1` will run the maintenance mode.                                                                                                                                                            |    0    |    no    |

## Running your Catalyst

After you have configured everything, all you need to do is run:

```
./init.sh
```

#### How to make sure that your Catalyst is running

Once you started your Catalyst server, after a few seconds you should be able to test the different services by accessing:

- Content: `CATALYST_URL/content/status`
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
./stop.sh [ nginx | lambdas | content-server | archipelago | nats | nats-exporter | explorer-bff ]
```

## [FAQ](https://github.com/decentraland/catalyst-owner/blob/master/docs/FAQ.md)

## [SNS Workflow](https://github.com/decentraland/catalyst-owner/blob/master/docs/SNS.md)

## [Metrics](https://github.com/decentraland/catalyst-owner/blob/master/docs/METRICS.md)

## [Compression](https://github.com/decentraland/catalyst-owner/blob/master/docs/COMPRESSION.md)

## [Logs](https://github.com/decentraland/catalyst-owner/blob/master/docs/LOGS.md)

## [Config](https://github.com/decentraland/catalyst-owner/blob/master/docs/CONFIG.md)

