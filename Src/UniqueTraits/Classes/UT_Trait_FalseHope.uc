//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_FalseHope.uc
//  PURPOSE: False Hope: +FALSEHOPE_AIM_BASE aim / +FALSEHOPE_HP_BASE HP at assignment, then
//           -FALSEHOPE_AIM_PER_RANK aim / -FALSEHOPE_HP_PER_RANK HP per rank gained after that (the HP bonus
//           floors at FALSEHOPE_HP_FLOOR, it never becomes a malus). The ability is a bare icon holder: the stat
//           changes are permanent direct mutations (OnGrant / OnRankUp, reversed in OnClear), and the XP malus
//           is UT_Trait_FalseHope.OnDistributeTacticalGameEndXp.
//---------------------------------------------------------------------------------------
class UT_Trait_FalseHope extends UT_TraitBase config(UniqueTraits);

var config int FALSEHOPE_XP_REDUCTION_PCT;

var config int FALSEHOPE_AIM_BASE;
var config float FALSEHOPE_HP_BASE;
var config float FALSEHOPE_AIM_PER_RANK;
var config float FALSEHOPE_HP_PER_RANK;
var config float FALSEHOPE_HP_FLOOR;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(PurePassive('UT_FalseHope', "img:///UniqueTraits_Icons.UT_FalseHope", true));

	return Templates;
}

static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	local int i;

	ShiftFalseHopeStats(MutableUnit, default.FALSEHOPE_AIM_BASE, default.FALSEHOPE_HP_BASE);
	MutableUnit.SetUnitFloatValue('UT_FalseHope_RanksScaled', 0, eCleanup_Never);

	// Baseline for the LWOTC part of the XP malus (OnDistributeTacticalGameEndXp_FalseHopeXp): the
	// mission experience the soldier already has is NOT reduced, only what is added from now on.
	MutableUnit.SetUnitFloatValue('UT_FalseHope_MissionXpSeen', GetUnitFloat(MutableUnit, 'MissionExperience'), eCleanup_Never);

	// A natural promotion grants the trait at rank 1 (nothing to catch up); AddUniqueTrait on an
	// already-ranked soldier must apply every rank gained since, as if it had held the trait from rank 1.
	for (i = 1; i < MutableUnit.GetRank(); ++i)
		OnRankUp(MutableUnit);
}

// Reverses the permanent mutation: base part plus the per-rank decay applied so far.
static function OnClear(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	local int RanksScaled;

	RanksScaled = int(GetUnitFloat(MutableUnit, 'UT_FalseHope_RanksScaled'));

	ShiftFalseHopeStats(MutableUnit,
		-(default.FALSEHOPE_AIM_BASE - RanksScaled * default.FALSEHOPE_AIM_PER_RANK),
		-GetFalseHopeHPDelta(RanksScaled));
	MutableUnit.SetUnitFloatValue('UT_FalseHope_RanksScaled', 0, eCleanup_Never);
	MutableUnit.SetUnitFloatValue('UT_FalseHope_MissionXpSeen', 0, eCleanup_Never);
}

static function OnRankUp(XComGameState_Unit UnitState)
{
	local int RanksScaled;

	RanksScaled = int(GetUnitFloat(UnitState, 'UT_FalseHope_RanksScaled'));

	ShiftFalseHopeStats(UnitState, -default.FALSEHOPE_AIM_PER_RANK,
		GetFalseHopeHPDelta(RanksScaled + 1) - GetFalseHopeHPDelta(RanksScaled));
	UnitState.SetUnitFloatValue('UT_FalseHope_RanksScaled', RanksScaled + 1, eCleanup_Never);
}

// Total HP delta after N ranks gained since assignment: starts at FALSEHOPE_HP_BASE, loses
// FALSEHOPE_HP_PER_RANK per rank, never goes below FALSEHOPE_HP_FLOOR (0: the decay only cancels the
// bonus, it never turns it into an HP malus).
static final function float GetFalseHopeHPDelta(int RanksScaled)
{
	return FMax(default.FALSEHOPE_HP_BASE - RanksScaled * default.FALSEHOPE_HP_PER_RANK, default.FALSEHOPE_HP_FLOOR);
}

// Adds (or, with negative values, removes) aim and HP on both max and current stat. Current HP never drops below 1.
static final function ShiftFalseHopeStats(XComGameState_Unit UnitState, float AimDelta, float HPDelta)
{
	ShiftStat(UnitState, eStat_Offense, AimDelta);
	ShiftStat(UnitState, eStat_HP, HPDelta);

	if (UnitState.GetCurrentStat(eStat_HP) < 1)
		UnitState.SetCurrentStat(eStat_HP, 1);
}

