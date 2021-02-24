# Evidence Handling - overview

## Introduction

This document discusses the overview of the evidence handling in the **Cross-Chain Validation** protocol.
Recall that the main goal of the Cross-Chain Validation protocol is to allow a new blockchain (baby blockchain) to be secured by some existing and *highly secure* blockchain (parent blockchain).
In other words, validators that are responsible for securing the parent blockchain "lend" their services to the baby blockchain.
Importantly, the increased security of the baby blockchain is a consequence of the fact that misbehaviors of its (baby blockchain's) validators are penalized on the parent blockchain (which is highly secure by the assumption, i.e., significant amount of tokens are bonded on the parent blockchain).

For the aforementioned concept to work and reinforce, the **evidence handling** subprotocol should be designed.
Namely, an evidence of each misbehavior discovered on the baby blockchain should be "transferred" and verified on the parent blockchain.
This document is devoted to discussing the evidence handling subprotocol of the Cross-Chain Validation protocol.

## "Normal-case" evidence handling

The purpose of this subsection is to briefly discuss how the evidence handling subprotocol operates in the "normal-case", i.e., when each blockchain is responsible exclusively for itself.

A block produced by the Tendermint consensus protocol can include evidences of misbehaviors committed by validators of the block.
The relevant information is handed over to the application in the `Begin-Block` callback, so misbehaving validators could be punished accordingly.
<br> Moreover, there could be other scenarios of interest.
For example, a fork could occur on the blockchain (two different blocks are decided in the same height) or a light client attack could take place.
In these scenarios, it is necessary to detect which validators are faulty, to produce proofs of their misbehavior and only then to punish them accordingly.

More information about evidence handling with respect to a light client:
[Light Client Attack Detector](https://github.com/tendermint/spec/blob/master/rust-spec/lightclient/detection/detection_003_reviewed.md), [Light Client Supervision](https://github.com/tendermint/spec/blob/master/rust-spec/lightclient/supervisor/supervisor_001_draft.md).

## Evidence handling subprotocol

This subsection provides an informal description of the evidence handling subprotocol.
We analyze two scenarios:
1. An observed light client attack on the baby blockchain, and
2. Evidence of a misbehavior committed in a block on the baby blockchain.

We first illustrate the light client attack scenario.
Then, we do the same for the second scenario.

TODO: modify the document once evidence verification on the parent blockchain is properly discussed.

### Light Client Attack Scenario

![image](../images/evidence_handling.PNG)

### Committed Evidence Scenario

![image](../images/evidence_handling_3.PNG)
