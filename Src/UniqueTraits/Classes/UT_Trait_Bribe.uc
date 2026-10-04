//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Bribe.uc
//  PURPOSE: Bribe [LWOTC ONLY]: icon holder; supplies are the 'OverrideSupplyDrop' listener + SyncBribeSupplyBonus, the infiltration penalty is read by LWOTC from XComLW_InfiltrationSettings.ini.
//---------------------------------------------------------------------------------------
class UT_Trait_Bribe extends UT_TraitBase config(UniqueTraits);

var config int BRIBE_SUPPLY_BONUS;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Bribe());

	return Templates;
}

// Bribe: this passive is just the icon holder. The +20 monthly supplies bonus is implemented by
// UT_Trait_Bribe.OnOverrideSupplyDrop (vanilla/CHL event, no LWOTC dependency).
// The infiltration penalty is entirely LWOTC's own doing: Config/XComLW_InfiltrationSettings.ini
// declares +AbilityCovertness=(AbilityName="UT_Bribe", IndividualMultiplier=1.20) under
// LW_Overhaul.XComGameState_LWPersistentSquad, and LWOTC's own GetSoldierCovertness reads that
// config and checks HasSoldierAbility('UT_Bribe') itself
static function X2AbilityTemplate Bribe()
{
	local X2AbilityTemplate Template;

	Template = PurePassive('UT_Bribe', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	return Template;
}

static function EventListenerReturn OnStaffUpdated(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	SyncBribeSupplyBonus();
	return ELR_NoInterrupt;
}

// Bribe: +20 supplies at the end of every month, as long as its holder is alive and haven advisor.
static function EventListenerReturn OnOverrideSupplyDrop(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;

	Tuple = XComLWTuple(EventData);
	if (Tuple == none || Tuple.Data.Length < 2)
		return ELR_NoInterrupt;

	// Only while a holder is actually stationed as a haven liaison (see SyncBribeSupplyBonus).
	if (AnyBribeHolderIsLiaison())
	{
		Tuple.Data[1].i += default.BRIBE_SUPPLY_BONUS;
		`log("UniqueTraits : Bribe -- OverrideSupplyDrop, +" $ default.BRIBE_SUPPLY_BONUS $ " supplies, month-end total now " $ Tuple.Data[1].i,, 'UniqueTraits');
	}

	return ELR_NoInterrupt;
}

// True if a living Bribe holder is currently stationed as a haven liaison (month-end payout gate).
static final function bool AnyBribeHolderIsLiaison()
{
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Unit> Soldiers;
	local XComGameState_Unit Soldier;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return false;

	Soldiers = XComHQ.GetSoldiers();
	foreach Soldiers(Soldier)
	{
		if (class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Soldier, 'UT_Bribe') && class'UT_LWOTCHelpers'.static.GetLiaisonRegion(Soldier) != none)
			return true;
	}

	return false;
}

// Bribe (LWOTC): +BRIBE_SUPPLY_BONUS supplies per month for the region whose haven the holder is
// stationed in as liaison/adviser. Whether/where a unit is a liaison comes from
// UT_LWOTCHelpers.GetLiaisonRegion. LWOTC's own UI shows a haven's income through that region's
// GetSupplyDropReward(), so the bonus is mirrored into the region's POISupplyBonusDelta (a vanilla field
// that feeds GetSupplyDropReward() and which LWOTC never rewrites, unlike BaseSupplyDrop). The real
// month-end payout is handled separately by OnOverrideSupplyDrop, which LWOTC's own listener overwrites
// with its outposts' income (region deltas are NOT part of that payout).
// Brings every region's Bribe bonus in line with reality. Each soldier's applied region is tracked in
// the UT_Bribe_RegionID UnitValue, so this is idempotent and also undoes a bonus whose holder lost the
// trait, died, was dismissed or was taken out of the haven. If ExternalGameState is given (a listener
// already inside a transaction) changes go into it, otherwise a transaction of our own is submitted.
static final function SyncBribeSupplyBonus(optional XComGameState ExternalGameState)
{
	local XComGameStateHistory History;
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Unit> Soldiers;
	local XComGameState_Unit Unit, MutableUnit;
	local XComGameState_WorldRegion Region, MutableRegion;
	local XComGameState NewGameState;
	local UnitValue AppliedValue;
	local array<int> LivingSoldierIDs;
	local int AppliedID, DesiredID, i;

	History = `XCOMHISTORY;
	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return;

	Soldiers = XComHQ.GetSoldiers();
	for (i = 0; i < Soldiers.Length; ++i)
		LivingSoldierIDs.AddItem(Soldiers[i].ObjectID);

	NewGameState = ExternalGameState;

	foreach History.IterateByClassType(class'XComGameState_Unit', Unit)
	{
		if (!Unit.IsSoldier())
			continue;

		AppliedID = 0;
		if (Unit.GetUnitValue('UT_Bribe_RegionID', AppliedValue))
			AppliedID = int(AppliedValue.fValue);

		DesiredID = 0;
		if (LivingSoldierIDs.Find(Unit.ObjectID) != INDEX_NONE && !Unit.IsDead() && class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Unit, 'UT_Bribe'))
		{
			Region = class'UT_LWOTCHelpers'.static.GetLiaisonRegion(Unit);
			if (Region != none)
				DesiredID = Region.ObjectID;
		}

		if (DesiredID == AppliedID)
			continue;

		if (NewGameState == none)
			NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Bribe supply sync");

		if (AppliedID != 0)
		{
			MutableRegion = XComGameState_WorldRegion(NewGameState.ModifyStateObject(class'XComGameState_WorldRegion', AppliedID));
			MutableRegion.POISupplyBonusDelta -= default.BRIBE_SUPPLY_BONUS;
		}
		if (DesiredID != 0)
		{
			MutableRegion = XComGameState_WorldRegion(NewGameState.ModifyStateObject(class'XComGameState_WorldRegion', DesiredID));
			MutableRegion.POISupplyBonusDelta += default.BRIBE_SUPPLY_BONUS;
		}

		MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Unit.ObjectID));
		MutableUnit.SetUnitFloatValue('UT_Bribe_RegionID', DesiredID, eCleanup_Never);

		`log("UniqueTraits : Bribe supply sync --" @ Unit.GetFullName() @ "region" @ AppliedID @ "->" @ DesiredID,, 'UniqueTraits');
	}

	if (NewGameState != none && ExternalGameState == none)
	{
		if (NewGameState.GetNumGameStateObjects() > 0)
			`GAMERULES.SubmitGameState(NewGameState);
		else
			History.CleanupPendingGameState(NewGameState);
	}
}

// Safety net for the region bonus: the holder may have died/been dismissed since the last 'StaffUpdated'.
static function EventListenerReturn OnPreEndOfMonth_Bribe(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	if (GameState != none)
		SyncBribeSupplyBonus(GameState);

	return ELR_NoInterrupt;
}
