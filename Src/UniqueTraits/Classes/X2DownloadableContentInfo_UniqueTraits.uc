//---------------------------------------------------------------------------------------
//  FILE:   X2DownloadableContentInfo_UniqueTraits.uc
//  PURPOSE: Holds the trait draw (AssignTraitToEligibleRookie, called from
//           X2EventListener_UniqueTraits when a rookie earns enough XP/kills to pick a class,
//           i.e. BEFORE the class choice) and grants each assigned trait's abilities via
//           AWCAbilities
//---------------------------------------------------------------------------------------
class X2DownloadableContentInfo_UniqueTraits extends X2DownloadableContentInfo config(UniqueTraits);

var config bool bLog;
var config int JACKOFALLTRADES_AP_BONUS;
var config name SUPPORT_GRENADEPOCKET_BACKFILL_ITEM_NAME;

var config int FALSEHOPE_AIM_BASE;
var config float FALSEHOPE_HP_BASE;
var config float FALSEHOPE_AIM_PER_RANK;
var config float FALSEHOPE_HP_PER_RANK;
var config float FALSEHOPE_HP_FLOOR;

var localized string ManiacExplosiveNoPrimaryReason;
var localized string SupportNoOffensiveItemReason;
var localized string SwordsmanNoPistolReason;

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

// Used for support trait to prevent using offensive items in utility slots and maniacExplosive for primary weapon and swordsman for pistol.
static function bool CanAddItemToInventory_CH_Improved(out int bCanAddItem, const EInventorySlot Slot, const X2ItemTemplate ItemTemplate, int Quantity, XComGameState_Unit UnitState, optional XComGameState CheckGameState, optional out string DisabledReason, optional XComGameState_Item ItemState)
{
	if (Slot == eInvSlot_PrimaryWeapon && UnitHasTrait(UnitState, 'UT_ManiacExplosive'))
	{
		bCanAddItem = 0;
		DisabledReason = default.ManiacExplosiveNoPrimaryReason;
		return CheckGameState != none;
	}

	if (IsSwordsmanPistolBlockedSlot(Slot, ItemTemplate) && UnitHasTrait(UnitState, 'UT_Swordsman'))
	{
		bCanAddItem = 0;
		DisabledReason = default.SwordsmanNoPistolReason;
		return CheckGameState != none;
	}

	if ((Slot == eInvSlot_Utility || Slot == eInvSlot_GrenadePocket || Slot == eInvSlot_AmmoPocket)
		&& UnitHasTrait(UnitState, 'UT_Support'))
	{
		if (class'X2ItemSlot_UniqueTraits'.static.IsOffensiveWeaponItem(ItemTemplate))
		{
			bCanAddItem = 0;
			DisabledReason = default.SupportNoOffensiveItemReason;
			return CheckGameState != none;
		}
	}

	return CheckGameState == none;
}

// Swordsman's "no pistol": any weapon of category 'pistol' (vanilla and LWOTC pistols alike).
static final function bool IsPistolTemplate(const X2ItemTemplate ItemTemplate)
{
	local X2WeaponTemplate WeaponTemplate;

	WeaponTemplate = X2WeaponTemplate(ItemTemplate);
	return WeaponTemplate != none && WeaponTemplate.WeaponCat == 'pistol';
}

// LWOTC keeps pistols in its own dedicated slot (eInvSlot_Pistol, CHItemSlot_PistolSlot_LW), so Swordsman
// blocks that slot outright; the secondary slot is only blocked for pistol-category weapons.
static final function bool IsSwordsmanPistolBlockedSlot(EInventorySlot Slot, const X2ItemTemplate ItemTemplate)
{
	return Slot == eInvSlot_Pistol || (Slot == eInvSlot_SecondaryWeapon && IsPistolTemplate(ItemTemplate));
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

// Bribe (LWOTC): +BRIBE_SUPPLY_BONUS supplies per month for the region whose haven the holder is
// stationed in as liaison/adviser. Whether/where a unit is a liaison comes from LWOTC's public
// 'GetLWUnitInfo' blind query (Data[5]=is liaison, Data[6]=the XComGameState_WorldRegion).
// LWOTC's own UI shows a haven's income through that region's
// GetSupplyDropReward(), so the bonus is mirrored into the region's POISupplyBonusDelta (a vanilla field
// that feeds GetSupplyDropReward() and which LWOTC never rewrites, unlike BaseSupplyDrop). The real
// month-end payout is handled separately by OnOverrideSupplyDrop, which LWOTC's own listener overwrites
// with its outposts' income (region deltas are NOT part of that payout).
static final function XComGameState_WorldRegion GetLiaisonRegion(XComGameState_Unit UnitState)
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

	if (!Tuple.Data[5].b)
		return none;

	return XComGameState_WorldRegion(Tuple.Data[6].o);
}

