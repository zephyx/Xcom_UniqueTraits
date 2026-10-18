//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_SecurityHacker.uc
//  PURPOSE: Security hacker: when the HOLDER hacks a security tower, the tower gives the same rewards as the computers (the mission's strategic
//           deck) and its lock strength (the hack defense) is multiplied by SECURITYHACKER_DEFENSE_MULT. The price: a FAILED hack deals
//           SECURITYHACKER_FAILURE_DAMAGE_PCT % of the hacker's MAX HP (rounded up) of damage to the hacker (a real wound dealt by a hidden ability, going through armor and the ablative
//           protection, that LWOTC's Failsafe cannot cancel since it is not a hack reward), on top of the tower's normal failure penalty.
//           And a SUCCESSFUL hack disables ALL the security towers of the mission, not only the one that was hacked.
//           Another soldier hacking the same tower gets the normal tower.
//           Like in the base game, after a carried-out hack (success or failure) the towers can no longer be hacked: the vanilla finalize sets
//           BattleData.bTacticalHackCompleted when the hacked object has the tactical flag, and an object with that flag can no longer be hacked
//           once it is set (XComGameState_InteractiveObject.CanInteractHack). The tower's tactical flag is off during the holder's attempt (it
//           offers the strategic deck), so the finalize does not set it: the handler sets it itself when the tower had the flag.
//           A hack is two abilities: the one that opens the hacking screen (its template has a FinalizeAbilityName) and the finalize / cancel
//           ability. So the tower is changed for the duration of the holder's attempt only (one handler, 'AbilityActivated', ELD_Immediate, inside
//           the pending state of the ability):
//           - Start (the ability that opens the screen, before the screen reads the lock strength and the reward list): the tower offers the
//             COMPUTERS' rewards (the strategic deck, see below) and the lock strength becomes LockStrength * mult (SetLockStrengthExactly).
//             The original values (the lock strength ALREADY includes the sitrep modifiers) are kept in UnitValues of the hacker (UT_SecHacker_*).
//           - End (the finalize / cancel abilities, after the rewards were awarded in that very state): the original values are restored
//             EXACTLY (the sitrep modifiers are not applied a second time). On a FINALIZE (not a cancel): if the hack succeeded, every other
//             security tower is marked hacked and gets its 'ObjectHacked' event (what the mission's Kismet reacts to: the same as hacking it);
//             if it failed, the hacker is flagged and takes the damage of a real ability right after (OnAbilityActivated_SecurityHackerBacklash).
//           Which objects are "security towers": hackable interactive objects (MustBeHacked) whose archetype path (the state's ArchetypePath, or
//           the actor's ObjectArchetype) contains one of SECURITYHACKER_TOWER_KEYWORDS (seen in the log: AdventTower.Archetypes.
//           ARC_AdventTower_Hackable). Every hack the holder starts is logged with its archetype (matched or not).
//---------------------------------------------------------------------------------------
class UT_Trait_SecurityHacker extends UT_TraitBase config(UniqueTraits);

var config float SECURITYHACKER_DEFENSE_MULT;   // a decimal number (1.0 to 3.0 in the Mod Config Menu)
var config int SECURITYHACKER_FAILURE_DAMAGE_PCT;
var config array<string> SECURITYHACKER_TOWER_KEYWORDS;
var config array<name> SECURITYHACKER_END_ABILITIES;
var config array<name> SECURITYHACKER_FINALIZE_ABILITIES;
var localized string SECURITYHACKER_FLYOVER;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;
	local X2AbilityTemplate Passive;

	Passive = PurePassive('UT_SecurityHacker', "img:///UniqueTraits_Icons.UT_SecurityHacker", true);
	Passive.AdditionalAbilities.AddItem('UT_SecurityHackerBacklash');
	Templates.AddItem(Passive);
	Templates.AddItem(SecurityHackerBacklash());

	return Templates;
}

