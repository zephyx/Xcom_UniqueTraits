//---------------------------------------------------------------------------------------
//  FILE:   UT_TraitBase.uc
//  PURPOSE: Base class of every per-trait class (UT_Trait_<Name>.uc). An X2Ability subclass is
//           auto-discovered as an X2DataSet, so each trait class returns its own ability
//           template(s) from CreateTemplates(); this base does not override it (X2DataSet's own is empty). The hooks below are all
//           no-ops by default; a trait overrides only the ones it needs. They are dispatched from
//           X2DownloadableContentInfo_UniqueTraits (GrantTraitToUnit / ClearAssignedTrait, or RemoveUnitTrait / SetUnitTrait as a transaction;
//           OnPostMission and OnPostTemplatesCreated on every trait of the pool) and
//           X2EventListener_UniqueTraits (OnUnitRankUp) through
//           UniqueTraits_TraitConfig.GetTraitClass(TraitID).
//---------------------------------------------------------------------------------------
class UT_TraitBase extends X2Ability config(UniqueTraits);

// Extra eligibility condition for the draw (besides Probability/RequiredMods in the ini): a trait whose mechanic could not
// apply in the current game returns false (policy: exclude, don't degrade). See UniqueTraits_TraitConfig.IsTraitEligible.
static function bool IsEligible()
{
	return true;
}

// Eligibility of this trait for one given unit (the draw and SetUnitTrait / AddUniqueTrait ask it): a trait that cannot work on some soldiers returns false for them
// (Predestined: a faction hero pays ability points for his class perks).
static function bool IsEligibleForUnit(XComGameState_Unit Unit)
{
	return true;
}

// Called by GrantTraitToUnit once the TraitID is in AcquiredTraits, BEFORE the generic AWCAbilities grant.
static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
}

// Called by ClearAssignedTrait once the TraitID is out of AcquiredTraits, BEFORE the generic AWCAbilities sweep. NewGameState is the caller's pending
// state (the one MutableUnit belongs to): anything else the trait must take back (Bribe's region bonus) goes into it, in the same transaction.
static function OnClear(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
}

// Called by MigrateTraits (X2DownloadableContentInfo_UniqueTraits) for a holder whose stamped version is older than the trait's Version in the ini (UniqueTraitDefinition.Version),
// once for each version step: FromVersion is the version the soldier is at, the step brings him to FromVersion + 1. Same pending state conventions as OnGrant: MutableUnit is a
// modified object of NewGameState, a change container of the caller's own. Nothing to do for a change that the rest of the machinery already repairs (the abilities granted and the
// retired ones are reconciled by MigrateTraits, the permanent stats by their ledger); this is for what only the trait knows how to bring up to date.
static function OnMigrate(XComGameState_Unit MutableUnit, int FromVersion, XComGameState NewGameState)
{
}

// True for the traits that change the BASE stats of their holder for good (ShiftStat): Nerd, False Hope, Born to be chief, Mind over matter, Support,
// Someone different. Only those take part in the "stats rebuilt" handling below (OnStatsReset) and in the rank-up sync (OnRankUp).
static function bool ShiftsStats()
{
	return false;
}

// Called from 'UnitRankUp' for every REAL promotion (the rank went up, rookie -> squaddie included) of a holder, on a pending copy of the unit in a change container of
// the dispatcher's own (X2EventListener_UniqueTraits.OnUnitRankUp). A trait that makes its stats depend on the rank brings them to what the new rank calls for:
// idempotent (the target minus the ledger), so the several events of one state that ranks up several times do no harm. Returns true if it changed the unit.
static function bool OnRankUp(XComGameState_Unit MutableUnit)
{
	return false;
}

// Called when the BASE stats of a holder were rebuilt from scratch by a respec (LWOTC's RespecSoldier: ResetSoldierRank puts every stat back to the template's,
// then the soldier ranks up again): every permanent change the trait had made is gone. The trait must FORGET them (ForgetShifts, its own marks to zero, without
// touching the stats) and apply its effect again for the unit as he is now. Same pending state conventions as OnRankUp.
static function OnStatsReset(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
}

