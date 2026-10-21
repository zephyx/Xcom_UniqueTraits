//---------------------------------------------------------------------------------------
//  FILE:   X2EventListener_UniqueTraits.uc
//  PURPOSE: The three event listener templates of the mod. Each trait registers ITS OWN events (UT_Trait_<Name>.OnCreateStrategyListeners / OnCreateTacticalListeners /
//           OnCreateSharedListeners, called from the loops below for every trait of the pool that is not disabled); only the events of the mod itself are listed
//           here, with their handlers: the per-rank dispatch ('UnitRankUp'), the respec / stat ledger events, the trait draw (covert action, new crew), the MEC conversion rule.
//---------------------------------------------------------------------------------------
class X2EventListener_UniqueTraits extends X2EventListener;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(CreateStrategyListeners());
	Templates.AddItem(CreateTacticalListeners());
	Templates.AddItem(CreateSharedListeners());

	return Templates;
}

static function CHEventListenerTemplate CreateStrategyListeners()
{
	local CHEventListenerTemplate Template;
	local class<UT_TraitBase> TraitClass;
	local int i;

	`CREATE_X2TEMPLATE(class'CHEventListenerTemplate', Template, 'UniqueTraits_StrategyListeners');

	// Events of the mod itself, not of one trait (the trait draw, the respec / stat ledger, the MEC conversion rule).
	// Rank-ups only drive the per-rank stat scaling (Nerd, False Hope); the trait itself is drawn earlier, when a
	// rookie becomes eligible to choose a class (mission: OnPostMission in the DLCInfo; covert action: the listener below).
	// Priority 90: it runs BEFORE the other 'UnitRankUp' listeners of the mod (Mind over matter and Someone different, 40), whose syncs read marks that a respec has
	// just made wrong; OnUnitRankUp absorbs the respec first (see HandleStatsRebuilt).
	Template.AddCHEvent('UnitRankUp', OnUnitRankUp, ELD_OnStateSubmitted, 90);
	// The respec of a ROOKIE sends no 'UnitRankUp': the Armory main menu refreshing (CHL, UIArmory_MainMenu.UpdateData: also the PopulateData that LWOTC's console
	// respec calls) is where the history test of UT_TraitBase finds it at once.
	Template.AddCHEvent('OnArmoryMainMenuUpdate', OnArmoryMainMenuUpdate_StatsCheck, ELD_Immediate, 50);
	// The console mod [WOTC] Additional Soldier Console Commands resets a soldier without keeping his stats by calling RandomizeStats(), which sends this event with the unit being rebuilt.
	Template.AddCHEvent('UnitRandomizedStats', OnUnitRandomizedStats_StatsWiped, ELD_Immediate, 50);
	// Trait draw, covert action path. OnStateSubmitted: the draw opens its own transaction, which must come after
	// the covert action's state (with the kills) is committed.
	Template.AddCHEvent('CovertActionCompleted', OnCovertActionCompleted_RookieTrait, ELD_OnStateSubmitted, 50);
	// ASSIGN_TRAIT_AT_RECRUITMENT: a new crew member (recruit, rescued rookie, LWOTC haven recruit...) and the soldiers of a new campaign get their trait at once.
	Template.AddCHEvent('NewCrewNotification', OnNewRookie_RookieTrait, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('OnNewGame', OnNewRookie_RookieTrait, ELD_OnStateSubmitted, 50);
	// MEC conversion (optional mods Playable MEC Troopers / Ted MEC Troopers for LWOTC): the soldier whose conversion project just started loses his trait.
	Template.AddCHEvent('StaffUpdated', class'UT_MecConversion'.static.OnStaffUpdated_MecConversion, ELD_OnStateSubmitted, 50);

	// The events of the traits: each trait of the pool that is not disabled registers its own (UT_TraitBase.OnCreateStrategyListeners).
	for (i = 0; i < class'UniqueTraits_TraitConfig'.default.Traits.Length; ++i)
	{
		TraitClass = class'UniqueTraits_TraitConfig'.static.GetActiveTraitClass(i);
		if (TraitClass != none)
			TraitClass.static.OnCreateStrategyListeners(Template);
	}

	Template.RegisterInStrategy = true;

	return Template;
}

static function CHEventListenerTemplate CreateTacticalListeners()
{
	local CHEventListenerTemplate Template;
	local class<UT_TraitBase> TraitClass;
	local int i;

	`CREATE_X2TEMPLATE(class'CHEventListenerTemplate', Template, 'UniqueTraits_TacticalListeners');


	// The events of the traits: each trait of the pool that is not disabled registers its own (UT_TraitBase.OnCreateTacticalListeners).
	for (i = 0; i < class'UniqueTraits_TraitConfig'.default.Traits.Length; ++i)
	{
		TraitClass = class'UniqueTraits_TraitConfig'.static.GetActiveTraitClass(i);
		if (TraitClass != none)
			TraitClass.static.OnCreateTacticalListeners(Template);
	}

	Template.RegisterInTactical = true;

	return Template;
}

