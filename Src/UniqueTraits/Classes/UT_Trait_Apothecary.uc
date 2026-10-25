//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Apothecary.uc
//  PURPOSE: Apothecary: every poison the holder inflicts on an enemy comes with a paralysing toxin, in return for a body worn out by the poisons: -APOTHECARY_HP_MALUS HP (the base HP never go below
//           APOTHECARY_MIN_HP because of the trait) and wounds APOTHECARY_RECOVERY_PCT % worse (more HP lost: the healing time follows the wound, but NOT by that percentage).
//           - The toxin is a debuff of its own, added to the poison (the poison effects are never touched, so nothing of other mods is patched): for APOTHECARY_TOXIN_TURNS turn(s) the enemy has
//             -APOTHECARY_TOXIN_AIM_MALUS Aim, -APOTHECARY_TOXIN_MOBILITY_MALUS Mobility, -APOTHECARY_TOXIN_SIGHT_MALUS sight radius and (APOTHECARY_TOXIN_REMOVES_SQUADSIGHT, an MCM checkbox) LOSES its squadsight, which comes back when the toxin ends
//             (the effect named Squadsight is removed and the very same effect, the one of the ability that provided it, is applied again when the toxin ends, as the Laser designator's
//             mark does with Shadowstep: see X2Effect_UT_Suppression; the Advent Sniper, for one, has an ability of its own for it).
//           - The toxin is INDEPENDENT of the poison: an effect of its own (name, state, duration), neither tied to the poison's state nor to the holder staying alive. Only an ability the HOLDER
//             activates can apply or renew it: a poison from a soldier without the trait never does, even on an enemy the holder poisoned earlier.
//           - Detection: 'AbilityActivated' (ELD_OnStateSubmitted), like Chemist: the persistent effect states of an activation of the holder, on an enemy, that this activation created or renewed
//             (more turns left than in the previous version: the refresh of a poison keeps its first source, so the source of the effect state is NOT tested) and that are a POISON,
//             whatever the mod: an effect whose damage types (its own, or those of the weapon damage it applies on every tick) contain one of APOTHECARY_POISON_NAME_PARTS ("Poison": the vanilla
//             'Poison', 'EleriumPoisoning'...), unless the target is immune to that damage type. The toxin is the effect of the hidden ability UT_ApothecaryToxin (never granted), applied in a
//             change container of its own. A poison that the holder does not apply himself (a spread from the poisoned unit, a cloud) gives no toxin.
//           - The numbers in the descriptions follow the ini / the Mod Config Menu: the texts hold the tag <Ability:UT_ApothecaryToxin/>, expanded by ExpandAbilityTag when they are shown.
//           - The HP are a permanent change of the soldier (ShiftStat and its ledger, see UT_TraitBase), given at once; the removal takes back the ledger, a respec is absorbed
//             by OnStatsReset. The floor is on the BASE HP the soldier would have without the trait (base - ledger), so it stays exact when the HP grow with the ranks.
//           - The recovery time is changed like Mind over matter's: a 'CleanupTacticalMission' handler, before EndTacticalHealthMod, makes the wound (HighestHP - LowestHP)
//             longer by the percentage (rounded to whole HP, so a small wound may not change).
//---------------------------------------------------------------------------------------
class UT_Trait_Apothecary extends UT_TraitBase config(UniqueTraits);

var config int APOTHECARY_HP_MALUS, APOTHECARY_MIN_HP, APOTHECARY_RECOVERY_PCT;
var config int APOTHECARY_TOXIN_TURNS, APOTHECARY_TOXIN_AIM_MALUS, APOTHECARY_TOXIN_MOBILITY_MALUS, APOTHECARY_TOXIN_SIGHT_MALUS;
var config bool APOTHECARY_TOXIN_REMOVES_SQUADSIGHT;   // false: the toxin leaves the squadsight of the enemy alone (the descriptions follow)
var config array<string> APOTHECARY_POISON_NAME_PARTS;

