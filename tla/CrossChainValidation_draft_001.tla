------------- MODULE CrossChainValidation_draft_001 ---------------

EXTENDS Integers, FiniteSets, Sequences

CONSTANTS ChannelIDs, \* set of channelIDs
          ChainIDs, \* set of chainIDs
          ValidatorIDs, \* set of validatorIDs
          ParentValidators, \* set of validatorIDs of validators at the parent
          MaxChangeValidatorSeqNum, \* integer
          ValidatorSetSequence \* sequence of length MaxChangeValidatorSeqNum, 
                               \* storing validator sets for each sequence number

VARIABLES \* parent variables
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
          

(*************************** Definitions **************************)
SeqNums == 1 .. MaxChangeValidatorSeqNum
\* AllValidators are nodes that have an account on the parent chain
AllValidators == ValidatorIDs

NullChainID == "none"
NullEvent == "none"

vars == <<parentNextSeqNum, parentUnfrozenSeqNums,
          babyUnbonding, babyValidatorSet, babySeqNum, babyValSetChanges, babyLastUnbondedSeqNum,
          packetCommitments, haltProtocol,
          parentPendingEvents, babyPendingEvents, upcomingEvent>>

Max(S) == CHOOSE x \in S : \A y \in S : x >= y 

CrossChainValidationPacketData == [
    type : {"ChangeValidatorSet"},
    validatorSet : SUBSET (AllValidators),
    seqNum : SeqNums
] \union [
    type : {"UnbondingOver"},
    seqNum : SeqNums
]

Packets == [
    srcChannel : ChannelIDs,
    dstChannel : ChannelIDs,
    data : CrossChainValidationPacketData
]          

Functions == 
    {"ChangeValidatorSet", "OnRecvPacket"} 
    (*
        Uncomment if packet acknowledgements are added.
        \union {"OnPacketAck"}
    *)
        
Events == [
    packet : Packets,
    function : Functions,
    chain : ChainIDs
]
    
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
    parentPendingEvents' = Append(parentPendingEvents, event)

(*
    English spec note: Here we create an UnbondingOver packet for a 
    single (most) mature sequence number on the baby chain.
    This should be enough to unfreeze the stake of all 
    validators at the parent chain, which were part of validator
    set changes with smaller or equal sequence numbers.
*)
CreateAndSendUnbondingOverPackets(chain, seqNum) ==
    LET packetData == [
        type |-> "UnbondingOver",
        seqNum |-> seqNum
    ] IN 
    LET packet == [
        srcChannel |-> "babyChannel",
        dstChannel |-> "parentChannel",
        data |-> packetData
    ] IN 
    LET event == [
        packet |-> packet,
        function |-> "OnPacketRecv",
        chain |-> "parent"
    ] IN

    \* send packet
    /\ packetCommitments' = [packetCommitments EXCEPT ![chain] = @ \union {packet}]
    \* add OnPacketRecv event for parent chain
    /\ parentPendingEvents' = Append(parentPendingEvents, event)

SendChangeValSetPacket(chain, packet) ==
    LET event == [
        packet |-> packet,
        function |-> "OnPacketRecv",
        chain |-> GetReceiverChain(packet)
    ] IN 

    \* send packet
    /\ packetCommitments' = [packetCommitments EXCEPT ![chain] = @ \union {packet}]
    \* add OnPacketRecv event for baby chain
    /\ babyPendingEvents' = Append(babyPendingEvents, event)

(* Staking module *)
UnfreezeStake(chain, seqNum) ==
    /\ chain = "parent"
    /\ parentUnfrozenSeqNums' = parentUnfrozenSeqNums \union 1..seqNum
    
UnfreezeSingleStake(chain, seqNum) ==
    /\ chain = "parent"
    /\ parentUnfrozenSeqNums' = parentUnfrozenSeqNums \union {seqNum}
    
StartUnbonding(newSeqNum) == 
    \* the sequence number of the baby blockchain is < newSeqNum
    \/ /\ babySeqNum < newSeqNum
       \* add babySeqNum to babyUnbonding
       /\ babyUnbonding' = babyUnbonding \union {babySeqNum}
    \/ UNCHANGED babyUnbonding \* TODO

