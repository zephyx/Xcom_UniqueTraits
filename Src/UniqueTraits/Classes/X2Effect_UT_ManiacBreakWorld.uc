//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_ManiacBreakWorld.uc
//  PURPOSE: The environment-damage half of Maniac explosive's "Break!". UT_Trait_ManiacExplosive.OnPostTemplatesCreated appends one of these to the
//           thrown and launched effects of every grenade that has a damage effect. It does nothing unless the thrower is affected by
//           UT_ManiacBreak_Active and the grenade has environment damage of its own (gas, fire, acid and EMP grenades have none, as with Sapper).
//           HOW: it INCREASES the DamageAmount of the grenade's own XComGameState_EnvironmentDamage states by ENV_BASE + ENV_PER_RANK x rank, it does not
//           create another event. Reason: a destructible actor that is not "targetable" takes environment damage as a GATE, not as hit points
//           (XComDestructibleActor.GetNewHealth: it is destroyed by ONE event whose DamageAmount reaches its Health, two smaller events do not add up),
//           so an extra event of the bonus's size would only matter on its own. Raising the grenade's events makes the bonus add up with the grenade's
//           damage, Sapper, Combat Engineer and any other source, exactly as if the grenade had more environment damage.
//           The effect is the LAST of the grenade's list (appended), so the grenade's damage effect (the base game's X2Effect_ApplyWeaponDamage, or
//           LWOTC's explosive falloff subclass) has already created its events in NewGameState when ApplyEffectToWorld runs. LWOTC makes one event per falloff
//           step (100 / 75 / 50 / 25 % of the amount, on the tiles of the step), Combat Engineer's no-falloff grenade makes one: each event gets the bonus in
//           proportion to its own amount compared with the biggest one, so the falloff of the bonus is the grenade's own, whatever the perks.
//---------------------------------------------------------------------------------------
class X2Effect_UT_ManiacBreakWorld extends X2Effect;

simulated function ApplyEffectToWorld(const out EffectAppliedData ApplyEffectParameters, XComGameState NewGameState)
{
	local XComGameStateHistory History;
	local XComGameState_Unit SourceUnit;
	local XComGameState_Ability AbilityState;
	local X2GrenadeTemplate GrenadeTemplate;
	local XComGameState_EnvironmentDamage DamageEvent;
	local array<XComGameState_EnvironmentDamage> GrenadeEvents;
	local int Bonus, MaxAmount;

	History = `XCOMHISTORY;
	SourceUnit = XComGameState_Unit(History.GetGameStateForObjectID(ApplyEffectParameters.SourceStateObjectRef.ObjectID));
	AbilityState = XComGameState_Ability(History.GetGameStateForObjectID(ApplyEffectParameters.AbilityStateObjectRef.ObjectID));
	if (SourceUnit == none || AbilityState == none || !SourceUnit.IsUnitAffectedByEffectName('UT_ManiacBreak_Active'))
		return;

	// Only a grenade that has environment damage of its own gets the bonus (iEnvironmentDamage of the template: 0 for gas, fire, acid, EMP).
	GrenadeTemplate = class'X2Effect_UT_ManiacBreak'.static.GetGrenadeTemplate(AbilityState);
	if (GrenadeTemplate == none || GrenadeTemplate.iEnvironmentDamage <= 0)
		return;

	Bonus = class'UT_Trait_ManiacExplosive'.default.MANIAC_BREAK_ENV_BASE + class'UT_Trait_ManiacExplosive'.default.MANIAC_BREAK_ENV_PER_RANK * SourceUnit.GetRank();
	if (Bonus <= 0)
		return;

	// The environment damage events that the grenade's DAMAGE effect has created so far (the base game's and LWOTC's both mark theirs with
	// "X2Effect_ApplyWeaponDamage"): not the events of a fire or acid world effect, and not the health bucket (bTargetableDamage) of a targetable object
	// hit by the explosion. A grenade without such an event (no environment damage) is left alone.
	foreach NewGameState.IterateByClassType(class'XComGameState_EnvironmentDamage', DamageEvent)
	{
		if (DamageEvent.DamageCause.ObjectID != SourceUnit.ObjectID || DamageEvent.DamageAmount <= 0 || DamageEvent.bTargetableDamage
			|| InStr(DamageEvent.DEBUG_SourceCodeLocation, "X2Effect_ApplyWeaponDamage") == INDEX_NONE)
			continue;

		GrenadeEvents.AddItem(DamageEvent);
		MaxAmount = Max(MaxAmount, DamageEvent.DamageAmount);
	}

	if (MaxAmount <= 0)
		return;

	foreach GrenadeEvents(DamageEvent)
		DamageEvent.DamageAmount += int(float(Bonus) * float(DamageEvent.DamageAmount) / float(MaxAmount));
}

defaultproperties
{
	bApplyToWorldOnHit = true
	bApplyToWorldOnMiss = true
}
