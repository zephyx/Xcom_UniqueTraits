//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Pacifist.uc
//  PURPOSE: Pacifist: -aim attacking and +defense defending, both only against non-robotic units (X2Effect_UT_OrganicCombat).
//---------------------------------------------------------------------------------------
class UT_Trait_Pacifist extends UT_TraitBase config(UniqueTraits);

var config int PACIFIST_AIM, PACIFIST_ORGANIC_DEFENSE;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Pacifist());

	return Templates;
}

// Pacifist: -20 aim attacking a biological target, +30 defense against a biological enemy
static function X2AbilityTemplate Pacifist()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_OrganicCombat CombatEffect;

	Template = PurePassive('UT_Pacifist', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	CombatEffect = new class'X2Effect_UT_OrganicCombat';
	CombatEffect.EffectName = 'UT_Pacifist_OrganicCombat';
	CombatEffect.AimMalus = default.PACIFIST_AIM;
	CombatEffect.DefenseBonus = default.PACIFIST_ORGANIC_DEFENSE;
	CombatEffect.BuildPersistentEffect(1, true, false);
	CombatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(CombatEffect);

	return Template;
}
