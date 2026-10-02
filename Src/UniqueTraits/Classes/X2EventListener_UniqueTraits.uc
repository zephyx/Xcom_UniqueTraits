//---------------------------------------------------------------------------------------
//  FILE:   X2EventListener_UniqueTraits.uc
//  PURPOSE: Detects a genuine Rookie -> Squaddie promotion earned through XP/kills (as
//           opposed to GTS training, a reward, TedMEC augmentation, a cheat, etc.) and
//           hands it off to X2DownloadableContentInfo_UniqueTraits for the trait draw.
//---------------------------------------------------------------------------------------
class X2EventListener_UniqueTraits extends X2EventListener config(UniqueTraits);

var config int ALLINARMS_THROW_RANGE;
var config int THIEF_STEAL_CHANCE_PCT;
var localized string THIEF_STEAL_FLYOVER;
var config array<int> TACTICIAN_MISS_DAMAGE_BY_TIER;
var config float SCOUT_SCANNER_RANGE_MULT;
var config int STAYFOCUS_FATIGUE_INTERVAL_NORMAL, STAYFOCUS_FATIGUE_INTERVAL_TIRED;
var config WillEventRollData STAYFOCUS_FATIGUE_ROLL_DATA;
var config array<name> FATIGUE_DOUBLING_TRAITS;
var config int BRIBE_SUPPLY_BONUS;
var config int SMOKER_WILL_REGEN;
var config int STAYFOCUS_WILL_LOSS;
var config int HUNTER_HEARING_INTERVAL;
var config int FALSEHOPE_XP_REDUCTION_PCT;
var config int ALWAYSREADY_RELOAD_BASE_CHANCE_PCT;
var config float ALWAYSREADY_RELOAD_WILL_FACTOR;
var config float ALWAYSREADY_RELOAD_AMMO_FACTOR;
var localized string ALWAYSREADY_RELOAD_FLYOVER;

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

	// Rank-ups only drive the per-rank stat scaling (Nerd, False Hope) now; the trait itself is drawn
	// earlier, when a rookie becomes eligible to choose a class (mission: OnPostMission in the DLCInfo;
	// covert action: the listener below).
	Template.AddCHEvent('UnitRankUp', OnUnitRankUp, ELD_OnStateSubmitted, 50);
	// Trait draw, covert action path. OnStateSubmitted: the draw opens its own transaction, which must
	// come after the covert action's state (with the kills) is committed.
	Template.AddCHEvent('CovertActionCompleted', OnCovertActionCompleted_RookieTrait, ELD_OnStateSubmitted, 50);
	// Optional soft dependency: only fires if the "Community Promotion Screen" mod is loaded.
	// Priority 1 = runs AFTER every other listener (larger number runs first): a block is only a block
	// if no later listener of another mod flips bCanPurchaseAbility back to true.
	Template.AddCHEvent('CPS_OverrideCanPurchaseAbility', OnCPSOverrideCanPurchaseAbility, ELD_Immediate, 1);
	// Priority 50 (< LWOTC's own 90 for this event, see OnOverrideSupplyDrop) so LWOTC's
	// listener runs first and we add on top of its result rather than being overwritten by it.
	Template.AddCHEvent('OverrideSupplyDrop', OnOverrideSupplyDrop, ELD_Immediate, 50);
	// Bribe: re-sync the region's displayed +supplies whenever a staff slot (incl. LWOTC's haven liaison
	// slots) is filled or emptied.
	Template.AddCHEvent('StaffUpdated', OnStaffUpdated_BribeSync, ELD_OnStateSubmitted, 50);
	// Born to be chief's officer-rank sync: officer rank only ever changes in the strategy layer
	// (finishing the LW officer training project), never mid-mission, so this belongs here, not
	// in the tactical listeners.
	Template.AddCHEvent('PreEndOfMonth', OnPreEndOfMonth_BornToBeChiefRankSync, ELD_Immediate, 50);
	// Second strategy-layer sync point for the same trait: whenever any personnel list finishes
	// refreshing. covers Barracks, the Armory soldier picker, and any other screen built on UIPersonnel,
	// once per refresh, not once per row). Not a correctness guarantee on its own (a pure UI-triggered event,
	// no pending GameState handed to us, so OnUIPersonnel_BornToBeChiefRankSync opens its own transaction
	// only if there's actually something to change).
	Template.AddCHEvent('UIPersonnel_OnSortFinished', OnUIPersonnel_BornToBeChiefRankSync, ELD_Immediate, 50);
	// Support: hide (not just gray out) offensive items from the Armory picker for its restricted
	// slots.
	Template.AddCHEvent('OverrideShowItemInLockerList', OnOverrideShowItemInLockerList, ELD_Immediate, 50);
	Template.RegisterInStrategy = true;

	return Template;
}