// True if a living Bribe holder is currently stationed as a haven liaison (month-end payout gate).
static final function bool AnyBribeHolderIsLiaison()
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
		if (UnitHasTrait(Soldier, 'UT_Bribe') && GetLiaisonRegion(Soldier) != none)
			return true;
	}

	return false;
}

// Brings every region's Bribe bonus in line with reality. Each soldier's applied region is tracked in
// the UT_Bribe_RegionID UnitValue, so this is idempotent and also undoes a bonus whose holder lost the
// trait, died, was dismissed or was taken out of the haven. If ExternalGameState is given (a listener
// already inside a transaction) changes go into it; otherwise a transaction of our own is submitted.
static final function SyncBribeSupplyBonus(optional XComGameState ExternalGameState)
{
	local XComGameStateHistory History;
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Unit> Soldiers;
	local XComGameState_Unit Unit, MutableUnit;
	local XComGameState_WorldRegion Region, MutableRegion;
	local XComGameState NewGameState;
	local UnitValue AppliedValue;
	local array<int> LivingSoldierIDs;
	local int AppliedID, DesiredID, i;

	History = `XCOMHISTORY;
	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return;

	Soldiers = XComHQ.GetSoldiers();
	for (i = 0; i < Soldiers.Length; ++i)
		LivingSoldierIDs.AddItem(Soldiers[i].ObjectID);

	NewGameState = ExternalGameState;

	foreach History.IterateByClassType(class'XComGameState_Unit', Unit)
	{
		if (!Unit.IsSoldier())
			continue;

		AppliedID = 0;
		if (Unit.GetUnitValue('UT_Bribe_RegionID', AppliedValue))
			AppliedID = int(AppliedValue.fValue);

		DesiredID = 0;
		if (LivingSoldierIDs.Find(Unit.ObjectID) != INDEX_NONE && !Unit.IsDead() && UnitHasTrait(Unit, 'UT_Bribe'))
		{
			Region = GetLiaisonRegion(Unit);
			if (Region != none)
				DesiredID = Region.ObjectID;
		}

		if (DesiredID == AppliedID)
			continue;

		if (NewGameState == none)
			NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Bribe supply sync");

		if (AppliedID != 0)
		{
			MutableRegion = XComGameState_WorldRegion(NewGameState.ModifyStateObject(class'XComGameState_WorldRegion', AppliedID));
			MutableRegion.POISupplyBonusDelta -= class'X2EventListener_UniqueTraits'.default.BRIBE_SUPPLY_BONUS;
		}
		if (DesiredID != 0)
		{
			MutableRegion = XComGameState_WorldRegion(NewGameState.ModifyStateObject(class'XComGameState_WorldRegion', DesiredID));
			MutableRegion.POISupplyBonusDelta += class'X2EventListener_UniqueTraits'.default.BRIBE_SUPPLY_BONUS;
		}

		MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Unit.ObjectID));
		MutableUnit.SetUnitFloatValue('UT_Bribe_RegionID', DesiredID, eCleanup_Never);

		`log("UniqueTraits : Bribe supply sync --" @ Unit.GetFullName() @ "region" @ AppliedID @ "->" @ DesiredID,, 'UniqueTraits');
	}

	if (NewGameState != none && ExternalGameState == none)
	{
		if (NewGameState.GetNumGameStateObjects() > 0)
			`GAMERULES.SubmitGameState(NewGameState);
		else
			History.CleanupPendingGameState(NewGameState);
	}
}

// Called by the game once the tactical -> strategy transfer after a mission is fully committed
// (XComGameStateContext_StrategyGameRule.CompleteStrategyFromTacticalTransfer, CHL #212), before the
// After Action screen: every XP/kill source (vanilla, LWOTC's own mission XP) is already in history.
static event OnPostMission()
{
	AssignTraitsToEligibleRookies();
}

// Gives a trait to every living rookie who can now choose a class and has none yet. Called after a
// mission (OnPostMission) and after a covert action ('CovertActionCompleted', OnStateSubmitted), once the
// XP/kills are committed, so the trait is known BEFORE the class choice screen. No before/after diff:
// every eligible rookie gets a trait the moment they become eligible, so an eligible trait-less rookie is
// a fresh one, and reward soldiers (mission/POI/covert action) are created already ranked.
// The grant is its own transaction on purpose: writing it into the still-pending transfer/covert action
// state from an ELD_Immediate listener was logged as succeeding yet was lost (empty AcquiredTraits in the
// Armory afterwards).
static final function AssignTraitsToEligibleRookies()
{
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Unit> Soldiers;
	local XComGameState_Unit Soldier, MutableUnit, CheckUnit;
	local array<int> EligibleIDs;
	local XComGameState NewGameState;
	local int ExistingIndex, i;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return;

	Soldiers = XComHQ.GetSoldiers();
	foreach Soldiers(Soldier)
	{
		if (Soldier.IsSoldier() && Soldier.IsAlive() && !Soldier.bCaptured && Soldier.GetRank() == 0
			&& Soldier.CanRankUpSoldier() && !GetAssignedTraitIndex(Soldier, ExistingIndex))
		{
			EligibleIDs.AddItem(Soldier.ObjectID);
		}
	}

	`log("UniqueTraits : AssignTraitsToEligibleRookies --" @ Soldiers.Length @ "soldier(s) checked," @ EligibleIDs.Length @ "eligible rookie(s) without a trait",, 'UniqueTraits');
	if (EligibleIDs.Length == 0)
		return;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Assign rookie traits");
	for (i = 0; i < EligibleIDs.Length; ++i)
	{
		MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', EligibleIDs[i]));
		AssignTraitToEligibleRookie(MutableUnit, NewGameState);
	}
	`GAMERULES.SubmitGameState(NewGameState);

	// [DIAG] what actually made it into history.
	for (i = 0; i < EligibleIDs.Length; ++i)
	{
		CheckUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(EligibleIDs[i]));
		`log("UniqueTraits [DIAG] : after submit," @ CheckUnit.GetFullName() @ "AcquiredTraits=" $ CheckUnit.AcquiredTraits.Length
			@ "AWCAbilities=" $ CheckUnit.AWCAbilities.Length @ "HasTrait=" $ GetAssignedTraitIndex(CheckUnit, ExistingIndex),, 'UniqueTraits');
	}
}

