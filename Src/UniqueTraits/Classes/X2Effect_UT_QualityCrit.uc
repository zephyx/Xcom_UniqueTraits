//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_QualityCrit.uc
//  PURPOSE: Quality over quantity's critical chance: abilities fired with the holder's PRIMARY weapon get a bonus critical chance
//           that depends on the weapon's Tier (CritByTier, indexed by X2WeaponTemplate.Tier, clamped to the last entry).
//---------------------------------------------------------------------------------------
class X2Effect_UT_QualityCrit extends X2Effect_Persistent;

var array<int> CritByTier;

function GetToHitModifiers(XComGameState_Effect EffectState, XComGameState_Unit Attacker, XComGameState_Unit Target, XComGameState_Ability AbilityState, class<X2AbilityToHitCalc> ToHitType, bool bMelee, bool bFlanking, bool bIndirectFire, out array<ShotModifierInfo> ShotModifiers)
{
	local ShotModifierInfo Modifier;
	local XComGameState_Item SourceWeapon;
	local X2WeaponTemplate WeaponTemplate;
	local int Bonus;

	if (AbilityState == none || CritByTier.Length == 0 || !class'UT_EffectHelpers'.static.IsPrimaryWeaponAbility(AbilityState))
		return;

	SourceWeapon = AbilityState.GetSourceWeapon();
	WeaponTemplate = X2WeaponTemplate(SourceWeapon.GetMyTemplate());
	if (WeaponTemplate == none)
		return;

	Bonus = CritByTier[Clamp(WeaponTemplate.Tier, 0, CritByTier.Length - 1)];
	if (Bonus <= 0)
		return;

	Modifier.ModType = eHit_Crit;
	Modifier.Value = Bonus;
	Modifier.Reason = class'UT_TraitBase'.static.GetShotModifierLabel(self);
	ShotModifiers.AddItem(Modifier);
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
