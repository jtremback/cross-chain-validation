# Initialization - Draft for Discussion

## Introduction

This document discusses how the initialization of the baby blockchain occurs.
Namely, we consider the parent blockchain that is already operating and we describe how validators of the parent blockchain "lend" their services to the newly created baby blockchain.

## Problem Statement

We assume that the baby blockchain maintains the "initialization" variable that is set to either true or false.

**Baby Blockchain Assumption:** If *initialization = true*, the application of the baby blockchain does not execute (i.e., trust) any (non-channel-establishing) transactions.

Moreover, we assume that the parent blockchain maintains "allowValidatorSetChanges" variable that is set to either true or false.

**Parent Blockchain Assumption:** If *allowValidatorSetChanges = false*, the parent blockchain does not require any validator set changes to the validator set of the baby blockchain.

We now present the set of properties we aim to ensure:
- Baby Blockchain Safety: If *initialization = false* and both blockchains perform valid transitions, then some validators of the baby blockchain are bonded on the parent blockchain.
- Baby Blockchain Liveness: If both blockchains perform valid transitions, the relayer works correctly, no blockchain is censored and 2/3 correct validators signed the genesis file, eventually *liveness = false* at the baby blockchain.

- Parent Blockchain Safety: If *allowValidatorSetChanges = true* and both blockchains perform valid transitions, then *initialization = false* at the baby blockchain.
- Parent Blockchain Liveness: If both blockchains perform valid transitions, the relayer works correctly, no blockchain is censored and 2/3 correct validators signed the genesis file, eventually *allowValidatorSetChanges = true* at the parent blockchain.

Lastly, we discuss the invariants we ensure:
- Let *V* be a validator set of the baby blockchain and let *initialization = true*.
Then, *V* is the initial validator set of the baby blockchain.    

## Validator Operator Viewpoint

A operator of a validator participates in a social consensus in order to validate the baby blockchain.
The social consensus process leads to a creation of the genesis file of the baby blockchain.
Roughly speaking, the validator operator "uses" the genesis file in two ways:
- It starts the validator for the baby blockchain.
- It uses the genesis file in order to issue a transaction to the parent blockchain specifying that it is indeed willing to participate as a validator on the baby blockchain (in order to fulfil the cross-chain validation concept).

## Intuition

In this section, we briefly introduce the idea behind the initialization protocol.
We properly describe the protocol in the rest of the document.

1. Operators of validators that are interested in securing the baby blockchain participate in a social consensus which results in the genesis file of the baby blockchain.
2. a) Once 2/3 of baby blockchain validators are online, the blockchain may start producing blocks.
However, correct validators do not execute any transaction except ones that aim to establish connection between the parent and the baby blockchain (as we explain the rest of the document).

   b) In parallel, a validator of the baby blockchain issues the genesis file of the baby blockchain as a transaction to the parent blockchain.
   Importantly, the validator specifies in this transaction which public key it will use on the baby blockchain.
   Note that the transaction is signed (with the private key used on the parent blockchain) by the validator.

3. Once all validators of the baby blockchain have issued the aforementioned transaction, the parent blockchain (1) initializes the staking module for the baby blockchain, and (2) initiates the establishment of a connection between itself and the baby blockchain.
Once these two tasks have been successfully executed, the process sends a packet to the baby blockchain that signalizes that the connection has been made.
Once the acknowledgment for the packet is received, the parent blockchain can start manipulating the validator set of the baby blockchain.

## Function Definitions

```golang
// genesis file structure; specifies the initial validator set of the blockchain
struct GenesisFile {
  chainId: ChainId,
  initialValidatorSet: Validator[]
}
```

```golang
// genesis file transaction; specifies the public key of each validator
struct GenesisFileTransaction {
  genesisFile: GenesisFile,
  validatorPublicKey: ValidatorPK[]
}
```

```golang
// IBC packet sent by the parent blockchain to the baby blockchain
// to signalize that the initial validators are bonded;
// the baby blockchain is secured once this packet is received
struct StartBabyBlockchainPacket {}
```

### Parent Blockchain

