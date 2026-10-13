//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_StayFocus.uc
//  PURPOSE: Stay focus: free-action ally buff; its Will cost is UT_Trait_StayFocus.OnAbilityActivated_StayFocus.
//---------------------------------------------------------------------------------------
class UT_Trait_StayFocus extends UT_TraitBase config(UniqueTraits);

var config int STAYFOCUS_WILL_LOSS;

var config int STAYFOCUS_AIM_BONUS, STAYFOCUS_CRIT_BONUS;
var config int STAYFOCUS_RADIUS_TILES;
var config int STAYFOCUS_COOLDOWN;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(StayFocus());

	return Templates;
}

// Stay focus: free action (STAYFOCUS_COOLDOWN-turn cooldown) that grants nearby allies (not
// self) +10 Aim/+5 Crit until their next turn. The malus is a fixed Will loss for the user on every
// use (OnAbilityActivated_StayFocus below).
static function X2AbilityTemplate StayFocus()
{
	local X2AbilityTemplate Template;
	local X2AbilityCost_ActionPoints ActionPointCost;
	local X2AbilityCooldown Cooldown;
	local X2AbilityMultiTarget_Radius RadiusMultiTarget;
	local X2Condition_UnitProperty AllyCondition;
	local X2Condition_UnitStatCheck WillCheck;
	local X2Effect_PersistentStatChange StatEffect;

	`CREATE_X2ABILITY_TEMPLATE(Template, 'UT_StayFocus');

	Template.IconImage = "img:///UILibrary_PerkIcons.UIPerk_standard";
	Template.AbilitySourceName = 'eAbilitySource_Perk';
	Template.Hostility = eHostility_Defensive;
	Template.AbilityToHitCalc = default.DeadEye;
	Template.AbilityTargetStyle = default.SelfTarget;

	// Unusable once the user can't pay its fixed Will cost (UT_Trait_StayFocus.STAYFOCUS_WILL_LOSS).
	WillCheck = new class'X2Condition_UnitStatCheck';
	WillCheck.AddCheckStat(eStat_Will, default.STAYFOCUS_WILL_LOSS, eCheck_GreaterThanOrEqual);
	Template.AbilityShooterConditions.AddItem(WillCheck);

	// Free, but only usable while the soldier still has an action point (iNumPoints = 1 with bFreeCost, like vanilla's FreeActionCost that
	// LWOTC's Rapid Deployment uses): CanAfford checks the points even though none is taken. iNumPoints left at 0 made it usable after the turn ended.
	ActionPointCost = new class'X2AbilityCost_ActionPoints';
	ActionPointCost.iNumPoints = 1;
	ActionPointCost.bFreeCost = true;
	Template.AbilityCosts.AddItem(ActionPointCost);

	Cooldown = new class'X2AbilityCooldown';
	Cooldown.iNumTurns = default.STAYFOCUS_COOLDOWN;
	Template.AbilityCooldown = Cooldown;

	RadiusMultiTarget = new class'X2AbilityMultiTarget_Radius';
	RadiusMultiTarget.fTargetRadius = default.STAYFOCUS_RADIUS_TILES * class'XComWorldData'.const.WORLD_StepSize * class'XComWorldData'.const.WORLD_UNITS_TO_METERS_MULTIPLIER;
	RadiusMultiTarget.bExcludeSelfAsTargetIfWithinRadius = true;
	// The targeting UI can't conform to partial cover, and without this the zone (and its targets) is
	// clipped by it like a smoke grenade's; vanilla does the same (X2Ability_DefaultAbilitySet.uc:2319).
	RadiusMultiTarget.bIgnoreBlockingCover = true;
	Template.AbilityMultiTargetStyle = RadiusMultiTarget;

	AllyCondition = new class'X2Condition_UnitProperty';
	AllyCondition.ExcludeDead = true;
	AllyCondition.ExcludeHostileToSource = true;
	AllyCondition.ExcludeFriendlyToSource = false;
	Template.AbilityMultiTargetConditions.AddItem(AllyCondition);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_StayFocus_Buff';
	StatEffect.BuildPersistentEffect(1, false, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_Offense, default.STAYFOCUS_AIM_BONUS);
	StatEffect.AddPersistentStatChange(eStat_CritChance, default.STAYFOCUS_CRIT_BONUS);
	Template.AddMultiTargetEffect(StatEffect);

	Template.AbilityTriggers.AddItem(default.PlayerInputTrigger);

	Template.BuildNewGameStateFn = TypicalAbility_BuildGameState;
	Template.BuildVisualizationFn = TypicalAbility_BuildVisualization;

	return Template;
}

// Stay focus's malus: a FIXED STAYFOCUS_WILL_LOSS Will loss for the holder each time they use the ability.
static function EventListenerReturn OnAbilityActivated_StayFocus(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateContext_Ability AbilityContext;
	local XComGameState_Unit SourceUnit, MutableUnit;
	local XComGameState NewGameState;
	local int NewWill;

	if (!ParseAbilityActivation(GameState, EventSource, 'UT_StayFocus', AbilityContext, SourceUnit))
		return ELR_NoInterrupt;

	if (AbilityContext.InputContext.AbilityTemplateName != 'UT_StayFocus')
		return ELR_NoInterrupt;

	NewWill = Max(0, int(SourceUnit.GetCurrentStat(eStat_Will)) - default.STAYFOCUS_WILL_LOSS);
	if (NewWill >= int(SourceUnit.GetCurrentStat(eStat_Will)))
		return ELR_NoInterrupt;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Stay focus will loss");
	MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', SourceUnit.ObjectID));
	MutableUnit.SetCurrentStat(eStat_Will, NewWill);
	`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}
