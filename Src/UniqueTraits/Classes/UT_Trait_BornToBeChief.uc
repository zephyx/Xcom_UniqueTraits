//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_BornToBeChief.uc
//  PURPOSE: Born to be chief [LWOTC ONLY]: fixed -BORNTOBECHIEF_AIM_DODGE_WILL_BASE Aim/Dodge/Will, +
//           BORNTOBECHIEF_AIM_DODGE_WILL_PER_RANK to each per LWOTC officer rank held. Neither part is an
//           ability effect (a plain X2Effect_PersistentStatChange is mission-scoped, it would never lower the real
//           Max Will/Aim/Dodge between missions): both are direct permanent mutations. The ability is a bare icon
//           holder; the ini also grants the LW ability 'QuickStudy'.
//           The officer rank comes from LWOTC's public 'GetLWUnitInfo' blind query (UT_LWOTCHelpers).
//           ApplyBornToBeChiefRankScaling is synced by X2EventListener_UniqueTraits at mission
//           start ('OnTacticalBeginPlay'), month end ('PreEndOfMonth') and personnel sort refresh, and at every promotion (OnRankUp).
//           The stats are brought to the total the rank calls for (-BASE + officer rank x PER_RANK, a rookie included) as a change of ours: the target minus the LEDGER
//           of UT_TraitBase.ShiftStat. Removal = RevertShifts (the exact stats back), a respec = OnStatsReset (see UT_TraitBase).
//---------------------------------------------------------------------------------------
class UT_Trait_BornToBeChief extends UT_TraitBase config(UniqueTraits);

var config int BORNTOBECHIEF_AIM_DODGE_WILL_BASE;
var config int BORNTOBECHIEF_AIM_DODGE_WILL_PER_RANK;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(PurePassive('UT_BornToBeChief', "img:///UniqueTraits_Icons.UT_BornToBeChief", true));

	return Templates;
}

static function bool ShiftsStats()
{
	return true;
}

static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	// The fixed malus and, for an already-officer soldier (AddUniqueTrait), the PER_RANK bonus per officer rank, right away instead of waiting for the
	// next mission start / month end / personnel sort sync. A rookie gets the fixed malus at once.
	ApplyBornToBeChiefRankScaling(MutableUnit);
}

// The trait is already out of AcquiredTraits here: the stats go back to what they were, exactly.
static function OnClear(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	RevertShifts(MutableUnit);
}

// 'UnitRankUp': a real promotion (the first one applies the fixed malus).
static function bool OnRankUp(XComGameState_Unit MutableUnit)
{
	return ApplyBornToBeChiefRankScaling(MutableUnit);
}

// The base stats were rebuilt by a respec: what the trait had put in them is gone.
static function OnStatsReset(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	ForgetShifts(MutableUnit);
	ApplyBornToBeChiefRankScaling(MutableUnit);
}

// Brings Aim / Dodge / Will to the total the unit calls for: -BORNTOBECHIEF_AIM_DODGE_WILL_BASE plus BORNTOBECHIEF_AIM_DODGE_WILL_PER_RANK per LWOTC
// officer rank (UT_LWOTCHelpers.GetLWOfficerRank), a rookie included. The target minus the ledger is applied, so it is idempotent. True if something changed.
static final function bool ApplyBornToBeChiefRankScaling(XComGameState_Unit MutableUnit)
{
	local float Wanted;
	local int OfficerRank;
	local bool bChanged;

	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(MutableUnit, 'UT_BornToBeChief'))
		return false;

	OfficerRank = class'UT_LWOTCHelpers'.static.GetLWOfficerRank(MutableUnit);
	Wanted = -default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE + OfficerRank * default.BORNTOBECHIEF_AIM_DODGE_WILL_PER_RANK;

	bChanged = ShiftStatTo(MutableUnit, eStat_Offense, Wanted);
	bChanged = ShiftStatTo(MutableUnit, eStat_Dodge, Wanted) || bChanged;
	bChanged = ShiftStatTo(MutableUnit, eStat_Will, Wanted) || bChanged;

	if (bChanged)
		`log("UniqueTraits : Born to be chief stats synced on" @ MutableUnit.GetFullName() @ "officer rank" @ OfficerRank @ ": aim/dodge/will" @ Wanted,, 'UniqueTraits');

	return bChanged;
}

// Born to be chief's officer-rank stat sync, personnel-list variant
static function EventListenerReturn OnUIPersonnelSortFinished(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Unit> Soldiers;
	local XComGameState_Unit Soldier, MutableUnit;
	local XComGameState NewGameState;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	Soldiers = XComHQ.GetSoldiers();
	foreach Soldiers(Soldier)
	{
		if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Soldier, 'UT_BornToBeChief'))
			continue;

		if (NewGameState == none)
			NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Born to be chief personnel-list rank sync");

		MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Soldier.ObjectID));
		ApplyBornToBeChiefRankScaling(MutableUnit);
	}

	if (NewGameState != none)
		`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}

// Born to be chief's officer-rank stat sync, mission-start variant
static function EventListenerReturn OnTacticalBeginPlay(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference SquadRef;
	local XComGameState_Unit SquadUnit, MutableUnit;

	if (GameState == none)
		return ELR_NoInterrupt;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	foreach XComHQ.Squad(SquadRef)
	{
		SquadUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(SquadRef.ObjectID));
		if (SquadUnit == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SquadUnit, 'UT_BornToBeChief'))
			continue;

		MutableUnit = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', SquadUnit.ObjectID));
		ApplyBornToBeChiefRankScaling(MutableUnit);
	}

	return ELR_NoInterrupt;
}

// Born to be chief's officer-rank stat sync. Officer rank only ever changes in the strategy
// layer (an LW officer-training HQ project completing) so this runs off the vanilla/CHL 'PreEndOfMonth'
// event. There's no precise "officer training completed" event to hook (LW_Overhaul's own would-be
// 'UnitPromoted' trigger is dead code, and CHL exposes no generic "any HQ project completed" event
// either). Monthly is a deliberate compromise: purely strategy-layer, and it piggybacks its changes directly
// onto the same NewGameState 'PreEndOfMonth' is fired with (ELD_Immediate, still open at this point) rather
// than opening a separate transaction. Two more sync points cover the gaps (see each's own comment):
// OnTacticalBeginPlay (once at the start of every mission, the one that actually *guarantees* combat
// correctness) and OnUIPersonnelSortFinished (whenever a personnel list is shown, display freshness only).
static function EventListenerReturn OnPreEndOfMonth_BornToBeChief(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Unit> Soldiers;
	local XComGameState_Unit Soldier, MutableUnit;

	if (GameState == none)
		return ELR_NoInterrupt;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	Soldiers = XComHQ.GetSoldiers();
	foreach Soldiers(Soldier)
	{
		if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Soldier, 'UT_BornToBeChief'))
			continue;

		MutableUnit = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', Soldier.ObjectID));
		ApplyBornToBeChiefRankScaling(MutableUnit);
	}

	return ELR_NoInterrupt;
}