// Event registrations. X2EventListener_UniqueTraits.CreateStrategyListeners / CreateTacticalListeners / CreateSharedListeners call these on every trait of the pool that
// is NOT disabled (UniqueTraits_TraitConfig.GetActiveTraitClass), with the template being built: a trait puts its own Template.AddCHEvent(...) here (a larger priority runs
// first). A trait that needs an event in both layers (strategy and tactical) must use the shared hook, once: the same handler in both templates would run twice while both
// are active. 'AbilityActivated' fires more than once per ability: each of its handlers starts with the interrupt-step early return.
static function OnCreateStrategyListeners(CHEventListenerTemplate Template)
{
}

static function OnCreateTacticalListeners(CHEventListenerTemplate Template)
{
}

static function OnCreateSharedListeners(CHEventListenerTemplate Template)
{
}

// CHL #419: called by X2DownloadableContentInfo_UniqueTraits.AbilityTagExpandHandler_CH for every trait of the pool when a description holds a tag <Ability:UT_...> that the
// base game did not handle. A trait that has a tag of its own expands it here: fill OutString and return true. ParseObj is the XComGameState_Effect (buff display of a
// passive), the XComGameState_Ability or the X2AbilityTemplate being described; StrategyParseObj is the unit in the Armory / promotion screens.
static function bool ExpandAbilityTag(string InString, out string OutString, Object ParseObj, Object StrategyParseObj, XComGameState GameState)
{
	return false;
}

//---------------------------------------------------------------------------------------
// Permanent stat changes and their ledger
//---------------------------------------------------------------------------------------
// A trait that changes the base stats of its holder for good does it through ShiftStat, which also keeps a LEDGER: per stat, the net change of the BASE value that
// ShiftStat really made (the UnitValue UT_Shift_<stat>, eCleanup_Never; a holder has ONE trait, so the ledger is that trait's). The ledger is the truth about what the trait
// put in the stats, whatever the ini says now, whatever rounding or clamping the engine did, and however the trait's own marks drifted:
// - the removal of the trait takes back exactly the ledger (RevertShifts), so the stats are the ones the soldier would have without the trait;
// - a sync that wants a stat to be at T applies T minus the ledger (idempotent);
// - after a respec the ledger is wiped without touching the stats (ForgetShifts), since the respec already removed what it described.
// The changes apply at once, a rookie (rank 0) included. A respec wipes them from the base stats while the ledger still says they are there, so the ledger must be
// forgotten and the trait applied again. The respec is told from the HISTORY, not from an event (the respec of a rookie sends none): ShiftStat keeps in the unit the
// index of the history when the ledger was last written (UT_ShiftIdx), and WasRespecSinceLastShift looks, among the states of the unit newer than that, for the one
// LWOTC's RespecSoldier makes (a change container whose ChangeInfo is exactly "Respec Soldier" / the console mod's "Reset Soldier" counts only when the event
// 'UnitRandomizedStats' noted the unit, i.e. when its reset does not keep the stats). Every sync and every removal starts with ForgetIfRespec; the
// listeners (X2EventListener_UniqueTraits) also run the test at once when the respec happens (a ranked soldier's 'UnitRankUp', the Armory main menu refreshing).
// A reset that is not LWOTC's (the console mod [WOTC] Additional Soldier Console Commands, whose "Reset Soldier" state wipes the stats and then calls RandomizeStats) is told by the event
// 'UnitRandomizedStats' instead (see UniqueTraits_TraitConfig.RESET_UNIT_IDS).

