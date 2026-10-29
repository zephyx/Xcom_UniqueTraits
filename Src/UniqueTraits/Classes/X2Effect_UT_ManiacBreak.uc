//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_ManiacBreak.uc
//  PURPOSE: Maniac explosive's "Break!": the effect the ability puts on its holder until the end of the turn (EffectName UT_ManiacBreak_Active, tested by
//           X2Effect_UT_ManiacBreakWorld). It carries the unit-damage part of the bonus and the cooldown rule:
//           - every damage a GRENADE thrown or launched by the holder already deals (not its ticks) is raised by DamagePerRank x rank (rounded down: with 0.3
//             per rank that is +1 from rank 4 (a LWOTC Sergeant) and +2 from rank 7); the explosion's environment damage is X2Effect_UT_ManiacBreakWorld's job;
//           - when the turn ends (OnEffectRemoved) and NOTHING was destroyed by the holder's environment damage since the ability was used, the ability's
//             cooldown is shortened by CooldownRefund turns. Environment damage that destroys nothing (open ground) does not count; DestructionSeen tells
//             what was destroyed (the game state has no hit points for the scenery, so it combines several signals).
//---------------------------------------------------------------------------------------
class X2Effect_UT_ManiacBreak extends X2Effect_Persistent;

var float DamagePerRank;
var int CooldownRefund;

function int GetAttackingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, const int CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, optional XComGameState NewGameState)
{
	// Any damage a grenade already deals (CurrentDamage > 0), flagged explosive or not: AP Grenades' effect has bExplosiveDamage = false (its APGRENADE_DESTROYSLOOT).
	// A grenade without damage (smoke, flashbang) has nothing to raise.
	if (CurrentDamage <= 0 || WeaponDamageEffect == none || class'UT_EffectHelpers'.static.IsTickDamage(AppliedData))
		return 0;

	if (!IsGrenadeAbility(AbilityState))
		return 0;

	// The small epsilon keeps an exact product (10 x 0.3 = 3) from falling short through float rounding.
	return int(float(Attacker.GetRank()) * DamagePerRank + 0.0001);
}

// True when the ability throws or launches a grenade.
static function bool IsGrenadeAbility(XComGameState_Ability AbilityState)
{
	return GetGrenadeTemplate(AbilityState) != none;
}

// The grenade of a throw (the ability's weapon) or of a launch (the ability's ammo, or the ammo loaded in the launcher); none for any other ability.
static function X2GrenadeTemplate GetGrenadeTemplate(XComGameState_Ability AbilityState)
{
	local XComGameState_Item SourceItem;
	local X2GrenadeTemplate GrenadeTemplate;

	if (AbilityState == none)
		return none;

	SourceItem = AbilityState.GetSourceAmmo();
	if (SourceItem != none)
	{
		GrenadeTemplate = X2GrenadeTemplate(SourceItem.GetMyTemplate());
		if (GrenadeTemplate != none)
			return GrenadeTemplate;
	}

	SourceItem = AbilityState.GetSourceWeapon();
	if (SourceItem == none)
		return none;

	GrenadeTemplate = X2GrenadeTemplate(SourceItem.GetMyTemplate());
	if (GrenadeTemplate != none)
		return GrenadeTemplate;

	return X2GrenadeTemplate(SourceItem.GetLoadedAmmoTemplate(AbilityState));
}

