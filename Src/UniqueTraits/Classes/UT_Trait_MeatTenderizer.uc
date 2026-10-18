//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_MeatTenderizer.uc
//  PURPOSE: Meat Tenderizer: what the holder would STUN becomes "Tenderized" (-mobility, and +aim / +crit for every unit that attacks it, like a holotarget) for as many enemy turns as the stun
//           would have taken (ceil(StunLevel / MEATTENDERIZER_STUN_ACTIONS_PER_TURN)), and what he would DISORIENT becomes "Slightly Tenderized"
//           (lighter malus, the disorient's own duration). Each time one is applied the holder gets a standard action point back (max one per turn).
//           Tenderized and Slightly Tenderized do not stack: only Tenderized stays.
//           - Technique: OnPostTemplatesCreated walks every ability template AND every item template. Next to each X2Effect_Stunned / disorient
//             effect of an ability's target and multi-target effects, of a grenade's thrown / launched effects (a flashbang's disorient lives there,
//             not in the ThrowGrenade ability), of an ammo's target effects and of a weapon's bonus effects, it inserts a twin X2Effect_UT_Tenderized with the same chance, conditions and hit/miss rules, and both effects get an
//             X2Condition_UT_TenderizerSource: the original applies unless the source is a holder against an enemy, the twin only then. So the stun
//             never happens at all (no stun animation, no lost action points), and an ability of any other source is untouched.
//           - The removal of the light twin by the full one is in X2Effect_UT_Tenderized.OnEffectAdded. The action point is
//             OnAbilityActivated_MeatTenderizer ('AbilityActivated', submitted): an ability's cost is applied after its effects and may consume
//             every action point (Arc Thrower, Disabling Shot, EM Pulse...), which swallowed a point granted from the effect. The handler looks at
//             the ability's effect results for a successfully applied twin and grants the point in a state of its own. A flyover on the target
//             announces the debuff (VisualizationFn of the twin).
//           - The mod must run LAST among the DLC infos (Config/XComGame.ini, CHDLCRunOrder): Merist's Improved Suppression adds its disorient to
//             the suppression abilities from its own OnPostTemplatesCreated, which our patch has to see.
//---------------------------------------------------------------------------------------
class UT_Trait_MeatTenderizer extends UT_TraitBase config(UniqueTraits);

var config int MEATTENDERIZER_STUN_ACTIONS_PER_TURN;
var config int MEATTENDERIZER_AIM_BONUS, MEATTENDERIZER_CRIT_BONUS, MEATTENDERIZER_MOBILITY_MALUS;
var config int MEATTENDERIZER_SLIGHT_AIM_BONUS, MEATTENDERIZER_SLIGHT_CRIT_BONUS, MEATTENDERIZER_SLIGHT_MOBILITY_MALUS;

var localized string MEATTENDERIZER_TENDERIZED_NAME, MEATTENDERIZER_TENDERIZED_DESC;
var localized string MEATTENDERIZER_SLIGHT_NAME, MEATTENDERIZER_SLIGHT_DESC;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(PurePassive('UT_MeatTenderizer', "img:///UILibrary_PerkIcons.UIPerk_standard", true));

	return Templates;
}

// UT_TraitBase.OnPostTemplatesCreated (called for every trait of the pool by X2DownloadableContentInfo_UniqueTraits).
static function OnPostTemplatesCreated()
{
	local X2AbilityTemplateManager AbilityManager;
	local X2DataTemplate DataTemplate;
	local X2AbilityTemplate Template;
	local X2ItemTemplateManager ItemManager;
	local X2GrenadeTemplate GrenadeTemplate;
	local X2WeaponTemplate WeaponTemplate;
	local X2AmmoTemplate AmmoTemplate;

	AbilityManager = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();
	foreach AbilityManager.IterateTemplates(DataTemplate, none)
	{
		Template = X2AbilityTemplate(DataTemplate);
		if (Template == none)
			continue;

		PatchEffects(Template.AbilityTargetEffects);
		PatchEffects(Template.AbilityMultiTargetEffects);
	}

	// The effects of a thrown / launched grenade, of an ammo and of a weapon's bonus effects are read from the ITEM at activation time.
	ItemManager = class'X2ItemTemplateManager'.static.GetItemTemplateManager();
	foreach ItemManager.IterateTemplates(DataTemplate, none)
	{
		GrenadeTemplate = X2GrenadeTemplate(DataTemplate);
		if (GrenadeTemplate != none)
		{
			PatchEffects(GrenadeTemplate.ThrownGrenadeEffects);
			PatchEffects(GrenadeTemplate.LaunchedGrenadeEffects);
		}

		WeaponTemplate = X2WeaponTemplate(DataTemplate);
		if (WeaponTemplate != none)
			PatchEffects(WeaponTemplate.BonusWeaponEffects);

		AmmoTemplate = X2AmmoTemplate(DataTemplate);
		if (AmmoTemplate != none)
			PatchEffects(AmmoTemplate.TargetEffects);
	}
}

