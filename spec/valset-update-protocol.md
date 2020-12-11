# Technical Specification

## Introduction

This document presents a technical specification for the **Cross-Chain Validation** protocol.
The basic idea of the Cross-Chain Validation protocol is to allow validators that are already securing some existing blockchain (parent blockchain) to also secure a "new" blockchain (baby blockchain).
The stake bonded at the parent blockchain guarantees that a validator behaves correctly at the baby blockchain.
If the validator misbehaves at the baby blockchain, its stake will be slashed at the parent blockchain.

Therefore, at a high level, we can imagine the Cross-Chain Validation protocol to be concerned with following entities:
  - Parent blockchain: This is a blockchain that "provides" validators. Namely, "provided" validators have some stake at the parent blockchain. Any misbehavior of a validator is slashed at the parent blockchain. Moreover, parent blockchain manipulates the validator set of a chain that "borrows" validators from it.
  - Baby blockchain: Baby blockchain is a blockchain that is being secured by the parent blockchain. In other words, validators that secure and operate the baby blockchain are bonded on the parent blockchain. Any misbehavior of a validator at the baby blockchain is punished at the parent blockchain (i.e., the validator is slashed at the parent blockchain).
  - IBC communication: IBC communication allows the parent and baby blockchain to communicate. We assume that the IBC communication is ordered and provides "timeout" and "acknowledgements" mechanisms.

### Properties

This subsection is devoted to defining properties that the Cross-Chain Validation protocol ensures.
Recall that the parent blockchain has an ability to demand a change to the validator set of the baby chain.
Moreover, we want to ensure the stake of validators of the baby blockchain are "frozen" at the parent chain.

Hence, we aim to achieve the following properties:
- *Liveness*: If the parent blockchain demands a change to the validator set of the baby chain to some set *V* of validators and the IBC communication successfully relays this demand to the baby blockchain, then the validator set of the baby blockchain is eventually set to *V* or to some set *V'*, such that the parent blockchain demanded a change to the validator set of the baby chain to *V'* **after** the demand for *V*.
- *Stake safety*: If a validator *v* belongs to a validator set of the baby blockchain, then the stake of *v* is frozen at the parent blockchain. Moreover, if the stake of *v* is unfrozen at the parent blockchain, the unbonding period has elapsed for *v* at the baby blockchain.
- *Stake liveness*: If the stake of a validator *v* is bonded at the parent blockchain, eventually the stake will be unbonded (some stake might be slashed).

### Closer look at the IBC communication

An IBC connection assumes two parties (the respective blockchains) involved in the communication. However, it also assumes a relayer which handles message transmissions between the two blockchains. The relayer carries a central responsibility in ensuring communication between the two parties.

A relayer intermediates communication between the two blockchains. Each blockchain exposes an API comprising read, write, as well as a queue (FIFO) functionality. So there are two parts to the communication API:

- a read/write store: The read/write store holds the entire state of the chain. Each module can write to this store.
- a queue of datagrams (packets):
Each module can pop datagrams stored in this queue and a relayer can push to this queue.

## Data Structures

We devote this section to defining the data structures used to represent the states of both parent and baby blockchain, as well as the packets exchanged by the two blockchains.

### Application data

#### Parent blockchain

- Frozen stake: Keeps track of frozen stake of validators.
- Outcoming data store: "Part" of the blockchain observable for the relayer. Namely, each packet written in outcoming data store will be relayed by the relayer.

#### Baby blockchain

- Unbonding: Keeps track of validators that are currently unbonding.
- Validator set: The validator set of the baby blockchain.
- ValSet changes: Keeps track of all demands of the parent blockchain for a change of the validator set of the baby blockchain in a **current** block.
- Outcoming data store: "Part" of the blockchain used for storing the packets that should be relayed to the parent blockchain (same as at the parent blockchain).

### Packet data

#### Sent by the parent blockchain

- ChangeValidatorSet(validatorSet, seqNum): Packet sent by the parent blockchain to the baby blockchain to express the demand of the parent blockchain to modify the validator set of the baby blockchain.
"New" validator set is defined in the *validatorSet* parameter, whereas the *seqNum* represents the unique identifier of the demand.

  *Remark:* There exists the acknowledgment packet for the ChangeValidatorSet packet. However, currently the acknowledgment packet does not influence any state transitions (as we introduce in the rest of the document).

