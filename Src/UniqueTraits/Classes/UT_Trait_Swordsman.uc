//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Swordsman.uc
//  PURPOSE: Swordsman [LWOTC ONLY]: melee damage and armor pierce scale with the melee weapon's Tier (see
//           X2Effect_UT_Swordsman), -1 damage on firearms. LWOTC-only because the pistol restriction targets
//           LWOTC's own pistol slot (the slot block lives in
//           X2DownloadableContentInfo_UniqueTraits.CanAddItemToInventory_CH_Improved, the CPS pistol row block
//           in X2EventListener_UniqueTraits; OnGrant strips the pistol the unit already carries).
//---------------------------------------------------------------------------------------
class UT_Trait_Swordsman extends UT_TraitBase config(UniqueTraits);

var localized string SwordsmanNoPistolReason;

var config array<int> SWORDSMAN_MELEE_BONUS_BY_TIER;
var config int SWORDSMAN_FIREARM_DAMAGE_REDUCTION;
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

	Template = PurePassive('UT_Swordsman', "img:///UniqueTraits_Icons.UT_Swordsman", true);

	SwordEffect = new class'X2Effect_UT_Swordsman';
	SwordEffect.EffectName = 'UT_Swordsman_Effect';
	SwordEffect.MeleeBonusByTier = default.SWORDSMAN_MELEE_BONUS_BY_TIER;
	SwordEffect.FirearmDamageReduction = default.SWORDSMAN_FIREARM_DAMAGE_REDUCTION;
	SwordEffect.BuildPersistentEffect(1, true, false);
	SwordEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(SwordEffect);

	return Template;
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