// Draws and grants a random trait to a rookie who can choose a class. MutableUnit must already be a
// modified object of NewGameState (a pending ChangeContainer state of the caller's own).
static final function AssignTraitToEligibleRookie(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Unit> Soldiers;
	local XComGameState_Unit Soldier, PendingSoldier;
	local array<bool> IndexUsed;
	local array<int> AvailableIndices;
	local int ExistingIndex, i, PickedIndex;
	local name TraitID;
	local XComGameState_Unit UnitState;

	UnitState = MutableUnit;
	`log("UniqueTraits : AssignTraitToEligibleRookie called for" @ UnitState.GetFullName() @ "- pool has" @ class'UniqueTraits_TraitConfig'.default.Traits.Length @ "trait(s) declared",, 'UniqueTraits');

	// Defensive: a rookie should never already carry a trait.
	if (GetAssignedTraitIndex(UnitState, ExistingIndex))
	{
		`log("UniqueTraits [WARN] : AssignTraitToEligibleRookie - " $ UnitState.GetFullName() $ " already has trait index" @ ExistingIndex @ " - skipping",, 'UniqueTraits');
		return;
	}

	IndexUsed.Length = class'UniqueTraits_TraitConfig'.default.Traits.Length;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
	{
		`log("UniqueTraits [WARN] : AssignTraitToEligibleRookie -- no XComGameState_HeadquartersXCom found, aborting",, 'UniqueTraits');
		return;
	}

	Soldiers = XComHQ.GetSoldiers();
	foreach Soldiers(Soldier)
	{
		if (Soldier.ObjectID == UnitState.ObjectID)
			continue;

		// Another rookie granted a trait earlier in this same pending transaction (two rookies
		// becoming eligible after one mission) isn't in history yet.
		PendingSoldier = XComGameState_Unit(NewGameState.GetGameStateForObjectID(Soldier.ObjectID));
		if (PendingSoldier != none)
			Soldier = PendingSoldier;

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

	GrantTraitToUnit(MutableUnit, NewGameState, TraitID);

	`log("UniqueTraits : assigned trait" @ TraitID @ "to" @ UnitState.GetFullName() $ " (ObjectID" $ UnitState.ObjectID $ ")"
		$ " - AcquiredTraits.Length=" $ MutableUnit.AcquiredTraits.Length,, 'UniqueTraits');
}

