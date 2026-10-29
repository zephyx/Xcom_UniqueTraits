//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Swordsman.uc
//  PURPOSE: Swordsman [LWOTC ONLY] (reworked 2026-10-30): +SWORDSMAN_MOBILITY_BONUS Mobility in missions (a plain stat effect, like Support's), then
//           melee bonuses by RANK (see X2Effect_UT_Swordsman): armor pierce at SWORDSMAN_PIERCE_RANK (LWOTC 3, Corporal), a floor of (minimum + 1) on the melee roll
//           at SWORDSMAN_MIN_DAMAGE_RANK (5, Staff Sergeant), +1 melee damage at SWORDSMAN_DAMAGE_RANK (7, Gunnery Sergeant). -1 damage on firearms while a melee
//           weapon is carried in the primary or secondary slot. No pistol outside the primary slot. LWOTC-only because the pistol restriction targets
//           LWOTC's own pistol slot (the slot block lives in
//           X2DownloadableContentInfo_UniqueTraits.CanAddItemToInventory_CH_Improved, the CPS pistol row block
//           in X2EventListener_UniqueTraits; OnGrant strips the pistol the unit already carries).
//---------------------------------------------------------------------------------------
class UT_Trait_Swordsman extends UT_TraitBase config(UniqueTraits);

var localized string SwordsmanNoPistolReason;

var config int SWORDSMAN_MOBILITY_BONUS;
var config int SWORDSMAN_PIERCE_BONUS, SWORDSMAN_PIERCE_RANK;
var config int SWORDSMAN_MIN_DAMAGE_BONUS, SWORDSMAN_MIN_DAMAGE_RANK;
var config int SWORDSMAN_DAMAGE_BONUS, SWORDSMAN_DAMAGE_RANK;
var config int SWORDSMAN_FIREARM_DAMAGE_REDUCTION;
// WeaponCats counted as "a melee weapon" for the firearm malus (swords, ripjack, claymore, gauntlets, knives, other melee).
var config array<name> SWORDSMAN_MELEE_WEAPON_CATS;
// WeaponCats counted as "pistol" for the pistol ban: 'pistol' (pistols, LWOTC's) and 'sidearm' (WOTC's automatic pistol).
var config array<name> SWORDSMAN_BANNED_PISTOL_CATS;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Swordsman());

	return Templates;
}

// Event registrations (X2EventListener_UniqueTraits.CreateStrategyListeners calls this for every trait of the pool that is not disabled).
static function OnCreateStrategyListeners(CHEventListenerTemplate Template)
{
	// Optional soft dependency: only fires if the "Community Promotion Screen" mod is loaded. Priority 1 = runs AFTER
	// every other listener (larger number runs first): a block is only a block if no later listener of another mod
	// flips bCanPurchaseAbility back to true.
	Template.AddCHEvent('CPS_OverrideCanPurchaseAbility', OnCPSOverrideCanPurchaseAbility_Swordsman, ELD_Immediate, 1);
	// Support / Swordsman: hide (not just gray out) forbidden items from the Armory picker.
	Template.AddCHEvent('OverrideShowItemInLockerList', OnOverrideShowItemInLockerList_Swordsman, ELD_Immediate, 50);
}

