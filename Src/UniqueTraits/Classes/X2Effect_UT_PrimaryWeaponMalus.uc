//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_PrimaryWeaponMalus.uc
//  PURPOSE: Maniac explosive's malus: abilities fired with the holder's PRIMARY weapon lose flat BASE damage and critical chance, both by weapon tier.
//           The tier of the weapon is its X2WeaponTemplate.WeaponTech (conventional, laser_lw, magnetic, coilgun_lw, beam), found in WeaponTechs: the
//           index of the tech is the index in DamageByTier / CritByTier. A tech that is not in the list (a weapon of another mod) takes the LAST
//           entry, the heaviest malus. X2WeaponTemplate.Tier is NOT used: LWOTC rewrites it from its ini (conventional 0, laser 150, magnetic 160,
//           coil 170, beam 180), the base game uses 0 / 2 / 4.
//           The damage is never reduced below 1 (a 0 would also hide the damage preview, as it did for Baseball player). Like X2Effect_UT_WeakExplosives it
//           only touches the weapon's own damage: tick effects (poison, burning...) are left alone (UT_EffectHelpers.IsTickDamage). A flat amount of the
//           weapon's BASE damage, so it lives in the PRE-default hook (CHL #923): it runs right after the base damage is computed (weapon damage and spread,
//           +1 rolls, critical or graze, rupture) and BEFORE every flat bonus (HeavyHitter, Psi adept...), which are therefore not reduced.
//---------------------------------------------------------------------------------------
class X2Effect_UT_PrimaryWeaponMalus extends X2Effect_Persistent;

var array<name> WeaponTechs;
var array<int> DamageByTier;
var array<int> CritByTier;

// Index of the weapon's tier for the ability, INDEX_NONE when the ability is not fired with the primary weapon.
function int GetTierIndex(XComGameState_Ability AbilityState)
{
	return class'UT_EffectHelpers'.static.GetPrimaryWeaponTechIndex(AbilityState, WeaponTechs);
}

function float GetPreDefaultAttackingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, float CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, XComGameState NewGameState)
{
	local int Index, Malus;

	if (CurrentDamage <= 1.0 || WeaponDamageEffect == none || class'UT_EffectHelpers'.static.IsTickDamage(AppliedData))
		return 0.0;

	Index = GetTierIndex(AbilityState);
	if (Index == INDEX_NONE || DamageByTier.Length == 0)
		return 0.0;

	Malus = DamageByTier[Clamp(Index, 0, DamageByTier.Length - 1)];
	if (Malus <= 0)
		return 0.0;

	return -FMin(float(Malus), CurrentDamage - 1.0);
}

function GetToHitModifiers(XComGameState_Effect EffectState, XComGameState_Unit Attacker, XComGameState_Unit Target, XComGameState_Ability AbilityState, class<X2AbilityToHitCalc> ToHitType, bool bMelee, bool bFlanking, bool bIndirectFire, out array<ShotModifierInfo> ShotModifiers)
{
	local ShotModifierInfo Modifier;
	local int Index, Malus;

	Index = GetTierIndex(AbilityState);
	if (Index == INDEX_NONE || CritByTier.Length == 0)
		return;

	Malus = CritByTier[Clamp(Index, 0, CritByTier.Length - 1)];
	if (Malus <= 0)
		return;

	Modifier.ModType = eHit_Crit;
	Modifier.Value = -Malus;
	Modifier.Reason = class'UT_TraitBase'.static.GetShotModifierLabel(self);
	ShotModifiers.AddItem(Modifier);
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
