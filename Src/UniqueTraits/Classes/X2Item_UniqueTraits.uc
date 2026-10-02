//---------------------------------------------------------------------------------------
//  FILE:   X2Item_UniqueTraits.uc
//  PURPOSE: Scout's free scanner item.
//---------------------------------------------------------------------------------------
class X2Item_UniqueTraits extends X2Item config(UniqueTraits);

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Items;

	Items.AddItem(CreateScoutScannerItem());

	return Items;
}

static function X2WeaponTemplate CreateScoutScannerItem()
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
	// separately by X2EventListener_UniqueTraits.OnGetItemRange, keyed off this item's DataName
	// via SCOUT_SCANNER_ITEM_NAME.
	Template.iRadius = class'X2Item_DefaultUtilityItems'.default.BATTLESCANNER_RADIUS;
	Template.iRange = class'X2Item_DefaultUtilityItems'.default.BATTLESCANNER_RANGE;

	// Not a real economy item => never craftable/purchasable, only ever handed out by X2Effect_UT_TemporaryItem.
	Template.CanBeBuilt = false;
	Template.bInfiniteItem = true;

	return Template;
}
