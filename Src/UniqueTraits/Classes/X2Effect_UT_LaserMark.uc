//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_LaserMark.uc
//  PURPOSE: Laser designator's mark on an enemy, for the duration of the effect (one turn): +DodgeBonus dodge (the stat change added by the
//           trait) and the loss of the abilities that are persistent effects named in EffectNamesToSuppress (Shadowstep). The suppressed
//           effects are REMOVED when the mark is applied and given back when it ends (OnEffectRemoved), by applying the restore effect of the
//           hidden ability UT_LaserDesignatorMark (effect index RestoreEffectIndex): the target unit remembers it was suppressed in the
//           UnitValue UT_LaserMark_Suppressed.
//---------------------------------------------------------------------------------------
class X2Effect_UT_LaserMark extends X2Effect_PersistentStatChange;

var array<name> EffectNamesToSuppress;
var name RestoreAbilityName;
var int RestoreEffectIndex;

simulated protected function OnEffectAdded(const out EffectAppliedData ApplyEffectParameters, XComGameState_BaseObject kNewTargetState, XComGameState NewGameState, XComGameState_Effect NewEffectState)
{
	local XComGameState_Unit Target;
	local XComGameState_Effect Existing;
	local bool bSuppressed;

	super.OnEffectAdded(ApplyEffectParameters, kNewTargetState, NewGameState, NewEffectState);

	Target = XComGameState_Unit(kNewTargetState);
	if (Target == none)
		return;

	foreach `XCOMHISTORY.IterateByClassType(class'XComGameState_Effect', Existing)
	{
		if (Existing.bRemoved || Existing.ApplyEffectParameters.TargetStateObjectRef.ObjectID != Target.ObjectID)
			continue;

		if (EffectNamesToSuppress.Find(Existing.GetX2Effect().EffectName) != INDEX_NONE)
		{
			Existing.RemoveEffect(NewGameState, NewGameState, true);
			bSuppressed = true;
		}
	}

	if (bSuppressed)
		Target.SetUnitFloatValue('UT_LaserMark_Suppressed', 1, eCleanup_BeginTactical);
}

simulated function OnEffectRemoved(const out EffectAppliedData ApplyEffectParameters, XComGameState NewGameState, bool bCleansed, XComGameState_Effect RemovedEffectState)
{
	local XComGameState_Unit Target, Source;
	local UnitValue SuppressedValue;

	super.OnEffectRemoved(ApplyEffectParameters, NewGameState, bCleansed, RemovedEffectState);

	Target = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', ApplyEffectParameters.TargetStateObjectRef.ObjectID));
	if (Target == none || !Target.IsAlive() || !Target.GetUnitValue('UT_LaserMark_Suppressed', SuppressedValue))
		return;

	Target.ClearUnitValue('UT_LaserMark_Suppressed');

	Source = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(ApplyEffectParameters.SourceStateObjectRef.ObjectID));
	if (Source != none)
		class'UT_EffectHelpers'.static.ApplyAbilityEffect(RestoreAbilityName, RestoreEffectIndex, Source, Target, NewGameState);
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
