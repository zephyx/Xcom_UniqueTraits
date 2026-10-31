//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_Coroner.uc
//  PURPOSE: The Coroner's drawback: ALL the damage he deals is lowered by CORONER_DAMAGE_MALUS_PCT percent, and by CORONER_AUTOPSY_DAMAGE_MALUS_PCT more once he has picked up an autopsy
//           in this mission (UnitValue UT_Coroner_Autopsied, set by UT_Trait_Coroner.OnItemLooted_Coroner, cleared when the next mission starts): 20 % in all with the default
//           values, whatever the number of autopsies. A percentage, so it lives in the POST-default hook (CHL #923): it applies to the total once every flat bonus is in, never
//           below 1 damage. Ticks of damage over time are included ("all damage"). The numbers are read live from the class defaults (ini or Mod Config Menu).
//---------------------------------------------------------------------------------------
class X2Effect_UT_Coroner extends X2Effect_Persistent;

function float GetPostDefaultAttackingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, float CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, XComGameState NewGameState)
{
	local float Percent, Modifier;

	if (CurrentDamage <= 0.0)
		return 0.0;

	Percent = float(class'UT_Trait_Coroner'.default.CORONER_DAMAGE_MALUS_PCT);
	if (class'UT_TraitBase'.static.GetUnitFloat(Attacker, 'UT_Coroner_Autopsied') > 0.0)
		Percent += float(class'UT_Trait_Coroner'.default.CORONER_AUTOPSY_DAMAGE_MALUS_PCT);

	// Only a share of the malus with a heavy primary weapon (the Coroner's rule: light primary = the full trait), evaluated at each attack from what he carries now.
	Percent = Percent * float(class'UT_Trait_Coroner'.static.GetWeaponFactorPct(Attacker)) / 100.0;

	if (Percent <= 0.0)
		return 0.0;

	Modifier = -FMax(0.0, FMin(CurrentDamage * Percent / 100.0, CurrentDamage - 1.0));

	return Modifier;
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
	bDisplayInSpecialDamageMessageUI = true
}
