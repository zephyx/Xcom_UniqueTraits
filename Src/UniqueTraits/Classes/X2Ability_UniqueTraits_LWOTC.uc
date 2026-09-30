//---------------------------------------------------------------------------------------
//  FILE:   X2Ability_UniqueTraits_LWOTC.uc
//  PURPOSE: Traits that only make sense with LongWarOfTheChosen active (RequiredMods in
//           Config/XComUniqueTraits.ini) -- Bribe, Stay focus, Smoker, Born to be chief. Built
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

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Bribe());
	Templates.AddItem(StayFocus());
	Templates.AddItem(Smoker());
	Templates.AddItem(BornToBeChief());

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
	local X2Effect_PersistentStatChange StatEffect;

	`CREATE_X2ABILITY_TEMPLATE(Template, 'UT_StayFocus');

	Template.IconImage = "img:///UILibrary_PerkIcons.UIPerk_standard";
	Template.AbilitySourceName = 'eAbilitySource_Perk';
	Template.Hostility = eHostility_Defensive;
	Template.AbilityToHitCalc = default.DeadEye;
	Template.AbilityTargetStyle = default.SelfTarget;

	ActionPointCost = new class'X2AbilityCost_ActionPoints';
	ActionPointCost.bFreeCost = true;
	Template.AbilityCosts.AddItem(ActionPointCost);

	Cooldown = new class'X2AbilityCooldown';
	Cooldown.iNumTurns = default.STAYFOCUS_COOLDOWN;
	Template.AbilityCooldown = Cooldown;

	RadiusMultiTarget = new class'X2AbilityMultiTarget_Radius';
	RadiusMultiTarget.fTargetRadius = default.STAYFOCUS_RADIUS_TILES * class'XComWorldData'.const.WORLD_StepSize * class'XComWorldData'.const.WORLD_UNITS_TO_METERS_MULTIPLIER;
	RadiusMultiTarget.bExcludeSelfAsTargetIfWithinRadius = true;
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
// X2DownloadableContentInfo_UniqueTraits.OnPostTemplatesCreated (see that class). Will regen
// while standing in smoke and the fatigue-doubling malus are both handled by
// X2EventListener_UniqueTraits.OnPlayerTurnEnded_FatigueDoubling / OnPlayerTurnEnded_
// SmokerWillRegen, since neither is naturally expressible as an effect on this ability.
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
	GrenadeEffect.BuildPersistentEffect(1, true, false);
	GrenadeEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	Template.AddTargetEffect(GrenadeEffect);

	return Template;
}

// Born to be chief: fixed -12 Aim/Dodge/Will baseline (this function), +4 to each per LWOTC
// officer rank held (dynamic, not an effect on this ability at all. Officer rank changes over
// the campaign, so it's applied/recomputed directly on the unit's stats via
// X2DownloadableContentInfo_UniqueTraits.ApplyBornToBeChiefRankScaling, the same
// precompute-then-Set pattern ApplyNerdRankScaling uses for its own per-rank scaling). Also
// grants the LW ability 'QuickStudy'.
static function X2AbilityTemplate BornToBeChief()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;

	Template = PurePassive('UT_BornToBeChief', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_BornToBeChief';
	StatEffect.BuildPersistentEffect(1, true, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_Offense, -default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE);
	StatEffect.AddPersistentStatChange(eStat_Dodge, -default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE);
	StatEffect.AddPersistentStatChange(eStat_Will, -default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE);
	Template.AddTargetEffect(StatEffect);

	// Base fixed part only -- the +4/rank scaling is applied directly to the unit's real stats by
	// ApplyBornToBeChiefRankScaling (not through this ability), so it's already reflected in
	// GetCurrentStat/GetMaxStat without needing a markup of its own.
	Template.SetUIStatMarkup(class'XLocalizedData'.default.AimLabel, eStat_Offense, -default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE);
	Template.SetUIStatMarkup(class'XLocalizedData'.default.DodgeLabel, eStat_Dodge, -default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE);
	Template.SetUIStatMarkup(class'XLocalizedData'.default.WillLabel, eStat_Will, -default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE);

	return Template;
}
