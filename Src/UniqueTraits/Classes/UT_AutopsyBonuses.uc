//---------------------------------------------------------------------------------------
//  FILE:   UT_AutopsyBonuses.uc
//  PURPOSE: The strategic effect of the Coroner's autopsies (UT_Trait_Coroner). For each alien type XCOM has autopsied N times (XComGameState_UT_Autopsy, N capped at
//           CORONER_MAX_AUTOPSIES), the bonus is N x CORONER_BONUS_PER_AUTOPSY_PCT percent (10 % each, 40 % at 4 autopsies), applied to everything whose COST lists that type's corpse
//           (in the artifact costs, which is where the base game puts it, OR in the resource costs, which is where LWOTC's proving ground projects put it):
//           - research time (techs: autopsy, proving ground projects, "render" techs...) and engineering time (items): -bonus % of the template's PointsToComplete;
//           - the black market price of the corpse itself: +bonus % (rounded up): the prices listed in the black market (BuyPrices, fixed per item when it first enters the list)
//             are recomputed from a remembered base price (ReconcilePrices); the item template is not touched;
//           - the resources a "recycling" research gives (UT_Trait_Coroner.OnResearchCompleted_Coroner).
//           How: the base game reads the template at the moment a project is started (XComGameState_Tech.GetProjectPoints, XComGameState_HeadquartersProjectBuildItem), so the templates
//           themselves are rewritten (every difficulty variant), from the ORIGINAL values remembered the first time (OrigKeys / OrigValues, config arrays that are never saved, like
//           UniqueTraits_IniCache). ApplyAll runs again at every load of a campaign into the strategy layer, at the start of a new one and after every mission (the tally changes there):
//           it first puts the originals back on every template it ever changed, then applies the tally of the campaign in memory. A project already running keeps its points.
//           The templates to rewrite are the <Name>_Diff_N variants AND the "current" template (FindXxxTemplate), which is a separate object that the tech states and projects read.
//           A template whose cost lists several corpses takes the biggest of their bonuses.
//---------------------------------------------------------------------------------------
class UT_AutopsyBonuses extends Object config(UniqueTraits);

// The original values of what was rewritten: key "<template name>|<difficulty variant index>|<field>" (field P = PointsToComplete).
var config array<string> OrigKeys;
var config array<int> OrigValues;

// The bonus percentage for N autopsies of one type (N is capped).
static final function int GetBonusPct(int Count)
{
	return Min(Max(Count, 0), Max(class'UT_Trait_Coroner'.default.CORONER_MAX_AUTOPSIES, 0)) * class'UT_Trait_Coroner'.default.CORONER_BONUS_PER_AUTOPSY_PCT;
}

// The corpse item of a type: a type is the corpse item itself (the corpse the dead alien left). An entry of an older version is a character group, whose corpse is named "Corpse" + group
// (CorpseSectoid...). '' = none known.
static final function name FindCorpse(name Group)
{
	local X2ItemTemplateManager ItemManager;
	local name Candidate;

	ItemManager = class'X2ItemTemplateManager'.static.GetItemTemplateManager();

	if (ItemManager.FindItemTemplate(Group) != none)
		return Group;

	Candidate = name("Corpse" $ string(Group));
	if (ItemManager.FindItemTemplate(Candidate) != none)
		return Candidate;

	return '';
}

// The key of a type in the tally: its corpse item, else the name itself.
static final function name TypeKey(name Group)
{
	local name Corpse;

	Corpse = FindCorpse(Group);

	return (Corpse != '') ? Corpse : Group;
}

