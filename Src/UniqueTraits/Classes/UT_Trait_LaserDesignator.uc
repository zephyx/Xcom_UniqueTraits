//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_LaserDesignator.uc
//  PURPOSE: Laser designator: grants a free ability (free action, LASERDESIGNATOR_COOLDOWN-turn cooldown). It primes the holder: the next time he
//           fires his PRIMARY weapon or holotargets an enemy (the main target only, even for multi-target attacks), that enemy gets the
//           mark for LASERDESIGNATOR_MARK_TURNS turn(s) (the effect ticks at the start of XCOM's turns, its player being the holder's:
//           applied during XCOM's turn, it ends, and Shadowstep comes back, at the start of XCOM's NEXT turn): it loses its Shadowstep (the effect names of LASERDESIGNATOR_SUPPRESSED_EFFECTS)
//           and GAINS LASERDESIGNATOR_DODGE_BONUS dodge. If the enemy is holotargeted, the designator's cooldown is reduced by LASERDESIGNATOR_HOLOTARGET_COOLDOWN_REDUCTION.
//           - UT_LaserDesignator: the active ability; its effect is the "primed" marker (effect UT_LaserDesignator_Primed on the holder).
//           - OnAbilityActivated_LaserDesignator ('AbilityActivated', ELD_OnStateSubmitted): consumes the marker and applies the mark, in a
//             change container of its own (effect of the hidden ability UT_LaserDesignatorMark; effect 1 of it restores Shadowstep when the
//             mark ends, see X2Effect_UT_LaserMark).
//---------------------------------------------------------------------------------------
class UT_Trait_LaserDesignator extends UT_TraitBase config(UniqueTraits);

var config int LASERDESIGNATOR_COOLDOWN, LASERDESIGNATOR_MARK_TURNS, LASERDESIGNATOR_DODGE_BONUS, LASERDESIGNATOR_HOLOTARGET_COOLDOWN_REDUCTION;
var config array<name> LASERDESIGNATOR_SUPPRESSED_EFFECTS;
var config array<name> LASERDESIGNATOR_HOLOTARGET_EFFECTS;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(LaserDesignator());
	Templates.AddItem(LaserDesignatorMark());

	return Templates;
}

// Event registrations (X2EventListener_UniqueTraits.CreateTacticalListeners calls this for every trait of the pool that is not disabled).
static function OnCreateTacticalListeners(CHEventListenerTemplate Template)
{
	// Chemist: the disease on the enemies a damage over time was just inflicted on. Laser designator: consumes the primed marker on the next primary
	// shot / holotarget and marks the main target. Both react to a submitted ability state and apply their effect in a state of their own.
	Template.AddCHEvent('AbilityActivated', OnAbilityActivated_LaserDesignator, ELD_OnStateSubmitted, 50);
}

