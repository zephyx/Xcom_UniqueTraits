//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Reliable.uc
//  PURPOSE: Reliable: the soldier never makes a critical hit => the crit chance of each of his shots is converted into aim
//           (+ceil(crit / RELIABLE_CRIT_TO_AIM_DIVISOR), 2) and lowers the target's dodge by RELIABLE_DODGE_REDUCTION_PCT % (100) of that crit chance.
//           The mechanism (a delegate in CHL's OverrideFinalHitChanceFns, fed by the holder's own effect) is explained in X2Effect_UT_Reliable.uc;
//           this class holds the ability, the config, the shot-breakdown label and the registration of the delegate on every StandardAim calc.
//---------------------------------------------------------------------------------------
class UT_Trait_Reliable extends UT_TraitBase config(UniqueTraits);

var config int RELIABLE_CRIT_TO_AIM_DIVISOR, RELIABLE_DODGE_REDUCTION_PCT;
var localized string ReliableReason;

// Priority of the passive's UnitPostBeginPlay trigger (the ordinary passives use the default 50; a LARGER number runs FIRST, as everywhere in the event manager).
// See Reliable() for why it is lower.
const RELIABLE_TRIGGER_PRIORITY = 45;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Reliable());

	return Templates;
}

// Reliable: a bare passive carrying the effect that marks the holder's shots (X2Effect_UT_Reliable).
// ORDER: the effect's ChangeHitResultForAttacker (a crit becomes a plain hit) is the last line of defence against crits, but the game
// calls that hook on the holder's effects one after the other, each one seeing the result the previous one left, so a hook of another effect that raises a
// hit to a crit AFTER ours would undo it (the Synaptic Booster gene mod does that on reaction shots: hit -> crit). The order of the holder's effects
// (AffectedByEffects) is the order in which they were applied (XComGameState_Unit.AddAffectingEffect), and a passive is applied by its UnitPostBeginPlay trigger, whose
// Priority is the priority of its OnUnitBeginPlay listener (XComGameState_Ability.uc:1444). Reliable's trigger therefore has a LOWER priority than the default 50:
// its effect is applied after the ordinary passives and its safety net comes last. A passive with a priority below 45 would still come after it.
static function X2AbilityTemplate Reliable()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_Reliable ReliableEffect;
	local X2AbilityTrigger_UnitPostBeginPlay LateTrigger;

	Template = PurePassive('UT_Reliable', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	LateTrigger = new class'X2AbilityTrigger_UnitPostBeginPlay';
	LateTrigger.Priority = RELIABLE_TRIGGER_PRIORITY;
	Template.AbilityTriggers.Length = 0;
	Template.AbilityTriggers.AddItem(LateTrigger);

	ReliableEffect = new class'X2Effect_UT_Reliable';
	ReliableEffect.EffectName = 'UT_Reliable_Shots';
	ReliableEffect.BuildPersistentEffect(1, true, false);
	ReliableEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(ReliableEffect);

	return Template;
}

// Puts the delegate in FRONT of OverrideFinalHitChanceFns on every StandardAim calc (LWOTC's own delegate is added by its OnPostTemplatesCreated and
// must come after ours; this mod runs RUN_LAST and inserts at index 0 anyway). A calc object shared by several templates is handled once.
static function OnPostTemplatesCreated()
{
	local X2AbilityTemplateManager AbilityManager;
	local X2DataTemplate DataTemplate;
	local X2AbilityTemplate Template;
	local array<X2AbilityToHitCalc> Done;
	local int Patched;

	AbilityManager = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();
	foreach AbilityManager.IterateTemplates(DataTemplate, none)
	{
		Template = X2AbilityTemplate(DataTemplate);
		if (Template == none || Template.AbilityToHitCalc == none)
			continue;

		if (!ClassIsChildOf(Template.AbilityToHitCalc.Class, class'X2AbilityToHitCalc_StandardAim'))
			continue;

		if (Done.Find(Template.AbilityToHitCalc) != INDEX_NONE)
			continue;

		Done.AddItem(Template.AbilityToHitCalc);
		Template.AbilityToHitCalc.OverrideFinalHitChanceFns.InsertItem(0, class'X2Effect_UT_Reliable'.static.OverrideFinalHitChance_Reliable);
		++Patched;
	}

	`log("UniqueTraits : Reliable --" @ Patched @ "to-hit calc(s) given the final hit chance delegate",, 'UniqueTraits');
}
