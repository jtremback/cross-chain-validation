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
- M(dc,i).valset, with M(dc,0).valset = InitialVS
- M(dc,i).epoch
- M(dc,0).epoch = 0

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


## Cross-chain Bonding

The mother chain maintains the validators whose unbonding has
started but their funds are not freed yet: *amount = Frozen(val,e)*
denotes that unbonding of *amount* tokens was started for validator
val at the begin of epoch e (on the mother chain)


Let unbonding-start(e) be the minimal time s.t. *DC.EPOCH >= e*

The daughter chain may issue a *Release(val,refund,e)*
transaction.

> *refund* tokens should be returned to the validator val due to
> unbonding in epoch e

#### [XCV-DC-UNB-UNIQUE-INV.1]
For each e and val, *Release(val,refund,e)* is issued at most once.

#### [XCV-DC-UNB-INV.1]
*Release(val,refund,e)* is not issued before  unbonding-start(e) +
UNBONDING_PERIOD.

#### [XCV-DC-UNB-LIFE.1]
*Release(val,refund,e)* is eventually issued

> refund could be equal to 0. If this is the case, the meaning simply is that "unbonding on the daughter chain is over" but nothing should be paid back

#### [XCV-DC-REFUND-INV.1]
If *Release(val,refund,e)* is issued, then *refund <= Frozen(val,e)*

> if val misbehaved, we don't pay all back

#### [XCV-XC-UNB-INV.1]
amount is not reduced before *Release(val,refund,e)* is issued.

#### [XCV-XC-UNB-LIFE.1]
If *Release(val,refund,e)* is issued and "the channel stays open",
then eventually *refund* should be paid back and *Frozen(val,e)*
should be set to 0.
