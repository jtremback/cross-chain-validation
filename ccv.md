# TYPES

```python
type ValidatorSetUpdate

type ValidatorSetUpdatePacket: {
    "updates": Set<ValidatorSetUpdate>
}

type ValidatorSetUpdateAck: {
    "updates": Set<ValidatorSetUpdate>
}

type unbondingChanges: Set<ValidatorSetUpdate>

type unbondingTimes: Set<(Timestamp, ValidatorSetUpdate)>
```

# Parent Chain

```python
def ChangeValidatorSet(update: ValidatorSetUpdate):
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
# NOTE: How does this work with epochs?
def OnEndBlock():
    # if pendingUpdates is empty, do nothing
    if pendingUpdates.isEmpty():
        return

    # set unbonding changes
    unbondingChanges.insert(pendingUpdates)
    
    # send the packet
    packet: ValidatorSetUpdatePacket = {
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
- If `pendingChanges` is not empty, then the `ValidatorSetUpdatePacket` with the updates from `pendingChanges` is created and sent.
- If `pendingChanges` is not empty, then `pendingChanges` are added into `unbondingChanges`.
- If `pendingChanges` is not empty, then `pendingChanges` is emptied.

**Error condition:**
- None
---
```python
def OnValidatorSetUpdateAck(ack: ValidatorSetUpdateAck):
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
- ValidatorSetUpdateAck is received.

**Expected postcondition:**
- `BABY_LIGHT_CLIENT_ON_PARENT.ClientUpdated() = true`; Note that it is possible for `BABY_LIGHT_CLIENT_ON_PARENT.ClientUpdated()` to return `false`. If that is the case, then `BABY_LIGHT_CLIENT_ON_PARENT.ClientUpdate(header)` is invoked, where header is the header of the latest height of the parent blockchain, which does ensure that the next call of `BABY_LIGHT_CLIENT_ON_PARENT.ClientUpdated()` returns true.
- `chain.unbondStake(ack.updates)` is invoked.
- `ack.updates` are removed from `unbondingChanges`.
- for each update in packet.updates, `<MatureUpdate, update>` is triggered.

**Error condition:**
- None

# Baby Chain

```python
def OnValidatorSetUpdatePacket(packet: ValidatorSetUpdatePacket):
    # store the updates from the packet
    pendingChanges.insert(packet.updates)
```

**Initiator:** Relayer

**Expected precondition:**
- Packet datagram is committed on the blockchain.
- `PARENT_LIGHT_CLIENT_ON_BABY.ClientUpdated() = true;` Note that it is possible for `PARENT_LIGHT_CLIENT_ON_BABY.ClientUpdated()` to return `false`. If that is the case, then `PARENT_LIGHT_CLIENT_ON_BABY.ClientUpdate(header)` is invoked, where header is the header of the latest height of the parent blockchain, which does ensure that the next call of `PARENT_LIGHT_CLIENT_ON_BABY.ClientUpdated()` returns true.

**Expected postcondition:**
- `packet.updates` are added to `pendingChanges`.

**Error condition:**
- If the precondition is violated.
---
```python
def OnEndBlock():
    for update in pendingChanges:
        # calculate and store the unbonding time for the packet in unbondingTimes
        unbondingTimes.insert((UnbondingPeriod + chain.blockTime(), packet.updates))

        # update the chain's validator set
        chain.applyValidatorSetUpdate(update)

        # trigger the ValidatorSetUpdate condition
        trigger <ValidatorSetUpdate, update>

    for (unbondingTime, updates) in unbondingTimes:
        # if the change is fully unbonded
        if chain.blockTime()) >= unbondingTime:
            # send an ValidatorSetUpdateAck to the parent chain
            packet: ValidatorSetUpdateAck = {
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
    - `<ValidatorSetUpdate, update>` is triggered.
    - `(unbondingTime, updates)` is added to `unbondingTimes`, where `unbondingTime = UnbondingPeriod + blockTime()`.
- for each (unbondingTime, updates) where currentTime >= unbondingTime
    - `ValidatorSetUpdateAck` is sent
    - the tuple is removed from unbondingTime.
- pendingChanges is emptied.

**Error condition:**
- None

# Correctness
## Safety - Parent: 
`<MatureUpdate, update>` is not triggered unless `ChangeValidatorSet(update)` has been previously invoked.

### Proof:
`<MatureUpdate, update>` is triggered once its `ValidatorSetUpdatePacket` is acknowledged with an `ValidatorSetUpdateAck`, where `update` in `packet.updates`. Hence, packet has been previously sent. Thus, `ChangeValidatorSet(update)` has been previously invoked.

## Unbonding Safety: 
If `<ValidatorSetUpdate, update>` is triggered at time `T`, then `<MatureUpdate, update>` is not triggered before `T + UnbondingPeriod`.

### Proof
Let `<MatureUpdate, update>` be triggered on the parent chain at time `T`. This implies that a `ValidatorSetUpdatePacket` from the parent chain is acknowledged with an `ValidatorSetUpdateAck` from the baby chain, where `update` in `packet.updates`. Furthermore, this means that `UnbondingPeriod` has elapsed on baby chain between the time that the `ValidatorSetUpdatePacket` was received and the `ValidatorSetUpdateAck` was sent. 

Once the first `OnEndBlock` on baby chain is invoked after `ValidatorSetUpdatePacket` is received, `<ValidatorSetUpdate, update>` is triggered; let this time be `T'`. Since `T'` is also the time at which packet is received by the baby blockchain, we conclude that Unbonding Safety is satisfied.

## Order Preservation - Parent:
If `<MatureUpdate, update>` is triggered before `<MatureUpdate, update'>`, then `ChangeValidatorSet(update)` is invoked before `ChangeValidatorSet(update')`.

### Proof:
Let `<MatureUpdate, update>` be triggered before `<MatureUpdate, update'>`. This means that a `ValidatorSetUpdatePacket` from the parent chain is acknowledged with an `ValidatorSetUpdateAck` from the baby chain, where `update` in `ValidatorSetUpdateAck.updates`. Moreover, a `ValidatorSetUpdatePacket'` is acknowledged with an `ValidatorSetUpdateAck'`, where `update'` in `ValidatorSetUpdateAck'.updates`.

