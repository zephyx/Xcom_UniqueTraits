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
	Template.AddCHEvent('UnitRankUp', OnUnitRankUp, ELD_OnStateSubmitted, 50);
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
	Template.AddCHEvent('OnDistributeTacticalGameEndXp', class'UT_Trait_FalseHope'.static.OnDistributeTacticalGameEndXp, ELD_OnStateSubmitted, 50);
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
	// tower offers the computers' rewards and a doubled lock (ELD_Immediate: inside the ability's pending state, before the screen reads them); If it succeeds, disables every security tower.
	Template.AddCHEvent('AbilityActivated', class'UT_Trait_SecurityHacker'.static.OnAbilityActivated_SecurityHacker, ELD_Immediate, 50);
	Template.AddCHEvent('AbilityActivated', class'UT_Trait_SecurityHacker'.static.OnAbilityActivated_SecurityHackerBacklash, ELD_OnStateSubmitted, 50);
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

// `RankUpSoldier` triggers 'UnitRankUp'. This listener is ELD_OnStateSubmitted, so by the time it
// fires, RankUpSoldier's own transaction is already fully committed to history : NewUnitState
// (EventData) is that final, submitted object. It only applies the per-rank scaling of Nerd/False
// Hope: trait ASSIGNMENT no longer happens here (see AssignTraitsToEligibleRookies).
static function EventListenerReturn OnUnitRankUp(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit NewUnitState, PreviousUnitState;
	local class<UT_TraitBase> TraitClass;
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

	// Rookie -> Squaddie (rank 0 -> 1): the trait was already drawn when the rookie became eligible
	// (OnPostMission / OnCovertActionCompleted_RookieTrait), and the
	// first rank is the one the trait was "granted at" -- nothing to scale. Later ranks scale.
	if (PreviousUnitState.GetRank() > 0)
	{
		if (class'X2DownloadableContentInfo_UniqueTraits'.static.GetAssignedTraitIndex(NewUnitState, TraitIndex))
		{
			TraitClass = class'UniqueTraits_TraitConfig'.static.GetTraitClass(class'UniqueTraits_TraitConfig'.default.Traits[TraitIndex].TraitID);
			if (TraitClass != none)
				TraitClass.static.OnRankUp(NewUnitState);
		}
	}

	return ELR_NoInterrupt;
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