// The damage of a failed hack: a hidden ability of the holder (granted with the passive through AdditionalAbilities), activated for real by
// OnAbilityActivated_SecurityHackerBacklash right after the finalize ability. Its effect is an X2Effect_ApplyWeaponDamage with a flat damage like
// the one SKULLMINEAbility applies on a miss but sized as a percentage of the max HP (X2Effect_UT_PercentHPDamage), and it runs as an ordinary ability (its own game state and context, normal visualization), so it is a
// genuine wound that goes through the same logic as any other: hit animation and damage flyover, 'UnitTakeEffectDamage' (Psychic Bond), LowestHP
// and the end-of-mission wound, the death if it kills. Armor and the ablative protection (eStat_ShieldHP) are bypassed (bIgnoreArmor,
// bBypassShields); it is not a hack reward, so Failsafe cannot cancel it.
static function X2AbilityTemplate SecurityHackerBacklash()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_PercentHPDamage DamageEffect;

	Template = HiddenEffectHolder('UT_SecurityHackerBacklash');
	Template.AbilityTargetStyle = default.SelfTarget;
	Template.Hostility = eHostility_Neutral;
	Template.bSkipFireAction = true;
	Template.BuildVisualizationFn = BuildVisualization_HackBacklash;

	DamageEffect = new class'X2Effect_UT_PercentHPDamage';
	DamageEffect.bIgnoreBaseDamage = true;
	DamageEffect.bIgnoreArmor = true;
	DamageEffect.bBypassShields = true;
	DamageEffect.PercentOfMaxHP = default.SECURITYHACKER_FAILURE_DAMAGE_PCT;
	Template.AddTargetEffect(DamageEffect);

	return Template;
}

static final function string GetArchetypeText(XComGameState_InteractiveObject Obj)
{
	local XComInteractiveLevelActor VisActor;
	local string Text;

	Text = Obj.ArchetypePath;
	VisActor = XComInteractiveLevelActor(Obj.GetVisualizer());
	if (VisActor != none && VisActor.ObjectArchetype != none)
		Text = Text @ PathName(VisActor.ObjectArchetype);

	return Text;
}

static final function bool IsTower(XComGameState_InteractiveObject Obj)
{
	local string Text, Keyword;

	if (Obj == none || !Obj.MustBeHacked())
		return false;

	Text = GetArchetypeText(Obj);
	foreach default.SECURITYHACKER_TOWER_KEYWORDS(Keyword)
	{
		if (InStr(Text, Keyword,, true) != INDEX_NONE)
			return true;
	}

	return false;
}

static final function string NamesToString(array<name> Names)
{
	local name N;
	local string Text;

	foreach Names(N)
		Text $= (Text == "" ? "" : ",") $ string(N);

	return Text;
}

// One line about a hackable object: archetype, the two "offers the mission's deck" flags, lock strength and the rewards it offers right now.
static final function string DescribeHackable(XComGameState_InteractiveObject Obj)
{
	return GetArchetypeText(Obj) @ "| tactical flag" @ Obj.bOffersTacticalHackRewards @ "| strategic flag" @ Obj.bOffersStrategyHackRewards
		@ "| lock" @ Obj.LockStrength @ "| rewards [" $ NamesToString(Obj.GetHackRewards('')) $ "]";
}

// Logs the situation at the start of a holder's hack (the tower before the change, the mission's reward decks, the other hackable objects): to
// see what a computer offers compared to a tower.
static final function LogHackSituation(XComGameState_InteractiveObject Tower)
{
	local XComGameState_BattleData BattleData;
	local XComGameState_InteractiveObject Other;

	BattleData = XComGameState_BattleData(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_BattleData'));
	if (BattleData != none)
		`log("UniqueTraits : Security hacker -- mission decks: tactical [" $ NamesToString(BattleData.TacticalHackRewards) $ "] strategic [" $ NamesToString(BattleData.StrategyHackRewards)
			$ "] tactical hack completed:" @ BattleData.bTacticalHackCompleted,, 'UniqueTraits');

	`log("UniqueTraits : Security hacker -- tower BEFORE:" @ DescribeHackable(Tower),, 'UniqueTraits');

	foreach `XCOMHISTORY.IterateByClassType(class'XComGameState_InteractiveObject', Other)
	{
		if (Other.ObjectID != Tower.ObjectID && Other.MustBeHacked())
			`log("UniqueTraits : Security hacker -- other hackable object:" @ DescribeHackable(Other),, 'UniqueTraits');
	}
}

