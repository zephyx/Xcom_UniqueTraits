//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Scout.uc
//  PURPOSE: Scout: -sight radius and a free, reusable scanner (UT_ScoutScannerItem, X2Item_UniqueTraits.uc, granted by X2Effect_UT_TemporaryItem). UT_ScoutScanner is that item's ability.
//---------------------------------------------------------------------------------------
class UT_Trait_Scout extends UT_TraitBase config(UniqueTraits);

var config float SCOUT_SCANNER_RANGE_MULT;

var config int SCOUT_SIGHT_RADIUS_PENALTY;
var config name SCOUT_SCANNER_ITEM_NAME;
var config int SCOUT_SCANNER_COOLDOWN;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Scout());
	Templates.AddItem(ScoutScanner());

	return Templates;
}

// Scout: -3 sight radius, plus a free, reusable scanning ability (not a consumable item => see
// UT_ScoutScannerItem in X2Item_UniqueTraits.uc and ScoutScanner() below).
static function X2AbilityTemplate Scout()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;
	local X2Effect_UT_TemporaryItem ScannerEffect;

	Template = PurePassive('UT_Scout', "img:///UniqueTraits_Icons.UT_Scout", true);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_Scout';
	StatEffect.BuildPersistentEffect(1, true, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_SightRadius, -default.SCOUT_SIGHT_RADIUS_PENALTY);
	Template.AddTargetEffect(StatEffect);

	ScannerEffect = new class'X2Effect_UT_TemporaryItem';
	ScannerEffect.EffectName = 'UT_Scout_FreeScanner';
	ScannerEffect.ItemName = default.SCOUT_SCANNER_ITEM_NAME;
	ScannerEffect.ItemInventorySlot = eInvSlot_Utility;
	ScannerEffect.BuildPersistentEffect(1, true, false);
	ScannerEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(ScannerEffect);

	return Template;
}

