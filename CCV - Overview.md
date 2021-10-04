The goal of CCV is to create a "baby blockchain" whose validators can be punished for misbehavior by losing tokens they have staked on a parent chain. This could be useful because the stake in one parent chain could be used to secure a number of different baby chains. The stake on the parent chain would be securing all of the baby chains simultaneously, allowing total security to be higher than if the same amount of value was split between all the baby chains.

CCV functions by allowing the baby chain to update its validator set in lockstep with the parent chain. This updating is necessary to make sure that control of the baby chain reflects tokens staked on the parent chain. For example, if a validator unstakes all its tokens on the parent chain, this needs to be reflected on the baby chain, otherwise the validator could corrupt the baby chain and not be punished on the parent.


## Protocol Narrative:

I will focus on unbonding during this narrative since that is the trickier interaction.

### Parent chain sends ChangeValidatorSet packet
If stake has been unbonded on the parent chain during a block, the parent chain will send a `ValidatorSetChangePacket` to the baby chain. The parent chain adds the updates to its `unbondingChanges` record. As long as an update is in this record, the unbonded tokens cannot be fully unlocked. The unbonded tokens will be fully unlocked once an `ValidatorSetChangeAck` is received from the baby chain.

### Baby chain applies changes
During each block, the baby chain receives and stores `ValidatorSetChangePacket` packets. It also stores the unbonding time of each packet in its `unbondingTimes` record. That is, at which block in the future it is safe to unbond stake on the parent chain based on validator set changes in this packet. For example, if a `ValidatorSetChangePacket` removes a validator from the validator set, and the unbonding period on the baby chain is 2 weeks, it will be safe to unbond that validator's stake on the parent chain in 2 weeks.

At the end of the block, the baby chain applies the updates from all received `ValidatorSetChangePacket` packets to its validator set. 

### Baby chain sends ValidatorSetChangeAcks
Every block, the baby chain looks at its `unbondingTimes` record, finds `ValidatorSetChangePacket` packets whose unbonding block has passed, and sends `ValidatorSetChangeAck`s to the parent chain, letting the parent chain know that it is safe to fully unlock tokens unbonded by the related `ValidatorSetChangePacket` packets.

### Parent chain receives ValidatorSetChangeAck
The parent chain removes the relevant unbondings from its `unbondingChanges` record, and allows the tokens to be fully unlocked and transferable (provided that they are not encumbered by ongoing unbondings of any other baby chains or the parent chain).
