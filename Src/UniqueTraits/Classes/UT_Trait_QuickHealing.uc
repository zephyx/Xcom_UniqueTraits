//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_QuickHealing.uc
//  PURPOSE: Quick healing: extra damage taken, and no recovery time for what was healed in combat. Both vanilla and LWOTC size the
//           post-mission wound (XComGameState_Unit.EndTacticalHealthMod) from the LOWEST HP the soldier reached, which never rises
//           back by itself, so life healed in combat would still count. A holder who did not bleed out (the 'UnitBleedingOut'
//           listener marks it) gets his end-of-mission HP described as the lowest: only the life still missing at the end counts as
//           a wound. Done in a handler of the 'CleanupTacticalMission' event (CHL, fired before EndTacticalHealthMod).
//---------------------------------------------------------------------------------------
class UT_Trait_QuickHealing extends UT_TraitBase config(UniqueTraits);

var config float QUICKHEALING_DAMAGE_TAKEN_MULT;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(QuickHealing());

	return Templates;
}

// Quick healing: +25% damage taken (X2Effect_UT_DamageTakenMult: a percentage, applied in CHL's post-default hook) +
// the recovery-time mechanic (OnCleanupTacticalMission_QuickHealing below).
static function X2AbilityTemplate QuickHealing()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_DamageTakenMult DamageTakenEffect;

	Template = PurePassive('UT_QuickHealing', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	DamageTakenEffect = new class'X2Effect_UT_DamageTakenMult';
	DamageTakenEffect.EffectName = 'UT_QuickHealing_DamageTaken';
	DamageTakenEffect.DamageMultiplier = default.QUICKHEALING_DAMAGE_TAKEN_MULT;
	DamageTakenEffect.BuildPersistentEffect(1, true, false);
	DamageTakenEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(DamageTakenEffect);

	return Template;
}

// 'CleanupTacticalMission' (CHL #96, fired with the cleanup state BEFORE the end-of-mission health adjustment): every Quick healing
// holder of the squad gets his end-of-mission HP described as the lowest.
static function EventListenerReturn OnCleanupTacticalMission_QuickHealing(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference SquadRef;
	local XComGameState_Unit SquadUnit, MutableUnit;

	if (GameState == none)
		return ELR_NoInterrupt;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	foreach XComHQ.Squad(SquadRef)
	{
		SquadUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(SquadRef.ObjectID));
		if (SquadUnit == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SquadUnit, 'UT_QuickHealing'))
			continue;

		MutableUnit = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', SquadUnit.ObjectID));
		ApplyEndOfMissionHealing(MutableUnit);
	}

	return ELR_NoInterrupt;
}

// UnitState must be modifiable (a pending state object).
static final function ApplyEndOfMissionHealing(XComGameState_Unit UnitState)
{
	local UnitValue BledOutValue;
	local XComGameState_Unit Probe;
	local int TacticalMax, EndHP, HealedInCombat, NewMissingHP, Guard;

	if (UnitState == none || UnitState.IsDead() || UnitState.IsBleedingOut() || UnitState.LowestHP <= 0)
		return;

	// Bled out at least once during the mission (UT_Trait_QuickHealing.OnUnitBleedingOut): the usual harsh penalty stays.
	if (UnitState.GetUnitValue('UT_QuickHealing_BledOut', BledOutValue))
		return;

	// The unit's tactical max HP at the start of the mission, bonus HP (armor...) included: HighestHP is the HP it started with
	// (plus such bonuses) and MissingHP what it was missing then. By now the bonus may be gone from its max HP, and the current HP
	// clamped to the new max (a unit missing 1 of 12 reads as a full 11/11; LW's perks warn that the current HP cannot be trusted
	// here for the same reason), so the HP at the end of the mission is read from the newest version of the unit that still has
	// that full max (history chain).
	TacticalMax = UnitState.HighestHP + UnitState.MissingHP;
	EndHP = -1;
	Probe = UnitState;
	while (Probe != none && Guard < 20000)
	{
		if (int(Probe.GetMaxStat(eStat_HP)) >= TacticalMax)
		{
			EndHP = int(Probe.GetCurrentStat(eStat_HP));
			break;
		}
		Probe = XComGameState_Unit(Probe.GetPreviousVersion());
		++Guard;
	}

	if (EndHP < 0)
	{
		`log("UniqueTraits [WARN] : Quick healing --" @ UnitState.GetFullName() @ "no unit version with a max HP of" @ TacticalMax @ "found, left untouched",, 'UniqueTraits');
		return;
	}

	// EndTacticalHealthMod sizes the wound from HighestHP - LowestHP and then keeps the unit MissingHP below its max: describe the end
	// of the mission to it. HighestHP does not rise when the unit is healed above its starting HP, so it is set to the tactical max;
	// MissingHP can only go down (a unit that started wounded and was healed in combat is no longer missing that HP).
	EndHP = Clamp(EndHP, UnitState.LowestHP, TacticalMax);
	HealedInCombat = EndHP - UnitState.LowestHP;
	NewMissingHP = Min(UnitState.MissingHP, TacticalMax - EndHP);
	if (HealedInCombat == 0 && TacticalMax == UnitState.HighestHP && NewMissingHP == UnitState.MissingHP)
		return;

	`log("UniqueTraits : Quick healing --" @ UnitState.GetFullName() @ "LowestHP" @ UnitState.LowestHP @ "->" @ EndHP @ "| HighestHP" @ UnitState.HighestHP @ "->" @ TacticalMax
		@ "| MissingHP" @ UnitState.MissingHP @ "->" @ NewMissingHP,, 'UniqueTraits');
	// LW's own update (Smart Macrophages: LowestHP = Min(HighestHP, LowestHP + heal)), with the amount healed in combat as the heal.
	UnitState.HighestHP = TacticalMax;
	UnitState.LowestHP = Min(UnitState.HighestHP, UnitState.LowestHP + HealedInCombat);
	UnitState.MissingHP = NewMissingHP;
}

// Quick healing: remembers (for the rest of the mission) that this soldier bled out at least
// once, so ApplyEndOfMissionHealing keeps the usual harsh recovery-time penalty.
static function EventListenerReturn OnUnitBleedingOut(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit UnitState, MutableUnit;

	UnitState = XComGameState_Unit(EventData);
	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_QuickHealing'))
		return ELR_NoInterrupt;

	MutableUnit = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', UnitState.ObjectID));
	MutableUnit.SetUnitFloatValue('UT_QuickHealing_BledOut', 1, eCleanup_BeginTactical);

	return ELR_NoInterrupt;
}
