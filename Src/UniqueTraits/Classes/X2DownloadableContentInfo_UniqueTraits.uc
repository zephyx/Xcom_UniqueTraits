//---------------------------------------------------------------------------------------
//  FILE:   X2DownloadableContentInfo_UniqueTraits.uc
//  PURPOSE: Holds the natural-promotion trait draw (AssignTraitOnNaturalPromotion, called from
//           X2EventListener_UniqueTraits when a rookie is promoted through earned XP) and grants
//           each assigned trait's abilities via AWCAbilities
//---------------------------------------------------------------------------------------
class X2DownloadableContentInfo_UniqueTraits extends X2DownloadableContentInfo config(UniqueTraits);

var config bool bLog;
var config int JACKOFALLTRADES_AP_BONUS;
var config name DEFENDER_GRENADEPOCKET_BACKFILL_ITEM_NAME;

var localized string ManiacExplosiveNoPrimaryReason;
var localized string DefenderNoOffensiveItemReason;

static event OnLoadedSavedGame()
{}

static event InstallNewCampaign(XComGameState StartState)
{}

static event OnPostTemplatesCreated()
{
	local X2AbilityTemplateManager AbilityManager;
	local X2AbilityTemplate ThrowGrenadeTemplate;
	local X2AbilityCost_ActionPoints OriginalCost;
	local X2AbilityCost_UT_SmokeThrow NewCost;
	local int i;

	AbilityManager = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();
	ThrowGrenadeTemplate = AbilityManager.FindAbilityTemplate('ThrowGrenade');
	if (ThrowGrenadeTemplate == none)
		return;

	for (i = 0; i < ThrowGrenadeTemplate.AbilityCosts.Length; ++i)
	{
		OriginalCost = X2AbilityCost_ActionPoints(ThrowGrenadeTemplate.AbilityCosts[i]);
		if (OriginalCost == none)
			continue;

		NewCost = new class'X2AbilityCost_UT_SmokeThrow';
		NewCost.iNumPoints = OriginalCost.iNumPoints;
		NewCost.bFreeCost = OriginalCost.bFreeCost;
		NewCost.bAddWeaponTypicalCost = OriginalCost.bAddWeaponTypicalCost;
		NewCost.bConsumeAllPoints = OriginalCost.bConsumeAllPoints;
		NewCost.bMoveCost = OriginalCost.bMoveCost;
		NewCost.AllowedTypes = OriginalCost.AllowedTypes;
		NewCost.DoNotConsumeAllEffects = OriginalCost.DoNotConsumeAllEffects;
		NewCost.DoNotConsumeAllSoldierAbilities = OriginalCost.DoNotConsumeAllSoldierAbilities;

		ThrowGrenadeTemplate.AbilityCosts[i] = NewCost;
		break;
	}
}