// Adds (or, with a negative Delta, removes) an amount to BOTH the max and the current value of a stat: a genuine,
// permanent change. Both Get*Stat are captured BEFORE SetBaseMaxStat, which resyncs the current stat as a side effect.
static final function ShiftStat(XComGameState_Unit UnitState, ECharStatType Stat, float Delta)
{
	local float NewMax, NewCurrent, BaseBefore;

	BaseBefore = UnitState.GetBaseStat(Stat);
	NewMax = UnitState.GetMaxStat(Stat) + Delta;
	NewCurrent = UnitState.GetCurrentStat(Stat) + Delta;

	// A lowering never takes the CURRENT Will below 1 (a soldier already below 1 keeps what he has): the max has its own floor, MIN_MAX_WILL (ShiftStatTo).
	if (Stat == eStat_Will && Delta < 0)
		NewCurrent = FMax(NewCurrent, FMin(UnitState.GetCurrentStat(Stat), 1.0));

	UnitState.SetBaseMaxStat(Stat, NewMax);
	UnitState.SetCurrentStat(Stat, NewCurrent);

	// What the BASE value really did (see the ledger above).
	SetStatLedger(UnitState, Stat, GetStatLedger(UnitState, Stat) + (UnitState.GetBaseStat(Stat) - BaseBefore));

	// When the ledger was last written (see above).
	UnitState.SetUnitFloatValue('UT_ShiftIdx', `XCOMHISTORY.GetCurrentHistoryIndex(), eCleanup_Never);
}

static final function name StatLedgerName(ECharStatType Stat)
{
	return name("UT_Shift_" $ int(Stat));
}

// True if LWOTC's RespecSoldier was made on this unit since the ledger was last written (UT_ShiftIdx): among the versions of the unit newer than that index, one
// belongs to a change container whose ChangeInfo is exactly "Respec Soldier" (the console mod [WOTC] Additional Soldier Console Commands names its states "Respec Soldier: Rank N" and "Reset Soldier":
// they do not match, see UniqueTraits_TraitConfig.RESET_UNIT_IDS). The ledger and the index are read in the unit GIVEN (pass the latest committed version from a listener, the pending copy from a sync).
// The walk starts from the latest committed version.
static final function bool WasRespecSinceLastShift(XComGameState_Unit Unit)
{
	local XComGameState_Unit Version;
	local XComGameState VersionState;
	local XComGameStateContext_ChangeContainer Context;
	local UnitValue IdxValue;
	local bool bHasIdx;
	local int LastIdx;

	Version = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(Unit.ObjectID));
	if (Version == none || !HasStatLedger(Unit))
		return false;

	// The ledger and its index are those of the unit GIVEN (a pending copy has already rewritten them after a respec was handled) => only the walk starts from the latest committed version.
	bHasIdx = Unit.GetUnitValue('UT_ShiftIdx', IdxValue);
	LastIdx = bHasIdx ? int(IdxValue.fValue) : -1;

	// The ledger was written in the latest state of the history: nothing newer can hold a respec.
	if (bHasIdx && LastIdx >= `XCOMHISTORY.GetCurrentHistoryIndex())
		return false;

	while (Version != none)
	{
		if (!bHasIdx && !HasStatLedger(Version))
			break;

		VersionState = Version.GetParentGameState();
		if (VersionState == none || (bHasIdx && VersionState.HistoryIndex <= LastIdx))
			break;

		Context = XComGameStateContext_ChangeContainer(VersionState.GetContext());
		if (Context != none && (Context.ChangeInfo == "Respec Soldier"
			|| (Context.ChangeInfo == "Reset Soldier" && class'UniqueTraits_TraitConfig'.static.IsUnitRandomized(Unit.ObjectID))))
			return true;

		Version = XComGameState_Unit(Version.GetPreviousVersion());
	}

	return false;
}