static function X2AbilityTemplate Swordsman()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_Swordsman SwordEffect;
	local X2Effect_PersistentStatChange MobilityEffect;

	Template = PurePassive('UT_Swordsman', "img:///UniqueTraits_Icons.UT_Swordsman", true);

	SwordEffect = new class'X2Effect_UT_Swordsman';
	SwordEffect.EffectName = 'UT_Swordsman_Effect';
	SwordEffect.PierceBonus = default.SWORDSMAN_PIERCE_BONUS;
	SwordEffect.MinDamageBonus = default.SWORDSMAN_MIN_DAMAGE_BONUS;
	SwordEffect.DamageBonus = default.SWORDSMAN_DAMAGE_BONUS;
	SwordEffect.FirearmDamageReduction = default.SWORDSMAN_FIREARM_DAMAGE_REDUCTION;
	SwordEffect.MeleeWeaponCats = default.SWORDSMAN_MELEE_WEAPON_CATS;
	SwordEffect.BuildPersistentEffect(1, true, false);
	SwordEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(SwordEffect);

	// +Mobility in missions only (a combat effect, no permanent stat, no ledger); the Armory header adds it through the UI markup, like Support's.
	MobilityEffect = new class'X2Effect_PersistentStatChange';
	MobilityEffect.EffectName = 'UT_Swordsman_MobilityBonus';
	MobilityEffect.BuildPersistentEffect(1, true, false);
	MobilityEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	MobilityEffect.AddPersistentStatChange(eStat_Mobility, default.SWORDSMAN_MOBILITY_BONUS);
	Template.AddTargetEffect(MobilityEffect);

	Template.SetUIStatMarkup(class'XLocalizedData'.default.MobilityLabel, eStat_Mobility, default.SWORDSMAN_MOBILITY_BONUS);

	return Template;
}

// The names of the three ranks for the texts (UT_TextTags): the rank name of the base game / LWOTC, or the number when the rank is out of the configured range.
static function bool GetTextValue(string Key, out string OutString)
{
	local int Rank;

	if (Key ~= "SWORDSMAN_PIERCE_RANK_NAME")
		Rank = default.SWORDSMAN_PIERCE_RANK;
	else if (Key ~= "SWORDSMAN_MIN_DAMAGE_RANK_NAME")
		Rank = default.SWORDSMAN_MIN_DAMAGE_RANK;
	else if (Key ~= "SWORDSMAN_DAMAGE_RANK_NAME")
		Rank = default.SWORDSMAN_DAMAGE_RANK;
	else
		return false;

	if (Rank >= 0 && Rank <= class'X2ExperienceConfig'.static.GetMaxRank())
		OutString = class'X2ExperienceConfig'.static.GetRankName(Rank, '');
	else
		OutString = string(Rank);

	return true;
}

static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	RemoveSwordsmanPistol(MutableUnit, NewGameState);
}

// The pistol block (CanAddItemToInventory_CH_Improved) only stops FUTURE equips.
static final function RemoveSwordsmanPistol(XComGameState_Unit UnitState, XComGameState NewGameState)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_Item PistolItem;
	local array<EInventorySlot> PistolSlots;
	local EInventorySlot PistolSlot;

	PistolSlots.AddItem(eInvSlot_Pistol);
	PistolSlots.AddItem(eInvSlot_SecondaryWeapon);

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	foreach PistolSlots(PistolSlot)
	{
		PistolItem = UnitState.GetItemInSlot(PistolSlot, NewGameState);
		if (PistolItem == none || !IsSwordsmanPistolBlockedSlot(PistolSlot, PistolItem.GetMyTemplate()))
			continue;

		PistolItem = XComGameState_Item(NewGameState.ModifyStateObject(class'XComGameState_Item', PistolItem.ObjectID));
		if (UnitState.RemoveItemFromInventory(PistolItem, NewGameState) && XComHQ != none)
			XComHQ.PutItemInInventory(NewGameState, PistolItem);
	}
}

// Swordsman's "no pistol": any weapon whose category is in SWORDSMAN_BANNED_PISTOL_CATS ('pistol' and 'sidearm', the
// automatic pistol).
static final function bool IsPistolTemplate(const X2ItemTemplate ItemTemplate)
{
	local X2WeaponTemplate WeaponTemplate;

	WeaponTemplate = X2WeaponTemplate(ItemTemplate);
	return WeaponTemplate != none && default.SWORDSMAN_BANNED_PISTOL_CATS.Find(WeaponTemplate.WeaponCat) != INDEX_NONE;
}

// LWOTC keeps pistols in its own dedicated slot (eInvSlot_Pistol, CHItemSlot_PistolSlot_LW), so Swordsman
// blocks that slot outright; the secondary slot is only blocked for pistol-category weapons.
static final function bool IsSwordsmanPistolBlockedSlot(EInventorySlot Slot, const X2ItemTemplate ItemTemplate)
{
	return Slot == eInvSlot_Pistol || (Slot == eInvSlot_SecondaryWeapon && IsPistolTemplate(ItemTemplate));
}

