//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_BountyHunter.uc
//  PURPOSE: Bounty hunter: every kill earns BOUNTYHUNTER_SUPPLY_PER_KILL supplies, but BOUNTYHUNTER_NO_XP_CHANCE_PCT% of the kills grant
//           no experience.
//           - 'OverrideKillXp' (CHL #562, fired once per kill of an enemy by a unit that can earn XP, with the kill's pending
//             game state): counts the kill in the killer's UT_BountyHunter_Kills UnitValue and sometimes zeroes the kill XP
//             (KillCount, which both vanilla and LWOTC use to rank up; bonus kill XP and Wet Work too; the assists of the
//             team mates are untouched).
//             It also queues a "Bounty" flyover on the killer (PostBuildVisualizationFn of the kill's own game state context).
//           - OnPostMission: the supplies are paid once the mission is over, from the tally, as a 'Supplies' item put in the HQ's
//             LootRecovered (PutItemInInventory with bLoot): they show in the mission rewards recap (the loot screen) like any
//             recovered supplies and are added to the resources when that loot is processed. The tally is reset. Only the kills of
//             the holder count: an ally's kill pays nothing.
//---------------------------------------------------------------------------------------
class UT_Trait_BountyHunter extends UT_TraitBase config(UniqueTraits);

var config int BOUNTYHUNTER_SUPPLY_PER_KILL;
var config int BOUNTYHUNTER_NO_XP_CHANCE_PCT;
var localized string BOUNTYHUNTER_FLYOVER;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(PurePassive('UT_BountyHunter', "img:///UILibrary_PerkIcons.UIPerk_standard", true));

	return Templates;
}

// EventData tuple: [0]=KillXp (float), [1]=BonusKillXp (float), [2]=KillAssistXp (float), [3]=WetWorkXp (int), [4]=Killer (the pending
// XComGameState_Unit). EventSource is the killed unit.
static function EventListenerReturn OnOverrideKillXp_BountyHunter(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;
	local XComGameState_Unit Killer;
	local UnitValue KillsValue;

	Tuple = XComLWTuple(EventData);
	if (Tuple == none || Tuple.Data.Length < 5)
		return ELR_NoInterrupt;

	Killer = XComGameState_Unit(Tuple.Data[4].o);
	if (Killer == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Killer, 'UT_BountyHunter'))
		return ELR_NoInterrupt;

	KillsValue.fValue = 0;
	Killer.GetUnitValue('UT_BountyHunter_Kills', KillsValue);
	Killer.SetUnitFloatValue('UT_BountyHunter_Kills', KillsValue.fValue + 1, eCleanup_BeginTactical);

	// "Bounty" flyover on the killer, appended to the visualization of the kill's own game state.
	GameState.GetContext().PostBuildVisualizationFn.AddItem(BuildVisualization_BountyFlyover);

	if (`SYNC_RAND_STATIC(100) < default.BOUNTYHUNTER_NO_XP_CHANCE_PCT)
	{
		Tuple.Data[0].f = 0.0;
		Tuple.Data[1].f = 0.0;
		Tuple.Data[3].i = 0;
	}

	return ELR_NoInterrupt;
}

// UT_TraitBase.OnPostMission: pays the supplies of the finished mission, for every soldier with a tally (also one who died).
static function OnPostMission()
{
	local XComGameStateHistory History;
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_Unit Unit, MutableUnit;
	local UnitValue KillsValue;
	local X2ItemTemplate SupplyTemplate;
	local XComGameState_Item SupplyItem;
	local array<int> UnitIDs;
	local int Kills, i;
	local XComGameState NewGameState;

	History = `XCOMHISTORY;

	foreach History.IterateByClassType(class'XComGameState_Unit', Unit)
	{
		if (Unit.IsSoldier() && Unit.GetUnitValue('UT_BountyHunter_Kills', KillsValue) && KillsValue.fValue > 0
			&& class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Unit, 'UT_BountyHunter'))
		{
			UnitIDs.AddItem(Unit.ObjectID);
			Kills += int(KillsValue.fValue);
		}
	}

	if (Kills <= 0)
		return;

	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Bounty hunter supplies");
	XComHQ = XComGameState_HeadquartersXCom(NewGameState.ModifyStateObject(class'XComGameState_HeadquartersXCom', XComHQ.ObjectID));
	SupplyTemplate = class'X2ItemTemplateManager'.static.GetItemTemplateManager().FindItemTemplate('Supplies');
	if (SupplyTemplate != none)
	{
		// As recovered loot: listed in the mission rewards recap, paid when the loot is processed.
		SupplyItem = SupplyTemplate.CreateInstanceFromTemplate(NewGameState);
		SupplyItem.Quantity = Kills * default.BOUNTYHUNTER_SUPPLY_PER_KILL;
		XComHQ.PutItemInInventory(NewGameState, SupplyItem, true);
	}
	else
		XComHQ.AddResource(NewGameState, 'Supplies', Kills * default.BOUNTYHUNTER_SUPPLY_PER_KILL);
	for (i = 0; i < UnitIDs.Length; ++i)
	{
		MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', UnitIDs[i]));
		MutableUnit.SetUnitFloatValue('UT_BountyHunter_Kills', 0, eCleanup_BeginTactical);
	}
	`GAMERULES.SubmitGameState(NewGameState);

	`log("UniqueTraits : Bounty hunter --" @ Kills @ "kill(s) paid" @ (Kills * default.BOUNTYHUNTER_SUPPLY_PER_KILL) @ "supplies",, 'UniqueTraits');
}

// PostBuildVisualizationFn of the kill's context: the killer(s) whose tally went up in that state get the flyover.
static function BuildVisualization_BountyFlyover(XComGameState VisualizeGameState)
{
	local XComGameStateHistory History;
	local XComGameState_Unit UnitState, PreviousState;
	local VisualizationActionMetadata ActionMetadata, EmptyMetadata;
	local X2Action_PlaySoundAndFlyOver FlyOver;
	local UnitValue KillsValue, PreviousKillsValue;

	History = `XCOMHISTORY;

	foreach VisualizeGameState.IterateByClassType(class'XComGameState_Unit', UnitState)
	{
		if (!UnitState.GetUnitValue('UT_BountyHunter_Kills', KillsValue))
			continue;

		PreviousKillsValue.fValue = 0;
		PreviousState = XComGameState_Unit(UnitState.GetPreviousVersion());
		if (PreviousState != none)
			PreviousState.GetUnitValue('UT_BountyHunter_Kills', PreviousKillsValue);
		if (KillsValue.fValue <= PreviousKillsValue.fValue)
			continue;

		ActionMetadata = EmptyMetadata;
		ActionMetadata.StateObject_OldState = PreviousState;
		ActionMetadata.StateObject_NewState = UnitState;
		ActionMetadata.VisualizeActor = History.GetVisualizer(UnitState.ObjectID);

		FlyOver = X2Action_PlaySoundAndFlyOver(class'X2Action_PlaySoundAndFlyOver'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, ActionMetadata.LastActionAdded));
		FlyOver.SetSoundAndFlyOverParameters(none, default.BOUNTYHUNTER_FLYOVER, '', eColor_Good);
	}
}
