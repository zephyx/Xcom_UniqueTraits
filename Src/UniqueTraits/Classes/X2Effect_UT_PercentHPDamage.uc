//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_PercentHPDamage.uc
//  PURPOSE: A flat-damage weapon damage effect whose amount is PercentOfMaxHP % of the TARGET's maximum HP, rounded up (at least 1). Used by
//           Security hacker's backlash (self-targeted hidden ability, bIgnoreBaseDamage / bIgnoreArmor / bBypassShields set by the trait).
//           The amount is given by GetBonusEffectDamageValue, which X2Effect_ApplyWeaponDamage reads for both the damage and its preview.
//---------------------------------------------------------------------------------------
class X2Effect_UT_PercentHPDamage extends X2Effect_ApplyWeaponDamage;

var int PercentOfMaxHP;

function WeaponDamageValue GetBonusEffectDamageValue(XComGameState_Ability AbilityState, XComGameState_Unit SourceUnit, XComGameState_Item SourceWeapon, StateObjectReference TargetRef)
{
	local WeaponDamageValue Value;
	local XComGameState_Unit Target;

	Value = EffectDamageValue;
	Target = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(TargetRef.ObjectID));
	if (Target != none)
		Value.Damage = Max(1, (int(Target.GetMaxStat(eStat_HP)) * PercentOfMaxHP + 99) / 100);

	return Value;
}
