//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_LongRange.uc
//  PURPOSE: Long Range: far-range shift and close-range malus (X2Effect_UT_LongRange).
//---------------------------------------------------------------------------------------
class UT_Trait_LongRange extends UT_TraitBase config(UniqueTraits);

var config int LONGRANGE_FAR_RANGE_SHIFT;
var config array<int> LONGRANGE_CLOSE_RANGE_AIM_PENALTY;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(LongRange());

	return Templates;
}

// Long Range: see X2Effect_UT_LongRange.
static function X2AbilityTemplate LongRange()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_LongRange RangeEffect;

	Template = PurePassive('UT_LongRange', "img:///UniqueTraits_Icons.UT_LongRange", true);

	RangeEffect = new class'X2Effect_UT_LongRange';
	RangeEffect.EffectName = 'UT_LongRange_Effect';
	RangeEffect.FarRangeShift = default.LONGRANGE_FAR_RANGE_SHIFT;
	RangeEffect.CloseRangeAimPenalty = default.LONGRANGE_CLOSE_RANGE_AIM_PENALTY;
	RangeEffect.BuildPersistentEffect(1, true, false);
	RangeEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(RangeEffect);

	return Template;
}