```golang
// invoked once the genesis file transaction of all validators of the baby
// blockchain is committed on the parent blockchain
func GenesisFileTransactionSigned (
  ts: GenesisFileTransaction[]) {
  // initialize the staking module for the baby
  stakingModule.initBabyModule(ts[0].genesisFile.chainId)

  // freeze the stake of all initial validators of the baby blockchain
  stakingModule.freezeStake(1) // 1 is the sequence number of the validator set change; see "Technical Specification"

  // validator set changes not allowed yet
  allowValidatorSetChanges[ts[0].genesisFile.chainId] = false

  // initialize the channel creation; see "Technical Specification"
  IBC.initChannel(ts[0].genesisFile.chainId)
}
```

- Expected precondition
  - The genesis file of the blockchain with the *ts.genesisFile.chainId* identifier is created
  - All validators specified in the genesis file of the baby blockchain issued the genesis file transaction
- Expected postcondition
  - Stake of each initial validator is frozen and associated with the sequence number 1
  - The channel creation is initiated
- Error condition
  - If the precondition is violated

```golang
// invoked once the channel is successfully established; see "Technical Specification"
func onChanOpenConfirm () {
  // create the empty StartBabyBlockchainPacket packet
  packet = StartBabyBlockchainPacket{}

  // obtain the destination port of the baby blockchain
  destPort = getPort(parentChainId)

  // send the packet
  handler.sendPacket(Packet{timeoutHeight, timeoutTimestamp, destPort, destChannel, sourcePort, sourceChannel, packet}, getCapability("port"))
}
```

```golang
// executed at the parent blockchain to handle the delivery of an IBC acknowledgment
func onAcknowledgePacket (
  packet: Packet,
  acknowledgement: bytes) {
  // the packet is of StartBabyBlockchainPacket type
  assert(packet.type = StartBabyBlockchainPacket)

  // validator set changes allowed
  allowValidatorSetChanges[packet.chainId] = true
}
```

- Expected precondition
  - The *packet* packet is sent to the parent blockchain before the packet is received
  - The packet is of the *StartBabyBlockchainPacketAck* type
- Expected postcondition
  - Validator set changes for the baby blockchain are allowed
- Error condition
  - If the precondition is violated  

```golang
// executed at the parent blockchain to handle the timeout of the IBC packet
func onTimeoutPacket (
  packet: Packet) {
  // the packet is of StartBabyBlockchainPacket type
  assert(packet.type = StartBabyBlockchainPacket)

  // TODO figure out what to do in this case
}
```

- Expected precondition
  - The *packet* packet sent to the parent blockchain timeouts
  - The packet is of the *StartBabyBlockchainPacketAck* type
- Expected postcondition
  - TODO
- Error condition
  - If the precondition is violated  

### Baby Blockchain

```golang
// executed once the validator of the baby blockchain starts executing
func init () {
  // set the current mode to the "Initialization" mode
  initialization = true
}
```

- Expected precondition
  - The validator of the baby blockchain started executing
- Expected postcondition
  - Current mode set to the "Initialization" mode
- Error condition
  - If the precondition is violated

**Remark:** The "Initialization" mode simply represents the fact that the validator should not execute (i.e., trust) any (non-channel-establishing) transactions while in this mode.

```golang
// executed at the baby blockchain to handle the delivery of an IBC packet
func onRecvPacket (
  packet: Packet) {
  // the packet is of StartBabyBlockchainPacket type
  assert(packet.type = StartBabyBlockchainPacket)

  // remove the "Initialization" mode
  initialization = false

  // the baby blockchain is now secured
  // construct the default acknowledgment
  ack = defaultAck(StartBabyBlockchainPacket)
  return ack
}
```

- Expected precondition
  - The *packet* packet is sent to the baby blockchain before the packet is received
  - The packet is of the *StartBabyBlockchainPacket* type
- Expected postcondition
  - The default acknowledgment is created
- Error condition
  - If the precondition is violated

## Correctness Arguments

The baby blockchain safety property is ensured because of the fact that the parent blockchain has bonded validators of the baby blockchain at the moment of sending the *StartBabyBlockchainPacket* packet.
The baby blockchain liveness property is ensured since eventually the *StartBabyBlockchainPacket* packet is indeed received by the baby blockchain.
The parent blockchain safety holds since the *allowValidatorSetChanges* variable is modified at the moment of receiving the *StartBabyBlockchainPacket* acknowledgment.
Lastly, the parent blockchain liveness holds since the *StartBabyBlockchainPacket* acknowledgment is eventually received by the parent blockchain.
