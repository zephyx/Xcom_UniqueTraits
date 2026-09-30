//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_WeakHeavyWeapons.uc
//  PURPOSE: Discreet's -1 damage penalty on heavy weapons (sniper rifles, cannons).
//---------------------------------------------------------------------------------------
class X2Effect_UT_WeakHeavyWeapons extends X2Effect_Persistent config(UniqueTraits);

var config array<name> HeavyWeaponCategories;
var int DamageReduction;

function int GetAttackingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, const int CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, optional XComGameState NewGameState)
{
	local XComGameState_Item SourceWeapon;
	local X2WeaponTemplate WeaponTemplate;

	SourceWeapon = AbilityState.GetSourceWeapon();
	if (SourceWeapon == none)
		return 0;

	WeaponTemplate = X2WeaponTemplate(SourceWeapon.GetMyTemplate());
	if (WeaponTemplate == none)
		return 0;

	if (default.HeavyWeaponCategories.Find(WeaponTemplate.WeaponCat) != INDEX_NONE)
		return -DamageReduction;

	return 0;
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
