//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_QuickHealing.uc
//  PURPOSE: Quick healing's core mechanic. Both vanilla and LWOTC compute post-mission
//           recovery time from the LOWEST HP the soldier reached at any point during the
//           mission (LowestHP), which never rises back up on its own even if the wound was
//           healed in combat. So by default, in-combat healing never shortens recovery.
//           This effect changes that for its holder: at mission end, reset LowestHP up to
//           HighestHP (as if never wounded), unless the soldier bled out at some point this
//           mission, in which case the usual harsh penalty is kept. Pattern copied from LW's
//           X2Effect_SmartMacrophages (LW_PerkPack_Integrated/Classes), which does the same
//           kind of LowestHP restoration for a different ability.
//---------------------------------------------------------------------------------------
class X2Effect_UT_QuickHealing extends X2Effect_Persistent;

function UnitEndedTacticalPlay(XComGameState_Effect EffectState, XComGameState_Unit UnitState)
{
	local UnitValue BledOutValue;

	if (UnitState != none && !UnitState.IsDead() && !UnitState.GetUnitValue('UT_QuickHealing_BledOut', BledOutValue))
	{
		UnitState.LowestHP = UnitState.HighestHP;
	}

	super.UnitEndedTacticalPlay(EffectState, UnitState);
}

defaultproperties
{
	EffectName = "UT_QuickHealing_LowestHP"
	DuplicateResponse = eDupe_Ignore
}
