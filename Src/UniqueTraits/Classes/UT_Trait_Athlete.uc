//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Athlete.uc
//  PURPOSE: Athlete (reworked 2026-10-29, the first version was +3 mobility, +15 dodge, -5 aim, -10 crit as a stat effect):
//           - MOBILITY: +ATHLETE_MOBILITY_BASE when the trait is given, then +ATHLETE_MOBILITY_STEP_1 from the rank ATHLETE_MOBILITY_STEP_1_RANK (LWOTC: 4, Sergeant) and
//             +ATHLETE_MOBILITY_STEP_2 from ATHLETE_MOBILITY_STEP_2_RANK (LWOTC: 7, Gunnery Sergeant). A PERMANENT change of the base stat, not an effect (a plain stat effect is
//             mission-scoped): brought to what the rank calls for by SyncStats, the target minus the LEDGER of UT_TraitBase.ShiftStat, so it is idempotent, removable (OnClear =
//             RevertShifts) and respec-proof (OnStatsReset), like Nerd's. The rank numbers are LWOTC's (the base game has no Gunnery Sergeant: edit the ini).
//           - WALL CLIMBING: X2Effect_PersistentTraversalChange (eTraversal_WallClimb), the base game's class; windows cannot be climbed. Same effect as the ABB Perk Pack's
//             'ABB_Parkour' (workshop 1993868715), without depending on that mod.
//           - AIM MALUS (X2Effect_UT_AthleteCover): -(ATHLETE_COVER_AIM_BASE + ATHLETE_COVER_AIM_PER_RANK x rank) Aim on a ranged shot at a target that can take cover
//             (flankable) and is not flanked, i.e. that has cover against him.
//---------------------------------------------------------------------------------------
class UT_Trait_Athlete extends UT_TraitBase config(UniqueTraits);

var config int ATHLETE_MOBILITY_BASE;
var config int ATHLETE_MOBILITY_STEP_1, ATHLETE_MOBILITY_STEP_1_RANK;
var config int ATHLETE_MOBILITY_STEP_2, ATHLETE_MOBILITY_STEP_2_RANK;
var config int ATHLETE_COVER_AIM_BASE, ATHLETE_COVER_AIM_PER_RANK;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Athlete());

	return Templates;
}

// The ability: wall climbing and the aim malus against a target in cover (the mobility is not an effect, see above).
static function X2AbilityTemplate Athlete()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentTraversalChange ClimbEffect;
	local X2Effect_UT_AthleteCover CoverEffect;

	Template = PurePassive('UT_Athlete', "img:///UniqueTraits_Icons.UT_Athlete", true);

	ClimbEffect = new class'X2Effect_PersistentTraversalChange';
	ClimbEffect.EffectName = 'UT_Athlete_WallClimb';
	ClimbEffect.BuildPersistentEffect(1, true, true, false, eGameRule_PlayerTurnBegin);
	ClimbEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyHelpText(), Template.IconImage, true,, Template.AbilitySourceName);
	ClimbEffect.AddTraversalChange(eTraversal_WallClimb, true);
	ClimbEffect.DuplicateResponse = eDupe_Refresh;
	Template.AddTargetEffect(ClimbEffect);

	CoverEffect = new class'X2Effect_UT_AthleteCover';
	CoverEffect.EffectName = 'UT_Athlete_CoverAim';
	CoverEffect.BuildPersistentEffect(1, true, false);
	CoverEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(CoverEffect);

	return Template;
}

static function bool ShiftsStats()
{
	return true;
}

// The mobility the rank calls for: the base at once (a rookie included), plus a step from each of the two ranks.
static final function bool SyncStats(XComGameState_Unit MutableUnit)
{
	local int Rank, Wanted;

	Rank = MutableUnit.GetRank();
	Wanted = default.ATHLETE_MOBILITY_BASE;
	if (Rank >= default.ATHLETE_MOBILITY_STEP_1_RANK)
		Wanted += default.ATHLETE_MOBILITY_STEP_1;
	if (Rank >= default.ATHLETE_MOBILITY_STEP_2_RANK)
		Wanted += default.ATHLETE_MOBILITY_STEP_2;

	return ShiftStatTo(MutableUnit, eStat_Mobility, Wanted);
}

static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	// A soldier who is already ranked (AddUniqueTrait) gets every step he has reached at once.
	SyncStats(MutableUnit);
}

// The trait is already out of AcquiredTraits here: the mobility goes back to what it was, exactly.
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

// Version 2 (first version: +3 mobility, +15 dodge, -5 aim, -10 crit as a stat effect): the holders get their mobility through the ledger. The effects of the old ability are
// gone with its template, the new ones come with the template at the next mission.
static function OnMigrate(XComGameState_Unit MutableUnit, int FromVersion, XComGameState NewGameState)
{
	if (FromVersion == 1)
		SyncStats(MutableUnit);
}

// The names of the two ranks for the texts (UT_TextTags): the rank name of the base game / LWOTC, or the number when the rank is out of the configured range.
static function bool GetTextValue(string Key, out string OutString)
{
	local int Rank;

	if (Key ~= "ATHLETE_MOBILITY_STEP_1_RANK_NAME")
		Rank = default.ATHLETE_MOBILITY_STEP_1_RANK;
	else if (Key ~= "ATHLETE_MOBILITY_STEP_2_RANK_NAME")
		Rank = default.ATHLETE_MOBILITY_STEP_2_RANK;
	else
		return false;

	if (Rank >= 0 && Rank <= class'X2ExperienceConfig'.static.GetMaxRank())
		OutString = class'X2ExperienceConfig'.static.GetRankName(Rank, '');
	else
		OutString = string(Rank);

	return true;
}