#### Sent by the baby blockchain

- UnbondingOver(validatorSet, seqNum): Packet sent by the baby blockchain to signalize that the unbonding period has elapsed at the baby blockchain for every validator that is demanded in the *ChangeValidatorSet* packet with sequence number *seqNum*.

  *Remark:* There exists the acknowledgment packet for the UnbondingOver packet. However, currently the acknowledgment packet does not influence any state transitions (as we introduce in the rest of the document).


## Transitions

In this section, we informally discuss the state transitions that occur in our protocol.
We observe state transitions that are driven by an user, driven by the relayer and driven by elapsed time.

  - User-driven state transitions: These transitions "start" the entire process of changing the validator set of the baby blockchain.
  We assume that the staking module expresses the will to change the validator set of the baby blockchain. It is done at the End-Block method (as in the "single blockchain" scenario).

  - Transaction-driven state transitions: These are the state transitions that are driven by the relayer. Namely, these transitions are activated since communication between the two blockchains takes place. E.g., some packet is received via the IBC communication, a timeout has elapsed for a packet, acknowledgment for a packet is received.

  - Time-driven state transitions: These transitions are activated since some time has elapsed. As we will present in the rest of the document, time-driven state transitions help us determine when the unbonding period, measured at the baby blockchain, has elapsed for a validator.

  In the rest of the section, we will discuss the aforementioned state transitions in more detail.

## State Machine for a Single Validator Set Change demand

When we say that there is a *single* validator set change demand, we assume that this demand will be a single committed validator set change demand in a block at the baby blockchain.
If this is indeed the case, the validator set change indeed takes place at the baby blockchain.
In other words, the validator set of the baby blockchain changes to the validator set from the demand.

We now present the state machine for this case.
![image](../images/data_flow.png)

## Function Definitions

### Parent blockchain

This subsection will present the functions executed at the parent blockchain.

```golang
// invoked by the staking module of the parent blockchain to
// express will to modify the validator set of the baby blockchain;
// executed in the End-Block method; similarly to the "normal, single-blockchain" case
func changeValidatorSet(
  babyChainId: ChainId
  valSet: Validator[]) {
  // freeze stake of validators from valSet associated with the seqNum; seqNum is a variable of the staking module
  for each (v in valSet) {
      freezeStake(v, seqNum)
  }  

  // create the ChangeValidatorSet packet
  ChangeValidatorSet data = ChangeValidatorSet{valSet, seqNum++}

  // obtain the destination port of the baby blockchain
  destPort = getPort(babyChainId)

  // send the packet
  handler.sendPacket(Packet{timeoutHeight, timeoutTimestamp, destPort, destChannel, sourcePort, sourceChannel, data}, getCapability("port"))
}
```

- Expected precondition
  - There exists a blockchain with *babyChainId* identifier
  - All validators from *valSet* are validators at the parent blockchain
- Expected postcondition
  - Stake of each validator from *valSet* is frozen and associated with this demand (via *seqNum*)
  - The packet containing information about this change validator set demand is created
- Error condition
  - If the precondition is violated

```golang
// executed at the parent blockchain to handle a delivery of the IBC packet
func onRecvPacket(packet: Packet) {
  // the packet is of UnbondingOver type
  assert(Packet = UnbondingOver)

  valSet = packet.valSet
  seqNum = packet.seqNum

  // unfreeze stake of validators associated with this seqNum
  for each (v in valSet) {
    unfreezeStake(v, seqNum)
  }

  // construct the default acknowledgment
  ack = defaultAck(UnbondingOver)
  return ack
}
```

- Expected precondition
  - The *ChangeValidatorSet* packet is sent to the baby blockchain before this packet is received
  - The packet is of the *UnbondingOver* type
- Expected postcondition
  - Stake of each validator from *valSet* associated with a sequence number *seqNum* is unfrozen
  - The default acknowledgment is created
- Error condition
  - If the precondition is violated

