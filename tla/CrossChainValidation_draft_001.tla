------------- MODULE CrossChainValidation_draft_001 ---------------

EXTENDS Integers, FiniteSets, Sequences

CONSTANTS PortIDs, \* set of portIDs
          ChannelIDs, \* set of channelIDs
          Chains, \* set of chainIDs
          Validators, \* set of validatorIDs
          ParentValidators, \* set of validatorIDs of validators at the parent
          MaxChangeValidatorSeqNum, \* integer
          ChangeValSetDemand \* sequence of length MaxChangeValidatorSeqNum, 
                             \* storing validator sets for each sequence number

VARIABLES parentFrozenStake, \* a mapping from sequence numbers to set of validators whose stake is frozen
          packetCommitments, \* a set of packet commitments for each chain, [Chains -> Packets]
          packetReceipts, \* a set of packet receipts for each chain, [Chains -> Packets]
          packetAcknowledgements, \* a set of packet acknowledgements for each chain, [Chains -> Packets]
          babyUnbonding, \* set of validators that are currently unbonding
          babyValidatorSet, \* validator set of the baby blockchain
          babySeqNum, \* sequence number of the last change validator set demand
          babyQueueValSetChanges, \* queue of validator set change demands, Seq(Validators \X SeqNums)
          pendingStakingModuleEvents,
          pendingEvents, 
          upcomingEvent

(*************************** Definitions **************************)
SeqNums == 1 .. MaxChangeValidatorSeqNum
AllValidators == Validators

NullChainID == "none"
NullEvent == "none"

CrossChainValidationPacketData == [
    type : {"ChangeValidatorSet"},
    validatorSet : SUBSET (Validators),
    seqNum : SeqNums
] \union [
    type : {"UnbondingOver"},
    seqNums : SUBSET (SeqNums)
]

Packets == [
    srcPort : PortIDs,
    srcChannel : ChannelIDs,
    dstPort : PortIDs,
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

StakingModuleEvents == [
    function : StakingModuleFunctions,
    chain : Chains,
    valSet : Validators,
    seqNum : SeqNums
]

Events == [
    packet : Packets,
    function : Functions,
    chain : Chains
]

InitialStakingModuleEvents == {
    [
        function |-> "FreezeStake",
        chain |-> "parent",
        valSet |-> ChangeValSetDemand[seq],
        seqNum |-> seq 
    ] : seq \in SeqNums
}
    
(**************************** Operators ***************************)
    
GetReceiverChain(packet) ==
    IF /\ packet.dstChannelID = "channelParent"
       /\ packet.dstPortID = "portParent"
    THEN "parent"
    ELSE IF /\ packet.dstChannelID = "channelBaby"
            /\ packet.dstPortID = "portBaby"
         THEN "baby"
         ELSE NullChainID

CreateChangeValSetPacket(chain, valSet, seqNum) ==
    LET packetData == [
        type |-> "ChangeValidatorSet",
        validatorSet |-> valSet,
        seqNum |-> seqNum
    ] IN 
    LET packet == [
        srcPort |-> "parentPort",
        srcChannel |-> "parentChannel",
        dstPort |-> "babyPort",
        dstChannel |-> "babyChannel",
        data |-> packetData
    ] IN 
    LET event == [
        packet |-> packet,
        function |-> "ChangeValidatorSet",
        chain |-> chain
    ] IN

    pendingEvents' = pendingEvents \union {event}

SendChangeValSetPacket(chain, packet) ==
    LET event == [
        packet |-> packet,
        function |-> "OnPacketRecv",
        chain |-> GetReceiverChain(packet)
    ] IN 

    /\ packetCommitments' = [packetCommitments EXCEPT 
                                ![chain] = @ \union {packet}]
    /\ pendingEvents' = pendingEvents \union {event} 

UnfreezeStake(chain, seqNum) ==
    /\ chain = "parent"
    /\ seqNum \in DOMAIN parentFrozenStake
    /\ parentFrozenStake' = [seq \in SeqNums |-> 
                                IF seq <= seqNum
                                THEN {}
                                ELSE parentFrozenStake[seq]
                            ]

