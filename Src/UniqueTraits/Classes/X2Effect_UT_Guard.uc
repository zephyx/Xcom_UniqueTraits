//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_Guard.uc
//  PURPOSE: Guard's passive (reworked 2026-10-30, the first version was a fixed -15 aim stat and a fixed +25 on reactions):
//           - every attack of the holder (ranged or melee, not indirect fire) loses AimPenaltyPerRank x his rank Aim, as a shot modifier (eHit_Success);
//           - every overwatch / reaction attack gains ReactionAimPerRank x his rank Aim: the game asks ModifyReactionFireSuccess for a flat bonus that is added to the hit
//             chance AFTER the reaction multiplier (X2AbilityToHitCalc_StandardAim.AddReactionFlatModifier), which is where the fixed +25 went. Those attacks can crit
//             (bAllowCrit, base game's X2Effect_ModifyReactionFire).
//---------------------------------------------------------------------------------------
class X2Effect_UT_Guard extends X2Effect_ModifyReactionFire;

var int AimPenaltyPerRank;
var int ReactionAimPerRank;

function ModifyReactionFireSuccess(XComGameState_Unit UnitState, XComGameState_Unit TargetState, out int Modifier)
{
	Modifier = ReactionAimPerRank * UnitState.GetRank();
}

function GetToHitModifiers(XComGameState_Effect EffectState, XComGameState_Unit Attacker, XComGameState_Unit Target, XComGameState_Ability AbilityState, class<X2AbilityToHitCalc> ToHitType, bool bMelee, bool bFlanking, bool bIndirectFire, out array<ShotModifierInfo> ShotModifiers)
{
	local ShotModifierInfo Modifier;

	if (bIndirectFire || AimPenaltyPerRank <= 0 || Attacker == none || Attacker.GetRank() <= 0)
		return;

	Modifier.ModType = eHit_Success;
	Modifier.Value = -AimPenaltyPerRank * Attacker.GetRank();
	Modifier.Reason = class'UT_TraitBase'.static.GetShotModifierLabel(self);
	ShotModifiers.AddItem(Modifier);
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
