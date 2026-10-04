//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_JackOfAllTrades.uc
//  PURPOSE: Jack of all trades: +JACKOFALLTRADES_AP_BONUS Ability Points once, at assignment (OnGrant,
//           reversed in OnClear). The ability itself is just the icon holder. The purchase block on the
//           class's top-cost ability row (~35 AP in LWOTC's random-deck system) is
//           UT_Trait_JackOfAllTrades.OnCPSOverrideCanPurchaseAbility_JackOfAllTrades, an optional-mod hook that only
//           fires if Community Promotion Screen is loaded.
//---------------------------------------------------------------------------------------
class UT_Trait_JackOfAllTrades extends UT_TraitBase config(UniqueTraits);

var localized string JackOfAllTradesLockedReason;

var config int JACKOFALLTRADES_AP_BONUS;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(PurePassive('UT_JackOfAllTrades', "img:///UILibrary_PerkIcons.UIPerk_standard", true));

	return Templates;
}

static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	MutableUnit.AbilityPoints += default.JACKOFALLTRADES_AP_BONUS;
}

static function OnClear(XComGameState_Unit MutableUnit)
{
	MutableUnit.AbilityPoints -= default.JACKOFALLTRADES_AP_BONUS;
}

// 'CPS_OverrideCanPurchaseAbility' (optional Community Promotion Screen hook): blocks buying the top-cost, non-class
// ability row (the ~35 AP "XCOM row" in LWOTC's random-deck purchase system). Registered at priority 1 (runs after every
// other mod's listener, larger numbers run first): a block only counts if no later listener flips bCanPurchaseAbility back.
static function EventListenerReturn OnCPSOverrideCanPurchaseAbility_JackOfAllTrades(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;
	local XComGameState_Unit UnitState;
	local X2SoldierClassTemplate ClassTemplate;
	local int TopRankIndex;

	Tuple = XComLWTuple(EventData);
	UnitState = XComGameState_Unit(EventSource);
	if (Tuple == none || UnitState == none || Tuple.Data.Length < 16)
		return ELR_NoInterrupt;

	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_JackOfAllTrades'))
		return ELR_NoInterrupt;

	// The last column of the soldier's own class rank tree, not the AbilityPointCosts array length:
	// LWOTC and other mods change either one independently of the other, and only the class's
	// real number of ranks says which ability is the last one on screen.
	ClassTemplate = UnitState.GetSoldierClassTemplate();
	if (ClassTemplate != none)
		TopRankIndex = ClassTemplate.GetMaxConfiguredRank() - 1;
	else
		TopRankIndex = class'X2StrategyGameRulesetDataStructures'.default.AbilityPointCosts.Length - 1;

	if (Tuple.Data[1].i < TopRankIndex || Tuple.Data[5].b)
		return ELR_NoInterrupt;

	Tuple.Data[13].b = false;
	Tuple.Data[15].s = default.JackOfAllTradesLockedReason;


	return ELR_NoInterrupt;
}
