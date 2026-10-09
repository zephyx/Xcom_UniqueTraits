//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_ManiacExplosive.uc
//  PURPOSE: Maniac explosive. UT_ManiacExplosive carries the malus (the primary weapon deals MANIAC_PRIMARY_WEAPON_DAMAGE_REDUCTION_PCT%
//           less damage, X2Effect_UT_PrimaryWeaponMalus); the +3 grenade pockets are the UT_ManiacExtraPockets CHItemSlot template
//           (CreateExtraPocketsSlot below, registered by X2ItemSlot_UniqueTraits.uc). Its second ability, UT_ManiacImproviseGrenade,
//           is a limited-use activated ability that conjures a free explosive grenade, frag or plasma (if researched), added
//           permanently to the holder's inventory for the rest of the mission.
//---------------------------------------------------------------------------------------
class UT_Trait_ManiacExplosive extends UT_TraitBase config(UniqueTraits);

var config int MANIAC_EXTRA_GRENADE_POCKETS;
var localized string ManiacPocketsSlotName, ManiacPocketsSlotLetter;

// Damage malus when the primary weapon is used (X2Effect_UT_PrimaryWeaponMalus).
var config int MANIAC_PRIMARY_WEAPON_DAMAGE_REDUCTION_PCT;
var config name MANIAC_IMPROVISE_GRENADE_ITEM_NAME;
// Better grenade once a research is done (first match wins): parallel lists, see X2Effect_UT_TemporaryItem.ResearchProjectNames.
var config array<name> MANIAC_IMPROVISE_GRENADE_RESEARCH_PROJECTS;
var config array<name> MANIAC_IMPROVISE_GRENADE_RESEARCH_ITEMS;
var config int MANIAC_IMPROVISE_CHARGES;
var config int MANIAC_IMPROVISE_COOLDOWN;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(ManiacExplosive());
	Templates.AddItem(ManiacImproviseGrenade());

	return Templates;
}

static function X2AbilityTemplate ManiacExplosive()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_PrimaryWeaponMalus MalusEffect;

	Template = PurePassive('UT_ManiacExplosive', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	MalusEffect = new class'X2Effect_UT_PrimaryWeaponMalus';
	MalusEffect.EffectName = 'UT_ManiacExplosive_PrimaryWeaponMalus';
	MalusEffect.DamageReductionPct = default.MANIAC_PRIMARY_WEAPON_DAMAGE_REDUCTION_PCT;
	MalusEffect.BuildPersistentEffect(1, true, false);
	MalusEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(MalusEffect);

	return Template;
}

static function X2AbilityTemplate ManiacImproviseGrenade()
{
	local X2AbilityTemplate Template;
	local X2AbilityCost_ActionPoints ActionPointCost;
	local X2AbilityCost_Charges ChargeCost;
	local X2AbilityCharges Charges;
	local X2AbilityCooldown Cooldown;
	local X2Effect_UT_TemporaryItem GrenadeEffect;

	`CREATE_X2ABILITY_TEMPLATE(Template, 'UT_ManiacImproviseGrenade');

	Template.IconImage = "img:///UILibrary_PerkIcons.UIPerk_fraggrenade";
	Template.AbilitySourceName = 'eAbilitySource_Perk';
	Template.eAbilityIconBehaviorHUD = eAbilityIconBehavior_AlwaysShow;
	Template.Hostility = eHostility_Neutral;
	Template.bShowActivation = true;

	Template.AbilityToHitCalc = default.DeadEye;
	Template.AbilityTargetStyle = default.SelfTarget;
	Template.AbilityTriggers.AddItem(default.PlayerInputTrigger);
	Template.AbilityShooterConditions.AddItem(default.LivingShooterProperty);
	Template.AddShooterEffectExclusions();

	ActionPointCost = new class'X2AbilityCost_ActionPoints';
	ActionPointCost.iNumPoints = 1;
	ActionPointCost.bConsumeAllPoints = true;
	Template.AbilityCosts.AddItem(ActionPointCost);

	Charges = new class'X2AbilityCharges';
	Charges.InitialCharges = default.MANIAC_IMPROVISE_CHARGES;
	Template.AbilityCharges = Charges;

	ChargeCost = new class'X2AbilityCost_Charges';
	ChargeCost.NumCharges = 1;
	Template.AbilityCosts.AddItem(ChargeCost);

	Cooldown = new class'X2AbilityCooldown';
	Cooldown.iNumTurns = default.MANIAC_IMPROVISE_COOLDOWN;
	Template.AbilityCooldown = Cooldown;

	GrenadeEffect = new class'X2Effect_UT_TemporaryItem';
	GrenadeEffect.EffectName = 'UT_ManiacImproviseGrenade_Item';
	GrenadeEffect.ItemName = default.MANIAC_IMPROVISE_GRENADE_ITEM_NAME;
	GrenadeEffect.ItemInventorySlot = eInvSlot_Utility;
	GrenadeEffect.ResearchProjectNames = default.MANIAC_IMPROVISE_GRENADE_RESEARCH_PROJECTS;
	GrenadeEffect.ResearchItemNames = default.MANIAC_IMPROVISE_GRENADE_RESEARCH_ITEMS;
	GrenadeEffect.bUseHighestAvailableUpgrade = true;
	GrenadeEffect.bStackOnExisting = true;
	// Each use adds one more grenade: the default eDupe_Ignore would reject every use after the first
	// (same EffectName already on the unit).
	GrenadeEffect.DuplicateResponse = eDupe_Allow;
	GrenadeEffect.BuildPersistentEffect(1, true, false);
	GrenadeEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	Template.AddTargetEffect(GrenadeEffect);

	Template.BuildNewGameStateFn = TypicalAbility_BuildGameState;
	Template.BuildVisualizationFn = TypicalAbility_BuildVisualization;
	Template.bSkipFireAction = true;
	Template.ChosenActivationIncreasePerUse = class'X2AbilityTemplateManager'.default.NonAggressiveChosenActivationIncreasePerUse;

	return Template;
}

//---------------------------------------------------------------------------------------
// Maniac explosive: +3 multi-item grenade pockets, holding any grenade (including rockets),
// same as the vanilla Grenade Pocket. The primary weapon block for this trait is handled
// separately, via CanAddItemToInventory_CH_Improved in X2DownloadableContentInfo_UniqueTraits
// (eInvSlot_PrimaryWeapon is a vanilla slot, not a templated one, so it can't be gated here).
//---------------------------------------------------------------------------------------
static function X2DataTemplate CreateExtraPocketsSlot()
{
	local CHItemSlot Template;

	`CREATE_X2TEMPLATE(class'CHItemSlot', Template, 'UT_ManiacExtraPockets');

	Template.InvSlot = eInvSlot_ExtraGrenadePocket;
	Template.SlotCatMask = Template.SLOT_ITEM;
	Template.IsUserEquipSlot = true;
	Template.IsEquippedSlot = false;
	// Same as vanilla's Grenade Pocket: 'grenade' is a unique-equip category, so without this a
	// frag already in another slot would block a second frag here (RespectsUniqueRule).
	Template.BypassesUniqueRule = true;
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

	ItemStates = Unit.GetAllItemsInSlot(Slot.InvSlot, NewGameState);

	// Without the slot nothing may stay in it; with it, only the first GetMaxItemCount items.
	if (!Slot.UnitHasSlot(Unit, strDummy, NewGameState))
		MoveItemsBackToHQ(Unit, XComHQ, NewGameState, ItemStates);
	else
		MoveItemsBackToHQ(Unit, XComHQ, NewGameState, ItemStates, Slot.GetMaxItemCount(Unit, NewGameState));
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

