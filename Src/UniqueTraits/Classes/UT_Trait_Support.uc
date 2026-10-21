//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Support.uc
//  PURPOSE: Support: a free medikit and a dedicated vest slot, but no offensive items in the UTILITY slots (the dedicated
//           Grenade Pocket and Ammo Pocket are NOT restricted, they keep taking their own kind of item).
//           The vest slot itself is the UT_SupportVestSlot CHItemSlot template in
//           X2ItemSlot_UniqueTraits.uc, defined by CreateVestSlot below; the offensive-item block is
//           X2DownloadableContentInfo_UniqueTraits.CanAddItemToInventory_CH_Improved (it only stops FUTURE
//           equips, so OnGrant strips what the unit already carries). The free medikit is granted the same
//           way LWOTC's own Corpsman/XMBEffect_AddUtilityItem grants its free medikit.
//           +SUPPORT_MOBILITY_BONUS mobility is a combat effect (X2Effect_PersistentStatChange, applied at the start of every mission) with a UI stat markup, which adds it
//           to the mobility shown in the Armory header.
//---------------------------------------------------------------------------------------
class UT_Trait_Support extends UT_TraitBase config(UniqueTraits);

// What counts as a "vest" for the vest slot, besides items whose own template says eInvSlot_Vest (none in the base
// game): utility items of one of these ItemCats ('defense' = vanilla's Plated/Nanofiber/Hazmat/Stasis Vest, LWOTC's and
// MZ Vest Mod's vests), or listed by DataName here (for a vest of another mod with a different category).
var config array<name> VEST_ITEM_CATEGORIES;
var config array<name> VEST_EXTRA_ITEM_NAMES;
var localized string SupportVestSlotName, SupportVestSlotLetter;

var localized string SupportNoOffensiveItemReason;

var config name SUPPORT_MEDIKIT_ITEM_NAME;
var config int SUPPORT_MOBILITY_BONUS;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Support());

	return Templates;
}

// Event registrations (X2EventListener_UniqueTraits.CreateStrategyListeners calls this for every trait of the pool that is not disabled).
static function OnCreateStrategyListeners(CHEventListenerTemplate Template)
{
	// Support / Swordsman: hide (not just gray out) forbidden items from the Armory picker.
	Template.AddCHEvent('OverrideShowItemInLockerList', OnOverrideShowItemInLockerList_Support, ELD_Immediate, 50);
}

static function X2AbilityTemplate Support()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_TemporaryItem MedikitEffect;
	local X2Effect_PersistentStatChange MobilityEffect;

	Template = PurePassive('UT_Support', "img:///UniqueTraits_Icons.UT_Support", true);

	MedikitEffect = new class'X2Effect_UT_TemporaryItem';
	MedikitEffect.EffectName = 'UT_Support_FreeMedikit';
	MedikitEffect.ItemName = default.SUPPORT_MEDIKIT_ITEM_NAME;
	MedikitEffect.ItemInventorySlot = eInvSlot_Vest;
	MedikitEffect.BuildPersistentEffect(1, true, false);
	MedikitEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(MedikitEffect);

	MobilityEffect = new class'X2Effect_PersistentStatChange';
	MobilityEffect.EffectName = 'UT_Support_MobilityBonus';
	MobilityEffect.BuildPersistentEffect(1, true, false);
	MobilityEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	MobilityEffect.AddPersistentStatChange(eStat_Mobility, default.SUPPORT_MOBILITY_BONUS);
	Template.AddTargetEffect(MobilityEffect);

	Template.SetUIStatMarkup(class'XLocalizedData'.default.MobilityLabel, eStat_Mobility, default.SUPPORT_MOBILITY_BONUS);

	return Template;
}

static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	RemoveSupportOffensiveItems(MutableUnit, NewGameState);
	MoveUtilityVestToVestSlot(MutableUnit, NewGameState);
}

// The trait is already out of AcquiredTraits here.
static function OnClear(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	RevertShifts(MutableUnit);
}

