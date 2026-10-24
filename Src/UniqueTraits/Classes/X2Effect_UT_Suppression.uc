//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_Suppression.uc
//  PURPOSE: A debuff on an enemy that, for as long as it lasts, takes away the abilities that are persistent effects named in EffectNamesToSuppress, and may carry stat changes
//           (AddPersistentStatChange, as any X2Effect_PersistentStatChange). The suppressed effects are REMOVED when the debuff is applied and given back when it ends
//           (OnEffectRemoved): the data each was applied with is kept in the debuff's own effect state (XComGameState_Effect_UT_Suppression) and the very same effect, the one of
//           the ability that provided it (whatever the mod: the Advent Sniper has an ability of its own for its Squadsight), is applied again from that data.
//           Used by the Laser designator's mark (+dodge, suppresses Shadowstep) and the Apothecary's toxin (Aim, Mobility and sight maluses, suppresses Squadsight).
//---------------------------------------------------------------------------------------
class X2Effect_UT_Suppression extends X2Effect_PersistentStatChange;

var array<name> EffectNamesToSuppress;

simulated protected function OnEffectAdded(const out EffectAppliedData ApplyEffectParameters, XComGameState_BaseObject kNewTargetState, XComGameState NewGameState, XComGameState_Effect NewEffectState)
{
	local XComGameState_Unit Target;
	local XComGameState_Effect Existing;
	local XComGameState_Effect_UT_Suppression Suppression;

	super.OnEffectAdded(ApplyEffectParameters, kNewTargetState, NewGameState, NewEffectState);

	Target = XComGameState_Unit(kNewTargetState);
	Suppression = XComGameState_Effect_UT_Suppression(NewEffectState);
	if (Target == none || Suppression == none)
		return;

	foreach `XCOMHISTORY.IterateByClassType(class'XComGameState_Effect', Existing)
	{
		if (Existing.bRemoved || Existing.ApplyEffectParameters.TargetStateObjectRef.ObjectID != Target.ObjectID)
			continue;

		if (EffectNamesToSuppress.Find(Existing.GetX2Effect().EffectName) != INDEX_NONE)
		{
			Suppression.SuppressedEffects.AddItem(Existing.ApplyEffectParameters);
			Existing.RemoveEffect(NewGameState, NewGameState, true);
		}
	}
}

simulated function OnEffectRemoved(const out EffectAppliedData ApplyEffectParameters, XComGameState NewGameState, bool bCleansed, XComGameState_Effect RemovedEffectState)
{
	local XComGameState_Unit Target;
	local XComGameState_Effect_UT_Suppression Suppression;
	local EffectAppliedData Saved;
	local X2Effect Original;

	super.OnEffectRemoved(ApplyEffectParameters, NewGameState, bCleansed, RemovedEffectState);

	Suppression = XComGameState_Effect_UT_Suppression(RemovedEffectState);
	if (Suppression == none || Suppression.SuppressedEffects.Length == 0)
		return;

	Target = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(ApplyEffectParameters.TargetStateObjectRef.ObjectID));
	if (Target == none || !Target.IsAlive())
		return;

	Target = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Target.ObjectID));

	// Each effect comes back from its own application data: same ability, same source, same effect template, so same text, icon and properties as before.
	foreach Suppression.SuppressedEffects(Saved)
	{
		Original = class'X2Effect'.static.GetX2Effect(Saved.EffectRef);
		if (Original != none)
			Original.ApplyEffect(Saved, Target, NewGameState);
	}
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
	GameStateEffectClass = class'XComGameState_Effect_UT_Suppression'
}
