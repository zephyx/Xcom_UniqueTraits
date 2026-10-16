//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_DamageTakenMult.uc
//  PURPOSE: Quick healing's drawback: the holder takes DamageMultiplier times the damage (1.25 = +25 %), from every source, ticks included. It replaces
//           the base game's X2Effect_ConditionalDamageModifier, which applies its multiplier in the FLAT defender hook (order dependent, rounded at
//           each effect). A percentage belongs in the POST-default hook (CHL #923): it applies to the total once every flat modifier is in, the
//           result does not depend on the order of the effects and CHL truncates the change only once.
//---------------------------------------------------------------------------------------
class X2Effect_UT_DamageTakenMult extends X2Effect_Persistent;

var float DamageMultiplier;

function float GetPostDefaultDefendingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, XComGameState_Unit TargetUnit, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, float CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, XComGameState NewGameState)
{
	local float Modifier;

	if (CurrentDamage <= 0.0)
		return 0.0;

	Modifier = CurrentDamage * (DamageMultiplier - 1.0);
	if (Modifier < 0.0)
		Modifier = -FMax(0.0, FMin(-Modifier, CurrentDamage - 1.0));

	return Modifier;
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
	bDisplayInSpecialDamageMessageUI = true
}
