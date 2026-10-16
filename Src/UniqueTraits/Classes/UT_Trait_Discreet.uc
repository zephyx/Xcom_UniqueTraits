//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Discreet.uc
//  PURPOSE: Discreet: detection modifier + primary weapons deal 1 less damage, never below 1 (X2Effect_UT_WeakPrimaryWeapons).
//---------------------------------------------------------------------------------------
class UT_Trait_Discreet extends UT_TraitBase config(UniqueTraits);

var config float DISCREET_DETECTION_MULT;
var config int DISCREET_PRIMARY_WEAPON_DAMAGE_REDUCTION;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Discreet());

	return Templates;
}

// Discreet: -20% detection radius; primary weapons deal 1 less damage (never below 1).
static function X2AbilityTemplate Discreet()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;
	local X2Effect_UT_WeakPrimaryWeapons WeakPrimaryEffect;

	Template = PurePassive('UT_Discreet', "img:///UniqueTraits_Icons.UT_Discreet", true);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_Discreet';
	StatEffect.BuildPersistentEffect(1, true, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_DetectionModifier, 1.0 - default.DISCREET_DETECTION_MULT);
	Template.AddTargetEffect(StatEffect);

	WeakPrimaryEffect = new class'X2Effect_UT_WeakPrimaryWeapons';
	WeakPrimaryEffect.EffectName = 'UT_Discreet_WeakPrimaryWeapons';
	WeakPrimaryEffect.DamageReduction = default.DISCREET_PRIMARY_WEAPON_DAMAGE_REDUCTION;
	WeakPrimaryEffect.BuildPersistentEffect(1, true, false);
	WeakPrimaryEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(WeakPrimaryEffect);

	return Template;
}
