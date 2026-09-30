//---------------------------------------------------------------------------------------
//  FILE:   X2ItemSlot_UniqueTraits.uc
//  PURPOSE: Custom CHItemSlot (Community Highlander issue #118) templates backing Defender
//           (a dedicated single-item "vest" slot, restricted to genuine vest-native items) and
//           Maniac explosive (+3 multi-item grenade pockets). Defender's free medikit is NOT
//           granted here (see X2Ability_UniqueTraits_Items.Defender(), which grants it the
//           same tactical-only, bIgnoreItemEquipRestrictions way LWOTC's Corpsman does). Both reuse
//           enum values the Highlander already reserves for exactly this purpose
//           (eInvSlot_Vest / eInvSlot_ExtraGrenadePocket), so no new EInventorySlot entry is
//           needed.
//
//           A CHItemSlotSet subclass needs no explicit registration: like X2Ability/
//           X2StrategyElement classes, its static CreateTemplates() is picked up
//           automatically as long as the class is compiled into an active mod package.
//---------------------------------------------------------------------------------------
class X2ItemSlot_UniqueTraits extends CHItemSlotSet config(UniqueTraits);

var config int MANIAC_EXTRA_GRENADE_POCKETS;

var localized string DefenderVestSlotName, DefenderVestSlotLetter;
var localized string ManiacPocketsSlotName, ManiacPocketsSlotLetter;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(CreateDefenderVestSlot());
	Templates.AddItem(CreateManiacExtraPocketsSlot());

	return Templates;
}