// What a security tower offers by itself: its tactical flag is set and nothing else, so it gives the mission's
// TACTICAL deck [ie: Reinforcements_T0 (the bad reward of a failure), Override_T1, Targeting_AimAndCrit_T2]; the other hackable objects (a computer-like
// object) have the strategic flag and give the STRATEGIC deck [ie: WatchList_T1, LootAlloys_T2].
// XComGameState_InteractiveObject.GetHackRewards = the object's private list + (tactical flag ? tactical deck : strategic flag ? strategic deck : nothing).
// For the holder's attempt the tower gets the strategic flag (not the tactical one) and, as its private list, the BAD rewards of the tactical
// deck (the first entry of a deck is its failure reward): success = the computers' rewards, failure = the tower's own penalty.
// Only done when the tower's private list is empty (what it offers equals its deck): otherwise its own rewards would be lost on restore, the
// private list cannot be read back.
static final function array<name> GetBadTacticalRewards(XComGameState_BattleData BattleData)
{
	local X2HackRewardTemplateManager TemplateMan;
	local X2HackRewardTemplate Template;
	local array<name> Bad;
	local name RewardName;

	TemplateMan = class'X2HackRewardTemplateManager'.static.GetHackRewardTemplateManager();
	foreach BattleData.TacticalHackRewards(RewardName)
	{
		Template = TemplateMan.FindHackRewardTemplate(RewardName);
		if (Template != none && Template.bBadThing)
			Bad.AddItem(RewardName);
	}

	return Bad;
}

// Sets the lock strength to exactly Target. The only way to write it is XComGameState_InteractiveObject.SetLocked, which applies the sitrep
// hack-defense modifiers (X2SitRepEffect_ModifyHackDefenses) to the value it is given: the stored LockStrength already includes them, so
// SetLocked(LockStrength) would apply them a second time. The modifiers are a pure function of the value (and exist only with such a sitrep),
// so the input that gives Target is searched: the value itself first (no sitrep: immediate), then a scan.
static final function SetLockStrengthExactly(XComGameState_InteractiveObject Obj, int Target)
{
	local int Candidate;

	Obj.SetLocked(Target);
	if (Obj.LockStrength == Target)
		return;

	for (Candidate = 0; Candidate <= Target * 4 + 20; ++Candidate)
	{
		Obj.SetLocked(Candidate);
		if (Obj.LockStrength == Target)
			return;
	}

	Obj.SetLocked(Target);
}

