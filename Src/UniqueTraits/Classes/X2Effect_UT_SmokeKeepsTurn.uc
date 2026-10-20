//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_SmokeKeepsTurn.uc
//  PURPOSE: Smoker's "throwing a smoke grenade does not end the turn".
//           X2Effect_Persistent.PostAbilityCostPaid is called by X2AbilityTemplate.ApplyCost for every persistent effect of the source unit, in the very state of the ability,
//           right after the cost was paid, with the action points the unit had BEFORE it (the hook LWOTC's Rapid Deployment uses to make a grenade free). When the ability is a
//           smoke grenade thrown or launched (UT_Trait_Smoker.IsSmokeThrow), the points the unit should have left are those before the cost minus the cost the throw really
//           has for him (GetPointCost of its action point costs: 0 when another effect made it free, then nothing is given back); if the throw took more than that (it
//           consumed all the points), the missing points are given back, with their types. A throw that is free by restoring the points (Rapid Deployment) leaves the unit with
//           at least that many: nothing is changed. The function returns false so that the effects after this one still run (Rapid Deployment must remove itself).
//---------------------------------------------------------------------------------------
class X2Effect_UT_SmokeKeepsTurn extends X2Effect_Persistent;

function bool PostAbilityCostPaid(XComGameState_Effect EffectState, XComGameStateContext_Ability AbilityContext, XComGameState_Ability kAbility, XComGameState_Unit SourceUnit, XComGameState_Item AffectWeapon, XComGameState NewGameState, const array<name> PreCostActionPoints, const array<name> PreCostReservePoints)
{
	local X2AbilityTemplate Template;
	local X2AbilityCost Cost;
	local X2AbilityCost_ActionPoints PointsCost, FirstPointsCost;
	local array<name> Wanted, Left;
	local int i, j, PointsToTake, Taken;

	if (SourceUnit == none || !class'UT_Trait_Smoker'.static.IsSmokeThrow(kAbility, AffectWeapon))
		return false;

	// What the throw costs this unit now (an effect may have made it free).
	Template = kAbility.GetMyTemplate();
	foreach Template.AbilityCosts(Cost)
	{
		PointsCost = X2AbilityCost_ActionPoints(Cost);
		if (PointsCost == none || PointsCost.bFreeCost || PointsCost.bMoveCost)
			continue;

		if (FirstPointsCost == none)
			FirstPointsCost = PointsCost;

		PointsToTake += PointsCost.GetPointCost(kAbility, SourceUnit);
	}

	if (FirstPointsCost == none || PointsToTake <= 0)
		return false;

	// The points the unit keeps if the throw only takes its cost: the ones before, minus the cost, in the order ApplyCost takes them (the most specific types first).
	Wanted = PreCostActionPoints;
	for (i = FirstPointsCost.AllowedTypes.Length - 1; i >= 0 && Taken < PointsToTake; --i)
	{
		for (j = Wanted.Length - 1; j >= 0 && Taken < PointsToTake; --j)
		{
			if (Wanted[j] == FirstPointsCost.AllowedTypes[i])
			{
				Wanted.Remove(j, 1);
				++Taken;
			}
		}
	}

	// The unit already has at least that many (the cost left them, or another effect gave the points back): nothing to do.
	if (SourceUnit.ActionPoints.Length >= Wanted.Length)
		return false;

	// Give back the ones he lacks, keeping any other point he got.
	Left = SourceUnit.ActionPoints;
	for (i = 0; i < Wanted.Length; ++i)
	{
		j = Left.Find(Wanted[i]);
		if (j != INDEX_NONE)
			Left.Remove(j, 1);
		else
			SourceUnit.ActionPoints.AddItem(Wanted[i]);
	}

	`log("UniqueTraits : Smoker keeps his turn --" @ SourceUnit.GetFullName() @ "threw" @ kAbility.GetMyTemplateName() @ ", action points" @ SourceUnit.ActionPoints.Length,, 'UniqueTraits');

	return false;
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