// Start of every sync and of every removal: forgets the ledger if the unit was respecced since it was last written (the respec wiped what it described). A trait that
// has marks of its own clears them when this returns true. True if the ledger was forgotten.
static final function bool ForgetIfRespec(XComGameState_Unit MutableUnit)
{
	if (!HasStatLedger(MutableUnit) || !WasRespecSinceLastShift(MutableUnit))
		return false;

	ForgetShifts(MutableUnit);
	`log("UniqueTraits : respec found in the history of" @ MutableUnit.GetFullName() @ ": the permanent stat changes of his trait are gone, applied again",, 'UniqueTraits');

	return true;
}

static final function float GetStatLedger(XComGameState_Unit Unit, ECharStatType Stat)
{
	return GetUnitFloat(Unit, StatLedgerName(Stat));
}

static final function SetStatLedger(XComGameState_Unit MutableUnit, ECharStatType Stat, float Amount)
{
	if (Abs(Amount) < 0.0005)
		MutableUnit.ClearUnitValue(StatLedgerName(Stat));
	else
		MutableUnit.SetUnitFloatValue(StatLedgerName(Stat), Amount, eCleanup_Never);
}

static final function bool HasStatLedger(XComGameState_Unit Unit)
{
	local int i;

	for (i = 1; i < eStat_MAX; ++i)
	{
		if (Abs(GetStatLedger(Unit, ECharStatType(i))) >= 0.0005)
			return true;
	}

	return false;
}

// Brings a stat to what Wanted calls for as a change of ours: ShiftStat of (Wanted - ledger). True if it really moved.
// The MAX Will never goes below UniqueTraits_TraitConfig.MIN_MAX_WILL because of a trait: a lowering that would cross the floor is cut to what is left above it (a soldier
// already below the floor loses nothing more). The ledger records what REALLY changed, so the removal of the trait and the next syncs stay exact: the target is asked again
// at every sync and applied as far as the floor allows (a Will that grows later, rank-ups, lets the rest of the malus in); a respec starts over from the fresh base.
static final function bool ShiftStatTo(XComGameState_Unit MutableUnit, ECharStatType Stat, float Wanted)
{
	local float Delta, Allowed;

	ForgetIfRespec(MutableUnit);

	Delta = Wanted - GetStatLedger(MutableUnit, Stat);
	if (Stat == eStat_Will && Delta < 0)
	{
		Allowed = FMax(0.0, MutableUnit.GetMaxStat(eStat_Will) - float(class'UniqueTraits_TraitConfig'.default.MIN_MAX_WILL));
		Delta = -FMin(-Delta, Allowed);
	}

	if (Abs(Delta) < 0.0005)
		return false;

	ShiftStat(MutableUnit, Stat, Delta);

	return true;
}

// Takes back EXACTLY what ShiftStat put in the stats (the ledger) and empties the ledger: the stats the soldier would have without the trait.
static final function RevertShifts(XComGameState_Unit MutableUnit)
{
	local int i;
	local float Amount;

	// Wiped by a respec since the last shift: nothing left to take back.
	ForgetIfRespec(MutableUnit);

	for (i = 1; i < eStat_MAX; ++i)
	{
		Amount = GetStatLedger(MutableUnit, ECharStatType(i));
		if (Abs(Amount) >= 0.0005)
			ShiftStat(MutableUnit, ECharStatType(i), -Amount);
		MutableUnit.ClearUnitValue(StatLedgerName(ECharStatType(i)));
	}

	MutableUnit.ClearUnitValue('UT_ShiftIdx');

	// Taking back an HP bonus from a wounded soldier must not leave him at 0 or below.
	if (MutableUnit.GetCurrentStat(eStat_HP) < 1)
		MutableUnit.SetCurrentStat(eStat_HP, 1);
}

// Empties the ledger WITHOUT touching the stats: the base stats were rebuilt (respec), what the ledger described no longer exists.
static final function ForgetShifts(XComGameState_Unit MutableUnit)
{
	local int i;

	for (i = 1; i < eStat_MAX; ++i)
		MutableUnit.ClearUnitValue(StatLedgerName(ECharStatType(i)));

	MutableUnit.ClearUnitValue('UT_ShiftIdx');

	// The reset noted for this unit (see UniqueTraits_TraitConfig.RESET_UNIT_IDS) is dealt with.
	class'UniqueTraits_TraitConfig'.static.ForgetUnitRandomized(MutableUnit.ObjectID);
}

// Label shown in the shot breakdown (hit chance tooltip) for a trait's aim modifier: the effect's display name
// (SetDisplayInfo, i.e. the trait's name) rather than its internal EffectName ("UT_NEMESIS_...").
static final function string GetShotModifierLabel(X2Effect_Persistent Effect)
{
	if (Effect.FriendlyName != "")
		return Effect.FriendlyName;

	return string(Effect.EffectName);
}

// Called by X2DownloadableContentInfo_UniqueTraits.OnPostMission (CHL #212) on EVERY trait class once a mission is over and committed,
// before the After Action screen: a trait that has something to do then checks for its own holders (supplies, upgrades...).
static function OnPostMission()
{
}

// Called by X2DownloadableContentInfo_UniqueTraits.OnPostTemplatesCreated on EVERY trait class of the pool (ini order) once all the templates exist, with this mod's
// CHDLCRunOrder RUN_LAST (so the templates other mods add or change are already there): a trait that patches templates it does not own (another ability's cost, a
// shared effect, a to-hit calc...) does it here. The traits' patches do not depend on each other's order.
static function OnPostTemplatesCreated()
{
}

// Called by X2DownloadableContentInfo_UniqueTraits.CanAddItemToInventory_CH_Improved for the unit's own trait: return true
// (and set DisabledReason) to forbid equipping ItemTemplate in Slot. That hook only stops FUTURE equips, so a trait that
// bans items strips the ones already carried in OnGrant.
static function bool IsItemBlocked(EInventorySlot Slot, X2ItemTemplate ItemTemplate, out string DisabledReason)
{
	return false;
}

// Shared prelude of the 'OnGetItemRange' handlers (All in arms, Scout): false unless the event is about a weapon
// template used by an ability with a known owner.
static final function bool ParseItemRangeEvent(Object EventData, Object EventSource, out XComLWTuple Tuple, out X2WeaponTemplate ItemTemplate, out XComGameState_Unit OwnerUnit)
{
	local XComGameState_Item ItemState;
	local XComGameState_Ability AbilityState;

	Tuple = XComLWTuple(EventData);
	ItemState = XComGameState_Item(EventSource);
	if (Tuple == none || ItemState == none)
		return false;

	ItemTemplate = X2WeaponTemplate(ItemState.GetMyTemplate());
	if (ItemTemplate == none)
		return false;

	AbilityState = XComGameState_Ability(Tuple.Data[2].o);
	if (AbilityState == none)
		return false;
	OwnerUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(AbilityState.OwnerStateObject.ObjectID));
	return OwnerUnit != none;
}

// A hidden ability template that only holds effects applied "by hand" (see UT_EffectHelpers): never granted to any unit, no input, no
// visualization. The caller adds its effects with AddTargetEffect (their index is the one given to UT_EffectHelpers.ApplyAbilityEffect).
static final function X2AbilityTemplate HiddenEffectHolder(name TemplateName)
{
	local X2AbilityTemplate Template;

	`CREATE_X2ABILITY_TEMPLATE(Template, TemplateName);

	Template.IconImage = "img:///UILibrary_PerkIcons.UIPerk_standard";
	Template.AbilitySourceName = 'eAbilitySource_Perk';
	Template.eAbilityIconBehaviorHUD = eAbilityIconBehavior_NeverShow;
	Template.Hostility = eHostility_Neutral;
	Template.bDontDisplayInAbilitySummary = true;
	Template.bDisplayInUITooltip = false;
	Template.bDisplayInUITacticalText = false;

	Template.AbilityToHitCalc = default.DeadEye;
	Template.AbilityTargetStyle = default.SimpleSingleTarget;
	Template.AbilityTriggers.AddItem(new class'X2AbilityTrigger_Placeholder');   // validation wants a trigger ("is invalid: no Triggers"); never fires, never granted
	Template.BuildNewGameStateFn = TypicalAbility_BuildGameState;

	return Template;
}


