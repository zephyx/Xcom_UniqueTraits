//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Acrobat.uc
//  PURPOSE: Acrobat: -aim/-crit attacking a lower target (X2Effect_UT_AcrobatMalus); also grants the Skirmisher's Grapple, SkirmisherGrapple (ini).
//---------------------------------------------------------------------------------------
class UT_Trait_Acrobat extends UT_TraitBase config(UniqueTraits);

var config int ACROBAT_AIM_PENALTY, ACROBAT_CRIT_PENALTY;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Acrobat());

	return Templates;
}

// Acrobat: grants SkirmisherGrapple (cd 3) -10 aim/-10 crit attacking a target below their own elevation.
static function X2AbilityTemplate Acrobat()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_AcrobatMalus MalusEffect;

	Template = PurePassive('UT_Acrobat', "img:///UniqueTraits_Icons.UT_Acrobat", true);

	MalusEffect = new class'X2Effect_UT_AcrobatMalus';
	MalusEffect.EffectName = 'UT_Acrobat_Malus';
	MalusEffect.AimPenalty = default.ACROBAT_AIM_PENALTY;
	MalusEffect.CritPenalty = default.ACROBAT_CRIT_PENALTY;
	MalusEffect.BuildPersistentEffect(1, true, false);
	MalusEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(MalusEffect);

	return Template;
}
