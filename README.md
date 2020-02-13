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

### 2. When issuing a certificate, if fails the first time, the script won't try to issue a new one.
One of the steps in issuing a certificate is the creation of auto signed certs. The script checks if there are any certs already created. If they exist, then no new certificates are created.

To force a certificate regeneration you will need to change the `REGENERATE` entry on the `.env` file to `1` and then execute the script again.

**IT'S IMPORTANT** to roll back this value to `0`. If you don't, a new certificate will be issued on each run and you will hit the Let's Encript ratio limit. It this happens, your domain will be banned.

### 3. How many certs I can issue?
This is tied to Let's Encrypt ratio limit. To know about Let's Encrypt ratio limit look [here](https://letsencrypt.org/docs/staging-environment/)

### 4. How can I can check the amount of certificates I already issued?
You can take a look on this [site](https://crt.sh/), entering the domain you want to check.