// Swordsman: nothing listed for LWOTC's pistol slot, no pistol listed for the secondary slot.
static function EventListenerReturn OnOverrideShowItemInLockerList_Swordsman(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
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
	if (Slot != eInvSlot_SecondaryWeapon && Slot != eInvSlot_Pistol)
		return ELR_NoInterrupt;

	UnitState = XComGameState_Unit(Tuple.Data[2].o);
	if (UnitState != none
		&& IsSwordsmanPistolBlockedSlot(Slot, ItemState.GetMyTemplate())
		&& class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_Swordsman'))
		Tuple.Data[0].b = false;

	return ELR_NoInterrupt;
}

// 'CPS_OverrideCanPurchaseAbility' (optional Community Promotion Screen hook): Swordsman can't buy the pistol ability row.
static function EventListenerReturn OnCPSOverrideCanPurchaseAbility_Swordsman(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;
	local XComGameState_Unit UnitState;

	Tuple = XComLWTuple(EventData);
	UnitState = XComGameState_Unit(EventSource);
	if (Tuple == none || UnitState == none || Tuple.Data.Length < 16)
		return ELR_NoInterrupt;

	if (class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_Swordsman'))
		BlockSwordsmanPistolAbility(Tuple, UnitState);

	return ELR_NoInterrupt;
}

// Swordsman: blocks buying a class ability tied to the pistol (secondary or pistol slot)
static function BlockSwordsmanPistolAbility(XComLWTuple Tuple, XComGameState_Unit UnitState)
{
	local X2SoldierClassTemplate ClassTemplate;
	local array<SoldierClassAbilityType> Possible;
	local SoldierClassAbilityType AbilityType;
	local SoldierClassWeaponType AllowedWeapon;
	local SoldierRankAbilities RankAbilities;
	local bool bPistolSecondary;

	// LWOTC's pistol row: the unit's own tree already has these abilities re-slotted to eInvSlot_Pistol
	// (X2DownloadableContentInfo_LongWarOfTheChosen, ~line 1100), whatever the class template says.
	foreach UnitState.AbilityTree(RankAbilities)
	{
		foreach RankAbilities.Abilities(AbilityType)
		{
			if (AbilityType.AbilityName == Tuple.Data[0].n && AbilityType.ApplyToWeaponSlot == eInvSlot_Pistol)
			{
				Tuple.Data[13].b = false;
				Tuple.Data[15].s = default.SwordsmanNoPistolReason;
				return;
			}
		}
	}

	// Vanilla-style class whose secondary slot is a pistol.
	ClassTemplate = UnitState.GetSoldierClassTemplate();
	if (ClassTemplate == none)
		return;

	foreach ClassTemplate.AllowedWeapons(AllowedWeapon)
	{
		if (AllowedWeapon.SlotType == eInvSlot_SecondaryWeapon
			&& default.SWORDSMAN_BANNED_PISTOL_CATS.Find(AllowedWeapon.WeaponType) != INDEX_NONE)
		{
			bPistolSecondary = true;
			break;
		}
	}
	if (!bPistolSecondary)
		return;

	Possible = ClassTemplate.GetAllPossibleAbilities();
	foreach Possible(AbilityType)
	{
		if (AbilityType.AbilityName == Tuple.Data[0].n
			&& (AbilityType.ApplyToWeaponSlot == eInvSlot_SecondaryWeapon || AbilityType.ApplyToWeaponSlot == eInvSlot_Pistol))
		{
			Tuple.Data[13].b = false;
			Tuple.Data[15].s = default.SwordsmanNoPistolReason;
			return;
		}
	}
}

// No pistol (see UT_TraitBase.IsItemBlocked).
static function bool IsItemBlocked(EInventorySlot Slot, X2ItemTemplate ItemTemplate, out string DisabledReason)
{
	if (!IsSwordsmanPistolBlockedSlot(Slot, ItemTemplate))
		return false;

	DisabledReason = default.SwordsmanNoPistolReason;
	return true;
}
