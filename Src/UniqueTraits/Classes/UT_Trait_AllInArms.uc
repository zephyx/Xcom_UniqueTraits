//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_AllInArms.uc
//  PURPOSE: All in arms (reworked 2026-10-30. the first version was -2 mobility and +5 throw range). Three effects, each with a base value and a value
//           from the rank ALLINARMS_STAFF_RANK (LWOTC 5, Staff Sergeant, the base game has no such rank: edit the ini). The values are TOTALS, the rank value replaces the base one:
//           - MOBILITY: -ALLINARMS_MOBILITY, then -ALLINARMS_MOBILITY_STAFF. A PERMANENT change of the base stat through the ledger (UT_TraitBase.ShiftStatTo), like Athlete's, so the
//             Armory shows the real mobility (a combat effect cannot be previewed by rank): SyncStats, OnGrant, OnRankUp, OnClear (RevertShifts), OnStatsReset, OnMigrate (version 2).
//           - HAND-THROW RANGE: +ALLINARMS_THROW_RANGE, then +ALLINARMS_THROW_RANGE_STAFF tiles, the global 'OnGetItemRange_AllInArms' listener (read when used).
//           - FREE FLASHBANGS: ALLINARMS_FLASHBANG_COUNT, then ALLINARMS_FLASHBANG_COUNT_STAFF, granted at the start of each mission as a stack in the utility slot
//             (X2Effect_UT_AllInArmsGrenades, a X2Effect_UT_TemporaryItem that counts from the rank).
//---------------------------------------------------------------------------------------
class UT_Trait_AllInArms extends UT_TraitBase config(UniqueTraits);

var config int ALLINARMS_STAFF_RANK;
var config int ALLINARMS_MOBILITY, ALLINARMS_MOBILITY_STAFF;
var config int ALLINARMS_THROW_RANGE, ALLINARMS_THROW_RANGE_STAFF;
var config int ALLINARMS_FLASHBANG_COUNT, ALLINARMS_FLASHBANG_COUNT_STAFF;
var config name ALLINARMS_FLASHBANG_ITEM_NAME;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(AllInArms());

	return Templates;
}

// Event registrations (X2EventListener_UniqueTraits.CreateTacticalListeners calls this for every trait of the pool that is not disabled).
static function OnCreateTacticalListeners(CHEventListenerTemplate Template)
{
	Template.AddCHEvent('OnGetItemRange', OnGetItemRange_AllInArms, ELD_Immediate, 50);
}

// The ability holds the free flashbangs, the mobility is a permanent change (see above) and the hand-throw range a global 'OnGetItemRange_AllInArms' listener, since that
// event fires on the item, not through an effect on the unit, and needs to tell hand-thrown items (grenade pocket / utility slot) apart from grenade launchers, rocket
// launchers and gauntlets.
static function X2AbilityTemplate AllInArms()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_AllInArmsGrenades GrenadeEffect;

	Template = PurePassive('UT_AllInArms', "img:///UniqueTraits_Icons.UT_AllInArms", true);

	GrenadeEffect = new class'X2Effect_UT_AllInArmsGrenades';
	GrenadeEffect.EffectName = 'UT_AllInArms_FreeFlashbangs';
	GrenadeEffect.ItemName = default.ALLINARMS_FLASHBANG_ITEM_NAME;
	GrenadeEffect.ItemInventorySlot = eInvSlot_Utility;
	// One icon with a stack of N (added to any flashbang the holder already carries) instead of N separate icons.
	GrenadeEffect.bStackOnExisting = true;
	GrenadeEffect.BuildPersistentEffect(1, true, false);
	GrenadeEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(GrenadeEffect);

	return Template;
}

// The ranks that count as "Staff Sergeant" (live: the texts compute the rank name from the same value).
static final function bool IsStaffRank(XComGameState_Unit Unit)
{
	return Unit.GetRank() >= default.ALLINARMS_STAFF_RANK;
}

static function bool ShiftsStats()
{
	return true;
}

// The mobility the rank calls for: a negative number, the staff value replacing the base one.
static final function bool SyncStats(XComGameState_Unit MutableUnit)
{
	local int Wanted;

	Wanted = -(IsStaffRank(MutableUnit) ? default.ALLINARMS_MOBILITY_STAFF : default.ALLINARMS_MOBILITY);

	return ShiftStatTo(MutableUnit, eStat_Mobility, Wanted);
}

static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	// A soldier who is already ranked (AddUniqueTrait) gets the value of his rank at once.
	SyncStats(MutableUnit);
}

// The trait is already out of AcquiredTraits here: the mobility goes back to what it was, exactly.
static function OnClear(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	RevertShifts(MutableUnit);
}

// 'UnitRankUp': a real promotion.
static function bool OnRankUp(XComGameState_Unit MutableUnit)
{
	return SyncStats(MutableUnit);
}

// The base stats were rebuilt by a respec: what the trait had put in them is gone.
static function OnStatsReset(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	ForgetShifts(MutableUnit);
	SyncStats(MutableUnit);
}

// Version 2 (first version: -2 mobility as a stat effect, +5 range): the holders get their mobility through the ledger. The old effect is gone with its template.
static function OnMigrate(XComGameState_Unit MutableUnit, int FromVersion, XComGameState NewGameState)
{
	if (FromVersion == 1)
		SyncStats(MutableUnit);
}

// The name of the staff rank for the texts (UT_TextTags): the rank name of the base game / LWOTC, or the number when the rank is out of the configured range.
static function bool GetTextValue(string Key, out string OutString)
{
	local int Rank;

	if (!(Key ~= "ALLINARMS_STAFF_RANK_NAME"))
		return false;

	Rank = default.ALLINARMS_STAFF_RANK;
	if (Rank >= 0 && Rank <= class'X2ExperienceConfig'.static.GetMaxRank())
		OutString = class'X2ExperienceConfig'.static.GetRankName(Rank, '');
	else
		OutString = string(Rank);

	return true;
}

// All in arms: + throw range, but only for items actually thrown by hand (carried in the grenade pocket or a utility slot).
static function EventListenerReturn OnGetItemRange_AllInArms(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;
	local X2WeaponTemplate ItemTemplate;
	local XComGameState_Unit OwnerUnit;

	if (!ParseItemRangeEvent(EventData, EventSource, Tuple, ItemTemplate, OwnerUnit))
		return ELR_NoInterrupt;

	if ((ItemTemplate.InventorySlot == eInvSlot_GrenadePocket || ItemTemplate.InventorySlot == eInvSlot_Utility)
		&& class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(OwnerUnit, 'UT_AllInArms'))
	{
		Tuple.Data[1].i += IsStaffRank(OwnerUnit) ? default.ALLINARMS_THROW_RANGE_STAFF : default.ALLINARMS_THROW_RANGE;
	}

	return ELR_NoInterrupt;
}
