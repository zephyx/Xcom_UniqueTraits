//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_PsiAdept.uc
//  PURPOSE: Psi adept: every 10 points of Psi Offense give 1 armor piercing and every 20 points +1 damage to the primary weapon's attacks
//           (no piercing and no damage bonus against robotic units, which take -20% damage instead). Both are X2Effect_UT_PsiAdept.
//           (The damage TYPE cannot be changed from the attacker's side by any hook of the game, so the trait does not claim psi damage.)
//---------------------------------------------------------------------------------------
class UT_Trait_PsiAdept extends UT_TraitBase config(UniqueTraits);

var config int PSIADEPT_PSI_PER_PIERCE;
var config int PSIADEPT_PSI_PER_DAMAGE;
var config int PSIADEPT_ROBOTIC_DAMAGE_REDUCTION_PCT;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(PsiAdept());

	return Templates;
}

static function X2AbilityTemplate PsiAdept()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_PsiAdept PsiEffect;

	Template = PurePassive('UT_PsiAdept', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	PsiEffect = new class'X2Effect_UT_PsiAdept';
	PsiEffect.EffectName = 'UT_PsiAdept_Effect';
	PsiEffect.PsiPerPierce = default.PSIADEPT_PSI_PER_PIERCE;
	PsiEffect.PsiPerDamage = default.PSIADEPT_PSI_PER_DAMAGE;
	PsiEffect.RoboticDamageReductionPct = default.PSIADEPT_ROBOTIC_DAMAGE_REDUCTION_PCT;
	PsiEffect.BuildPersistentEffect(1, true, false);
	PsiEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(PsiEffect);

	return Template;
}