UnfreezeSingleStake(chain, seqNum) ==
    /\ chain = "parent"
    /\ seqNum \in DOMAIN parentFrozenStake
    /\ parentFrozenStake' = [parentFrozenStake EXCEPT ![seqNum] = {}]

QueueValidatorSetChange(chain, packet) ==
    /\ chain = "baby"
    /\ babyQueueValSetChanges' = Append(babyQueueValSetChanges, 
                                        <<packet.data.validatorSet, packet.data.seqNum>>) 

DefaultAck(chain, packet) ==
    LET receiverChain == GetReceiverChain(packet) IN 
    LET event == [
        packet |-> packet,
        function |-> "OnPacketAck",
        chain |-> receiverChain
    ] IN 
    
    /\ packetAcknowledgements' = [packetAcknowledgements EXCEPT 
                                    ![chain] = @ \union {packet}]
    /\ pendingEvents' = pendingEvents \union {event}
        
(***************************** Actions ****************************)

\* no preconditions specified since the function is not specified 
FreezeStake ==
    /\ upcomingEvent.function = "FreezeStake"
    \* create a packet 
    /\ CreateChangeValSetPacket(upcomingEvent.chain, upcomingEvent.valSet, upcomingEvent.seqNum)
    \* keep track of validators whose stake is frozen on the parent chain
    /\ parentFrozenStake' = [parentFrozenStake EXCEPT 
                                ![upcomingEvent.seqNum] = @ \union upcomingEvent.valSet]
    /\ UNCHANGED <<>> \* TODO 

ChangeValidatorSet ==
    /\ upcomingEvent.function = "ChangeValidatorSet"
    /\ upcomingEvent.packet.data.type = "ChangeValidatorSet"
    \* there exists a blockchain that is a receiver of this packet
    /\ GetReceiverChain(upcomingEvent.packet) \in Chains
    \* all validators are validators at the parent blockchain
    /\ upcomingEvent.packet.data.validatorSet \subseteq ParentValidators
    \* the stake of each validator is frozen and associated with this demand
    /\ upcomingEvent.valSet \subseteq parentFrozenStake[upcomingEvent.seqNum]
    \* send packet, i.e., write packet to data store
    /\ SendChangeValSetPacket(upcomingEvent.chain, upcomingEvent.packet)
    /\ UNCHANGED <<>> \* TODO 

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
    /\ QueueValidatorSetChange(upcomingEvent.chain, upcomingEvent.packet)
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
    \* TODO: other ICS04 packet-related actions on timeout?
    /\ UNCHANGED <<>> \* TODO 

OnTimeoutPacketBaby ==    
    /\ upcomingEvent.packet.data.type = "UnbondingOver"
    \* TODO: send same packet again
    \* TODO: other ICS04 packet-related actions on timeout?
    /\ UNCHANGED <<>> \* TODO 

ExecuteEndBlock ==
    TRUE    

Init ==
    /\ parentFrozenStake = [seqNum \in SeqNums |-> {}]
    /\ packetCommitments = [chain \in Chains |-> {}]
    /\ packetReceipts = [chain \in Chains |-> {}]
    /\ packetAcknowledgements = [chain \in Chains |-> {}]
    /\ babyUnbonding = {}
    /\ babyValidatorSet \subseteq Validators
    /\ babySeqNum = 1
    /\ babyQueueValSetChanges = <<>>
    /\ pendingStakingModuleEvents = InitialStakingModuleEvents 
    /\ pendingEvents = {} 
    /\ upcomingEvent = NullEvent

\* TODO: sequence numbers in packets? ordered channels? 
Next ==
    \/ \E event \in pendingStakingModuleEvents :
        /\ upcomingEvent' = event
        /\ pendingStakingModuleEvents' = pendingStakingModuleEvents \ {event}
        /\ \/ /\ event.function = "FreezeStake"
              /\ FreezeStake
           
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