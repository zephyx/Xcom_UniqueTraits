//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_TemporaryItem.uc
//  PURPOSE: Grants one or more (Quantity) copies of a fixed item into a fixed inventory slot
//           for free, bypassing normal slot capacity (UnitState.bIgnoreItemEquipRestrictions),
//           for the duration of the tactical mission only. The item(s) and their ability are
//           cleaned up at mission end or when the effect is removed. Used by Scout for its free
//           Battle Scanner and by Smoker for its 2 free smoke grenades (Quantity=2).
//---------------------------------------------------------------------------------------
class X2Effect_UT_TemporaryItem extends X2Effect_Persistent;

var name ItemName;
var EInventorySlot ItemInventorySlot;
var int Quantity;
// If true, resolve ItemName through the unit's HQ's own item-upgrade chain first
var bool bUseHighestAvailableUpgrade;

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

	UnitState = XComGameState_Unit(kNewTargetState);
	EffectState = XComGameState_Effect_UT_TemporaryItem(NewEffectState);
	if (UnitState == none || EffectState == none)
		return;

	ItemTemplate = class'X2ItemTemplateManager'.static.GetItemTemplateManager().FindItemTemplate(ItemName);
	if (ItemTemplate == none)
		return;

	if (bUseHighestAvailableUpgrade)
		`XCOMHQ.UpdateItemTemplateToHighestAvailableUpgrade(ItemTemplate);

	EquipmentTemplate = X2EquipmentTemplate(ItemTemplate);
	if (EquipmentTemplate == none)
		return;

	AbilityManager = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();
	GrantCount = Max(Quantity, 1);
	for (i = 0; i < GrantCount; ++i)
	{
		ItemState = EquipmentTemplate.CreateInstanceFromTemplate(NewGameState);
		NewGameState.AddStateObject(ItemState);

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