// Visualization of the backlash ability: the standard one (hit animation and damage flyover of the damage effect), then a flyover above the
// hacker that explains where the HP went (N = the HP lost between the old and the new unit state).
static function BuildVisualization_HackBacklash(XComGameState VisualizeGameState)
{
	local XComGameStateHistory History;
	local XComGameStateContext_Ability AbilityContext;
	local XComGameState_Unit NewUnit, OldUnit;
	local VisualizationActionMetadata ActionMetadata;
	local X2Action_PlaySoundAndFlyOver FlyOver;
	local int Lost;

	class'X2Ability'.static.TypicalAbility_BuildVisualization(VisualizeGameState);

	History = `XCOMHISTORY;
	AbilityContext = XComGameStateContext_Ability(VisualizeGameState.GetContext());
	if (AbilityContext == none)
		return;

	NewUnit = XComGameState_Unit(VisualizeGameState.GetGameStateForObjectID(AbilityContext.InputContext.SourceObject.ObjectID));
	if (NewUnit == none)
		return;

	OldUnit = XComGameState_Unit(History.GetGameStateForObjectID(NewUnit.ObjectID, eReturnType_Reference, VisualizeGameState.HistoryIndex - 1));
	if (OldUnit == none)
		return;

	Lost = int(OldUnit.GetCurrentStat(eStat_HP) - NewUnit.GetCurrentStat(eStat_HP));
	if (Lost <= 0)
		return;

	ActionMetadata.StateObject_OldState = OldUnit;
	ActionMetadata.StateObject_NewState = NewUnit;
	ActionMetadata.VisualizeActor = History.GetVisualizer(NewUnit.ObjectID);

	FlyOver = X2Action_PlaySoundAndFlyOver(class'X2Action_PlaySoundAndFlyOver'.static.AddToVisualizationTree(ActionMetadata, AbilityContext, false, ActionMetadata.LastActionAdded));
	FlyOver.SetSoundAndFlyOverParameters(none, Repl(default.SECURITYHACKER_FLYOVER, "<Damage/>", string(Lost)), '', eColor_Bad);
}

// The finalize of a FAILED hack (ELD_OnStateSubmitted, after the hack is over): the hacker flagged by OnAbilityActivated_SecurityHacker takes
// the damage of the hidden ability UT_SecurityHackerBacklash, activated like any ability. The flag is cleared first.
static function EventListenerReturn OnAbilityActivated_SecurityHackerBacklash(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit Hacker, MutableHacker;
	local XComGameState_Ability BacklashState;
	local XComGameState NewGameState;
	local UnitValue FlagValue;

	if (GameState.GetContext().InterruptionStatus == eInterruptionStatus_Interrupt)
		return ELR_NoInterrupt;

	Hacker = XComGameState_Unit(EventSource);
	if (Hacker == none || !Hacker.GetUnitValue('UT_SecHacker_Backlash', FlagValue) || FlagValue.fValue <= 0)
		return ELR_NoInterrupt;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Security hacker: backlash flag");
	MutableHacker = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Hacker.ObjectID));
	MutableHacker.ClearUnitValue('UT_SecHacker_Backlash');
	`GAMERULES.SubmitGameState(NewGameState);

	BacklashState = XComGameState_Ability(`XCOMHISTORY.GetGameStateForObjectID(Hacker.FindAbility('UT_SecurityHackerBacklash').ObjectID));
	if (BacklashState == none || !BacklashState.AbilityTriggerAgainstSingleTarget(Hacker.GetReference(), false))
	{
		`log("UniqueTraits [WARN] : Security hacker -- the damage of the failed hack could not be activated for" @ Hacker.GetFullName(),, 'UniqueTraits');
		return ELR_NoInterrupt;
	}

	`log("UniqueTraits : Security hacker -- failed hack:" @ Hacker.GetFullName() @ "takes" @ default.SECURITYHACKER_FAILURE_DAMAGE_PCT @ "% of the max HP (rounded up) through armor and ablative protection",, 'UniqueTraits');
	return ELR_NoInterrupt;
}

// A successful hack of one tower disables all of them: every other security tower still locked is marked hacked and gets the event the hack of an
// object fires (the object listens to it to fire the Kismet "interactive object hacked" event, X2Ability_DefaultAbilitySet.FinalizeHackAbility_
// BuildGameState does the same for the hacked one). No loot, no interaction animation for the others (not visualized).
static final function DisableOtherTowers(XComGameState_Unit Hacker, int HackedObjectID, XComGameState GameState)
{
	local XComGameState_InteractiveObject Other, MutableOther;

	foreach `XCOMHISTORY.IterateByClassType(class'XComGameState_InteractiveObject', Other)
	{
		if (Other.ObjectID == HackedObjectID || Other.bHasBeenHacked || !IsTower(Other))
			continue;

		MutableOther = XComGameState_InteractiveObject(GameState.ModifyStateObject(class'XComGameState_InteractiveObject', Other.ObjectID));
		MutableOther.bHasBeenHacked = true;
		`XEVENTMGR.TriggerEvent('ObjectHacked', Hacker, MutableOther, GameState);

		`log("UniqueTraits : Security hacker -- tower" @ GetArchetypeText(Other) @ "disabled by the successful hack",, 'UniqueTraits');
	}
}