static function CHEventListenerTemplate CreateTacticalListeners()
{
	local CHEventListenerTemplate Template;

	`CREATE_X2TEMPLATE(class'CHEventListenerTemplate', Template, 'UniqueTraits_TacticalListeners');

	Template.AddCHEvent('OnGetItemRange', OnGetItemRange, ELD_Immediate, 50);
	Template.AddCHEvent('ItemLooted', OnItemLooted, ELD_Immediate, 50);
	Template.AddCHEvent('UnitBleedingOut', OnUnitBleedingOut, ELD_Immediate, 50);
	Template.AddCHEvent('AbilityActivated', OnAbilityActivated_Tactician, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('AbilityActivated', OnAbilityActivated_SmokerWillGain, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('AbilityActivated', OnAbilityActivated_StayFocusWillLoss, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('AbilityActivated', OnAbilityActivated_AlwaysReadyObsessiveReload, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('PlayerTurnEnded', OnPlayerTurnEnded_FatigueDoubling, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('PlayerTurnEnded', OnPlayerTurnEnded_Hunter, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('OnDistributeTacticalGameEndXp', OnDistributeTacticalGameEndXp_FalseHopeXp, ELD_OnStateSubmitted, 50);	// Born to be chief: the sync point that actually *guarantees* the officer-rank bonus is
	// correct in combat (see OnPreEndOfMonth_BornToBeChiefRankSync and
	// OnUIPersonnel_BornToBeChiefRankSync for the other two, display-freshness-only, sync
	// points). Fires exactly ONCE, right as a mission's tactical state is built.
	Template.AddCHEvent('OnTacticalBeginPlay', OnTacticalBeginPlay_BornToBeChiefRankSync, ELD_Immediate, 50);
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
	`log("UniqueTraits [DIAG] : OnUnitRankUp" @ NewUnitState.GetFullName()
		@ "-- previous: AcquiredTraits=" $ PreviousUnitState.AcquiredTraits.Length @ "AWCAbilities=" $ PreviousUnitState.AWCAbilities.Length
		@ "| new: AcquiredTraits=" $ NewUnitState.AcquiredTraits.Length @ "AWCAbilities=" $ NewUnitState.AWCAbilities.Length
		@ "class=" $ NewUnitState.GetSoldierClassTemplateName(),, 'UniqueTraits');

	// Rookie -> Squaddie (rank 0 -> 1): the trait was already drawn when the rookie became eligible
	// (OnPostMission / OnCovertActionCompleted_RookieTrait), and the
	// first rank is the one the trait was "granted at" -- nothing to scale. Later ranks scale.
	if (PreviousUnitState.GetRank() > 0)
	{
		class'X2DownloadableContentInfo_UniqueTraits'.static.ApplyNerdRankScaling(NewUnitState);
		class'X2DownloadableContentInfo_UniqueTraits'.static.ApplyFalseHopeRankScaling(NewUnitState);
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

// Jack of all trades: blocks buying the top-cost, non-class ability row (the ~35 AP "XCOM row"
// row in LWOTC's random-deck purchase system.
static function EventListenerReturn OnCPSOverrideCanPurchaseAbility(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;
	local XComGameState_Unit UnitState;
	local X2SoldierClassTemplate ClassTemplate;
	local int TopRankIndex;

	Tuple = XComLWTuple(EventData);
	UnitState = XComGameState_Unit(EventSource);
	if (Tuple == none || UnitState == none || Tuple.Data.Length < 16)
		return ELR_NoInterrupt;

	if (class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_Swordsman'))
		BlockSwordsmanPistolAbility(Tuple, UnitState);

	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_JackOfAllTrades'))
		return ELR_NoInterrupt;

	// The last column of the soldier's own class rank tree, not the AbilityPointCosts array length:
	// LWOTC and other mods change either one independently of the other, and only the class's
	// real number of ranks says which ability is the last one on screen.
	ClassTemplate = UnitState.GetSoldierClassTemplate();
	if (ClassTemplate != none)
		TopRankIndex = ClassTemplate.GetMaxConfiguredRank() - 1;
	else
		TopRankIndex = class'X2StrategyGameRulesetDataStructures'.default.AbilityPointCosts.Length - 1;

	if (Tuple.Data[1].i < TopRankIndex || Tuple.Data[5].b)
		return ELR_NoInterrupt;

	Tuple.Data[13].b = false;
	Tuple.Data[15].s = class'UniqueTraits_TraitConfig'.default.JackOfAllTradesLockedReason;

	`log("UniqueTraits [DIAG] : Jack of all trades blocked purchase of" @ Tuple.Data[0].n @ "(rank" @ Tuple.Data[1].i $ ", row" @ Tuple.Data[2].i $ ")",, 'UniqueTraits');

	return ELR_NoInterrupt;
}

// Swordsman: blocks buying a class ability tied to the pistol (secondary or pistol slot)
static function BlockSwordsmanPistolAbility(XComLWTuple Tuple, XComGameState_Unit UnitState)
{
	local X2SoldierClassTemplate ClassTemplate;
	local array<SoldierClassAbilityType> Possible;
	local SoldierClassAbilityType AbilityType;
	local SoldierClassWeaponType AllowedWeapon;
	local SoldierRankAbilities RankAbilities;
	local bool bPistolSecondary;

	// LWOTC's pistol row: the unit's own tree already has these abilities re-slotted to eInvSlot_Pistol
	// (X2DownloadableContentInfo_LongWarOfTheChosen, ~line 1100), whatever the class template says.
	foreach UnitState.AbilityTree(RankAbilities)
	{
		foreach RankAbilities.Abilities(AbilityType)
		{
			if (AbilityType.AbilityName == Tuple.Data[0].n && AbilityType.ApplyToWeaponSlot == eInvSlot_Pistol)
			{
				Tuple.Data[13].b = false;
				Tuple.Data[15].s = class'X2DownloadableContentInfo_UniqueTraits'.default.SwordsmanNoPistolReason;
				return;
			}
		}
	}

	// Vanilla-style class whose secondary slot is a pistol.
	ClassTemplate = UnitState.GetSoldierClassTemplate();
	if (ClassTemplate == none)
		return;

	foreach ClassTemplate.AllowedWeapons(AllowedWeapon)
	{
		if (AllowedWeapon.SlotType == eInvSlot_SecondaryWeapon && AllowedWeapon.WeaponType == 'pistol')
		{
			bPistolSecondary = true;
			break;
		}
	}
	if (!bPistolSecondary)
		return;

	Possible = ClassTemplate.GetAllPossibleAbilities();
	foreach Possible(AbilityType)
	{
		if (AbilityType.AbilityName == Tuple.Data[0].n
			&& (AbilityType.ApplyToWeaponSlot == eInvSlot_SecondaryWeapon || AbilityType.ApplyToWeaponSlot == eInvSlot_Pistol))
		{
			Tuple.Data[13].b = false;
			Tuple.Data[15].s = class'X2DownloadableContentInfo_UniqueTraits'.default.SwordsmanNoPistolReason;
			return;
		}
	}
}

static function EventListenerReturn OnStaffUpdated_BribeSync(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	class'X2DownloadableContentInfo_UniqueTraits'.static.SyncBribeSupplyBonus();
	return ELR_NoInterrupt;
}

// Support: excludes offensive items (frag grenades, ammo, etc.) from ever appearing in the
// Armory picker for Utility/Grenade pocket/Ammo pocket.
static function EventListenerReturn OnOverrideShowItemInLockerList(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;
	local XComGameState_Item ItemState;
	local XComGameState_Unit UnitState;
	local EInventorySlot Slot;

	Tuple = XComLWTuple(EventData);
	ItemState = XComGameState_Item(EventSource);
	if (Tuple == none || Tuple.Data.Length < 3 || ItemState == none)
		return ELR_NoInterrupt;

	Slot = EInventorySlot(Tuple.Data[1].i);

	// Swordsman: nothing listed for LWOTC's pistol slot, no pistol listed for the secondary slot.
	if (Slot == eInvSlot_SecondaryWeapon || Slot == eInvSlot_Pistol)
	{
		UnitState = XComGameState_Unit(Tuple.Data[2].o);
		if (UnitState != none
			&& class'X2DownloadableContentInfo_UniqueTraits'.static.IsSwordsmanPistolBlockedSlot(Slot, ItemState.GetMyTemplate())
			&& class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_Swordsman'))
			Tuple.Data[0].b = false;
		return ELR_NoInterrupt;
	}

	if (Slot != eInvSlot_Utility && Slot != eInvSlot_GrenadePocket && Slot != eInvSlot_AmmoPocket)
		return ELR_NoInterrupt;

	UnitState = XComGameState_Unit(Tuple.Data[2].o);
	if (UnitState == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_Support'))
		return ELR_NoInterrupt;

	if (class'X2ItemSlot_UniqueTraits'.static.IsOffensiveWeaponItem(ItemState.GetMyTemplate()))
		Tuple.Data[0].b = false;

	return ELR_NoInterrupt;
}

// Bribe: +20 supplies at the end of every month, as long as its holder is alive and haven advisor.
static function EventListenerReturn OnOverrideSupplyDrop(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;

	Tuple = XComLWTuple(EventData);
	if (Tuple == none || Tuple.Data.Length < 2)
		return ELR_NoInterrupt;

	// Only while a holder is actually stationed as a haven liaison (see SyncBribeSupplyBonus).
	if (class'X2DownloadableContentInfo_UniqueTraits'.static.AnyBribeHolderIsLiaison())
	{
		Tuple.Data[1].i += default.BRIBE_SUPPLY_BONUS;
		`log("UniqueTraits : Bribe -- OverrideSupplyDrop, +" $ default.BRIBE_SUPPLY_BONUS $ " supplies, month-end total now " $ Tuple.Data[1].i,, 'UniqueTraits');
	}

	return ELR_NoInterrupt;
}

// All in arms: +5 throw range, but only for items actually thrown by hand (carried in the
// grenade pocket or a utility slot).
static function EventListenerReturn OnGetItemRange(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;
	local XComGameState_Item ItemState;
	local XComGameState_Ability AbilityState;
	local XComGameState_Unit OwnerUnit;
	local X2WeaponTemplate ItemTemplate;

	Tuple = XComLWTuple(EventData);
	ItemState = XComGameState_Item(EventSource);
	if (Tuple == none || ItemState == none)
		return ELR_NoInterrupt;

	ItemTemplate = X2WeaponTemplate(ItemState.GetMyTemplate());
	if (ItemTemplate == none)
		return ELR_NoInterrupt;

	AbilityState = XComGameState_Ability(Tuple.Data[2].o);
	if (AbilityState == none)
		return ELR_NoInterrupt;

	OwnerUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(AbilityState.OwnerStateObject.ObjectID));
	if (OwnerUnit == none)
		return ELR_NoInterrupt;

	if (ItemTemplate.DataName == class'X2Ability_UniqueTraits_Advanced'.default.SCOUT_SCANNER_ITEM_NAME
		&& class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(OwnerUnit, 'UT_Scout'))
	{
		Tuple.Data[1].i = Round(float(Tuple.Data[1].i) * default.SCOUT_SCANNER_RANGE_MULT);
	}

	if ((ItemTemplate.InventorySlot == eInvSlot_GrenadePocket || ItemTemplate.InventorySlot == eInvSlot_Utility)
		&& class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(OwnerUnit, 'UT_AllInArms'))
	{
		Tuple.Data[1].i += default.ALLINARMS_THROW_RANGE;
	}

	return ELR_NoInterrupt;
}

// Thief: picking up loot (XCOM's turn only) always grants a bonus movement point. Independently,
// a flat chance rolls to secretly keep THAT ITEM (it's removed from the looter's
// inventory again right away (before it can ever reach XComHQ.LootRecovered at mission end, so
// it's simply never part of the recovered-loot pool, no separate post-mission bookkeeping
// needed)).
static function EventListenerReturn OnItemLooted(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit Looter, MutableLooter;
	local XComGameState_Item LootedItem;
	local XComGameState_Player ActivePlayer;

	Looter = XComGameState_Unit(EventSource);
	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Looter, 'UT_Thief'))
		return ELR_NoInterrupt;

	// Only during XCOM's own turn (loot can also be collected from a kill during the enemy turn).
	ActivePlayer = XComGameState_Player(`XCOMHISTORY.GetGameStateForObjectID(`TACTICALRULES.GetCachedUnitActionPlayerRef().ObjectID));
	if (ActivePlayer == none || ActivePlayer.GetTeam() != eTeam_XCom)
		return ELR_NoInterrupt;

	MutableLooter = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', Looter.ObjectID));
	MutableLooter.ActionPoints.AddItem(class'X2CharacterTemplateManager'.default.MoveActionPoint);

	if (`SYNC_RAND_STATIC(100) >= default.THIEF_STEAL_CHANCE_PCT)
		return ELR_NoInterrupt;

	LootedItem = XComGameState_Item(EventData);
	if (LootedItem == none || !MutableLooter.RemoveItemFromInventory(LootedItem, GameState))
		return ELR_NoInterrupt;

	// Flag the item so UIScreenListener_UT_LootWindow shows a red "Stolen!" row for it in the
	// tactical loot window (THIEF_STEAL_FLYOVER).
	MutableLooter.SetUnitFloatValue(name("UT_Thief_Stolen_" $ LootedItem.ObjectID), 1, eCleanup_BeginTactical);

	`log("UniqueTraits : Thief secretly kept" @ LootedItem.GetMyTemplateName() @ "- lost for XCOM",, 'UniqueTraits');

	return ELR_NoInterrupt;
}

