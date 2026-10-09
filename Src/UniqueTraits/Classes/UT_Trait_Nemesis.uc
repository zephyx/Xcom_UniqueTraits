//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Nemesis.uc
//  PURPOSE: Nemesis: every kill of an enemy permanently gives the holder +NEMESIS_AIM_PER_KILL aim against that TYPE of enemy (character template
//           group) and gives that type +NEMESIS_DEFENSE_PER_KILL chance to hit him (a defense malus), capped at NEMESIS_MAX_AIM / NEMESIS_MAX_DEFENSE.
//           - 'UnitDied': counts the kill in the holder's UnitValue UT_Nemesis_<group> (eCleanup_Never: it survives the missions), like Iridar's
//             Bounty Hunter "Headhunter". Only a kill made by an ability fired with a weapon of the PRIMARY, SECONDARY or PISTOL slot counts (no
//             grenade, heavy weapon, damage over time, explosion of the environment...). Summoned units count, their
//             type being their own character group. Not counted: allies of the holder and ghost copies. The tally stops once both caps are reached.
//           - The to-hit modifiers are X2Effect_UT_Nemesis (the passive's effect).
//           - A "Nemesis" flyover on the killer, appended to the visualization of the kill (UT_Nemesis_KillSerial changes on each counted kill).
//---------------------------------------------------------------------------------------
class UT_Trait_Nemesis extends UT_TraitBase config(UniqueTraits);

var config int NEMESIS_AIM_PER_KILL, NEMESIS_MAX_AIM, NEMESIS_DEFENSE_PER_KILL, NEMESIS_MAX_DEFENSE;
var localized string NEMESIS_FLYOVER;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Nemesis());

	return Templates;
}

static function X2AbilityTemplate Nemesis()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_Nemesis NemesisEffect;

	Template = PurePassive('UT_Nemesis', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	NemesisEffect = new class'X2Effect_UT_Nemesis';
	NemesisEffect.AimPerKill = default.NEMESIS_AIM_PER_KILL;
	NemesisEffect.MaxAim = default.NEMESIS_MAX_AIM;
	NemesisEffect.DefensePerKill = default.NEMESIS_DEFENSE_PER_KILL;
	NemesisEffect.MaxDefense = default.NEMESIS_MAX_DEFENSE;
	NemesisEffect.BuildPersistentEffect(1, true, false);
	NemesisEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(NemesisEffect);

	return Template;
}

// Number of kills of one type after which both bonuses are at their cap.
static final function int GetKillCap()
{
	local int AimKills, DefenseKills;

	if (default.NEMESIS_AIM_PER_KILL > 0)
		AimKills = (default.NEMESIS_MAX_AIM + default.NEMESIS_AIM_PER_KILL - 1) / default.NEMESIS_AIM_PER_KILL;
	if (default.NEMESIS_DEFENSE_PER_KILL > 0)
		DefenseKills = (default.NEMESIS_MAX_DEFENSE + default.NEMESIS_DEFENSE_PER_KILL - 1) / default.NEMESIS_DEFENSE_PER_KILL;

	return Max(AimKills, DefenseKills);
}

// True for the weapons whose kills count: primary, secondary and pistol slots (the pistol slot is CHL's / LWOTC's own slot).
static final function bool IsCountedWeaponSlot(EInventorySlot Slot)
{
	return Slot == eInvSlot_PrimaryWeapon || Slot == eInvSlot_SecondaryWeapon || Slot == eInvSlot_Pistol;
}