FinishUnbonding(matureSeqNum) ==
    \* the sequence numbers for which unbonding is finishing have been unbonding
    \/ /\ matureSeqNum \in babyUnbonding
       \* send UnbondingOverPackets
       /\ CreateAndSendUnbondingOverPackets("baby", matureSeqNum)
       /\ babyLastUnbondedSeqNum' = matureSeqNum
    \/ UNCHANGED babyLastUnbondedSeqNum \* TODO 


AddValidatorSetChange(chain, packet) ==
    /\ chain = "baby"
    \* this is an abstraction of the English spec -- 
    \* we only store the sequence number of the validator set change, 
    \* as we already have the validator set stored in the constant ValidatorSetSequence
    /\ babyValSetChanges' = babyValSetChanges \union {packet.data.seqNum}

(*  
    Engish spec note: Since applyValidatorUpdate is not specified in the 
    English spec, at this point, we assume that it returns the identity.
*)                                    
ApplyValidatorUpdate(valSetChanges) ==
    \* For now, we assume this operator returns the current value of the 
    \* baby validator set and sequence number
    \* TODO: This operator should be updated once the logic of applyValidatorUpdate
    \* is discussed.
    [valSet |-> babyValidatorSet, seqNum |-> babySeqNum]

(*
    English spec note: This function is not specified, hence we 
    omit creating acknowledgements for the purpose of this TLA spec.
    In case acknowledgements are necessary, the commented code below 
    captures creating a packet acknowledgement.
*)
DefaultAck(chain, packet) ==
    TRUE
    (*
    Uncomment if packet acknowledgements are added. 

    LET receiverChain == GetReceiverChain(packet) IN 
    LET event == [
        packet |-> packet,
        function |-> "OnPacketAck",
        chain |-> receiverChain
    ] IN 
    
    \/ /\ receiverChain = "parent"
       /\ parentPendingEvents' = parentPendingEvents \union {event} 
    \/ /\ receiverChain = "baby"
       /\ babyPendingEvents' = babyPendingEvents \union {event}
    *)
        
(***************************** Actions ****************************)

\* no preconditions specified since the function is not specified 
StartValSetUpdateParent ==
    \* enabled if the next validator sequence number does not exceed the maximum
    /\ parentNextSeqNum <= MaxChangeValidatorSeqNum
    \* create a packet 
    /\ CreateChangeValSetPacket("parent", ValidatorSetSequence[parentNextSeqNum], parentNextSeqNum)
    \* the validators whose stake is frozen on the parent chain are in the set:
    \* UNION {ValidatorSetSequence[i] : i \in 1..nextParentSeqNum \ unfrozenSeqNums}
    \* increase the sequence number of the next validator set change to be processed
    /\ parentNextSeqNum' = parentNextSeqNum + 1
    /\ UNCHANGED <<>> \* TODO 

ChangeValidatorSetParent ==
    /\ upcomingEvent.function = "ChangeValidatorSet"
    /\ upcomingEvent.packet.data.type = "ChangeValidatorSet"
    \* there exists a blockchain that is a receiver of this packet
    /\ GetReceiverChain(upcomingEvent.packet) \in ChainIDs
    
    (*  
        English spec note: The expected preconditions of ChangeValidatorSet 
        (formalized in TLA+ below)
        mix environment assumptions that need to be ensured by the staking 
        module, with conditions that need to be checked (eg. babyChainID exists)

    \* all validators are validators at the parent blockchain
    \* Note: A better precondition would be:
         - all validators have an account at the parent blockchain
    /\ upcomingEvent.packet.data.validatorSet \subseteq ParentValidators
    \* the stake of each validator is frozen and associated with this demand
    /\ upcomingEvent.packet.data.seqNum \notin unfrozenSeqNums
    /\ upcomingEvent.packet.data.validatorSet =
            ValidatorSetSequence[upcomingEvent.packet.data.seqNum]
    *)

    \* send packet, i.e., write packet to data store
    /\ SendChangeValSetPacket(upcomingEvent.chain, upcomingEvent.packet)
    /\ UNCHANGED <<>> \* TODO 

