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

	// ELD_OnStateSubmitted, not ELD_Immediate: AssignTraitOnNaturalPromotion opens and submits its
	// own separate transaction (see its own comment for why), which must only happen once
	// RankUpSoldier's own transaction has actually been committed.
	Template.AddCHEvent('UnitRankUp', OnUnitRankUp, ELD_OnStateSubmitted, 50);
	// Optional soft dependency: only fires if the "Community Promotion Screen" mod is loaded.
	Template.AddCHEvent('CPS_OverrideCanPurchaseAbility', OnCPSOverrideCanPurchaseAbility, ELD_Immediate, 50);
	// Priority 50 (< LWOTC's own 90 for this event, see OnOverrideSupplyDrop) so LWOTC's
	// listener runs first and we add on top of its result rather than being overwritten by it.
	Template.AddCHEvent('OverrideSupplyDrop', OnOverrideSupplyDrop, ELD_Immediate, 50);
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
	// Defender: hide (not just gray out) offensive items from the Armory picker for its restricted
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
	Template.AddCHEvent('PlayerTurnEnded', OnPlayerTurnEnded_FatigueDoubling, ELD_OnStateSubmitted, 50);
	// Born to be chief: the sync point that actually *guarantees* the officer-rank bonus is
	// correct in combat (see OnPreEndOfMonth_BornToBeChiefRankSync and
	// OnUIPersonnel_BornToBeChiefRankSync for the other two, display-freshness-only, sync
	// points). Fires exactly ONCE, right as a mission's tactical state is built.
	Template.AddCHEvent('OnTacticalBeginPlay', OnTacticalBeginPlay_BornToBeChiefRankSync, ELD_Immediate, 50);
	Template.RegisterInTactical = true;

	return Template;
}

// `RankUpSoldier` triggers 'UnitRankUp'. This listener is ELD_OnStateSubmitted (see the comment
// on AddCHEvent above), so by the time it fires, RankUpSoldier's own transaction is already
// fully committed to history : NewUnitState (EventData) is that final, submitted object.
//
// To tell a genuine Rookie -> Squaddie promotion (the only one we care about for trait
// ASSIGNMENT) apart from an artificial one (GTS "Train Rookie" project, a covert-action
// reward, a cheat, etc.), we need to know what the unit's state looked like JUST BEFORE this
// specific promotion.
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

	if (PreviousUnitState.GetRank() > 0)
	{
		class'X2DownloadableContentInfo_UniqueTraits'.static.ApplyNerdRankScaling(NewUnitState);
		return ELR_NoInterrupt;
	}

	if (!PreviousUnitState.CanRankUpSoldier())
	{
		`log("UniqueTraits : OnUnitRankUp -- pre-promotion CanRankUpSoldier() was false for" @ NewUnitState.GetFullName() @ "-- treating as non-natural (GTS/reward/cheat), not assigning a trait",, 'UniqueTraits');
		return ELR_NoInterrupt;
	}

	`log("UniqueTraits : OnUnitRankUp -- natural promotion confirmed for" @ NewUnitState.GetFullName() @ ", assigning trait",, 'UniqueTraits');
	class'X2DownloadableContentInfo_UniqueTraits'.static.AssignTraitOnNaturalPromotion(NewUnitState);

	return ELR_NoInterrupt;
}

// Jack of all trades: blocks buying the top-cost, non-class ability row (the ~35 AP "XCOM row"
// row in LWOTC's random-deck purchase system.
static function EventListenerReturn OnCPSOverrideCanPurchaseAbility(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;
	local XComGameState_Unit UnitState;
	local int TopRankIndex;

	Tuple = XComLWTuple(EventData);
	UnitState = XComGameState_Unit(EventSource);
	if (Tuple == none || UnitState == none || Tuple.Data.Length < 16)
		return ELR_NoInterrupt;

	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_JackOfAllTrades'))
		return ELR_NoInterrupt;

	TopRankIndex = class'X2StrategyGameRulesetDataStructures'.default.AbilityPointCosts.Length - 1;
	if (Tuple.Data[1].i != TopRankIndex || Tuple.Data[5].b)
		return ELR_NoInterrupt;

	Tuple.Data[13].b = false;
	Tuple.Data[15].s = class'UniqueTraits_TraitConfig'.default.JackOfAllTradesLockedReason;

	return ELR_NoInterrupt;
}

