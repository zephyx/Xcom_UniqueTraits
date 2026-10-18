//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Cyborg.uc
//  PURPOSE: Cyborg: can only wear BASIC personal combat sims (PCS: an equipment of the combat sim slot that only boosts stats from
//           CYBORG_ALLOWED_PCS_STATS, directly or through an ability of CYBORG_PCS_ABILITY_STATS, and does nothing else); a PCS that is replaced or removed is not destroyed but goes back
//           to the XCOM inventory; after every victorious mission, each worn PCS has CYBORG_UPGRADE_CHANCE_PCT% to be upgraded by
//           one tier (the PCS of the same stats with the next Tier: vanilla Common -> Rare -> Epic).
//           - Equip rule: 'OverrideCanEquipImplant' (CHL #1094, the armory list; registered at priority 1 because LWOTC's own listener
//             sets the result to true at priority 50), 'PCSApplied' as a safety net (a non-basic PCS that got equipped anyway is
//             sent straight back to the inventory) and OnGrant (a non-basic PCS already worn goes back to the inventory).
//             NOT a CanAddItemToInventory block: UIInventory_Implants.InstallImplant takes the PCS out of the inventory BEFORE
//             adding it to the unit, so a refused add made the PCS disappear.
//           - Not lost: 'ItemRemovedFromSlot' (CHL #694), for the "Remove Personal Combat Sim" change of UIInventory_Implants.RemoveImplant
//             only (it destroys the item afterwards, so a COPY is put in the inventory); skipped when the Reuse PCS breakthrough does it.
//           - Upgrade: OnPostMission.
//---------------------------------------------------------------------------------------
class UT_Trait_Cyborg extends UT_TraitBase config(UniqueTraits);

struct CyborgAbilityStat
{
	var name AbilityName;
	var ECharStatType Stat;
};

var config array<ECharStatType> CYBORG_ALLOWED_PCS_STATS;
// Abilities of a PCS that are nothing but a stat boost (the mod CutContentPsionicsLWOTC turns the Psi PCS into such an ability).
var config array<CyborgAbilityStat> CYBORG_PCS_ABILITY_STATS;
var config int CYBORG_UPGRADE_CHANCE_PCT;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(PurePassive('UT_Cyborg', "img:///UniqueTraits_Icons.UT_Cyborg", true));

	return Templates;
}

// The stats a PCS boosts: its StatsToBoost plus the stat of each of its abilities listed in CYBORG_PCS_ABILITY_STATS. False if it has an
// ability that is not a plain stat boost (a "special" PCS).
static final function bool GetBoostedStats(X2EquipmentTemplate PCS, out array<ECharStatType> Stats)
{
	local name AbilityName;
	local int Index;

	Stats = PCS.StatsToBoost;
	foreach PCS.Abilities(AbilityName)
	{
		Index = default.CYBORG_PCS_ABILITY_STATS.Find('AbilityName', AbilityName);
		if (Index == INDEX_NONE)
			return false;

		if (Stats.Find(default.CYBORG_PCS_ABILITY_STATS[Index].Stat) == INDEX_NONE)
			Stats.AddItem(default.CYBORG_PCS_ABILITY_STATS[Index].Stat);
	}

	return true;
}

// A basic PCS: a combat sim that only boosts the allowed stats (directly, or through a plain stat-boost ability) and does nothing else.
static final function bool IsBasicPCS(X2ItemTemplate ItemTemplate)
{
	local X2EquipmentTemplate PCS;
	local array<ECharStatType> Stats;
	local ECharStatType Stat;

	PCS = X2EquipmentTemplate(ItemTemplate);
	if (PCS == none || PCS.InventorySlot != eInvSlot_CombatSim || !GetBoostedStats(PCS, Stats) || Stats.Length == 0)
		return false;

	foreach Stats(Stat)
	{
		if (default.CYBORG_ALLOWED_PCS_STATS.Find(Stat) == INDEX_NONE)
			return false;
	}

	return true;
}

static final function bool HaveSameStats(X2EquipmentTemplate A, X2EquipmentTemplate B)
{
	local array<ECharStatType> StatsA, StatsB;
	local ECharStatType Stat;

	if (!GetBoostedStats(A, StatsA) || !GetBoostedStats(B, StatsB) || StatsA.Length != StatsB.Length)
		return false;

	foreach StatsA(Stat)
	{
		if (StatsB.Find(Stat) == INDEX_NONE)
			return false;
	}

	return true;
}