(* English spec note: when the UnbondingOver packet is introduced, its data field
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

(*
    English spec note: This function is not specified, hence we 
    omit acknowledging packets for the purpose of this TLA spec.
    In case OnPacketAck necessary, the code below captures 
    acknowledging a packet.
OnPacketAck ==
    /\ upcomingEvent.function \in "OnPacketAck"
    /\ upcomingEvent.packet \in packetCommitments[upcomingEvent.chain]
    \* remove packet commitment on acknowledgement
    /\ packetCommitments' = [packetCommitments EXCEPT ![upcomingEvent.chain] = @ \ {upcomingEvent.packet}]
    /\ UNCHANGED <<>> \* TODO 
*)

OnTimeoutPacketParent ==
    /\ upcomingEvent.packet.data.type = "ChangeValidatorSet"
    \* unfreeze stake of validators associated with the seqNum from the packet data
    /\ UnfreezeSingleStake(upcomingEvent.chain, upcomingEvent.packet.data.seqNum)
    \* ICS04: remove packet commitment 
    /\ packetCommitments' = [packetCommitments EXCEPT ![upcomingEvent.chain] = @ \ {upcomingEvent.packet}]
    \* ICS04: close ordered channels, in our case, halt protocol
    /\ haltProtocol' = TRUE
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
        TODO: 
        A correct on timeout handler should be specified once the English spec 
        is updated.
    *)
    \* ICS04: remove packet commitment 
    /\ packetCommitments' = [packetCommitments EXCEPT ![upcomingEvent.chain] = @ \ {upcomingEvent.packet}]
    \* ICS04: close ordered channels, in our case, halt protocol
    /\ haltProtocol' = TRUE
    \* TODO: other ICS04 packet-related actions on timeout?
    /\ UNCHANGED <<>> \* TODO 

(*  
    Engish spec note: The functions applyValidatorUpdate and finishUnbondingOVer
    called in the body of the function endBlock are not specified.
    It is not clear if applyValidatorUpdate only adds new validators to 
    the baby validator set, or if it also removes the validators for which 
    unbonding already finished, or if it just overwrites the existing validator set 
    with the validator set with the highest seqNum.
    Further, applyValidatorUpdate should be defined as a part of the staking module.
*)
ExecuteEndBlockBaby ==
    LET validatorUpdate == ApplyValidatorUpdate(babyValSetChanges) IN 
    /\ babyValidatorSet' = validatorUpdate.validatorSet
    /\ babySeqNum' = validatorUpdate.seqNum
    \* start unbonding 
    /\ StartUnbonding(validatorUpdate.seqNum)
    \* finish unbonding for mature validator sets
    /\ \E matureSeqNum \in SeqNums : 
        /\ matureSeqNum > babyLastUnbondedSeqNum
        /\ matureSeqNum <= babySeqNum      
        /\ FinishUnbonding(matureSeqNum) 

ProtocolStep ==
    \/ StartValSetUpdateParent
    \* step of parent chain IBC application
    \/ /\ parentPendingEvents /= <<>>
       /\ LET event == Head(parentPendingEvents) IN
            /\ upcomingEvent' = Head(parentPendingEvents)
            /\ parentPendingEvents' = Tail(parentPendingEvents)
            /\ \/ /\ event.function = "ChangeValidatorSet"
                  /\ event.chain = "parent"
                  /\ ChangeValidatorSetParent
               \/ /\ event.function = "OnPacketRecv"
                  /\ event.chain = "parent"
                  /\ OnPacketRecvParent
               (* 
                Uncomment if packet acknowledgements are added.
                \/ /\ event.function = "OnPacketAck"
                    /\ OnPacketAck
               *)      
               \/ /\ event.chain = "parent"
                  /\ OnTimeoutPacketParent   
    \* step of baby chain IBC application
    \/ /\ babyPendingEvents /= <<>>
       /\ LET event == Head(babyPendingEvents) IN
            /\ upcomingEvent' = event
            /\ parentPendingEvents' = Tail(babyPendingEvents)      
            /\ \/ /\ event.function = "OnPacketRecv"
                  /\ event.chain = "baby"
                  /\ OnPacketRecvBaby
                (* 
                Uncomment if packet acknowledgements are added.
                \/ /\ event.function = "OnPacketAck"
                    /\ OnPacketAck
                *)  
               \/ /\ event.chain = "baby"
                  /\ OnTimeoutPacketBaby
    \* endBlock function at baby chain
    \/ ExecuteEndBlockBaby