// The free ability: self-targeted, free action, cooldown. Its only effect is the "primed" marker, consumed by the next shot or holotarget.
static function X2AbilityTemplate LaserDesignator()
{
	local X2AbilityTemplate Template;
	local X2AbilityCost_ActionPoints ActionPointCost;
	local X2AbilityCooldown Cooldown;
	local X2Effect_Persistent PrimedEffect;

	`CREATE_X2ABILITY_TEMPLATE(Template, 'UT_LaserDesignator');

	Template.IconImage = "img:///UniqueTraits_Icons.UT_LaserDesignator";
	Template.AbilitySourceName = 'eAbilitySource_Perk';
	Template.Hostility = eHostility_Neutral;
	Template.eAbilityIconBehaviorHUD = eAbilityIconBehavior_AlwaysShow;
	Template.AbilityToHitCalc = default.DeadEye;
	Template.AbilityTargetStyle = default.SelfTarget;
	Template.AbilityShooterConditions.AddItem(default.LivingShooterProperty);

	// Free, but only usable while the soldier still has an action point (iNumPoints = 1 with bFreeCost, like vanilla's FreeActionCost that
	// LWOTC's Rapid Deployment uses): CanAfford checks the points even though none is taken. iNumPoints left at 0 made it usable after the turn ended.
	ActionPointCost = new class'X2AbilityCost_ActionPoints';
	ActionPointCost.iNumPoints = 1;
	ActionPointCost.bFreeCost = true;
	Template.AbilityCosts.AddItem(ActionPointCost);

	Cooldown = new class'X2AbilityCooldown';
	Cooldown.iNumTurns = default.LASERDESIGNATOR_COOLDOWN;
	Template.AbilityCooldown = Cooldown;

	// Primed until used: lasts the mission (the cooldown only starts counting when the ability is used).
	PrimedEffect = new class'X2Effect_Persistent';
	PrimedEffect.EffectName = 'UT_LaserDesignator_Primed';
	PrimedEffect.DuplicateResponse = eDupe_Ignore;
	PrimedEffect.BuildPersistentEffect(1, true, false);
	PrimedEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, true,, Template.AbilitySourceName);
	Template.AddTargetEffect(PrimedEffect);

	Template.AbilityTriggers.AddItem(default.PlayerInputTrigger);

	Template.BuildNewGameStateFn = TypicalAbility_BuildGameState;
	Template.BuildVisualizationFn = TypicalAbility_BuildVisualization;

	return Template;
}

// Holder of the mark (effect 0) and of the effect that gives Shadowstep back when the mark ends (effect 1): hidden, never granted.
static function X2AbilityTemplate LaserDesignatorMark()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_LaserMark MarkEffect;
	local X2Effect_Persistent RestoreEffect;
	local name SuppressedName;

	Template = HiddenEffectHolder('UT_LaserDesignatorMark');
	Template.Hostility = eHostility_Offensive;

	MarkEffect = new class'X2Effect_UT_LaserMark';
	MarkEffect.EffectName = 'UT_LaserDesignator_Mark';
	foreach default.LASERDESIGNATOR_SUPPRESSED_EFFECTS(SuppressedName)
		MarkEffect.EffectNamesToSuppress.AddItem(SuppressedName);
	MarkEffect.RestoreAbilityName = 'UT_LaserDesignatorMark';
	MarkEffect.RestoreEffectIndex = 1;
	MarkEffect.BuildPersistentEffect(default.LASERDESIGNATOR_MARK_TURNS, false, true, false, eGameRule_PlayerTurnBegin);
	MarkEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, true,, Template.AbilitySourceName);
	MarkEffect.AddPersistentStatChange(eStat_Dodge, default.LASERDESIGNATOR_DODGE_BONUS);
	Template.AddTargetEffect(MarkEffect);

	// The vanilla Shadowstep (a plain persistent effect with that name, which the game tests by name), given back when the mark ends.
	RestoreEffect = new class'X2Effect_Persistent';
	RestoreEffect.EffectName = 'Shadowstep';
	RestoreEffect.DuplicateResponse = eDupe_Ignore;
	RestoreEffect.BuildPersistentEffect(1, true, false);
	Template.AddTargetEffect(RestoreEffect);

	return Template;
}

// The restored Shadowstep must be listed when the unit is inspected: the UI lists the persistent effects that have display info (bDisplayInUI), which
// the plain effect of LaserDesignatorMark() lacks. Copied from the real Shadowstep template once every template exists (so another mod's changes to its
// text or icon are followed).
static function OnPostTemplatesCreated()
{
	local X2AbilityTemplateManager Manager;
	local X2AbilityTemplate ShadowstepTemplate, MarkTemplate;
	local X2Effect_Persistent RestoreEffect;

	Manager = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();
	ShadowstepTemplate = Manager.FindAbilityTemplate('Shadowstep');
	MarkTemplate = Manager.FindAbilityTemplate('UT_LaserDesignatorMark');
	if (ShadowstepTemplate == none || MarkTemplate == none || MarkTemplate.AbilityTargetEffects.Length < 2)
	{
		`log("UniqueTraits [WARN] : Laser designator -- Shadowstep or UT_LaserDesignatorMark template not found, the restored Shadowstep will not be listed in the unit inspection",, 'UniqueTraits');
		return;
	}

	RestoreEffect = X2Effect_Persistent(MarkTemplate.AbilityTargetEffects[1]);
	if (RestoreEffect != none)
		RestoreEffect.SetDisplayInfo(ePerkBuff_Passive, ShadowstepTemplate.LocFriendlyName, ShadowstepTemplate.GetMyLongDescription(), ShadowstepTemplate.IconImage,,, ShadowstepTemplate.AbilitySourceName);
}

static final function bool IsHolotargeted(XComGameState_Unit Target)
{
	local name EffectName;

	foreach default.LASERDESIGNATOR_HOLOTARGET_EFFECTS(EffectName)
	{
		if (Target.IsUnitAffectedByEffectName(EffectName))
			return true;
	}

	return false;
}

