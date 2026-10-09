//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_MindOverMatter.uc
//  PURPOSE: Mind over matter: -3 HP, -2 mobility, -6 aim and a wound recovery 45% longer, each offset by a percentage of the holder's
//           MAX Will: +7% (HP), +4% (mobility), +15% (aim) of the Will as stat points (rounded), and -120% of the Will as recovery
//           time %. The numbers are tuned (ini) so that the trait is neutral around 37 Will, punishing below and rewarding above.
//           The stats are PERMANENT changes of the soldier (ShiftStat, like Nerd / Born to be chief), so they also show in the Armory.
//           What was added is remembered per stat in the UnitValues UT_MindOverMatter_Applied_<Stat> (the net amount currently applied),
//           and SyncMindOverMatterStats applies only the difference between the amount the current max Will calls for and that one:
//           idempotent, and OnClear takes back exactly what is applied. There is no hook on a max Will change (SetBaseMaxStat is native),
//           so the sync runs at every known cause: rank-up, PCS equipped/removed ('ItemAddedToSlot'/'ItemRemovedFromSlot'), a Gene Mod
//           ('GeneModOperationCompleted', mod WotC_Gameplay_GeneModding), an ability bought ('AbilityPointsChange': perks that raise the
//           Will, e.g. Mitzruti's), plus safety nets: mission start (guarantees combat), month end and personnel lists.
//           The recovery time is changed like Quick healing / Give me more do (a 'CleanupTacticalMission' handler, before
//           EndTacticalHealthMod): the wound that EndTacticalHealthMod sizes from HighestHP - LowestHP is scaled by the percentage (a
//           longer or shorter wound = more or fewer HP missing, the recovery time following the wound).
//---------------------------------------------------------------------------------------
class UT_Trait_MindOverMatter extends UT_TraitBase config(UniqueTraits);

var config int MINDOVERMATTER_HP_MALUS, MINDOVERMATTER_MOBILITY_MALUS, MINDOVERMATTER_AIM_MALUS, MINDOVERMATTER_RECOVERY_MALUS_PCT;
var config float MINDOVERMATTER_HP_PCT_OF_WILL, MINDOVERMATTER_MOBILITY_PCT_OF_WILL, MINDOVERMATTER_AIM_PCT_OF_WILL, MINDOVERMATTER_RECOVERY_PCT_OF_WILL;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(MindOverMatter());

	return Templates;
}

// A bare icon holder: the stats are permanent changes (SyncMindOverMatterStats), the recovery time a handler.
static function X2AbilityTemplate MindOverMatter()
{
	return PurePassive('UT_MindOverMatter', "img:///UILibrary_PerkIcons.UIPerk_standard", true);
}

//---------------------------------------------------------------------------------------
// Stats
//---------------------------------------------------------------------------------------

// The net change of a stat that the unit's current max Will calls for: Round(Will * pct / 100) - malus (the bonus is rounded BEFORE the malus).
static final function int GetTargetChange(XComGameState_Unit Unit, ECharStatType Stat)
{
	local float Will;

	Will = Unit.GetMaxStat(eStat_Will);
	switch (Stat)
	{
		case eStat_HP:
			return Round(Will * default.MINDOVERMATTER_HP_PCT_OF_WILL / 100.0) - default.MINDOVERMATTER_HP_MALUS;
		case eStat_Mobility:
			return Round(Will * default.MINDOVERMATTER_MOBILITY_PCT_OF_WILL / 100.0) - default.MINDOVERMATTER_MOBILITY_MALUS;
		case eStat_Offense:
			return Round(Will * default.MINDOVERMATTER_AIM_PCT_OF_WILL / 100.0) - default.MINDOVERMATTER_AIM_MALUS;
	}

	return 0;
}

static final function name GetAppliedValueName(ECharStatType Stat)
{
	switch (Stat)
	{
		case eStat_HP:
			return 'UT_MindOverMatter_Applied_HP';
		case eStat_Mobility:
			return 'UT_MindOverMatter_Applied_Mobility';
		case eStat_Offense:
			return 'UT_MindOverMatter_Applied_Aim';
	}

	return '';
}

// The net change currently applied to the unit for a stat (what OnClear takes back).
static final function int GetAppliedChange(XComGameState_Unit Unit, ECharStatType Stat)
{
	local UnitValue Value;

	if (Unit.GetUnitValue(GetAppliedValueName(Stat), Value))
		return int(Value.fValue);

	return 0;
}

static final function bool NeedsSync(XComGameState_Unit Unit)
{
	return GetTargetChange(Unit, eStat_HP) != GetAppliedChange(Unit, eStat_HP)
		|| GetTargetChange(Unit, eStat_Mobility) != GetAppliedChange(Unit, eStat_Mobility)
		|| GetTargetChange(Unit, eStat_Offense) != GetAppliedChange(Unit, eStat_Offense);
}