// Graant a trait to a unit.
static final function GrantTraitToUnit(XComGameState_Unit MutableUnit, XComGameState NewGameState, name TraitID)
{
	local name AbilityName;
	local int TraitIndex;
	local ClassAgnosticAbility AWCAbility;
	local UnitValue ExperienceValue;
	local int NewMaxHacking, NewCurrentHacking, NewMaxWill, NewCurrentWill;
	local int NewMaxAim, NewCurrentAim, NewMaxDodge, NewCurrentDodge;
	local int i;

	if (class'UniqueTraits_TraitConfig'.static.FindTraitIndexByID(TraitID) == INDEX_NONE)
	{
		`log("UniqueTraits [WARN] : GrantTraitToUnit -- unknown TraitID '" $ TraitID $ "', nothing granted",, 'UniqueTraits');
		return;
	}
	TraitIndex = class'UniqueTraits_TraitConfig'.static.FindTraitIndexByID(TraitID);

	MutableUnit.AcquiredTraits.AddItem(TraitID);

	// Jack of all trades' AP bonus is a one-time grant at assignment time, not a persistent
	// effect (the ability itself carries no gameplay effect for this part).
	if (TraitID == 'UT_JackOfAllTrades')
		MutableUnit.AbilityPoints += default.JACKOFALLTRADES_AP_BONUS;

	// Maniac explosive's primary weapon block (CanAddItemToInventory_CH_Improved below) only
	// stops FUTURE attempts to equip one => the rookie's already-equipped starting weapon
	// needs to be stripped back to HQ inventory explicitly here.
	// Same for support utility slots
	if (TraitID == 'UT_ManiacExplosive')
		RemoveManiacPrimaryWeapon(MutableUnit, NewGameState);

	if (TraitID == 'UT_Support')
		RemoveSupportOffensiveItems(MutableUnit, NewGameState);

	if (TraitID == 'UT_Swordsman')
		RemoveSwordsmanPistol(MutableUnit, NewGameState);

	// False Hope's fixed +12 Aim/+3 HP: permanent direct mutation, same reasoning as Nerd below
	// (the per-rank decay is ApplyFalseHopeRankScaling).
	if (TraitID == 'UT_FalseHope')
	{
		ShiftFalseHopeStats(MutableUnit, default.FALSEHOPE_AIM_BASE, default.FALSEHOPE_HP_BASE);
		MutableUnit.SetUnitFloatValue('UT_FalseHope_RanksScaled', 0, eCleanup_Never);

		// Baseline for the LWOTC part of the XP malus (OnDistributeTacticalGameEndXp_FalseHopeXp): the
		// mission experience the soldier already has is NOT reduced, only what is added from now on.
		ExperienceValue.fValue = 0;
		MutableUnit.GetUnitValue('MissionExperience', ExperienceValue);
		MutableUnit.SetUnitFloatValue('UT_FalseHope_MissionXpSeen', ExperienceValue.fValue, eCleanup_Never);

		// A natural promotion grants the trait at rank 1 (nothing to catch up); AddUniqueTrait on an
		// already-ranked soldier must apply every rank gained since, as if it had held the trait from rank 1.
		for (i = 1; i < MutableUnit.GetRank(); ++i)
			ApplyFalseHopeRankScaling(MutableUnit);
	}

	// Nerd's fixed +10 Hacking/-5 Will: a genuine, permanent stat mutation (not an ability
	// effect => see the Nerd() ability comment) so it actually lowers Max Will in the strategy
	// layer, not just while deployed. Same precompute-then-Set pattern as ApplyNerdRankScaling.
	if (TraitID == 'UT_Nerd')
	{
		NewMaxHacking = MutableUnit.GetMaxStat(eStat_Hacking) + class'X2Ability_UniqueTraits_Core'.default.NERD_HACKING_BASE;
		NewCurrentHacking = MutableUnit.GetCurrentStat(eStat_Hacking) + class'X2Ability_UniqueTraits_Core'.default.NERD_HACKING_BASE;
		MutableUnit.SetBaseMaxStat(eStat_Hacking, NewMaxHacking);
		MutableUnit.SetCurrentStat(eStat_Hacking, NewCurrentHacking);

		NewMaxWill = MutableUnit.GetMaxStat(eStat_Will) - class'X2Ability_UniqueTraits_Core'.default.NERD_WILL_BASE;
		NewCurrentWill = MutableUnit.GetCurrentStat(eStat_Will) - class'X2Ability_UniqueTraits_Core'.default.NERD_WILL_BASE;
		MutableUnit.SetBaseMaxStat(eStat_Will, NewMaxWill);
		MutableUnit.SetCurrentStat(eStat_Will, NewCurrentWill);

		// Reset ApplyNerdRankScaling's cumulative counter (see that function) in case this unit
		// had Nerd before, was cleared, and is now getting it again => ClearAssignedTrait already
		// resets this to 0 on clear, this is just defensive.
		MutableUnit.SetUnitFloatValue('UT_Nerd_RanksScaled', 0, eCleanup_Never);

		// Same catch-up as False Hope: AddUniqueTrait on an already-ranked soldier must apply every
		// rank gained since rank 1 (a natural promotion grants at rank 1, nothing to catch up).
		for (i = 1; i < MutableUnit.GetRank(); ++i)
			ApplyNerdRankScaling(MutableUnit);
	}

	// Born to be chief's fixed -12 Aim/Dodge/Will: same reasoning as Nerd above => a genuine,
	// permanent mutation instead of an ability effect. The dynamic +4/officer-rank part stays in
	// ApplyBornToBeChiefRankScaling, applied separately (see 'UnitRankUp'/'PreEndOfMonth'/
	// 'UIPersonnel_OnSortFinished' listeners).
	if (TraitID == 'UT_BornToBeChief')
	{
		NewMaxAim = MutableUnit.GetMaxStat(eStat_Offense) - class'X2Ability_UniqueTraits_LWOTC'.default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE;
		NewCurrentAim = MutableUnit.GetCurrentStat(eStat_Offense) - class'X2Ability_UniqueTraits_LWOTC'.default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE;
		MutableUnit.SetBaseMaxStat(eStat_Offense, NewMaxAim);
		MutableUnit.SetCurrentStat(eStat_Offense, NewCurrentAim);

		NewMaxDodge = MutableUnit.GetMaxStat(eStat_Dodge) - class'X2Ability_UniqueTraits_LWOTC'.default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE;
		NewCurrentDodge = MutableUnit.GetCurrentStat(eStat_Dodge) - class'X2Ability_UniqueTraits_LWOTC'.default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE;
		MutableUnit.SetBaseMaxStat(eStat_Dodge, NewMaxDodge);
		MutableUnit.SetCurrentStat(eStat_Dodge, NewCurrentDodge);

		NewMaxWill = MutableUnit.GetMaxStat(eStat_Will) - class'X2Ability_UniqueTraits_LWOTC'.default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE;
		NewCurrentWill = MutableUnit.GetCurrentStat(eStat_Will) - class'X2Ability_UniqueTraits_LWOTC'.default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE;
		MutableUnit.SetBaseMaxStat(eStat_Will, NewMaxWill);
		MutableUnit.SetCurrentStat(eStat_Will, NewCurrentWill);

		// Reset ApplyBornToBeChiefRankScaling's tracking UnitValue (see that function) in case
		// this unit had the trait before, was cleared, and is now getting it again =>
		// ClearAssignedTrait already resets this to 0 on clear, this is just defensive.
		MutableUnit.SetUnitFloatValue('UT_BornToBeChief_LastOfficerRank', 0, eCleanup_Never);

		// An already-officer soldier (AddUniqueTrait) gets its +4/officer-rank right away instead of
		// waiting for the next mission start/month end/personnel sort sync. No-op for officer rank 0.
		ApplyBornToBeChiefRankScaling(MutableUnit);
	}

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
		SyncBribeSupplyBonus();
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
	local int NewMaxHacking, NewCurrentHacking, NewMaxWill, NewCurrentWill;
	local int NewMaxAim, NewCurrentAim, NewMaxDodge, NewCurrentDodge;
	local UnitValue RanksScaledValue, LastOfficerRankValue;
	local int RanksScaled, LastOfficerRank, ScalingDelta;

	if (GetAssignedTraitIndex(MutableUnit, TraitIndex))
	{
		TraitID = class'UniqueTraits_TraitConfig'.default.Traits[TraitIndex].TraitID;

		MutableUnit.AcquiredTraits.RemoveItem(TraitID);

		if (TraitID == 'UT_JackOfAllTrades')
			MutableUnit.AbilityPoints -= default.JACKOFALLTRADES_AP_BONUS;

		// Reverse False Hope's permanent mutation: base part plus the per-rank decay applied so far.
		if (TraitID == 'UT_FalseHope')
		{
			RanksScaled = 0;
			if (MutableUnit.GetUnitValue('UT_FalseHope_RanksScaled', RanksScaledValue))
				RanksScaled = int(RanksScaledValue.fValue);

			ShiftFalseHopeStats(MutableUnit,
				-(default.FALSEHOPE_AIM_BASE - RanksScaled * default.FALSEHOPE_AIM_PER_RANK),
				-GetFalseHopeHPDelta(RanksScaled));
			MutableUnit.SetUnitFloatValue('UT_FalseHope_RanksScaled', 0, eCleanup_Never);
			MutableUnit.SetUnitFloatValue('UT_FalseHope_MissionXpSeen', 0, eCleanup_Never);
		}

		// Reverse Nerd's fixed +10 Hacking/-5 Will permanent mutation (see GrantTraitToUnit).
		if (TraitID == 'UT_Nerd')
		{
			NewMaxHacking = MutableUnit.GetMaxStat(eStat_Hacking) - class'X2Ability_UniqueTraits_Core'.default.NERD_HACKING_BASE;
			NewCurrentHacking = MutableUnit.GetCurrentStat(eStat_Hacking) - class'X2Ability_UniqueTraits_Core'.default.NERD_HACKING_BASE;
			MutableUnit.SetBaseMaxStat(eStat_Hacking, NewMaxHacking);
			MutableUnit.SetCurrentStat(eStat_Hacking, NewCurrentHacking);

			NewMaxWill = MutableUnit.GetMaxStat(eStat_Will) + class'X2Ability_UniqueTraits_Core'.default.NERD_WILL_BASE;
			NewCurrentWill = MutableUnit.GetCurrentStat(eStat_Will) + class'X2Ability_UniqueTraits_Core'.default.NERD_WILL_BASE;
			MutableUnit.SetBaseMaxStat(eStat_Will, NewMaxWill);
			MutableUnit.SetCurrentStat(eStat_Will, NewCurrentWill);

			// Reverse ApplyNerdRankScaling's cumulative per-rank total (2026-09-30). RanksScaled
			// (incremented once per call in that function) is the exact count of +HACKING_PER_RANK/
			// -WILL_PER_RANK increments applied since assignment -- multiply back out and undo in
			// one shot, then reset the counter so a future re-grant starts clean.
			RanksScaled = 0;
			if (MutableUnit.GetUnitValue('UT_Nerd_RanksScaled', RanksScaledValue))
				RanksScaled = int(RanksScaledValue.fValue);

			if (RanksScaled > 0)
			{
				NewMaxHacking = MutableUnit.GetMaxStat(eStat_Hacking) - (RanksScaled * class'X2Ability_UniqueTraits_Core'.default.NERD_HACKING_PER_RANK);
				NewCurrentHacking = MutableUnit.GetCurrentStat(eStat_Hacking) - (RanksScaled * class'X2Ability_UniqueTraits_Core'.default.NERD_HACKING_PER_RANK);
				MutableUnit.SetBaseMaxStat(eStat_Hacking, NewMaxHacking);
				MutableUnit.SetCurrentStat(eStat_Hacking, NewCurrentHacking);

				NewMaxWill = MutableUnit.GetMaxStat(eStat_Will) + (RanksScaled * class'X2Ability_UniqueTraits_Core'.default.NERD_WILL_PER_RANK);
				NewCurrentWill = MutableUnit.GetCurrentStat(eStat_Will) + (RanksScaled * class'X2Ability_UniqueTraits_Core'.default.NERD_WILL_PER_RANK);
				MutableUnit.SetBaseMaxStat(eStat_Will, NewMaxWill);
				MutableUnit.SetCurrentStat(eStat_Will, NewCurrentWill);
			}
			MutableUnit.SetUnitFloatValue('UT_Nerd_RanksScaled', 0, eCleanup_Never);
		}

		// Reverse Born to be chief's fixed -12 Aim/Dodge/Will permanent mutation (see
		// GrantTraitToUnit).
		if (TraitID == 'UT_BornToBeChief')
		{
			NewMaxAim = MutableUnit.GetMaxStat(eStat_Offense) + class'X2Ability_UniqueTraits_LWOTC'.default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE;
			NewCurrentAim = MutableUnit.GetCurrentStat(eStat_Offense) + class'X2Ability_UniqueTraits_LWOTC'.default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE;
			MutableUnit.SetBaseMaxStat(eStat_Offense, NewMaxAim);
			MutableUnit.SetCurrentStat(eStat_Offense, NewCurrentAim);

			NewMaxDodge = MutableUnit.GetMaxStat(eStat_Dodge) + class'X2Ability_UniqueTraits_LWOTC'.default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE;
			NewCurrentDodge = MutableUnit.GetCurrentStat(eStat_Dodge) + class'X2Ability_UniqueTraits_LWOTC'.default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE;
			MutableUnit.SetBaseMaxStat(eStat_Dodge, NewMaxDodge);
			MutableUnit.SetCurrentStat(eStat_Dodge, NewCurrentDodge);

			NewMaxWill = MutableUnit.GetMaxStat(eStat_Will) + class'X2Ability_UniqueTraits_LWOTC'.default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE;
			NewCurrentWill = MutableUnit.GetCurrentStat(eStat_Will) + class'X2Ability_UniqueTraits_LWOTC'.default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE;
			MutableUnit.SetBaseMaxStat(eStat_Will, NewMaxWill);
			MutableUnit.SetCurrentStat(eStat_Will, NewCurrentWill);

			// Reverse ApplyBornToBeChiefRankScaling's cumulative +4/officer-rank total.
			// That function tracks UT_BornToBeChief_LastOfficerRank as the officer
			// rank it last synced stats for, always starting its own diff from a baseline of 0
			// (LastRank defaults to 0 when unset) => so the tracked value IS the total number of
			// "ranks" worth of delta accumulated so far; multiply back out and undo in one shot.
			LastOfficerRank = 0;
			if (MutableUnit.GetUnitValue('UT_BornToBeChief_LastOfficerRank', LastOfficerRankValue))
				LastOfficerRank = int(LastOfficerRankValue.fValue);

			if (LastOfficerRank > 0)
			{
				ScalingDelta = LastOfficerRank * class'X2Ability_UniqueTraits_LWOTC'.default.BORNTOBECHIEF_AIM_DODGE_WILL_PER_RANK;

				NewMaxAim = MutableUnit.GetMaxStat(eStat_Offense) - ScalingDelta;
				NewCurrentAim = MutableUnit.GetCurrentStat(eStat_Offense) - ScalingDelta;
				MutableUnit.SetBaseMaxStat(eStat_Offense, NewMaxAim);
				MutableUnit.SetCurrentStat(eStat_Offense, NewCurrentAim);

				NewMaxDodge = MutableUnit.GetMaxStat(eStat_Dodge) - ScalingDelta;
				NewCurrentDodge = MutableUnit.GetCurrentStat(eStat_Dodge) - ScalingDelta;
				MutableUnit.SetBaseMaxStat(eStat_Dodge, NewMaxDodge);
				MutableUnit.SetCurrentStat(eStat_Dodge, NewCurrentDodge);

				NewMaxWill = MutableUnit.GetMaxStat(eStat_Will) - ScalingDelta;
				NewCurrentWill = MutableUnit.GetCurrentStat(eStat_Will) - ScalingDelta;
				MutableUnit.SetBaseMaxStat(eStat_Will, NewMaxWill);
				MutableUnit.SetCurrentStat(eStat_Will, NewCurrentWill);
			}
			MutableUnit.SetUnitFloatValue('UT_BornToBeChief_LastOfficerRank', 0, eCleanup_Never);
		}

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
	SyncBribeSupplyBonus();
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

// Support's offensive-item block (CanAddItemToInventory_CH_Improved above) only stops FUTURE equip attempts.
static final function RemoveSupportOffensiveItems(XComGameState_Unit UnitState, XComGameState NewGameState)
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

	BackfillSupportGrenadePocket(UnitState, NewGameState);
}

// Vanilla's own Grenade Pocket always wants at least one grenade equipped (CHItemSlot.
// SlotGetMinimumEquipped defaults every vanilla eInvSlot_GrenadePocket to MinimumEquipped = 1)
// Backfilling with a real, persistent Smoke Grenade here (same CreateInstanceFromTemplate +
// AddItemToInventory pattern GrenadePocketPurchased itself uses) keeps the slot non-empty so that
// auto-refill path never triggers at all.
static final function BackfillSupportGrenadePocket(XComGameState_Unit UnitState, XComGameState NewGameState)
{
	local X2ItemTemplate BackfillTemplate;
	local XComGameState_Item BackfillItem;
	local name BackfillItemName;

	if (!UnitState.HasGrenadePocket())
		return;

	if (UnitState.GetItemInSlot(eInvSlot_GrenadePocket, NewGameState) != none)
		return;

	BackfillItemName = default.SUPPORT_GRENADEPOCKET_BACKFILL_ITEM_NAME;
	if (BackfillItemName == '')
		BackfillItemName = 'SmokeGrenade';

	BackfillTemplate = class'X2ItemTemplateManager'.static.GetItemTemplateManager().FindItemTemplate(BackfillItemName);
	if (BackfillTemplate == none)
	{
		`log("UniqueTraits [WARN] : BackfillSupportGrenadePocket -- backfill item '" $ BackfillItemName $ "' is not a valid item template",, 'UniqueTraits');
		return;
	}

	BackfillItem = BackfillTemplate.CreateInstanceFromTemplate(NewGameState);
	UnitState.AddItemToInventory(BackfillItem, eInvSlot_GrenadePocket, NewGameState);
}