Init ==
    \* parent variables
    /\ parentNextSeqNum = 1
    /\ parentUnfrozenSeqNums = {} 
    \* baby variables
    /\ babyValidatorSet = {}
    /\ babySeqNum = 0
    /\ babyUnbonding = {}
    /\ babyValSetChanges = {}
    /\ babyLastUnbondedSeqNum = 0
    \* shared variables
    /\ packetCommitments = [chain \in ChainIDs |-> {}]
    /\ haltProtocol = FALSE
    \* events simulating a relayer
    /\ parentPendingEvents = <<>>
    /\ babyPendingEvents = <<>>
    /\ upcomingEvent = NullEvent


Next ==
    \/ /\ ~haltProtocol
       /\ ProtocolStep
    \/ /\ haltProtocol
       /\ UNCHANGED vars

\* TODO: specify fairness constraint
Fairness ==
    TRUE

(******************** Invariants and properties *******************)

\* all validators in the baby validator set 
\* originated from a packet sent by the parent chain
ValSetChangeValidity ==
    \* for each packet sent by the parent chain
    \A packet \in packetCommitments["parent"] :
        \* whose seqNum is greater than babyLastUnbondedSeqNum
        packet.data.seqNum > babyLastUnbondedSeqNum 
            \* its validatorSet is a part of the babyValidatorSet
            => packet.data.validatorSet \subseteq babyValidatorSet

\* the validator sets whose stake is unfrozen on the parent chain
\* have sequence numbers which are less than or equal to the sequence number 
\* of the validator set that was unbonded last on the baby chain
UnfrozenAreUnbondedFirst ==
    \A seqNum \in parentUnfrozenSeqNums : 
        seqNum <= babyLastUnbondedSeqNum

\* the validator sets whose stake is unfrozen on the parent chain
\* have sequence numbers which are less than the sequence number 
\* of the next validator set change to be processed
UnfrozenWereFrozenBefore ==
    \A seqNum \in parentUnfrozenSeqNums : 
        seqNum <= parentNextSeqNum

\* the sequence number of the last unbonded validator set at the baby 
\* blockchain is smaller than the current sequence number at the baby blockchain
UnbondedIsSmallerThanCurrent ==
   babyLastUnbondedSeqNum < babySeqNum 


\* all validator sets whose stake is frozen eventually either 
\* get unfrozen or the protocol halts (there is a timeout)
StakeOfParentValidatorsIsEventuallyUnfrozen ==
    \A seqNum \in SeqNums :
        [](parentNextSeqNum = seqNum
            => <>(\/ seqNum \in parentUnfrozenSeqNums
                  \/ haltProtocol))

\* all validator set changes eventually either get processed 
\* at the baby chain or the protocol halts (there is a timeout)
ValidatorSetChangeIsEventuallyProcessed ==
    \A seqNum \in SeqNums :
        [](parentNextSeqNum = seqNum
            => <>(\/ babySeqNum >= seqNum
                  \/ haltProtocol))

\* all validator sets that are unbonded on the baby chain eventually
\* either get their stake unfrozen on the parent chain 
\* or the protocol halts (there is a timeout)
UnbondedAreEventuallyUnfrozen ==
    \A seqNum \in SeqNums :
        [](babyLastUnbondedSeqNum = seqNum
            => <>(\/ Max(parentUnfrozenSeqNums) <= seqNum
                  \/ haltProtocol))

\* all validator set changes eventually either get unbonded 
\* at the baby chain or the protocol halts (there is a timeout)
ValidatorSetIsEventuallyUnbonded ==
    \A seqNum \in SeqNums :
        [](parentNextSeqNum = seqNum
            => <>(\/ babyLastUnbondedSeqNum >= seqNum - 1
                  \/ haltProtocol))
===================================================================