// A float UnitValue of Unit; DefaultValue when the unit has none (or is none).
static final function float GetUnitFloat(XComGameState_Unit Unit, name ValueName, optional float DefaultValue = 0.0)
{
	local UnitValue Value;

	if (Unit != none && Unit.GetUnitValue(ValueName, Value))
		return Value.fValue;

	return DefaultValue;
}

// Shared prelude of the 'AbilityActivated' handlers: true only for a resolved activation (not the interrupt step) of an
// ability (AbilityContext) whose source (SourceUnit = EventSource) holds TraitID. A handler that has to test something else first (Smoker, Always
// ready, the Security hacker backlash) keeps its own prelude.
static final function bool ParseAbilityActivation(XComGameState GameState, Object EventSource, name TraitID, out XComGameStateContext_Ability AbilityContext, out XComGameState_Unit SourceUnit)
{
	if (GameState.GetContext().InterruptionStatus == eInterruptionStatus_Interrupt)
		return false;

	AbilityContext = XComGameStateContext_Ability(GameState.GetContext());
	SourceUnit = XComGameState_Unit(EventSource);

	return AbilityContext != none && SourceUnit != none && class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SourceUnit, TraitID);
}

// Takes the items of ItemStates out of Unit's inventory and gives them back to the HQ, last first, keeping the first KeepCount (item-slot
// validations: Maniac explosive's excess pockets, Support's vest slot). NewGameState is the validation's own pending state.
static final function MoveItemsBackToHQ(XComGameState_Unit Unit, XComGameState_HeadquartersXCom XComHQ, XComGameState NewGameState, array<XComGameState_Item> ItemStates, optional int KeepCount = 0)
{
	local XComGameState_Item ItemState;
	local int i;

	for (i = ItemStates.Length - 1; i >= KeepCount; i--)
	{
		ItemState = XComGameState_Item(NewGameState.ModifyStateObject(class'XComGameState_Item', ItemStates[i].ObjectID));
		if (Unit.RemoveItemFromInventory(ItemState, NewGameState))
			XComHQ.PutItemInInventory(NewGameState, ItemState);
	}
}
