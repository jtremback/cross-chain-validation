# Protocol

This document provides the specification of the CCV protocol.

# Light Client

We assume that a light client (`PARENT_LIGHT_CLIENT_ON_BABY` and `BABY_LIGHT_CLIENT_ON_PARENT`) expose the following methods:

- `ClientUpdate(Header header)`: void - updates the client with the header.

- `ClientUpdated()`: boolean - checks whether the client is updated.
# Data structures

```python
type ValidatorSetUpdate
```
`ValidatorSetUpdates` are produced by the parent blockchain, outside of the CCV module.
They contain information describing a change to the parent chain's
validator set 

---

```python
type ValidatorSetChangePacket: {
    "updates": List<ValidatorSetUpdate>
}
```
`ValidatorSetChangePacket` is sent from the parent chain to the baby chain. 
it contains an ordered list of ValidatorSetChanges
that must be applied to the baby chain validator set

---

```python
type ValidatorSetChangeAck: {
    "updates": List<ValidatorSetUpdate>
}
```
`ValidatorSetChangeAck` is sent from the baby chain to the parent chain
to let the parent chain know that the updates were completed
more than the baby chain's unbonding period ago. This means
that in most cases this ack will be sent more than two weeks 
after its corresponding ValidatorSetChangePacket.

---

```python
type unbondingChanges: List<ValidatorSetUpdate>
```
`unbondingChanges` is a data structure on the parent chain which records the
validator set updates that have been made and sent to the baby chain but 
have not yet been acknowledged.

---

```python
type unbondingTimes: List<(Timestamp, List(ValidatorSetUpdate))>
```
`unbondingTimes` is a data structure on the baby chain which records the
currently unbonding updates and the time that they were applied.
It is used by the baby chain to know when to send ValidatorSetChangeAcks
to the parent chain.

# Parent Chain

```python
def ChangeValidatorSet(update: ValidatorSetChange):
    pendingChanges.add(update)
```

**Initiator:** Application on the parent blockchain.

**Expected precondition:**
- CCV channel among two blockchains has already been established.

**Expected postcondition:**
- The update is added to the pendingChanges.

**Error condition:**
- None.
---
```python
def OnEndBlock():
    # if pendingUpdates is empty, do nothing
    if pendingUpdates.isEmpty():
        return

    # set unbonding changes
    unbondingChanges.insert(pendingUpdates)
    
    # send the packet
    packet: ValidatorSetChangePacket = {
        "updates": pendingUpdates
    }
    sendPacket(babyId, packet)
    
    # empty pending changes in preparation for next block
    pendingChanges.empty()
```

**Initiator:** Automicatically initiated at the end of each block.

**Expected precondition:**
- EndBlock method is invoked.

**Expected postcondition:**
- If `pendingChanges` is not empty, then the `ValidatorSetChangePacket` with the updates from `pendingChanges` is created and sent.
- If `pendingChanges` is not empty, then `pendingChanges` are added into `unbondingChanges`.
- If `pendingChanges` is not empty, then `pendingChanges` is emptied.

**Error condition:**
- None
---
```python
def OnValidatorSetChangeAck(ack: ValidatorSetChangeAck):
    # unbond the stake; JOVAN: do we need to discuss this more since it is important in general, but not relevant to our problem definition
    chain.unbondStake(ack.updates)
    
    # delete the pending changes
    unbondingChanges.delete(ack.updates)
    
    # trigger that all updates have matured
    for update in ack.updates:
        trigger <MatureUpdate, update>
```

**Initiator:** Relayer

**Expected precondition:**
- ValidatorSetChangeAck is received.

**Expected postcondition:**
- `BABY_LIGHT_CLIENT_ON_PARENT.ClientUpdated() = true`; Note that it is possible for `BABY_LIGHT_CLIENT_ON_PARENT.ClientUpdated()` to return `false`. If that is the case, then `BABY_LIGHT_CLIENT_ON_PARENT.ClientUpdate(header)` is invoked, where header is the header of the latest height of the parent blockchain, which does ensure that the next call of `BABY_LIGHT_CLIENT_ON_PARENT.ClientUpdated()` returns true.
- `chain.unbondStake(ack.updates)` is invoked.
- `ack.updates` are removed from `unbondingChanges`.
- for each update in packet.updates, `<MatureUpdate, update>` is triggered.

**Error condition:**
- None

# Baby Chain

