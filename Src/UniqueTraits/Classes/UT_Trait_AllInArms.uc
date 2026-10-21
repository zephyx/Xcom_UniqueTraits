//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_AllInArms.uc
//  PURPOSE: All in arms: -mobility here; the hand-throw range bonus is the global 'OnGetItemRange_AllInArms' listener.
//---------------------------------------------------------------------------------------
class UT_Trait_AllInArms extends UT_TraitBase config(UniqueTraits);

var config int ALLINARMS_THROW_RANGE;

var config int ALLINARMS_MOBILITY;

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

// All in arms: -2 mobility. The +5 hand-throw range bonus is handled by a global
// 'OnGetItemRange_AllInArms' listener (X2EventListener_UniqueTraits) since that event fires on the
// item, not through an effect on the unit, and needs to tell hand-thrown items (grenade
// pocket / utility slot) apart from grenade launchers, rocket launchers and gauntlets.
static function X2AbilityTemplate AllInArms()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;

	`CREATE_X2ABILITY_TEMPLATE(Template, 'UT_AllInArms');
	Template.IconImage = "img:///UniqueTraits_Icons.UT_AllInArms";
	Template.eAbilityIconBehaviorHUD = eAbilityIconBehavior_NeverShow;
	Template.AbilityToHitCalc = default.DeadEye;
	Template.AbilityTargetStyle = default.SelfTarget;
	Template.AbilityTriggers.AddItem(default.UnitPostBeginPlayTrigger);
	Template.bIsPassive = true;
	Template.Hostility = eHostility_Neutral;
	Template.AbilitySourceName = 'eAbilitySource_Perk';

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.AddPersistentStatChange(eStat_Mobility, -default.ALLINARMS_MOBILITY);
	StatEffect.BuildPersistentEffect(1, true, false, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, true,, Template.AbilitySourceName);
	Template.AddTargetEffect(StatEffect);
	Template.bCrossClassEligible = true;

	Template.SetUIStatMarkup(class'XLocalizedData'.default.MobilityLabel, eStat_Mobility, -default.ALLINARMS_MOBILITY);

	Template.BuildNewGameStateFn = TypicalAbility_BuildGameState;

	return Template;
}

// All in arms: +ALLINARMS_THROW_RANGE throw range, but only for items actually thrown by hand (carried in the
// grenade pocket or a utility slot).
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
		Tuple.Data[1].i += default.ALLINARMS_THROW_RANGE;
	}

	return ELR_NoInterrupt;
}