// Events needed in both layers (registered ONCE here: the same handler in the strategy and the tactical template would run twice
// while both are active).
static function CHEventListenerTemplate CreateSharedListeners()
{
	local CHEventListenerTemplate Template;
	local class<UT_TraitBase> TraitClass;
	local int i;

	`CREATE_X2TEMPLATE(class'CHEventListenerTemplate', Template, 'UniqueTraits_SharedListeners');


	// The events of the traits: each trait of the pool that is not disabled registers its own (UT_TraitBase.OnCreateSharedListeners).
	for (i = 0; i < class'UniqueTraits_TraitConfig'.default.Traits.Length; ++i)
	{
		TraitClass = class'UniqueTraits_TraitConfig'.static.GetActiveTraitClass(i);
		if (TraitClass != none)
			TraitClass.static.OnCreateSharedListeners(Template);
	}

	Template.RegisterInStrategy = true;
	Template.RegisterInTactical = true;

	return Template;
}

// 'UnitRankUp' (ELD_OnStateSubmitted, priority 90). RankUpSoldier fires it once per rank gained, and the state it belongs to can contain several RankUpSoldier calls:
// the listener then receives the SAME final unit object (EventData) several times. For a holder of a trait that changes base stats:
// - if LWOTC's RespecSoldier was made on the unit since the trait last wrote its ledger (UT_TraitBase.WasRespecSinceLastShift: one state that resets the soldier and
//   ranks him up again; ResetSoldierRank puts EVERY base stat back to the template's, so the permanent changes of the trait are gone), the trait forgets them and applies
//   itself again (HandleStatsRebuilt). The first event does it; the next ones of the same state find the ledger written after the respec and do nothing;
// - otherwise a real promotion (rookie -> squaddie included): the trait brings its rank-dependent stats to the new rank (UT_TraitBase.OnRankUp: Nerd, False Hope, Born
//   to be chief, Mind over matter, Support), in a change container of ours (the unit of the event is a submitted state: it is never written). The syncs are idempotent.
// A respec by the console mod [WOTC] Additional Soldier Console Commands is a "Reset Soldier" state (see OnUnitRandomizedStats_StatsWiped) followed by one "Respec Soldier: Rank N" state per rank, each a
// real promotion for this function. Trait ASSIGNMENT does not happen here (see AssignTraitsToEligibleRookies).
static function EventListenerReturn OnUnitRankUp(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit NewUnitState, PreviousUnitState, MutableUnit;
	local class<UT_TraitBase> TraitClass;
	local XComGameState NewGameState;
	local int TraitIndex;

	NewUnitState = XComGameState_Unit(EventData);
	if (NewUnitState == none)
	{
		`log("UniqueTraits [WARN] : OnUnitRankUp fired with EventData that isn't an XComGameState_Unit (" $ EventData $ ")",, 'UniqueTraits');
		return ELR_NoInterrupt;
	}

	PreviousUnitState = XComGameState_Unit(NewUnitState.GetPreviousVersion());
	if (PreviousUnitState == none)
	{
		`log("UniqueTraits [WARN] : OnUnitRankUp -- no previous version found for" @ NewUnitState.GetFullName(),, 'UniqueTraits');
		return ELR_NoInterrupt;
	}

	`log("UniqueTraits : OnUnitRankUp fired for" @ NewUnitState.GetFullName() @ "-- previous rank" @ PreviousUnitState.GetRank() @ "new rank" @ NewUnitState.GetRank(),, 'UniqueTraits');

	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.GetAssignedTraitIndex(NewUnitState, TraitIndex))
		return ELR_NoInterrupt;

	TraitClass = class'UniqueTraits_TraitConfig'.static.GetActiveTraitClass(TraitIndex);
	if (TraitClass == none || !TraitClass.static.ShiftsStats())
		return ELR_NoInterrupt;

	// The event gives the unit as it was when the state was submitted: the test is made on the latest committed version, which a first event of the same respec has
	// already resynced.
	if (TraitClass.static.WasRespecSinceLastShift(XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(NewUnitState.ObjectID))))
	{
		HandleStatsRebuilt(NewUnitState.ObjectID, TraitClass);

		return ELR_NoInterrupt;
	}

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: rank-dependent stats sync");
	MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', NewUnitState.ObjectID));
	if (TraitClass.static.OnRankUp(MutableUnit))
		`GAMERULES.SubmitGameState(NewGameState);
	else
		`XCOMHISTORY.CleanupPendingGameState(NewGameState);

	return ELR_NoInterrupt;
}

