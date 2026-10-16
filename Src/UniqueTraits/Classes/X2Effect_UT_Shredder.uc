//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_Shredder.uc
//  PURPOSE: Shredder's two damage modifiers, both on the holder as ATTACKER (GetAttackingDamageModifier_CH, which the game also calls for the
//           damage over time of the effects he is the source of):
//           - every tick of an ACID damage over time the holder inflicted (the weapon damage effect is a tick effect, bIgnoreBaseDamage, whose
//             damage type is in AcidDamageTypes) deals AcidTickBonus more damage, whatever applied the acid (his own shred, a grenade...): a FLAT
//             bonus, GetAttackingDamageModifier_CH.
//           - His PRIMARY weapon deals UnarmoredMalusPct % less damage (never below 1) to a target that has no armor left: a percentage, so in the
//             POST-default hook (GetPostDefaultAttackingDamageModifier_CH, CHL #923), applied to the total once every flat bonus is in, whatever
//             the order of the effects.
//---------------------------------------------------------------------------------------
class X2Effect_UT_Shredder extends X2Effect_Persistent;

var int AcidTickBonus;
var int UnarmoredMalusPct;
var array<name> AcidDamageTypes;

function int GetAttackingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, const int CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, optional XComGameState NewGameState)
{
	// A tick of a damage over time: only acid gets the bonus.
	if (WeaponDamageEffect != none && WeaponDamageEffect.bIgnoreBaseDamage && AcidDamageTypes.Find(WeaponDamageEffect.EffectDamageValue.DamageType) != INDEX_NONE)
		return AcidTickBonus;

	return 0;
}

// The weapon's own damage: the malus against an unarmored target, primary weapon only. A percentage of the total, never rounded here (CHL
// truncates the change once at the end of the stage), never leaves less than 1.
function float GetPostDefaultAttackingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, float CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, XComGameState NewGameState)
{
	local XComGameState_Unit Target;

	if (WeaponDamageEffect == none || WeaponDamageEffect.bIgnoreBaseDamage)
		return 0.0;

	if (CurrentDamage <= 1.0 || UnarmoredMalusPct <= 0 || AbilityState == none || !class'UT_EffectHelpers'.static.IsPrimaryWeaponAbility(AbilityState))
		return 0.0;

	Target = XComGameState_Unit(TargetDamageable);
	if (Target == none || Target.GetArmorMitigationForUnitFlag() > 0)
		return 0.0;

	return -FMax(0.0, FMin(CurrentDamage * UnarmoredMalusPct / 100.0, CurrentDamage - 1.0));
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
	EffectName = "UT_Shredder_Damage"
}
