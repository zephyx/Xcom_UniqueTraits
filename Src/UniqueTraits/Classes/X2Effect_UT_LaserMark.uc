//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_LaserMark.uc
//  PURPOSE: Laser designator's mark on an enemy, for the duration of the effect (one turn): +DodgeBonus dodge (the stat change added by the
//           trait) and the loss of the abilities that are persistent effects named in EffectNamesToSuppress (Shadowstep). The suppressed
//           effects are REMOVED when the mark is applied and given back when it ends (OnEffectRemoved), by applying the restore effect of the
//           hidden ability UT_LaserDesignatorMark (effect index RestoreEffectIndex): the target unit remembers it was suppressed in the
//           UnitValue SuppressedValueName (UT_LaserMark_Suppressed).
//           Also used by Apothecary's toxin (it suppresses Squadsight), with a value name of its own so that two marks on the same unit do not
//           forget each other's suppression.
//---------------------------------------------------------------------------------------
class X2Effect_UT_LaserMark extends X2Effect_PersistentStatChange;

var array<name> EffectNamesToSuppress;
var name RestoreAbilityName;
var int RestoreEffectIndex;
var name SuppressedValueName;

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
		Target.SetUnitFloatValue(SuppressedValueName, 1, eCleanup_BeginTactical);
}

simulated function OnEffectRemoved(const out EffectAppliedData ApplyEffectParameters, XComGameState NewGameState, bool bCleansed, XComGameState_Effect RemovedEffectState)
{
	local XComGameState_Unit Target, Source;
	local UnitValue SuppressedValue;
	local name RestoreResult;

	super.OnEffectRemoved(ApplyEffectParameters, NewGameState, bCleansed, RemovedEffectState);

	Target = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', ApplyEffectParameters.TargetStateObjectRef.ObjectID));
	if (Target == none || !Target.IsAlive() || !Target.GetUnitValue(SuppressedValueName, SuppressedValue))
		return;

	// What was suppressed is remembered in the unit itself (a UnitValue, part of the saved history), and everything needed here (this effect's variables, the hidden ability) is rebuilt
	// from the code at every load: a save made while the mark / toxin is active restores the effects when it ends, after the reload as before it.
	Target.ClearUnitValue(SuppressedValueName);

	// The effects must come back even if the source is no longer there to be found: the target itself then stands in for it.
	Source = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(ApplyEffectParameters.SourceStateObjectRef.ObjectID));
	if (Source == none)
		Source = Target;

	RestoreResult = class'UT_EffectHelpers'.static.ApplyAbilityEffect(RestoreAbilityName, RestoreEffectIndex, Source, Target, NewGameState);
	`log("UniqueTraits :" @ string(EffectName) @ "ended on" @ Target.GetFullName() @ ": suppressed effects given back (" $ RestoreAbilityName $ " effect " $ RestoreEffectIndex $ ") ->" @ RestoreResult,, 'UniqueTraits');
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
	SuppressedValueName = 'UT_LaserMark_Suppressed'
}
