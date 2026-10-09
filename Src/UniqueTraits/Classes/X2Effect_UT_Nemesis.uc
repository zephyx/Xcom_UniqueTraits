//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_Nemesis.uc
//  PURPOSE: Nemesis' permanent bonus: against an enemy TYPE (character template group) the holder has killed N times he gets +AimPerKill*N aim
//           (capped at MaxAim) when he attacks it, and that type gets +DefensePerKill*N (capped at MaxDefense) to hit him, i.e. a defense malus.
//           The kill tally is one UnitValue per type (UVPrefix + group name), written by UT_Trait_Nemesis.OnUnitDied_Nemesis, modelled on Iridar's
//           Bounty Hunter "Headhunter" perk.
//---------------------------------------------------------------------------------------
class X2Effect_UT_Nemesis extends X2Effect_Persistent;

var privatewrite name UVPrefix;
var int AimPerKill, MaxAim, DefensePerKill, MaxDefense;

// Kills of the holder against the enemy's type (0 when none or unknown).
static function int GetKills(XComGameState_Unit Holder, XComGameState_Unit Enemy)
{
	local UnitValue Tally;
	local name GroupName;

	GroupName = Enemy.GetMyTemplateGroupName();
	if (GroupName == '' || !Holder.GetUnitValue(Name(default.UVPrefix $ GroupName), Tally))
		return 0;

	return int(Tally.fValue);
}

function GetToHitModifiers(XComGameState_Effect EffectState, XComGameState_Unit Attacker, XComGameState_Unit Target, XComGameState_Ability AbilityState, class<X2AbilityToHitCalc> ToHitType, bool bMelee, bool bFlanking, bool bIndirectFire, out array<ShotModifierInfo> ShotModifiers)
{
	local ShotModifierInfo ShotModifier;

	ShotModifier.Value = Min(GetKills(Attacker, Target) * AimPerKill, MaxAim);
	if (ShotModifier.Value > 0)
	{
		ShotModifier.ModType = eHit_Success;
		ShotModifier.Reason = FriendlyName;
		ShotModifiers.AddItem(ShotModifier);
	}
}

// The holder is the target: a lower defense is a higher chance for the attacker to hit.
function GetToHitAsTargetModifiers(XComGameState_Effect EffectState, XComGameState_Unit Attacker, XComGameState_Unit Target, XComGameState_Ability AbilityState, class<X2AbilityToHitCalc> ToHitType, bool bMelee, bool bFlanking, bool bIndirectFire, out array<ShotModifierInfo> ShotModifiers)
{
	local ShotModifierInfo ShotModifier;

	ShotModifier.Value = Min(GetKills(Target, Attacker) * DefensePerKill, MaxDefense);
	if (ShotModifier.Value > 0)
	{
		ShotModifier.ModType = eHit_Success;
		ShotModifier.Reason = FriendlyName;
		ShotModifiers.AddItem(ShotModifier);
	}
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
	EffectName = "UT_Nemesis_Bonus"
	UVPrefix = "UT_Nemesis_"
}
