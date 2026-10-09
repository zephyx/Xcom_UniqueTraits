//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_PsiAdept.uc
//  PURPOSE: Psi adept's two numbers, both only for attacks made with the holder's PRIMARY weapon:
//           - armor piercing: 1 per PsiPerPierce points of the holder's Psi Offense (GetExtraArmorPiercing), not against a ROBOTIC target;
//           - damage (GetAttackingDamageModifier_CH; tick effects set bIgnoreBaseDamage and are left alone, like
//             X2Effect_UT_PrimaryWeaponMalus): +1 per PsiPerDamage points of Psi Offense, but against a ROBOTIC target no bonus and
//             -RoboticDamageReductionPct % instead (never below 1).
//---------------------------------------------------------------------------------------
class X2Effect_UT_PsiAdept extends X2Effect_Persistent;

var int PsiPerPierce;
var int PsiPerDamage;
var int RoboticDamageReductionPct;

function int GetExtraArmorPiercing(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData)
{
	local XComGameState_Unit Target;

	Target = XComGameState_Unit(TargetDamageable);
	if (PsiPerPierce <= 0 || Attacker == none || (Target != none && Target.IsRobotic()) || !class'UT_EffectHelpers'.static.IsPrimaryWeaponAbility(AbilityState))
		return 0;

	return int(Attacker.GetCurrentStat(eStat_PsiOffense)) / PsiPerPierce;
}

function int GetAttackingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, const int CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, optional XComGameState NewGameState)
{
	local XComGameState_Unit Target;

	Target = XComGameState_Unit(TargetDamageable);

	if (CurrentDamage <= 0 || Attacker == none || WeaponDamageEffect == none || WeaponDamageEffect.bIgnoreBaseDamage || !class'UT_EffectHelpers'.static.IsPrimaryWeaponAbility(AbilityState))
		return 0;
	if (Target == none)
		return 0;

	if (!Target.IsRobotic())
		return PsiPerDamage > 0 ? int(Attacker.GetCurrentStat(eStat_PsiOffense)) / PsiPerDamage : 0;

	if (CurrentDamage <= 1)
		return 0;

	return -Max(0, Min(Round(CurrentDamage * RoboticDamageReductionPct / 100.0), CurrentDamage - 1));
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