// 'UnitDied' (EventSource = the dead unit, ELD_Immediate: the tally goes into the kill's own game state). The killer is the source of the ability
// that killed, and that ability must have been fired with a weapon of a counted slot.
static function EventListenerReturn OnUnitDied_Nemesis(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateHistory History;
	local XComGameState_Unit DeadUnit, Killer;
	local XComGameState_Item Weapon;
	local XComGameStateContext_Ability AbilityContext;
	local name GroupName, ValueName;
	local int KillerID, Kills;

	DeadUnit = XComGameState_Unit(EventSource);
	if (DeadUnit == none)
		return ELR_NoInterrupt;

	History = `XCOMHISTORY;

	// No ability context (damage over time, environment...) or no weapon behind the ability (grenade from a utility slot is a weapon too,
	// but its slot is not counted): no kill for the tally.
	AbilityContext = XComGameStateContext_Ability(GameState.GetContext());
	if (AbilityContext == none)
		return ELR_NoInterrupt;
	KillerID = AbilityContext.InputContext.SourceObject.ObjectID;

	Weapon = XComGameState_Item(History.GetGameStateForObjectID(AbilityContext.InputContext.ItemObject.ObjectID));
	if (Weapon == none || !IsCountedWeaponSlot(Weapon.InventorySlot))
		return ELR_NoInterrupt;

	Killer = XComGameState_Unit(History.GetGameStateForObjectID(KillerID));
	if (Killer == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Killer, 'UT_Nemesis'))
		return ELR_NoInterrupt;

	if (!Killer.IsEnemyUnit(DeadUnit) || DeadUnit.GhostSourceUnit.ObjectID > 0)
		return ELR_NoInterrupt;

	GroupName = DeadUnit.GetMyTemplateGroupName();
	if (GroupName == '')
		return ELR_NoInterrupt;

	ValueName = Name(class'X2Effect_UT_Nemesis'.default.UVPrefix $ GroupName);
	Kills = int(GetUnitFloat(Killer, ValueName));
	if (Kills >= GetKillCap())
		return ELR_NoInterrupt;

	Killer = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', KillerID));
	++Kills;
	Killer.SetUnitFloatValue(ValueName, Kills, eCleanup_Never);

	// Marks for the flyover: a counter that changes on every counted kill, and the bonuses of the type just killed.
	Killer.SetUnitFloatValue('UT_Nemesis_KillSerial', GetUnitFloat(Killer, 'UT_Nemesis_KillSerial') + 1, eCleanup_BeginTactical);
	Killer.SetUnitFloatValue('UT_Nemesis_LastAim', Min(Kills * default.NEMESIS_AIM_PER_KILL, default.NEMESIS_MAX_AIM), eCleanup_BeginTactical);
	Killer.SetUnitFloatValue('UT_Nemesis_LastDefense', Min(Kills * default.NEMESIS_DEFENSE_PER_KILL, default.NEMESIS_MAX_DEFENSE), eCleanup_BeginTactical);

	GameState.GetContext().PostBuildVisualizationFn.AddItem(BuildVisualization_NemesisFlyover);

	return ELR_NoInterrupt;
}

// UT_TraitBase.OnClear: forgets every tally (one UnitValue per character group).
static function OnClear(XComGameState_Unit MutableUnit)
{
	local X2CharacterTemplateManager CharacterManager;
	local X2DataTemplate DataTemplate;
	local X2CharacterTemplate CharacterTemplate;
	local name GroupName;

	CharacterManager = class'X2CharacterTemplateManager'.static.GetCharacterTemplateManager();
	foreach CharacterManager.IterateTemplates(DataTemplate, none)
	{
		CharacterTemplate = X2CharacterTemplate(DataTemplate);
		if (CharacterTemplate == none)
			continue;

		GroupName = CharacterTemplate.CharacterGroupName;
		if (GroupName == '')
			GroupName = CharacterTemplate.DataName;
		MutableUnit.ClearUnitValue(Name(class'X2Effect_UT_Nemesis'.default.UVPrefix $ GroupName));
	}

	MutableUnit.ClearUnitValue('UT_Nemesis_KillSerial');
	MutableUnit.ClearUnitValue('UT_Nemesis_LastAim');
	MutableUnit.ClearUnitValue('UT_Nemesis_LastDefense');
}

// PostBuildVisualizationFn of the kill's context: the killer whose UT_Nemesis_KillSerial went up in that state gets the flyover.
static function BuildVisualization_NemesisFlyover(XComGameState VisualizeGameState)
{
	local XComGameState_Unit UnitState, PreviousState;
	local string Message;

	foreach VisualizeGameState.IterateByClassType(class'XComGameState_Unit', UnitState)
	{
		if (!class'UT_EffectHelpers'.static.ValueIncreased(UnitState, 'UT_Nemesis_KillSerial', PreviousState))
			continue;

		Message = Repl(default.NEMESIS_FLYOVER, "%AIM", string(int(GetUnitFloat(UnitState, 'UT_Nemesis_LastAim'))));
		Message = Repl(Message, "%DEF", string(int(GetUnitFloat(UnitState, 'UT_Nemesis_LastDefense'))));
		class'UT_EffectHelpers'.static.AddUnitFlyover(VisualizeGameState, UnitState, PreviousState, Message);
	}
}
