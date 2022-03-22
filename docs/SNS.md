# SNS workflow

To automate the update of catalyst servers, a message to a SNS topic is sent when a new docker image is available, SNS send messages to a different SQS queues for each catalyst which consume the message and update the server if necessary.

The Architecture Decisions are available [here](https://decentraland.github.io/adr/docs/ADR-21-update-cycle-of-catalysts.html).

## Format of the SNS message

```json
{
  "version": "latest",
  "region": "eu-west-1"
}
```

Messages sent to the SNS are composed of

- `version` which is required and represent the docker tag to be used by catalysts
- `region` which is optional and represent the AWS region to be updated (if not specified, all regions will be updated)
