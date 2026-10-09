//---------------------------------------------------------------------------------------
//  FILE:   UT_TraitBase.uc
//  PURPOSE: Base class of every per-trait class (UT_Trait_<Name>.uc). An X2Ability subclass is
//           auto-discovered as an X2DataSet, so each trait class returns its own ability
//           template(s) from CreateTemplates(); this base does not override it (X2DataSet's own is empty). The hooks below are all
//           no-ops by default; a trait overrides only the ones it needs. They are dispatched from
//           X2DownloadableContentInfo_UniqueTraits (GrantTraitToUnit / ClearAssignedTrait) and
//           X2EventListener_UniqueTraits (OnUnitRankUp) through
//           UniqueTraits_TraitConfig.GetTraitClass(TraitID).
//---------------------------------------------------------------------------------------
class UT_TraitBase extends X2Ability config(UniqueTraits);

// Extra eligibility condition for the draw (besides bEnabled/RequiredMods in the ini): a trait whose mechanic could not
// apply in the current game returns false (policy: exclude, don't degrade). See UniqueTraits_TraitConfig.IsTraitEligible.
static function bool IsEligible()
{
	return true;
}

// Called by GrantTraitToUnit once the TraitID is in AcquiredTraits, BEFORE the generic AWCAbilities grant.
static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
}

// Called by ClearAssignedTrait once the TraitID is out of AcquiredTraits, BEFORE the generic AWCAbilities sweep.
static function OnClear(XComGameState_Unit MutableUnit)
{
}

// Called from 'UnitRankUp' for every rank gained after the one that granted the trait (ranks > 0 only).
static function OnRankUp(XComGameState_Unit UnitState)
{
}

// Adds (or, with a negative Delta, removes) an amount to BOTH the max and the current value of a stat: a genuine,
// permanent change. Both Get*Stat are captured BEFORE SetBaseMaxStat, which resyncs the current stat as a side effect.
static final function ShiftStat(XComGameState_Unit UnitState, ECharStatType Stat, float Delta)
{
	local float NewMax, NewCurrent;

	NewMax = UnitState.GetMaxStat(Stat) + Delta;
	NewCurrent = UnitState.GetCurrentStat(Stat) + Delta;

	UnitState.SetBaseMaxStat(Stat, NewMax);
	UnitState.SetCurrentStat(Stat, NewCurrent);
}

// Label shown in the shot breakdown (hit chance tooltip) for a trait's aim modifier: the effect's display name
// (SetDisplayInfo, i.e. the trait's name) rather than its internal EffectName ("UT_PACIFIST_ORGANICCOMBAT").
static final function string GetShotModifierLabel(X2Effect_Persistent Effect)
{
	if (Effect.FriendlyName != "")
		return Effect.FriendlyName;

	return string(Effect.EffectName);
}

// Called by X2DownloadableContentInfo_UniqueTraits.OnPostMission (CHL #212) on EVERY trait class once a mission is over and committed,
// before the After Action screen: a trait that has something to do then checks for its own holders (supplies, upgrades...).
static function OnPostMission()
{
}

// Called by X2DownloadableContentInfo_UniqueTraits.CanAddItemToInventory_CH_Improved for the unit's own trait: return true
// (and set DisabledReason) to forbid equipping ItemTemplate in Slot. That hook only stops FUTURE equips, so a trait that
// bans items strips the ones already carried in OnGrant.
static function bool IsItemBlocked(EInventorySlot Slot, X2ItemTemplate ItemTemplate, out string DisabledReason)
{
	return false;
}

// Shared prelude of the 'OnGetItemRange' handlers (All in arms, Scout): false unless the event is about a weapon
// template used by an ability with a known owner.
static final function bool ParseItemRangeEvent(Object EventData, Object EventSource, out XComLWTuple Tuple, out X2WeaponTemplate ItemTemplate, out XComGameState_Unit OwnerUnit)
{
	local XComGameState_Item ItemState;
	local XComGameState_Ability AbilityState;

	Tuple = XComLWTuple(EventData);
	ItemState = XComGameState_Item(EventSource);
	if (Tuple == none || ItemState == none)
		return false;

	ItemTemplate = X2WeaponTemplate(ItemState.GetMyTemplate());
	if (ItemTemplate == none)
		return false;

	AbilityState = XComGameState_Ability(Tuple.Data[2].o);
	if (AbilityState == none)
		return false;
	OwnerUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(AbilityState.OwnerStateObject.ObjectID));
	return OwnerUnit != none;
}

// A hidden ability template that only holds effects applied "by hand" (see UT_EffectHelpers): never granted to any unit, no input, no
// visualization. The caller adds its effects with AddTargetEffect (their index is the one given to UT_EffectHelpers.ApplyAbilityEffect).
static final function X2AbilityTemplate HiddenEffectHolder(name TemplateName)
{
	local X2AbilityTemplate Template;

	`CREATE_X2ABILITY_TEMPLATE(Template, TemplateName);

	Template.IconImage = "img:///UILibrary_PerkIcons.UIPerk_standard";
	Template.AbilitySourceName = 'eAbilitySource_Perk';
	Template.eAbilityIconBehaviorHUD = eAbilityIconBehavior_NeverShow;
	Template.Hostility = eHostility_Neutral;
	Template.bDontDisplayInAbilitySummary = true;
	Template.bDisplayInUITooltip = false;
	Template.bDisplayInUITacticalText = false;

	Template.AbilityToHitCalc = default.DeadEye;
	Template.AbilityTargetStyle = default.SimpleSingleTarget;
	Template.AbilityTriggers.AddItem(new class'X2AbilityTrigger_Placeholder');   // validation wants a trigger ("is invalid: no Triggers"); never fires, never granted
	Template.BuildNewGameStateFn = TypicalAbility_BuildGameState;

	return Template;
}
