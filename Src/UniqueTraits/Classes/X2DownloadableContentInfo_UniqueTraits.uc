//---------------------------------------------------------------------------------------
//  FILE:   X2DownloadableContentInfo_UniqueTraits.uc
//  PURPOSE: Mod entry point and the generic trait machinery: the draw (OnPostMission / AssignTraitsToEligibleRookies,
//           run when a rookie earns enough XP/kills to pick a class, i.e. BEFORE the class choice; the covert action
//           path is in X2EventListener_UniqueTraits), the grant/clear of a trait (GrantTraitToUnit / ClearAssignedTrait:
//           AcquiredTraits + AWCAbilities, with the trait's own side effects in its UT_Trait_<Name> class), the
//           "has trait" helpers and the AddUniqueTrait / RemoveUniqueTrait console commands.
//---------------------------------------------------------------------------------------
class X2DownloadableContentInfo_UniqueTraits extends X2DownloadableContentInfo;

// Smoker splices its "doesn't end the turn" cost into the shared ThrowGrenade template; Meat Tenderizer adds a twin of every stun / disorient effect; Shredder copies the acid damage of its reference grenade.
static event OnPostTemplatesCreated()
{
	class'UT_Trait_Smoker'.static.OnPostTemplatesCreated();
	class'UT_Trait_MeatTenderizer'.static.OnPostTemplatesCreated();
	class'UT_Trait_Shredder'.static.OnPostTemplatesCreated();
}

// Dispatches to the unit's own trait (UT_TraitBase.IsItemBlocked): Maniac explosive's primary weapon block, Swordsman's
// pistol block, Support's offensive-item / vest block.
static function bool CanAddItemToInventory_CH_Improved(out int bCanAddItem, const EInventorySlot Slot, const X2ItemTemplate ItemTemplate, int Quantity, XComGameState_Unit UnitState, optional XComGameState CheckGameState, optional out string DisabledReason, optional XComGameState_Item ItemState)
{
	local int TraitIndex;
	local class<UT_TraitBase> TraitClass;

	if (UnitState != none && GetAssignedTraitIndex(UnitState, TraitIndex))
	{
		TraitClass = class'UniqueTraits_TraitConfig'.static.GetTraitClass(class'UniqueTraits_TraitConfig'.default.Traits[TraitIndex].TraitID);
		if (TraitClass != none && TraitClass.static.IsItemBlocked(Slot, ItemTemplate, DisabledReason))
		{
			bCanAddItem = 0;
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

// Called by the game once the tactical -> strategy transfer after a mission is fully committed
// (XComGameStateContext_StrategyGameRule.CompleteStrategyFromTacticalTransfer, CHL #212), before the
// After Action screen: every XP/kill source (vanilla, LWOTC's own mission XP) is already in history.
static event OnPostMission()
{
	local int i;
	local class<UT_TraitBase> TraitClass;

	AssignTraitsToEligibleRookies();

	// Every trait that has something to do once a mission is over (UT_TraitBase.OnPostMission).
	for (i = 0; i < class'UniqueTraits_TraitConfig'.default.Traits.Length; ++i)
	{
		TraitClass = class'UniqueTraits_TraitConfig'.static.GetTraitClass(class'UniqueTraits_TraitConfig'.default.Traits[i].TraitID);
		if (TraitClass != none)
			TraitClass.static.OnPostMission();
	}
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
	local XComGameState_Unit Soldier, MutableUnit;
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

// Grant a trait to a unit.
static final function GrantTraitToUnit(XComGameState_Unit MutableUnit, XComGameState NewGameState, name TraitID)
{
	local name AbilityName;
	local int TraitIndex;
	local class<UT_TraitBase> TraitClass;
	local ClassAgnosticAbility AWCAbility;

	TraitIndex = class'UniqueTraits_TraitConfig'.static.FindTraitIndexByID(TraitID);
	if (TraitIndex == INDEX_NONE)
	{
		`log("UniqueTraits [WARN] : GrantTraitToUnit -- unknown TraitID '" $ TraitID $ "', nothing granted",, 'UniqueTraits');
		return;
	}

	MutableUnit.AcquiredTraits.AddItem(TraitID);

	// The trait's own one-time side effects (stat changes, gear strip, AP...), BEFORE the ability grant below.
	TraitClass = class'UniqueTraits_TraitConfig'.static.GetTraitClass(TraitID);
	if (TraitClass != none)
		TraitClass.static.OnGrant(MutableUnit, NewGameState);

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
		class'UT_Trait_Bribe'.static.SyncBribeSupplyBonus();
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
	local class<UT_TraitBase> TraitClass;
	local bool bClearedAnything;

	if (GetAssignedTraitIndex(MutableUnit, TraitIndex))
	{
		TraitID = class'UniqueTraits_TraitConfig'.default.Traits[TraitIndex].TraitID;

		MutableUnit.AcquiredTraits.RemoveItem(TraitID);

		// Reverses the trait's own one-time side effects (see GrantTraitToUnit).
		TraitClass = class'UniqueTraits_TraitConfig'.static.GetTraitClass(TraitID);
		if (TraitClass != none)
			TraitClass.static.OnClear(MutableUnit);

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
	class'UT_Trait_Bribe'.static.SyncBribeSupplyBonus();
	Armory.PopulateData();

	`log("UniqueTraits : AddUniqueTrait -- force-assigned" @ TraitID @ "to" @ UnitState.GetFullName(),, 'UniqueTraits');
}
