# TYPES

```python
type ValidatorSetUpdate

type ValidatorSetUpdatePacket: {
    "updates": Set<ValidatorSetUpdate>
}

type UnbondingPacket: {
    "updates": Set<ValidatorSetUpdate>
}

type unbondingChanges: Set<ValidatorSetUpdate>

type unbondingTimes: Set<(Timestamp, ValidatorSetUpdate)>
```

# PARENT CHAIN

```python
def ChangeValidatorSet(update: ValidatorSetUpdate):
    pendingChanges.add(update)
```

NOTE: Epoch?

```python
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

```python
def OnUnbondingPacket(packet: UnbondingPacket):
    # unbond the stake; JOVAN: do we need to discuss this more since it is important in general, but not relevant to our problem definition
    chain.unbondStake(packet.updates)
    
    # delete the pending changes
    unbondingChanges.delete(packet.updates)
    
    # trigger that all updates have matured
    for update in packet.updates:
        trigger <MatureUpdate, update>
```

# BABY CHAIN

```python
def OnValidatorSetUpdatePacket(packet: ValidatorSetUpdatePacket):
    # store the updates from the packet
    pendingChanges.insert(packet.updates)
```

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
            # send an UnbondingPacket to the parent chain
            packet: UnbondingPacket = {
                "updates": updates
            }
            chain.sendPacket(parentId, packet)
            unbondingTimes.delete((unbondingTime, updates))
        else:
            break

    # empty pending changes in preparation for next block
    pendingChanges.empty()
```


## Safety - Parent: 
`<MatureUpdate, update>` is not triggered unless `ChangeValidatorSet(update)` has been previously invoked.

### Proof:
`<MatureUpdate, update>` is triggered once its `ValidatorSetUpdatePacket` is acknowledged with an `UnbondingPacket`, where `update` in `packet.updates`. Hence, packet has been previously sent. Thus, `ChangeValidatorSet(update)` has been previously invoked.

## Unbonding Safety: 
If `<ValidatorSetUpdate, update>` is triggered at time `T`, then `<MatureUpdate, update>` is not triggered before `T + UnbondingPeriod`.

### Proof
Let `<MatureUpdate, update>` be triggered on the parent chain at time `T`. This implies that a `ValidatorSetUpdatePacket` from the parent chain is acknowledged with an `UnbondingPacket` from the baby chain, where `update` in `packet.updates`. Furthermore, this means that `UnbondingPeriod` has elapsed on baby chain between the time that the `ValidatorSetUpdatePacket` was received and the `UnbondingPacket` was sent. 

<!-- JEHAN's note: Not sure what the following sentence adds: Once the first `OnEndBlock` on baby chain is invoked after `ValidatorSetUpdatePacket` is received, `<ValidatorSetUpdate, update>` is triggered; let this time be `T'`. Since `T'` is also the time at which packet is received by the baby blockchain, we conclude that Unbonding Safety is satisfied. -->

## Order Preservation - Parent:
If `<MatureUpdate, update>` is triggered before `<MatureUpdate, update'>`, then `ChangeValidatorSet(update)` is invoked before `ChangeValidatorSet(update')`.

### Proof:
Let `<MatureUpdate, update>` be triggered before `<MatureUpdate, update'>`. This means that a `ValidatorSetUpdatePacket` from the parent chain is acknowledged with an `UnbondingPacket` from the baby chain, where `update` in `packet.updates`. Moreover, a `ValidatorSetUpdatePacket'` is acknowledged with an `UnbondingPacket`, where `update'` in `packet'.updates`.

We consider two possible cases:
- `packet = packet'`: This means that `update` comes before `update'` in `packet.updates`. Hence, `pendingChanges` has update coming before `update'` (because `packet` is "built" out of `pendingChanges`). Thus, `ChangeValidatorSet(update)` is invoked before `ChangeValidatorSet(update')`.
- `packet != packet'`: This means that `packet'` is sent after `packet` (since `ValidatorSetUpdatePacket`s are acknowledged with `UnbondingPacket`s in the order they were sent). Hence, `ChangeValidatorSet(update)` is invoked before `ChangeValidatorSet(update')` because of the ordered channel.

## Safety - Baby:
`<ValidatorSetUpdate, update>` is not triggered on the baby chain unless `ChangeValidatorSet(update)` has been previously invoked on the parent chain.

### Proof:
Let `<ValidatorSetUpdate, update>` be triggered. This means that `update` in `pendingChanges`. Hence, `ValidatorSetUpdatePacket` with `update` in `packet.updates` is received. Hence, `ChangeValidatorSet(update)` has been previously invoked.

## Order Preservation - Baby:
If `<ValidatorSetUpdate, update>` is triggered before `<ValidatorSetUpdate, update'>`, then `ChangeValidatorSet(update)` is invoked before `ChangeValidatorSet(update')`.

