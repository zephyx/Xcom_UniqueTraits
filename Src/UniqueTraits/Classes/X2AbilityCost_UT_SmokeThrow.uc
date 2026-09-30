//---------------------------------------------------------------------------------------
//  FILE:   X2AbilityCost_UT_SmokeThrow.uc
//  PURPOSE: Smoker's "doesn't end the turn when thrown" mechanic, scoped to smoke grenades
//           only. Vanilla's X2AbilityCost_ActionPoints.ConsumeAllPoints already supports a
//           generic "don't consume all points" check (DoNotConsumeAllSoldierAbilities /
//           DoNotConsumeAllEffects, but neither list is aware of *which weapon* is being used, so
//           they can't be scoped to smoke grenades specifically without also freeing every
//           other grenade the unit carries. LW_XModBase's XMBEffect_DoNotConsumeAllPoints
//           solves this exact problem (see LW_XModBase/Classes/Examples.uc's SmokeAndMirrors),
//           but it only works through XMBAbilityCost_ActionPoints, a full replacement for the
//           vanilla action-point cost class installed via XModBase's own class-override system,
//           both are third-party (LW_XModBase), so neither may be referenced here. This is
//           a bespoke equivalent: a small subclass of the vanilla/CHL X2AbilityCost_ActionPoints
//           that adds one extra weapon+trait check on top of the inherited behaviour.
//---------------------------------------------------------------------------------------
class X2AbilityCost_UT_SmokeThrow extends X2AbilityCost_ActionPoints config(UniqueTraits);

var config array<name> SMOKER_GRENADE_WEAPON_NAMES;

simulated function bool ConsumeAllPoints(XComGameState_Ability AbilityState, XComGameState_Unit AbilityOwner)
{
	local XComGameState_Item SourceWeapon;

	if (bConsumeAllPoints)
	{
		SourceWeapon = AbilityState.GetSourceWeapon();
		if (SourceWeapon != none
			&& default.SMOKER_GRENADE_WEAPON_NAMES.Find(SourceWeapon.GetMyTemplateName()) != INDEX_NONE
			&& class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(AbilityOwner, 'UT_Smoker'))
		{
			return false;
		}
	}

	return super.ConsumeAllPoints(AbilityState, AbilityOwner);
}
