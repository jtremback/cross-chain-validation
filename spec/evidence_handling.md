# Evidence Handling

## Introduction

This document discusses the evidence handling in the **Cross-Chain Validation** protocol.
Recall that the main goal of the Cross-Chain Validation protocol is to allow a new blockchain (baby blockchain) to be secured by some existing and *highly secure* blockchain (parent blockchain).
In other words, validators that are responsible for securing the parent blockchain "lend" their services to the baby blockchain.
Importantly, the increased security of the baby blockchain is a consequence of the fact that misbehaviors of its (baby blockchain's) validators are penalised on the parent blockchain (which is highly secure by the assumption, i.e., significant amount of tokens are bonded on the parent blockchain).

For the aforementioned concept to work and reinforce, the **evidence handling** subprotocol should be designed.
Namely, an evidence of each misbehavior discovered on the baby blockchain should be "transferred" and verified on the parent blockchain.
This document is devoted to discussing the evidence handling subprotocol of the Cross-Chain Validation protocol.

## "Normal-case" evidence handling

The purpose of this subsection is to briefly discuss how the evidence handling subprotocol operates in the "normal-case", i.e., when each blockchain is responsible exclusively for itself.

A Block produced by the Tendermint consensus protocol can include evidences of misbehaviors committed by validators of the block.
The relevant information is handed over to the application in the *Begin-Block* callback, so misbehaving validators could be punished accordingly.

More information about evidence handling with respect to a light client:
[Light Client Attack Detector](https://github.com/tendermint/spec/blob/master/rust-spec/lightclient/detection/detection_003_reviewed.md), [Light Client Supervision](https://github.com/tendermint/spec/blob/master/rust-spec/lightclient/supervisor/supervisor_001_draft.md).

## Evidence handling subprotocol

This subsection provides an informal description of the evidence handling subprotocol.
We start by introducing an assumption about evidence verification and computability.

Assumption: Let *e* represent an evidence of misbehavior of a set *X* of faulty validators of the baby blockchain.
Every correct full node of the parent blockchain verifies that *e* is a valid evidence of the misbehavior of a validator *v in X*, for every *v in X*.\
The aforementioned assumption simply states that evidence could be correctly verified on the parent blockchain.

We now introduce entities that play a role in the evidence handling subprotocol.

### Light Client

A light client is a lightweight alternative to a full node.
In contrast to full nodes, light clients only verify results of transactions (without executing them).
Namely, a light client verifies block headers, given a trusted block header.
The verification of block headers is done using the skipping verification concept.

With respect to the evidence handling subprotocol, a light client of the baby blockchain is capable of collecting an evidence of misbehavior of faulty validators of the baby blockchain.
Moreover, the light client is able to send the aforementioned evidence to full nodes of the parent blockchain.
Importantly, we assume that light client is able to communicate (i.e., send evidence to) at least one *correct* full node.

### Full Node

Full nodes execute transactions submitted to a blockchain.
Similarly to light clients, they also verify results of transactions.

In our context, a full node receives an evidence of misbehavior from a light client.
Then, the full node is responsible for ensuring that the evidence eventually becomes committed on the parent blockchain.

### The subprotocol

![image](./images/evidence_handling.PNG)

### Discussion

This subsection discusses guarantees provided by the evidence handling subprotocol.
Namely, the communication between a light client and a full node is not timely.
Moreover, time that takes a transaction to be committed on a blockchain is unbounded.
Recall that a validator could be slashed only within the *unbonding period*.
Because of the unbounded communication delays and "commit" times, it is impossible to guarantee that the evidence will be committed on the parent blockchain **before** the unbonding period expires.

We define the following times:
- Latest time of detection: *D* (this time represents a *trusting period*)
- Maximum evidence transfer delay from a light client to a full node of the parent blockchain: *T*
- Maximum evidence submit time on the parent blockchain: *S*
- Maximum evidence commit time on the parent blockchain: *C*

Now, we define when the evidence handling subprotocol is guaranteed to operate successfully, i.e., when a misbehaving validator of the baby blockchain indeed gets slashed:

Let some misbehaving validator *v* leave the validator set of the baby blockchain at some time *t*.
Validator *v* gets slashed at the parent blockchain if and only if *D + T + S + C <= unbonding period*.

The evidence handling subprotocol operates successfully only if *D + T +S + C <= unbonding period*.
Namely, only if all of the aforementioned actions are executed "fast enough", a misbehaving validator will indeed be slashed.
Note here that we assume that time needed for a packet to be transferred from the baby to the parent blockchain is negligible.
If we assume that the time is not negligible, i.e., this transfer takes at least *X* time, we reach the following equation: *D + T + S +C <= unbonding period + X*.
