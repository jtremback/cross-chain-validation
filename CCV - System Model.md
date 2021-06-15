# Cross-Chain Validation (CCV)

## System Model

### Blockchains

A *blockchain* is a tamper-proof distributed sequence of *blocks*.
A block is a sequence of transactions.
Each block of a blockchain is *verified* by a set of pre-determined *full nodes*.
Moreover, each block defines a set of full nodes that have the responsibility to verify the next block in the sequence.

If a blockchain keeps appending blocks to its sequence, we say that the blockchain is *forever-active*.

We assume that a blockchain is associated with *UnbondingPeriod* parameter.
This parameter denotes a time period.

A validator is a tuple (id, power), where id represents a unique identifier of a full node and power denotes the voting power of the full node.
A *validator set* is a set of validators such that no two validators have the same id.
Morevoer, a *validator set update* is a validator set and it is used to describe changes to a validator set.

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
- Request \<ChangeValidatorSet, ValidatorSetUpdate update\>: demands that the validator set of the baby blockchain reflects update; invoked only by the parent blockchain.
- Indication \<MatureUpdate, ValidatorSetUpdate update\>: indicates that update has matured; triggered only on the parent blockchain.
- Indication \<ValidatorSetUpdate, ValidatorSetUpdate update\>: indicates that update should be applied to the validator set; triggered only on the baby blockchain.

We assume that no two identical <ChangeValidatorSet> operations are invoked.

### Properties

Now, we define the properties of the CCV module:

- **Safety - Parent:** <MatureUpdate, update> is not triggered unless <ChangeValidatorSet, update> has been previously invoked.

- **Unbonding Safety:** Let <MatureUpdate, update> be triggered at time T.
Then, <ValidatorSetUpdate, update> is triggered at time T', where T - T' >= UnbondingPeriod.

- **Order Preservation - Parent:** Let <MatureUpdate, update> be triggered before <MatureUpdate, update'>.
Then, <ChangeValidatorSet, update> is invoked before <ChangeValidatorSet, update'>.

- **Safety - Baby:** <ValidatorSetUpdate, update> is not triggered unless <ChangeValidatorSet, update> has been previously invoked.

- **Order Preservation - Baby:** Let <ValidatorSetUpdate, update> be triggered before <ValidatorSetUpdate, update'>.
Then, <ChangeValidatorSet, update> is invoked before <ChangeValidatorSet, update'>.

- **Liveness - Parent:** Let <ChangeValidatorSet, update> be invoked.
If the channel and both blockchains are forever-active, then eventually <MatureUpdate, update> is triggered.

- **Liveness - Baby:** Let <ChangeValidatorSet, update> be invoked.
If the channel and both blockchains are forever-active, then eventually <ValidatorSetUpdate, update> is triggerred.