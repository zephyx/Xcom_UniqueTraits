//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_AlwaysReady.uc
//  PURPOSE: Always ready: UT_AlwaysReady is the icon holder (the reload malus is a listener), UT_AlwaysReadyOverwatch is the bonus.
//           The forced reload is a compulsion of the mind: a soldier protected against mental effects is spared it, the way the
//           Gene Modding mod's Chaotic Mind is suppressed: UnitState.IsImmuneToDamage('Mental') (Mind Shield, Solace's aura, the Mitzruti gene mod Neural Damping...,
//           anything that provides a damage immunity, native character immunities included). The damage types tested are in ALWAYSREADY_MENTAL_DAMAGE_TYPES.
//           ONLY the forced reload (and its end of turn) is countered; the overwatch at the end of the turn always happens. The counter is switched by the Mod Config
//           Menu checkbox ALWAYSREADY_MENTAL_PROTECTION_COUNTERS (default true), read when used; the ability texts follow it (ALWAYSREADY_MENTAL_LONG / _HELP).
//---------------------------------------------------------------------------------------
class UT_Trait_AlwaysReady extends UT_TraitBase config(UniqueTraits);

var config int ALWAYSREADY_RELOAD_BASE_CHANCE_PCT;
var config float ALWAYSREADY_RELOAD_WILL_FACTOR;
var config float ALWAYSREADY_RELOAD_AMMO_FACTOR;
// Damage types of the mental effects: a holder immune to ANY of them does not get the forced reload ('Mental' is the type Chaotic Mind tests).
var config array<name> ALWAYSREADY_MENTAL_DAMAGE_TYPES;
// false: mental protection changes nothing (the forced reload happens whatever the soldier carries).
var config bool ALWAYSREADY_MENTAL_PROTECTION_COUNTERS;
var localized string ALWAYSREADY_RELOAD_FLYOVER;
// Pieces of the ability texts, used only while the counter is on (GetTextValue).
var localized string ALWAYSREADY_MENTAL_LONG, ALWAYSREADY_MENTAL_HELP;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(AlwaysReady());
	Templates.AddItem(AlwaysReadyOverwatch());

	return Templates;
}

// Event registrations (X2EventListener_UniqueTraits.CreateTacticalListeners calls this for every trait of the pool that is not disabled).
static function OnCreateTacticalListeners(CHEventListenerTemplate Template)
{
	Template.AddCHEvent('AbilityActivated', OnAbilityActivated_AlwaysReady, ELD_OnStateSubmitted, 50);
}

// Always ready: this passive is just the icon holder. The malus (chance to force a reload and
// end the turn after acting with a weapon that isn't full) is handled separately by
// UT_Trait_AlwaysReady.OnAbilityActivated_AlwaysReady, a reimplementation
// of vanilla's Trait_ObsessiveReloader personality trait's own trigger gate.
// The bonus is UT_AlwaysReadyOverwatch below.
static function X2AbilityTemplate AlwaysReady()
{
	local X2AbilityTemplate Template;

	Template = PurePassive('UT_AlwaysReady', "img:///UniqueTraits_Icons.UT_AlwaysReady", true);

	return Template;
}

