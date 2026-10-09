//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Chemist.uc
//  PURPOSE: Chemist: every time the holder inflicts a damage over time (poison, bleeding, acid, burning... any persistent effect with a weapon
//           damage effect in its ApplyOnTick) on a NON-ROBOTIC enemy, that enemy gets the "disease" for CHEMIST_DISEASE_TURNS turn(s): -CHEMIST_DAMAGE_MALUS
//           damage and -CHEMIST_AIM_MALUS aim on its attacks. In return the holder takes CHEMIST_DOT_DAMAGE_BONUS extra damage from DoT ticks.
//           - Detection: 'AbilityActivated' (ELD_OnStateSubmitted): the DoT effect states CREATED by the activation (no previous version) whose
//             source is the holder and whose target is an enemy.
//           - The disease is the effect of the hidden ability UT_ChemistDisease (never granted), applied in a change container of its own
//             like Tactician's disorient (an effect applied by hand must come from an ability template).
//---------------------------------------------------------------------------------------
class UT_Trait_Chemist extends UT_TraitBase config(UniqueTraits);

var config int CHEMIST_AIM_MALUS, CHEMIST_DAMAGE_MALUS, CHEMIST_DISEASE_TURNS, CHEMIST_DOT_DAMAGE_BONUS;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Chemist());
	Templates.AddItem(ChemistDisease());

	return Templates;
}

// Chemist: the drawback (+1 damage from DoT ticks); the disease on the enemies is OnAbilityActivated_Chemist.
static function X2AbilityTemplate Chemist()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_DoTVulnerability VulnerabilityEffect;

	Template = PurePassive('UT_Chemist', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	VulnerabilityEffect = new class'X2Effect_UT_DoTVulnerability';
	VulnerabilityEffect.EffectName = 'UT_Chemist_DoTVulnerability';
	VulnerabilityEffect.DamageBonus = default.CHEMIST_DOT_DAMAGE_BONUS;
	VulnerabilityEffect.BuildPersistentEffect(1, true, false);
	VulnerabilityEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(VulnerabilityEffect);

	return Template;
}

// Holder of the disease effect (hidden, never granted): its name and description are the disease's, shown on the enemy's unit flag.
static function X2AbilityTemplate ChemistDisease()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_Disease DiseaseEffect;

	Template = HiddenEffectHolder('UT_ChemistDisease');
	Template.Hostility = eHostility_Offensive;

	DiseaseEffect = new class'X2Effect_UT_Disease';
	DiseaseEffect.EffectName = 'UT_Chemist_Disease';
	DiseaseEffect.DamageReduction = default.CHEMIST_DAMAGE_MALUS;
	DiseaseEffect.BuildPersistentEffect(default.CHEMIST_DISEASE_TURNS, false, true, false, eGameRule_PlayerTurnBegin);
	DiseaseEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, true,, Template.AbilitySourceName);
	DiseaseEffect.AddPersistentStatChange(eStat_Offense, -default.CHEMIST_AIM_MALUS);
	Template.AddTargetEffect(DiseaseEffect);

	return Template;
}

// 'AbilityActivated' fires more than once per ability: the interrupt step is skipped.
static function EventListenerReturn OnAbilityActivated_Chemist(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateHistory History;
	local XComGameStateContext_Ability AbilityContext;
	local XComGameState_Unit SourceUnit, TargetUnit, MutableTarget;
	local XComGameState_Effect EffectState;
	local array<int> TargetIDs;
	local XComGameState NewGameState;
	local int TargetID, Applied;

	if (GameState.GetContext().InterruptionStatus == eInterruptionStatus_Interrupt)
		return ELR_NoInterrupt;

	SourceUnit = XComGameState_Unit(EventSource);
	AbilityContext = XComGameStateContext_Ability(GameState.GetContext());
	if (SourceUnit == none || AbilityContext == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SourceUnit, 'UT_Chemist'))
		return ELR_NoInterrupt;

	History = `XCOMHISTORY;

	// The DoTs this activation created: new effect states (no previous version) of the holder, on an enemy.
	foreach GameState.IterateByClassType(class'XComGameState_Effect', EffectState)
	{
		if (EffectState.ApplyEffectParameters.SourceStateObjectRef.ObjectID != SourceUnit.ObjectID || EffectState.GetPreviousVersion() != none)
			continue;
		if (!class'UT_EffectHelpers'.static.IsDamageOverTime(EffectState.GetX2Effect()))
			continue;

		TargetID = EffectState.ApplyEffectParameters.TargetStateObjectRef.ObjectID;
		TargetUnit = XComGameState_Unit(History.GetGameStateForObjectID(TargetID));
		if (TargetUnit != none && TargetUnit.IsAlive() && !TargetUnit.IsRobotic() && SourceUnit.IsEnemyUnit(TargetUnit) && TargetIDs.Find(TargetID) == INDEX_NONE)
			TargetIDs.AddItem(TargetID);
	}

	if (TargetIDs.Length == 0)
		return ELR_NoInterrupt;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Chemist disease");
	foreach TargetIDs(TargetID)
	{
		MutableTarget = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', TargetID));
		if (class'UT_EffectHelpers'.static.ApplyAbilityEffect('UT_ChemistDisease', 0, SourceUnit, MutableTarget, NewGameState, AbilityContext) == 'AA_Success')
			++Applied;
	}

	if (Applied == 0)
	{
		History.CleanupPendingGameState(NewGameState);
		return ELR_NoInterrupt;
	}

	XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = BuildVisualization_ChemistDisease;
	`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}

static function BuildVisualization_ChemistDisease(XComGameState VisualizeGameState)
{
	class'UT_EffectHelpers'.static.AddEffectVisualization(VisualizeGameState, 'UT_ChemistDisease', 0);
}
