//---------------------------------------------------------------------------------------
//  FILE:   X2Ability_UniqueTraits_Items.uc
//  PURPOSE: Traits whose mechanic lives mostly in a custom CHItemSlot / inventory
//           restriction (see X2ItemSlot_UniqueTraits.uc and
//           X2DownloadableContentInfo_UniqueTraits.CanAddItemToInventory_CH_Improved), plus
//           Maniac explosive's second, activated ability (ManiacImproviseGrenade).
//---------------------------------------------------------------------------------------
class X2Ability_UniqueTraits_Items extends X2Ability config(UniqueTraits);

var config name SUPPORT_MEDIKIT_ITEM_NAME;
var config name MANIAC_IMPROVISE_GRENADE_ITEM_NAME;
var config int MANIAC_IMPROVISE_CHARGES;
var config int MANIAC_IMPROVISE_COOLDOWN;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Support());
	Templates.AddItem(ManiacExplosive());
	Templates.AddItem(ManiacImproviseGrenade());

	return Templates;
}

// Support: the vest slot itself is implemented by the UT_SupportVestSlot CHItemSlot template in
// X2ItemSlot_UniqueTraits.uc.
// The free medikit is granted the same way LWOTC's own Corpsman/XMBEffect_AddUtilityItem grants its free medikit.
static function X2AbilityTemplate Support()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_TemporaryItem MedikitEffect;

	Template = PurePassive('UT_Support', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	MedikitEffect = new class'X2Effect_UT_TemporaryItem';
	MedikitEffect.EffectName = 'UT_Support_FreeMedikit';
	MedikitEffect.ItemName = default.SUPPORT_MEDIKIT_ITEM_NAME;
	MedikitEffect.ItemInventorySlot = eInvSlot_Vest;
	MedikitEffect.BuildPersistentEffect(1, true, false);
	MedikitEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(MedikitEffect);

	return Template;
}

// Maniac explosive: this passive is just the icon holder. The +3 grenade pockets are
// implemented by the UT_ManiacExtraPockets CHItemSlot template in
// X2ItemSlot_UniqueTraits.uc; the primary weapon block is implemented in
// X2DownloadableContentInfo_UniqueTraits.CanAddItemToInventory_CH_Improved.
static function X2AbilityTemplate ManiacExplosive()
{
	local X2AbilityTemplate Template;

	Template = PurePassive('UT_ManiacExplosive', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	return Template;
}

// Maniac explosive's second granted ability: a limited-use activated ability that conjures a
// free frag grenade out of nothing, added permanently to the holder's inventory for the rest of
// the mission
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
