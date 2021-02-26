# Initialization

## Introduction

This document discusses how the initialization of the baby blockchain occurs.
Namely, we consider the parent blockchain that is already operating and we describe how validators of the parent blockchain "lend" their services to the newly created baby blockchain.

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

## Validator Operator Viewpoint

A operator of a validator participates in a social consensus in order to validate the baby blockchain.
The social consensus process leads to a creation of the genesis file of the baby blockchain.
Roughly speaking, the validator operator "uses" the genesis file in two ways:
- It starts the validator for the baby blockchain.
- It uses the genesis file in order to issue a transaction to the parent blockchain specifying that it is indeed willing to participate as a validator on the baby blockchain (in order to fulfil the cross-chain validation concept).



## Definitions

Since the initial validators of the baby blockchain are bonded and slashable on the parent blockchain, the baby blockchain is not *safe* until its initial validators are bonded on the parent blockchain.
Thus, we specify a special IBC packet of type START_BABY_BLOCKCHAIN sent by the parent to the baby blockchain to signalize that the initial validators of the baby blockchain are bonded.
In other words, the baby blockchain starts to "operate" once the START_BABY_BLOCKCHAIN packet is received.
Importantly, nothing prevents the baby blockchain from producing blocks even before the START_BABY_BLOCKCHAIN packet is received.
However, the produced transaction **should not be** trusted since the blockchain was not secured at times of producing the transactions.

If the START_BABY_BLOCKCHAIN transaction is received by the baby blockchain, we say that the baby blockchain is *secured*.
Otherwise, the baby blockchain is not secured.
Hence, we aim to satisfy the following property:
- *Liveness:* If the baby and parent blockchain are not censored and the relayer works correctly, then the baby blockchain eventually becomes secured.

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
// invoked once the genesis file transaction of all validators of the baby // blockchain is committed on the parent blockchain
func GenesisFileTransactionSigned (
  ts: GenesisFileTransaction[]) {
  // initialize the staking module for the baby
  stakingModule.initBabyModule(ts[0].genesisFile.chainId)

  // freeze the stake of all initial validators of the baby blockchain
  stakingModule.freezeStake(1) // 1 is the sequence number of the validator set change; see "Technical Specification"

  // initialize the channel creation; see "Technical Specification"
  IBC.initChannel(ts[0].genesisFile.chainId)
}
```

- Expected precondition
  - The genesis file of the blockchain with the *ts.genesisFile.chainId* identifier is created
  - All validators specified in *ts.genesisFile* signed the *ts* transaction
- Expected postcondition
  - Stake of each initial validator is frozen and associated with the sequence number 1
  - The empty StartBabyBlockchainPacket is created
- Error condition
  - If the precondition is violated

```golang
// executed at the baby blockchain to handle the delivery of an IBC packet
func onRecvPacket (
  packet: Packet) {
  // the packet is of StartBabyBlockchainPacket type
  assert(packet.type = StartBabyBlockchainPacket)

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
