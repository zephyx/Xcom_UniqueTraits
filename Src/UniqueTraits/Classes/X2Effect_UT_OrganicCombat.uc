//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_OrganicCombat.uc
//  PURPOSE: Pacifist's two "won't properly fight anything alive" effects, both scoped to
//           biological (non-robotic) units only, never robots: -AimMalus when Pacifist is
//           the attacker shooting an organic target, +DefenseBonus when Pacifist is the
//           target being shot by an organic attacker. Needs a custom effect for both halves
//           because X2Effect_ToHitModifier's bApplyAsTarget mode only ever evaluates
//           ToHitConditions against the unit carrying the effect, never against the unit on
//           the other side of the shot.
//---------------------------------------------------------------------------------------
class X2Effect_UT_OrganicCombat extends X2Effect_Persistent;

var int AimMalus;
var int DefenseBonus;

// Pacifist as the attacker: no aim malus at all against a robotic target.
function GetToHitModifiers(XComGameState_Effect EffectState, XComGameState_Unit Attacker, XComGameState_Unit Target, XComGameState_Ability AbilityState, class<X2AbilityToHitCalc> ToHitType, bool bMelee, bool bFlanking, bool bIndirectFire, out array<ShotModifierInfo> ShotModifiers)
{
	local ShotModifierInfo Modifier;

	if (Target == none || Target.IsRobotic())
		return;

	Modifier.ModType = eHit_Success;
	Modifier.Value = -AimMalus;
	Modifier.Reason = string(EffectName);
	ShotModifiers.AddItem(Modifier);
}

// Pacifist as the target: no defense bonus at all against a robotic attacker.
function GetToHitAsTargetModifiers(XComGameState_Effect EffectState, XComGameState_Unit Attacker, XComGameState_Unit Target, XComGameState_Ability AbilityState, class<X2AbilityToHitCalc> ToHitType, bool bMelee, bool bFlanking, bool bIndirectFire, out array<ShotModifierInfo> ShotModifiers)
{
	local ShotModifierInfo Modifier;

	if (Attacker == none || Attacker.IsRobotic())
		return;

	Modifier.ModType = eHit_Success;
	Modifier.Value = -DefenseBonus;
	Modifier.Reason = string(EffectName);
	ShotModifiers.AddItem(Modifier);
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
