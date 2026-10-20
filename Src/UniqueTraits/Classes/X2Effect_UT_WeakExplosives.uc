//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_WeakExplosives.uc
//  PURPOSE: Baseball player's own explosives (grenades, rockets, etc.) deal 2 less explosive damage, never reduced below 1.
//---------------------------------------------------------------------------------------
class X2Effect_UT_WeakExplosives extends X2Effect_Persistent;

var int DamageReduction;

function int GetAttackingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, const int CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, optional XComGameState NewGameState)
{
	// Only the explosion's own base damage: skip nothing-to-reduce cases and tick effects
	// (poison, burning, ...), told by UT_EffectHelpers.IsTickDamage (LWOTC's HeavyFrags uses
	// bIgnoreBaseDamage, X2Effect_GrenadeDamage, ApplyToNonBaseDamage=false).
	if (CurrentDamage <= 0 || WeaponDamageEffect == none || class'UT_EffectHelpers'.static.IsTickDamage(AppliedData))
		return 0;

	if (!WeaponDamageEffect.bExplosiveDamage)
		return 0;

	// Never reduce below 1 damage (also: a 0 minimum made the damage preview show nothing for a 2-5 frag grenade).
	return -Max(0, Min(DamageReduction, CurrentDamage - 1));
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
