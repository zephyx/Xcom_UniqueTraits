//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Nerd.uc
//  PURPOSE: Nerd: +NERD_HACKING_BASE hacking / -NERD_WILL_BASE will, then
//           +NERD_HACKING_PER_RANK hacking / -NERD_WILL_PER_RANK will for every rank gained after the first one. Takes
//           NERD_MELEE_DAMAGE_TAKEN extra damage from melee attacks. Both the fixed and the scaling part are
//           direct, permanent stat mutations, NOT ability effects: a plain X2Effect_PersistentStatChange is
//           mission-scoped (X2Effect_ModifyStats.UnitEndedTacticalPlay un-applies it after every mission), so it
//           would never lower the real Max Will between missions.
//           The stats are brought to what the rank calls for by SyncStats: the target minus the LEDGER of UT_TraitBase.ShiftStat, so it is idempotent (the
//           several 'UnitRankUp' events of a state that ranks up several times do no harm), the trait can be removed at any time with the exact stats back
//           (OnClear = RevertShifts) and a respec (OnStatsReset, or the rookie snapshot test) is absorbed. A rookie gets the fixed part at once (see UT_TraitBase).
//---------------------------------------------------------------------------------------
class UT_Trait_Nerd extends UT_TraitBase config(UniqueTraits);

var config int NERD_HACKING_BASE, NERD_HACKING_PER_RANK;
var config int NERD_WILL_BASE, NERD_WILL_PER_RANK;
var config int NERD_MELEE_DAMAGE_TAKEN;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Nerd());

	return Templates;
}

// The ability is an icon holder plus 2 extra damage taken from melee attacks.
static function X2AbilityTemplate Nerd()
{
	local X2AbilityTemplate Template;
	local X2Effect_MeleeDamageAdjust MeleeEffect;

	Template = PurePassive('UT_Nerd', "img:///UniqueTraits_Icons.UT_Nerd", true);

	MeleeEffect = new class'X2Effect_MeleeDamageAdjust';
	MeleeEffect.EffectName = 'UT_Nerd_MeleeVulnerability';
	MeleeEffect.DamageMod = default.NERD_MELEE_DAMAGE_TAKEN;
	MeleeEffect.BuildPersistentEffect(1, true, false);
	MeleeEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(MeleeEffect);

	return Template;
}

static function bool ShiftsStats()
{
	return true;
}

// The totals the rank calls for: the fixed part at once (a rookie included), plus the per-rank part for every rank after the first one.
static final function bool SyncStats(XComGameState_Unit MutableUnit)
{
	local int Ranks;
	local bool bChanged;

	Ranks = Max(0, MutableUnit.GetRank() - 1);
	bChanged = ShiftStatTo(MutableUnit, eStat_Hacking, default.NERD_HACKING_BASE + Ranks * default.NERD_HACKING_PER_RANK);
	bChanged = ShiftStatTo(MutableUnit, eStat_Will, -(default.NERD_WILL_BASE + Ranks * default.NERD_WILL_PER_RANK)) || bChanged;

	return bChanged;
}

static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	// A unit that had the trait before was cleared by OnClear (which empties the ledger); a soldier who is already ranked (AddUniqueTrait) gets every rank at once.
	SyncStats(MutableUnit);
}

// The trait is already out of AcquiredTraits here: the stats go back to what they were, exactly.
static function OnClear(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	RevertShifts(MutableUnit);
}

// 'UnitRankUp': a real promotion.
static function bool OnRankUp(XComGameState_Unit MutableUnit)
{
	return SyncStats(MutableUnit);
}

// The base stats were rebuilt by a respec: what the trait had put in them is gone.
static function OnStatsReset(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	ForgetShifts(MutableUnit);
	SyncStats(MutableUnit);
}