// Defender: excludes offensive items (frag grenades, ammo, etc.) from ever appearing in the
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
	if (Slot != eInvSlot_Utility && Slot != eInvSlot_GrenadePocket && Slot != eInvSlot_AmmoPocket)
		return ELR_NoInterrupt;

	UnitState = XComGameState_Unit(Tuple.Data[2].o);
	if (UnitState == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_Defender'))
		return ELR_NoInterrupt;

	if (class'X2ItemSlot_UniqueTraits'.static.IsOffensiveWeaponItem(ItemState.GetMyTemplate()))
		Tuple.Data[0].b = false;

	return ELR_NoInterrupt;
}

// Bribe: +20 supplies at the end of every month, as long as its holder is alive (in the roster,
// regardless of current assignment). This event (CHL issue #539, XComGameState_HeadquartersResistance
// .uc:528) is vanilla/CHL, not LWOTC-specific, but the trait itself is still LWOTC-gated overall
// because its downside (infiltration time, via AbilityCovertness in
// Config/XComLW_InfiltrationSettings.ini) has no equivalent without LWOTC's infiltration system.
static function EventListenerReturn OnOverrideSupplyDrop(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;

	Tuple = XComLWTuple(EventData);
	if (Tuple == none || Tuple.Data.Length < 2)
		return ELR_NoInterrupt;

	if (class'X2DownloadableContentInfo_UniqueTraits'.static.AnyLivingSoldierHasTrait('UT_Bribe'))
		Tuple.Data[1].i += default.BRIBE_SUPPLY_BONUS;

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

// Thief: picking up any piece of loot always refunds a standard action point. Independently,
// a flat chance rolls to secretly keep THAT ITEM (it's removed from the looter's
// inventory again right away (before it can ever reach XComHQ.LootRecovered at mission end, so
// it's simply never part of the recovered-loot pool, no separate post-mission bookkeeping
// needed)).
static function EventListenerReturn OnItemLooted(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit Looter, MutableLooter;
	local XComGameState_Item LootedItem;

	Looter = XComGameState_Unit(EventSource);
	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Looter, 'UT_Thief'))
		return ELR_NoInterrupt;

	MutableLooter = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', Looter.ObjectID));
	MutableLooter.ActionPoints.AddItem(class'X2CharacterTemplateManager'.default.StandardActionPoint);

	if (`SYNC_RAND_STATIC(100) >= default.THIEF_STEAL_CHANCE_PCT)
		return ELR_NoInterrupt;

	LootedItem = XComGameState_Item(EventData);
	if (LootedItem == none || !MutableLooter.RemoveItemFromInventory(LootedItem, GameState))
		return ELR_NoInterrupt;

	`PRES.QueueWorldMessage(default.THIEF_STEAL_FLYOVER, `XWORLD.GetPositionFromTileCoordinates(MutableLooter.TileLocation), MutableLooter.GetReference(), eColor_Bad);

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

// Fatigue-doubling malus shared by Stay focus and Smoker ("doubles per-turn fatigue will
// loss"). LWOTC's own per-turn will loss (X2EventListener_Tactical.RollForPerTurnWillLoss,
// LW_Overhaul) can't be referenced or hooked directly. LW_Overhaul is a separate,
// independently-compiled mod package this project has no compile-time visibility into, and
// every LWOTC-gated trait must not introduce a hard dependency on it. Instead, this performs a
// second, independent will roll for each holder on the exact same public vanilla/CHL primitive
// LWOTC's own listener uses (XComGameStateContext_WillRoll, config(GameCore), unconditionally
// available), on a cadence mirroring LWOTC's own default config (NUM_TURNS_FOR_WILL_LOSS=3 /
// NUM_TURNS_FOR_TIRED_WILL_LOSS=2, PerTurnWillRollData / see XComLW_Overhaul.ini) via this
// mod's own, independently configurable copy of those values. The two rolls are entirely
// independent (this one doesn't read or affect LWOTC's own), so the net effect for a holder is
// losing will on this cadence roughly twice as often as a normal squadmate -- "doubles" in the
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

