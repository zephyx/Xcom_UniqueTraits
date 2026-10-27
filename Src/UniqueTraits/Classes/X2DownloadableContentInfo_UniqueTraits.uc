//---------------------------------------------------------------------------------------
//  FILE:   X2DownloadableContentInfo_UniqueTraits.uc
//  PURPOSE: Mod entry point and the generic trait machinery: the draw (OnPostMission / AssignTraitsToEligibleRookies,
//           run when a rookie earns enough XP/kills to pick a class, i.e. BEFORE the class choice; the covert action
//           path is in X2EventListener_UniqueTraits), the grant/clear of a trait (GrantTraitToUnit / ClearAssignedTrait:
//           AcquiredTraits + AWCAbilities, with the trait's own side effects in its UT_Trait_<Name> class), the
//           "has trait" helpers and the AddUniqueTrait / RemoveUniqueTrait console commands.
//---------------------------------------------------------------------------------------
class X2DownloadableContentInfo_UniqueTraits extends X2DownloadableContentInfo;

// With ASSIGN_TRAIT_AT_RECRUITMENT: the rookies already in the roster of a loaded save (also those of a game started before the option was turned on).
// Does nothing otherwise: the normal draw happens after a mission / covert action.
static event OnLoadedSavedGameToStrategy()
{
	if (class'UniqueTraits_TraitConfig'.static.ShouldAssignAtRecruitment())
		AssignTraitsToEligibleRookies();
}

// CHL #419, called by X2AbilityTag.ExpandHandler for a tag the base game did not handle: our tags are written <Ability:UT_...> (the quick exit keeps the cost of the other
// mods' tags to one comparison); the traits of the pool are asked in turn (UT_TraitBase.ExpandAbilityTag).
static function bool AbilityTagExpandHandler_CH(string InString, out string OutString, Object ParseObj, Object StrategyParseOb, XComGameState GameState)
{
	local int i;
	local class<UT_TraitBase> TraitClass;

	if (!(Left(InString, 3) ~= "UT_"))
		return false;

	for (i = 0; i < class'UniqueTraits_TraitConfig'.default.Traits.Length; ++i)
	{
		TraitClass = class'UniqueTraits_TraitConfig'.static.GetActiveTraitClass(i);
		if (TraitClass != none && TraitClass.static.ExpandAbilityTag(InString, OutString, ParseObj, StrategyParseOb, GameState))
			return true;
	}

	return false;
}

// CHL #412: before any X2DataSet is built. The values the player changed in the Mod Config Menu (Advanced page) are written into the trait classes' defaults here, so that
// even the ones baked into the ability templates are his (UniqueTraits_MCMOptions.ApplyOverrides). Without Mod Config Menu there is none and nothing changes.
static function OnPreCreateTemplates()
{
	class'UniqueTraits_MCMOptions'.static.ApplyOverrides();
}

// AI hazard fix (UT_AIHazardFix, ini option AI_HAZARD_FIX_ENABLED): an exposed enemy boxed in by a poison / fire / acid cloud may go to cover through it instead of staying in the open.
// The behavior trees are edited at the start of a mission (new or loaded into tactical), after LWOTC, if present, edited its own at the main menu.
static event OnPreMission(XComGameState StartGameState, XComGameState_MissionSite MissionState)
{
	class'UT_AIHazardFix'.static.Apply();
}

static event OnLoadedSavedGameToTactical()
{
	class'UT_AIHazardFix'.static.Apply();
}