// Scout's actual scanning ability.
static function X2AbilityTemplate ScoutScanner()
{
	local X2AbilityTemplate              Template;
	local X2AbilityCooldown              Cooldown;
	local X2AbilityTarget_Cursor         CursorTarget;
	local X2AbilityMultiTarget_Radius    RadiusMultiTarget;
	local X2Effect_PersistentSquadViewer ViewerEffect;
	local X2Effect_ScanningProtocol      ScanningEffect;
	local X2Condition_UnitProperty       CivilianProperty;

	`CREATE_X2ABILITY_TEMPLATE(Template, 'UT_ScoutScanner');

	Template.IconImage = "img:///UILibrary_PerkIcons.UIPerk_item_battlescanner";
	Template.AbilitySourceName = 'eAbilitySource_Item';
	Template.eAbilityIconBehaviorHUD = eAbilityIconBehavior_AlwaysShow;
	Template.Hostility = eHostility_Neutral;
	Template.bDisplayInUITacticalText = false;
	Template.bHideWeaponDuringFire = true;

	Cooldown = new class'X2AbilityCooldown';
	Cooldown.iNumTurns = default.SCOUT_SCANNER_COOLDOWN;
	Template.AbilityCooldown = Cooldown;

	Template.ShotHUDPriority = class'UIUtilities_Tactical'.const.STANDARD_GRENADE_PRIORITY;
	Template.AbilityCosts.AddItem(default.FreeActionCost);

	Template.AbilityToHitCalc = default.DeadEye;
	Template.AbilityShooterConditions.AddItem(default.LivingShooterProperty);
	Template.AddShooterEffectExclusions();

	Template.AbilityTriggers.AddItem(default.PlayerInputTrigger);

	CursorTarget = new class'X2AbilityTarget_Cursor';
	CursorTarget.bRestrictToWeaponRange = true;
	Template.AbilityTargetStyle = CursorTarget;

	RadiusMultiTarget = new class'X2AbilityMultiTarget_Radius';
	RadiusMultiTarget.bUseWeaponRadius = true;
	RadiusMultiTarget.bIgnoreBlockingCover = true;
	Template.AbilityMultiTargetStyle = RadiusMultiTarget;

	Template.TargetingMethod = class'X2TargetingMethod_Grenade';

	ScanningEffect = new class'X2Effect_ScanningProtocol';
	ScanningEffect.BuildPersistentEffect(1, false, false, false, eGameRule_PlayerTurnEnd);
	ScanningEffect.TargetConditions.AddItem(default.LivingHostileUnitOnlyProperty);
	Template.AddMultiTargetEffect(ScanningEffect);

	ScanningEffect = new class'X2Effect_ScanningProtocol';
	ScanningEffect.BuildPersistentEffect(1, false, false, false, eGameRule_PlayerTurnEnd);
	CivilianProperty = new class'X2Condition_UnitProperty';
	CivilianProperty.ExcludeNonCivilian = true;
	CivilianProperty.ExcludeHostileToSource = false;
	CivilianProperty.ExcludeFriendlyToSource = false;
	ScanningEffect.TargetConditions.AddItem(CivilianProperty);
	Template.AddMultiTargetEffect(ScanningEffect);

	ViewerEffect = new class'X2Effect_PersistentSquadViewer';
	ViewerEffect.BuildPersistentEffect(class'X2Ability_ItemGrantedAbilitySet'.default.BATTLESCANNER_DURATION, false, false, false, eGameRule_PlayerTurnBegin);
	Template.AddShooterEffect(ViewerEffect);

	Template.BuildNewGameStateFn = TypicalAbility_BuildGameState;
	Template.BuildVisualizationFn = TypicalAbility_BuildVisualization;

	Template.ChosenActivationIncreasePerUse = class'X2AbilityTemplateManager'.default.NonAggressiveChosenActivationIncreasePerUse;

	return Template;
}

// Scout: +SCOUT_SCANNER_RANGE_MULT on the range of its own scanner item.
static function EventListenerReturn OnGetItemRange_Scout(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;
	local X2WeaponTemplate ItemTemplate;
	local XComGameState_Unit OwnerUnit;

	if (!ParseItemRangeEvent(EventData, EventSource, Tuple, ItemTemplate, OwnerUnit))
		return ELR_NoInterrupt;

	if (ItemTemplate.DataName == default.SCOUT_SCANNER_ITEM_NAME
		&& class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(OwnerUnit, 'UT_Scout'))
	{
		Tuple.Data[1].i = Round(float(Tuple.Data[1].i) * default.SCOUT_SCANNER_RANGE_MULT);
	}

	return ELR_NoInterrupt;
}

static function X2WeaponTemplate CreateScannerItem()
{
	local X2WeaponTemplate Template;

	`CREATE_X2TEMPLATE(class'X2WeaponTemplate', Template, 'UT_ScoutScannerItem');

	Template.strImage = "img:///UILibrary_StrategyImages.X2InventoryIcons.Inv_Battle_Scanner";
	Template.GameArchetype = "WP_Grenade_BattleScanner.WP_Grenade_BattleScanner";
	Template.Abilities.AddItem('UT_ScoutScanner');
	Template.ItemCat = 'tech';
	Template.WeaponCat = 'utility';
	Template.WeaponTech = 'conventional';
	Template.InventorySlot = eInvSlot_Utility;
	Template.StowedLocation = eSlot_BeltHolster;
	Template.Tier = 1;

	// Same radius/range as the real Battle Scanner -- Scout's own +range% bonus is applied
	// separately by UT_Trait_Scout.OnGetItemRange_Scout, keyed off this item's DataName
	// via SCOUT_SCANNER_ITEM_NAME.
	Template.iRadius = class'X2Item_DefaultUtilityItems'.default.BATTLESCANNER_RADIUS;
	Template.iRange = class'X2Item_DefaultUtilityItems'.default.BATTLESCANNER_RANGE;

	// Not a real economy item => never craftable/purchasable, only ever handed out by X2Effect_UT_TemporaryItem.
	Template.CanBeBuilt = false;
	Template.bInfiniteItem = true;

	return Template;
}
