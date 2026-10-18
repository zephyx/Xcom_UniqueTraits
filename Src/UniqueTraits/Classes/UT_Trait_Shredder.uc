//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Shredder.uc
//  PURPOSE: Shredder: when the holder's PRIMARY weapon shreds the armor of an enemy, that enemy gets an Acid damage over time (the vanilla acid,
//           the damage per tick of the reference acid grenade's own acid, see OnPostTemplatesCreated; for X2StatusEffects.ACID_BURNING_TURNS turns). Every acid tick the holder
//           inflicts (not just the ones applied after a shred) deals SHREDDER_ACID_TICK_BONUS more damage. Malus: his primary weapon deals
//           SHREDDER_UNARMORED_DAMAGE_MALUS_PCT % less damage (never below 1) to targets with no armor left.
//           - The modifiers are X2Effect_UT_Shredder (the passive's effect).
//           - The acid: 'AbilityActivated' (ELD_OnStateSubmitted). A target "was shredded" when a damage result of THIS activation (same context)
//             has Shred > 0, i.e. armor was really removed (XComGameState_Unit.TakeDamage fills DamageResult.Shred with the shred that landed).
//             The acid is the effect of the hidden ability UT_ShredderAcid, applied in a change container of its own (like Chemist's disease), bound
//             to the TARGET's player (ApplyAbilityEffect's last argument) so that it ticks at the start of the enemy's turn, like an acid grenade's.
//---------------------------------------------------------------------------------------
class UT_Trait_Shredder extends UT_TraitBase config(UniqueTraits);

var config int SHREDDER_ACID_DAMAGE, SHREDDER_ACID_SPREAD, SHREDDER_ACID_TICK_BONUS, SHREDDER_UNARMORED_DAMAGE_MALUS_PCT;
var config array<name> SHREDDER_ACID_DAMAGE_TYPES;
var config name SHREDDER_ACID_REFERENCE_GRENADE;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Shredder());
	Templates.AddItem(ShredderAcid());

	return Templates;
}

// Shredder: the acid bonus and the malus against unarmored targets; the acid itself is OnAbilityActivated_Shredder.
static function X2AbilityTemplate Shredder()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_Shredder ShredderEffect;
	local name DamageType;

	Template = PurePassive('UT_Shredder', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	ShredderEffect = new class'X2Effect_UT_Shredder';
	ShredderEffect.AcidTickBonus = default.SHREDDER_ACID_TICK_BONUS;
	ShredderEffect.UnarmoredMalusPct = default.SHREDDER_UNARMORED_DAMAGE_MALUS_PCT;
	foreach default.SHREDDER_ACID_DAMAGE_TYPES(DamageType)
		ShredderEffect.AcidDamageTypes.AddItem(DamageType);
	ShredderEffect.BuildPersistentEffect(1, true, false);
	ShredderEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(ShredderEffect);

	return Template;
}

// Holder of the acid applied by OnAbilityActivated_Shredder (hidden, never granted): the vanilla acid, so immunities and the acid visualization
// are the game's own.
static function X2AbilityTemplate ShredderAcid()
{
	local X2AbilityTemplate Template;

	Template = HiddenEffectHolder('UT_ShredderAcid');
	Template.Hostility = eHostility_Offensive;
	Template.AddTargetEffect(class'X2StatusEffects'.static.CreateAcidBurningStatusEffect(default.SHREDDER_ACID_DAMAGE, default.SHREDDER_ACID_SPREAD));

	return Template;
}

