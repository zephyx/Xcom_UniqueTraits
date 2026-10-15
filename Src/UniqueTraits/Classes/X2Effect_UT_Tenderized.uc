//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_Tenderized.uc
//  PURPOSE: Meat Tenderizer's debuffs ("Tenderized" replaces a stun, "Slightly Tenderized" a disorient): a stat change on the target (mobility)
//           plus, like a holotarget (X2Effect_HoloTarget), a bonus to hit and to crit for EVERY unit that attacks the target.
//           The action point given back to the source is NOT here: the ability's cost is applied AFTER its effects (and may consume every
//           point), so it is granted by UT_Trait_MeatTenderizer.OnAbilityActivated_MeatTenderizer once the ability is over.
//           The two cannot stack: the full one removes the light one (here), and the light one is refused on a unit that already has the full
//           one (X2Condition_UnitEffects added by UT_Trait_MeatTenderizer).
//---------------------------------------------------------------------------------------
class X2Effect_UT_Tenderized extends X2Effect_PersistentStatChange;

var bool bSlight;                       // true = Slightly Tenderized
var name SlightEffectName;              // the light twin, removed when the full one is applied
var int AimBonus;                       // to-hit bonus given to whoever attacks the target
var int CritBonus;                      // crit chance bonus given to whoever attacks the target

// As X2Effect_HoloTarget.GetToHitAsTargetModifiers: the attacker's shot, whoever it is, gets the bonus (shown in the shot breakdown under the effect's name).
function GetToHitAsTargetModifiers(XComGameState_Effect EffectState, XComGameState_Unit Attacker, XComGameState_Unit Target, XComGameState_Ability AbilityState, class<X2AbilityToHitCalc> ToHitType, bool bMelee, bool bFlanking, bool bIndirectFire, out array<ShotModifierInfo> ShotModifiers)
{
	local ShotModifierInfo ModInfo;

	if (AimBonus != 0)
	{
		ModInfo.ModType = eHit_Success;
		ModInfo.Reason = FriendlyName;
		ModInfo.Value = AimBonus;
		ShotModifiers.AddItem(ModInfo);
	}

	if (CritBonus != 0)
	{
		ModInfo.ModType = eHit_Crit;
		ModInfo.Reason = FriendlyName;
		ModInfo.Value = CritBonus;
		ShotModifiers.AddItem(ModInfo);
	}
}

simulated protected function OnEffectAdded(const out EffectAppliedData ApplyEffectParameters, XComGameState_BaseObject kNewTargetState, XComGameState NewGameState, XComGameState_Effect NewEffectState)
{
	local XComGameState_Unit TargetUnit;
	local XComGameState_Effect SlightEffect;

	super.OnEffectAdded(ApplyEffectParameters, kNewTargetState, NewGameState, NewEffectState);

	// Tenderized wins over Slightly Tenderized.
	TargetUnit = XComGameState_Unit(kNewTargetState);
	if (!bSlight && TargetUnit != none)
	{
		SlightEffect = TargetUnit.GetUnitAffectedByEffectState(SlightEffectName);
		if (SlightEffect != none)
			SlightEffect.RemoveEffect(NewGameState, NewGameState, true);
	}
}

defaultproperties
{
	DuplicateResponse = eDupe_Refresh
}
