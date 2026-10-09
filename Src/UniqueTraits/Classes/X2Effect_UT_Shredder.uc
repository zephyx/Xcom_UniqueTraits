//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_Shredder.uc
//  PURPOSE: Shredder's two damage modifiers, both on the holder as ATTACKER (GetAttackingDamageModifier_CH, which the game also calls for the
//           damage over time of the effects he is the source of):
//           - every tick of an ACID damage over time the holder inflicted (the weapon damage effect is a tick effect, bIgnoreBaseDamage, whose
//             damage type is in AcidDamageTypes) deals AcidTickBonus more damage, whatever applied the acid (his own shred, a grenade...);
//           - his PRIMARY weapon deals UnarmoredMalusPct % less damage (never below 1) to a target that has no armor left.
//---------------------------------------------------------------------------------------
class X2Effect_UT_Shredder extends X2Effect_Persistent;

var int AcidTickBonus;
var int UnarmoredMalusPct;
var array<name> AcidDamageTypes;

function int GetAttackingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, const int CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, optional XComGameState NewGameState)
{
	local XComGameState_Unit Target;

	if (WeaponDamageEffect == none)
		return 0;

	// A tick of a damage over time: only acid gets the bonus.
	if (WeaponDamageEffect.bIgnoreBaseDamage)
	{
		if (AcidDamageTypes.Find(WeaponDamageEffect.EffectDamageValue.DamageType) != INDEX_NONE)
			return AcidTickBonus;

		return 0;
	}

	// The weapon's own damage: the malus against an unarmored target, primary weapon only.
	if (CurrentDamage <= 1 || UnarmoredMalusPct <= 0 || AbilityState == none || !class'UT_EffectHelpers'.static.IsPrimaryWeaponAbility(AbilityState))
		return 0;

	Target = XComGameState_Unit(TargetDamageable);
	if (Target == none || Target.GetArmorMitigationForUnitFlag() > 0)
		return 0;

	return -Max(0, Min(Round(CurrentDamage * UnarmoredMalusPct / 100.0), CurrentDamage - 1));
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
	EffectName = "UT_Shredder_Damage"
}
