//---------------------------------------------------------------------------------------
//  FILE:   X2Ability_UniqueTraits_Advanced.uc
//  PURPOSE: Traits that need one or more small custom effect classes, on top of base-game
//           building blocks.
//---------------------------------------------------------------------------------------
class X2Ability_UniqueTraits_Advanced extends X2Ability config(UniqueTraits);

var config int PACIFIST_AIM, PACIFIST_ORGANIC_DEFENSE;
var config int BASEBALL_EXPLOSIVE_DAMAGE_REDUCTION;
var config int ALLINARMS_MOBILITY;
var config float DISCREET_DETECTION_MULT;
var config int DISCREET_HEAVY_WEAPON_DAMAGE_REDUCTION;
var config int FLYCATCHER_AIM_PENALTY, FLYCATCHER_CRIT_PENALTY;
var config float QUICKHEALING_DAMAGE_TAKEN_MULT;
var config int SCOUT_SIGHT_RADIUS_PENALTY;
var config name SCOUT_SCANNER_ITEM_NAME;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Pacifist());
	Templates.AddItem(BaseballPlayer());
	Templates.AddItem(AllInArms());
	Templates.AddItem(Discreet());
	Templates.AddItem(Flycatcher());
	Templates.AddItem(AlwaysReady());
	Templates.AddItem(AlwaysReadyOverwatch());
	Templates.AddItem(QuickHealing());
	Templates.AddItem(Thief());
	Templates.AddItem(JackOfAllTrades());
	Templates.AddItem(Scout());

	return Templates;
}

// Pacifist: -20 aim attacking a biological target, +30 defense against a biological enemy
static function X2AbilityTemplate Pacifist()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_OrganicCombat CombatEffect;

	Template = PurePassive('UT_Pacifist', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	CombatEffect = new class'X2Effect_UT_OrganicCombat';
	CombatEffect.EffectName = 'UT_Pacifist_OrganicCombat';
	CombatEffect.AimMalus = default.PACIFIST_AIM;
	CombatEffect.DefenseBonus = default.PACIFIST_ORGANIC_DEFENSE;
	CombatEffect.BuildPersistentEffect(1, true, false);
	CombatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	Template.AddTargetEffect(CombatEffect);

	return Template;
}

// Baseball player: gains Salvo (granted separately via ini). Own explosives deal 2 less damage.
static function X2AbilityTemplate BaseballPlayer()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_WeakExplosives WeakExplosivesEffect;

	Template = PurePassive('UT_BaseballPlayer', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	WeakExplosivesEffect = new class'X2Effect_UT_WeakExplosives';
	WeakExplosivesEffect.EffectName = 'UT_BaseballPlayer';
	WeakExplosivesEffect.DamageReduction = default.BASEBALL_EXPLOSIVE_DAMAGE_REDUCTION;
	WeakExplosivesEffect.BuildPersistentEffect(1, true, false);
	WeakExplosivesEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	Template.AddTargetEffect(WeakExplosivesEffect);

	return Template;
}

