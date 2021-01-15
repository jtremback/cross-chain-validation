# Evidence Handling

## Introduction

This document discusses the evidence handling in the **Cross-Chain Validation** protocol.
Recall that the main goal of the Cross-Chain Validation protocol is to allow a new blockchain (baby blockchain) to be secured by some existing and *highly secure* blockchain (parent blockchain).
In other words, validators that are responsible for securing the parent blockchain "lend" their services to the baby blockchain.
Importantly, the increased security of the baby blockchain is a consequence of the fact that misbehaviors of its (baby blockchain's) validators are penalised on the parent blockchain (which is highly secure by the assumption, i.e., significant amount of tokens are bonded on the parent blockchain).

For the aforementioned concept to work, the **evidence handling** subprotocol should be designed.
Namely, an evidence of each misbehavior discovered on the baby blockchain should be "transferred" and verified on the parent blockchain.
This document is devoted to discussing the evidence handling subprotocol of the Cross-Chain Validation protocol.

## "Normal-case" evidence handling

The purpose of this subsection is to briefly discuss how the evidence handling subprotocol operates in the "normal-case", i.e., when each blockchain is responsible exclusively for itself.

A Block produced by the Tendermint consensus protocol can include evidences of misbehaviors committed by validators of the block.
The relevant information is handed over to the application in the *Begin-Block* callback, so misbehaving validators could be punished accordingly.

<span style="color:red">
Jovan: Do we want to go deeper here?
</span>

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
Moreover, the light client is able to send the aforementioned evidence to a full node of the parent blockchain.

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

<span style="color:red">
Jovan: How do we define time here? Specifically, there is one notion of time on the baby blockchain, and another on the parent blockchain.

A light client "accepts" an evidence if the evidence is within the trusting period of the validator (however, time here refers to time on the baby blockchain).
Then, the light client sends the evidence to a full node which ensures that eventually the evidence is committed on the parent blockchain.
Clearly, the slashing takes place if the evidence is committed before the UNBONDING_OVER packet (from the baby blockchain) is committed.
How can we provide discussion "deeper" than the simplistic one from the last sentence.
Am I mistaken somewhere?
</span>