// UT_TraitBase.OnPostTemplatesCreated (called for every trait of the pool by X2DownloadableContentInfo_UniqueTraits): the acid of the shred deals what the acid effect of the reference grenade
// (SHREDDER_ACID_REFERENCE_GRENADE, the plain acid grenade) deals per tick, damage and spread, whatever the game or a mod made it: it is read here,
// once every template exists (this mod runs LAST, see Config/XComGame.ini). CreateAcidBurningStatusEffect takes the damage as an argument, there is no
// global "acid damage". SHREDDER_ACID_DAMAGE / SHREDDER_ACID_SPREAD stay in use as the fallback when the grenade or its acid cannot be found.
static function OnPostTemplatesCreated()
{
	local X2AbilityTemplate AcidTemplate;
	local X2GrenadeTemplate Grenade;
	local X2Effect_Burning ShredderAcid, ReferenceAcid;
	local X2Effect Effect;

	AcidTemplate = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager().FindAbilityTemplate('UT_ShredderAcid');
	if (AcidTemplate == none || AcidTemplate.AbilityTargetEffects.Length == 0)
		return;
	ShredderAcid = X2Effect_Burning(AcidTemplate.AbilityTargetEffects[0]);
	if (ShredderAcid == none || ShredderAcid.GetBurnDamage() == none)
		return;

	Grenade = X2GrenadeTemplate(class'X2ItemTemplateManager'.static.GetItemTemplateManager().FindItemTemplate(default.SHREDDER_ACID_REFERENCE_GRENADE));
	if (Grenade == none)
	{
		`log("UniqueTraits [WARN] : Shredder -- reference grenade '" $ default.SHREDDER_ACID_REFERENCE_GRENADE $ "' not found, the acid keeps SHREDDER_ACID_DAMAGE / SHREDDER_ACID_SPREAD",, 'UniqueTraits');
		return;
	}

	foreach Grenade.ThrownGrenadeEffects(Effect)
	{
		ReferenceAcid = X2Effect_Burning(Effect);
		if (ReferenceAcid != none && ReferenceAcid.EffectName == class'X2StatusEffects'.default.AcidBurningName && ReferenceAcid.GetBurnDamage() != none)
		{
			ShredderAcid.GetBurnDamage().EffectDamageValue.Damage = ReferenceAcid.GetBurnDamage().EffectDamageValue.Damage;
			ShredderAcid.GetBurnDamage().EffectDamageValue.Spread = ReferenceAcid.GetBurnDamage().EffectDamageValue.Spread;
			`log("UniqueTraits : Shredder -- acid damage taken from" @ default.SHREDDER_ACID_REFERENCE_GRENADE $ ":" @ ShredderAcid.GetBurnDamage().EffectDamageValue.Damage @ "+/-" @ ShredderAcid.GetBurnDamage().EffectDamageValue.Spread,, 'UniqueTraits');
			return;
		}
	}

	`log("UniqueTraits [WARN] : Shredder -- no acid effect on the reference grenade '" $ default.SHREDDER_ACID_REFERENCE_GRENADE $ "', the acid keeps SHREDDER_ACID_DAMAGE / SHREDDER_ACID_SPREAD",, 'UniqueTraits');
}

// True when a damage result of this very activation removed armor from the target.
static final function bool WasShreddedBy(XComGameState_Unit Target, XComGameStateContext Context)
{
	local int i;

	for (i = 0; i < Target.DamageResults.Length; ++i)
	{
		if (Target.DamageResults[i].Context == Context && Target.DamageResults[i].Shred > 0)
			return true;
	}

	return false;
}

static function EventListenerReturn OnAbilityActivated_Shredder(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateContext_Ability AbilityContext;
	local XComGameState_Unit SourceUnit, TargetUnit, MutableTarget;
	local array<int> TargetIDs;
	local XComGameState NewGameState;
	local int i, Applied;

	if (!ParseAbilityActivation(GameState, EventSource, 'UT_Shredder', AbilityContext, SourceUnit))
		return ELR_NoInterrupt;

	if (!class'UT_EffectHelpers'.static.IsPrimaryWeaponAbility(XComGameState_Ability(EventData)))
		return ELR_NoInterrupt;

	foreach GameState.IterateByClassType(class'XComGameState_Unit', TargetUnit)
	{
		if (TargetUnit.ObjectID != SourceUnit.ObjectID && TargetUnit.IsAlive() && SourceUnit.IsEnemyUnit(TargetUnit) && WasShreddedBy(TargetUnit, GameState.GetContext()))
			TargetIDs.AddItem(TargetUnit.ObjectID);
	}

	if (TargetIDs.Length == 0)
		return ELR_NoInterrupt;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Shredder acid");
	for (i = 0; i < TargetIDs.Length; ++i)
	{
		MutableTarget = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', TargetIDs[i]));
		if (class'UT_EffectHelpers'.static.ApplyAbilityEffect('UT_ShredderAcid', 0, SourceUnit, MutableTarget, NewGameState, AbilityContext, true) == 'AA_Success')
			++Applied;
	}

	if (Applied == 0)
	{
		`XCOMHISTORY.CleanupPendingGameState(NewGameState);
		return ELR_NoInterrupt;
	}

	XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = BuildVisualization_ShredderAcid;
	`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}

static function BuildVisualization_ShredderAcid(XComGameState VisualizeGameState)
{
	class'UT_EffectHelpers'.static.AddEffectVisualization(VisualizeGameState, 'UT_ShredderAcid', 0);
}
