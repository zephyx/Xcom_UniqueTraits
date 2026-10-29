//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_AthleteCover.uc
//  PURPOSE: Athlete's aim malus: on a RANGED shot of the holder at a target that can take cover (a "flankable" unit, X2CharacterTemplate.bCanTakeCover) and is NOT flanked, the
//           hit chance loses ATHLETE_COVER_AIM_BASE + ATHLETE_COVER_AIM_PER_RANK x the holder's rank. bFlanking, given by X2AbilityToHitCalc_StandardAim, is true when the shooter can
//           flank and the target has no cover against him, so "can take cover and not flanked" is "has cover against him" (a target whose cover is gone for another reason, a
//           shooter who cannot flank: counted as covered, a rare approximation). Melee and indirect fire (no cover in the hit chance) are left alone. The numbers are read from
//           UT_Trait_Athlete when used, so a change in the Mod Config Menu applies at once.
//---------------------------------------------------------------------------------------
class X2Effect_UT_AthleteCover extends X2Effect_Persistent;

function GetToHitModifiers(XComGameState_Effect EffectState, XComGameState_Unit Attacker, XComGameState_Unit Target, XComGameState_Ability AbilityState, class<X2AbilityToHitCalc> ToHitType, bool bMelee, bool bFlanking, bool bIndirectFire, out array<ShotModifierInfo> ShotModifiers)
{
	local ShotModifierInfo Modifier;
	local int Malus;

	if (bMelee || bIndirectFire || bFlanking || Attacker == none || Target == none)
		return;

	if (!ClassIsChildOf(ToHitType, class'X2AbilityToHitCalc_StandardAim') || !Target.CanTakeCover())
		return;

	Malus = class'UT_Trait_Athlete'.default.ATHLETE_COVER_AIM_BASE + class'UT_Trait_Athlete'.default.ATHLETE_COVER_AIM_PER_RANK * Attacker.GetRank();
	if (Malus <= 0)
		return;

	Modifier.ModType = eHit_Success;
	Modifier.Value = -Malus;
	Modifier.Reason = class'UT_TraitBase'.static.GetShotModifierLabel(self);
	ShotModifiers.AddItem(Modifier);
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
