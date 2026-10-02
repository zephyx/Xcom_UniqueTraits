//---------------------------------------------------------------------------------------
//  FILE:   X2Ability_UniqueTraits_LWOTC.uc
//  PURPOSE: Traits that only make sense with LongWarOfTheChosen active (RequiredMods in
//           Config/XComUniqueTraits.ini) -- Bribe, Stay focus, Smoker, Born to be chief, Swordsman. Built
//           entirely from vanilla/CHL classes: this project has no compile-time visibility into
//           LW_Overhaul's own package, so nothing here may reference an LW_Overhaul class
//           directly, even though the traits themselves are gated to only be drawn when that mod
//           is active. Where a trait's effect needs to interact with an LWOTC-specific system
//           (Bribe's infiltration penalty, Stay focus's/Smoker's fatigue malus, Born to be
//           chief's officer rank query), it does so either through a config entry LWOTC's own
//           code reads by ability name (Bribe), by independently reimplementing the same public
//           vanilla primitive LWOTC's own feature is built on (Stay focus/Smoker), or by
//           triggering LWOTC's own public blind-tuple query event and reading the answer back
//           (Born to be chief)
//---------------------------------------------------------------------------------------
class X2Ability_UniqueTraits_LWOTC extends X2Ability config(UniqueTraits);

var config int STAYFOCUS_AIM_BONUS, STAYFOCUS_CRIT_BONUS;
var config int STAYFOCUS_RADIUS_TILES;
var config int STAYFOCUS_COOLDOWN;
var config name SMOKER_GRENADE_ITEM_NAME;
var config int SMOKER_GRENADE_COUNT;
var config int BORNTOBECHIEF_AIM_DODGE_WILL_BASE;
var config int BORNTOBECHIEF_AIM_DODGE_WILL_PER_RANK;
var config array<int> SWORDSMAN_MELEE_BONUS_BY_TIER;
var config int SWORDSMAN_FIREARM_DAMAGE_REDUCTION;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Bribe());
	Templates.AddItem(StayFocus());
	Templates.AddItem(Smoker());
	Templates.AddItem(BornToBeChief());
	Templates.AddItem(Swordsman());

	return Templates;
}

