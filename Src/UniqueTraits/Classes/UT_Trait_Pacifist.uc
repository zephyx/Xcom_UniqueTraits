//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Pacifist.uc
//  PURPOSE: Pacifist:
//           + Active ability UT_PacifistStayCovered (granted by the passive's AdditionalAbilities): no action point cost at all (usable even with none left),
//             cooldown PACIFIST_COOLDOWN (1). Every friendly unit within PACIFIST_RADIUS_TILES tiles of the holder (himself included) gets
//             +PACIFIST_DEFENSE_BONUS Defense and +PACIFIST_DODGE_BONUS Dodge until the start of XCOM's next turn. Requires that the holder inflicted
//             no damage during the PREVIOUS turn (X2Condition_UnitValue on UT_Pacifist_DealtLast).
//           - He can never overwatch: OnPostTemplatesCreated adds X2Condition_UT_PacifistNoOverwatch to every ability that reserves overwatch points.
//           "Damage inflicted" is tracked by OnAbilityActivated_Pacifist: an activation by the holder after which another unit has a damage result
//           (health or shield, not armor-absorbed) of THAT activation sets the marker UnitValue UT_Pacifist_Dealt (this cycle). At each XCOM turn start
//           OnPlayerTurnBegun_Pacifist moves it to UT_Pacifist_DealtLast (the previous cycle, what the ability checks) and clears it.
//---------------------------------------------------------------------------------------
class UT_Trait_Pacifist extends UT_TraitBase config(UniqueTraits);

var config int PACIFIST_DEFENSE_BONUS, PACIFIST_DODGE_BONUS, PACIFIST_RADIUS_TILES, PACIFIST_COOLDOWN;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Pacifist());
	Templates.AddItem(PacifistStayCovered());

	return Templates;
}

