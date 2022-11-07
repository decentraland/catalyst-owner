---
title: "Realm Selection"
slug: "/contributor/catalyst/realm-selection"
---

A [Catalyst](https://github.com/decentraland/catalyst) is a Server that bundles different Services required by the Decentraland World. Some of the main responsibilities of the server are the management of the decentralized storage for most of the content needed by the client and the orchestration of communications between peers.

When entering into a Decentraland Client, then you need to connect to a specific Catalyst for the backend services support Content, Lambdas & Comms. One of the DAO Catalysts needs to be used, it could be picked randomly but that could lead to the user accessing a backend service with great latency or a realm with a low amount of users while they are connected to another one.

To mitigate this, then an algorithm for realm selection is implemented in Kernel as described in [ADR-86](https://rfc.decentraland.org/adr/ADR-86).

It is a configurable algorithm that uses different criteria in an ordered list, if one of the conditions is strong enough to make a decision then it chooses a realm, if not then delegates the decision to the following criteria. If none condition was strong enough, then a default decision is made (random).

The default configuration is:
1. Prioritizes Peers with the most amount of users
2. Prioritizes Peers with the most amount of users near (in the current parcel)


Other criterias that can be used are:
- Large Latency: Prioritizes the Catalysts with the lower latency
- Load Balancing: Is a Round Robin Mechanism to distribute all peers between all Catalysts.



