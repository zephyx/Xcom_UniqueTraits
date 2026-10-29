//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_TemporaryItem.uc
//  PURPOSE: Grants one or more (Quantity) copies of a fixed item into a fixed inventory slot
//           for free, bypassing normal slot capacity (UnitState.bIgnoreItemEquipRestrictions),
//           for the duration of the tactical mission only. The item(s) and their ability are
//           cleaned up at mission end or when the effect is removed. Used by Scout for its free
//           Battle Scanner and by Smoker for its 2 free smoke grenades (Quantity = 2).
//---------------------------------------------------------------------------------------
class X2Effect_UT_TemporaryItem extends X2Effect_Persistent;

var name ItemName;
var EInventorySlot ItemInventorySlot;
var int Quantity;
// If true, resolve ItemName through the unit's HQ's own item-upgrade chain first
var bool bUseHighestAvailableUpgrade;
// If true and the unit already carries an item of the same template, add to that item's ammo
// (what the engine's own MergeAmmoAsNeeded does at mission start for bMergeAmmo items => one icon,
// quantity N) instead of creating a separate item. Used by Smoker and Young doctor.
var bool bStackOnExisting;

// Checked BEFORE bUseHighestAvailableUpgrade, in order: the first entry whose research is done replaces the item. Needed because
// the vanilla upgrade chain (BaseItem) is not reliable in a modded game: GetUpgradedItemTemplateFromBase returns the first
// template of ANY mod declaring the same BaseItem, so with LWOTC the frag grenade never climbed to the plasma one.
// Two parallel arrays (same length, index i = "when ResearchProjectNames[i] is researched, grant ResearchItemNames[i]"): no
// shared struct type, so a trait class can fill them without depending on this class at compile time.
var array<name> ResearchProjectNames;
var array<name> ResearchItemNames;

