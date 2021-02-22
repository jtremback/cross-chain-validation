# Initialization

## Introduction

This document discusses how the initialization of the baby blockchain occurs.
Namely, we consider the parent blockchain that is already operating and we describe how validators of the parent blockchain "lend" their services to the newly created baby blockchain.

## Definitions

Since the initial validators of the baby blockchain are bonded and slashable on the parent blockchain, the baby blockchain is not *safe* until its initial validators are bonded on the parent blockchain.
Thus, we specify a special IBC packet of type START_BABY_BLOCKCHAIN sent by the parent to the baby blockchain to signalize that the initial validators of the baby blockchain are bonded.
In other words, the baby blockchain starts to "operate" once the START_BABY_BLOCKCHAIN packet is received.
Importantly, nothing prevents the baby blockchain from producing blocks even before the START_BABY_BLOCKCHAIN packet is received.
However, the produced transaction **should not be** trusted since the blockchain was not secured at times of producing the transactions.

If the START_BABY_BLOCKCHAIN transaction is received by the baby blockchain, we say that the baby blockchain is *secured*.
Otherwise, the baby blockchain is not secured.7
Hence, we aim to satisfy the following property:
- *Liveness:* If the baby and parent blockchain are not censored and the relayer works correctly, then the baby blockchain eventually becomes secured.

## Concept

1. The genesis file of the baby blockchain is created and denoted by GF. Initial validators of the baby blockchain are specified in GF (like in the "single-blockchain" scenario).
2. Transaction TS that contains GF signed by all initial validators of the baby blockchain is committed on the parent blockchain.
Moreover, TS also associates each validator with the public key the validator uses on the baby blockchain.
3. Once the TS transaction is executed, the START_BABY_BLOCKCHAIN packet is sent from the parent to the baby blockchain.
4. Once the START_BABY_BLOCKCHAIN packet is received by the baby blockchain, the baby blockchain is secured.

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
// executed at the parent blockchain;
// IBC packet sent by the parent blockchain to the baby blockchain
// to signalize that the initial validators are bonded;
// the baby blockchain is secured once this packet is received
struct StartBabyBlockchainPacket {}
```

```golang
// invoked once the genesis file transaction is (1) signed by all initial validators of the blockchain specified in the transaction, and (2) committed on the parent blockchain
func GenesisFileTransactionSigned (
  ts: GenesisFileTransaction) {
  // freeze the stake of all initial validators of the baby blockchain
  stakingModule.freezeStake(1) // 1 is the sequence number of the validator set change; see "Technical Specification"

  // create the empty StartBabyBlockchainPacket
  StartBabyBlockchainPacket data = StartBabyBlockchainPacket{}

  // obtain the destination port of the baby blockchain
  destPort = getPort(ts.genesisFile.chainId)

  // send the packet
  handler.sendPacket(Packet{timeoutHeight, timeoutTimestamp, destPort, destChannel, sourcePort, sourceChannel, data}, getCapability("port"))  
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