// False Hope's XP malus: the holder earns FALSEHOPE_XP_REDUCTION_PCT% less experience, from the
// missions AFTER the trait was granted (the trait is drawn by OnPostMission, once the mission that made
// the rookie eligible is over, and UT_FalseHope_MissionXpSeen is baselined then). Two experience systems:
//
// 1. Vanilla full XP system: the XP manager fires 'OnDistributeTacticalGameEndXp' BEFORE distributing
//    (with the NewGameState that holds the result), so nothing can be scaled yet; this runs
//    ELD_OnStateSubmitted and the gain is the XP difference against the unit's previous version.
// 2. LWOTC (bUseFullXpSystem=false in its XComGameData_XpData.ini: vanilla distributes NO XP, rank-ups
//    depend on kills only): LWOTC's own listener for the same event (priority 90, so it runs BEFORE this
//    one at priority 50, larger numbers run first) adds the mission's "experience" to the soldier's
//    'MissionExperience' UnitValue in a transaction of its own, which LWOTC later turns into kill
//    equivalents ('OverrideTotalNumKills'). Only the NAME of that value is used here (no LW_Overhaul
//    class referenced). The gain is MissionExperience minus UT_FalseHope_MissionXpSeen, the amount already
//    accounted for; the reduction is removed from both, so the pair stays in sync and a missed or
//    reordered run just defers the malus to the next one instead of double counting.
//
// Without LWOTC the MissionExperience value never exists (0 forever): that part is a no-op.
// The reductions go in one follow-up transaction. A rank-up is never granted by this (promotion is a
// manual Armory action), so removing experience afterwards is safe.
static function EventListenerReturn OnDistributeTacticalGameEndXp(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Unit> Soldiers;
	local XComGameState_Unit Soldier, XpStateUnit, PreviousUnitState, MutableUnit;
	local array<int> UnitIDs, XpReductions;
	local array<float> ExperienceTotals, ExperienceReductions;
	local XComGameState NewGameState;
	local int XpGained, XpReduction, i;
	local float ExperienceTotal, ExperienceGained, ExperienceReduction;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	Soldiers = XComHQ.GetSoldiers();
	foreach Soldiers(Soldier)
	{
		if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Soldier, 'UT_FalseHope'))
			continue;

		// 1. Vanilla XP gained in the state that was just submitted (none when the unit isn't in it).
		XpReduction = 0;
		XpStateUnit = XComGameState_Unit(GameState.GetGameStateForObjectID(Soldier.ObjectID));
		if (XpStateUnit != none)
		{
			PreviousUnitState = XComGameState_Unit(XpStateUnit.GetPreviousVersion());
			if (PreviousUnitState != none)
			{
				XpGained = XpStateUnit.GetXPValue() - PreviousUnitState.GetXPValue();
				XpReduction = Round(XpGained * default.FALSEHOPE_XP_REDUCTION_PCT / 100.0);
			}
		}

		// 2. LWOTC mission experience added since the last time it was accounted for.
		ExperienceTotal = GetUnitFloat(Soldier, 'MissionExperience');
		ExperienceGained = ExperienceTotal - GetUnitFloat(Soldier, 'UT_FalseHope_MissionXpSeen');
		ExperienceReduction = 0;
		if (ExperienceGained > 0)
			ExperienceReduction = ExperienceGained * default.FALSEHOPE_XP_REDUCTION_PCT / 100.0;

		if (XpReduction > 0 || ExperienceReduction > 0)
		{
			UnitIDs.AddItem(Soldier.ObjectID);
			XpReductions.AddItem(XpReduction);
			ExperienceTotals.AddItem(ExperienceTotal);
			ExperienceReductions.AddItem(ExperienceReduction);
			`log("UniqueTraits : False Hope XP malus for" @ Soldier.GetFullName()
				@ "-- XP gained" @ XpGained @ "(removing" @ XpReduction $ "), LWOTC mission experience gained" @ ExperienceGained
				@ "(removing" @ ExperienceReduction $ ")",, 'UniqueTraits');
		}
	}

	if (UnitIDs.Length == 0)
		return ELR_NoInterrupt;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: False Hope XP malus");
	for (i = 0; i < UnitIDs.Length; ++i)
	{
		MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', UnitIDs[i]));
		if (XpReductions[i] > 0)
			MutableUnit.AddXp(-XpReductions[i]);

		if (ExperienceReductions[i] > 0)
		{
			MutableUnit.SetUnitFloatValue('MissionExperience', ExperienceTotals[i] - ExperienceReductions[i], eCleanup_Never);
			MutableUnit.SetUnitFloatValue('UT_FalseHope_MissionXpSeen', ExperienceTotals[i] - ExperienceReductions[i], eCleanup_Never);
		}
	}
	`GAMERULES.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}