// The pieces of the tag <Ability:UT_ApothecaryToxin/> ([UT_Trait_Apothecary] of UniqueTraits.int/.fra): %VALUE is the number.
var localized string APOTHECARY_AIM_TEXT, APOTHECARY_MOBILITY_TEXT, APOTHECARY_SIGHT_TEXT, APOTHECARY_NO_SQUADSIGHT_TEXT, APOTHECARY_DURATION_TEXT, APOTHECARY_DURATION_ONE_TEXT;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(PurePassive('UT_Apothecary', "img:///UniqueTraits_Icons.UT_Apothecary", true));
	Templates.AddItem(ApothecaryToxin());

	return Templates;
}

// Event registrations (X2EventListener_UniqueTraits.CreateTacticalListeners calls this for every trait of the pool that is not disabled).
static function OnCreateTacticalListeners(CHEventListenerTemplate Template)
{
	// The toxin on the enemies a poison was just inflicted on (applies its effect in a state of its own, like Chemist).
	Template.AddCHEvent('AbilityActivated', OnAbilityActivated_Apothecary, ELD_OnStateSubmitted, 50);
	// The longer wound, as Mind over matter does it.
	Template.AddCHEvent('CleanupTacticalMission', OnCleanupTacticalMission_Apothecary, ELD_Immediate, 50);
	Template.AddCHEvent('UnitBleedingOut', OnUnitBleedingOut_Apothecary, ELD_Immediate, 50);
}

//---------------------------------------------------------------------------------------
// The toxin
//---------------------------------------------------------------------------------------

// Holder of the toxin (effect 0): hidden, never granted.
static function X2AbilityTemplate ApothecaryToxin()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_Suppression ToxinEffect;

	Template = HiddenEffectHolder('UT_ApothecaryToxin');
	Template.Hostility = eHostility_Offensive;

	// The same effect class as the Laser designator's mark (it keeps what it suppressed in its own effect state, so a unit can carry both).
	ToxinEffect = new class'X2Effect_UT_Suppression';
	ToxinEffect.EffectName = 'UT_Apothecary_Toxin';
	if (default.APOTHECARY_TOXIN_REMOVES_SQUADSIGHT)
		ToxinEffect.EffectNamesToSuppress.AddItem('Squadsight');
	// A new poison of the holder on the same unit renews the toxin (duration back to the full value).
	ToxinEffect.DuplicateResponse = eDupe_Refresh;
	// Ticks at the start of XCOM's turns (the effect is bound to the holder's player), as Chemist's disease: applied during XCOM's turn, TOXIN_TURNS = 2 means two enemy phases.
	// It does not end with the holder (bRemoveWhenSourceDies false): it has its own life.
	ToxinEffect.BuildPersistentEffect(Max(1, default.APOTHECARY_TOXIN_TURNS), false, false, false, eGameRule_PlayerTurnBegin);
	// The RAW description (it holds the tag <Ability:UT_ApothecaryToxin/>, expanded when the effect is shown on the unit): GetMyLongDescription() would bake the tag once, at creation.
	ToxinEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.LocLongDescription, Template.IconImage, true,, Template.AbilitySourceName);
	if (default.APOTHECARY_TOXIN_AIM_MALUS != 0)
		ToxinEffect.AddPersistentStatChange(eStat_Offense, -default.APOTHECARY_TOXIN_AIM_MALUS);
	if (default.APOTHECARY_TOXIN_MOBILITY_MALUS != 0)
		ToxinEffect.AddPersistentStatChange(eStat_Mobility, -default.APOTHECARY_TOXIN_MOBILITY_MALUS);
	if (default.APOTHECARY_TOXIN_SIGHT_MALUS != 0)
		ToxinEffect.AddPersistentStatChange(eStat_SightRadius, -default.APOTHECARY_TOXIN_SIGHT_MALUS);
	Template.AddTargetEffect(ToxinEffect);

	return Template;
}