```python
def OnValidatorSetChangePacket(packet: ValidatorSetChangePacket):
    # store the updates from the packet
    pendingChanges.insert(packet.updates)

    # calculate and store the unbonding time for the packet in unbondingTimes
    unbondingTimes.insert((UnbondingPeriod + chain.blockTime(), packet.updates))
```

**Initiator:** Relayer

**Expected precondition:**
- Packet datagram is committed on the blockchain.
- `PARENT_LIGHT_CLIENT_ON_BABY.ClientUpdated() = true;` Note that it is possible for `PARENT_LIGHT_CLIENT_ON_BABY.ClientUpdated()` to return `false`. If that is the case, then `PARENT_LIGHT_CLIENT_ON_BABY.ClientUpdate(header)` is invoked, where header is the header of the latest height of the parent blockchain, which does ensure that the next call of `PARENT_LIGHT_CLIENT_ON_BABY.ClientUpdated()` returns true.

**Expected postcondition:**
- `packet.updates` are added to `pendingChanges`.
- `(unbondingTime, updates)` is added to `unbondingTimes`, where `unbondingTime = UnbondingPeriod + blockTime()`.

**Error condition:**
- If the precondition is violated.
---
```python
def OnEndBlock():
    for update in pendingChanges:
        # update the chain's validator set
        chain.applyValidatorSetChange(update)

        # trigger the ValidatorSetChange condition
        trigger <ValidatorSetChange, update>

    for (unbondingTime, updates) in unbondingTimes:
        # if the change is fully unbonded
        if chain.blockTime()) >= unbondingTime:
            # send an ValidatorSetChangeAck to the parent chain
            packet: ValidatorSetChangeAck = {
                "updates": updates
            }
            chain.sendPacket(parentId, packet)
            unbondingTimes.delete((unbondingTime, updates))
        else:
            break

    # empty pending changes in preparation for next block
    pendingChanges.empty()
```

**Initiator:** Automicatically initiated at the end of each block.

**Expected precondition:**
- EndBlock method is invoked.

**Expected postcondition:**
- for every update in pendingChanges
    - the chain's validator set is updated
    - `<ValidatorSetChange, update>` is triggered.
- for each (unbondingTime, updates) where currentTime >= unbondingTime
    - `ValidatorSetChangeAck` is sent
    - the tuple is removed from unbondingTime.
- pendingChanges is emptied.

**Error condition:**
- None

# Correctness
## Safety - Parent: 
`<MatureUpdate, update>` is not triggered unless `ChangeValidatorSet(update)` has been previously invoked.

### Proof:
`<MatureUpdate, update>` is triggered once its `ValidatorSetChangePacket` is acknowledged with an `ValidatorSetChangeAck`, where `update` in `packet.updates`. Hence, packet has been previously sent. Thus, `ChangeValidatorSet(update)` has been previously invoked.

## Unbonding Safety: 
If `<ValidatorSetChange, update>` is triggered at time `T`, then `<MatureUpdate, update>` is not triggered before `T + UnbondingPeriod`.

### Proof
Let `<MatureUpdate, update>` be triggered on the parent chain at time `T`. This implies that a `ValidatorSetChangePacket` from the parent chain is acknowledged with an `ValidatorSetChangeAck` from the baby chain, where `update` in `packet.updates`. Furthermore, this means that `UnbondingPeriod` has elapsed on baby chain between the time that the `ValidatorSetChangePacket` was received and the `ValidatorSetChangeAck` was sent. 

Once the first `OnEndBlock` on baby chain is invoked after `ValidatorSetChangePacket` is received, `<ValidatorSetChange, update>` is triggered; let this time be `T'`. Since `T'` is also the time at which packet is received by the baby blockchain, we conclude that Unbonding Safety is satisfied.

## Order Preservation - Parent:
If `<MatureUpdate, update>` is triggered before `<MatureUpdate, update'>`, then `ChangeValidatorSet(update)` is invoked before `ChangeValidatorSet(update')`.

### Proof:
Let `<MatureUpdate, update>` be triggered before `<MatureUpdate, update'>`. This means that a `ValidatorSetChangePacket` from the parent chain is acknowledged with an `ValidatorSetChangeAck` from the baby chain, where `update` in `ValidatorSetChangeAck.updates`. Moreover, a `ValidatorSetChangePacket'` is acknowledged with an `ValidatorSetChangeAck'`, where `update'` in `ValidatorSetChangeAck'.updates`.

