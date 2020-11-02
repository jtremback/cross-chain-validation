# Technical Specification

## State

Validator set for a chain
- 'validatorSet[chainId]'

(Validator, ChainId) -> Public key
- 'validatorPublicKey'

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

`EvidencePacket` is sent by the daughter chain once an evidence of misbehaviour is collected or an unbonding period is over at the daughter chain.

```golang
struct EvidencePacket {
  validator  Validator
  // is one evidence enough?
  evidence   Evidence[]
}
```

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
  // no action necessary
}
```

```golang
func onChanCloseConfirm(
  portIdentifier: Identifier,
  channelIdentifier: Identifier) {
  // no action necessary
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
func sendEvidencePacket(
  validator: Validator,
  evidence: Evidence[]) {

  UnbondingEndedPacket data = UnbondingEndedPacket{validator, evidence}
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

      // who manages validator sets in the SDK app and how do we pass this info to Tendermint?
      newValSet = data.valSet // how do we pass this information to Tendermint?
      return ack;
      break;

    // executed on the mother chain
    // unbonding allowed by the daughter chain
    case EvidencePacket:
      Validator val = packet.data.validator

      // check evidence
      if (!checkEvidence(validator, evidence, validatorPublicKey(validator, daughterChainId))) {
        return
      }

      // slash if there is an evidence
      slashingModule.slash(val, packet.data.evidence)

      // unbond
      stakingModule.unbound(val)

      // no acknowledgement needed?

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

```typescript
// performed on the mother chain
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
  * there exists a chain with *chainId* Identifier
  * all validators from *valset* are users of this (mother) chains
  * no CreateValidatorSet transaction is processed before this one for the specified chains

* Expected postcondition
  * validator set for the specified chain is updated
  * if the host process is in the new validator set for the specified chain, it issues ConfirmInitialValidator transaction with its stake and public key that will be used on the specified chain

* Error condition
  * if the precondition is violated

```typescript
// performed on the mother chain
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
  * CreateValidatorSet transaction for the chain with *chainId* identifier is already processed
  * Validator *validator* is specified in the CreateValidatorSet transaction
  * *PK* is a valid public key

* Expected postcondition
  * *stake* amount of money is staked for the validator *validator* and chain with *chainId* identifier
  * public key *PK* is associated with the validator *validator* and chain with *chainId* identifier
  * if the ConfirmInitialValidator is the last from the set of initial validators (specified by CreateValidatorSet transaction), then contribute to the genesis file

* Error condition
  * if the precondition is violated  

```typescript
// performed on the daughter chain
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
  * none

* Expected postcondition
  * the unbonding (on the *daughter* chain) is started for validators that were removed from the new validator set (i.e., *valset*)
  * the validator set is updated

* Error condition
  * none

```typescript
// performed on the daughter chain
function onEvidenceDiscovered(
  validator: Validator,
  evidence: Evidence) {
  // evidence is valid
  if (!valid(evidence, validator)) {
    return
  }

  // check whether the validator finished unbonding
  if (stakingModule.checkStatus(validator) == UNBONDED) {
    return
  }

  // store the evidence
  evidence[validator].append(evidence)

  // jail the validator -> this leads to a change of the validator set on the daughter chain?
  jailValidator(validator)

  // inform the mother chain
  sendEvidencePacket(validator, evidence[validator])

  // ignore the unbondingFinishedEvent
  unbondingFinishedEvent[validator] = true
}
```

`function onEvidenceDiscovered(validator: Validator, evidence: Evidence)`
* Expected precondition
  * evidence *evidence* is valid and associated with the validator *validator*

* Expected postcondition
  * if the validator *validator* is already unbonded, nothing happens
  * if the validator *validator* is not unbonded, then collect the evidence *evidence*, jail the validator *validator*, send the evidence *evidence* to the mother chain and set to ignore the UnbondingFinishedEvent

* Error condition
  * if the precondition is violated

```typescript
// performed on the daughter chain
function onUnbondingFinished(
  validator: Validator) {
  // check whether the unbonding event should be ignored
  if (unbondingFinishedEvent[validator]) {
    return
  }

  // inform the mother chain that the unbonding is done
  sendEvidencePacket(validator, null)
}
```

`function onUnbondingFinished(validator: Validator)`
* Expected precondition
  * none

* Expected postcondition
  * if UnbondingFinishedEvent is not ignored, then inform the mother chain that the unbonding for the validator *validator* is finished

* Error condition
  * none

## Light clients of the daughter chain

With a standalone chains, light client depends on the Tendermint security model
that is parameterized with the duration of the UNBONDING_PERIOD. Each block defines
a start of the UNBONDING_PERIOD for the new validtor set defined by the committed block.
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
