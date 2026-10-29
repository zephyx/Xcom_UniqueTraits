//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_ManiacExplosive.uc
//  PURPOSE: Maniac explosive. UT_ManiacExplosive carries the malus of the PRIMARY weapon by weapon tier (X2Effect_UT_PrimaryWeaponMalus: flat BASE damage
//           and critical chance, indexed by X2WeaponTemplate.WeaponTech through MANIAC_WEAPON_TECHS); the +1 grenade pocket is the UT_ManiacExtraPockets
//           CHItemSlot template (CreateExtraPocketsSlot below, registered by X2ItemSlot_UniqueTraits.uc).
//           Its second ability, UT_ManiacBreak ("Break!"), is a free action with a cooldown that puts X2Effect_UT_ManiacBreak on the holder until the
//           end of the turn: his grenades deal more damage to units (per rank) and more environment damage (a base amount plus an amount per rank,
//           added to the grenade's own environment damage events by X2Effect_UT_ManiacBreakWorld, which OnPostTemplatesCreated below appends to the
//           effects of every grenade). If the holder caused no environment damage during that turn the cooldown is shortened
//           (X2Effect_UT_ManiacBreak.OnEffectRemoved).
//---------------------------------------------------------------------------------------
class UT_Trait_ManiacExplosive extends UT_TraitBase config(UniqueTraits);

var config int MANIAC_EXTRA_GRENADE_POCKETS;
var localized string ManiacPocketsSlotName, ManiacPocketsSlotLetter;

// Malus of the primary weapon by tier: parallel lists, line N of the techs pairs with line N of the damage and the critical malus. A weapon whose
// WeaponTech is not listed (another mod's) takes the LAST line.
var config array<name> MANIAC_WEAPON_TECHS;
var config array<int> MANIAC_PRIMARY_DAMAGE_MALUS;
var config array<int> MANIAC_PRIMARY_CRIT_MALUS;

// Break!
var config int MANIAC_BREAK_COOLDOWN;
var config int MANIAC_BREAK_COOLDOWN_REFUND;
var config int MANIAC_BREAK_ENV_BASE;
var config int MANIAC_BREAK_ENV_PER_RANK;
var config float MANIAC_BREAK_DAMAGE_PER_RANK;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(ManiacExplosive());
	Templates.AddItem(ManiacBreak());

	return Templates;
}

static function X2AbilityTemplate ManiacExplosive()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_PrimaryWeaponMalus MalusEffect;

	Template = PurePassive('UT_ManiacExplosive', "img:///UniqueTraits_Icons.UT_ManiacExplosive", true);

	MalusEffect = new class'X2Effect_UT_PrimaryWeaponMalus';
	MalusEffect.EffectName = 'UT_ManiacExplosive_PrimaryWeaponMalus';
	MalusEffect.WeaponTechs = default.MANIAC_WEAPON_TECHS;
	MalusEffect.DamageByTier = default.MANIAC_PRIMARY_DAMAGE_MALUS;
	MalusEffect.CritByTier = default.MANIAC_PRIMARY_CRIT_MALUS;
	MalusEffect.BuildPersistentEffect(1, true, false);
	MalusEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(MalusEffect);

	return Template;
}