// 'OnArmoryMainMenuUpdate' (ELD_Immediate; EventData = the menu list, EventSource = the Armory screen). A holder whose stats a respec of LWOTC's wiped (its console
// RespecSelectedSoldier refreshes the screen right after => a rookie's respec sends no 'UnitRankUp') gets his trait's changes applied again at once, and the screen is
// refreshed to show them. The test is a read of the history => once the changes are applied again it is false, so the refresh cannot loop.
static function EventListenerReturn OnArmoryMainMenuUpdate_StatsCheck(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local UIArmory Armory;
	local XComGameState_Unit Unit;
	local class<UT_TraitBase> TraitClass;
	local int TraitIndex;

	Armory = UIArmory(EventSource);
	if (Armory == none)
		return ELR_NoInterrupt;

	Unit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(Armory.GetUnitRef().ObjectID));
	if (Unit == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.GetAssignedTraitIndex(Unit, TraitIndex))
		return ELR_NoInterrupt;

	TraitClass = class'UniqueTraits_TraitConfig'.static.GetActiveTraitClass(TraitIndex);
	if (TraitClass == none || !TraitClass.static.ShiftsStats() || !TraitClass.static.WasRespecSinceLastShift(Unit))
		return ELR_NoInterrupt;

	HandleStatsRebuilt(Unit.ObjectID, TraitClass);
	Armory.PopulateData();

	return ELR_NoInterrupt;
}

// 'UnitRandomizedStats' (CHL #185, ELD_Immediate; EventData = EventSource = the unit): sent by XComGameState_Unit.RandomizeStats(), i.e. when a soldier is created and when
// the console mod [WOTC] Additional Soldier Console Commands resets one WITHOUT keeping his stats (ResetSelectedSoldiersClass: ResetSoldierRank, then RandomizeStats, in a state named "Reset Soldier";
// its RebuildSelectedSoldiersClass keeps the stats, so the trait's changes survive and nothing is sent). The unit is the pending copy being rebuilt: the trait forgets its
// changes in it, the rank-ups that follow apply them again. A new soldier has no trait: nothing happens.
// The unit of this event is NOT the pending copy that is submitted (rank and stats of before the reset, the ledger it cleared came back), so
// nothing is written into it: the unit is only NOTED (UniqueTraits_TraitConfig.RESET_UNIT_IDS) and WasRespecSinceLastShift then counts the "Reset Soldier" state that
// follows as a respec; the first rank-up state of the console mod (OnUnitRankUp) resyncs the trait.
static function EventListenerReturn OnUnitRandomizedStats_StatsWiped(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit Unit;
	local class<UT_TraitBase> TraitClass;
	local int TraitIndex;

	Unit = XComGameState_Unit(EventData);
	if (Unit == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.GetAssignedTraitIndex(Unit, TraitIndex))
		return ELR_NoInterrupt;

	TraitClass = class'UniqueTraits_TraitConfig'.static.GetActiveTraitClass(TraitIndex);
	if (TraitClass == none || !TraitClass.static.ShiftsStats())
		return ELR_NoInterrupt;

	class'UniqueTraits_TraitConfig'.static.NoteUnitRandomized(Unit.ObjectID);
	`log("UniqueTraits : stats of" @ Unit.GetFullName() @ "randomized again (reset of the soldier): noted, the next sync of" @ TraitClass.Name @ "applies it again",, 'UniqueTraits');

	return ELR_NoInterrupt;
}

// The base stats of the holder were wiped by a respec: the trait forgets what it had put in them and applies itself again (UT_TraitBase.OnStatsReset), in a change
// container of ours.
static final function HandleStatsRebuilt(int UnitID, class<UT_TraitBase> TraitClass)
{
	local XComGameState_Unit MutableUnit;
	local XComGameState NewGameState;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: stats wiped by a respec, trait resync");
	MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', UnitID));
	TraitClass.static.OnStatsReset(MutableUnit, NewGameState);
	`GAMERULES.SubmitGameState(NewGameState);

	`log("UniqueTraits : respec found for" @ MutableUnit.GetFullName() @ ": the permanent stat changes of" @ TraitClass.Name @ "were forgotten and applied again",, 'UniqueTraits');
}

// A rookie's trait is drawn the moment they earn enough XP/kills to choose a class (so it is known
// BEFORE the class choice screen), not at promotion. Two XP sources exist for a rookie:
//
// 1. Mission end: X2DownloadableContentInfo_UniqueTraits.OnPostMission, once the tactical -> strategy
//    transfer is fully committed (so LWOTC's own mission XP/encounters, added in later transactions,
//    are counted too) and before the After Action screen.
// 2. Covert action: here, once the state holding GiveRewards' kills (NonTacticalKills) is committed.
static function EventListenerReturn OnCovertActionCompleted_RookieTrait(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	class'X2DownloadableContentInfo_UniqueTraits'.static.AssignTraitsToEligibleRookies();

	return ELR_NoInterrupt;
}

// ASSIGN_TRAIT_AT_RECRUITMENT only ('NewCrewNotification' and 'OnNewGame', submitted: the new unit is in history): the sweep gives every rookie of the
// roster without a trait one. A reward soldier is created ranked and is left alone, like in the default mode.
static function EventListenerReturn OnNewRookie_RookieTrait(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	if (class'UniqueTraits_TraitConfig'.static.ShouldAssignAtRecruitment())
		class'X2DownloadableContentInfo_UniqueTraits'.static.AssignTraitsToEligibleRookies();

	return ELR_NoInterrupt;
}