```golang
// called once a sent packet has timed-out
function onTimeoutPacket(packet: Packet) {
  // the packet is of ChangeValidatorSet type
  assert(packet = ChangeValidatorSet)

  valSet = packet.valSet
  seqNum = packet.seqNum

  // unfreeze stake of validators associated with this seqNum
  for each (v in valSet) {
    unfreezeStake(v, seqNum)
  }
}
```

- Expected precondition
  - The *packet* has timed out
- Expected postcondition
  - Stake of each validator from *valSet* associated with a sequence number *seqNum* is unfrozen
- Error condition
  - If the precondition is violated  

### Baby blockchain

```golang
// executed at the baby blockchain to handle a delivery of the IBC packet
func onRecvPacket(packet: Packet) {
  // the packet is of ChangeValidatorSet type
  assert(Packet = ChangeValidatorSet)

  valSet = packet.valSet
  seqNum = packet.seqNum

  // inform the staking module of the new validator set change demand
  stakingModule.queueValidatorSetChange(valSet, seqNum)

  // construct the default acknowledgment
  ack = defaultAck(ChangeValidatorSet)
  return ack
}
```

- Expected precondition
  - The packet is of the *ChangeValidatorSet* type
- Expected postcondition
  - The staking module is queues the new validator set change demand
  - The default acknowledgment is created
- Error condition
  - If the precondition is violated

```golang
// End-Block method executed at the end of each block
func endBlock(block: Block) {
  // get time
  time = block.time

  // get the old validator set
  oldValSet, oldSeqNum = block.validatorSet

  // start unbonding for the old validator set and all validators set specified in the current block, except for last
  stakingModule.startUnbonding(oldValSet, oldSeqNum, time)
  while (stakingModule.sizeValidatorSetChangeQueue() > 1) {
    stakingModule.startUnbonding(stakingModule.dequeueValidatorSetChange(), time)
  }

  // finish unbonding for mature validator sets
  for each (valSet, seqNum in stakingModule.finishUnbonding(time)) {
    // create the UnbondingOver packet
    UnbondingOver data = UnbondingOver{valSet, seqNum}

    // obtain the destination port of the baby blockchain
    destPort = getPort(parentChainId)

    // send the packet
    handler.sendPacket(Packet{timeoutHeight, timeoutTimestamp, destPort, destChannel, sourcePort, sourceChannel, data}, getCapability("port"))
  }

  newValSet, newSeqNum = stakingModule.dequeueValidatorSetChange()
  return newValSet, newSeqNum
}
```

- Expected precondition
  - Every transaction from the *block* is executed
- Expected postcondition
  - Unbonding starts for the old validator set, as well as all validators set from the changes committed on the *block*, except for the last
  - Unbonding finishes for all validator set that started unbonding more than *unbondingTime* before *time = block.time*. Moreover, the *UnbondingOver* packet is created for each such validator set
  - The new validator set *valSet* is pushed to the Tendermint protocol and *valSet* belongs to the last validator set change demand committed on the *block*
- Error condition
  - If the precondition is violated



```golang
// called once a sent packet has timed-out
function onTimeoutPacket(packet: Packet) {
  // the packet is of UbondingOver type
  assert(packet = UnbondingOver)

  valSet = packet.valSet
  seqNum = packet.seqNum

  // create the UnbondingOver packet
  UnbondingOver data = UnbondingOver{packets, seqNum}

  // obtain the destination port of the baby blockchain
  destPort = getPort(parentChainId)

  // send the packet
  handler.sendPacket(Packet{timeoutHeight, timeoutTimestamp, destPort, destChannel, sourcePort, sourceChannel, data}, getCapability("port"))
}
```

- Expected precondition
  - The *packet* has timed out
- Expected postcondition
  - The *UnbondingOver* packet is create again
- Error condition
  - If the precondition is violated


### Port & channel setup

The `setup` function must be called exactly once when the module is created
to bind to the appropriate port.

```golang
func setup() {
  capability = routingModule.bindPort("cross-chain staking", ModuleCallbacks{
    onChanOpenInit,
    onChanOpenTry,
    onChanOpenAck,
    onChanOpenConfirm,
    onChanCloseInit,
    onChanCloseConfirm,
    onRecvPacket,
    onTimeoutPacket,
    onAcknowledgePacket,
    onTimeoutPacketClose
  })
  claimCapability("port", capability)
}
```