// Enters in overwatch at the end of the turn (if not already in overwatch and have ammo left).
static function X2AbilityTemplate AlwaysReadyOverwatch()
{
	local X2AbilityTemplate Template;
	local X2AbilityTrigger_EventListener Trigger;
	local X2Effect_ReserveOverwatchPoints ReserveEffect;
	local X2Effect_CoveringFire CoveringFireEffect;
	local X2Condition_AbilityProperty CoveringFireCondition;

	`CREATE_X2ABILITY_TEMPLATE(Template, 'UT_AlwaysReadyOverwatch');

	Template.IconImage = "img:///UILibrary_PerkIcons.UIPerk_standard";
	Template.AbilitySourceName = 'eAbilitySource_Perk';
	Template.eAbilityIconBehaviorHUD = eAbilityIconBehavior_NeverShow;
	Template.Hostility = eHostility_Neutral;
	Template.bCrossClassEligible = true;
	Template.bDontDisplayInAbilitySummary = true;
	// Helper ability: only the trait's own UT_AlwaysReady is shown to the player (also hidden from the ability tooltips).
	Template.bDisplayInUITooltip = false;
	Template.bDisplayInUITacticalText = false;

	Template.AbilityToHitCalc = default.DeadEye;
	Template.AbilityTargetStyle = default.SelfTarget;
	Template.AbilityShooterConditions.AddItem(default.LivingShooterProperty);
	Template.AbilityShooterConditions.AddItem(new class'X2Condition_UT_ExcludeAlreadyOverwatching');

	Trigger = new class'X2AbilityTrigger_EventListener';
	Trigger.ListenerData.Deferral = ELD_OnStateSubmitted;
	Trigger.ListenerData.EventID = 'PlayerTurnEnded';
	Trigger.ListenerData.Filter = eFilter_Player;
	Trigger.ListenerData.EventFn = class'XComGameState_Ability'.static.AbilityTriggerEventListener_Self;
	Template.AbilityTriggers.AddItem(Trigger);

	ReserveEffect = new class'X2Effect_ReserveOverwatchPoints';
	Template.AddTargetEffect(ReserveEffect);

	CoveringFireEffect = new class'X2Effect_CoveringFire';
	CoveringFireEffect.AbilityToActivate = 'OverwatchShot';
	CoveringFireEffect.BuildPersistentEffect(1, false, true, false, eGameRule_PlayerTurnBegin);
	CoveringFireCondition = new class'X2Condition_AbilityProperty';
	CoveringFireCondition.OwnerHasSoldierAbilities.AddItem('CoveringFire');
	CoveringFireEffect.TargetConditions.AddItem(CoveringFireCondition);
	Template.AddTargetEffect(CoveringFireEffect);

	Template.BuildNewGameStateFn = TypicalAbility_BuildGameState;
	// Vanilla overwatch visualization: the unit's "Overwatch" voice line, flyover and camera frame, which an auto-triggered
	// ability otherwise skips entirely (no visualization function = silent and no stance change on screen).
	Template.BuildVisualizationFn = class'X2Ability_DefaultAbilitySet'.static.OverwatchAbility_BuildVisualization;
	Template.CinescriptCameraType = "Overwatch";

	return Template;
}

// Custom Chance formula (different from vanilla obsessive reloader trait) :
// FinalChancePct = BASE + WillPercentMark * WILL_FACTOR + MissingAmmoPercent * AMMO_FACTOR
// WillPercentMark mirrors vanilla's own stress metric (XComGameState_Unit.uc:911,
// RollForNegativeTrait: 100 - CurrentWill/MaxWill*100 => 0 at full Will, 100 at zero Will).
// MissingAmmoPercent is the same shape applied to the primary weapon's ammo (0 at full clip, 100
// empty) => always > 0 here since the gate above already requires Ammo < GetClipSize().
static function EventListenerReturn OnAbilityActivated_AlwaysReady(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit SourceUnit, MutableUnit;
	local XComGameState_Item SourceWeapon, MutableWeapon;
	local XComGameState NewGameState;
	local float WillPercentMark, MissingAmmoPercent, FinalChancePct;

	if (GameState.GetContext().InterruptionStatus == eInterruptionStatus_Interrupt)
		return ELR_NoInterrupt;

	SourceUnit = XComGameState_Unit(EventSource);
	if (SourceUnit == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SourceUnit, 'UT_AlwaysReady'))
		return ELR_NoInterrupt;

	if (SourceUnit.NumActionPoints() <= 0)
		return ELR_NoInterrupt;

	SourceWeapon = SourceUnit.GetPrimaryWeapon();
	if (SourceWeapon == none || SourceWeapon.Ammo >= SourceWeapon.GetClipSize() || SourceWeapon.GetClipSize() <= 0)
		return ELR_NoInterrupt;

	WillPercentMark = 100.0 - (SourceUnit.GetCurrentStat(eStat_Will) / SourceUnit.GetMaxStat(eStat_Will)) * 100.0;
	MissingAmmoPercent = 100.0 - (float(SourceWeapon.Ammo) / float(SourceWeapon.GetClipSize())) * 100.0;

	FinalChancePct = default.ALWAYSREADY_RELOAD_BASE_CHANCE_PCT
		+ WillPercentMark * default.ALWAYSREADY_RELOAD_WILL_FACTOR
		+ MissingAmmoPercent * default.ALWAYSREADY_RELOAD_AMMO_FACTOR;
	FinalChancePct = FClamp(FinalChancePct, 0.0, 100.0);

	if (`SYNC_FRAND_STATIC() >= FinalChancePct / 100.0)
		return ELR_NoInterrupt;

	// Only checked once the roll succeeded (the immunity scan walks the unit's effects): a mind-protected holder is spared the compulsion, no reload, the turn goes on.
	if (IsProtectedFromMentalEffects(SourceUnit))
	{
		`log("UniqueTraits : Always ready -- obsessive reload countered for" @ SourceUnit.GetFullName() @ "(immune to mental effects)",, 'UniqueTraits');
		return ELR_NoInterrupt;
	}

	`log("UniqueTraits : Always ready -- obsessive reload roll triggered for" @ SourceUnit.GetFullName()
		$ " (WillPercentMark=" $ WillPercentMark $ " MissingAmmoPercent=" $ MissingAmmoPercent
		$ " FinalChancePct=" $ FinalChancePct $ ")",, 'UniqueTraits');

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Always ready forced reload");
	XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = BuildVisualization_ForcedReload;
	MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', SourceUnit.ObjectID));
	MutableWeapon = XComGameState_Item(NewGameState.ModifyStateObject(class'XComGameState_Item', SourceWeapon.ObjectID));
	MutableWeapon.Ammo = MutableWeapon.GetClipSize();
	MutableUnit.ActionPoints.Length = 0;
	`GAMERULES.SubmitGameState(NewGameState);

	`log("UniqueTraits : Always ready -- obsessive reload triggered for" @ SourceUnit.GetFullName() $ ", weapon reloaded, turn ended",, 'UniqueTraits');

	return ELR_NoInterrupt;
}

