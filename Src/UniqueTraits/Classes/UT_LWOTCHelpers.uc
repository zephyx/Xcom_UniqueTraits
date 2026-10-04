//---------------------------------------------------------------------------------------
//  FILE:   UT_LWOTCHelpers.uc
//  PURPOSE: Reusable queries against LWOTC's public 'GetLWUnitInfo' blind-tuple event, without ever
//           referencing an LW_Overhaul class (hard rule, see CLAUDE.md "LWOTC soft-dependency pattern").
//           Every field is pre-filled with the event's documented "unanswered" defaults, so without LWOTC
//           (or for a unit it does not know) the answers are simply "no" / 0 / none.
//           Tuple layout (X2EventListener_LWModAPI.uc): Data[0]=has officer rank, Data[1]=officer rank,
//           Data[5]=is haven liaison, Data[6]=the liaison's XComGameState_WorldRegion.
//---------------------------------------------------------------------------------------
class UT_LWOTCHelpers extends Object;

// Triggers the query and returns the (possibly LWOTC-filled) tuple.
static final function XComLWTuple QueryUnitInfo(XComGameState_Unit UnitState)
{
	local XComLWTuple Tuple;

	Tuple = new class'XComLWTuple';
	Tuple.Id = 'GetLWUnitInfo';
	Tuple.Data.Length = 9;
	Tuple.Data[0].kind = XComLWTVBool;		Tuple.Data[0].b = false;
	Tuple.Data[1].kind = XComLWTVInt;		Tuple.Data[1].i = -1;
	Tuple.Data[2].kind = XComLWTVString;	Tuple.Data[2].s = "";
	Tuple.Data[3].kind = XComLWTVString;	Tuple.Data[3].s = "";
	Tuple.Data[4].kind = XComLWTVString;	Tuple.Data[4].s = "";
	Tuple.Data[5].kind = XComLWTVBool;		Tuple.Data[5].b = false;
	Tuple.Data[6].kind = XComLWTVObject;	Tuple.Data[6].o = none;
	Tuple.Data[7].kind = XComLWTVBool;		Tuple.Data[7].b = false;
	Tuple.Data[8].kind = XComLWTVBool;		Tuple.Data[8].b = false;

	`XEVENTMGR.TriggerEvent('GetLWUnitInfo', Tuple, UnitState, none);

	return Tuple;
}

// The unit's LWOTC officer rank, 0 if it has none (or LWOTC is absent).
static final function int GetLWOfficerRank(XComGameState_Unit UnitState)
{
	local XComLWTuple Tuple;

	Tuple = QueryUnitInfo(UnitState);
	if (!Tuple.Data[0].b || Tuple.Data[1].i < 0)
		return 0;

	return Tuple.Data[1].i;
}

// The region whose haven the unit is stationed in as liaison/adviser, none if it is not one.
static final function XComGameState_WorldRegion GetLiaisonRegion(XComGameState_Unit UnitState)
{
	local XComLWTuple Tuple;

	Tuple = QueryUnitInfo(UnitState);
	if (!Tuple.Data[5].b)
		return none;

	return XComGameState_WorldRegion(Tuple.Data[6].o);
}
