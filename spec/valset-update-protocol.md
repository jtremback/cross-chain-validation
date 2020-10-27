# Technical Specification

## State

The mother chain should know what is the active validator set of the daughter chain.

- 'daughterValidators'

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

`onRecvPacket` is called by the routing module when a packet addressed to this module has been received.

```typescript
function onRecvPacket(packet: Packet) {
  ValSetUpdatePacket data = packet.data
  // perform some checks?
  // construct default acknowledgement of success
  ValSetUpdateAcknowledgement = ValSetUpdateAcknowledgement{true, null}
  // who manages validator sets in the SDK app and how do we pass this info to Tendermint?
  newValSet = data.valSet // how do we pass this information to Tendermint?
  return ack
}

`onAcknowledgePacket` is called by the routing module when a packet sent by this module has been acknowledged.

```typescript
function onAcknowledgePacket(
  packet: Packet,
  acknowledgement: bytes) {  
  // if the update failed (why it would failed?) close channel
  if (!ack.success)
    close channel // TODO: Figure out if this is the right action to do

  // othwerise, start unbonding the validators that have left the active validator set of the daughter chain
  ValSetUpdatePacket data = packet.data
  startUnbonding(daughterValidators, data.valset)
  // how do we start unbonding?

  // update the active validator set of the daughter chain
  daughterValidators = data.valset
}
```

`onTimeoutPacket` is called by the routing module when a packet sent by this module has timed-out (such that it will
not be received on the destination chain).

```typescript
function onTimeoutPacket(packet: Packet) {
  // what we do on timeout? Does it make sense talking about retransmissions?
}
```

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