// Tactician: missed shots still land a little damage, scaling with the weapon's tier. There's
// no clean way to attach a bonus "damage on miss" effect (like the base game's own
// WeaponUpgradeMissDamage) to an arbitrary attack ability from outside without either mutating
// the shared/singleton X2AbilityTemplate for everyone using that ability (dangerous) or deep-
// copying every attack ability template per unit (heavy). Instead, this reacts to the fully
// resolved miss after the fact and deals the bonus damage directly via TakeEffectDamage.
static function EventListenerReturn OnAbilityActivated_Tactician(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit SourceUnit, TargetUnit;
	local XComGameStateContext_Ability AbilityContext;
	local XComGameState_Item SourceWeapon;
	local X2WeaponTemplate WeaponTemplate;
	local EffectAppliedData EmptyEffectData;
	local XComGameState NewGameState;
	local int TierIndex, DamageAmount;

	// 'AbilityActivated' fires once for the interrupt step and again on resume/final for the same
	// shot (XComGameStateContext_Ability.uc:191/:414); react only once or the bonus damage doubles.
	if (GameState.GetContext().InterruptionStatus == eInterruptionStatus_Interrupt)
		return ELR_NoInterrupt;

	SourceUnit = XComGameState_Unit(EventSource);
	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SourceUnit, 'UT_Tactician'))
		return ELR_NoInterrupt;

	AbilityContext = XComGameStateContext_Ability(GameState.GetContext());
	if (AbilityContext == none || AbilityContext.ResultContext.HitResult != eHit_Miss)
		return ELR_NoInterrupt;

	if (AbilityContext.InputContext.PrimaryTarget.ObjectID == 0)
		return ELR_NoInterrupt;

	TargetUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(AbilityContext.InputContext.PrimaryTarget.ObjectID));
	if (TargetUnit == none || TargetUnit.IsDead())
		return ELR_NoInterrupt;

	SourceWeapon = XComGameState_Item(`XCOMHISTORY.GetGameStateForObjectID(AbilityContext.InputContext.ItemObject.ObjectID));
	if (SourceWeapon == none)
		return ELR_NoInterrupt;

	WeaponTemplate = X2WeaponTemplate(SourceWeapon.GetMyTemplate());
	if (WeaponTemplate == none || default.TACTICIAN_MISS_DAMAGE_BY_TIER.Length == 0)
		return ELR_NoInterrupt;

	TierIndex = Clamp(WeaponTemplate.Tier, 0, default.TACTICIAN_MISS_DAMAGE_BY_TIER.Length - 1);
	DamageAmount = default.TACTICIAN_MISS_DAMAGE_BY_TIER[TierIndex];
	if (DamageAmount <= 0)
		return ELR_NoInterrupt;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Tactician miss damage");
	TargetUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', TargetUnit.ObjectID));
	EmptyEffectData.SourceStateObjectRef = SourceUnit.GetReference();
	EmptyEffectData.TargetStateObjectRef = TargetUnit.GetReference();
	TargetUnit.TakeEffectDamage(none, DamageAmount, 0, 0, EmptyEffectData, NewGameState);
	`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}