Once the `setup` function has been called, channels can be created through the IBC routing module
between instances of the cross-chain staking modules on mother and daughter chains.

##### Channel lifecycle management

Mother and daughter chains accept new channels from any module on another machine, if and only if:

- The channel being created is ordered.
- The version string is `icsXXX`.

```golang
func onChanOpenInit(
  order: ChannelOrder,
  connectionHops: [Identifier],
  portIdentifier: Identifier,
  channelIdentifier: Identifier,
  counterpartyPortIdentifier: Identifier,
  counterpartyChannelIdentifier: Identifier,
  version: string) {
  // only ordered channels allowed
  abortTransactionUnless(order === ORDERED)
  // assert that version is "icsXXX"
  abortTransactionUnless(version === "icsXXX")
}
```

```golang
func onChanOpenTry(
  order: ChannelOrder,
  connectionHops: [Identifier],
  portIdentifier: Identifier,
  channelIdentifier: Identifier,
  counterpartyPortIdentifier: Identifier,
  counterpartyChannelIdentifier: Identifier,
  version: string,
  counterpartyVersion: string) {
  // only ordered channels allowed
  abortTransactionUnless(order === ORDERED)
  // assert that version is "icsXXX"
  abortTransactionUnless(version === "icsXXX")
  abortTransactionUnless(counterpartyVersion === "icsXXX")
}
```

```golang
func onChanOpenAck(
  portIdentifier: Identifier,
  channelIdentifier: Identifier,
  version: string) {
  // port has already been validated
  // assert that version is "icsXXX"
  abortTransactionUnless(version === "icsXXX")
}
```

```golang
func onChanOpenConfirm(
  portIdentifier: Identifier,
  channelIdentifier: Identifier) {
  // accept channel confirmations, port has already been validated, version has already been validated
}
```

```golang
func onChanCloseInit(
  portIdentifier: Identifier,
  channelIdentifier: Identifier) {
  // the channel is closing, do we need to punish?
}
```

```golang
func onChanCloseConfirm(
  portIdentifier: Identifier,
  channelIdentifier: Identifier) {
  // the channel is closed, do we need to punish?
}
```

## State Machine for Multiple Validator Set Change demands

Note that "multiple" signalizes that more than one demand of the change validator set demand is committed in a block at the baby blockchain.
If that happens, only the last demand takes place, i.e., only the validator set specified in the last demand becomes the validator set of the baby blockchain.

The only difference from the "single" validator set change case is that the unbonding should start for "ignored" validator set changes.
The image below illustrates this.
![image](../images/data_flow_2.png)


## Correctness Arguments

Here we provide correctness arguments for the liveness, stake safety and stake liveness properties.

### Liveness
Suppose that the IBC communication indeed successfully relays the demand *ChangeValidatorSet(V, SN)* to the baby blockchain.
Therefore, either the validator set of the baby blockchain is set to *V* (if the *ChangeValidatorSet(V, SN)* is the only or the last demand of this type in a block at the baby blockchain) or the validator set is changed to some set *V'*.
If the first scenario occurs, the property is satisfied.

In order for the property to be satisfied even if the second scenario occurs, we must show that *ChangeValidatorSet(V', SN')* is demanded after *ChangeValidatorSet(V, SN)*.
We conclude that *ChangeValidatorSet(V', SN')* is the last demand of this type in a block.
Moreover, we know that *ChangeValidatorSet(V, SN)* is also in the same block.
Since the IBC communication is ordered, we conclude that indeed *ChangeValidatorSet(V', SN')* is demanded after *ChangeValidatorSet(V, SN)*.
Therefore, the property is satisfied.

### Stake safety

If the validator *v* belong to the validator set of the baby blockchain, we know that a *ChangeValidatorSet(V, SN)* is demanded by the parent blockchain, where *v in V*.
Since the stake is frozen at the moment of sending this demand, the first statement of the property is satisfied.

A stake of a validator *v* is unfrozen at the parent blockchain upon a receiption of the *UnbondingOver* packet.
Since this packet is sent by the baby blockchain only after the unbonding period has elapsed, the second claim of the property holds.