simulated function OnEffectRemoved(const out EffectAppliedData ApplyEffectParameters, XComGameState NewGameState, bool bCleansed, XComGameState_Effect RemovedEffectState)
{
	local XComGameStateHistory History;
	local XComGameState_Unit SourceUnit;
	local XComGameState_Ability AbilityState;
	local XComGameState_EnvironmentDamage Damage;
	local array<XComGameState_EnvironmentDamage> Events;
	local int StartIndex;

	super.OnEffectRemoved(ApplyEffectParameters, NewGameState, bCleansed, RemovedEffectState);

	if (CooldownRefund <= 0)
		return;

	History = `XCOMHISTORY;
	SourceUnit = XComGameState_Unit(History.GetGameStateForObjectID(ApplyEffectParameters.SourceStateObjectRef.ObjectID));
	if (SourceUnit == none || !SourceUnit.IsAlive())
		return;

	StartIndex = GetFirstHistoryIndex(RemovedEffectState);

	// The environment damage the holder has caused since the ability was used.
	foreach History.IterateByClassType(class'XComGameState_EnvironmentDamage', Damage)
	{
		if (Damage.DamageAmount > 0 && Damage.DamageCause.ObjectID == SourceUnit.ObjectID && Damage.GetParentGameState().HistoryIndex >= StartIndex)
			Events.AddItem(Damage);
	}

	if (Events.Length > 0 && DestructionSeen(Events))
		return;

	AbilityState = XComGameState_Ability(NewGameState.ModifyStateObject(class'XComGameState_Ability', ApplyEffectParameters.AbilityStateObjectRef.ObjectID));
	if (AbilityState != none && AbilityState.iCooldown > 0)
		AbilityState.iCooldown = Max(0, AbilityState.iCooldown - CooldownRefund);
}

// True when something was destroyed by these environment damage events (all caused by the holder). Three signals, any one is enough:
//  1. AdjacentFractureTiles of an event: filled by the game when the state is submitted with the tiles next to the walls and floors that the damage destroyed (0 on bare
//     ground, 2 to 112 with a wall or a building). The other results of the damage states (CausedDestruction(), DestroyedActors, FractureTiles, DestroyedLadders) were always
//     empty after the fact: native visualization caches, not used.
//  2. an XComDestructibleActor that is going down or down (states _DestructionStarted, _Destroyed, Dead, or Health 0) and whose LastDamageStateObject is one of these events:
//     an exact attribution (a wall, a tree, a car...);
//  3. the same rule applied in advance to the actors of the area that the visualization has not reached yet (the turn can end right after a throw, before the actors react):
//     XComDestructibleActor.GetNewHealth with the event's amount, a "gate" (one event whose amount reaches the actor's Health destroys it).
static function bool DestructionSeen(const out array<XComGameState_EnvironmentDamage> Events)
{
	local XComWorldData World;
	local XComGameState_EnvironmentDamage Damage;
	local XComDestructibleActor Destructible;
	local array<int> EventIDs;
	local array<TTile> TileMins, TileMaxs;
	local TTile Tile, BoxMin, BoxMax, ActorTile;
	local int i, OldHealth, NewHealth, GotoDamaged, GotoDestroyed;

	World = `XWORLD;

	for (i = 0; i < Events.Length; i++)
	{
		Damage = Events[i];
		if (Damage.AdjacentFractureTiles.Length > 0)
			return true;

		EventIDs.AddItem(Damage.ObjectID);

		// The bounding box of the tiles, to keep the search of the actors cheap.
		BoxMin.X = 100000; BoxMin.Y = 100000; BoxMin.Z = 100000;
		BoxMax.X = -100000; BoxMax.Y = -100000; BoxMax.Z = -100000;
		foreach Damage.DamageTiles(Tile)
		{
			BoxMin.X = Min(BoxMin.X, Tile.X); BoxMin.Y = Min(BoxMin.Y, Tile.Y); BoxMin.Z = Min(BoxMin.Z, Tile.Z);
			BoxMax.X = Max(BoxMax.X, Tile.X); BoxMax.Y = Max(BoxMax.Y, Tile.Y); BoxMax.Z = Max(BoxMax.Z, Tile.Z);
		}
		TileMins.AddItem(BoxMin);
		TileMaxs.AddItem(BoxMax);
	}

	foreach class'WorldInfo'.static.GetWorldInfo().AllActors(class'XComDestructibleActor', Destructible)
	{
		// Signal 2: the actor is down and the last damage it took is one of ours.
		if (EventIDs.Find(Destructible.LastDamageStateObject.ObjectID) != INDEX_NONE)
		{
			if (IsDown(Destructible))
				return true;

			continue;
		}

		if (IsDown(Destructible))
			continue;

		// Signal 3: the actor is still standing and in the area of an event: would the gate bring it down?
		if (Destructible.Toughness != none && Destructible.Toughness.bInvincible && !Destructible.Toughness.bSuccumbsToDamage)
			continue;

		ActorTile = World.GetTileCoordinatesFromPosition(Destructible.Location);
		for (i = 0; i < Events.Length; i++)
		{
			Damage = Events[i];
			if (!ActorInArea(Destructible, ActorTile, Damage, TileMins[i], TileMaxs[i]))
				continue;
			if (Damage.bAffectFragileOnly && !(Destructible.Toughness != none && Destructible.Toughness.bFragile))
				continue;

			OldHealth = Destructible.Health;
			NewHealth = class'XComDestructibleActor'.static.GetNewHealth(Destructible, OldHealth, Damage.DamageAmount, GotoDamaged, GotoDestroyed);
			if (GotoDestroyed == 1 || (NewHealth <= 0 && OldHealth > 0))
				return true;
		}
	}

	return false;
}

// The actor is going down or down.
static function bool IsDown(XComDestructibleActor Destructible)
{
	return Destructible.IsInState('_DestructionStarted') || Destructible.IsInState('_Destroyed') || Destructible.IsInState('Dead') || Destructible.Health <= 0;
}

// Is the actor in the area an environment damage event covers? Listed tiles (a bounding box test first) or, without tiles, the radius around the hit location.
static function bool ActorInArea(XComDestructibleActor Destructible, const out TTile ActorTile, XComGameState_EnvironmentDamage Damage, const out TTile BoxMin, const out TTile BoxMax)
{
	local TTile Tile;

	if (Damage.DamageTiles.Length == 0)
		return Damage.DamageRadius > 0.0 && VSize(Destructible.Location - Damage.HitLocation) <= Damage.DamageRadius;

	if (ActorTile.X < BoxMin.X || ActorTile.X > BoxMax.X || ActorTile.Y < BoxMin.Y || ActorTile.Y > BoxMax.Y || ActorTile.Z < BoxMin.Z - 1 || ActorTile.Z > BoxMax.Z + 1)
		return false;

	foreach Damage.DamageTiles(Tile)
	{
		if (Tile.X == ActorTile.X && Tile.Y == ActorTile.Y && Abs(Tile.Z - ActorTile.Z) <= 1)
			return true;
	}

	return false;
}

// History index of the game state that created the object (its oldest version).
static function int GetFirstHistoryIndex(XComGameState_BaseObject State)
{
	local XComGameState_BaseObject Oldest;

	Oldest = State;
	while (Oldest.GetPreviousVersion() != none)
		Oldest = Oldest.GetPreviousVersion();

	return Oldest.GetParentGameState().HistoryIndex;
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
