------------- MODULE CrossChainValidation_draft_001 ---------------

EXTENDS Integers, FiniteSets, Sequences

CONSTANTS ChannelIDs, \* set of channelIDs
          ChainIDs, \* set of chainIDs
          ValidatorIDs, \* set of validatorIDs
          ParentValidators, \* set of validatorIDs of validators at the parent
          MaxChangeValidatorSeqNum, \* integer
          ValidatorSetSequence \* sequence of length MaxChangeValidatorSeqNum, 
                               \* storing validator sets for each sequence number

VARIABLES nextParentSeqNum, \* a sequence number of the next set of parent validators 
                            \* to be processed as validators of the baby, Int 
          unfrozenSeqNums, \* set of sequence numbers identifying validator sets 
                           \* whose stake is unfrozen, {Int}
          packetCommitments, \* a set of packet commitments for each chain, [Chains -> Packets]
        \* TODO: do we need to care about receipts, acknowledgements in chain store?
        \*   packetReceipts, \* a set of packet receipts for each chain, [Chains -> Packets]
        \*   packetAcknowledgements, \* a set of packet acknowledgements for each chain, [Chains -> Packets]
          babyUnbonding, \* set of sequence numbers identifying validator sets that are currently unbonding
          babyValidatorSet, \* validator set of the baby blockchain
          babySeqNum, \* sequence number of the last change validator set demand
          babyValSetChanges, \* set of validator set change demands, {Validators \X SeqNums}
          pendingEvents, 
          upcomingEvent

(*************************** Definitions **************************)
SeqNums == 1 .. MaxChangeValidatorSeqNum
\* AllValidators are nodes that have an account on the parent chain
AllValidators == ValidatorIDs

NullChainID == "none"
NullEvent == "none"

Max(S) == CHOOSE x \in S : \A y \in S : x >= y 

CrossChainValidationPacketData == [
    type : {"ChangeValidatorSet"},
    validatorSet : SUBSET (AllValidators),
    seqNum : SeqNums
] \union [
    type : {"UnbondingOver"},
    seqNums : SUBSET (SeqNums)
]

Packets == [
    srcChannel : ChannelIDs,
    dstChannel : ChannelIDs,
    data : CrossChainValidationPacketData
]          

StakingModuleFunctions ==
    {"FreezeStake", "UnfreezeStake", "UnfreezeSingleStake", "StartUnbonding", "FinishUnbonding"}

ParentFunctions ==
    {"ChangeValidatorSet", "OnRecvPacket", "OnTimeoutPacket"}
        
BabyFunctions ==
    {"EndBlock", "OnRecvPacket", "OnTimeoutPacket"}

Functions == 
    StakingModuleFunctions \union ParentFunctions \union BabyFunctions

Events == [
    packet : Packets,
    function : Functions,
    chain : ChainIDs
]

InitialStakingModuleEvents == {
    [
        function |-> "FreezeStake",
        chain |-> "parent",
        valSet |-> ValidatorSetSequence[seq],
        seqNum |-> seq 
    ] : seq \in SeqNums
}
    
(**************************** Operators ***************************)
    
GetReceiverChain(packet) ==
    IF packet.dstChannelID = "parentChannel"
    THEN "parent"
    ELSE IF packet.dstChannelID = "babyChannel"
         THEN "baby"
         ELSE NullChainID

CreateChangeValSetPacket(chain, valSet, seqNum) ==
    LET packetData == [
        type |-> "ChangeValidatorSet",
        validatorSet |-> valSet,
        seqNum |-> seqNum
    ] IN 
    LET packet == [
        srcChannel |-> "parentChannel",
        dstChannel |-> "babyChannel",
        data |-> packetData
    ] IN 
    LET event == [
        packet |-> packet,
        function |-> "ChangeValidatorSet",
        chain |-> chain
    ] IN

    \* add ChangeValidatorSet event for parent chain
    pendingEvents' = pendingEvents \union {event}

CreateAndSendUnbondingOverPackets(chain, seqNums) ==
    LET packetData == [
        type : {"UnbondingOver"},
        seqNum : seqNums
    ] IN 
    LET packets == [
        srcChannel : {"babyChannel"},
        dstChannel : {"parentChannel"},
        data : packetData
    ] IN 
    LET events == [
        packet : packets,
        function : {"OnPacketRecv"},
        chain : {"parent"}
    ] IN

    \* send packet
    /\ packetCommitments' = [packetCommitments EXCEPT ![chain] = @ \union packets]
    \* add OnPacketRecv events for receiver chain
    /\ pendingEvents' = pendingEvents \union events

