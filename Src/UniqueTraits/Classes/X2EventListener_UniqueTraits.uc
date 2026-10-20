//---------------------------------------------------------------------------------------
//  FILE:   X2EventListener_UniqueTraits.uc
//  PURPOSE: Index of every event this mod listens to, with its deferral and priority. The handler bodies live in the
//           trait that owns them (UT_Trait_<Name>.uc), except the two generic ones below: the per-rank dispatch
//           ('UnitRankUp') and the covert action path of the trait draw.
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

	`CREATE_X2TEMPLATE(class'CHEventListenerTemplate', Template, 'UniqueTraits_StrategyListeners');

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
	// Optional soft dependency: only fires if the "Community Promotion Screen" mod is loaded. Priority 1 = runs AFTER
	// every other listener (larger number runs first): a block is only a block if no later listener of another mod
	// flips bCanPurchaseAbility back to true.
	Template.AddCHEvent('CPS_OverrideCanPurchaseAbility', class'UT_Trait_JackOfAllTrades'.static.OnCPSOverrideCanPurchaseAbility_JackOfAllTrades, ELD_Immediate, 1);
	Template.AddCHEvent('CPS_OverrideCanPurchaseAbility', class'UT_Trait_Swordsman'.static.OnCPSOverrideCanPurchaseAbility_Swordsman, ELD_Immediate, 1);
	// Priority 50 (< LWOTC's own 90 for this event) so LWOTC's listener runs first and we add on top of its result
	// rather than being overwritten by it.
	Template.AddCHEvent('OverrideSupplyDrop', class'UT_Trait_Bribe'.static.OnOverrideSupplyDrop, ELD_Immediate, 50);
	// Bribe: re-sync the region's displayed +supplies whenever a staff slot (incl. LWOTC's haven liaison slots) is filled or emptied.
	Template.AddCHEvent('StaffUpdated', class'UT_Trait_Bribe'.static.OnStaffUpdated, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('PreEndOfMonth', class'UT_Trait_Bribe'.static.OnPreEndOfMonth_Bribe, ELD_Immediate, 50);
	// Born to be chief's officer-rank sync, strategy-layer points: month end, and whenever any personnel list finishes
	// refreshing (display freshness only). The third one (mission start) is in the tactical listeners.
	Template.AddCHEvent('PreEndOfMonth', class'UT_Trait_BornToBeChief'.static.OnPreEndOfMonth_BornToBeChief, ELD_Immediate, 50);
	Template.AddCHEvent('UIPersonnel_OnSortFinished', class'UT_Trait_BornToBeChief'.static.OnUIPersonnelSortFinished, ELD_Immediate, 50);
	// Support / Swordsman: hide (not just gray out) forbidden items from the Armory picker.
	Template.AddCHEvent('OverrideShowItemInLockerList', class'UT_Trait_Support'.static.OnOverrideShowItemInLockerList_Support, ELD_Immediate, 50);
	Template.AddCHEvent('OverrideShowItemInLockerList', class'UT_Trait_Swordsman'.static.OnOverrideShowItemInLockerList_Swordsman, ELD_Immediate, 50);
	// Cyborg: only basic PCS can be equipped from the armory list, and a removed PCS is not lost.
	// Priority 1 (runs AFTER every other listener, larger numbers run first): LWOTC's own listener for this event (X2EventListener_PCSFix_LW,
	// priority 50) sets the result to true, which would undo our refusal.
	Template.AddCHEvent('OverrideCanEquipImplant', class'UT_Trait_Cyborg'.static.OnOverrideCanEquipImplant_Cyborg, ELD_Immediate, 1);
	Template.AddCHEvent('PCSApplied', class'UT_Trait_Cyborg'.static.OnPCSApplied_Cyborg, ELD_Immediate, 50);
	Template.AddCHEvent('ItemRemovedFromSlot', class'UT_Trait_Cyborg'.static.OnItemRemovedFromSlot_Cyborg, ELD_Immediate, 50);
	// Recruiter: at the end of the month, one more recruit in the recruitable pool (and sometimes a free rookie).
	Template.AddCHEvent('PreEndOfMonth', class'UT_Trait_Recruiter'.static.OnPreEndOfMonth_Recruiter, ELD_Immediate, 50);
	// Recruiter: tracks the time spent as haven adviser (a staff slot, incl. LWOTC's liaison slots, was filled or emptied).
	Template.AddCHEvent('StaffUpdated', class'UT_Trait_Recruiter'.static.OnStaffUpdated_Recruiter, ELD_OnStateSubmitted, 50);
	// Self-reinforcement: a staff slot (here: of a covert operation not launched yet) was filled or emptied -> resync the operation's duration (+50 % once) and the
	// doubling of the stat boost reward of the holder's slot.
	Template.AddCHEvent('StaffUpdated', class'UT_Trait_SelfReinforcement'.static.OnStaffUpdated_SelfReinforcement, ELD_OnStateSubmitted, 50);
	// MEC conversion (optional mods Playable MEC Troopers / Ted MEC Troopers for LWOTC): the soldier whose conversion project just started loses his trait.
	Template.AddCHEvent('StaffUpdated', class'UT_MecConversion'.static.OnStaffUpdated_MecConversion, ELD_OnStateSubmitted, 50);
	// Mind over matter: permanent stats that follow the max Will. No hook exists on a max Will change: every known cause resyncs (rank-up,
	// PCS equipped/removed, Gene Mod operation, ability bought), plus month end and personnel lists as safety nets. The mission-start sync
	// is in the tactical listeners.
	Template.AddCHEvent('UnitRankUp', class'UT_Trait_MindOverMatter'.static.OnWillMayHaveChanged_MindOverMatter, ELD_OnStateSubmitted, 40);
	Template.AddCHEvent('ItemAddedToSlot', class'UT_Trait_MindOverMatter'.static.OnWillMayHaveChanged_MindOverMatter, ELD_OnStateSubmitted, 40);
	Template.AddCHEvent('ItemRemovedFromSlot', class'UT_Trait_MindOverMatter'.static.OnWillMayHaveChanged_MindOverMatter, ELD_OnStateSubmitted, 40);
	Template.AddCHEvent('GeneModOperationCompleted', class'UT_Trait_MindOverMatter'.static.OnWillMayHaveChanged_MindOverMatter, ELD_OnStateSubmitted, 40);
	Template.AddCHEvent('AbilityPointsChange', class'UT_Trait_MindOverMatter'.static.OnWillMayHaveChanged_MindOverMatter, ELD_OnStateSubmitted, 40);
	Template.AddCHEvent('PreEndOfMonth', class'UT_Trait_MindOverMatter'.static.OnPreEndOfMonth_MindOverMatter, ELD_Immediate, 50);
	Template.AddCHEvent('UIPersonnel_OnSortFinished', class'UT_Trait_MindOverMatter'.static.OnUIPersonnelSortFinished_MindOverMatter, ELD_Immediate, 50);
	// Someone different: its stats follow the rank and the number of evolutions bought. Rank-up and a respec made at the Training Center are synced here; the
	// promotion screen closing (UIScreenListener_UT_PromotionMarks.OnRemoved: no event reports a purchase) and the mission start (tactical listeners) are the other points.
	Template.AddCHEvent('UnitRankUp', class'UT_Trait_SomeoneDifferent'.static.OnStatsMayHaveChanged_SomeoneDifferent, ELD_OnStateSubmitted, 40);
	Template.AddCHEvent('CompleteRespecSoldier', class'UT_Trait_SomeoneDifferent'.static.OnStatsMayHaveChanged_SomeoneDifferent, ELD_OnStateSubmitted, 40);
	Template.RegisterInStrategy = true;

	return Template;
}

static function CHEventListenerTemplate CreateTacticalListeners()
{
	local CHEventListenerTemplate Template;

	`CREATE_X2TEMPLATE(class'CHEventListenerTemplate', Template, 'UniqueTraits_TacticalListeners');

	Template.AddCHEvent('OnGetItemRange', class'UT_Trait_AllInArms'.static.OnGetItemRange_AllInArms, ELD_Immediate, 50);
	Template.AddCHEvent('OnGetItemRange', class'UT_Trait_Scout'.static.OnGetItemRange_Scout, ELD_Immediate, 50);
	Template.AddCHEvent('OnGetItemRange', class'UT_Trait_BaseballPlayer'.static.OnGetItemRange_BaseballPlayer, ELD_Immediate, 50);
	Template.AddCHEvent('ItemLooted', class'UT_Trait_Thief'.static.OnItemLooted, ELD_Immediate, 50);
	Template.AddCHEvent('UnitBleedingOut', class'UT_Trait_QuickHealing'.static.OnUnitBleedingOut, ELD_Immediate, 50);
	// Fired by the tactical rules when the mission is cleaned up, with the state submitted before the end-of-mission health adjustment.
	Template.AddCHEvent('CleanupTacticalMission', class'UT_Trait_QuickHealing'.static.OnCleanupTacticalMission_QuickHealing, ELD_Immediate, 50);
	// Give me more: same moment, Field Surgeon's mechanism (and the bleeding-out mark that makes it skip a soldier who bled out).
	Template.AddCHEvent('CleanupTacticalMission', class'UT_Trait_GiveMeMore'.static.OnCleanupTacticalMission_GiveMeMore, ELD_Immediate, 50);
	Template.AddCHEvent('UnitBleedingOut', class'UT_Trait_GiveMeMore'.static.OnUnitBleedingOut_GiveMeMore, ELD_Immediate, 50);
	// Mind over matter: mission-start sync of its permanent stats, and the same wound mechanism with a wound scaled by a percentage.
	Template.AddCHEvent('OnTacticalBeginPlay', class'UT_Trait_MindOverMatter'.static.OnTacticalBeginPlay_MindOverMatter, ELD_Immediate, 50);
	Template.AddCHEvent('CleanupTacticalMission', class'UT_Trait_MindOverMatter'.static.OnCleanupTacticalMission_MindOverMatter, ELD_Immediate, 50);
	Template.AddCHEvent('UnitBleedingOut', class'UT_Trait_MindOverMatter'.static.OnUnitBleedingOut_MindOverMatter, ELD_Immediate, 50);
	// 'AbilityActivated' fires more than once per ability: each handler starts with the interrupt-step early return.
	Template.AddCHEvent('AbilityActivated', class'UT_Trait_Tactician'.static.OnAbilityActivated_Tactician, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('AbilityActivated', class'UT_Trait_Smoker'.static.OnAbilityActivated_Smoker, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('AbilityActivated', class'UT_Trait_StayFocus'.static.OnAbilityActivated_StayFocus, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('AbilityActivated', class'UT_Trait_AlwaysReady'.static.OnAbilityActivated_AlwaysReady, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('PlayerTurnEnded', class'UT_Trait_Smoker'.static.OnPlayerTurnEnded_Smoker, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('PlayerTurnEnded', class'UT_Trait_Hunter'.static.OnPlayerTurnEnded_Hunter, ELD_OnStateSubmitted, 50);
	// False Hope: priority -10 on purpose, it must run AFTER LWOTC's XP listener (which gives the mission experience), whose priority is 0: its ini section
	// [LW_Overhaul.X2EventListener_XP] has no LISTENER_PRIORITY line, so the config int stays 0 instead of falling back on DEFAULT_LISTENER_PRIORITY (90).
	Template.AddCHEvent('OnDistributeTacticalGameEndXp', class'UT_Trait_FalseHope'.static.OnDistributeTacticalGameEndXp, ELD_OnStateSubmitted, -10);
	// Born to be chief: the sync point that actually *guarantees* the officer-rank bonus is correct in combat. Fires
	// exactly ONCE, right as a mission's tactical state is built.
	Template.AddCHEvent('OnTacticalBeginPlay', class'UT_Trait_BornToBeChief'.static.OnTacticalBeginPlay, ELD_Immediate, 50);
	// Bounty hunter: 20% of the kills without XP (fired once per kill that gives XP) and the tally of ALL the kills (supplies paid after the mission).
	Template.AddCHEvent('OverrideKillXp', class'UT_Trait_BountyHunter'.static.OnOverrideKillXp_BountyHunter, ELD_Immediate, 50);
	Template.AddCHEvent('UnitDied', class'UT_Trait_BountyHunter'.static.OnUnitDied_BountyHunter, ELD_Immediate, 50);
	// Shredder: the acid on a target whose armor the holder's primary weapon just shredded.
	Template.AddCHEvent('AbilityActivated', class'UT_Trait_Shredder'.static.OnAbilityActivated_Shredder, ELD_OnStateSubmitted, 50);
	// Meat Tenderizer: the action point back, once the ability (and its cost) is over.
	Template.AddCHEvent('AbilityActivated', class'UT_Trait_MeatTenderizer'.static.OnAbilityActivated_MeatTenderizer, ELD_OnStateSubmitted, 50);
	// Nemesis: the permanent per-enemy-type kill tally (aim against, defense malus against).
	Template.AddCHEvent('UnitDied', class'UT_Trait_Nemesis'.static.OnUnitDied_Nemesis, ELD_Immediate, 50);
	// Young doctor: reduces the heals of its holder and rewards the first treatment of each soldier. ELD_Immediate: it works on the ability's own
	// pending state, so the visualization shows the reduced heal.
	Template.AddCHEvent('AbilityActivated', class'UT_Trait_YoungDoctor'.static.OnAbilityActivated_YoungDoctor, ELD_Immediate, 50);
	// Chemist: the disease on the enemies a damage over time was just inflicted on. Laser designator: consumes the primed marker on the next primary
	// shot / holotarget and marks the main target. Both react to a submitted ability state and apply their effect in a state of their own.
	Template.AddCHEvent('AbilityActivated', class'UT_Trait_Chemist'.static.OnAbilityActivated_Chemist, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('AbilityActivated', class'UT_Trait_LaserDesignator'.static.OnAbilityActivated_LaserDesignator, ELD_OnStateSubmitted, 50);
	// Psychic Bond: the bondmate loses a share of the damage (once the damage is submitted, in a state of its own).
	Template.AddCHEvent('UnitTakeEffectDamage', class'UT_Trait_PsychicBond'.static.OnUnitTakeEffectDamage_PsychicBond, ELD_OnStateSubmitted, 50);
	// Security hacker: while the HOLDER hacks a security tower (from the ability that opens the hacking screen to the finalize / cancel ability), the
	// tower's lock is raised by the force level (ELD_Immediate: inside the ability's pending state, before the screen reads it); if it succeeds, disables every security tower.
	Template.AddCHEvent('AbilityActivated', class'UT_Trait_SecurityHacker'.static.OnAbilityActivated_SecurityHacker, ELD_Immediate, 50);
	Template.AddCHEvent('AbilityActivated', class'UT_Trait_SecurityHacker'.static.OnAbilityActivated_SecurityHackerBacklash, ELD_OnStateSubmitted, 50);
	// Security hacker: the XCOM ability points on top of the biggest reward of the tower (CHL #120, fired by AcquireHackRewards for each earned reward).
	// Priority -100 on purpose: the listeners of this event can cancel the reward (Data[0].b = true, LWOTC's Failsafe does it for a bad reward); ours must run
	// after all of them to see the final decision and give the points only for a reward that is really given.
	Template.AddCHEvent('PreAcquiredHackReward', class'UT_Trait_SecurityHacker'.static.OnPreAcquiredHackReward_SecurityHacker, ELD_Immediate, -100);
	// Someone different: mission-start sync of its permanent stats, and the collapse (unconscious) at the start of the Nth XCOM turn.
	Template.AddCHEvent('OnTacticalBeginPlay', class'UT_Trait_SomeoneDifferent'.static.OnTacticalBeginPlay_SomeoneDifferent, ELD_Immediate, 50);
	Template.AddCHEvent('PlayerTurnBegun', class'UT_Trait_SomeoneDifferent'.static.OnPlayerTurnBegun_SomeoneDifferent, ELD_OnStateSubmitted, 50);
	// Pacifist: the marker "inflicted damage" (after the ability resolved), and its move to "previous turn" at the start of XCOM's turns.
	Template.AddCHEvent('AbilityActivated', class'UT_Trait_Pacifist'.static.OnAbilityActivated_Pacifist, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('PlayerTurnBegun', class'UT_Trait_Pacifist'.static.OnPlayerTurnBegun_Pacifist, ELD_OnStateSubmitted, 50);
	Template.RegisterInTactical = true;

	return Template;
}

// Events needed in both layers (registered ONCE here: the same handler in the strategy and the tactical template would run twice
// while both are active).
static function CHEventListenerTemplate CreateSharedListeners()
{
	local CHEventListenerTemplate Template;

	`CREATE_X2TEMPLATE(class'CHEventListenerTemplate', Template, 'UniqueTraits_SharedListeners');

	// Quality over quantity: -1 clip on the primary weapon (the armory shows the clip size too).
	Template.AddCHEvent('OverrideClipSize', class'UT_Trait_QualityOverQuantity'.static.OnOverrideClipSize_QualityOverQuantity, ELD_Immediate, 50);
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

	TraitClass = class'UniqueTraits_TraitConfig'.static.GetTraitClass(class'UniqueTraits_TraitConfig'.default.Traits[TraitIndex].TraitID);
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

	TraitClass = class'UniqueTraits_TraitConfig'.static.GetTraitClass(class'UniqueTraits_TraitConfig'.default.Traits[TraitIndex].TraitID);
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

	TraitClass = class'UniqueTraits_TraitConfig'.static.GetTraitClass(class'UniqueTraits_TraitConfig'.default.Traits[TraitIndex].TraitID);
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
