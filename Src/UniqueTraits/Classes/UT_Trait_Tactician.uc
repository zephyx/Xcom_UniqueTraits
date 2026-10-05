//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Tactician.uc
//  PURPOSE: Tactician: -TACTICIAN_AIM aim, but a missed shot disorients its target (OnAbilityActivated_Tactician). The disoriented
//           status is vanilla's own (X2StatusEffects.CreateDisorientedStatusEffect, so robots are immune as usual): the effect has
//           to live in an ability template to be found again by its EffectRef, hence the hidden UT_TacticianDisorient, never
//           granted to any unit.
//---------------------------------------------------------------------------------------
class UT_Trait_Tactician extends UT_TraitBase config(UniqueTraits);

var config int TACTICIAN_AIM;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Tactician());
	Templates.AddItem(TacticianDisorient());

	return Templates;
}

// Tactician: -10 aim. The disorient on a missed shot is OnAbilityActivated_Tactician, since it needs to react to
// arbitrary attack abilities missing rather than something attachable to this passive itself.
static function X2AbilityTemplate Tactician()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;

	Template = PurePassive('UT_Tactician', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_Tactician';
	StatEffect.BuildPersistentEffect(1, true, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_Offense, -default.TACTICIAN_AIM);
	Template.AddTargetEffect(StatEffect);

	Template.SetUIStatMarkup(class'XLocalizedData'.default.AimLabel, eStat_Offense, -default.TACTICIAN_AIM);

	return Template;
}

// Holder of the disoriented effect applied by OnAbilityActivated_Tactician (an effect applied outside an ability must be found again
// by its X2EffectTemplateRef: ability template name + index in its AbilityTargetEffects). Not granted to any unit.
static function X2AbilityTemplate TacticianDisorient()
{
	local X2AbilityTemplate Template;

	`CREATE_X2ABILITY_TEMPLATE(Template, 'UT_TacticianDisorient');

	Template.AbilitySourceName = 'eAbilitySource_Perk';
	Template.eAbilityIconBehaviorHUD = eAbilityIconBehavior_NeverShow;
	Template.Hostility = eHostility_Offensive;
	Template.bDontDisplayInAbilitySummary = true;
	Template.bDisplayInUITooltip = false;
	Template.bDisplayInUITacticalText = false;

	Template.AbilityToHitCalc = default.DeadEye;
	Template.AbilityTargetStyle = default.SimpleSingleTarget;
	Template.AddTargetEffect(class'X2StatusEffects'.static.CreateDisorientedStatusEffect(true));

	Template.BuildNewGameStateFn = TypicalAbility_BuildGameState;

	return Template;
}

// Tactician: a missed shot disorients its target. There's no clean way to attach an "on miss" effect to an arbitrary attack ability
// from outside without either mutating the shared/singleton X2AbilityTemplate for everyone using that ability (dangerous) or deep-
// copying every attack ability template per unit (heavy). Instead, this reacts to the fully resolved miss after the fact and applies
// the effect of UT_TacticianDisorient to the target in a game state of its own.
static function EventListenerReturn OnAbilityActivated_Tactician(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit SourceUnit, TargetUnit;
	local XComGameStateContext_Ability AbilityContext;
	local X2AbilityTemplate DisorientTemplate;
	local X2Effect DisorientEffect;
	local EffectAppliedData EffectData;
	local XComGameState NewGameState;

	// 'AbilityActivated' fires once for the interrupt step and again on resume/final for the same
	// shot (XComGameStateContext_Ability.uc:191/:414); react only once.
	if (GameState.GetContext().InterruptionStatus == eInterruptionStatus_Interrupt)
		return ELR_NoInterrupt;

	SourceUnit = XComGameState_Unit(EventSource);
	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SourceUnit, 'UT_Tactician'))
		return ELR_NoInterrupt;

	AbilityContext = XComGameStateContext_Ability(GameState.GetContext());
	if (AbilityContext == none || AbilityContext.ResultContext.HitResult != eHit_Miss)
		return ELR_NoInterrupt;

	if (AbilityContext.InputContext.PrimaryTarget.ObjectID == 0)
		return ELR_NoInterrupt;

	TargetUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(AbilityContext.InputContext.PrimaryTarget.ObjectID));
	if (TargetUnit == none || TargetUnit.IsDead())
		return ELR_NoInterrupt;

	DisorientTemplate = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager().FindAbilityTemplate('UT_TacticianDisorient');
	if (DisorientTemplate == none || DisorientTemplate.AbilityTargetEffects.Length == 0)
		return ELR_NoInterrupt;
	DisorientEffect = DisorientTemplate.AbilityTargetEffects[0];

	EffectData.PlayerStateObjectRef = SourceUnit.ControllingPlayer;
	EffectData.SourceStateObjectRef = SourceUnit.GetReference();
	EffectData.TargetStateObjectRef = TargetUnit.GetReference();
	EffectData.ItemStateObjectRef = AbilityContext.InputContext.ItemObject;
	EffectData.AbilityStateObjectRef = AbilityContext.InputContext.AbilityRef;
	EffectData.AbilityInputContext = AbilityContext.InputContext;
	EffectData.EffectRef.SourceTemplateName = 'UT_TacticianDisorient';
	EffectData.EffectRef.LookupType = TELT_AbilityTargetEffects;
	EffectData.EffectRef.TemplateEffectLookupArrayIndex = 0;
	EffectData.EffectRef.ApplyOnTickIndex = INDEX_NONE;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Tactician disorient");
	TargetUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', TargetUnit.ObjectID));

	// ApplyEffect checks the effect's own conditions (robots are immune, no friendly fire...).
	if (DisorientEffect.ApplyEffect(EffectData, TargetUnit, NewGameState) != 'AA_Success')
	{
		`XCOMHISTORY.CleanupPendingGameState(NewGameState);
		return ELR_NoInterrupt;
	}

	XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = BuildVisualization_TacticianDisorient;
	`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}

// The disoriented effect's own visualization (flyover, message, unit flag), on the target.
static function BuildVisualization_TacticianDisorient(XComGameState VisualizeGameState)
{
	local XComGameStateHistory History;
	local XComGameState_Unit UnitState;
	local VisualizationActionMetadata ActionMetadata;
	local X2AbilityTemplate DisorientTemplate;

	History = `XCOMHISTORY;

	foreach VisualizeGameState.IterateByClassType(class'XComGameState_Unit', UnitState)
		break;
	if (UnitState == none)
		return;

	DisorientTemplate = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager().FindAbilityTemplate('UT_TacticianDisorient');
	if (DisorientTemplate == none || DisorientTemplate.AbilityTargetEffects.Length == 0)
		return;

	ActionMetadata.StateObject_OldState = History.GetGameStateForObjectID(UnitState.ObjectID, eReturnType_Reference, VisualizeGameState.HistoryIndex - 1);
	ActionMetadata.StateObject_NewState = UnitState;
	ActionMetadata.VisualizeActor = History.GetVisualizer(UnitState.ObjectID);

	DisorientTemplate.AbilityTargetEffects[0].AddX2ActionsForVisualization(VisualizeGameState, ActionMetadata, 'AA_Success');
}
