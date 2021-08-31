# Initialization

This documents tackles the initialization part of the cross-chain validation (CCV) protocol.
Namely, we need to ensure that (1) parent blockchain communicates with baby blockchain, (2) baby blockchain communicates with parent blockchain, and (3) these two blockchains communicate via a single channel.

We start by properly defining the properties of the initialization subprotocol.
Then, we provide the pseudocode and prove its correctness.

## Problem Definition

We assume that babyChain denotes the baby blockchain the parent blockchain wants to validate.
Similarly, parentChain denotes the parent blockchain which validates the baby blockchain, from the perspective of the baby blockchain.
Finally, we assume that the parent blockchain eventually sends a validator set update to the baby blockchain.

### Light Client

We assume that a light client (PARENT_LIGHT_CLIENT_ON_BABY and BABY_LIGHT_CLIENT_ON_PARENT) expose the following methods:

- VerifyChannelState(ClientState clientState, Height height, CommitmentPrefix prefix, CommitmentProof proof, Identifier portIdentifier, Identifier channelIdentifier, ChannelEnd channelEnd) - verifies a proof of the channel state of the specified channel end, under the specified port, stored on the target machine. For more details, see [Light Client Specification](https://github.com/cosmos/ibc/tree/master/spec/core/ics-002-client-semantics).

- ClientUpdate(Header header): void - updates the client with the header.

- ClientUpdated(): boolean - checks whether the client is updated.

### Problem Definition

The initialization exposes the following interface:
- Indication <Open, channel>: channel is open.

We ensure the following properties:

- **Parent Safety:** If <Open, channel> is triggered at parent blockchain, then channel is a channel between the parent and baby blockchain. [satisfied if the parent blockchain is "valid"]

- **Baby Safety:** If <Open, channel> is triggered at baby blockchain, then channel is a channel between the parent and baby blockchain. [satisfied if the baby blockchain is "valid"]

- **No Duplication:** There is no more than one channel open between two blockchains. [satisfied if the blockchain is "valid"]

- **Liveness:** A blockchain eventually triggers <Open, channel>. [satisfied if both blockchains are "valid"]

## Protocol

### Prerequisites

This subsection presents the state of both chains we assume at the start of the initialization subprotocol.
There exists a light client on the baby blockchain that follows the parent blockchain (denoted by PARENT_LIGHT_CLIENT_ON_BABY) and there exists a light client on the parent blockchain that follows the baby blockchain (denoted by BABY_LIGHT_CLIENT_ON_PARENT).

### Parent Blockchain

```
upon <OnChanOpenTry, Order order, String portId, String channelId, Counterparty counterparty, String version, String counterpartyVersion>:
    // validate parameters, i.e., check whether order = "ORDERED", portId is the expected port, version is the expected version
    if (!validate(order, portId, channelId, version)):
        trigger <error>

    // check whether the version of the counterparty is the expected one
    if (counterpartyVersion != expectedCCVVersion):
        trigger <error>

    // create the channel, i.e., claim a capability
    Channel channel = new Channel(portId, channelId)
    // set its status to "INITIALIZING"
    channel.setStatus("INITIALIZING")

    // get the client
    client = getClient(channelId)

    // verify consensus state
    verifyConsensusState(client, initialValidatorSetBaby)

    // verify that there does not exist a CCV channel
    if (ccvChannelBaby != nil):
        trigger <error>
```

<!-- TODO: Add clarification for what "last" indeed means! -->
<!-- TODO: Emphasize the fact that OnChanInit has been executed on the baby blockchain. -->
<!-- TODO: The relayer sends a client update and the client applies it. -->
<!-- TODO: BABY_LIGHT_CLIENT_ON_PARENT rename to "BABY_LIGHT_CLIENT_ON_PARENT" (or something similar). -->
<!-- TODO: Baby client state and chain state -> put it as a predicate (the proofs will reveal what we indeed need to emphasize regarding the predicate). -->
- **Initiator:** Relayer.
- **Expected precondition:** 
    - OnChanOpenInit has been executed on the baby blockchain.
    - ChanOpenTry datagram committed on the blockchain.
    - BABY_LIGHT_CLIENT_ON_PARENT.ClientUpdated() = true; Note that it is possible for BABY_LIGHT_CLIENT_ON_PARENT.ClientUpdated() to return false. If that is the case, then BABY_LIGHT_CLIENT_ON_PARENT.ClientUpdate(header) is invoked, where header is the  header of the latest height of the baby blockchain as seen from the perspective of the relayer, which does ensure that the next call of BABY_LIGHT_CLIENT_ON_PARENT.ClientUpdated() returns true.
    - BABY_LIGHT_CLIENT_ON_PARENT.VerifyChannelState(connection, height, connection.counterpartyPrefix, proof, portId, channelId, channelEnd) = true, where (see [Connection Semantics](https://github.com/cosmos/ibc/tree/master/spec/core/ics-003-connection-semantics) and [Channel Semantics](https://github.com/cosmos/ibc/tree/master/spec/core/ics-004-channel-and-packet-semantics)):
        - connection is the corresponding connection of the channel being established,
        - height is the height of the CommitmentProof,
        - proof is the CommitmentProof. 
- **Expected postcondition:**
    - A channel is created; its status is set to "INITIALIZING".
    - A consensus state of the baby blockchain is verified againts its initial validator set.
- **Error condition:** 
    - If the precondition is violated.

```
upon <OnChanOpenConfirm, String portId, String channelId>:
    // check whether the baby channel has not been already established
    channel = getBabyChannel();

    // the channel already exists
    if (channel):
        // set the status to "INVALID"
        channel.setStatus("INVALID")

        // close the channel
        channel.close()

        trigger <error>

    // update the channel
    ccvChannel = getChannel(channelId)
    // make it valid
    ccvChannel.setStatus("VALID")

    // set the channel as baby channel
    setBabyChannel(ccvChannel)

    // terminate
    trigger <Open, ccvChannel>
```

- **Initiator:** Relayer.
- **Expected precondition:** 
    - OnChanOpenAck has been executed on the baby blockchain.
    - ChanOpenConfirm datagram committed on the blockchain.
    - BABY_LIGHT_CLIENT_ON_PARENT.ClientUpdated() = true; Note that it is possible for BABY_LIGHT_CLIENT_ON_PARENT.ClientUpdated() to return false. If that is the case, then BABY_LIGHT_CLIENT_ON_PARENT.ClientUpdate(header) is invoked, where header is the header of the latest height of the baby blockchain as seen from the perspective of the relayer, which does ensure that the next call of BABY_LIGHT_CLIENT_ON_PARENT.ClientUpdated() returns true.
    - BABY_LIGHT_CLIENT_ON_PARENT.VerifyChannelState(connection, height, connection.counterpartyPrefix, proof, portId, channelId, channelEnd) = true, where (see [Connection Semantics](https://github.com/cosmos/ibc/tree/master/spec/core/ics-003-connection-semantics) and [Channel Semantics](https://github.com/cosmos/ibc/tree/master/spec/core/ics-004-channel-and-packet-semantics)):
        - connection is the corresponding connection of the channel being established,
        - height is the height of the CommitmentProof,
        - proof is the CommitmentProof.
- **Expected postcondition:**
    - If this is the first OnChanOpenConfirm callback invoked, the parent blockchain terminates the initialization protocol with this channel (it sets its status to "VALID"); otherwise, the callback is ignored and the previous channel is closed.
- **Error condition:** 
    - If the precondition is violated.

### Baby Blockchain

```
upon <OnChanOpenInit, Order order, String portId, String channelId, Counterparty counterparty, String version:
    // validate parameters, i.e., check whether order = "ORDERED", portId is the expected port, version is the expected version
    if (!validate(order, portId, channelId, version)):
        trigger <error>

    // create the channel, i.e., claim a capability
    Channel channel = new Channel(portId, channelId)
    // set its status to "INITIALIZING"
    channel.setStatus("INITIALIZING")

    // get the client
    client = getClient(channelId)

    // verify that the client is the expected client
    (client != expectedClient):
        trigger <error>
```
- **Initiator:** CCV module on the baby blockchain.
- **Expected precondition:** 
    - Connection among two blockchains has already been established.
- **Expected postcondition:**
    - A channel is created; its status is set to "INITIALIZING".
- **Error condition:** 
    - If the precondition is violated.

```
upon <OnChanOpenAck, String portId, String channelId, String counterpartyVersion>:
    // check whether there already exists the channel
    channel = getParentChannel();

    // the channel already exists
    if (channel):
        trigger <error>

    // check the version of the counterparty
    if (counterpartyVersion != expectedVersion): 
        trigger <error>
```
- **Initiator:** Relayer.
- **Expected precondition:** 
    - OnChanOpenTry has been executed on the parent blockchain.
    - ChanOpenAck datagram committed on the blockchain.
    - PARENT_LIGHT_CLIENT_ON_BABY.ClientUpdated() = true; Note that it is possible for PARENT_LIGHT_CLIENT_ON_BABY.ClientUpdated() to return false. If that is the case, then PARENT_LIGHT_CLIENT_ON_BABY.ClientUpdate(header) is invoked, where header is the header of the latest height of the parent blockchain as seen from the perspective of the relayer, which does ensure that the next call of PARENT_LIGHT_CLIENT_ON_BABY.ClientUpdated() returns true.
    - PARENT_LIGHT_CLIENT_ON_BABY.VerifyChannelState(connection, height, connection.counterpartyPrefix, proof, portId, channelId, channelEnd) = true, where (see [Connection Semantics](https://github.com/cosmos/ibc/tree/master/spec/core/ics-003-connection-semantics) and [Channel Semantics](https://github.com/cosmos/ibc/tree/master/spec/core/ics-004-channel-and-packet-semantics)):
        - connection is the corresponding connection of the channel being established,
        - height is the height of the CommitmentProof,
        - proof is the CommitmentProof.
- **Expected postcondition:**
    - If this is the first OnChanOpenAck callback invoked, the baby blockchain terminates the initialization protocol with this channel; otherwise, the callback is ignored.
- **Error condition:** 
    - If the precondition is violated.

For the sake of completeness, we insert the \<OnRecvPacket\> callback from [Protocol part](https://github.com/informalsystems/cross-chain-validation/blob/6abd0a947cef9faf1bb16f3a9971a559549d5712/CCV%20-%20Protocol.md) of the specification.

```
upon <OnRecvPacket, ValidatorSetUpdate packet>:
    Channel channel = packet.getDestinationChannel();
    // check whether the status of channel is "VALIDATING"
    if (channel.status != "VALIDATING"):
        // set status to "VALIDATING"
        channel.setStatus("VALIDATING")
        
        // set the channel as the parent channel
        setParentChannel(channel)

        // terminate the initialization protocol
        trigger <Open, channel>

    // store the updates from the packet
    pendingChanges.append(packet.updates)

    // calculate and store the unbonding time for the packet
    unbondingTime = blockTime().Add(UnbondingPeriod)
    unbondingTime.add(packet, unbondingTime)
```

- **Initiator:** Relayer
- **Expected precondition:**
    - Packet datagram is committed on the blockchain.
    - PARENT_LIGHT_CLIENT_ON_BABY.ClientUpdated() = true; Note that it is possible for PARENT_LIGHT_CLIENT_ON_BABY.ClientUpdated() to return false. If that is the case, then PARENT_LIGHT_CLIENT_ON_BABY.ClientUpdate(header) is invoked, where header is the header of the latest height of the parent blockchain, which does ensure that the next call of PARENT_LIGHT_CLIENT_ON_BABY.ClientUpdated() returns true.
- **Expected postcondition:**
    - packet.updates are appended to pendingChanges.
    - (packet, unbondingTime) is added to unbondingTime, where unbondingTime = UnbondingPeriod + blockTime().
- **Error condition:**
    - If the precondition is violated.

## Correctness Arguments

- **Parent Safety:** This property is satisfied because the underlying client is the one expected and the consensus state of the baby blockchain is verified.

- **Baby Safety:** This property is a consequence of the constantly updated light client of the parent blockchain on the baby blockchain.

- **No Duplication:** The property is ensured because the parent blockchain opens a single channel.
Under the assumption that the parent eventually sends a validator set update via the channel, the baby blockchain terminates upon receiving an update.

- **Liveness:** The property holds since the handshake eventually completes and the parent blockchain eventually sends a validator set update to the baby blockchain.