//---------------------------------------------------------------------------------------
// Defender: dedicated vest slot, one item, restricted to genuine vest-native items.
//---------------------------------------------------------------------------------------
static function X2DataTemplate CreateDefenderVestSlot()
{
	local CHItemSlot Template;

	`CREATE_X2TEMPLATE(class'CHItemSlot', Template, 'UT_DefenderVestSlot');

	Template.InvSlot = eInvSlot_Vest;
	Template.SlotCatMask = Template.SLOT_ITEM;
	Template.IsUserEquipSlot = true;
	Template.IsEquippedSlot = true;
	Template.BypassesUniqueRule = true;
	Template.IsMultiItemSlot = false;
	Template.MinimumEquipped = 0;
	Template.IsSmallSlot = true;
	Template.NeedsPresEquip = false;
	Template.ShowOnCinematicPawns = false;

	Template.UnitHasSlotFn = DefenderUnitHasSlot;
	Template.CanAddItemToSlotFn = DefenderCanAddItemToSlot;
	Template.ShowItemInLockerListFn = DefenderShowItemInLockerList;
	Template.ValidateLoadoutFn = DefenderValidateLoadout;
	Template.GetPriorityFn = DefenderGetPriority;
	Template.GetDisplayNameFn = DefenderGetDisplayName;
	Template.GetDisplayLetterFn = DefenderGetDisplayLetter;

	return Template;
}

static function bool DefenderUnitHasSlot(CHItemSlot Slot, XComGameState_Unit UnitState, out string LockedReason, optional XComGameState CheckGameState)
{
	return class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_Defender');
}

static function bool DefenderCanAddItemToSlot(CHItemSlot Slot, XComGameState_Unit Unit, X2ItemTemplate Template, optional XComGameState CheckGameState, optional int Quantity = 1, optional XComGameState_Item ItemState)
{
	local string strDummy;

	if (!Slot.UnitHasSlot(Unit, strDummy, CheckGameState))
		return false;

	if (Unit.GetItemInSlot(Slot.InvSlot, CheckGameState) != none)
		return false;

	return IsEligibleForVestSlot(Template);
}

static function bool DefenderShowItemInLockerList(CHItemSlot Slot, XComGameState_Unit Unit, XComGameState_Item ItemState, X2ItemTemplate ItemTemplate, XComGameState CheckGameState)
{
	return IsEligibleForVestSlot(ItemTemplate);
}

// Restricted to genuine "vest" items.
static function bool IsEligibleForVestSlot(X2ItemTemplate ItemTemplate)
{
	local X2EquipmentTemplate EquipmentTemplate;

	EquipmentTemplate = X2EquipmentTemplate(ItemTemplate);
	if (EquipmentTemplate == none || EquipmentTemplate.iItemSize <= 0)
		return false;

	return EquipmentTemplate.InventorySlot == eInvSlot_Vest;
}

// Defender eligibility support: base XCOM 2 WOTC (and this mod's own trait pool) ships no item
// whose own template declares InventorySlot=eInvSlot_Vest, so without another mod adding one,
// this slot would always sit empty and Defender's "restricted to genuine vest items" downside
// would be entirely cosmetic.
// Called from UniqueTraits_TraitConfig.IsTraitEligible to exclude Defender from the draw pool in
// that case, the same way the base game withholds mechanics tied to content that isn't present.
static function bool AnyVestItemTemplateExists()
{
	local X2ItemTemplateManager ItemMgr;
	local X2DataTemplate DataTemplate;
	local X2ItemTemplate ItemTemplate;

	ItemMgr = class'X2ItemTemplateManager'.static.GetItemTemplateManager();

	foreach ItemMgr.IterateTemplates(DataTemplate, none)
	{
		ItemTemplate = X2ItemTemplate(DataTemplate);
		if (ItemTemplate != none && IsEligibleForVestSlot(ItemTemplate))
			return true;
	}

	return false;
}

// Generic "does equipping/throwing this item let its user deal direct damage" check: ammo is
// always offensive, rockets are always offensive, a real grenade is offensive if either of its OWN
// ThrownGrenadeEffects/LaunchedGrenadeEffects lists carries an X2Effect_ApplyWeaponDamage, and any
// other weapon is offensive if any ability it grants carries one as a target OR multi-target
// effect. Deliberately not a hardcoded item-name blacklist so LWOTC/other mods' added
// grenades/weapons classify correctly too.
static function bool IsOffensiveWeaponItem(X2ItemTemplate ItemTemplate)
{
	local X2WeaponTemplate WeaponTemplate;
	local X2GrenadeTemplate GrenadeTemplate;
	local X2AbilityTemplateManager AbilityMgr;
	local X2AbilityTemplate AbilityTemplate;
	local name AbilityName;

	if (X2AmmoTemplate(ItemTemplate) != none)
		return true;

	WeaponTemplate = X2WeaponTemplate(ItemTemplate);
	if (WeaponTemplate == none)
		return false;

	if (WeaponTemplate.WeaponCat == 'rocket')
		return true;

	GrenadeTemplate = X2GrenadeTemplate(ItemTemplate);
	if (GrenadeTemplate != none)
	{
		if (EffectListHasRealWeaponDamage(GrenadeTemplate.ThrownGrenadeEffects, GrenadeTemplate)
			|| EffectListHasRealWeaponDamage(GrenadeTemplate.LaunchedGrenadeEffects, GrenadeTemplate))
			return true;
	}

	AbilityMgr = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();
	foreach WeaponTemplate.Abilities(AbilityName)
	{
		AbilityTemplate = AbilityMgr.FindAbilityTemplate(AbilityName);
		if (AbilityTemplate == none)
			continue;

		if (EffectListHasRealWeaponDamage(AbilityTemplate.AbilityTargetEffects, WeaponTemplate)
			|| EffectListHasRealWeaponDamage(AbilityTemplate.AbilityMultiTargetEffects, WeaponTemplate))
			return true;
	}

	return false;
}

// An X2Effect_ApplyWeaponDamage's mere presence isn't enough. Flashbang
// deliberately carries a real X2Effect_ApplyWeaponDamage with zero actual damage, purely so combat
// visualization still plays a flinch/overwatch-removal reaction.
static function bool EffectListHasRealWeaponDamage(array<X2Effect> Effects, X2WeaponTemplate WeaponTemplate)
{
	local int i;
	local X2Effect_ApplyWeaponDamage DamageEffect;

	for (i = 0; i < Effects.Length; i++)
	{
		DamageEffect = X2Effect_ApplyWeaponDamage(Effects[i]);
		if (DamageEffect == none)
			continue;

		if (DamageEffect.EffectDamageValue.Damage > 0)
			return true;

		if (!DamageEffect.bIgnoreBaseDamage && WeaponTemplate.BaseDamage.Damage > 0)
			return true;
	}

	return false;
}

// Defensive only: if the unit ever lost the slot (shouldn't happen, the trait is permanent),
// don't strand whatever real vest item might be equipped in it. Never touches the tactical-only
// free medikit (that item is never present at the strategy layer where ValidateLoadout runs).
static function DefenderValidateLoadout(CHItemSlot Slot, XComGameState_Unit Unit, XComGameState_HeadquartersXCom XComHQ, XComGameState NewGameState)
{
	local string strDummy;
	local array<XComGameState_Item> ItemStates;
	local XComGameState_Item ItemState;

	if (Slot.UnitHasSlot(Unit, strDummy, NewGameState))
		return;

	ItemStates = Unit.GetAllItemsInSlot(Slot.InvSlot, NewGameState);
	foreach ItemStates(ItemState)
	{
		ItemState = XComGameState_Item(NewGameState.ModifyStateObject(class'XComGameState_Item', ItemState.ObjectID));
		if (Unit.RemoveItemFromInventory(ItemState, NewGameState))
			XComHQ.PutItemInInventory(NewGameState, ItemState);
	}
}

static function int DefenderGetPriority(CHItemSlot Slot, XComGameState_Unit UnitState, optional XComGameState CheckGameState)
{
	return 115;
}

static function string DefenderGetDisplayName(CHItemSlot Slot)
{
	return default.DefenderVestSlotName;
}

static function string DefenderGetDisplayLetter(CHItemSlot Slot)
{
	return default.DefenderVestSlotLetter;
}

//---------------------------------------------------------------------------------------
// Maniac explosive: +3 multi-item grenade pockets, holding any grenade (including rockets),
// same as the vanilla Grenade Pocket. The primary weapon block for this trait is handled
// separately, via CanAddItemToInventory_CH_Improved in X2DownloadableContentInfo_UniqueTraits
// (eInvSlot_PrimaryWeapon is a vanilla slot, not a templated one, so it can't be gated here).
//---------------------------------------------------------------------------------------
static function X2DataTemplate CreateManiacExtraPocketsSlot()
{
	local CHItemSlot Template;

	`CREATE_X2TEMPLATE(class'CHItemSlot', Template, 'UT_ManiacExtraPockets');

	Template.InvSlot = eInvSlot_ExtraGrenadePocket;
	Template.SlotCatMask = Template.SLOT_ITEM;
	Template.IsUserEquipSlot = true;
	Template.IsEquippedSlot = false;
	Template.BypassesUniqueRule = false;
	Template.IsMultiItemSlot = true;
	Template.MinimumEquipped = 0;
	Template.IsSmallSlot = true;
	Template.NeedsPresEquip = false;
	Template.ShowOnCinematicPawns = false;

	Template.UnitHasSlotFn = ManiacUnitHasSlot;
	Template.CanAddItemToSlotFn = ManiacCanAddItemToSlot;
	Template.ShowItemInLockerListFn = ManiacShowItemInLockerList;
	Template.ValidateLoadoutFn = ManiacValidateLoadout;
	Template.GetPriorityFn = ManiacGetPriority;
	Template.GetMaxItemCountFn = ManiacGetMaxItemCount;
	Template.GetDisplayNameFn = ManiacGetDisplayName;
	Template.GetDisplayLetterFn = ManiacGetDisplayLetter;

	return Template;
}