// Always ready's malus: a genuine forced reload, matching the trait's own
// flavor text, not a psychological/morale effect.
//
// Custom Chance formula (different from vanilla obsessive reloader trait) :
// FinalChancePct = BASE + WillPercentMark * WILL_FACTOR + MissingAmmoPercent * AMMO_FACTOR
// WillPercentMark mirrors vanilla's own stress metric (XComGameState_Unit.uc:911,
// RollForNegativeTrait: 100 - CurrentWill/MaxWill*100 => 0 at full Will, 100 at zero Will).
// MissingAmmoPercent is the same shape applied to the primary weapon's ammo (0 at full clip, 100
// empty) => always > 0 here since the gate above already requires Ammo < GetClipSize().
static function EventListenerReturn OnAbilityActivated_AlwaysReadyObsessiveReload(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
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

	`log("UniqueTraits : Always ready -- obsessive reload roll triggered for" @ SourceUnit.GetFullName()
		$ " (WillPercentMark=" $ WillPercentMark $ " MissingAmmoPercent=" $ MissingAmmoPercent
		$ " FinalChancePct=" $ FinalChancePct $ ")",, 'UniqueTraits');

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Always ready forced reload");
	MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', SourceUnit.ObjectID));
	MutableWeapon = XComGameState_Item(NewGameState.ModifyStateObject(class'XComGameState_Item', SourceWeapon.ObjectID));
	MutableWeapon.Ammo = MutableWeapon.GetClipSize();
	MutableUnit.ActionPoints.Length = 0;
	`GAMERULES.SubmitGameState(NewGameState);

	`PRES.QueueWorldMessage(default.ALWAYSREADY_RELOAD_FLYOVER, `XWORLD.GetPositionFromTileCoordinates(SourceUnit.TileLocation), SourceUnit.GetReference(), eColor_Bad);

	`log("UniqueTraits : Always ready -- obsessive reload triggered for" @ SourceUnit.GetFullName() $ ", weapon reloaded, turn ended",, 'UniqueTraits');

	return ELR_NoInterrupt;
}

// Quick healing: remembers (for the rest of the mission) that this soldier bled out at least
// once, so X2Effect_UT_QuickHealing.UnitEndedTacticalPlay knows to keep the usual harsh
// recovery-time penalty instead of resetting LowestHP.
static function EventListenerReturn OnUnitBleedingOut(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit UnitState, MutableUnit;

	UnitState = XComGameState_Unit(EventData);
	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_QuickHealing'))
		return ELR_NoInterrupt;

	MutableUnit = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', UnitState.ObjectID));
	MutableUnit.SetUnitFloatValue('UT_QuickHealing_BledOut', 1, eCleanup_BeginTactical);

	return ELR_NoInterrupt;
}

// Fatigue-doubling malus (used by Smoker trait).
// LWOTC's own per-turn will loss (X2EventListener_Tactical.RollForPerTurnWillLoss,
// LW_Overhaul) can't be referenced or hooked directly. LW_Overhaul is a separate,
// independently-compiled mod package this project has no compile-time visibility into, and
// every LWOTC-gated trait must not introduce a hard dependency on it. Instead, this performs a
// second, independent will roll for each holder on the exact same public vanilla/CHL primitive
// LWOTC's own listener uses (XComGameStateContext_WillRoll, config(GameCore), unconditionally
// available), on a cadence mirroring LWOTC's own default config (NUM_TURNS_FOR_WILL_LOSS=3 /
// NUM_TURNS_FOR_TIRED_WILL_LOSS=2, PerTurnWillRollData / see XComLW_Overhaul.ini) via this
// mod's own, independently configurable copy of those values. The two rolls are entirely
// independent (this one doesn't read or affect LWOTC's own), so the net effect for a holder is
// losing will on this cadence roughly twice as often as a normal squadmate => "doubles" in the
// practical, felt sense described by the trait, without literally being coupled to LWOTC's
// internal implementation. FATIGUE_DOUBLING_TRAITS (config, default UT_StayFocus/UT_Smoker)
// keeps this generic instead of duplicating the function per trait.
static function EventListenerReturn OnPlayerTurnEnded_FatigueDoubling(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Player PlayerState;
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference SquadRef;
	local XComGameState_Unit SquadUnit;
	local XComGameStateContext_WillRoll WillRollContext;
	local name TraitID;
	local int Interval;
	local bool bHasFatigueDoublingTrait;

	PlayerState = XComGameState_Player(EventData);
	if (PlayerState == none || PlayerState.GetTeam() != eTeam_XCom)
		return ELR_NoInterrupt;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	foreach XComHQ.Squad(SquadRef)
	{
		SquadUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(SquadRef.ObjectID));
		if (SquadUnit == none)
			continue;

		bHasFatigueDoublingTrait = false;
		foreach default.FATIGUE_DOUBLING_TRAITS(TraitID)
		{
			if (class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SquadUnit, TraitID))
			{
				bHasFatigueDoublingTrait = true;
				break;
			}
		}
		if (!bHasFatigueDoublingTrait)
			continue;

		Interval = (SquadUnit.GetMentalState() == eMentalState_Tired) ? default.STAYFOCUS_FATIGUE_INTERVAL_TIRED : default.STAYFOCUS_FATIGUE_INTERVAL_NORMAL;
		if (Interval <= 0 || PlayerState.PlayerTurnCount % Interval != 0)
			continue;

		if (class'XComGameStateContext_WillRoll'.static.ShouldPerformWillRoll(default.STAYFOCUS_FATIGUE_ROLL_DATA, SquadUnit))
		{
			WillRollContext = class'XComGameStateContext_WillRoll'.static.CreateWillRollContext(SquadUnit, 'UT_ExtraFatigue',, false);
			WillRollContext.DoWillRoll(default.STAYFOCUS_FATIGUE_ROLL_DATA);
			WillRollContext.Submit();
		}
	}

	return ELR_NoInterrupt;
}

// Hunter: while a Hunter is alive on the mission, the squad "hears" the nearest enemy pod every
// HUNTER_HEARING_INTERVAL turns without having seen an enemy => vanilla's own hidden-movement
// indicator (X2Action_HiddenMovement), which normally only starts after TurnsUntilIndicator (a
// GameCore.ini value) such turns. Skipped once vanilla's own indicator is active so it never plays
// twice in one turn-end. Which soldier the camera/sound centre on is vanilla's native choice (the
// human closest to the pods), not necessarily the Hunter.
static function EventListenerReturn OnPlayerTurnEnded_Hunter(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Player PlayerState;
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference SquadRef;
	local XComGameState_Unit SquadUnit;
	local XComGameState NewGameState;
	local bool bHunterAlive;

	PlayerState = XComGameState_Player(EventData);
	if (PlayerState == none || PlayerState.GetTeam() != eTeam_XCom)
		return ELR_NoInterrupt;

	if (default.HUNTER_HEARING_INTERVAL <= 0
		|| PlayerState.TurnsSinceEnemySeen <= 0
		|| PlayerState.TurnsSinceEnemySeen % default.HUNTER_HEARING_INTERVAL != 0
		|| PlayerState.TurnsSinceEnemySeen >= class'X2Action_HiddenMovement'.default.TurnsUntilIndicator)
		return ELR_NoInterrupt;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	foreach XComHQ.Squad(SquadRef)
	{
		SquadUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(SquadRef.ObjectID));
		if (SquadUnit != none && SquadUnit.IsAlive() && !SquadUnit.bRemovedFromPlay
			&& class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SquadUnit, 'UT_Hunter'))
		{
			bHunterAlive = true;
			break;
		}
	}
	if (!bHunterAlive)
		return ELR_NoInterrupt;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Hunter hearing");
	// A game state with no modified object can be dropped before its visualization is built.
	NewGameState.ModifyStateObject(class'XComGameState_Player', PlayerState.ObjectID);
	XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = BuildVisualization_HunterHearing;
	`GAMERULES.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}

