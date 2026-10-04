//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Guard.uc
//  PURPOSE: Guard: -15 aim, +25 aim on overwatch/reaction shots which can crit (base-game effect classes).
//---------------------------------------------------------------------------------------
class UT_Trait_Guard extends UT_TraitBase config(UniqueTraits);

var config int GUARD_AIM, GUARD_OVERWATCH_AIM;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Guard());

	return Templates;
}

// Guard: -15 aim, +25 aim on overwatch/reaction shots and those shots can crit.
static function X2AbilityTemplate Guard()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;
	local X2Effect_ModifyReactionFire ReactionEffect;

	Template = PurePassive('UT_Guard', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_Guard';
	StatEffect.BuildPersistentEffect(1, true, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_Offense, -default.GUARD_AIM);
	Template.AddTargetEffect(StatEffect);

	Template.SetUIStatMarkup(class'XLocalizedData'.default.AimLabel, eStat_Offense, -default.GUARD_AIM);

	ReactionEffect = new class'X2Effect_ModifyReactionFire';
	ReactionEffect.EffectName = 'UT_Guard_Overwatch';
	ReactionEffect.ReactionModifier = default.GUARD_OVERWATCH_AIM;
	ReactionEffect.bAllowCrit = true;
	ReactionEffect.BuildPersistentEffect(1, true, false);
	ReactionEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(ReactionEffect);

	return Template;
}