static function X2AbilityTemplate ManiacBreak()
{
	local X2AbilityTemplate Template;
	local X2AbilityCost_ActionPoints ActionPointCost;
	local X2AbilityCooldown Cooldown;
	local X2Effect_UT_ManiacBreak BreakEffect;

	`CREATE_X2ABILITY_TEMPLATE(Template, 'UT_ManiacBreak');

	Template.IconImage = "img:///UniqueTraits_Icons.UT_ManiacExplosive_Break";
	Template.AbilitySourceName = 'eAbilitySource_Perk';
	Template.eAbilityIconBehaviorHUD = eAbilityIconBehavior_AlwaysShow;
	Template.Hostility = eHostility_Neutral;
	Template.bShowActivation = true;

	Template.AbilityToHitCalc = default.DeadEye;
	Template.AbilityTargetStyle = default.SelfTarget;
	Template.AbilityTriggers.AddItem(default.PlayerInputTrigger);
	Template.AbilityShooterConditions.AddItem(default.LivingShooterProperty);
	Template.AddShooterEffectExclusions();

	// A free action: iNumPoints 1 AND bFreeCost, so it needs an action point left but takes none.
	ActionPointCost = new class'X2AbilityCost_ActionPoints';
	ActionPointCost.iNumPoints = 1;
	ActionPointCost.bFreeCost = true;
	Template.AbilityCosts.AddItem(ActionPointCost);

	Cooldown = new class'X2AbilityCooldown';
	Cooldown.iNumTurns = default.MANIAC_BREAK_COOLDOWN;
	Template.AbilityCooldown = Cooldown;

	BreakEffect = new class'X2Effect_UT_ManiacBreak';
	BreakEffect.EffectName = 'UT_ManiacBreak_Active';
	BreakEffect.DamagePerRank = default.MANIAC_BREAK_DAMAGE_PER_RANK;
	BreakEffect.CooldownRefund = default.MANIAC_BREAK_COOLDOWN_REFUND;
	// Until the end of the holder's turn.
	BreakEffect.BuildPersistentEffect(1, false, true, false, eGameRule_PlayerTurnEnd);
	BreakEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, true,, Template.AbilitySourceName);
	Template.AddTargetEffect(BreakEffect);

	Template.BuildNewGameStateFn = TypicalAbility_BuildGameState;
	Template.BuildVisualizationFn = TypicalAbility_BuildVisualization;
	Template.bSkipFireAction = true;
	Template.ChosenActivationIncreasePerUse = class'X2AbilityTemplateManager'.default.NonAggressiveChosenActivationIncreasePerUse;

	return Template;
}

// UT_TraitBase.OnPostTemplatesCreated (called for every trait of the pool by X2DownloadableContentInfo_UniqueTraits).
// Break!'s environment damage is an effect of the GRENADE: it is read from the item at activation time, in every difficulty variant of the item
// (see UT_Trait_MeatTenderizer.OnPostTemplatesCreated for the reason), so one X2Effect_UT_ManiacBreakWorld is appended to the thrown and launched
// effects of each grenade that has a damage effect. Appended, never inserted: the effects are looked up by their index. The effect does nothing for a
// thrower that is not under Break!.
static function OnPostTemplatesCreated()
{
	local X2ItemTemplateManager ItemManager;
	local array<name> TemplateNames;
	local array<X2DataTemplate> Variants;
	local X2DataTemplate DataTemplate;
	local X2GrenadeTemplate GrenadeTemplate;
	local name TemplateName;

	ItemManager = class'X2ItemTemplateManager'.static.GetItemTemplateManager();
	ItemManager.GetTemplateNames(TemplateNames);
	foreach TemplateNames(TemplateName)
	{
		Variants.Length = 0;
		ItemManager.FindDataTemplateAllDifficulties(TemplateName, Variants);
		foreach Variants(DataTemplate)
		{
			GrenadeTemplate = X2GrenadeTemplate(DataTemplate);
			if (GrenadeTemplate == none)
				continue;

			AppendWorldEffect(GrenadeTemplate.ThrownGrenadeEffects);
			AppendWorldEffect(GrenadeTemplate.LaunchedGrenadeEffects);
		}
	}
}

static final function AppendWorldEffect(out array<X2Effect> Effects)
{
	local X2Effect Effect;
	local bool bHasDamage;

	foreach Effects(Effect)
	{
		if (X2Effect_UT_ManiacBreakWorld(Effect) != none)
			return;
		if (X2Effect_ApplyWeaponDamage(Effect) != none)
			bHasDamage = true;
	}

	if (bHasDamage)
		Effects.AddItem(new class'X2Effect_UT_ManiacBreakWorld');
}

//---------------------------------------------------------------------------------------
// Maniac explosive: extra multi-item grenade pockets (MANIAC_EXTRA_GRENADE_POCKETS), holding any grenade (including rockets),
// same as the vanilla Grenade Pocket.
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
