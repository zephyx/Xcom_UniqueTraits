//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Thief.uc
//  PURPOSE: Thief: icon holder, the mechanics are the 'ItemLooted' listener and UIScreenListener_UT_LootWindow.
//---------------------------------------------------------------------------------------
class UT_Trait_Thief extends UT_TraitBase config(UniqueTraits);

var config int THIEF_STEAL_CHANCE_PCT;
var localized string THIEF_STEAL_FLYOVER;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Thief());

	return Templates;
}

// Thief: this passive is just the icon holder. The actual mechanics (MP refund on loot pickup,
// chance to secretly keep a looted item) are implemented as global event listeners in
// X2EventListener_UniqueTraits (OnItemLooted / OnAfterActionModifyRecoveredLoot), since
// neither is naturally expressible as an effect attached to this ability.
static function X2AbilityTemplate Thief()
{
	local X2AbilityTemplate Template;

	Template = PurePassive('UT_Thief', "img:///UniqueTraits_Icons.UT_Thief", true);

	return Template;
}

// Thief: picking up loot (XCOM's turn only) grants a bonus movement point, once per turn. Independently,
// a flat chance rolls to secretly keep THAT ITEM (it's removed from the looter's
// inventory again right away (before it can ever reach XComHQ.LootRecovered at mission end, so
// it's simply never part of the recovered-loot pool, no separate post-mission bookkeeping needed)).
static function EventListenerReturn OnItemLooted(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit Looter, MutableLooter;
	local XComGameState_Item LootedItem;
	local XComGameState_Player ActivePlayer;
	local UnitValue BonusValue;

	Looter = XComGameState_Unit(EventSource);
	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Looter, 'UT_Thief'))
		return ELR_NoInterrupt;

	// Only during XCOM's own turn (loot can also be collected from a kill during the enemy turn).
	ActivePlayer = XComGameState_Player(`XCOMHISTORY.GetGameStateForObjectID(`TACTICALRULES.GetCachedUnitActionPlayerRef().ObjectID));
	if (ActivePlayer == none || ActivePlayer.GetTeam() != eTeam_XCom)
		return ELR_NoInterrupt;

	MutableLooter = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', Looter.ObjectID));

	// 'ItemLooted' fires once PER ITEM (and "loot all" picks every item of a pool inside one game state), and a soldier can loot
	// several pools in a turn: the bonus movement point is granted once per TURN. UT_Thief_BonusThisTurn is cleared at the start
	// of the unit's next turn; it is set on the pending state, so a second item of the same loot action sees it too.
	if (!MutableLooter.GetUnitValue('UT_Thief_BonusThisTurn', BonusValue))
	{
		MutableLooter.ActionPoints.AddItem(class'X2CharacterTemplateManager'.default.MoveActionPoint);
		MutableLooter.SetUnitFloatValue('UT_Thief_BonusThisTurn', 1, eCleanup_BeginTurn);
	}

	if (`SYNC_RAND_STATIC(100) >= default.THIEF_STEAL_CHANCE_PCT)
		return ELR_NoInterrupt;

	LootedItem = XComGameState_Item(EventData);
	if (LootedItem == none || !MutableLooter.RemoveItemFromInventory(LootedItem, GameState))
		return ELR_NoInterrupt;

	// Flag the item so UIScreenListener_UT_LootWindow shows a red "Stolen!" row for it in the
	// tactical loot window (THIEF_STEAL_FLYOVER).
	MutableLooter.SetUnitFloatValue(name("UT_Thief_Stolen_" $ LootedItem.ObjectID), 1, eCleanup_BeginTactical);

	`log("UniqueTraits : Thief secretly kept" @ LootedItem.GetMyTemplateName() @ "- lost for XCOM",, 'UniqueTraits');

	return ELR_NoInterrupt;
}