static function BuildVisualization_HunterHearing(XComGameState VisualizeGameState)
{
	class'X2Action_HiddenMovement'.static.AddHiddenMovementActionToBlock(VisualizeGameState);
}

// False Hope's XP malus: the holder earns FALSEHOPE_XP_REDUCTION_PCT% less experience, from the
// missions AFTER the trait was granted (the trait is drawn by OnPostMission, once the mission that made
// the rookie eligible is over, and UT_FalseHope_MissionXpSeen is baselined then). Two experience systems:
//
// 1. Vanilla full XP system: the XP manager fires 'OnDistributeTacticalGameEndXp' BEFORE distributing
//    (with the NewGameState that holds the result), so nothing can be scaled yet; this runs
//    ELD_OnStateSubmitted and the gain is the XP difference against the unit's previous version.
// 2. LWOTC (bUseFullXpSystem=false in its XComGameData_XpData.ini: vanilla distributes NO XP, rank-ups
//    depend on kills only): LWOTC's own listener for the same event (priority 90, so it runs BEFORE this
//    one at priority 50, larger numbers run first) adds the mission's "experience" to the soldier's
//    'MissionExperience' UnitValue in a transaction of its own, which LWOTC later turns into kill
//    equivalents ('OverrideTotalNumKills'). Only the NAME of that value is used here (no LW_Overhaul
//    class referenced). The gain is MissionExperience minus UT_FalseHope_MissionXpSeen, the amount already
//    accounted for; the reduction is removed from both, so the pair stays in sync and a missed or
//    reordered run just defers the malus to the next one instead of double counting.
//
// Without LWOTC the MissionExperience value never exists (0 forever): that part is a no-op.
// The reductions go in one follow-up transaction. A rank-up is never granted by this (promotion is a
// manual Armory action), so removing experience afterwards is safe.
static function EventListenerReturn OnDistributeTacticalGameEndXp_FalseHopeXp(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Unit> Soldiers;
	local XComGameState_Unit Soldier, XpStateUnit, PreviousUnitState, MutableUnit;
	local UnitValue ExperienceValue, SeenValue;
	local array<int> UnitIDs, XpReductions;
	local array<float> ExperienceTotals, ExperienceReductions;
	local XComGameState NewGameState;
	local int XpGained, XpReduction, i;
	local float ExperienceGained, ExperienceReduction;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	Soldiers = XComHQ.GetSoldiers();
	foreach Soldiers(Soldier)
	{
		if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Soldier, 'UT_FalseHope'))
			continue;

		// 1. Vanilla XP gained in the state that was just submitted (none when the unit isn't in it).
		XpReduction = 0;
		XpStateUnit = XComGameState_Unit(GameState.GetGameStateForObjectID(Soldier.ObjectID));
		if (XpStateUnit != none)
		{
			PreviousUnitState = XComGameState_Unit(XpStateUnit.GetPreviousVersion());
			if (PreviousUnitState != none)
			{
				XpGained = XpStateUnit.GetXPValue() - PreviousUnitState.GetXPValue();
				XpReduction = Round(XpGained * default.FALSEHOPE_XP_REDUCTION_PCT / 100.0);
			}
		}

		// 2. LWOTC mission experience added since the last time it was accounted for.
		ExperienceValue.fValue = 0;
		Soldier.GetUnitValue('MissionExperience', ExperienceValue);
		SeenValue.fValue = 0;
		Soldier.GetUnitValue('UT_FalseHope_MissionXpSeen', SeenValue);
		ExperienceGained = ExperienceValue.fValue - SeenValue.fValue;
		ExperienceReduction = 0;
		if (ExperienceGained > 0)
			ExperienceReduction = ExperienceGained * default.FALSEHOPE_XP_REDUCTION_PCT / 100.0;

		if (XpReduction > 0 || ExperienceReduction > 0)
		{
			UnitIDs.AddItem(Soldier.ObjectID);
			XpReductions.AddItem(XpReduction);
			ExperienceTotals.AddItem(ExperienceValue.fValue);
			ExperienceReductions.AddItem(ExperienceReduction);
			`log("UniqueTraits : False Hope XP malus for" @ Soldier.GetFullName()
				@ "-- XP gained" @ XpGained @ "(removing" @ XpReduction $ "), LWOTC mission experience gained" @ ExperienceGained
				@ "(removing" @ ExperienceReduction $ ")",, 'UniqueTraits');
		}
	}

	if (UnitIDs.Length == 0)
		return ELR_NoInterrupt;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: False Hope XP malus");
	for (i = 0; i < UnitIDs.Length; ++i)
	{
		MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', UnitIDs[i]));
		if (XpReductions[i] > 0)
			MutableUnit.AddXp(-XpReductions[i]);

		if (ExperienceReductions[i] > 0)
		{
			MutableUnit.SetUnitFloatValue('MissionExperience', ExperienceTotals[i] - ExperienceReductions[i], eCleanup_Never);
			MutableUnit.SetUnitFloatValue('UT_FalseHope_MissionXpSeen', ExperienceTotals[i] - ExperienceReductions[i], eCleanup_Never);
		}
	}
	`GAMERULES.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}