static final function bool SyncOneStat(XComGameState_Unit MutableUnit, ECharStatType Stat)
{
	local int Target, Applied;

	Target = GetTargetChange(MutableUnit, Stat);
	Applied = GetAppliedChange(MutableUnit, Stat);
	if (Target == Applied)
		return false;

	ShiftStat(MutableUnit, Stat, Target - Applied);
	MutableUnit.SetUnitFloatValue(GetAppliedValueName(Stat), Target, eCleanup_Never);

	return true;
}

// Brings the stats to what the unit's max Will calls for. The unit must be modifiable (a pending state object) and hold the trait.
static final function bool SyncMindOverMatterStats(XComGameState_Unit MutableUnit)
{
	local bool bChanged;

	bChanged = SyncOneStat(MutableUnit, eStat_HP);
	bChanged = SyncOneStat(MutableUnit, eStat_Mobility) || bChanged;
	bChanged = SyncOneStat(MutableUnit, eStat_Offense) || bChanged;

	if (bChanged)
		`log("UniqueTraits : Mind over matter --" @ MutableUnit.GetFullName() @ "max Will" @ MutableUnit.GetMaxStat(eStat_Will) @ ": HP" @ GetAppliedChange(MutableUnit, eStat_HP)
			$ ", mobility" @ GetAppliedChange(MutableUnit, eStat_Mobility) $ ", aim" @ GetAppliedChange(MutableUnit, eStat_Offense),, 'UniqueTraits');

	return bChanged;
}

static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	// Defensive: a unit that had the trait before was cleared by OnClear, which already resets them.
	MutableUnit.SetUnitFloatValue(GetAppliedValueName(eStat_HP), 0, eCleanup_Never);
	MutableUnit.SetUnitFloatValue(GetAppliedValueName(eStat_Mobility), 0, eCleanup_Never);
	MutableUnit.SetUnitFloatValue(GetAppliedValueName(eStat_Offense), 0, eCleanup_Never);

	SyncMindOverMatterStats(MutableUnit);
}

// Takes back exactly what is applied (the trait is already out of AcquiredTraits here, so nothing may depend on UnitHasTrait).
static function OnClear(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	local int Applied;

	Applied = GetAppliedChange(MutableUnit, eStat_HP);
	if (Applied != 0)
		ShiftStat(MutableUnit, eStat_HP, -Applied);
	Applied = GetAppliedChange(MutableUnit, eStat_Mobility);
	if (Applied != 0)
		ShiftStat(MutableUnit, eStat_Mobility, -Applied);
	Applied = GetAppliedChange(MutableUnit, eStat_Offense);
	if (Applied != 0)
		ShiftStat(MutableUnit, eStat_Offense, -Applied);

	MutableUnit.SetUnitFloatValue(GetAppliedValueName(eStat_HP), 0, eCleanup_Never);
	MutableUnit.SetUnitFloatValue(GetAppliedValueName(eStat_Mobility), 0, eCleanup_Never);
	MutableUnit.SetUnitFloatValue(GetAppliedValueName(eStat_Offense), 0, eCleanup_Never);
}

// One handler for the events after which the max Will of a unit may have changed: 'UnitRankUp' (EventData = the unit), 'ItemAddedToSlot' /
// 'ItemRemovedFromSlot' (EventData = the item, EventSource = the unit), 'GeneModOperationCompleted' and 'AbilityPointsChange' (the unit).
// All registered ELD_OnStateSubmitted: the change that moved the Will is committed, the sync goes in a transaction of its own.
static function EventListenerReturn OnWillMayHaveChanged_MindOverMatter(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit Unit, MutableUnit;
	local XComGameState NewGameState;

	Unit = XComGameState_Unit(EventData);
	if (Unit == none)
		Unit = XComGameState_Unit(EventSource);
	if (Unit == none)
		return ELR_NoInterrupt;

	Unit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(Unit.ObjectID));
	if (Unit == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Unit, 'UT_MindOverMatter') || !NeedsSync(Unit))
		return ELR_NoInterrupt;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Mind over matter stats sync");
	MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Unit.ObjectID));
	SyncMindOverMatterStats(MutableUnit);
	`GAMERULES.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}

// Mission start (the point that guarantees the stats in combat): the squad's holders are synced in the mission's own state.
static function EventListenerReturn OnTacticalBeginPlay_MindOverMatter(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
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
		if (SquadUnit == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SquadUnit, 'UT_MindOverMatter') || !NeedsSync(SquadUnit))
			continue;

		MutableUnit = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', SquadUnit.ObjectID));
		SyncMindOverMatterStats(MutableUnit);
	}

	return ELR_NoInterrupt;
}

