---
title: "Glossary"
slug: "/contributor/catalyst/glossary"
---

### Catalyst

[Catalyst](https://github.com/decentraland/catalyst) is the name given to the **Decentraland Service Bundle**, each Catalyst [node](https://decentraland.github.io/catalyst-monitor) exposes a set of services that work as the backbone for the platform and also exposes a public [API](https://decentraland.github.io/catalyst-api-specs/). 

### Bootstrap

The moment when the Catalyst is booted, the node will have a `Bootstrapping` until it is ready to serve content. 

### Catalyst Client

[Library](https://github.com/decentraland/catalyst-client) that can be used to interact with the Catalyst servers. You can both fetch data, or deploy new entities to the server you specify.

### Entity

Data Type, defined with [schemas](https://github.com/decentraland/common-schemas), that cannot be stored in the blockchain because of its size. Some of the current [supported types](https://github.com/decentraland/common-schemas/blob/main/src/platform/entity.ts#L13) are the following:

- [Wearable](https://github.com/decentraland/common-schemas/blob/main/src/platform/item/wearable/wearable.ts)
- [Emote](https://github.com/decentraland/common-schemas/blob/main/src/platform/item/emote/emote.ts)
- [Scene](https://github.com/decentraland/common-schemas/blob/main/src/platform/scene/scene.ts)
- [Profile](https://github.com/decentraland/common-schemas/blob/main/src/platform/profile/profile.ts)

### Deployment

Instances of Entities created on the Content Server and identified with a unique [EntityId](https://github.com/decentraland/common-schemas/blob/main/src/platform/entity.ts#L31). Deployments can be of any [Entity Type](https://github.com/decentraland/common-schemas/blob/main/src/platform/entity.ts#L13).

### Failed Deployment 

Instance of an Entity deployed to a Content Server that failed to pass the [Content Validations](https://github.com/decentraland/adr/blob/main/docs/ADR-51-catalyst-content-validations.md). Validations are implemented on the [content validator](https://github.com/decentraland/content-validator) library. 

### Active Entity 

Current Entity content deployed on a pointer, thus all active entities represent the live content of Decentraland: scenes, profiles, wearables, etc. 

### Deployment History 

Each time a new version of a Deployment is done on a `pointer`, the `Active Entity ` content changes and the previous active content passes to be part of the pointer history. The list of deployments done on a pointer order by timestamp represent the history.

### Pointer 

Pointers are the ids or locations to which a Deployment belongs, they change based on the `Entity Type`, for example: 

- **Wearables**: Uses URN as pointers `urn:decentraland:ethereum:collections-v1:dg_atari_dillon_francis:gerald_patchwork_knit_sweater`
- **Scenes**: Uses an array of parcels as pointers `[(0,0), (0,1), (0,-1)]`
- **Profiles**: Uses a Wallet address as pointer `0xb01ddb6d4c89314f74a32dfc2f3bd0f8311a6d75`
- **Stores**: Uses a URN as pointer `urn:decentraland:off-chain:marketplace-stores:{wallet}`

### URN 

[URN](https://en.wikipedia.org/wiki/Uniform_Resource_Name) stands for  Uniform Resource Name, they are used as global unique identifiers for assets across the Metaverse projects. 

- URN Resolver: https://github.com/decentraland/urn-resolver
- URN Namespace: https://github.com/common-metaverse/urn-namespaces
   
### Content Server

The [Content Server](https://github.com/decentraland/catalyst/tree/main/content) is a part of the Catalyst node in charge of managing the Decentralized storage of Entities Deployments. Currently, all content stored in a Content Server is synchronized with the rest of the DAO Catalysts.

### Lambdas

The [Lambdas](https://github.com/decentraland/catalyst/tree/main/lambdas) Service is a part of the Catalyst node that that works as a reconciliation layer between the Content Servers and the Blockchain, sanitizing content, validating ownership and helping retrieve information for the Catalyst clients.

### Synchronization 

Content Servers have to offer the ability to deploy content on them, and also ensure that any content deployed on any other valid and running Catalyst from the DAO List is available there too. Resolving this is called **synchronization**. 

### Content SNAPSHOT 

A set of all the  Active Entities of the specified type. This Content SNAPSHOTS are used to synchronize content between Catalyst nodes.

### Realm 

When connected to Decentraland, you would only be able to interact with Peers connected to the same Realm. As friendly-names Realms make use of Greek Gods names such as Hela or Loki. Each realm is determined by a single [Catalyst Node](https://decentraland.github.io/catalyst-monitor/).

### Peer 

A user connected to Decentraland. 

### Lighthouse 

The [Lighthouse](https://github.com/decentraland/lighthouse) is the name used t reference the previous version of the Communications Service hosted on the Catalyst nodes and used to group users in a P2P network. 
Main responsibilities were to determine which are the candidates for a P2P connection and do the WebRTC signaling to establish the connection. Most of this logic was done through two external components: the PeerJS Server (connects [WebRTC](https://webrtc.org/) peers) and Archipelago (receives users positions and groups them in islands).

### Backend for Frontend (aka BFF) 

The [BFF](https://github.com/decentraland/explorer-bff) Service was created to resolve client needs and to enable faster development of new features without breaking the existing APIs. In the context of the Catalyst Communication Service, it will be in charge of managing the P2P signaling and thus replacing the Lighthouse.

### Catalyst Owner

A [Catalyst Owner](https://github.com/decentraland/catalyst-owner) is an individual or organization running a Catalyst node. To add a Catalyst node to the DAO network a [proposal](https://governance.decentraland.org/?type=catalyst) needs to be submitted and the DAO nodes represent the trusted Decentraland Network.


### Archipelago Service 

The [Archipelago Service](https://github.com/decentraland/archipelago-service) previously was a library used by the Lighthouse. This service will have the same responsibility that the library did: group Peers in clusters so they can communicate efficiently and each cluster is called an island. On the other hand, the service also needs to be able to balance islands using the available communications Transports and following a set of [Catalyst Owner](https://github.com/decentraland/catalyst-owner) defined rules, in order to, for example, use LiveKit for an island in the Casino scene and P2P in a Genesis Plaza.

### Island

Cluster of connected peers.

### Communication Transport 

Transport is the technology used to share updates between Peers connected to an Island.

### P2P Transport 

Uses [WebRTC](https://webrtc.org/) connections between Peers, no extra infrastructure needed to scale as the load is on the client side and the Servers only manage the signaling. Latency increases as more Peers are added to an Island. There is a limit on the amount of WebRTC connections a client can have thus in order to have bigger islands, more indirect connections (jumps) between peers are needed.

### LiveKit Transport 

[LiveKit](https://livekit.io/) is an open source project that provides scalable, multi-user conferencing over WebRTC. Instead of doing a P2P network, Peers are connected to a Selective Forwarding Unit (SFU) in charge of managing message rely and different quality aspects of the communication. The SFUs are the added infrastructure needed in order to provide high-performance/high-quality communications between crowds on designated scenes.

### WebSocket Transport 

The [WebSocket Transport](https://github.com/decentraland/ws-room-service) is lighter than LiveKit, it also requires a Server that manages the relay of messages through WebSocket rooms, rooms are equivalent to islands. 
This transport provides less latency/better performance than P2P islands but also requires the extra infrastructure.  

### NATS 

[NATS](https://nats.io/) is a message broker that enables the date exchange and communication between services. In the context of the Catalyst Server it is used to communicate Some of the internal Services.

### DAO

DAO stands for "Decentralized Autonomous Organization". The Decentraland DAO owns the most important smart contracts and assets that make up Decentraland – the LAND Contract, the Estates Contract, Wearables, Content Servers and the Marketplace. It also owns a substantial purse of MANA which allows it to be truly autonomous as well as subsidize various operations and initiatives throughout Decentraland.

[https://dao.decentraland.org/en/](https://dao.decentraland.org/en/)