// Smoker's will gain: a ONE-TIME +SMOKER_WILL_REGEN Will per smoke grenade, granted only to a
// Smoker trait holder who is standing exactly where a smoke grenade (any thrower) lands, at the
// moment it detonates.
static function EventListenerReturn OnAbilityActivated_SmokerWillGain(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateContext_Ability AbilityContext;
	local XComGameState_Ability AbilityState;
	local XComGameState_Item SourceWeapon;
	local StateObjectReference TargetRef;
	local XComGameState_Unit TargetUnit, MutableUnit;
	local XComGameState NewGameState;
	local int NewWill;

	if (GameState.GetContext().InterruptionStatus == eInterruptionStatus_Interrupt)
		return ELR_NoInterrupt;

	AbilityContext = XComGameStateContext_Ability(GameState.GetContext());
	if (AbilityContext == none)
		return ELR_NoInterrupt;

	AbilityState = XComGameState_Ability(`XCOMHISTORY.GetGameStateForObjectID(AbilityContext.InputContext.AbilityRef.ObjectID));
	if (AbilityState == none
		|| (AbilityState.GetMyTemplateName() != 'ThrowGrenade' && AbilityState.GetMyTemplateName() != 'LaunchGrenade'))
		return ELR_NoInterrupt;

	SourceWeapon = XComGameState_Item(`XCOMHISTORY.GetGameStateForObjectID(AbilityContext.InputContext.ItemObject.ObjectID));
	if (SourceWeapon == none
		|| class'X2AbilityCost_UT_SmokeThrow'.default.SMOKER_GRENADE_WEAPON_NAMES.Find(SourceWeapon.GetMyTemplateName()) == INDEX_NONE)
		return ELR_NoInterrupt;

	foreach AbilityContext.InputContext.MultiTargets(TargetRef)
	{
		TargetUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(TargetRef.ObjectID));
		if (TargetUnit == none || TargetUnit.IsDead()
			|| !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(TargetUnit, 'UT_Smoker'))
			continue;

		NewWill = Min(TargetUnit.GetCurrentStat(eStat_Will) + default.SMOKER_WILL_REGEN, TargetUnit.GetMaxStat(eStat_Will));
		if (NewWill <= TargetUnit.GetCurrentStat(eStat_Will))
			continue;

		NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Smoker will gain");
		MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', TargetUnit.ObjectID));
		MutableUnit.SetCurrentStat(eStat_Will, NewWill);
		`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);
	}

	return ELR_NoInterrupt;
}

// Stay focus's malus: a FIXED STAYFOCUS_WILL_LOSS Will loss for the holder each time they use the
// ability (replaces the old "doubled fatigue" malus, which now only Smoker keeps).
static function EventListenerReturn OnAbilityActivated_StayFocusWillLoss(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateContext_Ability AbilityContext;
	local XComGameState_Unit SourceUnit, MutableUnit;
	local XComGameState NewGameState;
	local int NewWill;

	if (GameState.GetContext().InterruptionStatus == eInterruptionStatus_Interrupt)
		return ELR_NoInterrupt;

	AbilityContext = XComGameStateContext_Ability(GameState.GetContext());
	if (AbilityContext == none || AbilityContext.InputContext.AbilityTemplateName != 'UT_StayFocus')
		return ELR_NoInterrupt;

	SourceUnit = XComGameState_Unit(EventSource);
	if (SourceUnit == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SourceUnit, 'UT_StayFocus'))
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

// Born to be chief's officer-rank stat sync. Officer rank only ever changes in the strategy
// layer (an LW officer-training HQ project completing) so this runs off
// the vanilla/CHL 'PreEndOfMonth' event. There's no precise "officer training completed" event to hook (currently),
// where LW_Overhaul's own would-be 'UnitPromoted' trigger is dead code, commented out, and CHL
// exposes no generic "any HQ project completed" event either. Monthly is a deliberate compromise:
// frequent enough that the bonus won't be stale for long, purely strategy-layer, and
// piggybacks GameState changes directly onto the same NewGameState 'PreEndOfMonth' is fired with
// (ELD_Immediate, still open/unsubmitted at this point) rather than opening a separate
// transaction. Two more sync points cover the gaps this alone can't (see each's own comment for
// why): 'OnTacticalBeginPlay' (OnTacticalBeginPlay_BornToBeChiefRankSync, tactical listeners
// below) once at the start of every mission (the one that actually *guarantees* combat
// correctness) and 'UIPersonnel_OnSortFinished' (OnUIPersonnel_BornToBeChiefRankSync, below)
// whenever a personnel list is shown, purely to keep the displayed number fresh between missions.
static function EventListenerReturn OnPreEndOfMonth_BornToBeChiefRankSync(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Unit> Soldiers;
	local XComGameState_Unit Soldier, MutableUnit;

	if (GameState == none)
		return ELR_NoInterrupt;

	// Also the safety net for Bribe's region bonus (holder died/dismissed since the last StaffUpdated).
	class'X2DownloadableContentInfo_UniqueTraits'.static.SyncBribeSupplyBonus(GameState);

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	Soldiers = XComHQ.GetSoldiers();
	foreach Soldiers(Soldier)
	{
		if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Soldier, 'UT_BornToBeChief'))
			continue;

		MutableUnit = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', Soldier.ObjectID));
		class'X2DownloadableContentInfo_UniqueTraits'.static.ApplyBornToBeChiefRankScaling(MutableUnit);
	}

	return ELR_NoInterrupt;
}

// Born to be chief's officer-rank stat sync, personnel-list variant
static function EventListenerReturn OnUIPersonnel_BornToBeChiefRankSync(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Unit> Soldiers;
	local XComGameState_Unit Soldier, MutableUnit;
	local XComGameState NewGameState;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	Soldiers = XComHQ.GetSoldiers();
	foreach Soldiers(Soldier)
	{
		if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Soldier, 'UT_BornToBeChief'))
			continue;

		if (NewGameState == none)
			NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Born to be chief personnel-list rank sync");

		MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Soldier.ObjectID));
		class'X2DownloadableContentInfo_UniqueTraits'.static.ApplyBornToBeChiefRankScaling(MutableUnit);
	}

	if (NewGameState != none)
		`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}

// Born to be chief's officer-rank stat sync, mission-start variant
static function EventListenerReturn OnTacticalBeginPlay_BornToBeChiefRankSync(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference SquadRef;
	local XComGameState_Unit SquadUnit, MutableUnit;

	if (GameState == none)
		return ELR_NoInterrupt;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	foreach XComHQ.Squad(SquadRef)
	{
		SquadUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(SquadRef.ObjectID));
		if (SquadUnit == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SquadUnit, 'UT_BornToBeChief'))
			continue;

		MutableUnit = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', SquadUnit.ObjectID));
		class'X2DownloadableContentInfo_UniqueTraits'.static.ApplyBornToBeChiefRankScaling(MutableUnit);
	}

	return ELR_NoInterrupt;
}