// Used for defender trait to prevent using offensive items in utility slots and maniacExplosive for primary weapon.
static function bool CanAddItemToInventory_CH_Improved(out int bCanAddItem, const EInventorySlot Slot, const X2ItemTemplate ItemTemplate, int Quantity, XComGameState_Unit UnitState, optional XComGameState CheckGameState, optional out string DisabledReason, optional XComGameState_Item ItemState)
{
	if (Slot == eInvSlot_PrimaryWeapon && UnitHasTrait(UnitState, 'UT_ManiacExplosive'))
	{
		bCanAddItem = 0;
		DisabledReason = default.ManiacExplosiveNoPrimaryReason;
		return CheckGameState != none;
	}

	if ((Slot == eInvSlot_Utility || Slot == eInvSlot_GrenadePocket || Slot == eInvSlot_AmmoPocket)
		&& UnitHasTrait(UnitState, 'UT_Defender'))
	{
		// Diagnostic (2026-09-29): the user reported an ALLOWED item (smoke grenade/medikit) getting
		// silently lost from XCOM's inventory entirely after being dropped from one of these slots on
		// a Defender holder -- confirmed only with this trait active, in both Utility and Grenade
		// pocket. This hook itself only ever blocks OFFENSIVE items and otherwise explicitly declines
		// to override (`return CheckGameState == none;`), so it shouldn't be able to cause that on its
		// own -- logging every call against these three slots for a Defender holder (blocked or not)
		// to see what this hook is actually being asked about during the drop -> ValidateLoadout
		// sequence, since ValidateLoadout's own Utility/Grenade-pocket minimum-equip auto-refill
		// (XComGameState_Unit.uc ~12100-12246) calls AddItemToInventory for freshly-created candidate
		// items in the same transaction and could be routing through here in a way not yet understood.
		`log("UniqueTraits : CanAddItemToInventory_CH_Improved -- Defender check, Slot=" $ Slot
			$ " Item=" $ (ItemTemplate != none ? string(ItemTemplate.DataName) : "none")
			$ " IsOffensive=" $ class'X2ItemSlot_UniqueTraits'.static.IsOffensiveWeaponItem(ItemTemplate)
			$ " CheckGameStateIsNone=" $ (CheckGameState == none)
			$ " Unit=" $ UnitState.GetFullName(),, 'UniqueTraits');

		if (class'X2ItemSlot_UniqueTraits'.static.IsOffensiveWeaponItem(ItemTemplate))
		{
			bCanAddItem = 0;
			DisabledReason = default.DefenderNoOffensiveItemReason;
			return CheckGameState != none;
		}
	}

	return CheckGameState == none;
}

// Check if the unit own a specific trait.
static final function bool GetAssignedTraitIndex(XComGameState_Unit UnitState, out int OutIndex)
{
	local int i;
	local name AcquiredTraitName;

	foreach UnitState.AcquiredTraits(AcquiredTraitName)
	{
		for (i = 0; i < class'UniqueTraits_TraitConfig'.default.Traits.Length; ++i)
		{
			if (class'UniqueTraits_TraitConfig'.default.Traits[i].TraitID == AcquiredTraitName)
			{
				OutIndex = i;
				return true;
			}
		}
	}

	return false;
}

// Convenience check used by traits whose behaviour hooks a global event rather than an
// effect on the unit (e.g. All in arms' throw-range bonus), where we still need to know
// whether a specific unit is the one holding a specific trait.
static final function bool UnitHasTrait(XComGameState_Unit UnitState, name TraitID)
{
	local int TraitIndex;

	if (UnitState == none || !GetAssignedTraitIndex(UnitState, TraitIndex))
		return false;

	return class'UniqueTraits_TraitConfig'.default.Traits[TraitIndex].TraitID == TraitID;
}

// Bribe's +20 monthly supplies applies as long as its holder is alive and in the roster.
static final function bool AnyLivingSoldierHasTrait(name TraitID)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Unit> Soldiers;
	local XComGameState_Unit Soldier;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return false;

	Soldiers = XComHQ.GetSoldiers();
	foreach Soldiers(Soldier)
	{
		if (UnitHasTrait(Soldier, TraitID))
			return true;
	}

	return false;
}

// Called by X2EventListener_UniqueTraits once it has confirmed this is a genuine Rookie ->
// Squaddie promotion earned through XP/kills (not GTS training, a reward, a cheat, etc). Takes
// only the not-yet-submitted UnitState from the 'UnitRankUp' event for reading (eligibility
// checks, ObjectID)
static final function AssignTraitOnNaturalPromotion(XComGameState_Unit UnitState)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Unit> Soldiers;
	local XComGameState_Unit Soldier;
	local array<bool> IndexUsed;
	local array<int> AvailableIndices;
	local int ExistingIndex, i, PickedIndex;
	local name TraitID;
	local XComGameState OwnGameState;
	local XComGameState_Unit MutableUnit;

	`log("UniqueTraits : AssignTraitOnNaturalPromotion called for" @ UnitState.GetFullName() @ "-- pool has" @ class'UniqueTraits_TraitConfig'.default.Traits.Length @ "trait(s) declared",, 'UniqueTraits');

	// Defensive: a fresh rookie should never already carry a trait.
	if (GetAssignedTraitIndex(UnitState, ExistingIndex))
	{
		`log("UniqueTraits [WARN] : AssignTraitOnNaturalPromotion -- " $ UnitState.GetFullName() $ " already has trait index" @ ExistingIndex @ "-- skipping (unexpected for a fresh promotion)",, 'UniqueTraits');
		return;
	}

	IndexUsed.Length = class'UniqueTraits_TraitConfig'.default.Traits.Length;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
	{
		`log("UniqueTraits [WARN] : AssignTraitOnNaturalPromotion -- no XComGameState_HeadquartersXCom found, aborting",, 'UniqueTraits');
		return;
	}

	Soldiers = XComHQ.GetSoldiers();
	foreach Soldiers(Soldier)
	{
		if (Soldier.ObjectID == UnitState.ObjectID)
			continue;

		if (GetAssignedTraitIndex(Soldier, ExistingIndex))
			IndexUsed[ExistingIndex] = true;
	}

	for (i = 0; i < class'UniqueTraits_TraitConfig'.default.Traits.Length; ++i)
	{
		`log("UniqueTraits : trait[" $ i $ "] TraitID='" $ class'UniqueTraits_TraitConfig'.default.Traits[i].TraitID
			$ "' bEnabled=" $ class'UniqueTraits_TraitConfig'.default.Traits[i].bEnabled
			$ " RequiredMods.Length=" $ class'UniqueTraits_TraitConfig'.default.Traits[i].RequiredMods.Length
			$ " GrantedAbilities.Length=" $ class'UniqueTraits_TraitConfig'.default.Traits[i].GrantedAbilities.Length
			$ " IndexUsed=" $ IndexUsed[i]
			$ " IsTraitEligible=" $ class'UniqueTraits_TraitConfig'.static.IsTraitEligible(i),, 'UniqueTraits');

		if (IndexUsed[i])
			continue;

		if (!class'UniqueTraits_TraitConfig'.static.IsTraitEligible(i))
			continue;

		AvailableIndices.AddItem(i);
	}

	if (AvailableIndices.Length == 0)
	{
		`log("UniqueTraits [WARN] : trait pool exhausted, no trait assigned to" @ UnitState.GetFullName(),, 'UniqueTraits');
		return;
	}

	PickedIndex = AvailableIndices[`SYNC_RAND_STATIC(AvailableIndices.Length)];
	TraitID = class'UniqueTraits_TraitConfig'.default.Traits[PickedIndex].TraitID;

	OwnGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Assign Trait");
	MutableUnit = XComGameState_Unit(OwnGameState.ModifyStateObject(class'XComGameState_Unit', UnitState.ObjectID));

	GrantTraitToUnit(MutableUnit, OwnGameState, TraitID);

	`GAMERULES.SubmitGameState(OwnGameState);

	`log("UniqueTraits : assigned trait" @ TraitID @ "to" @ UnitState.GetFullName() $ " (ObjectID" $ UnitState.ObjectID $ ")"
		$ " -- post-submit AcquiredTraits.Length=" $ MutableUnit.AcquiredTraits.Length,, 'UniqueTraits');
}

// Graant a trait to a unit.
static final function GrantTraitToUnit(XComGameState_Unit MutableUnit, XComGameState NewGameState, name TraitID)
{
	local name AbilityName;
	local int TraitIndex;
	local ClassAgnosticAbility AWCAbility;

	if (class'UniqueTraits_TraitConfig'.static.FindTraitIndexByID(TraitID) == INDEX_NONE)
	{
		`log("UniqueTraits [WARN] : GrantTraitToUnit -- unknown TraitID '" $ TraitID $ "', nothing granted",, 'UniqueTraits');
		return;
	}
	TraitIndex = class'UniqueTraits_TraitConfig'.static.FindTraitIndexByID(TraitID);

	MutableUnit.AcquiredTraits.AddItem(TraitID);

	// Always ready's malus reuses the base game's own Obsessive Reloader personality trait
	// instead of duplicating its will-roll-gated chance-to-reload-after-moving logic.
	if (TraitID == 'UT_AlwaysReady')
		MutableUnit.AcquiredTraits.AddItem('Trait_ObsessiveReloader');

	// Jack of all trades' AP bonus is a one-time grant at assignment time, not a persistent
	// effect (the ability itself carries no gameplay effect for this part).
	if (TraitID == 'UT_JackOfAllTrades')
		MutableUnit.AbilityPoints += default.JACKOFALLTRADES_AP_BONUS;

	// Maniac explosive's primary weapon block (CanAddItemToInventory_CH_Improved below) only
	// stops *future* attempts to equip one => the rookie's already-equipped starting weapon
	// needs to be stripped back to HQ inventory explicitly here.
	// Same for defender utility slots
	if (TraitID == 'UT_ManiacExplosive')
		RemoveManiacPrimaryWeapon(MutableUnit, NewGameState);

	if (TraitID == 'UT_Defender')
		RemoveDefenderOffensiveItems(MutableUnit, NewGameState);

	// Grant the unit the real ability(ies) related to the trait.
	foreach class'UniqueTraits_TraitConfig'.default.Traits[TraitIndex].GrantedAbilities(AbilityName)
	{
		AWCAbility.AbilityType.AbilityName = AbilityName;
		AWCAbility.AbilityType.ApplyToWeaponSlot = eInvSlot_Unknown;
		AWCAbility.AbilityType.UtilityCat = '';
		AWCAbility.iRank = 0;
		AWCAbility.bUnlocked = true;
		MutableUnit.AWCAbilities.AddItem(AWCAbility);
	}
}

// Remove a trait added by this mod.
exec function RemoveUniqueTrait()
{
	local UIArmory Armory;
	local StateObjectReference UnitRef;
	local XComGameState_Unit UnitState, MutableUnit;
	local XComGameState NewGameState;

	Armory = UIArmory(`SCREENSTACK.GetFirstInstanceOf(class'UIArmory'));
	if (Armory == none)
	{
		`log("UniqueTraits : RemoveUniqueTrait -- no Armory screen open, select a soldier first",, 'UniqueTraits');
		return;
	}

	UnitRef = Armory.GetUnitRef();
	UnitState = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(UnitRef.ObjectID));
	if (UnitState == none)
	{
		`log("UniqueTraits : RemoveUniqueTrait -- no unit selected",, 'UniqueTraits');
		return;
	}

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: RemoveUniqueTrait");
	MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', UnitState.ObjectID));

	if (ClearAssignedTrait(MutableUnit))
	{
		`GAMERULES.SubmitGameState(NewGameState);
		Armory.PopulateData();
		`log("UniqueTraits : RemoveUniqueTrait -- cleared trait from" @ UnitState.GetFullName(),, 'UniqueTraits');
	}
	else
	{
		`XCOMHISTORY.CleanupPendingGameState(NewGameState);
		`log("UniqueTraits : RemoveUniqueTrait --" @ UnitState.GetFullName() @ "has no trait assigned",, 'UniqueTraits');
	}
}

// Strips a unit's assigned trait (called by RemoveUniqueTrait above).
static final function bool ClearAssignedTrait(XComGameState_Unit MutableUnit)
{
	local int TraitIndex, i, AWCIdx;
	local name TraitID, AbilityName;
	local bool bClearedAnything;

	if (GetAssignedTraitIndex(MutableUnit, TraitIndex))
	{
		TraitID = class'UniqueTraits_TraitConfig'.default.Traits[TraitIndex].TraitID;

		MutableUnit.AcquiredTraits.RemoveItem(TraitID);

		if (TraitID == 'UT_AlwaysReady')
			MutableUnit.AcquiredTraits.RemoveItem('Trait_ObsessiveReloader');

		if (TraitID == 'UT_JackOfAllTrades')
			MutableUnit.AbilityPoints -= default.JACKOFALLTRADES_AP_BONUS;

		bClearedAnything = true;
		`log("UniqueTraits : cleared trait" @ TraitID @ "from" @ MutableUnit.GetFullName(),, 'UniqueTraits');
	}

	for (i = 0; i < class'UniqueTraits_TraitConfig'.default.Traits.Length; ++i)
	{
		foreach class'UniqueTraits_TraitConfig'.default.Traits[i].GrantedAbilities(AbilityName)
		{
			for (AWCIdx = MutableUnit.AWCAbilities.Length - 1; AWCIdx >= 0; AWCIdx--)
			{
				if (MutableUnit.AWCAbilities[AWCIdx].AbilityType.AbilityName == AbilityName)
				{
					`log("UniqueTraits : RemoveUniqueTrait sweep -- removing AWCAbilities entry" @ AbilityName @ "from" @ MutableUnit.GetFullName(),, 'UniqueTraits');
					MutableUnit.AWCAbilities.Remove(AWCIdx, 1);
					bClearedAnything = true;
				}
			}
		}
	}

	return bClearedAnything;
}

// A console command for granting a specific trait on purpose.
exec function AddUniqueTrait(name TraitID)
{
	local UIArmory Armory;
	local StateObjectReference UnitRef;
	local XComGameState_Unit UnitState, MutableUnit;
	local XComGameState NewGameState;

	if (class'UniqueTraits_TraitConfig'.static.FindTraitIndexByID(TraitID) == INDEX_NONE)
	{
		`log("UniqueTraits : AddUniqueTrait -- unknown TraitID '" $ TraitID $ "', check Config/XComUniqueTraits.ini for valid TraitID values",, 'UniqueTraits');
		return;
	}

	Armory = UIArmory(`SCREENSTACK.GetFirstInstanceOf(class'UIArmory'));
	if (Armory == none)
	{
		`log("UniqueTraits : AddUniqueTrait -- no Armory screen open, select a soldier first",, 'UniqueTraits');
		return;
	}

	UnitRef = Armory.GetUnitRef();
	UnitState = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(UnitRef.ObjectID));
	if (UnitState == none)
	{
		`log("UniqueTraits : AddUniqueTrait -- no unit selected",, 'UniqueTraits');
		return;
	}

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: AddUniqueTrait");
	MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', UnitState.ObjectID));

	ClearAssignedTrait(MutableUnit);
	GrantTraitToUnit(MutableUnit, NewGameState, TraitID);

	`GAMERULES.SubmitGameState(NewGameState);
	Armory.PopulateData();

	`log("UniqueTraits : AddUniqueTrait -- force-assigned" @ TraitID @ "to" @ UnitState.GetFullName(),, 'UniqueTraits');
}

static final function RemoveManiacPrimaryWeapon(XComGameState_Unit UnitState, XComGameState NewGameState)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_Item PrimaryWeapon;

	PrimaryWeapon = UnitState.GetItemInSlot(eInvSlot_PrimaryWeapon, NewGameState);
	if (PrimaryWeapon == none)
		return;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	PrimaryWeapon = XComGameState_Item(NewGameState.ModifyStateObject(class'XComGameState_Item', PrimaryWeapon.ObjectID));
	if (UnitState.RemoveItemFromInventory(PrimaryWeapon, NewGameState) && XComHQ != none)
		XComHQ.PutItemInInventory(NewGameState, PrimaryWeapon);
}

// Defender's offensive-item block (CanAddItemToInventory_CH_Improved above) only stops FUTURE equip attempts.
static final function RemoveDefenderOffensiveItems(XComGameState_Unit UnitState, XComGameState NewGameState)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local array<EInventorySlot> PocketSlots;
	local EInventorySlot PocketSlot;
	local array<XComGameState_Item> SlotItems;
	local XComGameState_Item SlotItem;

	PocketSlots.AddItem(eInvSlot_Utility);
	PocketSlots.AddItem(eInvSlot_GrenadePocket);
	PocketSlots.AddItem(eInvSlot_AmmoPocket);

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));

	foreach PocketSlots(PocketSlot)
	{
		SlotItems = UnitState.GetAllItemsInSlot(PocketSlot, NewGameState);
		foreach SlotItems(SlotItem)
		{
			if (!class'X2ItemSlot_UniqueTraits'.static.IsOffensiveWeaponItem(SlotItem.GetMyTemplate()))
				continue;

			SlotItem = XComGameState_Item(NewGameState.ModifyStateObject(class'XComGameState_Item', SlotItem.ObjectID));
			if (UnitState.RemoveItemFromInventory(SlotItem, NewGameState) && XComHQ != none)
				XComHQ.PutItemInInventory(NewGameState, SlotItem);
		}
	}

	BackfillDefenderGrenadePocket(UnitState, NewGameState);
}

// Vanilla's own Grenade Pocket always wants at least one grenade equipped (CHItemSlot.
// SlotGetMinimumEquipped defaults every vanilla eInvSlot_GrenadePocket to MinimumEquipped=1)
// Backfilling with a real, persistent Smoke Grenade here (same CreateInstanceFromTemplate +
// AddItemToInventory pattern GrenadePocketPurchased itself uses) keeps the slot non-empty so that
// auto-refill path never triggers at all.
static final function BackfillDefenderGrenadePocket(XComGameState_Unit UnitState, XComGameState NewGameState)
{
	local X2ItemTemplate BackfillTemplate;
	local XComGameState_Item BackfillItem;
	local name BackfillItemName;

	if (!UnitState.HasGrenadePocket())
		return;

	if (UnitState.GetItemInSlot(eInvSlot_GrenadePocket, NewGameState) != none)
		return;

	BackfillItemName = default.DEFENDER_GRENADEPOCKET_BACKFILL_ITEM_NAME;
	if (BackfillItemName == '')
		BackfillItemName = 'SmokeGrenade';

	BackfillTemplate = class'X2ItemTemplateManager'.static.GetItemTemplateManager().FindItemTemplate(BackfillItemName);
	if (BackfillTemplate == none)
	{
		`log("UniqueTraits [WARN] : BackfillDefenderGrenadePocket -- backfill item '" $ BackfillItemName $ "' is not a valid item template",, 'UniqueTraits');
		return;
	}

	BackfillItem = BackfillTemplate.CreateInstanceFromTemplate(NewGameState);
	UnitState.AddItemToInventory(BackfillItem, eInvSlot_GrenadePocket, NewGameState);
}

// Nerd's hacking/will scale by rank on top of the fixed amount granted with the trait itself
// (NERD_HACKING_BASE/NERD_WILL_BASE, baked into the ability's own X2Effect_PersistentStatChange).
// Called from X2EventListener_UniqueTraits.OnUnitRankUp for every rank gained AFTER the one
// that granted the trait (rank 1)
static final function ApplyNerdRankScaling(XComGameState_Unit UnitState)
{
	local int NewMaxHacking, NewCurrentHacking, NewMaxWill, NewCurrentWill;

	if (!UnitHasTrait(UnitState, 'UT_Nerd'))
		return;

	NewMaxHacking = UnitState.GetMaxStat(eStat_Hacking) + class'X2Ability_UniqueTraits_Core'.default.NERD_HACKING_PER_RANK;
	NewCurrentHacking = UnitState.GetCurrentStat(eStat_Hacking) + class'X2Ability_UniqueTraits_Core'.default.NERD_HACKING_PER_RANK;
	UnitState.SetBaseMaxStat(eStat_Hacking, NewMaxHacking);
	UnitState.SetCurrentStat(eStat_Hacking, NewCurrentHacking);

	NewMaxWill = UnitState.GetMaxStat(eStat_Will) - class'X2Ability_UniqueTraits_Core'.default.NERD_WILL_PER_RANK;
	NewCurrentWill = UnitState.GetCurrentStat(eStat_Will) - class'X2Ability_UniqueTraits_Core'.default.NERD_WILL_PER_RANK;
	UnitState.SetBaseMaxStat(eStat_Will, NewMaxWill);
	UnitState.SetCurrentStat(eStat_Will, NewCurrentWill);
}

// Born to be chief: queries LWOTC's own public blind-tuple API for this unit's officer rank,
// without ever referencing an LW_Overhaul class.
static final function int GetLWOfficerRank(XComGameState_Unit UnitState)
{
	local XComLWTuple Tuple;

	Tuple = new class'XComLWTuple';
	Tuple.Id = 'GetLWUnitInfo';
	Tuple.Data.Length = 9;
	Tuple.Data[0].kind = XComLWTVBool;		Tuple.Data[0].b = false;
	Tuple.Data[1].kind = XComLWTVInt;		Tuple.Data[1].i = -1;
	Tuple.Data[2].kind = XComLWTVString;	Tuple.Data[2].s = "";
	Tuple.Data[3].kind = XComLWTVString;	Tuple.Data[3].s = "";
	Tuple.Data[4].kind = XComLWTVString;	Tuple.Data[4].s = "";
	Tuple.Data[5].kind = XComLWTVBool;		Tuple.Data[5].b = false;
	Tuple.Data[6].kind = XComLWTVObject;	Tuple.Data[6].o = none;
	Tuple.Data[7].kind = XComLWTVBool;		Tuple.Data[7].b = false;
	Tuple.Data[8].kind = XComLWTVBool;		Tuple.Data[8].b = false;

	`XEVENTMGR.TriggerEvent('GetLWUnitInfo', Tuple, UnitState, none);

	if (!Tuple.Data[0].b || Tuple.Data[1].i < 0)
		return 0;

	return Tuple.Data[1].i;
}

// Applies the delta between this unit's currently-known officer rank (GetLWOfficerRank) and the
// last rank this function applied stats for (tracked via the UT_BornToBeChief_LastOfficerRank
// UnitValue), +/- BORNTOBECHIEF_AIM_DODGE_WILL_PER_RANK per rank of difference, to Aim/Dodge/
// Will. Same precompute-then-Set pattern as ApplyNerdRankScaling (these are setters, not adders
static final function bool ApplyBornToBeChiefRankScaling(XComGameState_Unit MutableUnit)
{
	local UnitValue LastRankValue;
	local int LastRank, CurrentRank, StatDelta;
	local int NewMaxAim, NewCurrentAim, NewMaxDodge, NewCurrentDodge, NewMaxWill, NewCurrentWill;

	if (!UnitHasTrait(MutableUnit, 'UT_BornToBeChief'))
		return false;

	CurrentRank = GetLWOfficerRank(MutableUnit);
	LastRank = 0;
	if (MutableUnit.GetUnitValue('UT_BornToBeChief_LastOfficerRank', LastRankValue))
		LastRank = int(LastRankValue.fValue);

	if (CurrentRank == LastRank)
		return false;

	StatDelta = (CurrentRank - LastRank) * class'X2Ability_UniqueTraits_LWOTC'.default.BORNTOBECHIEF_AIM_DODGE_WILL_PER_RANK;

	NewMaxAim = MutableUnit.GetMaxStat(eStat_Offense) + StatDelta;
	NewCurrentAim = MutableUnit.GetCurrentStat(eStat_Offense) + StatDelta;
	NewMaxDodge = MutableUnit.GetMaxStat(eStat_Dodge) + StatDelta;
	NewCurrentDodge = MutableUnit.GetCurrentStat(eStat_Dodge) + StatDelta;
	NewMaxWill = MutableUnit.GetMaxStat(eStat_Will) + StatDelta;
	NewCurrentWill = MutableUnit.GetCurrentStat(eStat_Will) + StatDelta;

	MutableUnit.SetBaseMaxStat(eStat_Offense, NewMaxAim);
	MutableUnit.SetCurrentStat(eStat_Offense, NewCurrentAim);
	MutableUnit.SetBaseMaxStat(eStat_Dodge, NewMaxDodge);
	MutableUnit.SetCurrentStat(eStat_Dodge, NewCurrentDodge);
	MutableUnit.SetBaseMaxStat(eStat_Will, NewMaxWill);
	MutableUnit.SetCurrentStat(eStat_Will, NewCurrentWill);

	MutableUnit.SetUnitFloatValue('UT_BornToBeChief_LastOfficerRank', CurrentRank, eCleanup_Never);

	`log("UniqueTraits : Born to be chief officer rank scaling applied to" @ MutableUnit.GetFullName() @ "rank" @ LastRank @ "->" @ CurrentRank,, 'UniqueTraits');

	return true;
}