// The PCS of the same stats with the next higher Tier, none if Current is already the best.
static final function X2EquipmentTemplate FindUpgradedPCS(X2EquipmentTemplate Current)
{
	local X2ItemTemplateManager ItemMgr;
	local X2DataTemplate DataTemplate;
	local X2EquipmentTemplate Candidate, Best;

	ItemMgr = class'X2ItemTemplateManager'.static.GetItemTemplateManager();

	foreach ItemMgr.IterateTemplates(DataTemplate, none)
	{
		Candidate = X2EquipmentTemplate(DataTemplate);
		if (Candidate == none || Candidate.Tier <= Current.Tier || !IsBasicPCS(Candidate) || !HaveSameStats(Candidate, Current))
			continue;

		if (Best == none || Candidate.Tier < Best.Tier)
			Best = Candidate;
	}

	return Best;
}

// A PCS already worn that is not basic goes back to the inventory (the equip rules only stop future equips).
static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Item> Items;
	local XComGameState_Item Item;

	Items = MutableUnit.GetAllItemsInSlot(eInvSlot_CombatSim, NewGameState);
	foreach Items(Item)
	{
		if (IsBasicPCS(Item.GetMyTemplate()))
			continue;

		Item = XComGameState_Item(NewGameState.ModifyStateObject(class'XComGameState_Item', Item.ObjectID));
		if (MutableUnit.RemoveItemFromInventory(Item, NewGameState))
		{
			XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
			if (XComHQ != none)
			{
				XComHQ = XComGameState_HeadquartersXCom(NewGameState.ModifyStateObject(class'XComGameState_HeadquartersXCom', XComHQ.ObjectID));
				XComHQ.PutItemInInventory(NewGameState, Item);
			}
		}
	}
}