### Stake liveness
The unbonding period for each validator eventually elapses.
Since the *UnbondingOver* packet is resent until the packet is received by the parent blockchain, the stake is eventually unfrozen.

## Generalization

Note that we assume a single baby blockchain per a parent blockchain.
However, the protocol itself allows that a single parent blockchain takes care of multiple baby blockchains.
The only difference would be that the parent blockchain takes care of each "cross-chain validation"-related parameter **per** baby blockchain (i.e., the sequence numbers for the change validator set demands would be **per** baby blockchain, the "stake freezing" logic would be **per** baby blockchain, etc.).

<!----
## State

Validator set for a chain
- 'validatorSet[chainId]'

(Validator, ChainId) -> Public key
- 'validatorPublicKey'

## Desired properties

- Main safety property: If an evidence of a misbehavior is "timely" committed on a mother chain, then the misbehaving validator is slashed.
  "Committed on a mother chain" = evidence appears in a request of the BeginBlock method
  "timely": Let T_unbond be a time when an unbonding of a validator V starts (at the daughter chain; EndBlock method).
            Let T_evidence be a time when an evidence of misbehavior of V is discovered (at the daughter chain; BeginBlock method).
            Let T_mc_evidence be a time when an evidence of misbehavior of V is committed on a mother chain (BeginBlock method).
            Let T_timeout be a time when a mother chain "learns" that unbonding for V is over on the daughter chain.
            Then, "timely" = T_mc_evidence < T_timeout.
            Are T_unbond and T_evidence (and their relation with each other and other T's) important?

 - Main liveness property: For each validator V, where unbonding period for V is over on the daughter chain, the mother chain eventually unbonds V.
 Remark: The above liveness property seems like "the most important" liveness property. I guess we should discuss here about the daughter chain validators changes "initiated" by the mother chain.
         If we want to have that, I guess we should introduce something like: If the mother chain "wants" to change the validator set of the daughter chain, the change eventually "happens".

## Data Structures

`ValSetUpdatePacket` is sent by the mother chain to the daughter chain to inform the daughter chain about
the validator set changes.

```golang
struct ValSetUpdatePacket {
  valset  Validator[]
}
```

```golang
struct ValSetUpdateAcknowledgement {
  success  boolean
  error    string
}
```

`UnbondingTimeoutExpiredPacket` is sent by the daughter chain to the mother chain to inform the mother chain
that the unbonding period for a specific validator has expired.

```golang
struct UnbondingTimeoutExpiredPacket {
  validator Validator
}
```
// TODO Check whether an acknowledgment is necessary

## Protocol

### Port & channel setup

The `setup` function must be called exactly once when the module is created
to bind to the appropriate port.

```golang
func setup() {
  capability = routingModule.bindPort("cross-chain staking", ModuleCallbacks{
    onChanOpenInit,
    onChanOpenTry,
    onChanOpenAck,
    onChanOpenConfirm,
    onChanCloseInit,
    onChanCloseConfirm,
    onRecvPacket,
    onTimeoutPacket,
    onAcknowledgePacket,
    onTimeoutPacketClose
  })
  claimCapability("port", capability)
}
```

Once the `setup` function has been called, channels can be created through the IBC routing module
between instances of the cross-chain staking modules on mother and daughter chains.

##### Channel lifecycle management

Mother and daughter chains accept new channels from any module on another machine, if and only if:

- The channel being created is ordered.
- The version string is `icsXXX`.

```golang
func onChanOpenInit(
  order: ChannelOrder,
  connectionHops: [Identifier],
  portIdentifier: Identifier,
  channelIdentifier: Identifier,
  counterpartyPortIdentifier: Identifier,
  counterpartyChannelIdentifier: Identifier,
  version: string) {
  // only ordered channels allowed
  abortTransactionUnless(order === ORDERED)
  // assert that version is "icsXXX"
  abortTransactionUnless(version === "icsXXX")
}
```

```golang
func onChanOpenTry(
  order: ChannelOrder,
  connectionHops: [Identifier],
  portIdentifier: Identifier,
  channelIdentifier: Identifier,
  counterpartyPortIdentifier: Identifier,
  counterpartyChannelIdentifier: Identifier,
  version: string,
  counterpartyVersion: string) {
  // only ordered channels allowed
  abortTransactionUnless(order === ORDERED)
  // assert that version is "icsXXX"
  abortTransactionUnless(version === "icsXXX")
  abortTransactionUnless(counterpartyVersion === "icsXXX")
}
```

```golang
func onChanOpenAck(
  portIdentifier: Identifier,
  channelIdentifier: Identifier,
  version: string) {
  // port has already been validated
  // assert that version is "icsXXX"
  abortTransactionUnless(version === "icsXXX")
}
```

```golang
func onChanOpenConfirm(
  portIdentifier: Identifier,
  channelIdentifier: Identifier) {
  // accept channel confirmations, port has already been validated, version has already been validated
}
```

```golang
func onChanCloseInit(
  portIdentifier: Identifier,
  channelIdentifier: Identifier) {
  // the channel is closing, do we need to punish?
}
```

```golang
func onChanCloseConfirm(
  portIdentifier: Identifier,
  channelIdentifier: Identifier) {
  // the channel is closed, do we need to punish?
}
```

### Packet relay

```golang
func sendValSetUpdatePacket(
  valSet: Validator[],
  destPort: string,
  destChannel: string,
  sourcePort: string,
  sourceChannel: string,
  timeoutHeight: Height,
  timeoutTimestamp: uint64) {

  ValSetUpdatePacket data = ValSetUpdatePacket{valSet}
  handler.sendPacket(Packet{timeoutHeight, timeoutTimestamp, destPort, destChannel, sourcePort, sourceChannel, data}, getCapability("port"))
}
```

```golang
func sendUnbondingTimeoutExpiredPacket(
  validator: Validator) {

  UnbondingTimeoutExpiredPacket data = UnbondingTimeoutExpiredPacket{validator}
  handler.sendPacket(Packet{timeoutHeight, timeoutTimestamp, destPort, destChannel, sourcePort, sourceChannel, data}, getCapability("port"))
}
```

`onRecvPacket` is called by the routing module when a packet addressed to this module has been received.

```typescript
function onRecvPacket(packet: Packet) {
  Type type = packet.type()

  switch (type) {
    // executed on the daughter chain
    // validator set change demanded by the mother chain
    case ValSetUpdatePacket:
      ValSetUpdatePacket data = packet.data
      // perform some checks?

      // construct default acknowledgement of success
      ValSetUpdateAcknowledgement = ValSetUpdateAcknowledgement{true, null}

      newValSet = data.valSet // this information is forwarded to Tendermint at the end of the block (response to the EndBlock method)
      return ack;
      break;

      // executed on the mother chain
      // unbonding allowed by the daughter chain
      case UnbondingTimeoutExpiredPacket:
        Validator validator = packet.data.validator
        // construct default acknowledgement of success?

        if (validEvidenceExists(validator)) {
          slashingModule.slash(validator)
        }

        stakingModule.unbond(validator)

        // no acknowledgment needed?

    default:
      break;
  }
}

`onAcknowledgePacket` is called by the routing module when a packet sent by this module has been acknowledged.

```typescript
function onAcknowledgePacket(
  packet: Packet,
  acknowledgement: bytes) {  
  // if the update failed (why it would failed?) close channel
  if (!ack.success)
    close channel // TODO: Figure out if this is the right action to do
}
```

`onTimeoutPacket` is called by the routing module when a packet sent by this module has timed-out (such that it will
not be received on the destination chain).

```typescript
function onTimeoutPacket(packet: Packet) {
  // what we do on timeout? Does it make sense talking about retransmissions?
}
```

### Transaction callbacks

#### Mother chain

```typescript
// onCreateValidatorSet function = deliverTx(CreateValidatorSet)
function onCreateValidatorSet(
  chainId: ChainId,
  valset: Validator[]) {
  // do we assume that all chains can act as mother chains to all other chains?
  // or it can act as mother to only a strict subset of all chains?

  // check whether there exists a chain with the specified id
  if (!chainExists(chainId)) {
    return
  }

  // check whether all validators from the specified set are present on this (mother) chains
  if (!allPresent(thisChainId, valset)) {
    return
  }

  // check whether this is the first CreateValidatorSet transaction for the chain
  if (createValidatorSetSeen(chainId)) {
    return
  }  

  // update the validator set for a chain
  validatorSet[chainId] = valset

  // if this validator is in the validator set and its willing to participate,
  // then issue the transaction confirming this
  // question: What if a CreateValidatorSet tx is issued, but not all processes want to participate? It looks like this tx should not be considered
  if (me in valset) {
    issueTx("ConfirmInitialValidator", id, me, PK, stake)
  }
}
```

`function onCreateValidatorSet(chainId: ChainId, valset: Validator[])`
* Expected precondition
  * CreateValidatorSet transaction committed
  * there exists a chain with *chainId* Identifier
  * all validators from *valset* are users of this (mother) chains
  * no CreateValidatorSet transaction is processed before this one for the specified chains

* Expected postcondition
  * validator set for the specified chain is updated
  * if the host process is in the new validator set for the specified chain, it issues ConfirmInitialValidator transaction with its stake and public key that will be used on the specified chain

* Error condition
  * if the precondition is violated

```typescript
// onConfirmInitialValidator function = deliverTx(ConfirmInitialValidator)
function onConfirmInitialValidator(
  chainId: ChainId,
  validator: Validator,
  PK: PublicKey,
  stake: Integer) {
  // CreateValidatorSet processed before
  if (!CreateValidatorSetSeen()) {
    return
  }

  // validator specified in the CreateValidatorSet
  if (!validatorSet[chainId].contains(validator)) {
    return
  }

  // PK is a valid public key
  if (!validPublicKey(PK)) {
    return
  }

  // stake the money
  stakingModule.stakeForChain(chainId, validator, stake)

  // associate validator with the public key
  validatorPublicKey.set(validator, chainId, PK)

  // if every validator from the initial set confirmed, create a genesis file
  validatorsConfirmed.add(chainId, validator)
  if (validatorsConfirmed[chainId] == validatorSet[chainId]) {
    createGenesisFile(...)
  }
}
```

`function onConfirmInitialValidator(chainId: ChainId, validator: Validator, PK: PublicKey, stake: Integer)`
* Expected precondition
  * ConfirmInitialValidator transaction committed
  * CreateValidatorSet transaction for the chain with *chainId* identifier is already executed
  * Validator *validator* is specified in the CreateValidatorSet transaction
  * *PK* is a valid public key

* Expected postcondition
  * *stake* amount of money is staked for the validator *validator* and chain with *chainId* identifier
  * public key *PK* is associated with the validator *validator* and chain with *chainId* identifier
  * if the ConfirmInitialValidator is the last from the set of initial validators (specified by CreateValidatorSet transaction), then contribute to the genesis file

* Error condition
  * if the precondition is violated  

  ```typescript
  // onChangeValidatorSet function = deliverTx(ChangeValidatorSet)
  function onChangeValidatorSet(
    chainId: ChainId,
    valset: Validator[]) {
    // do we assume that all chains can act as mother chains to all other chains?
    // or it can act as mother to only a strict subset of all chains?

    // check whether there exists a chain with the specified id
    if (!chainExists(chainId)) {
      return
    }

    sendValSetUpdatePacket(chainId, valset)
  }
  ```

  `function onChangeValidatorSet(chainId: ChainId, valset: Validator[])`
  * Expected precondition
    * ChangeValidatorSet transaction committed
    * CreateValidatorSet transaction for the chain with *chainId* identifier is already executed

  * Expected postcondition
    * none

  * Error condition
    * if the precondition is violated  

#### Daughter chain

```typescript
// executed at the End-block
// do we need to specify this explicitly since there should exist this logic already?
function onValidatorSetChanged(
  valset: Validator[]) {
  // there is a change in the validator set of the daughter chain
  // start unbonding for validators that are not in the validator set anymore
  stakingModule.unbond(validatorSet[thisChainId], valset)

  // update the validator set
  validatorSet[thisChainId] = valset
}
```

`function onValidatorSetChanged(valset: Validator[])`
* Expected precondition
  * validator set changed at the End-Block method

* Expected postcondition
  * the unbonding (on the *daughter* chain) is started for validators that were removed from the new validator set (i.e., *valset*)
  * the validator set is updated

* Error condition
  * none


Since the daughter chain could be censored, the evidence should not be sent via IBC, but solely by means of the light client.
Hence, whenever a correct process executes BeginBlock method, it obtains a set of evidences.
Then, the light client "picks up" these evidences and must ensure that they are eventually committed on the mother chain.
\\ TODO discuss how to present this

```typescript
// executed at the BeginBlock with time T, where T - U > 3 weeks; U is time when the unbonding started
function onUnbondingFinished(T: BftTime) {
  // find validators that are done with the unbonding
  validators = stakingModule.unbondingFinished(T)

  // send the packet
  for each v in validators:
    sendUnbondingTimeoutExpiredPacket(v)
}
```

`function onUnbondingFinished(validator: Validator)`
* Expected precondition
  * a block B with time T is committed and an unbonding for the validator started at time U, where T - U > 3 weeks

* Expected postcondition
  * Inform the mother chain that the unbonding for the validator *validator* is finished, i.e., UnbondingTimeoutExpiredPacket is sent to the mother chain via IBC

* Error condition
  * none

## Remarks and discussion topics

One of the problems is that IBC is not resistant to the censorship attacks.
In other words, if a chain has more than N/3 faulty validators, an information might never be relayed between two chains.
This is, usually, not a problem since faulty processes have an incentive to behave "properly" with respect to IBC (e.g., UnbondingTimeoutExpiredPacket is relayed to the mother chain since faulty processes want to collect their money).

However, there might be some cases where this is not true.
For example, manipulation of a validator set of a daughter chain by a mother chain could be problematic.
Namely, the CHANGE_VALIDATOR_SET (issued by the mother chain) might never take place on a daughter chain.
In this way, daughter chain achieves complete autonomy in manipulating its own validator set.

## Light clients of the daughter chain

With a standalone chains, light client depends on the Tendermint security model
that is parameterized with the duration of the UNBONDING_PERIOD. Each block defines
a start of the UNBONDING_PERIOD for the new validator set defined by the committed block.
In case of cross chain validation, a validator set change on the mother change is
committed at some time t that is equal to block. Time where the block is the block at which
validator set changes has taken place.

Compared to the standalone chain, in the case of cross chain validation, the validator set change
is not effective at the commit time. The important scenario to consider is the case where a validator
unbonds its stake and wants to get its stake from the system. In the single chain case, this action
is blocked for a duration of the unbonding period. During this time frame, any detectable misbehavior
is slashable. Trust in the validator set is shortened by introducing trusted period that is shorter than
the unbonding period.

In the cross-chain staking scenario, validator set changes of the baby chain happens on the mother chain.
As validator set update is not immediately effective on the baby chain, upon unbonding request,
we should not start unbonding period before update is effective on the baby chain. This can for example
be implemented by delaying effective unbonding period before acknowledgment of the valset packet is
received.

The other problem is regarding the light client evidence submission. The existing light client evidence submission
protocol assumes that entry point for the evidence is a correct full node that has access to a correct blockchain.
Therefore, if we apply this model to the baby chain, light clients for the baby chain would be submitting
attack evidences to the full nodes of the baby chain. Then evidence is handled and processed on the baby chain and
the result (set of faulty processed and attack type) is sent to the mother chain over IBC channel. Note that
this assumes that there is an IBC channel open between mother and daughter.

Note: Is there a scenario in which IBC channel between mother chain and daughter chain is closed but
mother chain and daughter chain continues to operate? For example, assume that light client at the daughter
side of the IBC channel is in invalid state (either received evidence of misbehaviour or the latest header
has expired). In that case channel will be closed and baby chain should most probably shut down and start a
manual recovery. But if UNBONDING_PERIOD is not over, there is still a possibility that validators trick
light clients of the baby chain. In this case even if attack is detected there is no way to process and send
misbehaving processes to the mother chain. We should analyse what are faulty scenarios in which channel
can be closed and see how we can ensure light clients are still safe. Note that one interesting option
to consider is light client of the baby chain being able to also track mother chain (run also light client for
mother chain), but the issue in this case is the fact that the mother chain does not understand attack evidences
of the baby chain.
--->