static final function PatchEffects(out array<X2Effect> Effects)
{
	local X2Effect_Stunned StunEffect;
	local X2Effect_Persistent PersistentEffect;
	local X2Effect_UT_Tenderized Twin;
	local X2Condition_UT_TenderizerSource KeepOriginal;
	local int i;

	for (i = 0; i < Effects.Length; ++i)
	{
		// A twin already follows this effect in THIS list. The check is per list, not per effect: a grenade's thrown and launched lists usually
		// hold the very same effect objects, so the second list meets an original that already carries the condition but has no twin yet.
		if (i + 1 < Effects.Length && X2Effect_UT_Tenderized(Effects[i + 1]) != none)
			continue;
		if (X2Effect_UT_Tenderized(Effects[i]) != none)
			continue;

		Twin = none;
		StunEffect = X2Effect_Stunned(Effects[i]);
		if (StunEffect != none)
		{
			Twin = CreateTwin(StunEffect, false, GetTenderizedTurns(StunEffect.StunLevel));
		}
		else
		{
			PersistentEffect = X2Effect_Persistent(Effects[i]);
			if (PersistentEffect != none && PersistentEffect.EffectName == class'X2AbilityTemplateManager'.default.DisorientedName)
				Twin = CreateTwin(PersistentEffect, true, Max(1, PersistentEffect.iNumTurns));
		}

		if (Twin == none)
			continue;

		// The twin copied the original's conditions above; only now does the original learn to step aside for a holder (once: the same
		// effect object can sit in several lists).
		if (!IsPatched(Effects[i]))
		{
			KeepOriginal = new class'X2Condition_UT_TenderizerSource';
			KeepOriginal.bRequireTenderizing = false;
			Effects[i].TargetConditions.AddItem(KeepOriginal);
		}

		Effects.InsertItem(i + 1, Twin);
		++i;
	}
}

static final function bool IsPatched(X2Effect Effect)
{
	local X2Condition Condition;

	foreach Effect.TargetConditions(Condition)
	{
		if (X2Condition_UT_TenderizerSource(Condition) != none)
			return true;
	}

	return false;
}

// A stun is counted in action points of its target (2 = a whole turn lost).
static final function int GetTenderizedTurns(int StunLevel)
{
	local int PerTurn;

	PerTurn = Max(1, default.MEATTENDERIZER_STUN_ACTIONS_PER_TURN);

	return Max(1, (StunLevel + PerTurn - 1) / PerTurn);
}

// The twin of a stun (bSlight = false) or of a disorient (bSlight = true): same application rules as Original, a stat malus for Turns turns.
static final function X2Effect_UT_Tenderized CreateTwin(X2Effect Original, bool bSlight, int Turns)
{
	local X2Effect_UT_Tenderized Twin;
	local X2Condition_UT_TenderizerSource OnlyHolder;
	local X2Condition_UnitEffects NoFullTenderized;
	local X2Condition Condition;
	local string DisplayName, Desc;
	local int AimBonus, CritBonus, MobilityMalus;

	if (bSlight)
	{
		AimBonus = default.MEATTENDERIZER_SLIGHT_AIM_BONUS;
		CritBonus = default.MEATTENDERIZER_SLIGHT_CRIT_BONUS;
		MobilityMalus = default.MEATTENDERIZER_SLIGHT_MOBILITY_MALUS;
		DisplayName = default.MEATTENDERIZER_SLIGHT_NAME;
		Desc = default.MEATTENDERIZER_SLIGHT_DESC;
	}
	else
	{
		AimBonus = default.MEATTENDERIZER_AIM_BONUS;
		CritBonus = default.MEATTENDERIZER_CRIT_BONUS;
		MobilityMalus = default.MEATTENDERIZER_MOBILITY_MALUS;
		DisplayName = default.MEATTENDERIZER_TENDERIZED_NAME;
		Desc = default.MEATTENDERIZER_TENDERIZED_DESC;
	}
	Desc = Repl(Desc, "%AIM", string(AimBonus));
	Desc = Repl(Desc, "%CRIT", string(CritBonus));
	Desc = Repl(Desc, "%MOB", string(MobilityMalus));

	Twin = new class'X2Effect_UT_Tenderized';
	Twin.bSlight = bSlight;
	Twin.SlightEffectName = 'UT_MeatTenderizer_SlightlyTenderized';
	Twin.AimBonus = AimBonus;
	Twin.CritBonus = CritBonus;
	if (bSlight)
		Twin.EffectName = Twin.SlightEffectName;
	else
		Twin.EffectName = 'UT_MeatTenderizer_Tenderized';

	// Same application rules as the original.
	Twin.ApplyChance = Original.ApplyChance;
	Twin.ApplyChanceFn = Original.ApplyChanceFn;
	Twin.bApplyOnHit = Original.bApplyOnHit;
	Twin.bApplyOnMiss = Original.bApplyOnMiss;
	Twin.MinStatContestResult = Original.MinStatContestResult;
	Twin.MaxStatContestResult = Original.MaxStatContestResult;
	Twin.DamageTypes = Original.DamageTypes;
	foreach Original.TargetConditions(Condition)
	{
		// Not our own switch, which the original may already carry (see PatchEffects).
		if (X2Condition_UT_TenderizerSource(Condition) == none)
			Twin.TargetConditions.AddItem(Condition);
	}

	OnlyHolder = new class'X2Condition_UT_TenderizerSource';
	OnlyHolder.bRequireTenderizing = true;
	Twin.TargetConditions.AddItem(OnlyHolder);

	// Slightly Tenderized is refused on a unit that is already (fully) Tenderized.
	if (bSlight)
	{
		NoFullTenderized = new class'X2Condition_UnitEffects';
		NoFullTenderized.AddExcludeEffect('UT_MeatTenderizer_Tenderized', 'AA_DuplicateEffectIgnored');
		Twin.TargetConditions.AddItem(NoFullTenderized);
	}

	if (bSlight)
		Twin.VisualizationFn = SlightlyTenderizedVisualization;
	else
		Twin.VisualizationFn = TenderizedVisualization;
	Twin.BuildPersistentEffect(Turns, false, false, false, eGameRule_PlayerTurnBegin);
	Twin.SetDisplayInfo(ePerkBuff_Penalty, DisplayName, Desc, "img:///UILibrary_PerkIcons.UIPerk_standard", true,, 'eAbilitySource_Perk');
	Twin.AddPersistentStatChange(eStat_Mobility, -MobilityMalus);
	Twin.bRemoveWhenTargetDies = true;

	return Twin;
}

