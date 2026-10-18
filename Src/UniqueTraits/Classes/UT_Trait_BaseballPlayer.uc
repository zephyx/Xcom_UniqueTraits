//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_BaseballPlayer.uc
//  PURPOSE: Baseball player: own explosives deal less damage (X2Effect_UT_WeakExplosives); also grants UT_BaseballSalvo (ini), an own copy of Salvo
//           (heavy weapons and grenades don't end the turn) that adds Bombardier's range bonus on grenades.
//---------------------------------------------------------------------------------------
class UT_Trait_BaseballPlayer extends UT_TraitBase config(UniqueTraits);

var config int BASEBALL_EXPLOSIVE_DAMAGE_REDUCTION;
var config int BASEBALL_BOMBARD_RANGE;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(BaseballPlayer());
	Templates.AddItem(BaseballSalvo());

	return Templates;
}

// Baseball player: own explosives deal 2 less damage. The Salvo-like ability is granted separately via the ini (UT_BaseballSalvo).
static function X2AbilityTemplate BaseballPlayer()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_WeakExplosives WeakExplosivesEffect;

	Template = PurePassive('UT_BaseballPlayer', "img:///UniqueTraits_Icons.UT_BaseballPlayer", true);

	WeakExplosivesEffect = new class'X2Effect_UT_WeakExplosives';
	WeakExplosivesEffect.EffectName = 'UT_BaseballPlayer_WeakExplosives';
	WeakExplosivesEffect.DamageReduction = default.BASEBALL_EXPLOSIVE_DAMAGE_REDUCTION;
	WeakExplosivesEffect.BuildPersistentEffect(1, true, false);
	WeakExplosivesEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(WeakExplosivesEffect);

	return Template;
}

// Own copy of Salvo: a pure passive with no effect of its own. The game tests Salvo BY NAME (X2AbilityCost_ActionPoints.DoNotConsumeAllSoldierAbilities, read through
// HasSoldierAbility), so OnPostTemplatesCreated adds this name next to 'Salvo' in every cost that lists it. Granting the real Salvo through AWCAbilities blocked
// the class column that holds it; this one cannot clash with any class tree. The Bombardier range bonus is the 'OnGetItemRange' listener below.
static function X2AbilityTemplate BaseballSalvo()
{
	return PurePassive('UT_BaseballSalvo', "img:///UILibrary_PerkIcons.UIPerk_salvo", true);
}

// UT_TraitBase.OnPostTemplatesCreated (called for every trait of the pool by X2DownloadableContentInfo_UniqueTraits): wherever 'Salvo' keeps an action cost from consuming every point (grenade throws and launches,
// heavy weapons, other mods' grenade abilities: any X2AbilityCost_ActionPoints that lists it), UT_BaseballSalvo does the same. Runs last (RUN_LAST), so the costs
// other mods add to their templates are seen too.
static function OnPostTemplatesCreated()
{
	local X2AbilityTemplateManager AbilityManager;
	local X2DataTemplate DataTemplate;
	local X2AbilityTemplate Template;
	local X2AbilityCost Cost;
	local X2AbilityCost_ActionPoints ActionPointCost;
	local int Patched;

	AbilityManager = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();
	foreach AbilityManager.IterateTemplates(DataTemplate, none)
	{
		Template = X2AbilityTemplate(DataTemplate);
		if (Template == none)
			continue;

		foreach Template.AbilityCosts(Cost)
		{
			ActionPointCost = X2AbilityCost_ActionPoints(Cost);
			if (ActionPointCost == none)
				continue;

			if (ActionPointCost.DoNotConsumeAllSoldierAbilities.Find('Salvo') != INDEX_NONE
				&& ActionPointCost.DoNotConsumeAllSoldierAbilities.Find('UT_BaseballSalvo') == INDEX_NONE)
			{
				ActionPointCost.DoNotConsumeAllSoldierAbilities.AddItem('UT_BaseballSalvo');
				++Patched;
				`log("UniqueTraits : Baseball player -- Salvo-like cost on:" @ Template.DataName,, 'UniqueTraits');
			}
		}
	}

	`log("UniqueTraits : Baseball player --" @ Patched @ "action cost(s) patched",, 'UniqueTraits');
}

// Bombardier's range bonus (LWOTC's Bombard: grenades, grenade launchers and the Battle Scanner), copied here because LWOTC's class cannot be referenced.
static function EventListenerReturn OnGetItemRange_BaseballPlayer(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;
	local X2WeaponTemplate ItemTemplate;
	local XComGameState_Unit OwnerUnit;

	if (!ParseItemRangeEvent(EventData, EventSource, Tuple, ItemTemplate, OwnerUnit))
		return ELR_NoInterrupt;

	if ((X2GrenadeTemplate(ItemTemplate) != none || X2GrenadeLauncherTemplate(ItemTemplate) != none || ItemTemplate.DataName == 'Battlescanner')
		&& class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(OwnerUnit, 'UT_BaseballPlayer'))
	{
		Tuple.Data[1].i += default.BASEBALL_BOMBARD_RANGE;
	}

	return ELR_NoInterrupt;
}