// Event registrations (X2EventListener_UniqueTraits.CreateTacticalListeners calls this for every trait of the pool that is not disabled).
static function OnCreateTacticalListeners(CHEventListenerTemplate Template)
{
	// Pacifist: the marker "inflicted damage" (after the ability resolved), and its move to "previous turn" at the start of XCOM's turns.
	Template.AddCHEvent('AbilityActivated', OnAbilityActivated_Pacifist, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('PlayerTurnBegun', OnPlayerTurnBegun_Pacifist, ELD_OnStateSubmitted, 50);
}

// The passive: the ban on overwatch is code (OnPostTemplatesCreated); it brings the active ability along (AdditionalAbilities, so a holder who already
// existed before the ability was added gets it too).
static function X2AbilityTemplate Pacifist()
{
	local X2AbilityTemplate Template;

	Template = PurePassive('UT_Pacifist', "img:///UniqueTraits_Icons.UT_Pacifist", true);
	Template.AdditionalAbilities.AddItem('UT_PacifistStayCovered');

	return Template;
}

// The "Stay covered" ability (modelled on Stay focus): self target with a radius multi target. Free, but like Stay focus it needs an action point left
// (iNumPoints = 1 + bFreeCost); the cooldown and the previous-turn rule are its other limits.
static function X2AbilityTemplate PacifistStayCovered()
{
	local X2AbilityTemplate Template;
	local X2AbilityCost_ActionPoints ActionPointCost;
	local X2AbilityCooldown Cooldown;
	local X2AbilityMultiTarget_Radius RadiusMultiTarget;
	local X2Condition_UnitProperty AllyCondition;
	local X2Condition_UnitValue NoDamageCondition;

	`CREATE_X2ABILITY_TEMPLATE(Template, 'UT_PacifistStayCovered');

	Template.IconImage = "img:///UILibrary_PerkIcons.UIPerk_standard";
	Template.AbilitySourceName = 'eAbilitySource_Perk';
	Template.Hostility = eHostility_Defensive;
	Template.AbilityToHitCalc = default.DeadEye;
	Template.AbilityTargetStyle = default.SelfTarget;

	Template.AbilityShooterConditions.AddItem(default.LivingShooterProperty);
	Template.AddShooterEffectExclusions();

	// Nothing inflicted during the previous turn (an absent value reads 0).
	NoDamageCondition = new class'X2Condition_UnitValue';
	NoDamageCondition.AddCheckValue('UT_Pacifist_DealtLast', 0, eCheck_Exact);
	Template.AbilityShooterConditions.AddItem(NoDamageCondition);

	// Free, but only usable while the soldier still has an action point (as Stay focus): CanAfford checks the points even though none is taken.
	ActionPointCost = new class'X2AbilityCost_ActionPoints';
	ActionPointCost.iNumPoints = 1;
	ActionPointCost.bFreeCost = true;
	Template.AbilityCosts.AddItem(ActionPointCost);

	Cooldown = new class'X2AbilityCooldown';
	Cooldown.iNumTurns = default.PACIFIST_COOLDOWN;
	Template.AbilityCooldown = Cooldown;

	RadiusMultiTarget = new class'X2AbilityMultiTarget_Radius';
	RadiusMultiTarget.fTargetRadius = default.PACIFIST_RADIUS_TILES * class'XComWorldData'.const.WORLD_StepSize * class'XComWorldData'.const.WORLD_UNITS_TO_METERS_MULTIPLIER;
	// The holder is a target of his own ability (the target effect below), not of the multi target.
	RadiusMultiTarget.bExcludeSelfAsTargetIfWithinRadius = true;
	// As Stay focus (and vanilla, X2Ability_DefaultAbilitySet.uc:2319): the zone must not be clipped by partial cover.
	RadiusMultiTarget.bIgnoreBlockingCover = true;
	Template.AbilityMultiTargetStyle = RadiusMultiTarget;

	AllyCondition = new class'X2Condition_UnitProperty';
	AllyCondition.ExcludeDead = true;
	AllyCondition.ExcludeHostileToSource = true;
	AllyCondition.ExcludeFriendlyToSource = false;
	AllyCondition.ExcludeCivilian = true;
	Template.AbilityMultiTargetConditions.AddItem(AllyCondition);

	// Two instances of the same effect: one for the holder, one for the others.
	Template.AddTargetEffect(CreateCoveredEffect(Template));
	Template.AddMultiTargetEffect(CreateCoveredEffect(Template));

	Template.AbilityTriggers.AddItem(default.PlayerInputTrigger);

	Template.BuildNewGameStateFn = TypicalAbility_BuildGameState;
	Template.BuildVisualizationFn = BuildVisualization_StayCovered;

	return Template;
}

// +defense / +dodge until the start of XCOM's next turn (1 turn watched at PlayerTurnBegin, bound to the holder's player: XCOM's).
static function X2Effect_PersistentStatChange CreateCoveredEffect(X2AbilityTemplate Template)
{
	local X2Effect_PersistentStatChange StatEffect;

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_Pacifist_StayCovered';
	StatEffect.BuildPersistentEffect(1, false, false, false, eGameRule_PlayerTurnBegin);
	StatEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_Defense, default.PACIFIST_DEFENSE_BONUS);
	StatEffect.AddPersistentStatChange(eStat_Dodge, default.PACIFIST_DODGE_BONUS);

	return StatEffect;
}

// UT_TraitBase.OnPostTemplatesCreated (called for every trait of the pool by X2DownloadableContentInfo_UniqueTraits): "never overwatch". Every ability that reserves overwatch points (the plain and the
// pistol overwatch, Long Watch, the overwatch of other mods...: an X2Effect_ReserveOverwatchPoints, or a reserve effect of an overwatch action point type,
// on the shooter, the target or the multi targets) gets a shooter condition that fails for a holder of this trait. Suppression, Kill Zone and the other
// reserve types are NOT overwatch and are left alone.
static function OnPostTemplatesCreated()
{
	local X2AbilityTemplateManager AbilityManager;
	local X2DataTemplate DataTemplate;
	local X2AbilityTemplate Template;
	local int Patched;

	AbilityManager = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();
	foreach AbilityManager.IterateTemplates(DataTemplate, none)
	{
		Template = X2AbilityTemplate(DataTemplate);
		if (Template == none)
			continue;

		if (HasOverwatchEffect(Template.AbilityShooterEffects) || HasOverwatchEffect(Template.AbilityTargetEffects) || HasOverwatchEffect(Template.AbilityMultiTargetEffects))
		{
			Template.AbilityShooterConditions.AddItem(new class'X2Condition_UT_PacifistNoOverwatch');
			++Patched;
			`log("UniqueTraits : Pacifist -- overwatch ability closed to the holder:" @ Template.DataName,, 'UniqueTraits');
		}
	}

	`log("UniqueTraits : Pacifist --" @ Patched @ "overwatch abilit(y/ies) patched",, 'UniqueTraits');
}

static final function bool HasOverwatchEffect(array<X2Effect> Effects)
{
	local X2Effect Effect;
	local X2Effect_ReserveActionPoints ReserveEffect;

	foreach Effects(Effect)
	{
		ReserveEffect = X2Effect_ReserveActionPoints(Effect);
		if (ReserveEffect == none)
			continue;

		if (X2Effect_ReserveOverwatchPoints(ReserveEffect) != none
			|| ReserveEffect.ReserveType == class'X2CharacterTemplateManager'.default.OverwatchReserveActionPoint
			|| ReserveEffect.ReserveType == class'X2CharacterTemplateManager'.default.PistolOverwatchReserveActionPoint)
		{
			return true;
		}
	}

	return false;
}

// The standard visualization, plus a flyover with the ability's name and Hunker Down's sound cue and voice line (vanilla's own
// HunkerDownAbility_BuildVisualization plays SoundUI.HunkerDownCue with the speech 'HunkerDown', the flyover icon and a 1 s look-at).
static function BuildVisualization_StayCovered(XComGameState VisualizeGameState)
{
	local XComGameStateHistory History;
	local XComGameStateContext_Ability AbilityContext;
	local X2AbilityTemplate AbilityTemplate;
	local VisualizationActionMetadata ActionMetadata;
	local X2Action_PlaySoundAndFlyOver FlyOver;
	local int UnitID;

	class'X2Ability'.static.TypicalAbility_BuildVisualization(VisualizeGameState);

	AbilityContext = XComGameStateContext_Ability(VisualizeGameState.GetContext());
	if (AbilityContext == none)
		return;

	History = `XCOMHISTORY;
	UnitID = AbilityContext.InputContext.SourceObject.ObjectID;
	AbilityTemplate = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager().FindAbilityTemplate(AbilityContext.InputContext.AbilityTemplateName);
	if (AbilityTemplate == none || History.GetGameStateForObjectID(UnitID) == none)
		return;

	ActionMetadata.StateObject_OldState = History.GetGameStateForObjectID(UnitID, eReturnType_Reference, VisualizeGameState.HistoryIndex - 1);
	ActionMetadata.StateObject_NewState = VisualizeGameState.GetGameStateForObjectID(UnitID);
	ActionMetadata.VisualizeActor = History.GetVisualizer(UnitID);

	FlyOver = X2Action_PlaySoundAndFlyOver(class'X2Action_PlaySoundAndFlyOver'.static.AddToVisualizationTree(ActionMetadata, AbilityContext, false, ActionMetadata.LastActionAdded));
	FlyOver.SetSoundAndFlyOverParameters(SoundCue'SoundUI.HunkerDownCue', AbilityTemplate.LocFlyOverText, 'HunkerDown', eColor_Good, AbilityTemplate.IconImage, 1.0, true);
}