// Month end (safety net, in the 'PreEndOfMonth' state, still open).
static function EventListenerReturn OnPreEndOfMonth_MindOverMatter(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
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
		if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Soldier, 'UT_MindOverMatter') || !NeedsSync(Soldier))
			continue;

		MutableUnit = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', Soldier.ObjectID));
		SyncMindOverMatterStats(MutableUnit);
	}

	return ELR_NoInterrupt;
}

// Personnel lists (safety net for what the Armory shows): a transaction only when something has to change.
static function EventListenerReturn OnUIPersonnelSortFinished_MindOverMatter(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
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
		if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Soldier, 'UT_MindOverMatter') || !NeedsSync(Soldier))
			continue;

		if (NewGameState == none)
			NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Mind over matter personnel-list sync");

		MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Soldier.ObjectID));
		SyncMindOverMatterStats(MutableUnit);
	}

	if (NewGameState != none)
		`GAMERULES.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}

//---------------------------------------------------------------------------------------
// Recovery time
//---------------------------------------------------------------------------------------

// 'CleanupTacticalMission' (CHL #96, BEFORE the end-of-mission health adjustment): for each squad holder, the wound (HighestHP - LowestHP) is
// scaled by (100 + MALUS - Will * 50 / 100) %, rounded to whole HP, with LWOTC Field Surgeon's guards (not dead/captured, not bleeding out
// now or earlier in the mission, actually wounded). A wound can grow up to a unit left with 1 HP, never to death. As Field Surgeon does for a
// smaller wound, the current HP follow when it is raised. The time is not linear in HP (the game sizes it by wound severity bands) and the HP
// are whole: a very small wound may not change.
static function EventListenerReturn OnCleanupTacticalMission_MindOverMatter(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference SquadRef;
	local XComGameState_Unit SquadUnit, MutableUnit;
	local UnitValue BledOutValue;
	local float Percent;
	local int Wound, NewWound, OldLowest;

	if (GameState == none)
		return ELR_NoInterrupt;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	foreach XComHQ.Squad(SquadRef)
	{
		SquadUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(SquadRef.ObjectID));
		if (SquadUnit == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SquadUnit, 'UT_MindOverMatter'))
			continue;

		MutableUnit = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', SquadUnit.ObjectID));
		if (MutableUnit.IsDead() || MutableUnit.bCaptured || MutableUnit.IsBleedingOut() || MutableUnit.GetUnitValue('UT_MindOverMatter_BledOut', BledOutValue))
			continue;
		if (MutableUnit.LowestHP <= 0 || MutableUnit.LowestHP >= MutableUnit.HighestHP)
			continue;

		Percent = default.MINDOVERMATTER_RECOVERY_MALUS_PCT - MutableUnit.GetMaxStat(eStat_Will) * default.MINDOVERMATTER_RECOVERY_PCT_OF_WILL / 100.0;
		Wound = MutableUnit.HighestHP - MutableUnit.LowestHP;
		NewWound = Clamp(Round(Wound * (100.0 + Percent) / 100.0), 0, MutableUnit.HighestHP - 1);
		if (NewWound == Wound)
			continue;

		OldLowest = MutableUnit.LowestHP;
		MutableUnit.LowestHP = MutableUnit.HighestHP - NewWound;

		// Like Field Surgeon for a smaller wound; for a bigger one only LowestHP, which is what the wound is sized from, changes.
		if (NewWound < Wound && MutableUnit.GetCurrentStat(eStat_HP) < MutableUnit.GetMaxStat(eStat_HP))
			MutableUnit.ModifyCurrentStat(eStat_HP, MutableUnit.LowestHP - OldLowest);

		`log("UniqueTraits : Mind over matter --" @ MutableUnit.GetFullName() @ "wound" @ Wound @ "->" @ NewWound @ "HP (" $ Percent $ "%), LowestHP" @ OldLowest @ "->" @ MutableUnit.LowestHP,, 'UniqueTraits');
	}

	return ELR_NoInterrupt;
}

// Mind over matter: remembers that this soldier bled out during the mission (the status is cleared before the cleanup handler runs): the
// usual harsh recovery stays, as with Field Surgeon.
static function EventListenerReturn OnUnitBleedingOut_MindOverMatter(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit UnitState, MutableUnit;

	UnitState = XComGameState_Unit(EventData);
	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_MindOverMatter'))
		return ELR_NoInterrupt;

	MutableUnit = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', UnitState.ObjectID));
	MutableUnit.SetUnitFloatValue('UT_MindOverMatter_BledOut', 1, eCleanup_BeginTactical);

	return ELR_NoInterrupt;
}
