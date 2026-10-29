//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_QualityCrit.uc
//  PURPOSE: Quality over quantity's critical chance: abilities fired with the holder's PRIMARY weapon get a bonus critical chance
//           that depends on the weapon's tier. The tier is the index of X2WeaponTemplate.WeaponTech in WeaponTechs (conventional, laser_lw, magnetic,
//           coilgun_lw, beam), which is also the index in CritByTier; a tech that is not listed takes the last entry. The weapon's Tier is NOT used:
//           LWOTC rewrites it from its ini (conventional 0, laser 150, magnetic 160, coil 170, beam 180), which gave every weapon above conventional the
//           last entry.
//---------------------------------------------------------------------------------------
class X2Effect_UT_QualityCrit extends X2Effect_Persistent;

var array<name> WeaponTechs;
var array<int> CritByTier;

function GetToHitModifiers(XComGameState_Effect EffectState, XComGameState_Unit Attacker, XComGameState_Unit Target, XComGameState_Ability AbilityState, class<X2AbilityToHitCalc> ToHitType, bool bMelee, bool bFlanking, bool bIndirectFire, out array<ShotModifierInfo> ShotModifiers)
{
	local ShotModifierInfo Modifier;
	local int Index, Bonus;

	if (CritByTier.Length == 0)
		return;

	Index = class'UT_EffectHelpers'.static.GetPrimaryWeaponTechIndex(AbilityState, WeaponTechs);
	if (Index == INDEX_NONE)
		return;

	Bonus = CritByTier[Clamp(Index, 0, CritByTier.Length - 1)];
	if (Bonus <= 0)
		return;

	Modifier.ModType = eHit_Crit;
	Modifier.Value = Bonus;
	Modifier.Reason = class'UT_TraitBase'.static.GetShotModifierLabel(self);
	ShotModifiers.AddItem(Modifier);
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
