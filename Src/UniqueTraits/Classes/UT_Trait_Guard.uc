//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Guard.uc
//  PURPOSE: Guard (reworked 2026-10-30): -GUARD_AIM_PER_RANK Aim per rank on every attack, +GUARD_OVERWATCH_AIM_PER_RANK Aim per rank on every
//           overwatch/reaction attack, ranged or melee (any ability whose to-hit calc has bReactionFire), which can crit. Both scale with the holder's rank, so a
//           rookie has neither. All in X2Effect_UT_Guard (a subclass of the base game's X2Effect_ModifyReactionFire).
//---------------------------------------------------------------------------------------
class UT_Trait_Guard extends UT_TraitBase config(UniqueTraits);

var config int GUARD_AIM_PER_RANK, GUARD_OVERWATCH_AIM_PER_RANK;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Guard());

	return Templates;
}

static function X2AbilityTemplate Guard()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_Guard GuardEffect;

	Template = PurePassive('UT_Guard', "img:///UniqueTraits_Icons.UT_Guard", true);

	GuardEffect = new class'X2Effect_UT_Guard';
	GuardEffect.EffectName = 'UT_Guard_Effect';
	GuardEffect.AimPenaltyPerRank = default.GUARD_AIM_PER_RANK;
	GuardEffect.ReactionAimPerRank = default.GUARD_OVERWATCH_AIM_PER_RANK;
	GuardEffect.bAllowCrit = true;
	GuardEffect.BuildPersistentEffect(1, true, false);
	GuardEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(GuardEffect);

	return Template;
}
