# Catalyst Management

Welcome to the Catalyst management tool!

Here you will find everything you need to set up you our Catalyst node.

## Set up

### Requirements

* You will to have installed [docker-compose](https://docs.docker.com/compose/install/).
* You will need to have a public domain pointing to your server.
* Your server will need to have the HTTPS port open (443).
* The initialization script runs on Bash. It has not been tested on Windows.

### What you will need to configure
To configure your node, you will have to set three variables in the [.env](.env) file:

* EMAIL: Needed to handle the TLS certificates. For example, you will be notified when they are about to expire.
* CONTENT_SERVER_STORAGE: The path to the directory where the content will be stored.
* CATALYST_URL: The public domain of the node. For example `https://peer.decentraland.org`.

## Running your Catalyst

After you have configured everything, all you need to do is run:

```
./init.sh
```

## Updating your Catalyst

To update your Catalyst to a newer version, you can do the same as above:

```
./init.sh
```

## Stopping your Catalyst

To stop your Catalyst, you can run:
```
./stop.sh
```

## FAQ
### 1. How are TLS certificates managed?
We are using [Let's Encrypt](https://letsencrypt.org/) for certificates. We automatically generate the certificates the first time you start your server. We will also handle the renewal of the server for you!