We consider two possible cases:
- `ValidatorSetUpdateAck = ValidatorSetUpdateAck'`: This means that `update` comes before `update'` in `ValidatorSetUpdateAck.updates`. Hence, `pendingChanges` has update coming before `update'` (because `ValidatorSetUpdateAck` is "built" out of `pendingChanges`). Thus, `ChangeValidatorSet(update)` is invoked before `ChangeValidatorSet(update')`.
- `ValidatorSetUpdateAck != ValidatorSetUpdateAck'`: This means that `ValidatorSetUpdateAck'` is sent after `ValidatorSetUpdateAck` (since `ValidatorSetUpdatePacket`s are acknowledged with `ValidatorSetUpdateAck`s in the order they were sent). Hence, `ChangeValidatorSet(update)` is invoked before `ChangeValidatorSet(update')` because of the ordered channel.

## Safety - Baby:
`<ValidatorSetUpdate, update>` is not triggered on the baby chain unless `ChangeValidatorSet(update)` has been previously invoked on the parent chain.

### Proof:
Let `<ValidatorSetUpdate, update>` be triggered. This means that `update` in `pendingChanges`. Hence, `ValidatorSetUpdatePacket` with `update` in `packet.updates` is received. Hence, `ChangeValidatorSet(update)` has been previously invoked.

## Order Preservation - Baby:
If `<ValidatorSetUpdate, update>` is triggered before `<ValidatorSetUpdate, update'>`, then `ChangeValidatorSet(update)` is invoked before `ChangeValidatorSet(update')`.

### Proof:
Let `<ValidatorSetUpdate, update>` be triggered before `<ValidatorSetUpdate, update'>`. This means that a `ValdiatorSetUpdatePacket` is received, where `update` in `ValdiatorSetUpdatePacket.updates`. Moreover, a `ValdiatorSetUpdatePacket'` is received, where `update'` in `ValdiatorSetUpdatePacket'.updates`.

## Liveness - Parent:
Let `ChangeValidatorSet(update)` be invoked. If the channel and both blockchains are forever-active, then eventually `<MatureUpdate, update>` is triggered.

> "forever-active" means that no packet times out. That is there is an active relayer. If a validator wants liveness, then it should run a relayer.

## Liveness - Baby:
Let `ChangeValidatorSet(update)` be invoked on the parent chain. If the channel and both blockchains are forever-active, then eventually `<ValidatorSetUpdate, update>` is triggered on the baby chain.

#### Jehan's note - forever-active and ValidatorSetUpdateAck

This definition of forever-active needs to be looked at closely. If validators on the baby chain can censor the `ValidatorSetUpdatePacket` indefinitely, then they can keep control of the baby chain with few consequences.
I don't remember all the details of how IBC works, but the following mechanisms may prevent it from happening:

- If the baby chain validators censor the `ValidatorSetUpdatePacket`, it will be impossible for the baby chain validators to ever unstake their tokens, since `<MatureUpdate, update>` will never be triggered. Presumably these staked tokens can continue to generate staking rewards though, so this is not a full deterrent.
- There must be a timeout of some kind after which the baby chain validators get punished on the parent chain if a `ValidatorSetUpdatePacket` never appears on the baby chain. This timeout must be shorter than the parent chain unbonding period.