SendChangeValSetPacket(chain, packet) ==
    LET event == [
        packet |-> packet,
        function |-> "OnPacketRecv",
        chain |-> GetReceiverChain(packet)
    ] IN 

    \* send packet
    /\ packetCommitments' = [packetCommitments EXCEPT ![chain] = @ \union {packet}]
    \* add OnPacketRecv event for receiver chain
    /\ pendingEvents' = pendingEvents \union {event} 

(* Staking module *)
UnfreezeStake(chain, seqNum) ==
    /\ chain = "parent"
    /\ unfrozenSeqNums' = unfrozenSeqNums \union 1..seqNum
    
UnfreezeSingleStake(chain, seqNum) ==
    /\ chain = "parent"
    /\ unfrozenSeqNums' = unfrozenSeqNums \union {seqNum}
    
StartAndFinishUnbonding(newSeqNum, oldSeqNums) ==
    \* the sequence number of the baby blockchain is < newSeqNum
    /\ babySeqNum < newSeqNum
    \* the sequence numbers for which unbonding is finishing have been unbonding
    /\ oldSeqNums \subseteq babyUnbonding
    \* remove oldSeqNums from unbonding, add babySeqNum
    /\ babyUnbonding' = (babyUnbonding \ oldSeqNums) \union {babySeqNum}
    /\ CreateAndSendUnbondingOverPackets("baby", oldSeqNums)


AddValidatorSetChange(chain, packet) ==
    /\ chain = "baby"
    /\ babyValSetChanges' = babyValSetChanges \union
                                {<<packet.data.validatorSet, packet.data.seqNum>>}

DefaultAck(chain, packet) ==
    LET receiverChain == GetReceiverChain(packet) IN 
    LET event == [
        packet |-> packet,
        function |-> "OnPacketAck",
        chain |-> receiverChain
    ] IN 
    
    \* TODO: do we need to care about acknowledgements in chain store?
    \* /\ packetAcknowledgements' = [packetAcknowledgements EXCEPT 
    \*                                 ![chain] = @ \union {packet}]
    /\ pendingEvents' = pendingEvents \union {event}
        
(***************************** Actions ****************************)

\* no preconditions specified since the function is not specified 
FreezeStake ==
    /\ upcomingEvent.function = "FreezeStake"
    /\ nextParentSeqNum <= MaxChangeValidatorSeqNum
    \* create a packet 
    /\ CreateChangeValSetPacket(upcomingEvent.chain, upcomingEvent.valSet, upcomingEvent.seqNum)
    \* the validators whose stake is frozen on the parent chain are in the set:
    \* UNION {ValidatorSetSequence[i] : i \in 1..nextParentSeqNum \ unfrozenSeqNums}
    \* increase the sequence number of the next validator set change to be processed
    /\ nextParentSeqNum' = nextParentSeqNum + 1
    /\ UNCHANGED <<>> \* TODO 

ChangeValidatorSet ==
    /\ upcomingEvent.function = "ChangeValidatorSet"
    /\ upcomingEvent.packet.data.type = "ChangeValidatorSet"
    \* there exists a blockchain that is a receiver of this packet
    /\ GetReceiverChain(upcomingEvent.packet) \in ChainIDs
    \* all validators are validators at the parent blockchain
    (*  
        English spec note: A better precondition would be:
         - all validators have an account at the parent blockchain
    *)
    /\ upcomingEvent.packet.data.validatorSet \subseteq ParentValidators
    \* the stake of each validator is frozen and associated with this demand
    /\ upcomingEvent.packet.data.seqNum \notin unfrozenSeqNums
    /\ upcomingEvent.packet.data.validatorSet \subseteq 
            ValidatorSetSequence[upcomingEvent.packet.data.seqNum]
    \* send packet, i.e., write packet to data store
    /\ SendChangeValSetPacket(upcomingEvent.chain, upcomingEvent.packet)
    /\ UNCHANGED <<>> \* TODO 

(* Note on English spec: when the UnbondingOver packet is introduced, its data field
is called seqNums, which leads to the interpretation that this is a set of sequence 
numbers for which the unbonding has finished. However, in the function endBlock,
where UnbondingOver packets are created, the data field of the packet seems to be 
a single sequence number seqNum, and that on the parent side, the stake of all 
validators that are part of validator sets at sequence numbers <= seqNum is unfrozen.
How can we be sure that indeed all sequence numbers <= seqNum should be unfrozen? 
Wouldn't it be more efficient to send one UnbondingOver packet with a set of 
sequence numbers, rather than multiple UnbondingOver packets with a signle sequence number? *)
OnPacketRecvParent ==
    /\ upcomingEvent.function = "OnPacketRecv"
    \* the packet is of type UnbondingOver
    /\ upcomingEvent.packet.data.type = "UnbondingOver"
    \* the ChangeValidatorSet packet is sent to the baby blockchain before 
    \* this packet is received
    /\ \E packet \in packetCommitments[upcomingEvent.chain] :
            packet.data.seqNum = upcomingEvent.packet.data.seqNum
    \* unfreeze stake
    /\ UnfreezeStake(upcomingEvent.chain, upcomingEvent.packet.data.seqNum)
    \* create default acknowledegement
    /\ DefaultAck(upcomingEvent.chain, upcomingEvent.packet)
    /\ UNCHANGED <<>> \* TODO 

