//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Discreet.uc
//  PURPOSE: Discreet: detection modifier + heavy weapons deal less damage (X2Effect_UT_WeakHeavyWeapons).
//---------------------------------------------------------------------------------------
class UT_Trait_Discreet extends UT_TraitBase config(UniqueTraits);

var config float DISCREET_DETECTION_MULT;
var config int DISCREET_HEAVY_WEAPON_DAMAGE_REDUCTION;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Discreet());

	return Templates;
}

// Discreet: -20% detection radius; heavy weapons (sniper rifles, cannons) deal 1 less damage.
static function X2AbilityTemplate Discreet()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;
	local X2Effect_UT_WeakHeavyWeapons WeakHeavyEffect;

	Template = PurePassive('UT_Discreet', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_Discreet';
	StatEffect.BuildPersistentEffect(1, true, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_DetectionModifier, 1.0 - default.DISCREET_DETECTION_MULT);
	Template.AddTargetEffect(StatEffect);

	WeakHeavyEffect = new class'X2Effect_UT_WeakHeavyWeapons';
	WeakHeavyEffect.EffectName = 'UT_Discreet_WeakHeavyWeapons';
	WeakHeavyEffect.DamageReduction = default.DISCREET_HEAVY_WEAPON_DAMAGE_REDUCTION;
	WeakHeavyEffect.BuildPersistentEffect(1, true, false);
	WeakHeavyEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(WeakHeavyEffect);

	return Template;
}
