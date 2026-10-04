//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_AcrobatMalus.uc
//  PURPOSE: Acrobat's -10 aim / -10 crit chance when attacking a target below their own
//           elevation (effectively cancelling their own height advantage bonus).
//---------------------------------------------------------------------------------------
class X2Effect_UT_AcrobatMalus extends X2Effect_Persistent;

var int AimPenalty, CritPenalty;

function GetToHitModifiers(XComGameState_Effect EffectState, XComGameState_Unit Attacker, XComGameState_Unit Target, XComGameState_Ability AbilityState, class<X2AbilityToHitCalc> ToHitType, bool bMelee, bool bFlanking, bool bIndirectFire, out array<ShotModifierInfo> ShotModifiers)
{
	local ShotModifierInfo Modifier;

	if (Attacker == none || Target == none || !Attacker.HasHeightAdvantageOver(Target, true))
		return;

	Modifier.ModType = eHit_Success;
	Modifier.Value = -AimPenalty;
	Modifier.Reason = class'UT_TraitBase'.static.GetShotModifierLabel(self);
	ShotModifiers.AddItem(Modifier);

	Modifier.ModType = eHit_Crit;
	Modifier.Value = -CritPenalty;
	Modifier.Reason = class'UT_TraitBase'.static.GetShotModifierLabel(self);
	ShotModifiers.AddItem(Modifier);
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
