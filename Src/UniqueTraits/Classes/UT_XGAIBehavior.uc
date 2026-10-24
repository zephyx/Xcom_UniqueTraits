//---------------------------------------------------------------------------------------
//  FILE:   UT_XGAIBehavior.uc
//  PURPOSE: The AI behavior class of the enemies (X2CharacterTemplate.BehaviorClass, swapped for the base game's XGAIBehavior by UT_AIHazardFix.UseHazardBehaviorClass), with ONE
//           difference: when X2AIBT_UT_Actions.UTFindHazardCover has chosen a destination for an exposed unit standing in a hazard, MoveToPoint builds the path through the hazard
//           (X2PathSolver.BuildNonUnitPath, as the Community Highlander's AIHazardEscape does) and submits the move itself. The base game's MoveToPoint asks the reachable-tiles cache,
//           which leaves every hazard tile out, so it cannot reach such a destination. In every other case it calls the base game's MoveToPoint: nothing else changes.
//---------------------------------------------------------------------------------------
class UT_XGAIBehavior extends XGAIBehavior;

// Set by UTFindHazardCover once it has put its destination in m_vBTDestination; cleared by the next destination search reset and by the move itself.
var bool bUTHazardMove;

function BT_ResetDestinationSearch()
{
	super.BT_ResetDestinationSearch();

	bUTHazardMove = false;
}

simulated function bool MoveToPoint(vector vDestination, optional out string FailText)
{
	if (bUTHazardMove)
	{
		bUTHazardMove = false;

		return UTMoveThroughHazard(vDestination, FailText);
	}

	return super.MoveToPoint(vDestination, FailText);
}

// The same end as the base game's MoveToPoint (GameStateMoveUnitSingle with GameStateMoveUnitCallback, which hands the unit over to the end of its turn), with a path that does not
// care about the hazards.
function bool UTMoveThroughHazard(vector vDestination, out string FailText)
{
	local array<TTile> Path;
	local array<ETraversalType> Traversals;
	local TTile kTileDest;

	kTileDest = `XWORLD.GetTileCoordinatesFromPosition(vDestination);

	class'X2AIBT_UT_Actions'.static.FillWalkingTraversals(Traversals);
	if (!class'X2PathSolver'.static.BuildNonUnitPath(UnitState.TileLocation, kTileDest, Traversals, Path) || Path.Length < 2)
	{
		FailText = "UT hazard cover move: no path to (" $ kTileDest.X @ kTileDest.Y @ kTileDest.Z $ ").";
		OnMoveFailure("MoveToPoint (UT hazard cover) failed:" @ FailText, false);

		return false;
	}

	XComTacticalController(GetALocalPlayerController()).GameStateMoveUnitSingle(m_kUnit, Path,, GameStateMoveUnitCallback);

	return true;
}
