//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_ManiacExplosive.uc
//  PURPOSE: Maniac explosive. UT_ManiacExplosive is just the icon holder: the +3 grenade pockets are the
//           UT_ManiacExtraPockets CHItemSlot template (CreateExtraPocketsSlot below, registered by
//           X2ItemSlot_UniqueTraits.uc), and the primary weapon
//           block is X2DownloadableContentInfo_UniqueTraits.CanAddItemToInventory_CH_Improved (it only stops
//           FUTURE equips, so OnGrant strips the starting primary weapon). Its second ability,
//           UT_ManiacImproviseGrenade, is a limited-use activated ability that conjures a free explosive grenade,
//           frag or plasma (if researched), added permanently to the holder's inventory for the rest of the mission.
//---------------------------------------------------------------------------------------
class UT_Trait_ManiacExplosive extends UT_TraitBase config(UniqueTraits);

var config int MANIAC_EXTRA_GRENADE_POCKETS;
var localized string ManiacPocketsSlotName, ManiacPocketsSlotLetter;

var localized string ManiacExplosiveNoPrimaryReason;

// Unarmed stance (experimental, can be switched off in the ini): with no primary weapon the soldier would keep the animations of a
// rifle holder. When enabled, the animation sets of MANIAC_UNARMED_WEAPON_ARCHETYPE (default: the Templar's gauntlet, hands-free
// stance) are added to the pawn while the unit carries no primary weapon.
var config bool MANIAC_UNARMED_ANIMS_ENABLED;
var config string MANIAC_UNARMED_WEAPON_ARCHETYPE;
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

	Template = PurePassive('UT_ManiacExplosive', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

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

static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	RemoveManiacPrimaryWeapon(MutableUnit, NewGameState);
}

// The primary weapon block only stops FUTURE equips => the rookie's already-equipped starting weapon is
// stripped back to HQ inventory explicitly.
static final function RemoveManiacPrimaryWeapon(XComGameState_Unit UnitState, XComGameState NewGameState)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_Item PrimaryWeapon;

	PrimaryWeapon = UnitState.GetItemInSlot(eInvSlot_PrimaryWeapon, NewGameState);
	if (PrimaryWeapon == none)
		return;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	PrimaryWeapon = XComGameState_Item(NewGameState.ModifyStateObject(class'XComGameState_Item', PrimaryWeapon.ObjectID));
	if (UnitState.RemoveItemFromInventory(PrimaryWeapon, NewGameState) && XComHQ != none)
		XComHQ.PutItemInInventory(NewGameState, PrimaryWeapon);
}

// No primary weapon (see UT_TraitBase.IsItemBlocked).
static function bool IsItemBlocked(EInventorySlot Slot, X2ItemTemplate ItemTemplate, out string DisabledReason)
{
	if (Slot != eInvSlot_PrimaryWeapon)
		return false;

	DisabledReason = default.ManiacExplosiveNoPrimaryReason;
	return true;
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

// UT_TraitBase.UpdateAnimations (CHL #24). The sets are read from the weapon archetype itself (XComWeapon.CustomUnitPawnAnimsets,
// the female list for a female soldier when it has one), so no AnimSet asset name is hard-coded.
static function UpdateAnimations(out array<AnimSet> CustomAnimSets, XComGameState_Unit UnitState, XComUnitPawn Pawn)
{
	local XComWeapon Archetype;
	local array<AnimSet> Sets;
	local AnimSet Set;

	if (!default.MANIAC_UNARMED_ANIMS_ENABLED || default.MANIAC_UNARMED_WEAPON_ARCHETYPE == "" || UnitState == none || !UnitState.IsSoldier())
		return;

	// Only while really unarmed (a Maniac cannot equip a primary weapon, but one can still be there before OnGrant strips it).
	if (UnitState.GetPrimaryWeapon() != none)
		return;

	Archetype = XComWeapon(`CONTENT.RequestGameArchetype(default.MANIAC_UNARMED_WEAPON_ARCHETYPE));
	if (Archetype == none)
	{
		`log("UniqueTraits [WARN] : Maniac unarmed stance -- archetype '" $ default.MANIAC_UNARMED_WEAPON_ARCHETYPE $ "' not found",, 'UniqueTraits');
		return;
	}

	if (UnitState.kAppearance.iGender == eGender_Female && Archetype.CustomUnitPawnAnimsetsFemale.Length > 0)
		Sets = Archetype.CustomUnitPawnAnimsetsFemale;
	else
		Sets = Archetype.CustomUnitPawnAnimsets;

	foreach Sets(Set)
		CustomAnimSets.AddItem(Set);
}