// Mind Shield, Solace, a gene mod... : the unit is immune to one of the mental damage types (the test Chaotic Mind uses).
static final function bool IsProtectedFromMentalEffects(XComGameState_Unit Unit)
{
	local name DamageType;

	if (!default.ALWAYSREADY_MENTAL_PROTECTION_COUNTERS)
		return false;

	foreach default.ALWAYSREADY_MENTAL_DAMAGE_TYPES(DamageType)
	{
		if (Unit.IsImmuneToDamage(DamageType))
			return true;
	}

	return false;
}

// The pieces of the texts that mention the mental protection (UT_TextTags): empty while the option is off.
static function bool GetTextValue(string Key, out string OutString)
{
	if (Key ~= "ALWAYSREADY_MENTAL_LONG")
		OutString = default.ALWAYSREADY_MENTAL_PROTECTION_COUNTERS ? default.ALWAYSREADY_MENTAL_LONG : "";
	else if (Key ~= "ALWAYSREADY_MENTAL_HELP")
		OutString = default.ALWAYSREADY_MENTAL_PROTECTION_COUNTERS ? default.ALWAYSREADY_MENTAL_HELP : "";
	else
		return false;

	return true;
}

// The forced reload plays vanilla's own reload (HL_Reload animation, the unit's reload voice line) plus the trait's flyover.
static function BuildVisualization_ForcedReload(XComGameState VisualizeGameState)
{
	local XComGameStateHistory History;
	local XComGameState_Unit UnitState;
	local VisualizationActionMetadata ActionMetadata;
	local X2Action_PlayAnimation PlayAnimation;
	local X2Action_PlaySoundAndFlyOver SoundAndFlyOver;
	local X2AbilityTemplate ReloadTemplate;

	History = `XCOMHISTORY;

	foreach VisualizeGameState.IterateByClassType(class'XComGameState_Unit', UnitState)
		break;
	if (UnitState == none)
		return;

	ActionMetadata.StateObject_OldState = History.GetGameStateForObjectID(UnitState.ObjectID, eReturnType_Reference, VisualizeGameState.HistoryIndex - 1);
	ActionMetadata.StateObject_NewState = UnitState;
	ActionMetadata.VisualizeActor = History.GetVisualizer(UnitState.ObjectID);

	PlayAnimation = X2Action_PlayAnimation(class'X2Action_PlayAnimation'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, ActionMetadata.LastActionAdded));
	PlayAnimation.Params.AnimName = 'HL_Reload';

	ReloadTemplate = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager().FindAbilityTemplate('Reload');
	SoundAndFlyOver = X2Action_PlaySoundAndFlyOver(class'X2Action_PlaySoundAndFlyOver'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, ActionMetadata.LastActionAdded));
	SoundAndFlyOver.SetSoundAndFlyOverParameters(none, default.ALWAYSREADY_RELOAD_FLYOVER, ReloadTemplate.ActivationSpeech, eColor_Bad);
}
