//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_WeakPrimaryWeapons.uc
//  PURPOSE: Discreet's malus: abilities fired with the holder's PRIMARY weapon (any category) deal DamageReduction less damage, never below 1.
//           Like X2Effect_UT_PrimaryWeaponMalus it only touches the weapon's own damage: tick effects (poison, burning...) are left
//           alone (UT_EffectHelpers.IsTickDamage). Replaces X2Effect_UT_WeakHeavyWeapons (snipers and cannons only, no minimum), 2026-10-09.
//---------------------------------------------------------------------------------------
class X2Effect_UT_WeakPrimaryWeapons extends X2Effect_Persistent;

var int DamageReduction;

function int GetAttackingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, const int CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, optional XComGameState NewGameState)
{
	if (CurrentDamage <= 1 || AbilityState == none || WeaponDamageEffect == none || class'UT_EffectHelpers'.static.IsTickDamage(AppliedData))
		return 0;

	if (!class'UT_EffectHelpers'.static.IsPrimaryWeaponAbility(AbilityState))
		return 0;

	return -Max(0, Min(DamageReduction, CurrentDamage - 1));
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