We consider two possible cases:
- `ValidatorSetChangeAck = ValidatorSetChangeAck'`: This means that `update` comes before `update'` in `ValidatorSetChangeAck.updates`. Hence, `pendingChanges` has update coming before `update'` (because `ValidatorSetChangeAck` is "built" out of `pendingChanges`). Thus, `ChangeValidatorSet(update)` is invoked before `ChangeValidatorSet(update')`.
- `ValidatorSetChangeAck != ValidatorSetChangeAck'`: This means that `ValidatorSetChangeAck'` is sent after `ValidatorSetChangeAck` (since `ValidatorSetChangePacket`s are acknowledged with `ValidatorSetChangeAck`s in the order they were sent). Hence, `ChangeValidatorSet(update)` is invoked before `ChangeValidatorSet(update')` because of the ordered channel.

## Safety - Baby:
`<ValidatorSetChange, update>` is not triggered on the baby chain unless `ChangeValidatorSet(update)` has been previously invoked on the parent chain.

### Proof:
Let `<ValidatorSetChange, update>` be triggered. This means that `update` in `pendingChanges`. Hence, `ValidatorSetChangePacket` with `update` in `packet.updates` is received. Hence, `ChangeValidatorSet(update)` has been previously invoked.

## Order Preservation - Baby:
If `<ValidatorSetChange, update>` is triggered before `<ValidatorSetChange, update'>`, then `ChangeValidatorSet(update)` is invoked before `ChangeValidatorSet(update')`.

### Proof:
Let `<ValidatorSetChange, update>` be triggered before `<ValidatorSetChange, update'>`. This means that a `ValidatorSetChangePacket` is received, where `update` in `ValidatorSetChangePacket.updates`. Moreover, a `ValidatorSetChangePacket'` is received, where `update'` in `ValidatorSetChangePacket'.updates`.

We consider two possible cases:
- `ValidatorSetChangePacket = ValidatorSetChangePacket'`: This means that `update` comes before `update'` in `ValidatorSetChangePacket.updates`. Thus, `<ValidatorSetChange, update>` is invoked before `<ValidatorSetChange, update'>`.
- `ValidatorSetChangePacket != ValidatorSetChangePacket'`: This means that `packet'` is sent after `packet` (since packets are received in the order they were sent). Hence, `<ValidatorSetChange, update>` is invoked before `<ValidatorSetChange, update'>` because of the ordered channel.

## Liveness - Parent:
Let `ChangeValidatorSet(update)` be invoked. If the channel and both blockchains are forever-active, then eventually `<MatureUpdate, update>` is triggered.

> "forever-active" means that no packet times out. That is there is an active relayer. If a validator wants liveness, then it should run a relayer.

### Proof:
Let `ChangeValidatorSet(update)` be invoked.

Since the channel is forever-active, `update` is eventually received on the baby blockchain.
At that point, the packet is added to `unbondingTimes`.

Because of the fact that the baby blockchain is also forever-active, the `UnbondingPeriod` eventually elapses and the packet is acknowledged.

Thus, `<MatureUpdate, update>` is eventually triggered.

## Liveness - Baby:
Let `ChangeValidatorSet(update)` be invoked on the parent chain. If the channel and both blockchains are forever-active, then eventually `<ValidatorSetChange, update>` is triggered on the baby chain.

### Proof:
Let `ChangeValidatorSet(update)` be invoked.

Since the channel and the baby blockchain is forever-active, `update` is eventually received on the baby blockchain.

Hence, it is added to `pendingChanges`.

Once `EndBlock()` is invoked, `<ValidatorSetUpdate, update>` is triggered.


<!-- #### Jehan's note - forever-active and ValidatorSetChangeAck

This definition of forever-active needs to be looked at closely. If validators on the baby chain can censor the `ValidatorSetChangePacket` indefinitely, then they can keep control of the baby chain with few consequences.
I don't remember all the details of how IBC works, but the following mechanisms may prevent it from happening:

- If the baby chain validators censor the `ValidatorSetChangePacket`, it will be impossible for the baby chain validators to ever unstake their tokens, since `<MatureUpdate, update>` will never be triggered. Presumably these staked tokens can continue to generate staking rewards though, so this is not a full deterrent.
- There must be a timeout of some kind after which the baby chain validators get punished on the parent chain if a `ValidatorSetChangePacket` never appears on the baby chain. This timeout must be shorter than the parent chain unbonding period. -->