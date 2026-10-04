//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_LongRange.uc
//  PURPOSE: Long Range's aim modifiers, applied to any ranged (non-melee) shot:
//           - Far side: once a weapon's own RangeAccuracy table has been through a non-malus
//             stretch and falls back into malus, the holder uses the entry 3 tiles earlier
//             instead of the current one (see GetFarRangeCorrection).
//           - Near side: a flat aim malus on the closest tiles (CloseRangeAimPenalty[0] at 1 tile).
//---------------------------------------------------------------------------------------
class X2Effect_UT_LongRange extends X2Effect_Persistent;

var int FarRangeShift;
// Index 0 = distance of 1 tile, index 1 = 2 tiles, ... no penalty beyond the last entry.
var array<int> CloseRangeAimPenalty;

private function int GetRangeAccuracyAt(X2WeaponTemplate WeaponTemplate, int Tiles)
{
	if (WeaponTemplate.RangeAccuracy.Length == 0)
		return 0;

	// Mirrors X2AbilityToHitCalc_StandardAim's own lookup (last configured entry past the end).
	return WeaponTemplate.RangeAccuracy[Min(Tiles, WeaponTemplate.RangeAccuracy.Length - 1)];
}

// Returns the aim to ADD so the shot behaves as if it were taken FarRangeShift tiles closer, or 0
// when the far-range rule doesn't apply at this distance.
private function int GetFarRangeCorrection(X2WeaponTemplate WeaponTemplate, int Tiles)
{
	local int Current, Shifted, i;
	local bool bHadNoMalusBefore;

	Current = GetRangeAccuracyAt(WeaponTemplate, Tiles);
	if (Current >= 0 || Tiles - FarRangeShift < 0)
		return 0;

	for (i = 0; i < Tiles; ++i)
	{
		if (GetRangeAccuracyAt(WeaponTemplate, i) >= 0)
		{
			bHadNoMalusBefore = true;
			break;
		}
	}
	if (!bHadNoMalusBefore)
		return 0;

	Shifted = GetRangeAccuracyAt(WeaponTemplate, Tiles - FarRangeShift);
	return Shifted - Current;
}

function GetToHitModifiers(XComGameState_Effect EffectState, XComGameState_Unit Attacker, XComGameState_Unit Target, XComGameState_Ability AbilityState, class<X2AbilityToHitCalc> ToHitType, bool bMelee, bool bFlanking, bool bIndirectFire, out array<ShotModifierInfo> ShotModifiers)
{
	local ShotModifierInfo Modifier;
	local XComGameState_Item SourceWeapon;
	local X2WeaponTemplate WeaponTemplate;
	local int Tiles, Correction;

	if (bMelee || Attacker == none || Target == none || AbilityState == none)
		return;

	SourceWeapon = AbilityState.GetSourceWeapon();
	if (SourceWeapon == none)
		return;

	WeaponTemplate = X2WeaponTemplate(SourceWeapon.GetMyTemplate());
	if (WeaponTemplate == none)
		return;

	Tiles = Attacker.TileDistanceBetween(Target);

	Correction = GetFarRangeCorrection(WeaponTemplate, Tiles);
	if (Correction != 0)
	{
		Modifier.ModType = eHit_Success;
		Modifier.Value = Correction;
		Modifier.Reason = class'UT_TraitBase'.static.GetShotModifierLabel(self);
		ShotModifiers.AddItem(Modifier);
	}

	if (Tiles >= 1 && Tiles <= CloseRangeAimPenalty.Length && CloseRangeAimPenalty[Tiles - 1] != 0)
	{
		Modifier.ModType = eHit_Success;
		Modifier.Value = -CloseRangeAimPenalty[Tiles - 1];
		Modifier.Reason = class'UT_TraitBase'.static.GetShotModifierLabel(self);
		ShotModifiers.AddItem(Modifier);
	}
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