// The corpse items that have a bonus now, with their percentages, from the campaign's tally.
static final function BuildCorpseLists(out array<name> CorpseNames, out array<int> CorpsePcts, optional XComGameState_UT_Autopsy PendingTally)
{
	local XComGameState_UT_Autopsy Tally;
	local array<name> Types;
	local array<int> Totals;
	local int i, Pct;

	CorpseNames.Length = 0;
	CorpsePcts.Length = 0;

	// The pending tally of a transaction when one is given, else the committed one.
	Tally = (PendingTally != none) ? PendingTally : class'XComGameState_UT_Autopsy'.static.GetState();
	if (Tally == none)
		return;

	Tally.GetTotals(Types, Totals);
	for (i = 0; i < Types.Length; ++i)
	{
		Pct = GetBonusPct(Totals[i]);
		if (Pct <= 0)
			continue;

		if (class'X2ItemTemplateManager'.static.GetItemTemplateManager().FindItemTemplate(Types[i]) == none)
		{
			`log("UniqueTraits [WARN] : Coroner -- no corpse item known for the type" @ Types[i],, 'UniqueTraits');
			continue;
		}

		CorpseNames.AddItem(Types[i]);
		CorpsePcts.AddItem(Pct);
	}
}

// The percentage a cost lists: the biggest bonus among the corpses it asks for, in its artifact costs or in its resource costs (0 if it asks for none).
static final function int GetCostPct(const out StrategyCost Cost, const out array<name> CorpseNames, const out array<int> CorpsePcts)
{
	local int i, Index, Best;

	for (i = 0; i < Cost.ArtifactCosts.Length; ++i)
	{
		Index = CorpseNames.Find(Cost.ArtifactCosts[i].ItemTemplateName);
		if (Index != INDEX_NONE)
			Best = Max(Best, CorpsePcts[Index]);
	}

	for (i = 0; i < Cost.ResourceCosts.Length; ++i)
	{
		Index = CorpseNames.Find(Cost.ResourceCosts[i].ItemTemplateName);
		if (Index != INDEX_NONE)
			Best = Max(Best, CorpsePcts[Index]);
	}

	return Best;
}

// The same, for the campaign's tally as it is now.
static final function int GetCostBonusPct(const out StrategyCost Cost)
{
	local array<name> CorpseNames;
	local array<int> CorpsePcts;

	BuildCorpseLists(CorpseNames, CorpsePcts);

	return GetCostPct(Cost, CorpseNames, CorpsePcts);
}

// Remembers Current under Key the first time and returns the remembered original.
static final function int Original(string Key, int Current)
{
	local int Index;

	Index = default.OrigKeys.Find(Key);
	if (Index != INDEX_NONE)
		return default.OrigValues[Index];

	default.OrigKeys.AddItem(Key);
	default.OrigValues.AddItem(Current);

	return Current;
}

static final function bool HasOriginal(string Key)
{
	return default.OrigKeys.Find(Key) != INDEX_NONE;
}

// Puts the originals back and applies the campaign's autopsy tally to the item and tech templates. Safe to call at any time in the strategy layer.
static function ApplyAll()
{
	local array<name> CorpseNames;
	local array<int> CorpsePcts;
	local int i, Patched;

	BuildCorpseLists(CorpseNames, CorpsePcts);

	// Nothing to apply and nothing ever changed: leave the templates alone.
	if (CorpseNames.Length == 0 && default.OrigKeys.Length == 0)
		return;

	Patched += PatchManager(class'X2ItemTemplateManager'.static.GetItemTemplateManager(), true, CorpseNames, CorpsePcts);
	Patched += PatchManager(class'X2StrategyElementTemplateManager'.static.GetStrategyElementTemplateManager(), false, CorpseNames, CorpsePcts);

	for (i = 0; i < CorpseNames.Length; ++i)
		`log("UniqueTraits : Coroner -- bonus" @ CorpsePcts[i] $ "% for" @ CorpseNames[i],, 'UniqueTraits');

	`log("UniqueTraits : Coroner -- autopsy bonuses applied:" @ CorpseNames.Length @ "corpse type(s)," @ Patched @ "template variant(s) rewritten",, 'UniqueTraits');
}

// Every variant (one per difficulty) of every template of the manager. A variant that is the SAME object as an earlier one of the same name (a template that is not varied by difficulty)
// is skipped, otherwise its change would be applied once per variant and compound. Bonus 0 and no remembered original = nothing to do for that template.
static final function int PatchManager(X2DataTemplateManager Manager, bool bItems, const out array<name> CorpseNames, const out array<int> CorpsePcts)
{
	local array<name> TemplateNames;
	local array<X2DataTemplate> Variants;
	local X2DataTemplate Current;
	local name TemplateName;
	local int v, u, Patched;
	local bool bDuplicate;

	Manager.GetTemplateNames(TemplateNames);
	foreach TemplateNames(TemplateName)
	{
		Variants.Length = 0;
		Manager.FindDataTemplateAllDifficulties(TemplateName, Variants);

		// The "current" template (what FindXxxTemplate returns, and what tech / project states read) is an object of its own, NOT one of the _Diff_N variants: it is patched as one more variant, index = the number of variants.
		if (bItems)
			Current = class'X2ItemTemplateManager'.static.GetItemTemplateManager().FindItemTemplate(TemplateName);
		else
			Current = class'X2StrategyElementTemplateManager'.static.GetStrategyElementTemplateManager().FindStrategyElementTemplate(TemplateName);

		if (Current != none && Variants.Find(Current) == INDEX_NONE)
			Variants.AddItem(Current);

		for (v = 0; v < Variants.Length; ++v)
		{
			bDuplicate = false;
			for (u = 0; u < v; ++u)
			{
				if (Variants[u] == Variants[v])
					bDuplicate = true;
			}

			if (bDuplicate)
				continue;

			if (bItems)
			{
				if (PatchItem(X2ItemTemplate(Variants[v]), v, CorpseNames, CorpsePcts))
					++Patched;
			}
			else if (PatchTech(X2TechTemplate(Variants[v]), v, CorpseNames, CorpsePcts))
				++Patched;
		}
	}

	return Patched;
}

// Points of a project: -Pct %, at least 1. Returns the original.
static final function int SetPoints(string Key, out int Points, int Pct)
{
	local int Base;

	Base = Original(Key, Points);
	Points = (Pct > 0 && Base > 0) ? Max(1, Round(float(Base) * float(100 - Pct) / 100.0)) : Base;

	return Base;
}

static final function bool PatchTech(X2TechTemplate Tech, int Variant, const out array<name> CorpseNames, const out array<int> CorpsePcts)
{
	local string Key;
	local int Pct, Base;

	if (Tech == none)
		return false;

	Pct = GetCostPct(Tech.Cost, CorpseNames, CorpsePcts);
	Key = string(Tech.DataName) $ "|" $ Variant $ "|P";
	if (Pct <= 0 && !HasOriginal(Key))
		return false;

	Base = SetPoints(Key, Tech.PointsToComplete, Pct);

	if (Pct > 0)
		`log("UniqueTraits : Coroner --" @ Tech.DataName @ "variant" @ Variant $ ": research points" @ Base @ "->" @ Tech.PointsToComplete @ "(-" $ Pct $ "%)",, 'UniqueTraits');

	return true;
}

static final function bool PatchItem(X2ItemTemplate Item, int Variant, const out array<name> CorpseNames, const out array<int> CorpsePcts)
{
	local string KeyBase, Key;
	local int Pct, Base;
	local bool bTouched;

	if (Item == none)
		return false;

	KeyBase = string(Item.DataName) $ "|" $ Variant $ "|";

	// 1. how long the item takes to build, when its cost lists a corpse
	Pct = GetCostPct(Item.Cost, CorpseNames, CorpsePcts);
	Key = KeyBase $ "P";
	if (Pct > 0 || HasOriginal(Key))
	{
		Base = SetPoints(Key, Item.PointsToComplete, Pct);
		bTouched = true;

		if (Pct > 0)
			`log("UniqueTraits : Coroner --" @ Item.DataName @ "variant" @ Variant $ ": build points" @ Base @ "->" @ Item.PointsToComplete @ "(-" $ Pct $ "%)",, 'UniqueTraits');
	}

	return bTouched;
}

// The black market fixes the price of an item state when it first enters its price list (XComGameState_BlackMarket.GetItemPrice: the template's TradingPostValue, a random variance,
// the interest multiplier), and the list is saved with the campaign. So the bonus is not put in the template: it is applied to the LISTED price, from a base price that the tally
// remembers per listed corpse state (XComGameState_UT_Autopsy.PriceBase / PricePct). Each pass computes price = ceil(base x (100 + bonus) / 100) for every listed corpse of a type
// with a bonus, and gives the base back when the bonus is gone, so it does not matter when the corpse was listed, nor which save is loaded, nor how often this runs (idempotent).
// A corpse listed for the first time has no record yet: its current price is its base. Records of corpses no longer listed (list reset, sold) are dropped.
// PendingTally = the tally of the transaction when the caller has just changed it (counts not yet committed). Returns true when it modified a state of NewGameState.
static function bool ReconcilePrices(XComGameState NewGameState, optional XComGameState_UT_Autopsy PendingTally)
{
	local XComGameStateHistory History;
	local XComGameState_BlackMarket Market, MutableMarket;
	local XComGameState_UT_Autopsy Source, MutableTally;
	local XComGameState_Item ItemState;
	local array<name> CorpseNames;
	local array<int> CorpsePcts, StaleIDs;
	local int i, r, Index, Pct, Base, NewPrice, ItemID;
	local bool bChanged;

	Source = (PendingTally != none) ? PendingTally : class'XComGameState_UT_Autopsy'.static.GetState();
	if (Source == none)
		return false;

	History = `XCOMHISTORY;
	Market = XComGameState_BlackMarket(History.GetSingleGameStateObjectForClass(class'XComGameState_BlackMarket', true));
	if (Market == none)
		return false;

	BuildCorpseLists(CorpseNames, CorpsePcts, Source);

	MutableTally = PendingTally;

	for (i = 0; i < Market.BuyPrices.Length; ++i)
	{
		ItemState = XComGameState_Item(History.GetGameStateForObjectID(Market.BuyPrices[i].ItemRef.ObjectID));
		if (ItemState == none)
			continue;

		Index = CorpseNames.Find(ItemState.GetMyTemplateName());
		Pct = (Index == INDEX_NONE) ? 0 : CorpsePcts[Index];
		r = Source.PriceItemIDs.Find(Market.BuyPrices[i].ItemRef.ObjectID);

		if (r == INDEX_NONE && Pct <= 0)
			continue;

		Base = (r == INDEX_NONE) ? Market.BuyPrices[i].Price : Source.PriceBase[r];
		NewPrice = (Pct > 0) ? FCeil(float(Base) * float(100 + Pct) / 100.0) : Base;

		if (r != INDEX_NONE && Source.PricePct[r] == Pct && NewPrice == Market.BuyPrices[i].Price)
			continue;

		if (MutableMarket == none)
			MutableMarket = XComGameState_BlackMarket(NewGameState.ModifyStateObject(class'XComGameState_BlackMarket', Market.ObjectID));
		if (MutableTally == none)
			MutableTally = XComGameState_UT_Autopsy(NewGameState.ModifyStateObject(class'XComGameState_UT_Autopsy', Source.ObjectID));

		`log("UniqueTraits : Coroner -- black market price of a" @ ItemState.GetMyTemplateName() @ ":" @ Market.BuyPrices[i].Price @ "->" @ NewPrice @ "(base" @ Base $ ", bonus" @ Pct $ "%)",, 'UniqueTraits');
		MutableMarket.BuyPrices[i].Price = NewPrice;
		MutableTally.SetPriceRecord(Market.BuyPrices[i].ItemRef.ObjectID, Base, Pct);
		bChanged = true;
	}

	// Records of corpses that are not listed any more.
	foreach Source.PriceItemIDs(ItemID)
	{
		for (i = 0; i < Market.BuyPrices.Length; ++i)
		{
			if (Market.BuyPrices[i].ItemRef.ObjectID == ItemID)
				break;
		}

		if (i >= Market.BuyPrices.Length)
			StaleIDs.AddItem(ItemID);
	}

	foreach StaleIDs(ItemID)
	{
		if (MutableTally == none)
			MutableTally = XComGameState_UT_Autopsy(NewGameState.ModifyStateObject(class'XComGameState_UT_Autopsy', Source.ObjectID));

		MutableTally.SetPriceRecord(ItemID, 0, 0);
		bChanged = true;
	}

	return bChanged;
}

// Reconciles the listed prices in a transaction of its own (campaign loaded, console switch, the black market's sell screen opened). Returns true when a state was submitted.
static function bool ReconcileNow()
{
	local XComGameState NewGameState;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Coroner black market prices");
	if (ReconcilePrices(NewGameState))
	{
		`GAMERULES.SubmitGameState(NewGameState);
		return true;
	}

	`XCOMHISTORY.CleanupPendingGameState(NewGameState);
	return false;
}
