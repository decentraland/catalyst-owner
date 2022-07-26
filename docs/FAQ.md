---
title: "FAQ"
slug: "/contributor/catalyst/faq"
---

Below you can find the **frequently asked questions** about Catalyst Servers.
## How are TLS certificates managed?

We are using [Let's Encrypt](https://letsencrypt.org/) for certificates. We automatically generate the certificates the first time you start your server. We will also handle the renewal of the server for you!

## When issuing a certificate, if fails the first time, the script won't try to issue a new one.

One of the steps in issuing a certificate is the creation of auto signed certs. The script checks if there are any certs already created. If they exist, then no new certificates are created.

To force a certificate regeneration you will need to change the `REGENERATE` entry on the `.env` file to `1` and then execute the script again.

**IT'S IMPORTANT** to roll back this value to `0`. If you don't, a new certificate will be issued on each run and you will hit the Let's Encrypt ratio limit. It this happens, your domain will be banned.

## How many certs I can issue?

This is tied to Let's Encrypt ratio limit. To know about Let's Encrypt ratio limit look [here](https://letsencrypt.org/docs/staging-environment/)

## How can I can check the amount of certificates I already issued?

You can take a look on this [site](https://crt.sh/), entering the domain you want to check.
