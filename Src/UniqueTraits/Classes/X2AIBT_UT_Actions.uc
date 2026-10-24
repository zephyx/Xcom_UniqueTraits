//---------------------------------------------------------------------------------------
//  FILE:   X2AIBT_UT_Actions.uc
//  PURPOSE: Custom behavior tree action (node type "UTAction", registered in Config/XComAI.ini [XComGame.X2AIBTBehaviorTree] CustomNodes, the way LWOTC registers its own LWAction).
//           UTFindHazardCover (used by UT_AIHazardFix's UT_FlankedEscape node): for an EXPOSED AI unit that stands IN a hazard tile (poison, fire, acid) and has no reachable cover
//           besides the tile it stands on (the base game's reachable-tiles cache leaves every hazard tile out), picks a tile with cover that really protects it (the base game's own
//           unflanked test, IsUnflankedAt), ON A HAZARD TILE OR NOT, by a strict ranking (clean and soldier in view, hazard and in view, clean and no view, hazard and no view; then the
//           cheapest path), and sets it as the behavior's destination.
//           The move itself is UT_XGAIBehavior.MoveToPoint (path through the hazard). Every test comes first and changes nothing: when one fails the node just fails and the base game's
//           behavior goes on untouched.
//---------------------------------------------------------------------------------------
class X2AIBT_UT_Actions extends X2AIBTDefaultActions;

// How far from the unit (in tiles, each way) the cover is looked for, at most; the real limit is the unit's Mobility (one action) on the path cost.
const MAX_SEARCH_RADIUS = 10;

// The ranking of the destinations (strict: the quality first, the path cost only between tiles of the same quality; every candidate has cover):
// 0. no hazard and at least one soldier in the unit's view
// 1. hazard and a soldier in view
// 2. no hazard, no soldier in view
// 3. hazard, no soldier in view.
// A tile where the unit still sees a soldier lets it shoot back or overwatch; a clean tile is better than one in the cloud, but being able to see comes first.
const RANK_CLEAN_IN_VIEW = 0;
const RANK_HAZARD_IN_VIEW = 1;
const RANK_CLEAN_NO_VIEW = 2;
const RANK_HAZARD_NO_VIEW = 3;

static event bool FindBTActionDelegate(name strName, optional out delegate<BTActionDelegate> dOutFn, optional out name NameParam, optional out name MoveProfile)
{
	dOutFn = None;

	if (strName == 'UTFindHazardCover')
	{
		dOutFn = UTFindHazardCover;
		return true;
	}

	return super.FindBTActionDelegate(strName, dOutFn, NameParam, MoveProfile);
}

// The generic walking traversals (the unit's own list is protected in XComGameState_Unit); shared with UT_XGAIBehavior.UTMoveThroughHazard.
static final function FillWalkingTraversals(out array<ETraversalType> Traversals)
{
	Traversals.Length = 0;
	Traversals.AddItem(eTraversal_Normal);
	Traversals.AddItem(eTraversal_ClimbOver);
	Traversals.AddItem(eTraversal_ClimbOnto);
	Traversals.AddItem(eTraversal_ClimbLadder);
	Traversals.AddItem(eTraversal_DropDown);
	Traversals.AddItem(eTraversal_Landing);
	Traversals.AddItem(eTraversal_BreakWindow);
	Traversals.AddItem(eTraversal_KickDoor);
	Traversals.AddItem(eTraversal_JumpUp);
	Traversals.AddItem(eTraversal_Ramp);
}

// The base game's own test of an "unflanked" destination, the one RestrictToUnflanked applies (XGAIBehavior.PassesRestriction with bUnflanked), copied step by step so that this
// node judges a tile exactly as the vanilla flanked move would: the enemies the unit does not know, that cannot see the tile or are out of its sight range are dropped. If nobody
// is left the tile still needs cover against the nearest known enemy. Otherwise every remaining enemy with a clear line must find the unit in cover (TargetCover is not CT_None),
// except the ones the base game ignores for defense checks.
function bool IsUnflankedAt(XComGameState_Unit Unit, vector Position)
{
	local array<GameRulesCache_VisibilityInfo> EnemyInfos;
	local GameRulesCache_VisibilityInfo Info;
	local XComCoverPoint CoverPoint;
	local int i;

	class'X2TacticalVisibilityHelpers'.static.GetAllEnemiesForLocation(Position, Unit.ControllingPlayer.ObjectID, EnemyInfos);

	for (i = EnemyInfos.Length - 1; i >= 0; --i)
	{
		if (m_kBehavior.CachedKnownUnitRefs.Find('ObjectId', EnemyInfos[i].SourceID) == INDEX_NONE
			|| !EnemyInfos[i].bVisibleGameplay
			|| EnemyInfos[i].DefaultTargetDist > m_kBehavior.m_fSightRangeSq)
		{
			EnemyInfos.Remove(i, 1);
		}
	}

	if (EnemyInfos.Length == 0 && m_kBehavior.CachedKnownUnitRefs.Length > 0)
		return `XWORLD.GetCoverPointAtFloor(Position, CoverPoint) && !m_kBehavior.IsCoverFlankedToNearbyEnemies(CoverPoint);

	foreach EnemyInfos(Info)
	{
		if (!Info.bClearLOS || Info.DefaultTargetDist >= m_kBehavior.m_fSightRangeSq)
			continue;

		if (m_kBehavior.IgnoredEnemiesForDefenseChecks.Find('ObjectID', Info.SourceID) != INDEX_NONE)
			continue;

		if (Info.TargetCover == CT_None)
			return false;
	}

	return true;
}

// How many of the soldiers the unit knows would be in ITS view from this tile: the line between the two tiles is clear and the distance is within the unit's own sight range
// (m_fSightRangeSq = its current visibility radius + 3 m, the same figure and the same test as XGAIBehavior.IsValidFlankingTile). It is the view of the enemy that plays, which can be
// shorter than the soldiers' (a sight malus, a short-sighted type): the soldiers' own view of the tile (GetAllEnemiesForLocation) is not used here.
function int CountSoldiersInViewFrom(TTile FromTile)
{
	local StateObjectReference SoldierRef;
	local XComGameState_Unit Soldier;
	local TTile SoldierTile;
	local GameRulesCache_VisibilityInfo VisInfo;
	local XComWorldData World;
	local int InView;

	World = `XWORLD;

	foreach m_kBehavior.CachedKnownUnitRefs(SoldierRef)
	{
		Soldier = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(SoldierRef.ObjectID));
		if (Soldier == none || !Soldier.IsAlive())
			continue;

		SoldierTile = Soldier.TileLocation;
		if (World.CanSeeTileToTile(FromTile, SoldierTile, VisInfo) && VisInfo.DefaultTargetDist < m_kBehavior.m_fSightRangeSq)
			++InView;
	}

	return InView;
}

