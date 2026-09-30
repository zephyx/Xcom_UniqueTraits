//---------------------------------------------------------------------------------------
//  FILE:   XComGameState_Effect_UT_TemporaryItem.uc
//  PURPOSE: Companion gamestate class for X2Effect_UT_TemporaryItem : tracks the item(s) it
//           granted so they can be cleaned up at mission end. Trimmed-down reimplementation
//           of LW_PerkPack_Integrated's XComGameState_Effect_TemporaryItem/X2Effect_TemporaryItem
//           pattern (that class isn't usable directly since this mod must also work without
//           LWOTC installed).
//---------------------------------------------------------------------------------------
class XComGameState_Effect_UT_TemporaryItem extends XComGameState_Effect dependson(X2Effect_UT_TemporaryItem);

var array<StateObjectReference> TemporaryItems;

defaultproperties
{
	bTacticalTransient = true
}
