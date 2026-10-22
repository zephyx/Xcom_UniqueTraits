//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_QualityOverQuantity.uc
//  PURPOSE: Quality over quantity: the PRIMARY weapon gets a critical chance bonus by weapon tier (X2Effect_UT_QualityCrit,
//           QUALITY_CRIT_BY_TIER) but loses QUALITY_CLIP_REDUCTION from its clip size when that clip is at least
//           QUALITY_CLIP_MIN_FOR_REDUCTION ('OverrideClipSize' event, CHL #393, see OnOverrideClipSize_QualityOverQuantity).
//---------------------------------------------------------------------------------------
class UT_Trait_QualityOverQuantity extends UT_TraitBase config(UniqueTraits);

// Indexed by X2WeaponTemplate.Tier (vanilla 0/2/4, LWOTC adds 1/3), clamped to the last entry.
var config array<int> QUALITY_CRIT_BY_TIER;
var config int QUALITY_CLIP_REDUCTION;
var config int QUALITY_CLIP_MIN_FOR_REDUCTION;

// The smallest clip that is reduced: QUALITY_CLIP_MIN_FOR_REDUCTION, but always more than the reduction itself (minimum clip - reduction >= 1), whatever the ini or the Mod
// Config Menu give: the clip of a holder can never reach 0. The Mod Config Menu page keeps the two sliders in that relation (UniqueTraits_MCMScreen.EnforceClipRule).
static final function int GetMinClipForReduction()
{
	return Max(default.QUALITY_CLIP_MIN_FOR_REDUCTION, default.QUALITY_CLIP_REDUCTION + 1);
}

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(QualityOverQuantity());

	return Templates;
}

// Event registrations (X2EventListener_UniqueTraits.CreateSharedListeners calls this for every trait of the pool that is not disabled).
static function OnCreateSharedListeners(CHEventListenerTemplate Template)
{
	// Quality over quantity: -1 clip on the primary weapon (the armory shows the clip size too).
	Template.AddCHEvent('OverrideClipSize', OnOverrideClipSize_QualityOverQuantity, ELD_Immediate, 50);
}

static function X2AbilityTemplate QualityOverQuantity()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_QualityCrit CritEffect;

	Template = PurePassive('UT_QualityOverQuantity', "img:///UniqueTraits_Icons.UT_QualityOverQuantity", true);

	CritEffect = new class'X2Effect_UT_QualityCrit';
	CritEffect.EffectName = 'UT_QualityOverQuantity_Crit';
	CritEffect.CritByTier = default.QUALITY_CRIT_BY_TIER;
	CritEffect.BuildPersistentEffect(1, true, false);
	CritEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(CritEffect);

	return Template;
}

// 'OverrideClipSize' fires from XComGameState_Item.GetClipSize with the clip size after upgrades/ammo: this handler must never call
// GetClipSize on the same item (infinite recursion). The primary weapon of a holder loses a clip when it has enough of them.
static function EventListenerReturn OnOverrideClipSize_QualityOverQuantity(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;
	local XComGameState_Item ItemState;
	local XComGameState_Unit OwnerUnit;

	Tuple = XComLWTuple(EventData);
	ItemState = XComGameState_Item(EventSource);
	if (Tuple == none || ItemState == none || ItemState.InventorySlot != eInvSlot_PrimaryWeapon
		|| Tuple.Data[0].i < GetMinClipForReduction())
		return ELR_NoInterrupt;

	OwnerUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(ItemState.OwnerStateObject.ObjectID));
	if (OwnerUnit == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(OwnerUnit, 'UT_QualityOverQuantity'))
		return ELR_NoInterrupt;

	Tuple.Data[0].i = Max(1, Tuple.Data[0].i - default.QUALITY_CLIP_REDUCTION);

	return ELR_NoInterrupt;
}
