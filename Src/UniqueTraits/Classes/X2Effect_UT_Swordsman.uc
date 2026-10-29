//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_Swordsman.uc
//  PURPOSE: Swordsman's melee bonuses, which come with the soldier's RANK:
//           - from PierceRank: +PierceBonus armor piercing on melee attacks;
//           - from MinDamageRank: the damage of a melee attack can not be lower than (the weapon's minimum + MinDamageBonus): a 4-6 weapon becomes 5-6, a weapon
//             without spread (5-5) becomes 6-6. A floor on the roll, in the PRE-default hook (the base damage is rolled and no flat bonus is in yet), computed from the
//             weapon's own damage and spread (GetBaseWeaponDamageValue + the ability's bonus damage; upgrades and ammo are not counted);
//           - from DamageRank: +DamageBonus melee damage, flat.
//           The three ranks are read from the class defaults when used (not copied at startup), so the Mod Config Menu changes them at once and the rank names in the
//           texts, which are computed live, stay right.
//           "Melee" includes abilities that strike with a DeadEye calc but move to the target (see IsMeleeLike).
//           And a malus: -FirearmDamageReduction on firearm attacks while the soldier carries a MELEE weapon in his primary or secondary slot (WeaponCat in
//           MeleeWeaponCats); melee damage is never reduced. The +1 Mobility is a plain stat effect of the passive (UT_Trait_Swordsman).
//---------------------------------------------------------------------------------------
class X2Effect_UT_Swordsman extends X2Effect_Persistent;

var int PierceBonus, MinDamageBonus, DamageBonus;
var int FirearmDamageReduction;
// X2WeaponTemplate.WeaponCat of the weapons that count as "a melee weapon" for the firearm malus.
var array<name> MeleeWeaponCats;

// A melee attack for Swordsman. XComGameState_Ability.IsMeleeAbility() only knows the abilities whose to-hit calc is a StandardAim with bMeleeAttack (StandardMelee), so an
// ability that moves to its target and strikes with a plain DeadEye calc is missed (ABB Arsenal's Body Harvest: it took the firearm malus): such an
// ability is recognised by its target style (X2AbilityTarget_MovingMelee) or its targeting method (X2TargetingMethod_MeleePath, which every melee path attack uses).
private function bool IsMeleeLike(XComGameState_Ability AbilityState)
{
	local X2AbilityTemplate Template;

	if (AbilityState.IsMeleeAbility())
		return true;

	Template = AbilityState.GetMyTemplate();
	if (Template == none)
		return false;

	return X2AbilityTarget_MovingMelee(Template.AbilityTargetStyle) != none
		|| (Template.TargetingMethod != none && ClassIsChildOf(Template.TargetingMethod, class'X2TargetingMethod_MeleePath'));
}

// A "firearm" here is any non-melee, non-explosive attack made with a primary or secondary weapon.
private function bool IsFirearmAttack(XComGameState_Ability AbilityState, X2Effect_ApplyWeaponDamage WeaponDamageEffect)
{
	local XComGameState_Item SourceWeapon;
	local X2WeaponTemplate WeaponTemplate;

	if (IsMeleeLike(AbilityState) || WeaponDamageEffect.bExplosiveDamage)
		return false;

	SourceWeapon = AbilityState.GetSourceWeapon();
	if (SourceWeapon == none)
		return false;

	WeaponTemplate = X2WeaponTemplate(SourceWeapon.GetMyTemplate());
	return WeaponTemplate != none
		&& (WeaponTemplate.InventorySlot == eInvSlot_PrimaryWeapon || WeaponTemplate.InventorySlot == eInvSlot_SecondaryWeapon);
}

private function bool IsMeleeWeapon(XComGameState_Item Item)
{
	local X2WeaponTemplate WeaponTemplate;

	if (Item == none)
		return false;

	WeaponTemplate = X2WeaponTemplate(Item.GetMyTemplate());
	return WeaponTemplate != none && MeleeWeaponCats.Find(WeaponTemplate.WeaponCat) != INDEX_NONE;
}

private function bool CarriesMeleeWeapon(XComGameState_Unit Unit)
{
	return IsMeleeWeapon(Unit.GetPrimaryWeapon()) || IsMeleeWeapon(Unit.GetSecondaryWeapon());
}

// Pre-default hook: the melee roll is raised to the floor (weapon minimum + MinDamageBonus). The damage preview calls it for the minimum and for the maximum, so the
// minimum shown follows (and a weapon without spread shows +MinDamageBonus on both).
// The game adds the critical damage to the roll BEFORE this hook, so on a critical hit (AppliedData.AbilityResultContext.HitResult, also set by the previews that
// compute a critical hit, Extended Information Redux 3's "critical damage" list) the floor includes the weapon's critical damage: the floor applies to the roll in
// both cases and a critical hit keeps its full bonus over a normal one. Without it the critical hit was never raised while the normal one was, and the preview showed
// "Swordsman -1 - 0" in the critical damage list. Only the weapon's own critical damage and the ability's bonus damage are counted
// (upgrades and ammo are not), like the minimum itself.
function float GetPreDefaultAttackingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, float CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, XComGameState NewGameState)
{
	local XComGameState_Item SourceWeapon;
	local WeaponDamageValue BaseDamage, BonusDamage;
	local float WantedMin;

	if (MinDamageBonus <= 0 || Attacker == none || Attacker.GetRank() < class'UT_Trait_Swordsman'.default.SWORDSMAN_MIN_DAMAGE_RANK)
		return 0.0;
	if (WeaponDamageEffect == none || AbilityState == none || !IsMeleeLike(AbilityState) || class'UT_EffectHelpers'.static.IsTickDamage(AppliedData))
		return 0.0;

	SourceWeapon = AbilityState.GetSourceWeapon();
	if (SourceWeapon == none)
		return 0.0;

	SourceWeapon.GetBaseWeaponDamageValue(XComGameState_BaseObject(TargetDamageable), BaseDamage);
	BonusDamage = WeaponDamageEffect.GetBonusEffectDamageValue(AbilityState, Attacker, SourceWeapon, AppliedData.TargetStateObjectRef);

	WantedMin = float(BaseDamage.Damage - BaseDamage.Spread + BonusDamage.Damage - BonusDamage.Spread + MinDamageBonus);
	if (AppliedData.AbilityResultContext.HitResult == eHit_Crit)
		WantedMin += float(BaseDamage.Crit + BonusDamage.Crit);
	if (CurrentDamage >= WantedMin)
		return 0.0;

	return WantedMin - CurrentDamage;
}

function int GetAttackingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, const int CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, optional XComGameState NewGameState)
{
	// Base weapon damage only: skip tick effects (poison, burning, ...), same discriminator as
	// X2Effect_UT_WeakExplosives.
	if (CurrentDamage <= 0 || Attacker == none || WeaponDamageEffect == none || class'UT_EffectHelpers'.static.IsTickDamage(AppliedData) || AbilityState == none)
		return 0;

	if (IsMeleeLike(AbilityState))
		return (Attacker.GetRank() >= class'UT_Trait_Swordsman'.default.SWORDSMAN_DAMAGE_RANK) ? DamageBonus : 0;

	if (IsFirearmAttack(AbilityState, WeaponDamageEffect) && CarriesMeleeWeapon(Attacker))
		return -FirearmDamageReduction;

	return 0;
}

function int GetExtraArmorPiercing(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData)
{
	if (Attacker != none && AbilityState != none && IsMeleeLike(AbilityState) && Attacker.GetRank() >= class'UT_Trait_Swordsman'.default.SWORDSMAN_PIERCE_RANK)
		return PierceBonus;

	return 0;
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
