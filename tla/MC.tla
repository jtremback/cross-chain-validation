--------------------------- MODULE MC -----------------------------

CONSTANT 
    \* @type: Set(Str);
    ParentValidators,  \* set of validatorIDs of validators at the parent
    \* @type: Seq(Set(Str));
    ValidatorSetSequence \* sequence of length MaxChangeValidatorSeqNum, 
                            \* storing validator sets for each sequence numbe

VARIABLES 
    \* parent variables
    \* @type: Int;
    parentNextSeqNum, \* a sequence number of the next set of parent validators 
                      \* to be processed as validators of the baby, Int 
    \* @type: Set(Int);
    parentUnfrozenSeqNums, \* set of sequence numbers, which are smaller than parentNextSeqNum,
                           \* identifying validator sets whose stake is unfrozen, {Int}
    \* baby variables
    \* @type: Set(Str);
    babyValidatorSet, \* validator set of the baby blockchain, ValidatorIDs
    \* @type: Int;
    babySeqNum, \* sequence number of the last change validator set demand, Int
    \* @type: Set(Int);
    babyUnbonding, \* set of sequence numbers identifying validator sets that are currently unbonding, {Int}
    \* @type: Set(Int);
    babyValSetChanges, \* set of sequence numbers of validator set change demands, {Int}
    \* @type: Int;
    babyLastUnbondedSeqNum, \* sequence number of the last validator set that unbonded on the baby blockchain, Int
    \* shared variables
    (* @typeAlias: PACKETDATA = 
        [
            type: Str,
            validatorSet: Set(Str),
            seqNum: Int
        ];
    *)
    (* @typeAlias: PACKET = 
        [
            srcChannel: Str,
            dstChannel: Str,
            data: PACKETDATA
        ];
    *)
    \* @type: Str -> Set(PACKET);
    packetCommitments, \* a set of packet commitments for each chain, [Chains -> Packets]
    \* @type: Bool;
    haltProtocol, \* a flag that stores whether the protocol halted due to a timeout and closure of ordered channels, BOOL
    \* events simulating a relayer
    (* @typeAlias: EVENT =
        [
            packet: PACKET,
            function: Str,
            chain: Str
        ];
    *)
    \* @type: Seq(EVENT);
    parentPendingEvents, \* pending events of the parent blockchain, Seq(Events)
    \* @type: Seq(EVENT);
    babyPendingEvents, \* pending events of the baby blockchain, Seq(Events)
    \* @type: EVENT;
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
