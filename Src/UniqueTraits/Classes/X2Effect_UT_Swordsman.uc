//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_Swordsman.uc
//  PURPOSE: Swordsman's melee damage/armor-pierce bonus (scaled by the melee weapon's Tier) and
//           flat damage malus on firearms.
//---------------------------------------------------------------------------------------
class X2Effect_UT_Swordsman extends X2Effect_Persistent;

// Indexed by X2WeaponTemplate.Tier, clamped to the last entry for anything higher.
var array<int> MeleeBonusByTier;
var int FirearmDamageReduction;

private function int GetMeleeBonus(XComGameState_Ability AbilityState)
{
	local XComGameState_Item SourceWeapon;
	local X2WeaponTemplate WeaponTemplate;
	local int TierIdx;

	if (MeleeBonusByTier.Length == 0)
		return 0;

	SourceWeapon = AbilityState.GetSourceWeapon();
	if (SourceWeapon != none)
		WeaponTemplate = X2WeaponTemplate(SourceWeapon.GetMyTemplate());

	TierIdx = (WeaponTemplate != none) ? WeaponTemplate.Tier : 0;
	TierIdx = Clamp(TierIdx, 0, MeleeBonusByTier.Length - 1);

	return MeleeBonusByTier[TierIdx];
}

// A "firearm" here is any non-melee, non-explosive attack made with a primary or secondary weapon.
private function bool IsFirearmAttack(XComGameState_Ability AbilityState, X2Effect_ApplyWeaponDamage WeaponDamageEffect)
{
	local XComGameState_Item SourceWeapon;
	local X2WeaponTemplate WeaponTemplate;

	if (AbilityState.IsMeleeAbility() || WeaponDamageEffect.bExplosiveDamage)
		return false;

	SourceWeapon = AbilityState.GetSourceWeapon();
	if (SourceWeapon == none)
		return false;

	WeaponTemplate = X2WeaponTemplate(SourceWeapon.GetMyTemplate());
	return WeaponTemplate != none
		&& (WeaponTemplate.InventorySlot == eInvSlot_PrimaryWeapon || WeaponTemplate.InventorySlot == eInvSlot_SecondaryWeapon);
}

function int GetAttackingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, const int CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, optional XComGameState NewGameState)
{
	// Base weapon damage only: skip tick effects (poison, burning, ...), same discriminator as
	// X2Effect_UT_WeakExplosives.
	if (CurrentDamage <= 0 || WeaponDamageEffect == none || WeaponDamageEffect.bIgnoreBaseDamage || AbilityState == none)
		return 0;

	if (AbilityState.IsMeleeAbility())
		return GetMeleeBonus(AbilityState);

	if (IsFirearmAttack(AbilityState, WeaponDamageEffect))
		return -FirearmDamageReduction;

	return 0;
}

function int GetExtraArmorPiercing(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData)
{
	if (AbilityState != none && AbilityState.IsMeleeAbility())
		return GetMeleeBonus(AbilityState);

	return 0;
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
