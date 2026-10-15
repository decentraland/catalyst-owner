---
title: "FAQ"
slug: "/contributor/catalyst/faq"
---

Below you can find the **frequently asked questions** about Catalyst Servers.
## How are TLS certificates managed?

We are using [Let's Encrypt](https://letsencrypt.org/) for certificates. We automatically generate the certificates the first time you start your server. We will also handle the renewal of the server for you!

The `certbot` container renews the certificate when it gets close to expiring. On top of that, every `./init.sh` run checks the current certificate and only requests a new one when it is missing, was not issued by Let's Encrypt (for example the temporary self-signed one), comes from the Let's Encrypt staging environment, has an RSA key under 2048 bits, or expires in less than 30 days.

## What happens if issuing a certificate fails?

The previous certificate files are put back, so nginx keeps running, and the next `./init.sh` run tries again. To protect your domain from the Let's Encrypt rate limits, the script waits 60 minutes after a failed request before trying again. Delete the `.cert-request-failed` file to retry right away.

Before every request the script runs a dry run against the Let's Encrypt staging environment, so a misconfigured DNS or firewall fails there without counting against the production limits.

## How can I force a new certificate?

Set `REGENERATE=1` in the `.env-advanced` file and execute `./init.sh` again. The new certificate is requested while the current one keeps being served, and the current one is kept if the request fails.

Set the value back to `0` afterwards. While it is on, the script skips regeneration if the certificate is less than a day old, but it would still request a new one every day.

## How many certs I can issue?

This is tied to Let's Encrypt ratio limit. To know about Let's Encrypt ratio limit look [here](https://letsencrypt.org/docs/staging-environment/)

## How can I can check the amount of certificates I already issued?

You can take a look on this [site](https://crt.sh/), entering the domain you want to check.