OnPacketRecvBaby ==
    /\ upcomingEvent.function = "OnPacketRecv"
    \* the packet is of type ChangeValidatorSet 
    /\ upcomingEvent.packet.data.type = "ChangeValidatorSet"
    \* inform the staking module of the new validator set change demand
    /\ AddValidatorSetChange(upcomingEvent.chain, upcomingEvent.packet)
    \* create default acknowledegement
    /\ DefaultAck(upcomingEvent.chain, upcomingEvent.packet)
    /\ UNCHANGED <<>> \* TODO 

OnPacketAck ==
    /\ upcomingEvent.function \in "OnPacketAck"
    /\ upcomingEvent.packet \in packetCommitments[upcomingEvent.chain]
    \* remove packet commitment on acknowledgement
    /\ packetCommitments' = [packetCommitments EXCEPT ![upcomingEvent.chain] = @ \ {upcomingEvent.packet}]
    /\ UNCHANGED <<>> \* TODO 

OnTimeoutPacketParent ==
    /\ upcomingEvent.packet.data.type = "ChangeValidatorSet"
    \* unfreeze stake of validators associated with the seqNum from the packet data
    /\ UnfreezeSingleStake(upcomingEvent.chain, upcomingEvent.packet.data.seqNum)
    \* ICS04: remove packet commitment 
    /\ packetCommitments' = [packetCommitments EXCEPT ![upcomingEvent.chain] = @ \ {upcomingEvent.packet}]
    \* TODO: other ICS04 packet-related actions on timeout?
    /\ UNCHANGED <<>> \* TODO 

OnTimeoutPacketBaby ==    
    /\ upcomingEvent.packet.data.type = "UnbondingOver"
    (*  
        English spec note: Here, the English spec says that a new 
        packet is sent again. However, based on ICS04, when a 
        timeout happens on an ordered channel, the channel is 
        closed. Thus, sending packets again on the same channel 
        would be impossible.
    *)
    \* TODO: specify correct on timeout handler
    \* ICS04: remove packet commitment 
    /\ packetCommitments' = [packetCommitments EXCEPT ![upcomingEvent.chain] = @ \ {upcomingEvent.packet}]
    \* TODO: other ICS04 packet-related actions on timeout?
    /\ UNCHANGED <<>> \* TODO 

(*  
    Engish spec note: The functions applyValidatorUpdate and finishUnbondingOVer
    called in the body of the function endBlock are not specified 
*)
ExecuteEndBlock ==
    LET newSeqNum == Max({vsc[2] : vsc \in babyValSetChanges}) IN
    /\ babyValidatorSet' = UNION {vsc[1] : vsc \in babyValSetChanges}     
    /\ babySeqNum' = newSeqNum
    \* finish unbonding for mature validator sets
    /\ \E matureSeqNums \in SUBSET SeqNums : 
        /\ StartAndFinishUnbonding(newSeqNum, matureSeqNums) 

Init ==
    /\ nextParentSeqNum = 1
    /\ unfrozenSeqNums = {}
    /\ packetCommitments = [chain \in ChainIDs |-> {}]
    /\ babyUnbonding = {}
    /\ babyValidatorSet \subseteq AllValidators
    /\ babySeqNum = 1
    /\ babyValSetChanges = {}
    /\ pendingEvents = {} 
    /\ upcomingEvent = NullEvent

\* TODO: sequence numbers in packets? ordered channels? 
Next ==
    \/ FreezeStake
    \/ \E event \in pendingEvents :         
        /\ upcomingEvent' = event
        /\ pendingEvents' = pendingEvents \ {event}
        /\ \/ /\ event.function = "ChangeValidatorSet"
              /\ event.chain = "parent"
              /\ ChangeValidatorSet
           \/ /\ event.function = "OnPacketRecv"
              /\ event.chain = "parent"
              /\ OnPacketRecvParent
           \/ /\ event.function = "OnPacketRecv"
              /\ event.chain = "baby"
              /\ OnPacketRecvBaby
           \/ /\ event.function = "OnPacketAck"
              /\ OnPacketAck
           \/ /\ event.chain = "parent"
              /\ OnTimeoutPacketParent
           \/ /\ event.chain = "baby"
              /\ OnTimeoutPacketBaby
    \/ ExecuteEndBlock


           \* TODO ...

===================================================================