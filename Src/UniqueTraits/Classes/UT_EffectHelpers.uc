//---------------------------------------------------------------------------------------
//  FILE:   UT_EffectHelpers.uc
//  PURPOSE: Shared helper for the traits that apply an effect "by hand" (outside the ability that owns it): Tactician's disorient (its own
//           code), Chemist's disease, Laser designator's mark, Psychic Bond's partner stats. An effect applied by hand must come from an ability
//           template: XComGameState_Effect finds its effect again through an X2EffectTemplateRef (ability template name + index in its
//           AbilityTargetEffects), so each such effect lives in a hidden ability template that is never granted to any unit.
//           Also home of the small queries on effects shared by several traits (IsDamageOverTime: Chemist).
//---------------------------------------------------------------------------------------
class UT_EffectHelpers extends Object;

// Applies effect EffectIndex of the AbilityTargetEffects of the hidden ability TemplateName to Target, as if Source had applied it.
// Target must be a pending (modifiable) state object of NewGameState. AbilityContext may be none (effects applied outside an ability).
// Returns the result of X2Effect.ApplyEffect ('AA_Success' when applied); 'AA_AbilityUnavailable' if the template/effect does not exist.
static function name ApplyAbilityEffect(name TemplateName, int EffectIndex, XComGameState_Unit Source, XComGameState_BaseObject Target, XComGameState NewGameState, optional XComGameStateContext_Ability AbilityContext)
{
	local X2AbilityTemplate Template;
	local EffectAppliedData EffectData;

	Template = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager().FindAbilityTemplate(TemplateName);
	if (Template == none || EffectIndex < 0 || EffectIndex >= Template.AbilityTargetEffects.Length)
		return 'AA_AbilityUnavailable';

	EffectData.PlayerStateObjectRef = Source.ControllingPlayer;
	EffectData.SourceStateObjectRef = Source.GetReference();
	EffectData.TargetStateObjectRef = Target.GetReference();
	if (AbilityContext != none)
	{
		EffectData.ItemStateObjectRef = AbilityContext.InputContext.ItemObject;
		EffectData.AbilityStateObjectRef = AbilityContext.InputContext.AbilityRef;
		EffectData.AbilityInputContext = AbilityContext.InputContext;
	}
	EffectData.EffectRef.SourceTemplateName = TemplateName;
	EffectData.EffectRef.LookupType = TELT_AbilityTargetEffects;
	EffectData.EffectRef.TemplateEffectLookupArrayIndex = EffectIndex;
	EffectData.EffectRef.ApplyOnTickIndex = INDEX_NONE;

	return Template.AbilityTargetEffects[EffectIndex].ApplyEffect(EffectData, Target, NewGameState);
}

// The visualization of a hidden ability's effect on each unit of a change container state that carries it (flyover, unit flag...).
static function AddEffectVisualization(XComGameState VisualizeGameState, name TemplateName, int EffectIndex)
{
	local XComGameStateHistory History;
	local XComGameState_Unit UnitState;
	local VisualizationActionMetadata ActionMetadata, EmptyMetadata;
	local X2AbilityTemplate Template;
	local X2Effect_Persistent PersistentEffect;

	Template = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager().FindAbilityTemplate(TemplateName);
	if (Template == none || EffectIndex < 0 || EffectIndex >= Template.AbilityTargetEffects.Length)
		return;

	History = `XCOMHISTORY;
	PersistentEffect = X2Effect_Persistent(Template.AbilityTargetEffects[EffectIndex]);

	foreach VisualizeGameState.IterateByClassType(class'XComGameState_Unit', UnitState)
	{
		// Only the units that carry the effect (the state may also hold the source unit, whose effect was just consumed...).
		if (PersistentEffect != none && !UnitState.IsUnitAffectedByEffectName(PersistentEffect.EffectName))
			continue;

		ActionMetadata = EmptyMetadata;
		ActionMetadata.StateObject_OldState = History.GetGameStateForObjectID(UnitState.ObjectID, eReturnType_Reference, VisualizeGameState.HistoryIndex - 1);
		ActionMetadata.StateObject_NewState = UnitState;
		ActionMetadata.VisualizeActor = History.GetVisualizer(UnitState.ObjectID);

		Template.AbilityTargetEffects[EffectIndex].AddX2ActionsForVisualization(VisualizeGameState, ActionMetadata, 'AA_Success');
	}
}

// A damage over time = a persistent effect that applies a weapon damage effect on every tick.
static final function bool IsDamageOverTime(X2Effect_Persistent Effect)
{
	local X2Effect TickEffect;

	if (Effect == none)
		return false;

	foreach Effect.ApplyOnTick(TickEffect)
	{
		if (X2Effect_ApplyWeaponDamage(TickEffect) != none)
			return true;
	}

	return false;
}
