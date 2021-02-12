--------------------------- MODULE MC -----------------------------

CONSTANT ParentValidators,  \* set of validatorIDs of validators at the parent
         ValidatorSetSequence \* sequence of length MaxChangeValidatorSeqNum, 
                            \* storing validator sets for each sequence numbe

VARIABLES nextParentSeqNum, \* a sequence number of the next set of parent validators 
                            \* to be processed as validators of the baby, Int 
          unfrozenSeqNums, \* set of sequence numbers identifying validator sets 
                           \* whose stake is unfrozen, {Int}
          packetCommitments, \* a set of packet commitments for each chain [Chains -> Packets]
          packetAcknowledgements, \* a set of packet acknowledgements for each chain [Chains -> Packets]
          babyUnbonding, \* set of validators that are currently unbonding {ValidatorID}
          babyValidatorSet, \* validator set of the baby blockchain
          babySeqNum, \* sequence number of the last change validator set demand
          babyValSetChanges, \* queue of validator set change demands, Seq(Validators \X SeqNums)
          pendingEvents, 
          upcomingEvent


INSTANCE CrossChainValidation_draft_001 WITH 
    ChannelIDs <- {"channelParent", "channelBaby"}, \* set of channelIDs
    ChainIDs <- {"parent", "baby"}, \* set of chainIDs
    ValidatorIDs <- {"v1", "v2"}, \* set of validatorIDs
    MaxChangeValidatorSeqNum <- 1 \* integer

\* run Apalache with --cinit=ConstInit
ConstInit == 
    /\ ValidatorSetSequence \in [SeqNums -> SUBSET (AllValidators)]
    /\ ParentValidators \subseteq AllValidators 
===================================================================