// Every trait of the pool that is not disabled gets to patch the templates it does not own (UT_TraitBase.OnPostTemplatesCreated). A trait taken out of the ini pool
// is no longer patched in. The abilities of a DISABLED trait are made inert (MakeTraitInert): a soldier who still carries it is not affected.
static event OnPostTemplatesCreated()
{
	local int i;
	local class<UT_TraitBase> TraitClass;
	local array<name> Done;
	local name AbilityName;

	// The {VARIABLE} placeholders of the ability texts become the current values (ini or Mod Config Menu); UT_TextTags.PatchTemplates runs again when the Advanced page is saved.
	class'UT_TextTags'.static.PatchTemplates();

	// AI hazard fix (UT_AIHazardFix): the behavior class of the enemies, for the hazard cover move (nothing happens when the option is off).
	class'UT_AIHazardFix'.static.UseHazardBehaviorClass();

	for (i = 0; i < class'UniqueTraits_TraitConfig'.default.Traits.Length; ++i)
	{
		if (class'UniqueTraits_TraitConfig'.static.IsTraitDisabled(i))
		{
			`log("UniqueTraits : trait" @ class'UniqueTraits_TraitConfig'.default.Traits[i].TraitID @ "is DISABLED: not drawn, no event registered, no template patched, abilities made inert",, 'UniqueTraits');
			foreach class'UniqueTraits_TraitConfig'.default.Traits[i].GrantedAbilities(AbilityName)
				MakeAbilityInert(AbilityName, Done);

			continue;
		}

		TraitClass = class'UniqueTraits_TraitConfig'.static.GetTraitClass(class'UniqueTraits_TraitConfig'.default.Traits[i].TraitID);
		if (TraitClass != none)
			TraitClass.static.OnPostTemplatesCreated();
	}
}

// A disabled trait's own ability (this mod's "UT_" ones only: a base game ability that the trait grants is shared with the classes and is left alone) loses its effects and
// gets a shooter condition that always fails; the abilities it adds (AdditionalAbilities, the hidden helpers) too. Every difficulty variant.
static final function MakeAbilityInert(name AbilityName, out array<name> Done)
{
	local X2AbilityTemplateManager AbilityManager;
	local array<X2AbilityTemplate> Templates;
	local X2AbilityTemplate Template;
	local array<name> SubAbilities;
	local name SubAbility;

	if (!(Left(string(AbilityName), 3) ~= "UT_") || Done.Find(AbilityName) != INDEX_NONE)
		return;

	Done.AddItem(AbilityName);

	AbilityManager = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();
	AbilityManager.FindAbilityTemplateAllDifficulties(AbilityName, Templates);
	foreach Templates(Template)
	{
		Template.AbilityShooterEffects.Length = 0;
		Template.AbilityTargetEffects.Length = 0;
		Template.AbilityMultiTargetEffects.Length = 0;
		Template.AbilityShooterConditions.AddItem(new class'X2Condition_UT_TraitDisabled');

		foreach Template.AdditionalAbilities(SubAbility)
			SubAbilities.AddItem(SubAbility);
	}

	foreach SubAbilities(SubAbility)
		MakeAbilityInert(SubAbility, Done);
}

// Dispatches to the unit's own trait (UT_TraitBase.IsItemBlocked): Maniac explosive's primary weapon block, Swordsman's
// pistol block, Support's offensive-item / vest block.
static function bool CanAddItemToInventory_CH_Improved(out int bCanAddItem, const EInventorySlot Slot, const X2ItemTemplate ItemTemplate, int Quantity, XComGameState_Unit UnitState, optional XComGameState CheckGameState, optional out string DisabledReason, optional XComGameState_Item ItemState)
{
	local int TraitIndex;
	local class<UT_TraitBase> TraitClass;

	if (UnitState != none && GetAssignedTraitIndex(UnitState, TraitIndex))
	{
		TraitClass = class'UniqueTraits_TraitConfig'.static.GetActiveTraitClass(TraitIndex);
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
		TraitClass = class'UniqueTraits_TraitConfig'.static.GetActiveTraitClass(i);
		if (TraitClass != none)
			TraitClass.static.OnPostMission();
	}
}

// True for a rookie who gets a trait now: one who can choose a class (the default, the trait is known before the class choice screen) or, with
// ASSIGN_TRAIT_AT_RECRUITMENT, any rookie of the roster (not a Resistance hero).
static final function bool IsRookieEligibleForTrait(XComGameState_Unit Soldier)
{
	return Soldier.CanRankUpSoldier() || (class'UniqueTraits_TraitConfig'.static.ShouldAssignAtRecruitment() && !Soldier.IsResistanceHero());
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
			&& IsRookieEligibleForTrait(Soldier) && !GetAssignedTraitIndex(Soldier, ExistingIndex))
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
	local array<int> AvailableIndices, Weights;
	local int ExistingIndex, i, PickedIndex, TotalWeight, Roll;
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

		if (!class'UniqueTraits_TraitConfig'.static.GetTraitClass(class'UniqueTraits_TraitConfig'.default.Traits[i].TraitID).static.IsEligibleForUnit(UnitState))
			continue;

		AvailableIndices.AddItem(i);
		Weights.AddItem(class'UniqueTraits_TraitConfig'.static.GetTraitProbability(i));
		TotalWeight += Weights[Weights.Length - 1];
	}

	if (AvailableIndices.Length == 0 || TotalWeight <= 0)
	{
		`log("UniqueTraits [WARN] : trait pool exhausted, no trait assigned to" @ UnitState.GetFullName(),, 'UniqueTraits');
		return;
	}

	// Weighted draw: each available trait covers a stretch of the roll as long as its probability.
	`log("UniqueTraits : draw --" @ AvailableIndices.Length @ "available trait(s), total weight" @ TotalWeight @ "(default weight" @ class'UniqueTraits_TraitConfig'.static.GetDefaultTraitProbability() $ ")",, 'UniqueTraits');
	Roll = `SYNC_RAND_STATIC(TotalWeight);
	PickedIndex = AvailableIndices[AvailableIndices.Length - 1];
	for (i = 0; i < AvailableIndices.Length; ++i)
	{
		Roll -= Weights[i];
		if (Roll < 0)
		{
			PickedIndex = AvailableIndices[i];
			break;
		}
	}
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

// ---- Changing the trait of an EXISTING unit: the two entry points below are the ONLY way to do it outside the draw. Each one is a complete
// transaction (a change container of its own, submitted), so every caller gets the same result: the RemoveUniqueTrait / AddUniqueTrait console
// commands and the MEC conversion (UT_MecConversion). Whatever a trait has to do outside the unit (Bribe's region bonus) is done by its own
// OnGrant / OnClear inside that transaction. The draw of a rookie (AssignTraitsToEligibleRookies) batches several rookies in ONE transaction and
// so calls GrantTraitToUnit itself.

// Takes the trait (ClearAssignedTrait: OnClear, AcquiredTraits, AWCAbilities) off the unit. False if the unit had none.
static final function bool RemoveUnitTrait(StateObjectReference UnitRef, string Reason)
{
	return ChangeUnitTrait(UnitRef, '', Reason);
}

// Gives the unit the trait TraitID, replacing the one it has (if any). False if TraitID is unknown or the unit cannot be modified.
static final function bool SetUnitTrait(StateObjectReference UnitRef, name TraitID, string Reason)
{
	local class<UT_TraitBase> TraitClass;
	local XComGameState_Unit Unit;

	if (class'UniqueTraits_TraitConfig'.static.FindTraitIndexByID(TraitID) == INDEX_NONE)
	{
		`log("UniqueTraits [WARN] : SetUnitTrait -- unknown TraitID '" $ TraitID $ "', nothing changed",, 'UniqueTraits');
		return false;
	}

	if (class'UniqueTraits_TraitConfig'.static.IsTraitDisabled(class'UniqueTraits_TraitConfig'.static.FindTraitIndexByID(TraitID)))
	{
		`log("UniqueTraits [WARN] : SetUnitTrait -- trait" @ TraitID @ "is disabled (Mod Config Menu or bDisabled in the ini), nothing changed",, 'UniqueTraits');
		return false;
	}

	TraitClass = class'UniqueTraits_TraitConfig'.static.GetTraitClass(TraitID);
	Unit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(UnitRef.ObjectID));
	if (TraitClass != none && Unit != none && !TraitClass.static.IsEligibleForUnit(Unit))
	{
		`log("UniqueTraits [WARN] : SetUnitTrait -- trait" @ TraitID @ "cannot be given to" @ Unit.GetFullName() @ "(not eligible for this unit), nothing changed",, 'UniqueTraits');
		return false;
	}

	return ChangeUnitTrait(UnitRef, TraitID, Reason);
}

// NewTraitID = '' only removes.
static final function bool ChangeUnitTrait(StateObjectReference UnitRef, name NewTraitID, string Reason)
{
	local XComGameState NewGameState;
	local XComGameState_Unit MutableUnit;
	local bool bChanged;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: " $ Reason);
	MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', UnitRef.ObjectID));
	if (MutableUnit == none)
	{
		`XCOMHISTORY.CleanupPendingGameState(NewGameState);
		return false;
	}

	bChanged = ClearAssignedTrait(MutableUnit, NewGameState);
	if (NewTraitID != '')
	{
		GrantTraitToUnit(MutableUnit, NewGameState, NewTraitID);
		bChanged = true;
	}

	if (!bChanged)
	{
		`XCOMHISTORY.CleanupPendingGameState(NewGameState);
		return false;
	}

	`GAMERULES.SubmitGameState(NewGameState);

	return true;
}

// Console command: removes the trait of the soldier shown in the Armory.
exec function RemoveUniqueTrait()
{
	local UIArmory Armory;
	local XComGameState_Unit UnitState;

	Armory = UIArmory(`SCREENSTACK.GetFirstInstanceOf(class'UIArmory'));
	if (Armory == none)
	{
		`log("UniqueTraits : RemoveUniqueTrait -- no Armory screen open, select a soldier first",, 'UniqueTraits');
		return;
	}

	UnitState = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(Armory.GetUnitRef().ObjectID));
	if (UnitState == none)
	{
		`log("UniqueTraits : RemoveUniqueTrait -- no unit selected",, 'UniqueTraits');
		return;
	}

	if (RemoveUnitTrait(UnitState.GetReference(), "RemoveUniqueTrait"))
	{
		Armory.PopulateData();
		`log("UniqueTraits : RemoveUniqueTrait -- cleared trait from" @ UnitState.GetFullName(),, 'UniqueTraits');
	}
	else
	{
		`log("UniqueTraits : RemoveUniqueTrait --" @ UnitState.GetFullName() @ "has no trait assigned",, 'UniqueTraits');
	}
}

// Strips a unit's assigned trait, inside the caller's pending state (use RemoveUnitTrait / SetUnitTrait to do it as a transaction).
static final function bool ClearAssignedTrait(XComGameState_Unit MutableUnit, XComGameState NewGameState)
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
			TraitClass.static.OnClear(MutableUnit, NewGameState);

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

// Console command: "UTHazardFix on" / "UTHazardFix off" switches the AI hazard fix (UT_AIHazardFix) in the running game, without argument it toggles. Meant for A/B tests on the
// same scene: load the save, run the command, play the turn. Do it during XCOM's turn (the behavior table is rebuilt). It cannot turn on a fix that the ini option
// AI_HAZARD_FIX_ENABLED disabled.
exec function UTHazardFix(optional string Mode)
{
	if (Mode ~= "on")
		class'UT_AIHazardFix'.static.SetEnabled(true);
	else if (Mode ~= "off")
		class'UT_AIHazardFix'.static.SetEnabled(false);
	else
		class'UT_AIHazardFix'.static.SetEnabled(!class'UT_AIHazardFix'.static.IsApplied());
}

// Console command: "UTPredestinedMarks behind" / "corner" (or 0 / 1) picks where the symbols of Predestined are drawn on the promotion screen (UT_PromotionMarks): behind the icon or
// small in its corner. The open promotion screen rebuilds them at once; the ini value is PREDESTINED_MARK_MODE. Without argument it switches.
exec function UTPredestinedMarks(optional string Mode)
{
	if (Mode ~= "behind" || Mode == "0")
		class'UT_PromotionMarks'.default.PREDESTINED_MARK_MODE = 0;
	else if (Mode ~= "corner" || Mode == "1")
		class'UT_PromotionMarks'.default.PREDESTINED_MARK_MODE = 1;
	else
		class'UT_PromotionMarks'.default.PREDESTINED_MARK_MODE = 1 - class'UT_PromotionMarks'.default.PREDESTINED_MARK_MODE;
}

// Console command, the way to test a trait: gives the soldier shown in the Armory the trait TraitID, replacing the one they have.
exec function AddUniqueTrait(name TraitID)
{
	local UIArmory Armory;
	local XComGameState_Unit UnitState;

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

	UnitState = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(Armory.GetUnitRef().ObjectID));
	if (UnitState == none)
	{
		`log("UniqueTraits : AddUniqueTrait -- no unit selected",, 'UniqueTraits');
		return;
	}

	if (SetUnitTrait(UnitState.GetReference(), TraitID, "AddUniqueTrait"))
	{
		Armory.PopulateData();
		`log("UniqueTraits : AddUniqueTrait -- force-assigned" @ TraitID @ "to" @ UnitState.GetFullName(),, 'UniqueTraits');
	}
}
