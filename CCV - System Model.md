# Cross-Chain Verification (CCV)

## System Model

### Blockchains

A *blockchain* is a tamper-proof distributed sequence of *blocks*.
A block is a sequence of transactions.
Each block of a blockchain is *verified* by a set of pre-determined *full nodes*.
Moreover, each block defines a set of full nodes that have the responsibility to verify the next block in the sequence.

We assume that a blockchain is associated with *UnbondingPeriod* parameter.
This parameter denotes a time period.

A validator is a tuple (id, power), where id represents a unique identifier of a full node and power denotes the voting power of the full node.
A *validator set* is a set of validators such that no two validators have the same id.
<!-- A validator set V = {(id1, power1), ..., (idN, powerN)} is a validator set of block b if and only if full nodes id1, ..., idN verified b with their associated voting powers.
We say that V is a validator set of blockchain B at time T if and only if V is specified by block b', where b' is the last block of B at time T. -->

<!-- #### Stake

A stake is a non-negative integer.
Each full node of a blockchain is assoaciated with a sequence of stakes.
The voting power of a validator is proportional to the stake of the validator. -->

#### Validator Set Update

A *validator set update* is simply a validator set.
It is used to describe changes to some other validator set.
Each validator set can be *merged* with another validator set, where:
```
(ValidatorSet validatorSet).merge(ValidatorSet validatorSetUpdate):
    merged = validatorSet
    for each v = (id, power) in validatorSetUpdate:
        merged.removeValidatorWithId(id)
        merged.add(v)
    
    return merged
```

### Setup

We consider two blockchains: blockchain *parent* and blockchain *baby*.
These blockchains are able to communicate over an ordered IBC channel.
We say that the ordered IBC channel is in one of two states:
- active: The channel is operating properly, i.e., the packets sent by the parent to the baby blockchain are eventually received and they are received in the order in which they were sent. Moreover, the received packets could be acknowledged by the baby blockchain (the packets are acknowledged in the order they were sent).
- failed: The channel can transit from active to failed state at any point in time (the opposite is not true).
Once the channel is in the failed state, it does not provide transit of packets between two blockchains.
Moreover, once the channel fail, it never restores to the active state.

If the channel never fails, we say that the channel is forever-active.

## Problem Definition

The CCV module exposes the following interface:
- Request \<ChangeValidatorSet, seqnum, update\>: demands that the validator set of the baby blockchain reflects update; invoked only by the parent blockchain.
- Indication \<FreeStake, seqnum, result\>, where result = {(id1, freeStake1), ..., (idN, freeStakeN)}: indicates that the full node with id1 is free to take freeStake1, etc.
- Indication \<UpdatedValidatorSet, seqnum, valSet\>: indicates that the validator set is updated to valSet; triggered only on the baby blockchain.

We assume the following:
Let \<ChangeValidatorSet, seqnum, update\> be the i-th invoked operation.
Then, seqnum = i.

### Properties

We say that a validator set V is *made of* a sequence of validator sets u[1], u[2], ..., u[n] if and only if V = u[1].merge(u[2]).merge(u[3]). ... .merge(u[n]).
Now, we define the properties of the CCV module:

- **FreeStake Order:** Let <FreeStake, seqnum, result> and <FreeStake seqnum', result'> be triggerred such that seqnum' > seqnum.
Then, <FreeStake, seqnum, result> is triggerred before <FreeStake, seqnum', result'>.

- **UpdatedValidatorSet Order:** Let <UpdatedValidatorSet, seqnum, valSet> and <UpdatedValidatorSet, seqnum', valSet'> be triggered such that seqnum' > seqnum.
Then, <UpdatedValidatorSet, seqnum, valSet> is triggerred before <UpdatedValidatorSet, seqnum', valSet'>.

- **Safety Parent:** Let <FreeStake, seqnum, result> be triggerred T, where (id, freeStake) in result.
Then, <UpdatedValidatorSet, s, valSet> is triggerred at T' such that:
    - s >= seqnum,
    - valSet is made of a sequence u[1], ..., u[s],
    - (id, p1) in u[i], for some 1 <= i <= s,
    - (id, p2) in u[j], for some i < j <= s,
    - no (id, p) in u[k], for any i < k < j,
    - p2 - p1 = freeStake,
    - T - T' >= UnbondingPeriod.

- **Safety Baby:** Let <UpdatedValidatorSet, seqnum, valSet> be triggerred.
Then, valSet is made of a sequence u[1], u[2], ..., u[seqnum] and, for every i in [1, seqnum], <ChangeValidatorSet, i, u[i]> is invoked. 

- **Liveness Parent:** Let <ChangeValidatorSet, seqnum1, u1> be invoked, where (id, p1) in u1.
Let <ChangeValidatorSet, seqnum2, u2> be the first operation invoked after <ChangeValidatorSet, seqnum1, u1> and let (id, p2) in u1 and p1 > p2.
If the channel is forever-active, then eventually <FreeStake, seqnum2, result> is triggered such that (id, p1 - p2) in result.

- **Liveness Baby:** Let <ChangeValidatorSet, seqnum, u> be invoked.
If the channel is forever-active, then <UpdatedValidatorSet, seqnum', valSet'> is eventually triggered such that valSet' is made of a sequence u[1], ..., u[seqnum], ... .



<!-- If the channel is forever-active, then there exists a validator set V and a sequence of validator set updates seq such that:
    - V is the validator set of  -->

<!-- We assume the following: Let \<ChangeValidatorSet, update\> is invoked and let v in update, where v = (id, stake). Then, stake in seq, where seq = stake[id].
This assumption simply states that stake is "noted" on the parent blockchain before the operation is invoked. -->

     

<!-- ### Assumptions

We make the following assumptions:
- Let \<ChangeValidatorSet, update\> is invoked and let v in update, where v = (id, stake). Then, stake in seq, where seq = stake[id].
-  -->




<!-- A *blockchain* is a tamper-proof sequence of *blocks*.
A block is a sequence of transactions and each block is *verified* by a set of *validators*.
If a block B is verified with a set V of validators, we say that V is the validator set of B.

Each block defines a set of validators that verify the next block of the blockchain.
We say that V is the validator set of blockchain B at time T if and only if V is defined by block b, where b is the last block of B at time T.

We consider two blockchains: blockchain *parent* and blockchain *baby*. -->