// Swordsman's pistol block (CanAddItemToInventory_CH_Improved above) only stops FUTURE equips.
static final function RemoveSwordsmanPistol(XComGameState_Unit UnitState, XComGameState NewGameState)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_Item PistolItem;
	local array<EInventorySlot> PistolSlots;
	local EInventorySlot PistolSlot;

	PistolSlots.AddItem(eInvSlot_Pistol);
	PistolSlots.AddItem(eInvSlot_SecondaryWeapon);

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	foreach PistolSlots(PistolSlot)
	{
		PistolItem = UnitState.GetItemInSlot(PistolSlot, NewGameState);
		if (PistolItem == none || !IsSwordsmanPistolBlockedSlot(PistolSlot, PistolItem.GetMyTemplate()))
			continue;

		PistolItem = XComGameState_Item(NewGameState.ModifyStateObject(class'XComGameState_Item', PistolItem.ObjectID));
		if (UnitState.RemoveItemFromInventory(PistolItem, NewGameState) && XComHQ != none)
			XComHQ.PutItemInInventory(NewGameState, PistolItem);
	}
}

// False Hope's total HP delta after N ranks gained since assignment: starts at FALSEHOPE_HP_BASE,
// loses FALSEHOPE_HP_PER_RANK per rank, never goes below FALSEHOPE_HP_FLOOR (0: the decay only
// cancels the +3 bonus, it never turns it into an HP malus).
static final function float GetFalseHopeHPDelta(int RanksScaled)
{
	return FMax(default.FALSEHOPE_HP_BASE - RanksScaled * default.FALSEHOPE_HP_PER_RANK, default.FALSEHOPE_HP_FLOOR);
}

