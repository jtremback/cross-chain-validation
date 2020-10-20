# Cross-chain Validation Temporal Properties

## Mother chain

The mother chain publishes the following transactions
- `CREATE_VALIDATOR_SET (dc, InitialVS)`
- `MODIFY_VALIDATOR_SET (dc, NEWVS, epoch)`

#### [XCV-MC-INV-CREATE-VALS.1]
For each `dc`, there is at most one `CREATE_VALIDATOR_SET (dc, DCVS)` during the whole execution.

#### [XCV-MC-DEF-EPOCH.1]
The sequence of calls `MODIFY_VALIDATOR_SET (dc, NEWVS,epoch)` is denoted 
by *M(dc)*.  
By *M(dc,i)* we denote the *i*th element. We use the notation
- M(dc,i).valset, with M(dc,0) = InitialVS
- M(dc,i).epoch


#### [XCV-MC-INV-MODIFY-VALS.1]
At all times, for all *i*, *M(dc,i).epoch = i*.

#### [XCV-MC-DEF-EPOCH.1]

*epoch(t)* = e iff 
- `MODIFY_VALIDATOR_SET (dc, NEWVS, e)` appeared in a
block with *bfttime < t*, 
- and there is no other block
generated at *t'*,  *bfttime < t' < t*, with a `MODIFY_VALIDATOR_SET` transaction

## Daughter chain

EPOCH is an integer in the application state of the daughter chain.  

> I think it will make definitions easier. We might drop it eventually.

#### [XCV-DC-SETUP.1]

We say the daughter chain is *set up* if
- IBC channel (connection?) between MC and DC set up
- DC.VS = InitialVS
- DC.EPOCH = 0

#### [XCV-DC-INV-EPOCH.1]
For all times *t*, *DC.EPOCH <= epoch(t)*.

#### [XCV-DC-TRANSINV-EPOCH.1]
*DC.EPOCH* is non-decreasing.

#### [XCV-DC-LIVE-EPOCH.1]
For all times *t*, if *DC.EPOCH(t) < epoch(t)* then there is a time *t'>t* such that *DC.EPOCH(t') > DC.EPOCH(t)*.

> We will need some fairness regarding IBC packet delivery to ensure liveness. I am not sure how to formalize that. 

> I am not sure whether we should require *DC.EPOCH(t') = DC.EPOCH(t) + 1*. I am not sure what "ordered" channels mean in IBC. Can we receive two packets in the same block?

#### [XCV-DC-INV.1]
For all times, *DC.VS = M(dc,DC.EPOCH).valset* 