// Flyover on the target when the debuff is applied (the twin's VisualizationFn, called by the persistent effect's own visualization on AA_Success).
static function TenderizedVisualization(XComGameState VisualizeGameState, out VisualizationActionMetadata ActionMetadata, const name EffectApplyResult)
{
	AddDebuffFlyover(VisualizeGameState, ActionMetadata, EffectApplyResult, default.MEATTENDERIZER_TENDERIZED_NAME);
}

static function SlightlyTenderizedVisualization(XComGameState VisualizeGameState, out VisualizationActionMetadata ActionMetadata, const name EffectApplyResult)
{
	AddDebuffFlyover(VisualizeGameState, ActionMetadata, EffectApplyResult, default.MEATTENDERIZER_SLIGHT_NAME);
}

static final function AddDebuffFlyover(XComGameState VisualizeGameState, out VisualizationActionMetadata ActionMetadata, const name EffectApplyResult, string DebuffName)
{
	local XComGameState_Unit UnitState;

	UnitState = XComGameState_Unit(ActionMetadata.StateObject_NewState);
	if (EffectApplyResult != 'AA_Success' || UnitState == none || UnitState.IsDead())
		return;

	class'X2StatusEffects'.static.AddEffectSoundAndFlyOverToTrack(ActionMetadata, VisualizeGameState.GetContext(), DebuffName, '', eColor_Bad, "img:///UILibrary_PerkIcons.UIPerk_standard");
	class'X2StatusEffects'.static.UpdateUnitFlag(ActionMetadata, VisualizeGameState.GetContext());
}

// True when one of the results holds a Tenderized / Slightly Tenderized twin that was applied.
static final function bool HasAppliedTwin(EffectResults Results)
{
	local int i;

	for (i = 0; i < Results.Effects.Length && i < Results.ApplyResults.Length; ++i)
	{
		if (X2Effect_UT_Tenderized(Results.Effects[i]) != none && Results.ApplyResults[i] == 'AA_Success')
			return true;
	}

	return false;
}

// 'AbilityActivated' (ELD_OnStateSubmitted): the holder's ability tenderized someone -> one standard action point back, once per turn, given AFTER
// the ability's cost (see the header). A twin refreshed on an already tenderized target counts too (the result is AA_Success whatever the stacking).
static function EventListenerReturn OnAbilityActivated_MeatTenderizer(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateContext_Ability AbilityContext;
	local XComGameState_Unit SourceUnit, MutableUnit;
	local UnitValue Given;
	local EffectResults MultiResults;
	local XComGameState NewGameState;
	local bool bApplied;
	local int i;

	if (!ParseAbilityActivation(GameState, EventSource, 'UT_MeatTenderizer', AbilityContext, SourceUnit))
		return ELR_NoInterrupt;

	// Latest version of the holder: the guard is written in states of our own.
	SourceUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(SourceUnit.ObjectID));
	if (SourceUnit == none || !SourceUnit.IsAlive() || SourceUnit.GetUnitValue('UT_MeatTenderizer_AP', Given))
		return ELR_NoInterrupt;

	bApplied = HasAppliedTwin(AbilityContext.ResultContext.TargetEffectResults);
	for (i = 0; i < AbilityContext.ResultContext.MultiTargetEffectResults.Length && !bApplied; ++i)
	{
		MultiResults = AbilityContext.ResultContext.MultiTargetEffectResults[i];
		bApplied = HasAppliedTwin(MultiResults);
	}
	if (!bApplied)
		return ELR_NoInterrupt;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Meat Tenderizer action point");
	MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', SourceUnit.ObjectID));
	MutableUnit.ActionPoints.AddItem(class'X2CharacterTemplateManager'.default.StandardActionPoint);
	MutableUnit.SetUnitFloatValue('UT_MeatTenderizer_AP', 1, eCleanup_BeginTurn);
	`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}
