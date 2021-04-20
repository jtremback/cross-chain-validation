--------------------------- MODULE MC -----------------------------

CONSTANT 
    ParentValidators,  \* set of validatorIDs of validators at the parent
    ValidatorSetSequence \* sequence of length MaxChangeValidatorSeqNum, 
                            \* storing validator sets for each sequence numbe

VARIABLES 
    \* parent variables
    parentNextSeqNum, \* a sequence number of the next set of parent validators 
                    \* to be processed as validators of the baby, Int 
    parentUnfrozenSeqNums, \* set of sequence numbers, which are smaller than parentNextSeqNum,
                            \* identifying validator sets whose stake is unfrozen, {Int}
    \* baby variables
    babyValidatorSet, \* validator set of the baby blockchain, ValidatorIDs
    babySeqNum, \* sequence number of the last change validator set demand, Int
    babyUnbonding, \* set of sequence numbers identifying validator sets that are currently unbonding, {Int}
    babyValSetChanges, \* set of sequence numbers of validator set change demands, {Int}
    babyLastUnbondedSeqNum, \* sequence number of the last validator set that unbonded on the baby blockchain, Int
    \* shared variables
    packetCommitments, \* a set of packet commitments for each chain, [Chains -> Packets]
    haltProtocol, \* a flag that stores whether the protocol halted due to a timeout and closure of ordered channels, BOOL
    \* events simulating a relayer
    parentPendingEvents, \* pending events of the parent blockchain, Seq(Events)
    babyPendingEvents, \* pending events of the baby blockchain, Seq(Events)
    upcomingEvent \* current event to be processed, Events


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
