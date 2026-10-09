//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Tactician.uc
//  PURPOSE: Tactician: -TACTICIAN_AIM aim, but a missed shot disorients its target (OnAbilityActivated_Tactician). The disoriented
//           status is vanilla's own (X2StatusEffects.CreateDisorientedStatusEffect, so robots are immune as usual): the effect has
//           to live in an ability template to be found again by its EffectRef, hence the hidden UT_TacticianDisorient (UT_TraitBase.
//           HiddenEffectHolder), never granted to any unit, applied and visualized through UT_EffectHelpers.
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

	Template = HiddenEffectHolder('UT_TacticianDisorient');
	Template.Hostility = eHostility_Offensive;
	Template.AddTargetEffect(class'X2StatusEffects'.static.CreateDisorientedStatusEffect(true));

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
	local XComGameState NewGameState;

	// 'AbilityActivated' fires once for the interrupt step and again on resume/final for the same
	// shot (XComGameStateContext_Ability.uc:191/:414); react only once.
	if (!ParseAbilityActivation(GameState, EventSource, 'UT_Tactician', AbilityContext, SourceUnit))
		return ELR_NoInterrupt;

	if (AbilityContext.ResultContext.HitResult != eHit_Miss)
		return ELR_NoInterrupt;

	if (AbilityContext.InputContext.PrimaryTarget.ObjectID == 0)
		return ELR_NoInterrupt;

	TargetUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(AbilityContext.InputContext.PrimaryTarget.ObjectID));
	if (TargetUnit == none || TargetUnit.IsDead())
		return ELR_NoInterrupt;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Tactician disorient");
	TargetUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', TargetUnit.ObjectID));

	// ApplyEffect checks the effect's own conditions (robots are immune, no friendly fire...).
	if (class'UT_EffectHelpers'.static.ApplyAbilityEffect('UT_TacticianDisorient', 0, SourceUnit, TargetUnit, NewGameState, AbilityContext) != 'AA_Success')
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
	class'UT_EffectHelpers'.static.AddEffectVisualization(VisualizeGameState, 'UT_TacticianDisorient', 0);
}
