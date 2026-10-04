//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_BaseballPlayer.uc
//  PURPOSE: Baseball player: own explosives deal less damage (X2Effect_UT_WeakExplosives); also grants the base ability Salvo (ini).
//---------------------------------------------------------------------------------------
class UT_Trait_BaseballPlayer extends UT_TraitBase config(UniqueTraits);

var config int BASEBALL_EXPLOSIVE_DAMAGE_REDUCTION;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(BaseballPlayer());

	return Templates;
}

// Baseball player: gains Salvo (granted separately via ini). Own explosives deal 2 less damage.
static function X2AbilityTemplate BaseballPlayer()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_WeakExplosives WeakExplosivesEffect;

	Template = PurePassive('UT_BaseballPlayer', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	WeakExplosivesEffect = new class'X2Effect_UT_WeakExplosives';
	WeakExplosivesEffect.EffectName = 'UT_BaseballPlayer_WeakExplosives';
	WeakExplosivesEffect.DamageReduction = default.BASEBALL_EXPLOSIVE_DAMAGE_REDUCTION;
	WeakExplosivesEffect.BuildPersistentEffect(1, true, false);
	WeakExplosivesEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(WeakExplosivesEffect);

	return Template;
}
