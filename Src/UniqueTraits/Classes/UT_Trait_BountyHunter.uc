//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_BountyHunter.uc
//  PURPOSE: Bounty hunter: every kill earns BOUNTYHUNTER_SUPPLY_PER_KILL supplies, but BOUNTYHUNTER_NO_XP_CHANCE_PCT% of the kills grant
//           no experience.
//           - 'UnitDied': counts the kills of the regular enemy force (NOT the Lost, NOT summoned units) in the killer's UT_BountyHunter_Kills UnitValue.
//           - 'OverrideKillXp' (CHL #562, fired once per kill of an enemy by a unit that can earn XP, with the kill's pending
//             game state): sometimes zeroes the kill XP
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

	Templates.AddItem(PurePassive('UT_BountyHunter', "img:///UniqueTraits_Icons.UT_BountyHunter", true));

	return Templates;
}

// EventData tuple: [0]=KillXp (float), [1]=BonusKillXp (float), [2]=KillAssistXp (float), [3]=WetWorkXp (int), [4]=Killer (the pending
// XComGameState_Unit). EventSource is the killed unit.
static function EventListenerReturn OnOverrideKillXp_BountyHunter(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;
	local XComGameState_Unit Killer;

	Tuple = XComLWTuple(EventData);
	if (Tuple == none || Tuple.Data.Length < 5)
		return ELR_NoInterrupt;

	Killer = XComGameState_Unit(Tuple.Data[4].o);
	if (Killer == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Killer, 'UT_BountyHunter'))
		return ELR_NoInterrupt;

	if (`SYNC_RAND_STATIC(100) < default.BOUNTYHUNTER_NO_XP_CHANCE_PCT)
	{
		Tuple.Data[0].f = 0.0;
		Tuple.Data[1].f = 0.0;
		Tuple.Data[3].i = 0;
	}

	return ELR_NoInterrupt;
}

// 'UnitDied' (EventSource = the dead unit): counts the kill for the supplies, ONLY for the regular enemy force (team Alien): the Lost and
// summoned units (Chosen Warlock...) do NOT pay. The killer is the source of the ability that killed, else the last unit that damaged the dead one.
static function EventListenerReturn OnUnitDied_BountyHunter(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateHistory History;
	local XComGameState_Unit DeadUnit, Killer;
	local XComGameStateContext_Ability AbilityContext;
	local int KillerID;

	DeadUnit = XComGameState_Unit(EventSource);
	if (DeadUnit == none)
		return ELR_NoInterrupt;

	History = `XCOMHISTORY;

	AbilityContext = XComGameStateContext_Ability(GameState.GetContext());
	if (AbilityContext != none)
		KillerID = AbilityContext.InputContext.SourceObject.ObjectID;
	if (KillerID == 0)
		KillerID = DeadUnit.LastDamagedByUnitID;

	Killer = XComGameState_Unit(History.GetGameStateForObjectID(KillerID));
	if (Killer == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Killer, 'UT_BountyHunter'))
		return ELR_NoInterrupt;

	// Only the real enemy force pays: not the Lost, not a unit summoned by an effect (Chosen Warlock's spectral zombies...), not a ghost copy.
	if (DeadUnit.GetTeam() != eTeam_Alien || DeadUnit.GhostSourceUnit.ObjectID > 0 || IsSummonedUnit(DeadUnit))
		return ELR_NoInterrupt;

	Killer = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', KillerID));
	Killer.SetUnitFloatValue('UT_BountyHunter_Kills', GetUnitFloat(Killer, 'UT_BountyHunter_Kills') + 1, eCleanup_BeginTactical);

	// "Bounty" flyover on the killer, appended to the visualization of the kill's own game state.
	GameState.GetContext().PostBuildVisualizationFn.AddItem(BuildVisualization_BountyFlyover);

	return ELR_NoInterrupt;
}

// A unit created by an X2Effect_SpawnUnit (the effect state remembers the created unit, like a claymore's in vanilla's OnUnitDied).
static function bool IsSummonedUnit(XComGameState_Unit Unit)
{
	local XComGameState_Effect EffectState;

	foreach `XCOMHISTORY.IterateByClassType(class'XComGameState_Effect', EffectState)
	{
		if (EffectState.CreatedObjectReference.ObjectID == Unit.ObjectID && X2Effect_SpawnUnit(EffectState.GetX2Effect()) != none)
			return true;
	}

	return false;
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
	local XComGameState_Unit UnitState, PreviousState;

	foreach VisualizeGameState.IterateByClassType(class'XComGameState_Unit', UnitState)
	{
		if (class'UT_EffectHelpers'.static.ValueIncreased(UnitState, 'UT_BountyHunter_Kills', PreviousState))
			class'UT_EffectHelpers'.static.AddUnitFlyover(VisualizeGameState, UnitState, PreviousState, default.BOUNTYHUNTER_FLYOVER);
	}
}