// UT_TraitBase.ExpandAbilityTag: <Ability:UT_ApothecaryToxin/> = the toxin's effects with the CURRENT values (ini or Mod Config Menu), e.g. "-10 Aim, -2 Mobility, -3 sight radius,
// no Squadsight for 2 turns". A malus set to 0 is left out.
static function bool ExpandAbilityTag(string InString, out string OutString, Object ParseObj, Object StrategyParseObj, XComGameState GameState)
{
	local string Effects, Duration;
	local int Turns;

	if (!(InString ~= "UT_ApothecaryToxin"))
		return false;

	if (default.APOTHECARY_TOXIN_AIM_MALUS != 0)
		Effects = AppendPart(Effects, Repl(default.APOTHECARY_AIM_TEXT, "%VALUE", string(default.APOTHECARY_TOXIN_AIM_MALUS)));
	if (default.APOTHECARY_TOXIN_MOBILITY_MALUS != 0)
		Effects = AppendPart(Effects, Repl(default.APOTHECARY_MOBILITY_TEXT, "%VALUE", string(default.APOTHECARY_TOXIN_MOBILITY_MALUS)));
	if (default.APOTHECARY_TOXIN_SIGHT_MALUS != 0)
		Effects = AppendPart(Effects, Repl(default.APOTHECARY_SIGHT_TEXT, "%VALUE", string(default.APOTHECARY_TOXIN_SIGHT_MALUS)));
	if (default.APOTHECARY_TOXIN_REMOVES_SQUADSIGHT)
		Effects = AppendPart(Effects, default.APOTHECARY_NO_SQUADSIGHT_TEXT);

	Turns = Max(1, default.APOTHECARY_TOXIN_TURNS);
	if (Turns == 1)
		Duration = default.APOTHECARY_DURATION_ONE_TEXT;
	else
		Duration = Repl(default.APOTHECARY_DURATION_TEXT, "%VALUE", string(Turns));

	OutString = Effects @ Duration;

	return true;
}

static final function string AppendPart(string List, string Part)
{
	if (List == "")
		return Part;

	return List $ ", " $ Part;
}

// True when the name (a damage type or an effect name) contains one of APOTHECARY_POISON_NAME_PARTS, whatever the case.
static final function bool IsPoisonName(name TypeName)
{
	local string Part, Upper;

	if (TypeName == '')
		return false;

	Upper = Caps(string(TypeName));
	foreach default.APOTHECARY_POISON_NAME_PARTS(Part)
	{
		if (Part != "" && InStr(Upper, Caps(Part)) != INDEX_NONE)
			return true;
	}

	return false;
}

// True when the persistent effect is a poison; PoisonType is then the damage type that names it (the one the target's immunity is tested against).
static final function bool IsPoisonEffect(X2Effect_Persistent Effect, out name PoisonType)
{
	local X2Effect TickEffect;
	local X2Effect_ApplyWeaponDamage Damage;
	local name TypeName;

	if (Effect == none)
		return false;

	foreach Effect.DamageTypes(TypeName)
	{
		if (IsPoisonName(TypeName))
		{
			PoisonType = TypeName;
			return true;
		}
	}

	// The damage the effect applies on every tick (the Elerium poisoning of a mod puts its type in both places, another mod may only use one).
	foreach Effect.ApplyOnTick(TickEffect)
	{
		Damage = X2Effect_ApplyWeaponDamage(TickEffect);
		if (Damage == none)
			continue;

		foreach Damage.DamageTypes(TypeName)
		{
			if (IsPoisonName(TypeName))
			{
				PoisonType = TypeName;
				return true;
			}
		}

		if (IsPoisonName(Damage.EffectDamageValue.DamageType))
		{
			PoisonType = Damage.EffectDamageValue.DamageType;
			return true;
		}
	}

	return false;
}