// True when a damage result of this very activation hurt the target (health or shield; what the armor absorbed does not count).
static final function bool WasDamagedBy(XComGameState_Unit Target, XComGameStateContext Context)
{
	local int i;

	for (i = 0; i < Target.DamageResults.Length; ++i)
	{
		if (Target.DamageResults[i].Context == Context && (Target.DamageResults[i].DamageAmount > 0 || Target.DamageResults[i].ShieldHP > 0))
			return true;
	}

	return false;
}

// 'AbilityActivated' (ELD_OnStateSubmitted): the holder's activation hurt someone else -> marker UT_Pacifist_Dealt (own change container, once per turn).
static function EventListenerReturn OnAbilityActivated_Pacifist(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateContext_Ability AbilityContext;
	local XComGameState_Unit SourceUnit, TargetUnit, MutableSource;
	local XComGameState NewGameState;

	if (!ParseAbilityActivation(GameState, EventSource, 'UT_Pacifist', AbilityContext, SourceUnit))
		return ELR_NoInterrupt;

	// The latest state of the holder (the event's object may predate a marker written by a previous activation).
	SourceUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(SourceUnit.ObjectID));
	if (SourceUnit == none || GetUnitFloat(SourceUnit, 'UT_Pacifist_Dealt') > 0)
		return ELR_NoInterrupt;

	foreach GameState.IterateByClassType(class'XComGameState_Unit', TargetUnit)
	{
		if (TargetUnit.ObjectID == SourceUnit.ObjectID || !WasDamagedBy(TargetUnit, GameState.GetContext()))
			continue;

		NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Pacifist inflicted damage");
		MutableSource = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', SourceUnit.ObjectID));
		MutableSource.SetUnitFloatValue('UT_Pacifist_Dealt', 1, eCleanup_BeginTactical);
		`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);
		break;
	}

	return ELR_NoInterrupt;
}

// 'PlayerTurnBegun' (ELD_OnStateSubmitted, XCOM's turns only): for each holder of the squad, what was inflicted since the previous XCOM turn start
// (UT_Pacifist_Dealt) becomes "the previous turn" (UT_Pacifist_DealtLast, checked by the ability), and the current one starts clean. A cycle runs
// from one XCOM turn start to the next (his own turn plus the enemy turn). Nothing is written when both markers are already clear.
static function EventListenerReturn OnPlayerTurnBegun_Pacifist(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateHistory History;
	local XComGameState_Player PlayerState;
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference SquadRef;
	local XComGameState_Unit Holder, MutableUnit;
	local XComGameState NewGameState;
	local float Dealt;

	PlayerState = XComGameState_Player(EventData);
	if (PlayerState == none || PlayerState.GetTeam() != eTeam_XCom)
		return ELR_NoInterrupt;

	History = `XCOMHISTORY;
	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	foreach XComHQ.Squad(SquadRef)
	{
		Holder = XComGameState_Unit(History.GetGameStateForObjectID(SquadRef.ObjectID));
		if (Holder == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Holder, 'UT_Pacifist'))
			continue;

		Dealt = GetUnitFloat(Holder, 'UT_Pacifist_Dealt');
		if (Dealt <= 0 && GetUnitFloat(Holder, 'UT_Pacifist_DealtLast') <= 0)
			continue;

		if (NewGameState == none)
			NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Pacifist turn markers");
		MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Holder.ObjectID));
		MutableUnit.SetUnitFloatValue('UT_Pacifist_DealtLast', (Dealt > 0) ? 1 : 0, eCleanup_BeginTactical);
		MutableUnit.SetUnitFloatValue('UT_Pacifist_Dealt', 0, eCleanup_BeginTactical);
	}

	if (NewGameState != none)
		`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}
