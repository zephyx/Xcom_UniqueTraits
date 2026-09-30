//---------------------------------------------------------------------------------------
//  FILE:   X2Ability_UniqueTraits_Core.uc
//  PURPOSE: The simplest traits -- pure stat passives, built entirely from base-game
//           effect classes (X2Effect_PersistentStatChange, X2Effect_MeleeDamageAdjust,
//           X2Effect_ModifyReactionFire). No custom effect classes needed.
//---------------------------------------------------------------------------------------
class X2Ability_UniqueTraits_Core extends X2Ability config(UniqueTraits);

var config int ATHLETE_MOBILITY, ATHLETE_DODGE, ATHLETE_AIM, ATHLETE_CRIT;
var config int NERD_HACKING_BASE, NERD_HACKING_PER_RANK;
var config int NERD_WILL_BASE, NERD_WILL_PER_RANK;
var config int NERD_MELEE_DAMAGE_TAKEN;
var config int GUARD_AIM, GUARD_OVERWATCH_AIM;
var config int TACTICIAN_AIM;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Athlete());
	Templates.AddItem(Nerd());
	Templates.AddItem(Guard());
	Templates.AddItem(Tactician());

	return Templates;
}

// Athlete: +3 mobility, +15 dodge, -5 aim, -10 crit chance.
static function X2AbilityTemplate Athlete()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;

	Template = PurePassive('UT_Athlete', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_Athlete';
	StatEffect.BuildPersistentEffect(1, true, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_Mobility, default.ATHLETE_MOBILITY);
	StatEffect.AddPersistentStatChange(eStat_Dodge, default.ATHLETE_DODGE);
	StatEffect.AddPersistentStatChange(eStat_Offense, -default.ATHLETE_AIM);
	StatEffect.AddPersistentStatChange(eStat_CritChance, -default.ATHLETE_CRIT);
	Template.AddTargetEffect(StatEffect);

	Template.SetUIStatMarkup(class'XLocalizedData'.default.MobilityLabel, eStat_Mobility, default.ATHLETE_MOBILITY);
	Template.SetUIStatMarkup(class'XLocalizedData'.default.DodgeLabel, eStat_Dodge, default.ATHLETE_DODGE);
	Template.SetUIStatMarkup(class'XLocalizedData'.default.AimLabel, eStat_Offense, -default.ATHLETE_AIM);
	Template.SetUIStatMarkup(class'XLocalizedData'.default.CritChanceLabel, eStat_CritChance, -default.ATHLETE_CRIT);

	return Template;
}

// Nerd: +10 hacking / -5 will on promotion, then +4 hacking / -2 will on every rank gained
// after that (on top of whatever hacking/will the soldier's class normally grants at that
// rank in X2DownloadableContentInfo_UniqueTraits.ApplyNerdRankScaling (called from the general
// 'UnitRankUp' listener for every rank-up past the first, natural or not.
// Takes 2 extra damage from melee attacks.
static function X2AbilityTemplate Nerd()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;
	local X2Effect_MeleeDamageAdjust MeleeEffect;

	Template = PurePassive('UT_Nerd', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_Nerd';
	StatEffect.BuildPersistentEffect(1, true, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_Hacking, default.NERD_HACKING_BASE);
	StatEffect.AddPersistentStatChange(eStat_Will, -default.NERD_WILL_BASE);
	Template.AddTargetEffect(StatEffect);

	Template.SetUIStatMarkup(class'XLocalizedData'.default.TechLabel, eStat_Hacking, default.NERD_HACKING_BASE);
	Template.SetUIStatMarkup(class'XLocalizedData'.default.WillLabel, eStat_Will, -default.NERD_WILL_BASE);

	MeleeEffect = new class'X2Effect_MeleeDamageAdjust';
	MeleeEffect.EffectName = 'UT_Nerd_MeleeVulnerability';
	MeleeEffect.DamageMod = default.NERD_MELEE_DAMAGE_TAKEN;
	MeleeEffect.BuildPersistentEffect(1, true, false);
	MeleeEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	Template.AddTargetEffect(MeleeEffect);

	return Template;
}

// Guard: -20 aim, +35 aim on overwatch/reaction shots and those shots can crit.
static function X2AbilityTemplate Guard()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;
	local X2Effect_ModifyReactionFire ReactionEffect;

	Template = PurePassive('UT_Guard', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_Guard';
	StatEffect.BuildPersistentEffect(1, true, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_Offense, -default.GUARD_AIM);
	Template.AddTargetEffect(StatEffect);

	Template.SetUIStatMarkup(class'XLocalizedData'.default.AimLabel, eStat_Offense, -default.GUARD_AIM);

	ReactionEffect = new class'X2Effect_ModifyReactionFire';
	ReactionEffect.EffectName = 'UT_Guard_Overwatch';
	ReactionEffect.ReactionModifier = default.GUARD_OVERWATCH_AIM;
	ReactionEffect.bAllowCrit = true;
	ReactionEffect.BuildPersistentEffect(1, true, false);
	ReactionEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	Template.AddTargetEffect(ReactionEffect);

	return Template;
}

// Tactician: -10 aim. The bonus damage on missed shots (scaling with weapon tier) is handled
// by X2EventListener_UniqueTraits.OnAbilityActivated_Tactician, since it needs to react to
// arbitrary attack abilities missing rather than something attachable to this passive itself.
static function X2AbilityTemplate Tactician()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;

	Template = PurePassive('UT_Tactician', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_Tactician';
	StatEffect.BuildPersistentEffect(1, true, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage,,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_Offense, -default.TACTICIAN_AIM);
	Template.AddTargetEffect(StatEffect);

	Template.SetUIStatMarkup(class'XLocalizedData'.default.AimLabel, eStat_Offense, -default.TACTICIAN_AIM);

	return Template;
}
