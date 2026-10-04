//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Tactician.uc
//  PURPOSE: Tactician: -10 aim; the bonus damage on missed shots is UT_Trait_Tactician.OnAbilityActivated_Tactician.
//---------------------------------------------------------------------------------------
class UT_Trait_Tactician extends UT_TraitBase config(UniqueTraits);

// Indexed by X2WeaponTemplate.Tier, clamped to the last entry.
var config array<int> TACTICIAN_MISS_DAMAGE_BY_TIER;

var config int TACTICIAN_AIM;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Tactician());

	return Templates;
}

// Tactician: -10 aim. The bonus damage on missed shots (scaling with weapon tier) is handled
// by UT_Trait_Tactician.OnAbilityActivated_Tactician, since it needs to react to
// arbitrary attack abilities missing rather than something attachable to this passive itself.
static function X2AbilityTemplate Tactician()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;

	Template = PurePassive('UT_Tactician', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_Tactician';
	StatEffect.BuildPersistentEffect(1, true, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_Offense, -default.TACTICIAN_AIM);
	Template.AddTargetEffect(StatEffect);

	Template.SetUIStatMarkup(class'XLocalizedData'.default.AimLabel, eStat_Offense, -default.TACTICIAN_AIM);

	return Template;
}

// Tactician: missed shots still land a little damage, scaling with the weapon's tier. There's
// no clean way to attach a bonus "damage on miss" effect (like the base game's own
// WeaponUpgradeMissDamage) to an arbitrary attack ability from outside without either mutating
// the shared/singleton X2AbilityTemplate for everyone using that ability (dangerous) or deep-
// copying every attack ability template per unit (heavy). Instead, this reacts to the fully
// resolved miss after the fact and deals the bonus damage directly via TakeEffectDamage.
static function EventListenerReturn OnAbilityActivated_Tactician(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit SourceUnit, TargetUnit;
	local XComGameStateContext_Ability AbilityContext;
	local XComGameState_Item SourceWeapon;
	local X2WeaponTemplate WeaponTemplate;
	local EffectAppliedData EmptyEffectData;
	local XComGameState NewGameState;
	local int TierIndex, DamageAmount;

	// 'AbilityActivated' fires once for the interrupt step and again on resume/final for the same
	// shot (XComGameStateContext_Ability.uc:191/:414); react only once or the bonus damage doubles.
	if (GameState.GetContext().InterruptionStatus == eInterruptionStatus_Interrupt)
		return ELR_NoInterrupt;

	SourceUnit = XComGameState_Unit(EventSource);
	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SourceUnit, 'UT_Tactician'))
		return ELR_NoInterrupt;

	AbilityContext = XComGameStateContext_Ability(GameState.GetContext());
	if (AbilityContext == none || AbilityContext.ResultContext.HitResult != eHit_Miss)
		return ELR_NoInterrupt;

	if (AbilityContext.InputContext.PrimaryTarget.ObjectID == 0)
		return ELR_NoInterrupt;

	TargetUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(AbilityContext.InputContext.PrimaryTarget.ObjectID));
	if (TargetUnit == none || TargetUnit.IsDead())
		return ELR_NoInterrupt;

	SourceWeapon = XComGameState_Item(`XCOMHISTORY.GetGameStateForObjectID(AbilityContext.InputContext.ItemObject.ObjectID));
	if (SourceWeapon == none)
		return ELR_NoInterrupt;

	WeaponTemplate = X2WeaponTemplate(SourceWeapon.GetMyTemplate());
	if (WeaponTemplate == none || default.TACTICIAN_MISS_DAMAGE_BY_TIER.Length == 0)
		return ELR_NoInterrupt;

	TierIndex = Clamp(WeaponTemplate.Tier, 0, default.TACTICIAN_MISS_DAMAGE_BY_TIER.Length - 1);
	DamageAmount = default.TACTICIAN_MISS_DAMAGE_BY_TIER[TierIndex];
	if (DamageAmount <= 0)
		return ELR_NoInterrupt;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Tactician miss damage");
	TargetUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', TargetUnit.ObjectID));
	EmptyEffectData.SourceStateObjectRef = SourceUnit.GetReference();
	EmptyEffectData.TargetStateObjectRef = TargetUnit.GetReference();
	TargetUnit.TakeEffectDamage(none, DamageAmount, 0, 0, EmptyEffectData, NewGameState);
	`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}