// Adds (or, with negative values, removes) False Hope's aim/HP on both max and current stat.
// Capture both Get*Stat before calling SetBaseMaxStat (it resyncs the current stat as a side effect).
static final function ShiftFalseHopeStats(XComGameState_Unit UnitState, float AimDelta, float HPDelta)
{
	local float NewMaxAim, NewCurrentAim, NewMaxHP, NewCurrentHP;

	NewMaxAim = UnitState.GetMaxStat(eStat_Offense) + AimDelta;
	NewCurrentAim = UnitState.GetCurrentStat(eStat_Offense) + AimDelta;
	NewMaxHP = UnitState.GetMaxStat(eStat_HP) + HPDelta;
	NewCurrentHP = UnitState.GetCurrentStat(eStat_HP) + HPDelta;

	UnitState.SetBaseMaxStat(eStat_Offense, NewMaxAim);
	UnitState.SetCurrentStat(eStat_Offense, NewCurrentAim);
	UnitState.SetBaseMaxStat(eStat_HP, NewMaxHP);
	UnitState.SetCurrentStat(eStat_HP, FMax(NewCurrentHP, 1));
}

// Called from 'UnitRankUp' for every rank gained after the one that granted the trait.
static final function ApplyFalseHopeRankScaling(XComGameState_Unit UnitState)
{
	local UnitValue RanksScaledValue;
	local int RanksScaled;

	if (!UnitHasTrait(UnitState, 'UT_FalseHope'))
		return;

	RanksScaled = 0;
	if (UnitState.GetUnitValue('UT_FalseHope_RanksScaled', RanksScaledValue))
		RanksScaled = int(RanksScaledValue.fValue);

	ShiftFalseHopeStats(UnitState, -default.FALSEHOPE_AIM_PER_RANK,
		GetFalseHopeHPDelta(RanksScaled + 1) - GetFalseHopeHPDelta(RanksScaled));
	UnitState.SetUnitFloatValue('UT_FalseHope_RanksScaled', RanksScaled + 1, eCleanup_Never);
}