// All in arms: -2 mobility. The +5 hand-throw range bonus is handled by a global
// 'OnGetItemRange' listener (X2EventListener_UniqueTraits) since that event fires on the
// item, not through an effect on the unit, and needs to tell hand-thrown items (grenade
// pocket / utility slot) apart from grenade launchers, rocket launchers and gauntlets.
static function X2AbilityTemplate AllInArms()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;

	`CREATE_X2ABILITY_TEMPLATE(Template, 'UT_AllInArms');
	Template.IconImage = "img:///UILibrary_PerkIcons.UIPerk_standard";
	Template.eAbilityIconBehaviorHUD = eAbilityIconBehavior_NeverShow;
	Template.AbilityToHitCalc = default.DeadEye;
	Template.AbilityTargetStyle = default.SelfTarget;
	Template.AbilityTriggers.AddItem(default.UnitPostBeginPlayTrigger);
	Template.bIsPassive = true;
	Template.Hostility = eHostility_Neutral;
	Template.AbilitySourceName = 'eAbilitySource_Perk';

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.AddPersistentStatChange(eStat_Mobility, -default.ALLINARMS_MOBILITY);
	StatEffect.BuildPersistentEffect(1, true, false, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, true,, Template.AbilitySourceName);
	Template.AddTargetEffect(StatEffect);
	Template.bCrossClassEligible = true;

	Template.SetUIStatMarkup(class'XLocalizedData'.default.MobilityLabel, eStat_Mobility, -default.ALLINARMS_MOBILITY);

	Template.BuildNewGameStateFn = TypicalAbility_BuildGameState;

	return Template;
}

// Discreet: -20% detection radius; heavy weapons (sniper rifles, cannons) deal 1 less damage.
static function X2AbilityTemplate Discreet()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;
	local X2Effect_UT_WeakHeavyWeapons WeakHeavyEffect;

	Template = PurePassive('UT_Discreet', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_Discreet';
	StatEffect.BuildPersistentEffect(1, true, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_DetectionRadius, default.DISCREET_DETECTION_MULT, MODOP_Multiplication);
	Template.AddTargetEffect(StatEffect);

	WeakHeavyEffect = new class'X2Effect_UT_WeakHeavyWeapons';
	WeakHeavyEffect.EffectName = 'UT_Discreet_WeakHeavyWeapons';
	WeakHeavyEffect.DamageReduction = default.DISCREET_HEAVY_WEAPON_DAMAGE_REDUCTION;
	WeakHeavyEffect.BuildPersistentEffect(1, true, false);
	WeakHeavyEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	Template.AddTargetEffect(WeakHeavyEffect);

	return Template;
}

// Flycatcher: grants Grapple (via ini); -10 aim/-10 crit attacking a target below their own elevation.
static function X2AbilityTemplate Flycatcher()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_FlycatcherMalus MalusEffect;

	Template = PurePassive('UT_Flycatcher', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	MalusEffect = new class'X2Effect_UT_FlycatcherMalus';
	MalusEffect.EffectName = 'UT_Flycatcher';
	MalusEffect.AimPenalty = default.FLYCATCHER_AIM_PENALTY;
	MalusEffect.CritPenalty = default.FLYCATCHER_CRIT_PENALTY;
	MalusEffect.BuildPersistentEffect(1, true, false);
	MalusEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	Template.AddTargetEffect(MalusEffect);

	return Template;
}

// Always ready: this passive is just the icon holder. The malus (chance to auto-reload
// after moving) is granted separately by reusing the base game's Trait_ObsessiveReloader
// personality trait (see X2DownloadableContentInfo_UniqueTraits.AssignTraitOnNaturalPromotion).
// The bonus is UT_AlwaysReadyOverwatch below.
static function X2AbilityTemplate AlwaysReady()
{
	local X2AbilityTemplate Template;

	Template = PurePassive('UT_AlwaysReady', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	return Template;
}

// Enters in overwatch at the end of the turn (if not already in overwatch and have ammo left).
static function X2AbilityTemplate AlwaysReadyOverwatch()
{
	local X2AbilityTemplate Template;
	local X2AbilityTrigger_EventListener Trigger;
	local X2AbilityCost_Ammo AmmoCost;
	local X2Effect_ReserveOverwatchPoints ReserveEffect;
	local X2Effect_CoveringFire CoveringFireEffect;
	local X2Condition_AbilityProperty CoveringFireCondition;

	`CREATE_X2ABILITY_TEMPLATE(Template, 'UT_AlwaysReadyOverwatch');

	Template.AbilitySourceName = 'eAbilitySource_Perk';
	Template.eAbilityIconBehaviorHUD = eAbilityIconBehavior_NeverShow;
	Template.Hostility = eHostility_Neutral;
	Template.bCrossClassEligible = true;

	Template.AbilityToHitCalc = default.DeadEye;
	Template.AbilityTargetStyle = default.SelfTarget;
	Template.AbilityShooterConditions.AddItem(default.LivingShooterProperty);
	Template.AbilityShooterConditions.AddItem(new class'X2Condition_UT_ExcludeAlreadyOverwatching');

	AmmoCost = new class'X2AbilityCost_Ammo';
	AmmoCost.iAmmo = 1;
	AmmoCost.bFreeCost = true;
	Template.AbilityCosts.AddItem(AmmoCost);

	Trigger = new class'X2AbilityTrigger_EventListener';
	Trigger.ListenerData.Deferral = ELD_OnStateSubmitted;
	Trigger.ListenerData.EventID = 'PlayerTurnEnded';
	Trigger.ListenerData.Filter = eFilter_Player;
	Trigger.ListenerData.EventFn = class'XComGameState_Ability'.static.AbilityTriggerEventListener_Self;
	Template.AbilityTriggers.AddItem(Trigger);

	ReserveEffect = new class'X2Effect_ReserveOverwatchPoints';
	Template.AddTargetEffect(ReserveEffect);

	CoveringFireEffect = new class'X2Effect_CoveringFire';
	CoveringFireEffect.AbilityToActivate = 'OverwatchShot';
	CoveringFireEffect.BuildPersistentEffect(1, false, true, false, eGameRule_PlayerTurnBegin);
	CoveringFireCondition = new class'X2Condition_AbilityProperty';
	CoveringFireCondition.OwnerHasSoldierAbilities.AddItem('CoveringFire');
	CoveringFireEffect.TargetConditions.AddItem(CoveringFireCondition);
	Template.AddTargetEffect(CoveringFireEffect);

	Template.bSkipFireAction = true;
	Template.BuildNewGameStateFn = TypicalAbility_BuildGameState;

	return Template;
}