// Vests can no longer be equipped in Utility (CanAddItemToInventory_CH_Improved): one already carried there
// goes into the new vest slot, any further one back to the HQ inventory.
static final function MoveUtilityVestToVestSlot(XComGameState_Unit UnitState, XComGameState NewGameState)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Item> SlotItems;
	local XComGameState_Item SlotItem;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));

	SlotItems = UnitState.GetAllItemsInSlot(eInvSlot_Utility, NewGameState);
	foreach SlotItems(SlotItem)
	{
		if (!IsEligibleForVestSlot(SlotItem.GetMyTemplate()))
			continue;

		SlotItem = XComGameState_Item(NewGameState.ModifyStateObject(class'XComGameState_Item', SlotItem.ObjectID));
		if (!UnitState.RemoveItemFromInventory(SlotItem, NewGameState))
			continue;

		if (UnitState.GetItemInSlot(eInvSlot_Vest, NewGameState) == none
			&& UnitState.AddItemToInventory(SlotItem, eInvSlot_Vest, NewGameState))
			continue;

		if (XComHQ != none)
			XComHQ.PutItemInInventory(NewGameState, SlotItem);
	}
}

// Support's offensive-item block (CanAddItemToInventory_CH_Improved) only stops FUTURE equip attempts. It only concerns the UTILITY slots, 
// so the Grenade Pocket and the Ammo Pocket are left alone and nothing is stripped from them.
static final function RemoveSupportOffensiveItems(XComGameState_Unit UnitState, XComGameState NewGameState)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Item> SlotItems;
	local XComGameState_Item SlotItem;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));

	SlotItems = UnitState.GetAllItemsInSlot(eInvSlot_Utility, NewGameState);
	foreach SlotItems(SlotItem)
	{
		if (!IsOffensiveWeaponItem(SlotItem.GetMyTemplate()))
			continue;

		SlotItem = XComGameState_Item(NewGameState.ModifyStateObject(class'XComGameState_Item', SlotItem.ObjectID));
		if (UnitState.RemoveItemFromInventory(SlotItem, NewGameState) && XComHQ != none)
			XComHQ.PutItemInInventory(NewGameState, SlotItem);
	}
}