// The hack-related activations of the holder (ELD_Immediate: GameState is the ability's own pending state, EventSource the pending hacker).
static function EventListenerReturn OnAbilityActivated_SecurityHacker(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateContext_Ability AbilityContext;
	local XComGameState_Ability AbilityState;
	local XComGameState_Unit Hacker, MutableHacker;
	local XComGameState_InteractiveObject Obj, MutableObj;
	local UnitValue ActiveValue, LockValue, TacticalValue, StrategyValue, PrivateEmptyValue;
	local XComGameState_BattleData BattleData;
	local array<name> Combined, Expected, EmptyRewards;
	local bool bPrivateEmpty;
	local int OldStrength;

	if (!ParseAbilityActivation(GameState, EventSource, 'UT_SecurityHacker', AbilityContext, Hacker))
		return ELR_NoInterrupt;

	AbilityState = XComGameState_Ability(EventData);
	if (AbilityState == none)
		return ELR_NoInterrupt;

	// End of an attempt: the original rules of the tower come back (the rewards were awarded in this state already).
	if (Hacker.GetUnitValue('UT_SecHacker_Object', ActiveValue) && ActiveValue.fValue > 0)
	{
		if (default.SECURITYHACKER_END_ABILITIES.Find(AbilityState.GetMyTemplateName()) == INDEX_NONE)
			return ELR_NoInterrupt;

		Hacker.GetUnitValue('UT_SecHacker_Lock', LockValue);
		Hacker.GetUnitValue('UT_SecHacker_Tactical', TacticalValue);
		Hacker.GetUnitValue('UT_SecHacker_Strategic', StrategyValue);
		Hacker.GetUnitValue('UT_SecHacker_PrivateEmpty', PrivateEmptyValue);

		MutableObj = XComGameState_InteractiveObject(GameState.ModifyStateObject(class'XComGameState_InteractiveObject', int(ActiveValue.fValue)));

		// A carried-out hack (not a cancel): on success every tower is disabled, on failure the hacker takes damage.
		if (default.SECURITYHACKER_FINALIZE_ABILITIES.Find(AbilityState.GetMyTemplateName()) != INDEX_NONE)
		{
			MutableHacker = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', Hacker.ObjectID));
			if (MutableObj.bHasBeenHacked)
				DisableOtherTowers(MutableHacker, MutableObj.ObjectID, GameState);
			else
				MutableHacker.SetUnitFloatValue('UT_SecHacker_Backlash', 1, eCleanup_BeginTactical);	// see OnAbilityActivated_SecurityHackerBacklash

			// As in the base game, a carried-out hack on a tactical-flag object (the tower, normally) uses up the tactical hack: no more retries.
			if (TacticalValue.fValue > 0)
			{
				BattleData = XComGameState_BattleData(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_BattleData'));
				BattleData = XComGameState_BattleData(GameState.ModifyStateObject(class'XComGameState_BattleData', BattleData.ObjectID));
				BattleData.bTacticalHackCompleted = true;
			}
		}

		if (LockValue.fValue > 0 && default.SECURITYHACKER_DEFENSE_MULT > 1.0)
			SetLockStrengthExactly(MutableObj, int(LockValue.fValue));
		MutableObj.bOffersTacticalHackRewards = TacticalValue.fValue > 0;
		MutableObj.bOffersStrategyHackRewards = StrategyValue.fValue > 0;
		if (PrivateEmptyValue.fValue > 0)
		{
			EmptyRewards.Length = 0;
			MutableObj.SetHackRewards(EmptyRewards);
		}

		MutableHacker = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', Hacker.ObjectID));
		MutableHacker.ClearUnitValue('UT_SecHacker_Object');
		return ELR_NoInterrupt;
	}

	// Start of an attempt: the ability that opens the hacking screen (it names the ability that finalizes it), on a security tower.
	if (AbilityState.GetMyTemplate().FinalizeAbilityName == '' || AbilityContext.InputContext.PrimaryTarget.ObjectID == 0)
		return ELR_NoInterrupt;

	Obj = XComGameState_InteractiveObject(GameState.GetGameStateForObjectID(AbilityContext.InputContext.PrimaryTarget.ObjectID));
	if (Obj == none)
		Obj = XComGameState_InteractiveObject(`XCOMHISTORY.GetGameStateForObjectID(AbilityContext.InputContext.PrimaryTarget.ObjectID));
	if (Obj == none)
		return ELR_NoInterrupt;

	`log("UniqueTraits : Security hacker --" @ Hacker.GetFullName() @ "starts a hack on" @ GetArchetypeText(Obj) @ "| tower:" @ IsTower(Obj),, 'UniqueTraits');
	if (!IsTower(Obj))
		return ELR_NoInterrupt;

	LogHackSituation(Obj);

	MutableObj = XComGameState_InteractiveObject(GameState.ModifyStateObject(class'XComGameState_InteractiveObject', Obj.ObjectID));
	OldStrength = MutableObj.LockStrength;

	MutableHacker = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', Hacker.ObjectID));
	MutableHacker.SetUnitFloatValue('UT_SecHacker_Object', Obj.ObjectID, eCleanup_BeginTactical);
	MutableHacker.SetUnitFloatValue('UT_SecHacker_Lock', OldStrength, eCleanup_BeginTactical);
	MutableHacker.SetUnitFloatValue('UT_SecHacker_Tactical', MutableObj.bOffersTacticalHackRewards ? 1 : 0, eCleanup_BeginTactical);
	MutableHacker.SetUnitFloatValue('UT_SecHacker_Strategic', MutableObj.bOffersStrategyHackRewards ? 1 : 0, eCleanup_BeginTactical);

	// The computers' rewards: strategic deck instead of the tactical one, keeping the tower's own failure reward (see GetBadTacticalRewards).
	BattleData = XComGameState_BattleData(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_BattleData'));
	Combined = MutableObj.GetHackRewards('');
	if (MutableObj.bOffersTacticalHackRewards)
		Expected = BattleData.TacticalHackRewards;
	else if (MutableObj.bOffersStrategyHackRewards)
		Expected = BattleData.StrategyHackRewards;
	bPrivateEmpty = BattleData != none && Combined.Length == Expected.Length;

	MutableHacker.SetUnitFloatValue('UT_SecHacker_PrivateEmpty', bPrivateEmpty ? 1 : 0, eCleanup_BeginTactical);
	if (bPrivateEmpty)
	{
		MutableObj.SetHackRewards(GetBadTacticalRewards(BattleData));
		MutableObj.bOffersTacticalHackRewards = false;
		MutableObj.bOffersStrategyHackRewards = true;
	}
	else
	{
		`log("UniqueTraits [WARN] : Security hacker -- the tower has rewards of its own, left as they are (only the defense is doubled)",, 'UniqueTraits');
	}
	if (OldStrength > 0 && default.SECURITYHACKER_DEFENSE_MULT > 1.0)
		SetLockStrengthExactly(MutableObj, Round(float(OldStrength) * default.SECURITYHACKER_DEFENSE_MULT));

	`log("UniqueTraits : Security hacker -- tower AFTER:" @ DescribeHackable(MutableObj),, 'UniqueTraits');

	return ELR_NoInterrupt;
}
