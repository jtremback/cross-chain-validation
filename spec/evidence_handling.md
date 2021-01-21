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

A block produced by the Tendermint consensus protocol can include evidences of misbehaviors committed by validators of the block.
The relevant information is handed over to the application in the `Begin-Block` callback, so misbehaving validators could be punished accordingly.
<br> Moreover, there could be other scenarios of interest.
For example, a fork could occur on the blockchain (two different blocks are decided in the same height) or a light client attack could take place.
In these scenarios, it is necessary to detect which validators are faulty, to produce proofs of their misbehaviour and only then to punish them accordingly.

More information about evidence handling with respect to a light client:
[Light Client Attack Detector](https://github.com/tendermint/spec/blob/master/rust-spec/lightclient/detection/detection_003_reviewed.md), [Light Client Supervision](https://github.com/tendermint/spec/blob/master/rust-spec/lightclient/supervisor/supervisor_001_draft.md).

## Evidence handling subprotocol

This subsection provides an informal description of the evidence handling subprotocol.
We start by introducing an assumption about evidence verification and computability.

Assumption: Let *e* represent an evidence of misbehavior of a set *X* of faulty validators of the baby blockchain.
Every correct full node of the parent blockchain verifies that *e* is a valid evidence of the misbehavior of a validator *v in X*, for every *v in X*.
<br>The aforementioned assumption simply states that evidence could be correctly verified on the parent blockchain.

In the rest of the document, we analyze two scenarios:
1. An observed light client attack on the baby blockchain, and
2. Evidence of a misbehaviour committed in a block on the baby blockchain.

We first discuss the light client attack scenario.
Then, we do the same for the second scenario.

### Light Client Attack Scenario

We first introduce entities that play a role in the evidence handling subprotocol in the light client attack scenario.

#### Light Client

A light client is a lightweight alternative to a full node.
In contrast to full nodes, light clients only verify results of transactions (without executing them).
Namely, a light client verifies block headers, given a trusted block header.
The verification of block headers is done using the skipping verification concept.

With respect to the evidence handling subprotocol, a light client of the baby blockchain is capable of observing a light client attack.
Moreover, the light client is able to inform a full node of the baby blockchain that the light client attack has indeed occurred.
Importantly, we assume that light client is able to communicate (i.e., send evidence to) at least one *correct* full node.

#### Full Node

Full nodes execute transactions submitted to a blockchain.
Similarly to light clients, they also verify results of transactions.

In our context, a full node (of the baby blockchain) receives information that a light client attack has occurred.
Then, the full node is able to deduce misbehaving validators that have mounted the attack.
Lastly, the full node is capable of transferring its deduction to full nodes of the parent blockchain.

#### Subprotocol

![image](./images/evidence_handling.PNG)

#### Discussion

This subsection discusses guarantees provided by the evidence handling subprotocol.
Namely, the communication between a light client and a full node is not timely.
Moreover, time that takes a transaction to be committed on a blockchain is unbounded.
Recall that a validator could be slashed only within the *unbonding period*.
Because of the unbounded communication delays and "commit" times, it is impossible to guarantee that the evidence will be committed on the parent blockchain **before** the unbonding period expires.


We define the following times (times are defined with respect to the baby blockchain; moreover, global time is defined as a bfttime of the last block produced by the baby blockchain):
- Latest time of detection: *D* (this time represents a *trusting period*)
- Maximum evidence transfer delay from a light client to a full node of the baby blockchain: *T1*
- Maximum evidence transfer delay from a full node of the baby blockchain to a full node of the parent blockchain: *T2*
- Maximum evidence submit time on the parent blockchain: *S*
- Maximum evidence commit time on the parent blockchain: *C*

Now, we define when the evidence handling subprotocol is guaranteed to operate successfully, i.e., when a misbehaving validator of the baby blockchain indeed gets slashed:

Let some misbehaving validator *v* leave the validator set of the baby blockchain at some time *t*.
Validator *v* gets slashed at the parent blockchain if and only if *D + T1 + T2 + S + C <= unbonding period*.

Note that *D* (*trusting period*) and *unbonding period* are parameters of the baby blockchain.
Moreover, *D << unbonding period* so that the aforementioned equation is indeed satisfied even when other actions take long.

The evidence handling subprotocol operates successfully only if *D + T1 + T2 + S + C <= unbonding period*.
Namely, only if all of the aforementioned actions are executed "fast enough", a misbehaving validator will indeed be slashed.
Note here that we assume that time needed for a packet to be transferred from the baby to the parent blockchain is negligible.
If we assume that the time is not negligible, i.e., this transfer takes at least *X* time, we reach the following equation: *D + T1 + T2 + S + C <= unbonding period + X*.

### Committed Evidence Scenario

#### Subprotocol
The protocol for this scenario is also quite simple.
Once an evidence has been committed on the baby blockchain, it is transferred via IBC to the parent blockchain.
Once the evidence has been received on the parent blockchain, the slashing could take place (since the evidence is **already** committed on the blockchain).

### Pseudocode

In this subsection, we represent pseudocode of the evidence handling subprotocol.
<br>First, we present data structures that abstract (1) an evidence of a misbehaviour of a validator, (2) an evidence that a light client attack has occurred, and (3) a packet sent by the baby blockchain to the parent blockchain.
<br>Then, we define functions and callbacks needed to ensure that validators of the baby blockchain that have mounted a light client attack are slashed at the parent blockchain.
<br>Lastly, we present functions and callbacks needed to transfer an evidence, which is committed on the baby blockchain, to the parent blockchain.

#### Data Structures

The following data structure abstracts an evidence of a misbehaviour of a validator:
```golang
type Evidence struct {
  evidence Evidence
  validator Validator
  chain ChainId
}
```
Namely, this data structure specifies that validator *validator* committed a misbehaviour which is provable with *evidence*.
Note that we specify the identifier of chain where the misbehaviour occurred (this represents a slight difference from the "single-chain" scenario).
We assume that each correct full node could verify this statement and that no verifiable evidence could ever be produced to prove a misbehaviour of a correct validator.

Next, the data structure below represents an evidence that a light client attack has taken place:
```golang
type LightClientAttackEvidence struct {
  conflictingBlock LightBlock
  commonHeight int64
  chain ChainId
}
```

Lastly, we introduce a data structure that abstracts a packet with an evidence committed on the baby blockchain:
```golang
type CommittedEvidencePacket struct {
  evidence Evidence
}
```

#### Light Client Attack Scenario

Let us first describe the protocol that is executed once a light client of the baby blockchain discovers that a light client attack has occurred:
<br>Once a light client discovers that a light client attack on the baby blockchain has taken place, it transfers this information to full nodes of the baby blockchain (we assume that at least one correct full node receives this information).
<br>A correct full node is able to interpret the received information and produce an evidence of misbehaviour for some faulty validators.
<br>Then, the full node transfers information about exposed faulty validators (along with evidences) to full nodes of the parent blockchain.
<br>Lastly, once a correct full node of the parent blockchain receives this information, it informs its staking module, which is responsible for ensuring that the evidences end up committed on the parent blockchain.

The following function is invoked once a light client of the baby blockchain discovers that a light client attack has occurred:
```golang
// Submits evidence of a light client attack to a set of full nodes
func submitLightClientAttackEvidence(evidence LightClientAttackEvidence, fullNodeSample []FullNode)
```
- Expected precondition
  - A light client attack has occurred
- Expected postcondition
  - Evidence is submitted to each full node from *fullNodeSample*
-Error condition
  - If the precondition is violated

As we have already mentioned, a (correct) full node of the baby blockchain should discover a set of faulty validators (with corresponding evidences of misbehaviours) whenever a light client attack is observed by the light client.
The following function captures this logic (please, see [Light client Attackers Isolation](https://github.com/tendermint/spec/blob/master/rust-spec/lightclient/attacks/isolate-attackers_002_reviewed.md#LCAI-FUNC-NONVALID1%5D) for more details):
```golang
func isolateMisbehavingProcesses(ev LightClientAttackEvidence) []Evidence {
      bc := blockchain[ev.chain]
      reference := bc[ev.conflictingBlock.Header.Height].Header
      ev_header := ev.conflictingBlock.Header

      ref_commit := bc[ev.conflictingBlock.Header.Height + 1].Header.LastCommit // + 1 !!
      ev_commit := ev.conflictingBlock.Commit

      if violatesTMValidity(reference, ev_header) {
          // lunatic light client attack
          signatories := Signers(ev.ConflictingBlock.Commit)
          bonded_vals := Addresses(bc[ev.CommonHeight].NextValidators)
          return intersection(signatories,bonded_vals)

      }
      // If this point is reached the validator sets in reference and ev_header are identical
      else if RoundOf(ref_commit) == RoundOf(ev_commit) {
          // equivocation light client attack
          return intersection(Signers(ref_commit),
          Signers(ev_commit))
    }
    else {
        // amnesia light client attack
        return IsolateAmnesiaAttacker(ev, bc)
    }
}
```

Moreover, we define a callback triggered at a correct full node of the baby blockchain once it receives an information about a light client attack:
```golang
// Triggered once a full node of the baby blockchain receives LightClientAttackEvidence
func lightClientAttackEvidenceSubmitted(ev LightClientAttackEvidence) {
  evidences := isolateMisbehavingProcesses(ev)
  submitLightClientAttackEvidence(evidences, parentBlockchainFullNodes)
}
```
- Expected precondition
  - `LightClientAttackEvidence` received
- Expected postcondition
  - Array of `Evidence` submitted to each full node in `parentBlockchainFullNodes`
- Error condition
  - If the precondition is violated

Lastly, we define a callback triggered at a correct full node of the parent blockchain once it receives an array of evidences (`Evidence`):
```golang
// Triggered once a full node of the parent blockchain receives an array of Evidence from a full node of the baby blockchain
func evidenceOfMisbehavioursSubmitted(evidences []Evidence) {
  stakingModule.processEvidences(evidences)
}
```
- Expected precondition
  - Array of `Evidence` received
- Expected postcondition
  - `stakingModule.processEvidences()` invoked
- Error condition
  - If the precondition is violated

We now just present the preconditions and postconditions of `stakingModule.processEvidences()` function:
```golang
func stakingModule.processEvidences(evidences []Evidence)
```
- Expected precondition
  - Array of `Evidence` received by a full node
- Expected postcondition
  - The input array of `Evidence` is eventually committed on the blockchain
- Error condition
  - If the precondition is violated

![image](./images/evidence_handling_1.PNG)

#### Committed Evidence Scenario

We now consider the protocol that is executed once an evidence of a misbehaviour is committed on the baby blockchain.
The evidence is simply transferred to the parent blockchain via IBC.
<br> **Remark:** We do not define all the functions and callbacks needed for an IBC communication to be established between two blockchains.
For more details, please see: [Validator Change Protocol](https://github.com/informalsystems/cross-chain-validation/blob/main/spec/valset-update-protocol.md).

The following callback is triggered once there exists an evidence of a misbehaviour committed on the baby blockchain:
```golang
// Invoked once there is an evidence of a misbehaviour committed on the baby blockchain
func evidenceCommitted(evidence Evidence) {
  // create the CommittedEvidencePacket
  CommittedEvidencePacket packet = CommittedEvidencePacket{evidence}

  // obtain the destination port of the parent blockchain
  destPort = getPort(parentChainId)

  // send the packet
  handler.sendPacket(packet, destPort)
}
```
- Expected precondition
  - Begin-Block method is executed for the block `b`
  - Evidence `evidence` is committed in `b`
- Expected postcondition
  - Packet containing information about `evidence` is created
- Error condition
  - If the precondition is violated

Moreover, the function below is triggered once a CommittedEvidencePacket is received on the parent blockchain:
```golang
// Executed at the parent blockchain to handle a delivery of the IBC packet; in this case it is exclusively a CommittedEvidencePacket
func onRecvPacket(packet: Packet) {
  // the packet is of CommittedEvidencePacket type
  assert(packet.type = CommittedEvidencePacket)

  // inform the staking module of the new evidence
  stakingModule.submitEvidence(evidence)

  // construct the default acknowledgment
  ack = defaultAck(CommittedEvidencePacket)
  return ack
}
```
- Expected precondition
  - The `CommittedEvidencePacket` is sent to the parent blockchain previously
  - The received packet is of the `CommittedEvidencePacket` type
- Expected postcondition
  - The evidence from the received packet is submitted to the staking module
  - The default acknowledgment is created
- Error condition
  - If the precondition is violated

Lastly, we describe the `submitEvidence()` function of the staking module of the parent blockchain that is responsible for "punishing" the misbehaving validator:
```golang
func stakingModule.submitEvidence(evidence Evidence)
```
- Expected precondition
  - `onRecvPacket` function invoked because of the reception of a packet of the `CommittedEvidencePacket` type
- Expected postcondition
  - Validator from the `CommittedEvidencePacket` is slashed
- Error condition
  - If the precondition is violated

Note the difference between `stakingModule.submitEvidence()` and `stakingModule.processEvidences()` functions.
Namely, once the `stakingModule.submitEvidence()` function is invoked, the evidence is already committed on the parent blockchain (because of IBC) and the slashing could take place.
<br>However, `stakingModule.produceEvidences()` is invoked while the evidence(s) is still not committed on the parent blockchain.
Therefore, this function is responsible for ensuring that the evidence(s) are eventually committed and only then the slashing takes place.

![image](./images/evidence_handling_2.PNG)
