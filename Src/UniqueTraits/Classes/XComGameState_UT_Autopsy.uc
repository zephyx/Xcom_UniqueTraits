//---------------------------------------------------------------------------------------
//  FILE:   XComGameState_UT_Autopsy.uc
//  PURPOSE: The campaign's autopsy tally of the Coroner trait: how many autopsies of each alien type (the corpse item the alien left, e.g. CorpseSectoid) XCOM has done, whoever did them and even if the Coroner
//           died since. One object for the whole campaign, created by the first credit (UT_Trait_Coroner.OnPostMission) and saved with the history.
//           The strategic bonuses (research time, item costs, black market price) are computed from these counts, see UT_Trait_Coroner.
//---------------------------------------------------------------------------------------
class XComGameState_UT_Autopsy extends XComGameState_BaseObject;

var array<name> Groups;
var array<int> Counts;

// Black market prices raised by the Coroner's bonus (UT_AutopsyBonuses.ReconcilePrices): per listed corpse state (ObjectID) the price it had WITHOUT our bonus and the bonus percentage
// applied to it now. Saved with the history, so the price list and these records always agree whatever happened between two saves.
// ObjectIDs of the autopsy items of the loot recap that were already credited (UT_Trait_Coroner.OnPostMission), so crediting twice is impossible; forgotten once their item is gone.
var array<int> CreditedItemIDs;

var array<int> PriceItemIDs;
var array<int> PriceBase;
var array<int> PricePct;

static function XComGameState_UT_Autopsy GetState()
{
	return XComGameState_UT_Autopsy(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_UT_Autopsy', true));
}

// The number of autopsies of this type done so far (0 before the first one, or without the object). The type is the CORPSE the alien left (UT_AutopsyBonuses.TypeKey).
static function int GetCount(name Group)
{
	local XComGameState_UT_Autopsy Tally;

	Tally = GetState();

	return (Tally == none) ? 0 : Tally.CountOf(Group);
}

// The count of this type in THIS object (the pending one inside a transaction).
function int CountOf(name Group)
{
	local name Key;
	local int i, Total;

	Key = class'UT_AutopsyBonuses'.static.TypeKey(Group);
	for (i = 0; i < Groups.Length; ++i)
	{
		if (class'UT_AutopsyBonuses'.static.TypeKey(Groups[i]) == Key)
			Total += Counts[i];
	}

	return Total;
}

// Every type with its total (entries that fold into the same corpse added up).
function GetTotals(out array<name> Types, out array<int> Totals)
{
	local name Key;
	local int i, Index;

	Types.Length = 0;
	Totals.Length = 0;

	for (i = 0; i < Groups.Length; ++i)
	{
		Key = class'UT_AutopsyBonuses'.static.TypeKey(Groups[i]);
		Index = Types.Find(Key);
		if (Index == INDEX_NONE)
		{
			Types.AddItem(Key);
			Totals.AddItem(Counts[i]);
		}
		else
			Totals[Index] += Counts[i];
	}
}

// Adds Num autopsies of the type to this (pending, modifiable) object.
function AddAutopsies(name Group, int Num)
{
	local int i;

	Group = class'UT_AutopsyBonuses'.static.TypeKey(Group);
	i = Groups.Find(Group);
	if (i == INDEX_NONE)
	{
		Groups.AddItem(Group);
		Counts.AddItem(Num);
	}
	else
		Counts[i] += Num;
}

// Notes (or forgets, when Pct <= 0) the base price and the bonus applied to a listed corpse.
function SetPriceRecord(int ItemID, int Base, int Pct)
{
	local int i;

	i = PriceItemIDs.Find(ItemID);
	if (Pct <= 0)
	{
		if (i != INDEX_NONE)
		{
			PriceItemIDs.Remove(i, 1);
			PriceBase.Remove(i, 1);
			PricePct.Remove(i, 1);
		}
		return;
	}

	if (i == INDEX_NONE)
	{
		PriceItemIDs.AddItem(ItemID);
		PriceBase.AddItem(Base);
		PricePct.AddItem(Pct);
	}
	else
	{
		PriceBase[i] = Base;
		PricePct[i] = Pct;
	}
}

defaultproperties
{
	bTacticalTransient = false
}
