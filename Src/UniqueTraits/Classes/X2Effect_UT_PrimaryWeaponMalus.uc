//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_PrimaryWeaponMalus.uc
//  PURPOSE: Maniac explosive's malus: abilities fired with the holder's PRIMARY weapon deal DamageReductionPct% less damage, never
//           below 1 (a 0 would also hide the damage preview, as it did for Baseball player). Like X2Effect_UT_WeakExplosives it only
//           touches the weapon's own damage: tick effects (poison, burning...) set bIgnoreBaseDamage.
//---------------------------------------------------------------------------------------
class X2Effect_UT_PrimaryWeaponMalus extends X2Effect_Persistent;

var int DamageReductionPct;

function int GetAttackingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, const int CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, optional XComGameState NewGameState)
{
	local XComGameState_Item SourceWeapon;

	if (CurrentDamage <= 1 || AbilityState == none || WeaponDamageEffect == none || WeaponDamageEffect.bIgnoreBaseDamage)
		return 0;

	SourceWeapon = AbilityState.GetSourceWeapon();
	if (SourceWeapon == none || SourceWeapon.InventorySlot != eInvSlot_PrimaryWeapon)
		return 0;

	return -Max(0, Min(Round(CurrentDamage * DamageReductionPct / 100.0), CurrentDamage - 1));
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