static function bool ManiacUnitHasSlot(CHItemSlot Slot, XComGameState_Unit UnitState, out string LockedReason, optional XComGameState CheckGameState)
{
	return class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_ManiacExplosive');
}

static function int ManiacGetMaxItemCount(CHItemSlot Slot, XComGameState_Unit UnitState, optional XComGameState CheckGameState)
{
	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_ManiacExplosive'))
		return 0;

	return default.MANIAC_EXTRA_GRENADE_POCKETS;
}

static function bool ManiacCanAddItemToSlot(CHItemSlot Slot, XComGameState_Unit Unit, X2ItemTemplate Template, optional XComGameState CheckGameState, optional int Quantity = 1, optional XComGameState_Item ItemState)
{
	local string strDummy;

	if (!Slot.UnitHasSlot(Unit, strDummy, CheckGameState))
		return false;

	if (Unit.GetAllItemsInSlot(Slot.InvSlot, CheckGameState).Length >= Slot.GetMaxItemCount(Unit, CheckGameState))
		return false;

	return X2GrenadeTemplate(Template) != none;
}

static function bool ManiacShowItemInLockerList(CHItemSlot Slot, XComGameState_Unit Unit, XComGameState_Item ItemState, X2ItemTemplate ItemTemplate, XComGameState CheckGameState)
{
	return X2GrenadeTemplate(ItemTemplate) != none;
}

static function ManiacValidateLoadout(CHItemSlot Slot, XComGameState_Unit Unit, XComGameState_HeadquartersXCom XComHQ, XComGameState NewGameState)
{
	local string strDummy;
	local array<XComGameState_Item> ItemStates;
	local XComGameState_Item ItemState;
	local int i, MaxItems;

	ItemStates = Unit.GetAllItemsInSlot(Slot.InvSlot, NewGameState);

	if (!Slot.UnitHasSlot(Unit, strDummy, NewGameState))
	{
		foreach ItemStates(ItemState)
		{
			ItemState = XComGameState_Item(NewGameState.ModifyStateObject(class'XComGameState_Item', ItemState.ObjectID));
			if (Unit.RemoveItemFromInventory(ItemState, NewGameState))
				XComHQ.PutItemInInventory(NewGameState, ItemState);
		}
		return;
	}

	MaxItems = Slot.GetMaxItemCount(Unit, NewGameState);
	for (i = ItemStates.Length - 1; i >= MaxItems; i--)
	{
		ItemState = XComGameState_Item(NewGameState.ModifyStateObject(class'XComGameState_Item', ItemStates[i].ObjectID));
		if (Unit.RemoveItemFromInventory(ItemState, NewGameState))
			XComHQ.PutItemInInventory(NewGameState, ItemState);
	}
}

static function int ManiacGetPriority(CHItemSlot Slot, XComGameState_Unit UnitState, optional XComGameState CheckGameState)
{
	return 95;
}

static function string ManiacGetDisplayName(CHItemSlot Slot)
{
	return default.ManiacPocketsSlotName;
}

static function string ManiacGetDisplayLetter(CHItemSlot Slot)
{
	return default.ManiacPocketsSlotLetter;
}
