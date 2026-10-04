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
	Template.RegisterInStrategy = true;

	return Template;
}

static function CHEventListenerTemplate CreateTacticalListeners()
{
	local CHEventListenerTemplate Template;

	`CREATE_X2TEMPLATE(class'CHEventListenerTemplate', Template, 'UniqueTraits_TacticalListeners');

	Template.AddCHEvent('OnGetItemRange', class'UT_Trait_AllInArms'.static.OnGetItemRange_AllInArms, ELD_Immediate, 50);
	Template.AddCHEvent('OnGetItemRange', class'UT_Trait_Scout'.static.OnGetItemRange_Scout, ELD_Immediate, 50);
	Template.AddCHEvent('ItemLooted', class'UT_Trait_Thief'.static.OnItemLooted, ELD_Immediate, 50);
	Template.AddCHEvent('UnitBleedingOut', class'UT_Trait_QuickHealing'.static.OnUnitBleedingOut, ELD_Immediate, 50);
	// Fired by the tactical rules when the mission is cleaned up, with the state submitted before the end-of-mission health adjustment.
	Template.AddCHEvent('CleanupTacticalMission', class'UT_Trait_QuickHealing'.static.OnCleanupTacticalMission_QuickHealing, ELD_Immediate, 50);
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
