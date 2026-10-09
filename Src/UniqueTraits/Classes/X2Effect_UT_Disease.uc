//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_Disease.uc
//  PURPOSE: Chemist's "disease" on an enemy: -DiseaseAim aim (the stat change, added by the trait) and DamageReduction less damage on its
//           attacks, never below 1. Like X2Effect_UT_PrimaryWeaponMalus it only touches the weapon's own damage: tick effects set
//           bIgnoreBaseDamage and are left alone.
//---------------------------------------------------------------------------------------
class X2Effect_UT_Disease extends X2Effect_PersistentStatChange;

var int DamageReduction;

function int GetAttackingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, const int CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, optional XComGameState NewGameState)
{
	if (CurrentDamage <= 1 || WeaponDamageEffect == none || WeaponDamageEffect.bIgnoreBaseDamage)
		return 0;

	return -Min(DamageReduction, CurrentDamage - 1);
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