function bt_status UTFindHazardCover()
{
	local XComWorldData World;
	local XComGameState_Unit Unit;
	local UT_XGAIBehavior Behavior;
	local TTile Origin, Candidate, BestTile, CoverTile;
	local XComCoverPoint CoverPoint;
	local array<ETraversalType> Traversals;
	local array<TTile> Path;
	local vector Position, CoverPosition;
	local float Mobility, PathCost, BestCost;
	local int dx, dy, Radius, Rank, BestRank;
	local bool bFound, bHazard, bInView;

	Unit = m_kBehavior.UnitState;
	World = `XWORLD;
	Origin = Unit.TileLocation;

	// 1. The unit stands IN a hazard (poison, fire or acid: TileContainsHazard does not tell them apart). Anywhere else, nothing of ours applies.
	if (!class'XComPath'.static.TileContainsHazard(Unit, Origin))
		return BTS_FAILURE;

	// Only the units whose behavior class is ours (UT_AIHazardFix.UseHazardBehaviorClass swaps the base game's one; a mod that gave a unit its own class keeps it).
	Behavior = UT_XGAIBehavior(m_kBehavior);
	if (Behavior == none)
		return BTS_FAILURE;

	// 2. It is exposed: flanked, or in view of an enemy without cover (the first clauses of XGAIBehavior.IsInDangerousArea). A unit that is in cover stays where it is.
	if (!(m_kBehavior.HasKnowledgeOfXCom() && m_kBehavior.BT_IsFlanked())
		&& !(m_kBehavior.CanUseCover() && !m_kBehavior.IsInCover() && Unit.GetNumVisibleEnemyUnits(true, true, , , , , false) > 0))
		return BTS_FAILURE;

	// 3. No reachable cover besides the tile it stands on (that tile is in the cache as a cover destination when it has any cover, flanked or not).
	m_kBehavior.m_kUnit.m_kReachableTilesCache.UpdateTileCacheIfNeeded();
	foreach m_kBehavior.m_kUnit.m_kReachableTilesCache.CoverDestinations(CoverPosition)
	{
		CoverTile = World.GetTileCoordinatesFromPosition(CoverPosition);
		if (CoverTile.X != Origin.X || CoverTile.Y != Origin.Y || CoverTile.Z != Origin.Z)
			return BTS_FAILURE;
	}

	Mobility = Unit.GetCurrentStat(eStat_Mobility);
	Radius = Min(MAX_SEARCH_RADIUS, int(Mobility));
	FillWalkingTraversals(Traversals);

	for (dx = -Radius; dx <= Radius; ++dx)
	{
		for (dy = -Radius; dy <= Radius; ++dy)
		{
			if (dx == 0 && dy == 0)
				continue;

			Candidate = Origin;
			Candidate.X += dx;
			Candidate.Y += dy;

			if (!World.IsFloorTileAndValidDestination(Candidate, Unit))
				continue;

			// A tile with cover that really protects from every enemy that could shoot at it.
			Position = World.GetPositionFromTileCoordinates(Candidate);
			if (!World.GetCoverPointAtFloor(Position, CoverPoint) || !IsUnflankedAt(Unit, Position))
				continue;

			Path.Length = 0;
			if (!class'X2PathSolver'.static.BuildNonUnitPath(Origin, Candidate, Traversals, Path, int(Mobility), PathCost) || Path.Length < 2 || PathCost > Mobility)
				continue;

			bHazard = class'XComPath'.static.TileContainsHazard(Unit, Candidate);
			bInView = CountSoldiersInViewFrom(Candidate) > 0;
			if (bInView)
				Rank = bHazard ? RANK_HAZARD_IN_VIEW : RANK_CLEAN_IN_VIEW;
			else
				Rank = bHazard ? RANK_HAZARD_NO_VIEW : RANK_CLEAN_NO_VIEW;

			// The better quality wins whatever the distance; at the same quality the cheaper path.
			if (!bFound || Rank < BestRank || (Rank == BestRank && PathCost < BestCost))
			{
				bFound = true;
				BestRank = Rank;
				BestCost = PathCost;
				BestTile = Candidate;
			}
		}
	}

	if (!bFound)
		return BTS_FAILURE;

	// Only now that a destination exists: clear what the previous nodes left in the destination search, then set ours and tell UT_XGAIBehavior.MoveToPoint to build the path.
	Behavior.BT_ResetDestinationSearch();
	Behavior.m_vBTDestination = World.GetPositionFromTileCoordinates(BestTile);
	Behavior.m_bBTDestinationSet = true;
	Behavior.bUTHazardMove = true;

	return BTS_SUCCESS;
}
