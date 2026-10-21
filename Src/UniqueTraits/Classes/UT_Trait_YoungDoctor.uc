//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_YoungDoctor.uc
//  PURPOSE: Young doctor: a free medikit, but the HP he heals are reduced by YOUNGDOCTOR_HEAL_REDUCTION_PCT %; every soldier he heals
//           (himself included) for the first time in a combat earns him the experience of a kill (the kill XP, the bonus kill XP of the
//           resistance cards and the Wet Work count of the Guerrilla Tactics School, as XComGameState_Unit.OnUnitDied gives them),
//           limited to 1/2/3 times per combat by rank. Stabilizing a soldier is worth double.
//           One handler ('AbilityActivated', ELD_Immediate: it runs inside the ability's own pending game state, once the effects are
//           applied, so the reduced heal is what the visualization shows) for the abilities of YOUNGDOCTOR_HEAL_ABILITIES and
//           YOUNGDOCTOR_STABILIZE_ABILITIES.
//           UnitValues on the holder (eCleanup_BeginTactical): UT_YoungDoctor_XpGrants (XP rewards used) and
//           UT_YoungDoctor_Healed_<unit id> (soldiers already treated).
//---------------------------------------------------------------------------------------
class UT_Trait_YoungDoctor extends UT_TraitBase config(UniqueTraits);

var config name YOUNGDOCTOR_MEDIKIT_ITEM_NAME;
var config int YOUNGDOCTOR_HEAL_REDUCTION_PCT;
var config float YOUNGDOCTOR_XP_PER_TREATMENT;
var config float YOUNGDOCTOR_STABILIZE_XP_MULT;
var config int YOUNGDOCTOR_RANK_FOR_TWO_XP, YOUNGDOCTOR_RANK_FOR_THREE_XP;
var config array<name> YOUNGDOCTOR_HEAL_ABILITIES;
var config array<name> YOUNGDOCTOR_STABILIZE_ABILITIES;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(YoungDoctor());

	return Templates;
}

// Event registrations (X2EventListener_UniqueTraits.CreateTacticalListeners calls this for every trait of the pool that is not disabled).
static function OnCreateTacticalListeners(CHEventListenerTemplate Template)
{
	// Young doctor: reduces the heals of its holder and rewards the first treatment of each soldier. ELD_Immediate: it works on the ability's own
	// pending state, so the visualization shows the reduced heal.
	Template.AddCHEvent('AbilityActivated', OnAbilityActivated_YoungDoctor, ELD_Immediate, 50);
}

// Young doctor: a free medikit (utility slot, stacked on a medikit the holder already carries, like Smoker's grenades). The rest is
// OnAbilityActivated_YoungDoctor.
static function X2AbilityTemplate YoungDoctor()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_TemporaryItem MedikitEffect;

	Template = PurePassive('UT_YoungDoctor', "img:///UniqueTraits_Icons.UT_YoungDoctor", true);

	MedikitEffect = new class'X2Effect_UT_TemporaryItem';
	MedikitEffect.EffectName = 'UT_YoungDoctor_FreeMedikit';
	MedikitEffect.ItemName = default.YOUNGDOCTOR_MEDIKIT_ITEM_NAME;
	MedikitEffect.ItemInventorySlot = eInvSlot_Utility;
	MedikitEffect.Quantity = 1;
	MedikitEffect.bStackOnExisting = true;
	MedikitEffect.BuildPersistentEffect(1, true, false);
	MedikitEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(MedikitEffect);

	return Template;
}

// Number of XP rewards per combat for a rank.
static function int GetMaxXpGrants(XComGameState_Unit Unit)
{
	if (Unit.GetRank() >= default.YOUNGDOCTOR_RANK_FOR_THREE_XP)
		return 3;
	if (Unit.GetRank() >= default.YOUNGDOCTOR_RANK_FOR_TWO_XP)
		return 2;

	return 1;
}

// The experience of Multiplier kills: what XComGameState_Unit.OnUnitDied adds for a kill (KillCount, BonusKills, WetWorkKills). Unit must be
// a pending state object.
static function GrantKillXp(XComGameState_Unit Unit, float Multiplier)
{
	local XComGameState_HeadquartersXCom XComHQ;

	Unit.KillCount += default.YOUNGDOCTOR_XP_PER_TREATMENT * Multiplier;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom', true));
	if (XComHQ != none)
	{
		if (XComHQ.SoldierUnlockTemplates.Find('WetWorkUnlock') != INDEX_NONE)
			Unit.WetWorkKills += int(Multiplier);

		Unit.BonusKills += XComHQ.BonusKillXP * Multiplier;
	}
}