// 'OverrideCanEquipImplant' (the armory's PCS list): EventData tuple [0]=CanEquip (bool), [1]=the PCS (XComGameState_Item); EventSource = the unit.
static function EventListenerReturn OnOverrideCanEquipImplant_Cyborg(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;
	local XComGameState_Unit UnitState;
	local XComGameState_Item Implant;

	Tuple = XComLWTuple(EventData);
	UnitState = XComGameState_Unit(EventSource);
	if (Tuple == none || UnitState == none || Tuple.Data.Length < 2 || !Tuple.Data[0].b)
		return ELR_NoInterrupt;

	Implant = XComGameState_Item(Tuple.Data[1].o);
	if (Implant != none && class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_Cyborg') && !IsBasicPCS(Implant.GetMyTemplate()))
		Tuple.Data[0].b = false;

	return ELR_NoInterrupt;
}

// 'PCSApplied' (UIInventory_Implants.InstallImplant, pending state, just after the PCS was added to the unit): EventData = the unit,
// EventSource = the item. A non-basic PCS on a Cyborg goes straight back to the XCOM inventory.
static function EventListenerReturn OnPCSApplied_Cyborg(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit UnitState;
	local XComGameState_Item Implant;
	local XComGameState_HeadquartersXCom XComHQ;

	UnitState = XComGameState_Unit(EventData);
	Implant = XComGameState_Item(EventSource);
	if (UnitState == none || Implant == none || GameState == none
		|| !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_Cyborg') || IsBasicPCS(Implant.GetMyTemplate()))
		return ELR_NoInterrupt;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	UnitState = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', UnitState.ObjectID));
	Implant = XComGameState_Item(GameState.ModifyStateObject(class'XComGameState_Item', Implant.ObjectID));
	if (UnitState.RemoveItemFromInventory(Implant, GameState))
	{
		XComHQ = XComGameState_HeadquartersXCom(GameState.ModifyStateObject(class'XComGameState_HeadquartersXCom', XComHQ.ObjectID));
		XComHQ.PutItemInInventory(GameState, Implant);
		`log("UniqueTraits : Cyborg --" @ UnitState.GetFullName() @ ": non-basic PCS" @ Implant.GetMyTemplateName() @ "sent back to the inventory",, 'UniqueTraits');
	}

	return ELR_NoInterrupt;
}

// 'ItemRemovedFromSlot': EventData = the item (its slot is already unknown), EventSource = the unit, GameState = the pending state.
// UIInventory_Implants.RemoveImplant destroys the removed PCS afterwards unless the Reuse PCS breakthrough is active, so a copy
// goes into the XCOM inventory (stacked with the same PCS there). Recognised by the change's description, which the UI hard-codes.
static function EventListenerReturn OnItemRemovedFromSlot_Cyborg(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Item Item, ItemCopy;
	local XComGameState_Unit UnitState;
	local XComGameStateContext_ChangeContainer ChangeContext;
	local XComGameState_HeadquartersXCom XComHQ;

	Item = XComGameState_Item(EventData);
	UnitState = XComGameState_Unit(EventSource);
	if (Item == none || UnitState == none || GameState == none)
		return ELR_NoInterrupt;

	ChangeContext = XComGameStateContext_ChangeContainer(GameState.GetContext());
	if (ChangeContext == none || ChangeContext.ChangeInfo != "Remove Personal Combat Sim")
		return ELR_NoInterrupt;

	if (Item.GetMyTemplate().ItemCat != 'combatsim' || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_Cyborg'))
		return ELR_NoInterrupt;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none || XComHQ.bReusePCS)
		return ELR_NoInterrupt;

	XComHQ = XComGameState_HeadquartersXCom(GameState.ModifyStateObject(class'XComGameState_HeadquartersXCom', XComHQ.ObjectID));
	ItemCopy = Item.GetMyTemplate().CreateInstanceFromTemplate(GameState);
	ItemCopy.StatBoosts = Item.StatBoosts;
	XComHQ.PutItemInInventory(GameState, ItemCopy);

	`log("UniqueTraits : Cyborg --" @ UnitState.GetFullName() @ ": PCS" @ Item.GetMyTemplateName() @ "kept in the inventory",, 'UniqueTraits');

	return ELR_NoInterrupt;
}

// UT_TraitBase.OnPostMission: after a VICTORIOUS mission, each PCS worn by a Cyborg of the squad has a chance to be upgraded by a tier.
static function OnPostMission()
{
	local XComGameStateHistory History;
	local XComGameState_BattleData BattleData;
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference SquadRef;
	local XComGameState_Unit Unit, MutableUnit;
	local array<XComGameState_Item> Items;
	local XComGameState_Item PCS, MutablePCS, NewPCS;
	local X2EquipmentTemplate UpgradeTemplate;
	local XComGameState NewGameState;

	History = `XCOMHISTORY;

	BattleData = XComGameState_BattleData(History.GetSingleGameStateObjectForClass(class'XComGameState_BattleData', true));
	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (BattleData == none || !BattleData.bLocalPlayerWon || XComHQ == none)
		return;

	foreach XComHQ.Squad(SquadRef)
	{
		Unit = XComGameState_Unit(History.GetGameStateForObjectID(SquadRef.ObjectID));
		if (Unit == none || !Unit.IsAlive() || Unit.bCaptured || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Unit, 'UT_Cyborg'))
			continue;

		Items = Unit.GetAllItemsInSlot(eInvSlot_CombatSim);
		foreach Items(PCS)
		{
			if (!IsBasicPCS(PCS.GetMyTemplate()) || `SYNC_RAND_STATIC(100) >= default.CYBORG_UPGRADE_CHANCE_PCT)
				continue;

			UpgradeTemplate = FindUpgradedPCS(X2EquipmentTemplate(PCS.GetMyTemplate()));
			if (UpgradeTemplate == none)
				continue;

			if (NewGameState == none)
				NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Cyborg PCS upgrade");

			MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Unit.ObjectID));
			MutablePCS = XComGameState_Item(NewGameState.ModifyStateObject(class'XComGameState_Item', PCS.ObjectID));
			if (!MutableUnit.RemoveItemFromInventory(MutablePCS, NewGameState))
				continue;

			NewGameState.RemoveStateObject(PCS.ObjectID);
			NewPCS = UpgradeTemplate.CreateInstanceFromTemplate(NewGameState);
			MutableUnit.AddItemToInventory(NewPCS, eInvSlot_CombatSim, NewGameState);

			`log("UniqueTraits : Cyborg --" @ Unit.GetFullName() @ ": PCS" @ PCS.GetMyTemplateName() @ "upgraded to" @ UpgradeTemplate.DataName,, 'UniqueTraits');
		}
	}

	if (NewGameState != none)
		`GAMERULES.SubmitGameState(NewGameState);
}