// Bribe: this passive is just the icon holder. The +20 monthly supplies bonus is implemented by
// X2EventListener_UniqueTraits.OnOverrideSupplyDrop (vanilla/CHL event, no LWOTC dependency).
// The infiltration penalty is entirely LWOTC's own doing: Config/XComLW_InfiltrationSettings.ini
// declares +AbilityCovertness=(AbilityName="UT_Bribe", IndividualMultiplier=1.20) under
// LW_Overhaul.XComGameState_LWPersistentSquad, and LWOTC's own GetSoldierCovertness reads that
// config and checks HasSoldierAbility('UT_Bribe') itself
static function X2AbilityTemplate Bribe()
{
	local X2AbilityTemplate Template;

	Template = PurePassive('UT_Bribe', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	return Template;
}

// Stay focus: free action (STAYFOCUS_COOLDOWN-turn cooldown) that grants nearby allies (not
// self) +10 Aim/+5 Crit until their next turn. The fatigue malus ("doubles per-turn fatigue
// will loss") is NOT implemented here (see X2EventListener_UniqueTraits.OnPlayerTurnEnded_FatigueDoubling
// for why (no compile-time LW_Overhaul dependency allowed) and how.
static function X2AbilityTemplate StayFocus()
{
	local X2AbilityTemplate Template;
	local X2AbilityCost_ActionPoints ActionPointCost;
	local X2AbilityCooldown Cooldown;
	local X2AbilityMultiTarget_Radius RadiusMultiTarget;
	local X2Condition_UnitProperty AllyCondition;
	local X2Condition_UnitStatCheck WillCheck;
	local X2Effect_PersistentStatChange StatEffect;

	`CREATE_X2ABILITY_TEMPLATE(Template, 'UT_StayFocus');

	Template.IconImage = "img:///UILibrary_PerkIcons.UIPerk_standard";
	Template.AbilitySourceName = 'eAbilitySource_Perk';
	Template.Hostility = eHostility_Defensive;
	Template.AbilityToHitCalc = default.DeadEye;
	Template.AbilityTargetStyle = default.SelfTarget;

	// Unusable once the user can't pay its fixed Will cost (X2EventListener_UniqueTraits.STAYFOCUS_WILL_LOSS).
	WillCheck = new class'X2Condition_UnitStatCheck';
	WillCheck.AddCheckStat(eStat_Will, class'X2EventListener_UniqueTraits'.default.STAYFOCUS_WILL_LOSS, eCheck_GreaterThanOrEqual);
	Template.AbilityShooterConditions.AddItem(WillCheck);

	ActionPointCost = new class'X2AbilityCost_ActionPoints';
	ActionPointCost.bFreeCost = true;
	Template.AbilityCosts.AddItem(ActionPointCost);

	Cooldown = new class'X2AbilityCooldown';
	Cooldown.iNumTurns = default.STAYFOCUS_COOLDOWN;
	Template.AbilityCooldown = Cooldown;

	RadiusMultiTarget = new class'X2AbilityMultiTarget_Radius';
	RadiusMultiTarget.fTargetRadius = default.STAYFOCUS_RADIUS_TILES * class'XComWorldData'.const.WORLD_StepSize * class'XComWorldData'.const.WORLD_UNITS_TO_METERS_MULTIPLIER;
	RadiusMultiTarget.bExcludeSelfAsTargetIfWithinRadius = true;
	// The targeting UI can't conform to partial cover, and without this the zone (and its targets) is
	// clipped by it like a smoke grenade's; vanilla does the same (X2Ability_DefaultAbilitySet.uc:2319).
	RadiusMultiTarget.bIgnoreBlockingCover = true;
	Template.AbilityMultiTargetStyle = RadiusMultiTarget;

	AllyCondition = new class'X2Condition_UnitProperty';
	AllyCondition.ExcludeDead = true;
	AllyCondition.ExcludeHostileToSource = true;
	AllyCondition.ExcludeFriendlyToSource = false;
	Template.AbilityMultiTargetConditions.AddItem(AllyCondition);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_StayFocus_Buff';
	StatEffect.BuildPersistentEffect(1, false, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_Offense, default.STAYFOCUS_AIM_BONUS);
	StatEffect.AddPersistentStatChange(eStat_CritChance, default.STAYFOCUS_CRIT_BONUS);
	Template.AddMultiTargetEffect(StatEffect);

	Template.AbilityTriggers.AddItem(default.PlayerInputTrigger);

	Template.BuildNewGameStateFn = TypicalAbility_BuildGameState;
	Template.BuildVisualizationFn = TypicalAbility_BuildVisualization;

	return Template;
}

// Smoker: 2 free smoke grenades. "Doesn't end turn when thrown" is
// X2AbilityCost_UT_SmokeThrow, spliced into the shared ThrowGrenade template by
// X2DownloadableContentInfo_UniqueTraits.OnPostTemplatesCreated (see that class). Regain Will when
// standing near the smoke grenade impact and the fatigue-doubling malus are both handled by
// X2EventListener_UniqueTraits.OnPlayerTurnEnded_FatigueDoubling.
static function X2AbilityTemplate Smoker()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_TemporaryItem GrenadeEffect;

	Template = PurePassive('UT_Smoker', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	GrenadeEffect = new class'X2Effect_UT_TemporaryItem';
	GrenadeEffect.EffectName = 'UT_Smoker_FreeSmokeGrenades';
	GrenadeEffect.ItemName = default.SMOKER_GRENADE_ITEM_NAME;
	GrenadeEffect.ItemInventorySlot = eInvSlot_Utility;
	GrenadeEffect.Quantity = default.SMOKER_GRENADE_COUNT;
	// One icon with a stack of N (added to any smoke grenade the holder already carries) instead of N separate icons.
	GrenadeEffect.bStackOnExisting = true;
	GrenadeEffect.BuildPersistentEffect(1, true, false);
	GrenadeEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(GrenadeEffect);

	return Template;
}

// Born to be chief: fixed -12 Aim/Dodge/Will baseline, +4 to each per LWOTC officer rank held.
// A plain X2Effect_PersistentStatChange is mission-scoped
// (X2Effect_ModifyStats.UnitEndedTacticalPlay un-applies it at the end of every tactical mission,
// since it's re-applied fresh each time via PurePassive's UnitPostBeginPlayTrigger), so the fixed
// part would never actually lower the soldier's real Max Will/Aim/Dodge between missions.
// Also grants the LW ability 'QuickStudy'.
static function X2AbilityTemplate BornToBeChief()
{
	local X2AbilityTemplate Template;

	Template = PurePassive('UT_BornToBeChief', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	return Template;
}

// Swordsman: melee damage and armor pierce scale with the melee weapon's Tier; -1 damage on
// firearms. LWOTC-only because the pistol restriction targets LWOTC's own pistol slot (the slot +
// CPS pistol row block live in X2DownloadableContentInfo_UniqueTraits.CanAddItemToInventory_CH_Improved
// / X2EventListener_UniqueTraits).
static function X2AbilityTemplate Swordsman()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_Swordsman SwordEffect;

	Template = PurePassive('UT_Swordsman', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	SwordEffect = new class'X2Effect_UT_Swordsman';
	SwordEffect.EffectName = 'UT_Swordsman_Effect';
	SwordEffect.MeleeBonusByTier = default.SWORDSMAN_MELEE_BONUS_BY_TIER;
	SwordEffect.FirearmDamageReduction = default.SWORDSMAN_FIREARM_DAMAGE_REDUCTION;
	SwordEffect.BuildPersistentEffect(1, true, false);
	SwordEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(SwordEffect);

	return Template;
}
