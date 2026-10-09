//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Nerd.uc
//  PURPOSE: Nerd: +NERD_HACKING_BASE hacking / -NERD_WILL_BASE will at assignment, then
//           +NERD_HACKING_PER_RANK hacking / -NERD_WILL_PER_RANK will on every rank gained after that. Takes
//           NERD_MELEE_DAMAGE_TAKEN extra damage from melee attacks. Both the fixed and the scaling part are
//           direct, permanent stat mutations, NOT ability effects: a plain X2Effect_PersistentStatChange is
//           mission-scoped (X2Effect_ModifyStats.UnitEndedTacticalPlay un-applies it after every mission), so it
//           would never lower the real Max Will between missions. The UT_Nerd_RanksScaled UnitValue counts the
//           per-rank increments only so OnClear can reverse the exact cumulative total.
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

	Template = PurePassive('UT_Nerd', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	MeleeEffect = new class'X2Effect_MeleeDamageAdjust';
	MeleeEffect.EffectName = 'UT_Nerd_MeleeVulnerability';
	MeleeEffect.DamageMod = default.NERD_MELEE_DAMAGE_TAKEN;
	MeleeEffect.BuildPersistentEffect(1, true, false);
	MeleeEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(MeleeEffect);

	return Template;
}

static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	local int i;

	ShiftStat(MutableUnit, eStat_Hacking, default.NERD_HACKING_BASE);
	ShiftStat(MutableUnit, eStat_Will, -default.NERD_WILL_BASE);

	// Reset OnRankUp's cumulative counter in case this unit had Nerd before, was cleared, and is now
	// getting it again (OnClear already resets it, this is just defensive).
	MutableUnit.SetUnitFloatValue('UT_Nerd_RanksScaled', 0, eCleanup_Never);

	// AddUniqueTrait on an already-ranked soldier must apply every rank gained since rank 1 (a natural
	// promotion grants at rank 1, nothing to catch up).
	for (i = 1; i < MutableUnit.GetRank(); ++i)
		OnRankUp(MutableUnit);
}

static function OnClear(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	local UnitValue RanksScaledValue;
	local int RanksScaled;

	// Fixed part.
	ShiftStat(MutableUnit, eStat_Hacking, -default.NERD_HACKING_BASE);
	ShiftStat(MutableUnit, eStat_Will, default.NERD_WILL_BASE);

	// Cumulative per-rank total: RanksScaled (incremented once per OnRankUp) is the exact count of
	// increments applied since assignment, multiply back out and undo in one shot.
	RanksScaled = 0;
	if (MutableUnit.GetUnitValue('UT_Nerd_RanksScaled', RanksScaledValue))
		RanksScaled = int(RanksScaledValue.fValue);

	if (RanksScaled > 0)
	{
		ShiftStat(MutableUnit, eStat_Hacking, -(RanksScaled * default.NERD_HACKING_PER_RANK));
		ShiftStat(MutableUnit, eStat_Will, RanksScaled * default.NERD_WILL_PER_RANK);
	}
	MutableUnit.SetUnitFloatValue('UT_Nerd_RanksScaled', 0, eCleanup_Never);
}

// Called from 'UnitRankUp' for every rank gained AFTER the one that granted the trait (rank 1). Military
// rank-ups fire the event exactly once per rank gained, so it just adds the flat per-rank delta every call.
static function OnRankUp(XComGameState_Unit UnitState)
{
	local UnitValue RanksScaledValue;
	local int RanksScaled;

	ShiftStat(UnitState, eStat_Hacking, default.NERD_HACKING_PER_RANK);
	ShiftStat(UnitState, eStat_Will, -default.NERD_WILL_PER_RANK);

	RanksScaled = 0;
	if (UnitState.GetUnitValue('UT_Nerd_RanksScaled', RanksScaledValue))
		RanksScaled = int(RanksScaledValue.fValue);
	UnitState.SetUnitFloatValue('UT_Nerd_RanksScaled', RanksScaled + 1, eCleanup_Never);
}