// Support: hides (not just grays out) from the Armory picker the offensive items (frag grenades, ammo, etc.) and the vests in the Utility slots
// (the vests go in the vest slot). The Grenade Pocket and the Ammo Pocket are not touched.
static function EventListenerReturn OnOverrideShowItemInLockerList_Support(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;
	local XComGameState_Item ItemState;
	local XComGameState_Unit UnitState;
	local EInventorySlot Slot;

	Tuple = XComLWTuple(EventData);
	ItemState = XComGameState_Item(EventSource);
	if (Tuple == none || Tuple.Data.Length < 3 || ItemState == none)
		return ELR_NoInterrupt;

	Slot = EInventorySlot(Tuple.Data[1].i);
	if (Slot != eInvSlot_Utility)
		return ELR_NoInterrupt;

	UnitState = XComGameState_Unit(Tuple.Data[2].o);
	if (UnitState == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_Support'))
		return ELR_NoInterrupt;

	if (IsOffensiveWeaponItem(ItemState.GetMyTemplate()) || IsEligibleForVestSlot(ItemState.GetMyTemplate()))
		Tuple.Data[0].b = false;

	return ELR_NoInterrupt;
}

// No offensive item and no vest in the Utility slots (the vests go in the vest slot). The dedicated Grenade Pocket and Ammo Pocket are NOT restricted
static function bool IsItemBlocked(EInventorySlot Slot, X2ItemTemplate ItemTemplate, out string DisabledReason)
{
	if (Slot != eInvSlot_Utility)
		return false;

	// Vests live in Support's vest slot, not in Utility.
	if (IsEligibleForVestSlot(ItemTemplate))
		return true;

	if (!IsOffensiveWeaponItem(ItemTemplate))
		return false;

	DisabledReason = default.SupportNoOffensiveItemReason;
	return true;
}

//---------------------------------------------------------------------------------------
// Support: dedicated vest slot, one item, restricted to genuine vest-native items.
//---------------------------------------------------------------------------------------
static function X2DataTemplate CreateVestSlot()
{
	local CHItemSlot Template;

	`CREATE_X2TEMPLATE(class'CHItemSlot', Template, 'UT_SupportVestSlot');

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

	Template.UnitHasSlotFn = SupportUnitHasSlot;
	Template.CanAddItemToSlotFn = SupportCanAddItemToSlot;
	Template.ShowItemInLockerListFn = SupportShowItemInLockerList;
	Template.ValidateLoadoutFn = SupportValidateLoadout;
	Template.GetPriorityFn = SupportGetPriority;
	Template.GetDisplayNameFn = SupportGetDisplayName;
	Template.GetDisplayLetterFn = SupportGetDisplayLetter;

	return Template;
}

static function bool SupportUnitHasSlot(CHItemSlot Slot, XComGameState_Unit UnitState, out string LockedReason, optional XComGameState CheckGameState)
{
	return class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_Support');
}

static function bool SupportCanAddItemToSlot(CHItemSlot Slot, XComGameState_Unit Unit, X2ItemTemplate Template, optional XComGameState CheckGameState, optional int Quantity = 1, optional XComGameState_Item ItemState)
{
	local string strDummy;

	if (!Slot.UnitHasSlot(Unit, strDummy, CheckGameState))
		return false;

	if (Unit.GetItemInSlot(Slot.InvSlot, CheckGameState) != none)
		return false;

	return IsEligibleForVestSlot(Template);
}

static function bool SupportShowItemInLockerList(CHItemSlot Slot, XComGameState_Unit Unit, XComGameState_Item ItemState, X2ItemTemplate ItemTemplate, XComGameState CheckGameState)
{
	return IsEligibleForVestSlot(ItemTemplate);
}

// Restricted to vests: an item that natively targets eInvSlot_Vest, or a utility item configured as a vest (see
// VEST_ITEM_CATEGORIES / VEST_EXTRA_ITEM_NAMES). A Support holder can't equip those in Utility anymore (the vest slot is
// where they go): see CanAddItemToInventory_CH_Improved and OnOverrideShowItemInLockerList_Support.
static function bool IsEligibleForVestSlot(X2ItemTemplate ItemTemplate)
{
	local X2EquipmentTemplate EquipmentTemplate;

	EquipmentTemplate = X2EquipmentTemplate(ItemTemplate);
	if (EquipmentTemplate == none || EquipmentTemplate.iItemSize <= 0)
		return false;

	if (EquipmentTemplate.InventorySlot == eInvSlot_Vest)
		return true;

	return EquipmentTemplate.InventorySlot == eInvSlot_Utility
		&& (default.VEST_ITEM_CATEGORIES.Find(EquipmentTemplate.ItemCat) != INDEX_NONE
			|| default.VEST_EXTRA_ITEM_NAMES.Find(EquipmentTemplate.DataName) != INDEX_NONE);
}

// Support eligibility: without any item the slot accepts, it would always sit empty and Support would be a pure
// downside. Called from UniqueTraits_TraitConfig.IsTraitEligible to exclude Support from the draw pool in that case
// (can only happen if VEST_ITEM_CATEGORIES/VEST_EXTRA_ITEM_NAMES are emptied or no utility vest is loaded).
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
static function SupportValidateLoadout(CHItemSlot Slot, XComGameState_Unit Unit, XComGameState_HeadquartersXCom XComHQ, XComGameState NewGameState)
{
	local string strDummy;

	if (Slot.UnitHasSlot(Unit, strDummy, NewGameState))
		return;

	MoveItemsBackToHQ(Unit, XComHQ, NewGameState, Unit.GetAllItemsInSlot(Slot.InvSlot, NewGameState));
}

static function int SupportGetPriority(CHItemSlot Slot, XComGameState_Unit UnitState, optional XComGameState CheckGameState)
{
	return 115;
}

static function string SupportGetDisplayName(CHItemSlot Slot)
{
	return default.SupportVestSlotName;
}

static function string SupportGetDisplayLetter(CHItemSlot Slot)
{
	return default.SupportVestSlotLetter;
}

// Without any item the vest slot accepts, it would always sit empty and Support would be a pure downside: the trait
// leaves the draw pool (can only happen if VEST_ITEM_CATEGORIES/VEST_EXTRA_ITEM_NAMES are emptied or no utility vest is loaded).
static function bool IsEligible()
{
	return AnyVestItemTemplateExists();
}