// Nerd's hacking/will scale by rank on top of the fixed amount granted with the trait itself
// (NERD_HACKING_BASE/NERD_WILL_BASE, applied once in GrantTraitToUnit). Called from
// X2EventListener_UniqueTraits.OnUnitRankUp for every rank gained AFTER the one that granted the
// trait (rank 1). Unlike ApplyBornToBeChiefRankScaling, this has no external "current rank" to
// diff against each call (military rank-ups fire 'UnitRankUp' exactly once per rank gained, no
// polling), so it just adds the flat per-rank delta every time it's called.
// The UT_Nerd_RanksScaled counter below exists purely so ClearAssignedTrait can reverse the exact
// cumulative total later, since this function itself has no need to know the running
// total to apply the next increment correctly.
static final function ApplyNerdRankScaling(XComGameState_Unit UnitState)
{
	local int NewMaxHacking, NewCurrentHacking, NewMaxWill, NewCurrentWill;
	local UnitValue RanksScaledValue;
	local int RanksScaled;

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

	RanksScaled = 0;
	if (UnitState.GetUnitValue('UT_Nerd_RanksScaled', RanksScaledValue))
		RanksScaled = int(RanksScaledValue.fValue);
	UnitState.SetUnitFloatValue('UT_Nerd_RanksScaled', RanksScaled + 1, eCleanup_Never);
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