// Quick healing: +25% damage taken (base X2Effect_ConditionalDamageModifier, reused as-is) +
// custom X2Effect_UT_QuickHealing (see that file for the LowestHP/recovery-time mechanic).
static function X2AbilityTemplate QuickHealing()
{
	local X2AbilityTemplate Template;
	local X2Effect_ConditionalDamageModifier DamageTakenEffect;
	local X2Effect_UT_QuickHealing HealingEffect;

	Template = PurePassive('UT_QuickHealing', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	DamageTakenEffect = new class'X2Effect_ConditionalDamageModifier';
	DamageTakenEffect.EffectName = 'UT_QuickHealing_DamageTaken';
	DamageTakenEffect.bModifyIncomingDamage = true;
	DamageTakenEffect.DamageModifier = default.QUICKHEALING_DAMAGE_TAKEN_MULT;
	DamageTakenEffect.BuildPersistentEffect(1, true, false);
	DamageTakenEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	Template.AddTargetEffect(DamageTakenEffect);

	HealingEffect = new class'X2Effect_UT_QuickHealing';
	HealingEffect.BuildPersistentEffect(1, true, false);
	HealingEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	Template.AddTargetEffect(HealingEffect);

	return Template;
}

// Thief: this passive is just the icon holder. The actual mechanics (AP refund on loot pickup,
// chance to secretly keep a looted item) are implemented as global event listeners in
// X2EventListener_UniqueTraits (OnItemLooted / OnAfterActionModifyRecoveredLoot), since
// neither is naturally expressible as an effect attached to this ability.
static function X2AbilityTemplate Thief()
{
	local X2AbilityTemplate Template;

	Template = PurePassive('UT_Thief', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	return Template;
}

// Jack of all trades: this passive is just the icon holder. The +15 Ability Point bonus is
// granted once, directly in X2DownloadableContentInfo_UniqueTraits.AssignTraitOnNaturalPromotion
// (keyed off TraitID == 'UT_JackOfAllTrades'), the same way Always ready's malus is special-
// cased there. The purchase block on the class's top-cost ability row (~35 AP in LWOTC's
// random-deck system) is X2EventListener_UniqueTraits.OnCPSOverrideCanPurchaseAbility, an
// optional-mod hook that only fires if Community Promotion Screen is loaded.
static function X2AbilityTemplate JackOfAllTrades()
{
	local X2AbilityTemplate Template;

	Template = PurePassive('UT_JackOfAllTrades', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	return Template;
}

// Scout: free Battle Scanner (granted via X2Effect_UT_TemporaryItem, bypassing slot capacity,
// tactical-only), -3 sight radius. The +25% throw range on that scanner specifically is handled by a global
// 'OnGetItemRange' listener scoped to the Battle Scanner item template name.
static function X2AbilityTemplate Scout()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;
	local X2Effect_UT_TemporaryItem ScannerEffect;

	Template = PurePassive('UT_Scout', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_Scout';
	StatEffect.BuildPersistentEffect(1, true, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_SightRadius, -default.SCOUT_SIGHT_RADIUS_PENALTY);
	Template.AddTargetEffect(StatEffect);

	ScannerEffect = new class'X2Effect_UT_TemporaryItem';
	ScannerEffect.EffectName = 'UT_Scout_FreeScanner';
	ScannerEffect.ItemName = default.SCOUT_SCANNER_ITEM_NAME;
	ScannerEffect.ItemInventorySlot = eInvSlot_Utility;
	ScannerEffect.BuildPersistentEffect(1, true, false);
	ScannerEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	Template.AddTargetEffect(ScannerEffect);

	return Template;
}