// True if this activation (a submitted state) applied a holotarget effect to the unit: the holotarget action itself, whatever the ability.
static final function bool AppliedHolotarget(XComGameState GameState, int SourceID, int TargetID)
{
	local XComGameState_Effect EffectState;

	foreach GameState.IterateByClassType(class'XComGameState_Effect', EffectState)
	{
		if (EffectState.ApplyEffectParameters.SourceStateObjectRef.ObjectID == SourceID && EffectState.ApplyEffectParameters.TargetStateObjectRef.ObjectID == TargetID
			&& EffectState.GetPreviousVersion() == none && default.LASERDESIGNATOR_HOLOTARGET_EFFECTS.Find(EffectState.GetX2Effect().EffectName) != INDEX_NONE)
			return true;
	}

	return false;
}

// 'AbilityActivated' fires more than once per ability: the interrupt step is skipped.
static function EventListenerReturn OnAbilityActivated_LaserDesignator(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateHistory History;
	local XComGameStateContext_Ability AbilityContext;
	local XComGameState_Ability AbilityState, DesignatorState;
	local XComGameState_Unit SourceUnit, TargetUnit, MutableTarget;
	local XComGameState_Effect PrimedState;
	local XComGameState_Item SourceWeapon;
	local StateObjectReference DesignatorRef;
	local XComGameState NewGameState;
	local bool bPrimaryShot, bHolotargeted;

	if (!ParseAbilityActivation(GameState, EventSource, 'UT_LaserDesignator', AbilityContext, SourceUnit))
		return ELR_NoInterrupt;

	AbilityState = XComGameState_Ability(EventData);
	if (AbilityState == none || AbilityContext.InputContext.AbilityTemplateName == 'UT_LaserDesignator')
		return ELR_NoInterrupt;

	PrimedState = SourceUnit.GetUnitAffectedByEffectState('UT_LaserDesignator_Primed');
	if (PrimedState == none)
		return ELR_NoInterrupt;

	// Main target only: an enemy unit that is alive.
	History = `XCOMHISTORY;
	TargetUnit = XComGameState_Unit(History.GetGameStateForObjectID(AbilityContext.InputContext.PrimaryTarget.ObjectID));
	if (TargetUnit == none || !TargetUnit.IsAlive() || !SourceUnit.IsEnemyUnit(TargetUnit))
		return ELR_NoInterrupt;

	// A shot with the primary weapon (an offensive ability fired from the primary slot) or the holotarget action.
	SourceWeapon = AbilityState.GetSourceWeapon();
	bPrimaryShot = AbilityState.GetMyTemplate().Hostility == eHostility_Offensive && SourceWeapon != none && SourceWeapon.InventorySlot == eInvSlot_PrimaryWeapon;
	if (!bPrimaryShot && !AppliedHolotarget(GameState, SourceUnit.ObjectID, TargetUnit.ObjectID))
		return ELR_NoInterrupt;

	bHolotargeted = IsHolotargeted(TargetUnit);

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Laser designator mark");
	MutableTarget = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', TargetUnit.ObjectID));
	if (class'UT_EffectHelpers'.static.ApplyAbilityEffect('UT_LaserDesignatorMark', 0, SourceUnit, MutableTarget, NewGameState, AbilityContext) != 'AA_Success')
	{
		History.CleanupPendingGameState(NewGameState);
		return ELR_NoInterrupt;
	}

	// The marker is used up.
	PrimedState.RemoveEffect(NewGameState, NewGameState, true);

	// A holotargeted enemy shortens the cooldown.
	if (bHolotargeted && default.LASERDESIGNATOR_HOLOTARGET_COOLDOWN_REDUCTION > 0)
	{
		DesignatorRef = SourceUnit.FindAbility('UT_LaserDesignator');
		if (DesignatorRef.ObjectID != 0)
		{
			DesignatorState = XComGameState_Ability(NewGameState.ModifyStateObject(class'XComGameState_Ability', DesignatorRef.ObjectID));
			DesignatorState.iCooldown = Max(0, DesignatorState.iCooldown - default.LASERDESIGNATOR_HOLOTARGET_COOLDOWN_REDUCTION);
		}
	}

	XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = BuildVisualization_LaserDesignatorMark;
	`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}

static function BuildVisualization_LaserDesignatorMark(XComGameState VisualizeGameState)
{
	class'UT_EffectHelpers'.static.AddEffectVisualization(VisualizeGameState, 'UT_LaserDesignatorMark', 0);
}
