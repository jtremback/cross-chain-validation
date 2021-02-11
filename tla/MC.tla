--------------------------- MODULE MC -----------------------------

CONSTANT ParentValidators,  \* set of validatorIDs of validators at the parent
         ChangeValSetDemand \* sequence of length MaxChangeValidatorSeqNum, 
                            \* storing validator sets for each sequence numbe

VARIABLES parentFrozenStake, \* a mapping from sequence numbers to set of validators whose stake is frozen
          packetCommitments, \* a set of packet commitments for each chain [Chains -> Packets]
          packetReceipts, \* a set of packet receipts for each chain [Chains -> Packets]
          packetAcknowledgements, \* a set of packet acknowledgements for each chain [Chains -> Packets]
          babyUnbonding, \* set of validators that are currently unbonding
          babyValidatorSet, \* validator set of the baby blockchain
          babySeqNum, \* sequence number of the last change validator set demand
          babyValSetChanges,
          pendingStakingModuleEvents,
          pendingEvents, 
          upcomingEvent


INSTANCE CrossChainValidation_draft_001 WITH 
    PortIDs <- {"portParent", "portBaby"}, \* set of portIDs
    ChannelIDs <- {"channelParent", "channelBaby"}, \* set of channelIDs
    Chains <- {"parent", "baby"}, \* set of chainIDs
    Validators <- {"v1", "v2"}, \* set of validatorIDs
    MaxChangeValidatorSeqNum <- 1 \* integer

\* run Apalache with --cinit=ConstInit
ConstInit == 
    /\ ChangeValSetDemand \in [ChangeValidatorSeqNums -> SUBSET (AllValidators)]
    /\ ParentValidators \subseteq AllValidators
===================================================================
