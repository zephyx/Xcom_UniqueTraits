//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_BornToBeChief.uc
//  PURPOSE: Born to be chief [LWOTC ONLY]: fixed -BORNTOBECHIEF_AIM_DODGE_WILL_BASE Aim/Dodge/Will, +
//           BORNTOBECHIEF_AIM_DODGE_WILL_PER_RANK to each per LWOTC officer rank held. Neither part is an
//           ability effect (a plain X2Effect_PersistentStatChange is mission-scoped, it would never lower the real
//           Max Will/Aim/Dodge between missions): both are direct permanent mutations. The ability is a bare icon
//           holder; the ini also grants the LW ability 'QuickStudy'.
//           The officer rank comes from LWOTC's public 'GetLWUnitInfo' blind query (UT_LWOTCHelpers).
//           ApplyBornToBeChiefRankScaling is synced by X2EventListener_UniqueTraits at mission
//           start ('OnTacticalBeginPlay'), month end ('PreEndOfMonth') and personnel sort refresh.
//---------------------------------------------------------------------------------------
class UT_Trait_BornToBeChief extends UT_TraitBase config(UniqueTraits);

var config int BORNTOBECHIEF_AIM_DODGE_WILL_BASE;
var config int BORNTOBECHIEF_AIM_DODGE_WILL_PER_RANK;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(PurePassive('UT_BornToBeChief', "img:///UILibrary_PerkIcons.UIPerk_standard", true));

	return Templates;
}

static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	ShiftBaseStats(MutableUnit, -default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE);

	// Reset ApplyBornToBeChiefRankScaling's tracking UnitValue in case this unit had the trait before, was
	// cleared, and is now getting it again (OnClear already resets it, this is just defensive).
	MutableUnit.SetUnitFloatValue('UT_BornToBeChief_LastOfficerRank', 0, eCleanup_Never);

	// An already-officer soldier (AddUniqueTrait) gets its PER_RANK bonus per officer rank right away instead of waiting for
	// the next mission start/month end/personnel sort sync. No-op for officer rank 0.
	ApplyBornToBeChiefRankScaling(MutableUnit);
}

static function OnClear(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	local UnitValue LastOfficerRankValue;
	local int LastOfficerRank;

	ShiftBaseStats(MutableUnit, default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE);

	// ApplyBornToBeChiefRankScaling tracks UT_BornToBeChief_LastOfficerRank as the officer rank it last synced
	// stats for, always diffing from a baseline of 0 => the tracked value IS the total number of "ranks" worth
	// of delta accumulated so far; multiply back out and undo in one shot.
	LastOfficerRank = 0;
	if (MutableUnit.GetUnitValue('UT_BornToBeChief_LastOfficerRank', LastOfficerRankValue))
		LastOfficerRank = int(LastOfficerRankValue.fValue);

	if (LastOfficerRank > 0)
		ShiftBaseStats(MutableUnit, -(LastOfficerRank * default.BORNTOBECHIEF_AIM_DODGE_WILL_PER_RANK));
	MutableUnit.SetUnitFloatValue('UT_BornToBeChief_LastOfficerRank', 0, eCleanup_Never);
}

static final function ShiftBaseStats(XComGameState_Unit UnitState, float Delta)
{
	ShiftStat(UnitState, eStat_Offense, Delta);
	ShiftStat(UnitState, eStat_Dodge, Delta);
	ShiftStat(UnitState, eStat_Will, Delta);
}

// Applies the delta between this unit's currently-known officer rank (UT_LWOTCHelpers.GetLWOfficerRank) and the last rank this
// function applied stats for (tracked via the UT_BornToBeChief_LastOfficerRank UnitValue),
// +/- BORNTOBECHIEF_AIM_DODGE_WILL_PER_RANK per rank of difference, to Aim/Dodge/Will.
static final function bool ApplyBornToBeChiefRankScaling(XComGameState_Unit MutableUnit)
{
	local UnitValue LastRankValue;
	local int LastRank, CurrentRank;

	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(MutableUnit, 'UT_BornToBeChief'))
		return false;

	CurrentRank = class'UT_LWOTCHelpers'.static.GetLWOfficerRank(MutableUnit);
	LastRank = 0;
	if (MutableUnit.GetUnitValue('UT_BornToBeChief_LastOfficerRank', LastRankValue))
		LastRank = int(LastRankValue.fValue);

	if (CurrentRank == LastRank)
		return false;

	ShiftBaseStats(MutableUnit, (CurrentRank - LastRank) * default.BORNTOBECHIEF_AIM_DODGE_WILL_PER_RANK);

	MutableUnit.SetUnitFloatValue('UT_BornToBeChief_LastOfficerRank', CurrentRank, eCleanup_Never);

	`log("UniqueTraits : Born to be chief officer rank scaling applied to" @ MutableUnit.GetFullName() @ "rank" @ LastRank @ "->" @ CurrentRank,, 'UniqueTraits');

	return true;
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