simulated protected function OnEffectAdded(const out EffectAppliedData ApplyEffectParameters, XComGameState_BaseObject kNewTargetState, XComGameState NewGameState, XComGameState_Effect NewEffectState)
{
	local XComGameState_Unit UnitState;
	local XComGameState_Effect_UT_TemporaryItem EffectState;
	local X2ItemTemplate ItemTemplate;
	local X2EquipmentTemplate EquipmentTemplate;
	local XComGameState_Item ItemState;
	local X2AbilityTemplateManager AbilityManager;
	local X2AbilityTemplate AbilityTemplate;
	local name AbilityName;
	local bool bCachedIgnoreRestrictions;
	local int i, GrantCount;
	local X2ItemTemplate OptionTemplate;

	UnitState = XComGameState_Unit(kNewTargetState);
	EffectState = XComGameState_Effect_UT_TemporaryItem(NewEffectState);
	if (UnitState == none || EffectState == none)
		return;

	ItemTemplate = class'X2ItemTemplateManager'.static.GetItemTemplateManager().FindItemTemplate(ItemName);
	if (ItemTemplate == none)
		return;

	for (i = 0; i < ResearchProjectNames.Length && i < ResearchItemNames.Length; ++i)
	{
		if (`XCOMHQ.IsTechResearched(ResearchProjectNames[i]))
		{
			OptionTemplate = class'X2ItemTemplateManager'.static.GetItemTemplateManager().FindItemTemplate(ResearchItemNames[i]);
			if (OptionTemplate != none)
			{
				ItemTemplate = OptionTemplate;
				break;
			}
		}
	}

	if (bUseHighestAvailableUpgrade)
		`XCOMHQ.UpdateItemTemplateToHighestAvailableUpgrade(ItemTemplate);

	EquipmentTemplate = X2EquipmentTemplate(ItemTemplate);
	if (EquipmentTemplate == none)
		return;

	AbilityManager = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();
	GrantCount = Max(Quantity, 1);
	for (i = 0; i < GrantCount; ++i)
	{
		if (bStackOnExisting && TryStackOnExistingItem(UnitState, EquipmentTemplate, NewGameState))
			continue;

		ItemState = EquipmentTemplate.CreateInstanceFromTemplate(NewGameState);

		bCachedIgnoreRestrictions = UnitState.bIgnoreItemEquipRestrictions;
		UnitState.bIgnoreItemEquipRestrictions = true;
		UnitState.AddItemToInventory(ItemState, ItemInventorySlot, NewGameState);
		UnitState.bIgnoreItemEquipRestrictions = bCachedIgnoreRestrictions;

		EffectState.TemporaryItems.AddItem(ItemState.GetReference());

		// The unit's abilities are normally gathered from equipment before this effect
		// (triggered on UnitPostBeginPlayTrigger) ever runs, so the item's own ability
		// (e.g. BattleScanner) needs to be initialized explicitly here rather than relying
		// on that earlier pass to have picked it up.
		foreach EquipmentTemplate.Abilities(AbilityName)
		{
			AbilityTemplate = AbilityManager.FindAbilityTemplate(AbilityName);
			if (AbilityTemplate != none && UnitState.FindAbility(AbilityName, ItemState.GetReference()).ObjectID == 0)
			{
				`TACTICALRULES.InitAbilityForUnit(AbilityTemplate, UnitState, NewGameState, ItemState.GetReference());
			}
		}
	}

	super.OnEffectAdded(ApplyEffectParameters, kNewTargetState, NewGameState, NewEffectState);
}

// Mirrors XComGameState_Unit.MergeAmmoAsNeeded for a mid-mission grant. Nothing to clean up
// later: XComGameState_Item.OnEndTacticalPlay resets Ammo/MergedItemCount/bMergedOut.
static function bool TryStackOnExistingItem(XComGameState_Unit UnitState, X2EquipmentTemplate EquipmentTemplate, XComGameState NewGameState)
{
	local X2WeaponTemplate WeaponTemplate;
	local array<XComGameState_Item> Items;
	local XComGameState_Item Item, MergeTarget;

	WeaponTemplate = X2WeaponTemplate(EquipmentTemplate);
	if (WeaponTemplate == none || !WeaponTemplate.bMergeAmmo)
		return false;

	Items = UnitState.GetAllInventoryItems(NewGameState);
	foreach Items(Item)
	{
		if (Item.GetMyTemplate() == EquipmentTemplate && !Item.bMergedOut)
		{
			MergeTarget = XComGameState_Item(NewGameState.ModifyStateObject(Item.Class, Item.ObjectID));
			MergeTarget.MergedItemCount = Max(MergeTarget.MergedItemCount, 1) + 1;
			MergeTarget.Ammo += MergeTarget.GetClipSize();
			return true;
		}
	}

	return false;
}

simulated function OnEffectRemoved(const out EffectAppliedData ApplyEffectParameters, XComGameState NewGameState, bool bCleansed, XComGameState_Effect RemovedEffectState)
{
	local XComGameState_Unit UnitState;

	UnitState = XComGameState_Unit(NewGameState.GetGameStateForObjectID(ApplyEffectParameters.TargetStateObjectRef.ObjectID));
	if (UnitState == none)
		UnitState = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(ApplyEffectParameters.TargetStateObjectRef.ObjectID));

	ClearTemporaryItems(XComGameState_Effect_UT_TemporaryItem(RemovedEffectState), NewGameState, UnitState);

	super.OnEffectRemoved(ApplyEffectParameters, NewGameState, bCleansed, RemovedEffectState);
}

function UnitEndedTacticalPlay(XComGameState_Effect EffectState, XComGameState_Unit UnitState)
{
	ClearTemporaryItems(XComGameState_Effect_UT_TemporaryItem(EffectState), UnitState.GetParentGameState(), UnitState);
}

static function ClearTemporaryItems(XComGameState_Effect_UT_TemporaryItem EffectState, XComGameState NewGameState, XComGameState_Unit UnitState)
{
	local StateObjectReference ItemRef;
	local XComGameState_Item ItemState;

	if (EffectState == none || UnitState == none || NewGameState == none)
		return;

	foreach EffectState.TemporaryItems(ItemRef)
	{
		ItemState = XComGameState_Item(`XCOMHISTORY.GetGameStateForObjectID(ItemRef.ObjectID));
		if (ItemState != none && UnitState.RemoveItemFromInventory(ItemState, NewGameState))
			NewGameState.RemoveStateObject(ItemRef.ObjectID);
	}
}

defaultproperties
{
	bInfiniteDuration = true
	GameStateEffectClass = class'XComGameState_Effect_UT_TemporaryItem'
	DuplicateResponse = eDupe_Ignore
	Quantity = 1
}
