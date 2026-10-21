//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_GiveMeMore.uc
//  PURPOSE: Give me more: -10 defense, +10 dodge (plain stat passive) and the end-of-mission wound is computed as if the soldier had lost
//           3 HP less: the mechanism of LWOTC's Field Surgeon (LowestHP raised, see OnCleanupTacticalMission_GiveMeMore).
//---------------------------------------------------------------------------------------
class UT_Trait_GiveMeMore extends UT_TraitBase config(UniqueTraits);

var config int GIVEMEMORE_DEFENSE_MALUS, GIVEMEMORE_DODGE_BONUS, GIVEMEMORE_WOUND_HP_REDUCTION;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(GiveMeMore());

	return Templates;
}

// Event registrations (X2EventListener_UniqueTraits.CreateTacticalListeners calls this for every trait of the pool that is not disabled).
static function OnCreateTacticalListeners(CHEventListenerTemplate Template)
{
	// Give me more: same moment, Field Surgeon's mechanism (and the bleeding-out mark that makes it skip a soldier who bled out).
	Template.AddCHEvent('CleanupTacticalMission', OnCleanupTacticalMission_GiveMeMore, ELD_Immediate, 50);
	Template.AddCHEvent('UnitBleedingOut', OnUnitBleedingOut_GiveMeMore, ELD_Immediate, 50);
}

static function X2AbilityTemplate GiveMeMore()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;

	Template = PurePassive('UT_GiveMeMore', "img:///UniqueTraits_Icons.UT_GiveMeMore", true);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_GiveMeMore';
	StatEffect.BuildPersistentEffect(1, true, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_Defense, -default.GIVEMEMORE_DEFENSE_MALUS);
	StatEffect.AddPersistentStatChange(eStat_Dodge, default.GIVEMEMORE_DODGE_BONUS);
	Template.AddTargetEffect(StatEffect);

	Template.SetUIStatMarkup(class'XLocalizedData'.default.DefenseLabel, eStat_Defense, -default.GIVEMEMORE_DEFENSE_MALUS);
	Template.SetUIStatMarkup(class'XLocalizedData'.default.DodgeLabel, eStat_Dodge, default.GIVEMEMORE_DODGE_BONUS);

	return Template;
}

// 'CleanupTacticalMission' (CHL #96, fired with the cleanup state BEFORE the end-of-mission health adjustment): every Give me more holder of the
// squad gets his wound reduced, with the mechanism of LWOTC's Field Surgeon (X2Effect_FieldSurgeon.ApplyFieldSurgeon): LowestHP, from which
// EndTacticalHealthMod sizes the wound, is raised (here by GIVEMEMORE_WOUND_HP_REDUCTION, never above HighestHP), as is the current HP.
// Same guards as Field Surgeon: not dead, not captured, not bleeding out now or earlier in the mission, and actually wounded.
static function EventListenerReturn OnCleanupTacticalMission_GiveMeMore(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference SquadRef;
	local XComGameState_Unit SquadUnit, MutableUnit;
	local UnitValue BledOutValue;
	local int OldLowest, Raise;

	if (GameState == none)
		return ELR_NoInterrupt;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	foreach XComHQ.Squad(SquadRef)
	{
		SquadUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(SquadRef.ObjectID));
		if (SquadUnit == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SquadUnit, 'UT_GiveMeMore'))
			continue;

		MutableUnit = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', SquadUnit.ObjectID));
		if (MutableUnit.IsDead() || MutableUnit.bCaptured || MutableUnit.IsBleedingOut() || MutableUnit.GetUnitValue('UT_GiveMeMore_BledOut', BledOutValue))
			continue;
		if (MutableUnit.LowestHP <= 0 || MutableUnit.LowestHP >= MutableUnit.HighestHP)
			continue;

		OldLowest = MutableUnit.LowestHP;
		MutableUnit.LowestHP = Min(MutableUnit.HighestHP, MutableUnit.LowestHP + default.GIVEMEMORE_WOUND_HP_REDUCTION);
		Raise = MutableUnit.LowestHP - OldLowest;

		// Field Surgeon also raises the current HP (not above the max), the value some of the end-of-mission code reads.
		if (MutableUnit.GetCurrentStat(eStat_HP) < MutableUnit.GetMaxStat(eStat_HP))
			MutableUnit.ModifyCurrentStat(eStat_HP, Raise);

		`log("UniqueTraits : Give me more --" @ MutableUnit.GetFullName() @ "LowestHP" @ OldLowest @ "->" @ MutableUnit.LowestHP @ "(HighestHP" @ MutableUnit.HighestHP $ ")",, 'UniqueTraits');
	}

	return ELR_NoInterrupt;
}

// Give me more: remembers that this soldier bled out during the mission (the status is cleared before the cleanup handler runs), so the
// reduction is skipped, as Field Surgeon does.
static function EventListenerReturn OnUnitBleedingOut_GiveMeMore(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit UnitState, MutableUnit;

	UnitState = XComGameState_Unit(EventData);
	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_GiveMeMore'))
		return ELR_NoInterrupt;

	MutableUnit = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', UnitState.ObjectID));
	MutableUnit.SetUnitFloatValue('UT_GiveMeMore_BledOut', 1, eCleanup_BeginTactical);

	return ELR_NoInterrupt;
}