// 'AbilityActivated' fires more than once per ability: the interrupt step is skipped (ParseAbilityActivation, which also requires the activating unit to hold the trait: an ability of a
// soldier without it never applies or renews the toxin). The poisons this activation created (no previous version) or renewed (more turns left than in the previous version), on an enemy
// that can be poisoned.
static function EventListenerReturn OnAbilityActivated_Apothecary(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateHistory History;
	local XComGameStateContext_Ability AbilityContext;
	local XComGameState_Unit SourceUnit, TargetUnit, MutableTarget;
	local XComGameState_Effect EffectState, PreviousEffect;
	local array<int> TargetIDs;
	local XComGameState NewGameState;
	local name PoisonType, ApplyResult;
	local int TargetID, Applied;

	if (!ParseAbilityActivation(GameState, EventSource, 'UT_Apothecary', AbilityContext, SourceUnit))
		return ELR_NoInterrupt;

	History = `XCOMHISTORY;

	foreach GameState.IterateByClassType(class'XComGameState_Effect', EffectState)
	{
		// Not the source of the effect state: the refresh of a poison keeps the source of the first one (XComGameState_Effect.OnRefresh), and this activation is the holder's anyway.
		if (EffectState.bRemoved)
			continue;

		PreviousEffect = XComGameState_Effect(EffectState.GetPreviousVersion());
		if (PreviousEffect != none && PreviousEffect.iTurnsRemaining >= EffectState.iTurnsRemaining)
			continue;
		if (!IsPoisonEffect(EffectState.GetX2Effect(), PoisonType))
			continue;

		TargetID = EffectState.ApplyEffectParameters.TargetStateObjectRef.ObjectID;
		TargetUnit = XComGameState_Unit(History.GetGameStateForObjectID(TargetID));
		if (TargetUnit != none && TargetUnit.IsAlive() && SourceUnit.IsEnemyUnit(TargetUnit) && !TargetUnit.IsImmuneToDamage(PoisonType) && TargetIDs.Find(TargetID) == INDEX_NONE)
			TargetIDs.AddItem(TargetID);
	}

	if (TargetIDs.Length == 0)
		return ELR_NoInterrupt;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Apothecary toxin");
	foreach TargetIDs(TargetID)
	{
		MutableTarget = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', TargetID));
		ApplyResult = class'UT_EffectHelpers'.static.ApplyAbilityEffect('UT_ApothecaryToxin', 0, SourceUnit, MutableTarget, NewGameState, AbilityContext);
		if (ApplyResult == 'AA_Success' || ApplyResult == 'AA_EffectRefreshed')
		{
			++Applied;
			`log("UniqueTraits : Apothecary --" @ MutableTarget.GetFullName() @ "poisoned (" $ PoisonType $ ") by" @ SourceUnit.GetFullName() @ ": toxin" @ ApplyResult,, 'UniqueTraits');
		}
	}

	if (Applied == 0)
	{
		History.CleanupPendingGameState(NewGameState);
		return ELR_NoInterrupt;
	}

	XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = BuildVisualization_ApothecaryToxin;
	`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}

static function BuildVisualization_ApothecaryToxin(XComGameState VisualizeGameState)
{
	class'UT_EffectHelpers'.static.AddEffectVisualization(VisualizeGameState, 'UT_ApothecaryToxin', 0);
}

//---------------------------------------------------------------------------------------
// HP
//---------------------------------------------------------------------------------------

static function bool ShiftsStats()
{
	return true;
}

// The HP malus, right away (a rookie included).
static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	// Defensive: a unit that had the trait before was cleared by OnClear, which already empties the ledger.
	ForgetShifts(MutableUnit);

	ApplyApothecaryHP(MutableUnit);
}

// The trait is already out of AcquiredTraits here: the HP go back to what they were, exactly.
static function OnClear(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	RevertShifts(MutableUnit);
}

// 'UnitRankUp': the base HP grow with the ranks, a malus that the floor held back may come in.
static function bool OnRankUp(XComGameState_Unit MutableUnit)
{
	return ApplyApothecaryHP(MutableUnit);
}

// The base stats were rebuilt by a respec: what the trait had put in them is gone.
static function OnStatsReset(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	ForgetShifts(MutableUnit);
	ApplyApothecaryHP(MutableUnit);
}

// Brings the HP to -APOTHECARY_HP_MALUS, as far as the floor allows: the base HP the soldier would have without the trait (the base minus the ledger) never go below
// APOTHECARY_MIN_HP because of it. Idempotent (the target minus the ledger). True if the unit changed.
static final function bool ApplyApothecaryHP(XComGameState_Unit MutableUnit)
{
	local float BaseWithoutTrait, Wanted;
	local bool bChanged;

	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(MutableUnit, 'UT_Apothecary'))
		return false;

	// A respec since the last shift: the ledger is forgotten first, or the base without the trait would be wrong.
	ForgetIfRespec(MutableUnit);

	BaseWithoutTrait = MutableUnit.GetBaseStat(eStat_HP) - GetStatLedger(MutableUnit, eStat_HP);
	Wanted = -FMin(float(Max(0, default.APOTHECARY_HP_MALUS)), FMax(0.0, BaseWithoutTrait - float(default.APOTHECARY_MIN_HP)));

	bChanged = ShiftStatTo(MutableUnit, eStat_HP, Wanted);
	if (bChanged)
		`log("UniqueTraits : Apothecary --" @ MutableUnit.GetFullName() @ "base HP without the trait" @ BaseWithoutTrait @ ": HP change" @ Wanted,, 'UniqueTraits');

	return bChanged;
}

