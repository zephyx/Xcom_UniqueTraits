//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Athlete.uc
//  PURPOSE: Athlete: +3 mobility, +15 dodge, -5 aim, -10 crit chance (pure stat passive, base-game effect classes).
//---------------------------------------------------------------------------------------
class UT_Trait_Athlete extends UT_TraitBase config(UniqueTraits);

var config int ATHLETE_MOBILITY, ATHLETE_DODGE, ATHLETE_AIM, ATHLETE_CRIT;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Athlete());

	return Templates;
}

// Athlete: +3 mobility, +15 dodge, -5 aim, -10 crit chance.
static function X2AbilityTemplate Athlete()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;

	Template = PurePassive('UT_Athlete', "img:///UniqueTraits_Icons.UT_Athlete", true);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_Athlete';
	StatEffect.BuildPersistentEffect(1, true, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_Mobility, default.ATHLETE_MOBILITY);
	StatEffect.AddPersistentStatChange(eStat_Dodge, default.ATHLETE_DODGE);
	StatEffect.AddPersistentStatChange(eStat_Offense, -default.ATHLETE_AIM);
	StatEffect.AddPersistentStatChange(eStat_CritChance, -default.ATHLETE_CRIT);
	Template.AddTargetEffect(StatEffect);

	Template.SetUIStatMarkup(class'XLocalizedData'.default.MobilityLabel, eStat_Mobility, default.ATHLETE_MOBILITY);
	Template.SetUIStatMarkup(class'XLocalizedData'.default.DodgeLabel, eStat_Dodge, default.ATHLETE_DODGE);
	Template.SetUIStatMarkup(class'XLocalizedData'.default.AimLabel, eStat_Offense, -default.ATHLETE_AIM);
	Template.SetUIStatMarkup(class'XLocalizedData'.default.CritChanceLabel, eStat_CritChance, -default.ATHLETE_CRIT);

	return Template;
}