// The NOMINAL heal of an activation: what the ability's X2Effect_ApplyMedikitHeal effects heal before the target's max HP caps it (PerUseHP, the research that
// raises it, a gremlin's HealingBonus: the same rules as X2Effect_ApplyMedikitHeal.OnEffectAdded, which keeps the amount to itself and only calls ModifyCurrentStat,
// so it cannot be read back afterwards). 0 for an ability with no such effect (A Harder War's Resuscitate...).
static final function int GetNominalMedikitHeal(XComGameState_Ability AbilityState)
{
	local X2AbilityTemplate Template;
	local X2Effect Effect;
	local X2Effect_ApplyMedikitHeal MedikitHeal;
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_Item SourceWeapon;
	local X2GremlinTemplate GremlinTemplate;
	local int Amount, Total;

	Template = AbilityState.GetMyTemplate();
	if (Template == none)
		return 0;

	foreach Template.AbilityTargetEffects(Effect)
	{
		MedikitHeal = X2Effect_ApplyMedikitHeal(Effect);
		if (MedikitHeal == none)
			continue;

		Amount = MedikitHeal.PerUseHP;

		if (MedikitHeal.IncreasedHealProject != '')
		{
			XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom', true));
			if (XComHQ != none && XComHQ.IsTechResearched(MedikitHeal.IncreasedHealProject))
				Amount = MedikitHeal.IncreasedPerUseHP;
		}

		SourceWeapon = AbilityState.GetSourceWeapon();
		if (SourceWeapon != none)
		{
			GremlinTemplate = X2GremlinTemplate(SourceWeapon.GetMyTemplate());
			if (GremlinTemplate != none)
				Amount += GremlinTemplate.HealingBonus;
		}

		Total += Amount;
	}

	return Total;
}

// 'AbilityActivated' (ELD_Immediate, so GameState is still the ability's pending state, effects applied). Fires more than once per ability:
// the interrupt step is skipped, and the work below is idempotent (the HP comparison is against the committed history, the XP is guarded by the
// "already treated" marks).
static function EventListenerReturn OnAbilityActivated_YoungDoctor(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateContext_Ability AbilityContext;
	local XComGameState_Ability AbilityState;
	local XComGameState_Unit SourceUnit, MutableSource, TargetUnit, PreviousTarget;
	local name AbilityName, HealedName;
	local bool bHeal, bStabilize;
	local UnitValue Value;
	local int TargetID, Healed, Nominal, Cut, WantedHP, Granted;

	if (!ParseAbilityActivation(GameState, EventSource, 'UT_YoungDoctor', AbilityContext, SourceUnit))
		return ELR_NoInterrupt;

	AbilityState = XComGameState_Ability(EventData);
	if (AbilityState == none)
		return ELR_NoInterrupt;

	AbilityName = AbilityState.GetMyTemplateName();
	bHeal = default.YOUNGDOCTOR_HEAL_ABILITIES.Find(AbilityName) != INDEX_NONE;
	bStabilize = default.YOUNGDOCTOR_STABILIZE_ABILITIES.Find(AbilityName) != INDEX_NONE;
	if (!bHeal && !bStabilize)
		return ELR_NoInterrupt;

	TargetID = AbilityContext.InputContext.PrimaryTarget.ObjectID;
	TargetUnit = XComGameState_Unit(GameState.GetGameStateForObjectID(TargetID));
	if (TargetUnit == none)
		return ELR_NoInterrupt;

	// The heal is reduced, and the reduction is taken on the NOMINAL heal of the ability, not on the HP that really went in: a medikit worth 4 HP cut by 25 %
	// heals 3, so a soldier who misses only 3 HP gets his 3 HP (the cap at his max HP is applied AFTER the reduction, as it would be for any other heal).
	// The nominal heal is read from the ability (GetNominalMedikitHeal); an ability without such an effect
	// (a stabilization that also heals, like Resuscitate) falls back on the HP really healed (pending HP against the last committed ones).
	PreviousTarget = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(TargetID));
	if (PreviousTarget != none)
	{
		Healed = int(TargetUnit.GetCurrentStat(eStat_HP) - PreviousTarget.GetCurrentStat(eStat_HP));
		if (Healed > 0)
		{
			Nominal = Max(Healed, GetNominalMedikitHeal(AbilityState));
			Cut = Min(Round(Nominal * default.YOUNGDOCTOR_HEAL_REDUCTION_PCT / 100.0), Nominal - 1);
			if (Cut > 0)
			{
				WantedHP = Min(int(TargetUnit.GetMaxStat(eStat_HP)), int(PreviousTarget.GetCurrentStat(eStat_HP)) + Nominal - Cut);
				if (WantedHP < int(TargetUnit.GetCurrentStat(eStat_HP)))
					TargetUnit.ModifyCurrentStat(eStat_HP, WantedHP - TargetUnit.GetCurrentStat(eStat_HP));
			}
		}
	}

	// The experience: a soldier not treated yet in this combat, within the limit of the rank.
	if (!TargetUnit.IsSoldier() || !SourceUnit.CanEarnXp())
		return ELR_NoInterrupt;

	HealedName = name("UT_YoungDoctor_Healed_" $ TargetID);
	if (SourceUnit.GetUnitValue(HealedName, Value))
		return ELR_NoInterrupt;

	if (SourceUnit.GetUnitValue('UT_YoungDoctor_XpGrants', Value))
		Granted = int(Value.fValue);
	if (Granted >= GetMaxXpGrants(SourceUnit))
		return ELR_NoInterrupt;

	MutableSource = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', SourceUnit.ObjectID));
	MutableSource.SetUnitFloatValue(HealedName, 1, eCleanup_BeginTactical);
	MutableSource.SetUnitFloatValue('UT_YoungDoctor_XpGrants', Granted + 1, eCleanup_BeginTactical);
	GrantKillXp(MutableSource, bStabilize ? default.YOUNGDOCTOR_STABILIZE_XP_MULT : 1.0);

	`log("UniqueTraits : Young doctor --" @ SourceUnit.GetFullName() @ "treated unit" @ TargetID @ "with" @ AbilityName $ ", XP reward" @ (Granted + 1) @ "of" @ GetMaxXpGrants(SourceUnit),, 'UniqueTraits');

	return ELR_NoInterrupt;
}