### Proof:
Let `<ValidatorSetUpdate, update>` be triggered before `<ValidatorSetUpdate, update'>`. This means that a `ValdiatorSetUpdatePacket` is received, where `update` in `packet.updates`. Moreover, a `ValdiatorSetUpdatePacket'` is received, where `update'` in `packet'.updates`.

JEHAN'S NOTE: for completeness, this needs some extra analysis of a case where `packet = packet'`, as in `Order Preservation - Parent`

## Liveness - Parent:
Let `ChangeValidatorSet(update)` be invoked. If the channel and both blockchains are forever-active, then eventually `<MatureUpdate, update>` is triggered.

"forever-active" means that no packet times out. That is there is an active relayer. If a validator wants liveness, then it should run a relayer.

## Liveness - Baby:
Let `ChangeValidatorSet(update)` be invoked on the parent chain. If the channel and both blockchains are forever-active, then eventually <ValidatorSetUpdate, update> is triggered on the baby chain.

#### Jehan's note - forever-active and UnbondingPacket

This definition of forever-active needs to be looked at closely. If validators on the baby chain can censor the `ValidatorSetUpdatePacket` indefinitely, then they can keep control of the baby chain with few consequences.
I don't remember all the details of how IBC works, but the following mechanisms may prevent it from happening:

- If the baby chain validators censor the `ValidatorSetUpdatePacket`, it will be impossible for the baby chain validators to ever unstake their tokens, since `<MatureUpdate, update>` will never be triggered. Presumably these staked tokens can continue to generate staking rewards though, so this is not a full deterrent.
- There must be a timeout of some kind after which the baby chain validators get punished on the parent chain if a `ValidatorSetUpdatePacket` never appears on the baby chain. This timeout must be shorter than the parent chain unbonding period.
- I'm not completely familiar with IBC, but it seems like the acknowledgement packet of `ValidatorSetUpdatePacket` would be an ideal vehicle for this. If an acknowledgement packet is not received within a certain timeout, the baby chain validators are slashed to punish censorship.
- I think the above point precludes the use of the `ValidatorSetUpdatePacket`'s IBC acknowledgement to signal that unbonding is complete on the baby chain, in cases where the baby chain's unbonding period is greater than or equal to the parent chain's unbonding period.
- For this reason, I have defined `UnbondingPacket` for the baby chain to signal to the parent that unbonding is complete. This also seems more intuitive, as most "acknowledgement" messages in other computing contexts happen shortly after the message they are acknowledging, not weeks later.

<NOTE: the below was written with an incorrect understanding of IBC channel timeouts and acknowledgements>
<!-- - IBC channel may time out on the parent chain if the `ValidatorSetUpdatePacket`'s acknowledgement is not received within a certain time. In "Discussion about channel abstraction", Jovan states "In the CCV protocol, the IBC channel used between parent and baby blockchains cannot ever timeout". I'm not sure if this is intended to mean that: 
    - A. The IBC channel will be configured so that it never times out at all, or, 
    - B. If the IBC channel does ever time out, we have moved outside of the bounds of the CCV definition.
    - If A, then the CCV protocol is vulnerable to an attack where the baby chain validators censor the `ValidatorSetUpdatePacket` packet and retain control of the baby chain forever, while forfeiting their ability to unbond their parent chain stake (they may be OK with this).
    - If B, then we should probably expand the definition to cover this condition because it is important.
- To expand the definition to cover IBC channel timeouts, we can consider the following two options: <NOTE: This is not the timeout we want>
- The parent chain could have a slashing condition to provide a more severe punishment to the baby chain validators if the channel times out.
- A baby chain with a timed out CCV channel could be considered permanently disabled. -->

<!-- #### Jehan's note - packet types and acks
I have changed this protocol to have two separate packet types- `ValidatorSetUpdatePacket` and `UnbondingPacket`. It is implied that each of these has an acknowledgement packet that goes back to the sending chain, and that the IBC channel times out if this is not received. In Jovan's original protocol, the `UnbondingPacket` is simply called an "acknowledgement". I'm not sure if this is intended to literally be the IBC ack packet. If it is, this may raise some issues with the timeout. This message is sent from the baby chain back to the parent chain only after the baby chain's unbonding period has elapsed.

- If the channel's timeout is the same length as the baby chain's unbonding period, the channel will timeout the first time it is used.
    - This implies that the channel's timeout must be longer than the baby chain's unbonding period, with a margin of error for packet relaying time.
    - The parent's unbonding period would have to be longer than both the baby chain's unbonding period and the channel timeout. If this is not the case, the baby chain validators can start unbonding on the parent chain, censor the `ValidatorSetUpdatePacket` on the baby chain, 

- If the channel is ordered, that is, if it is not possible to send packet2 until after packet1's acknowledgement has been received (is this the correct definition of an ordered channel?), then it will not be possible to change the baby chain's validator set more than once per unbonding period.

Both of these outcomes are pretty bad, and for that reason, I have concluded that `ValidatorSetUpdatePacket` and `UnbondingPacket` are separate packet types, each with their own acknowledgement. -->