//---------------------------------------------------------------------------------------
// Recovery time
//---------------------------------------------------------------------------------------

// 'CleanupTacticalMission' (CHL #96, BEFORE the end-of-mission health adjustment): for each squad holder, the wound (HighestHP - LowestHP) is made APOTHECARY_RECOVERY_PCT % longer,
// rounded to whole HP, with LWOTC Field Surgeon's guards (not dead / captured, not bleeding out now or earlier in the mission, actually wounded). A wound can grow up to a unit left
// with 1 HP, never to death. The time is not linear in HP (the game sizes it by wound severity bands) and the HP are whole: a very small wound may not change.
static function EventListenerReturn OnCleanupTacticalMission_Apothecary(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference SquadRef;
	local XComGameState_Unit SquadUnit, MutableUnit;
	local UnitValue BledOutValue;
	local int Wound, NewWound, OldLowest;

	if (GameState == none || default.APOTHECARY_RECOVERY_PCT <= 0)
		return ELR_NoInterrupt;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	foreach XComHQ.Squad(SquadRef)
	{
		SquadUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(SquadRef.ObjectID));
		if (SquadUnit == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SquadUnit, 'UT_Apothecary'))
			continue;

		MutableUnit = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', SquadUnit.ObjectID));
		if (MutableUnit.IsDead() || MutableUnit.bCaptured || MutableUnit.IsBleedingOut() || MutableUnit.GetUnitValue('UT_Apothecary_BledOut', BledOutValue))
			continue;
		if (MutableUnit.LowestHP <= 0 || MutableUnit.LowestHP >= MutableUnit.HighestHP)
			continue;

		Wound = MutableUnit.HighestHP - MutableUnit.LowestHP;
		NewWound = Clamp(Round(float(Wound) * float(100 + default.APOTHECARY_RECOVERY_PCT) / 100.0), 0, MutableUnit.HighestHP - 1);
		if (NewWound <= Wound)
			continue;

		OldLowest = MutableUnit.LowestHP;
		MutableUnit.LowestHP = MutableUnit.HighestHP - NewWound;

		`log("UniqueTraits : Apothecary --" @ MutableUnit.GetFullName() @ "wound" @ Wound @ "->" @ NewWound @ "HP (+" $ default.APOTHECARY_RECOVERY_PCT $ "%), LowestHP" @ OldLowest @ "->" @ MutableUnit.LowestHP,, 'UniqueTraits');
	}

	return ELR_NoInterrupt;
}

// Remembers that this soldier bled out during the mission (the status is cleared before the cleanup handler runs): the usual harsh recovery stays, as with Field Surgeon.
static function EventListenerReturn OnUnitBleedingOut_Apothecary(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit UnitState, MutableUnit;

	UnitState = XComGameState_Unit(EventData);
	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_Apothecary'))
		return ELR_NoInterrupt;

	MutableUnit = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', UnitState.ObjectID));
	MutableUnit.SetUnitFloatValue('UT_Apothecary_BledOut', 1, eCleanup_BeginTactical);

	return ELR_NoInterrupt;
}
