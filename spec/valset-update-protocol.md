# Technical Specification

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
