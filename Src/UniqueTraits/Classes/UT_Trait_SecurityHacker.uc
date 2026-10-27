//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_SecurityHacker.uc
//  PURPOSE: Security hacker: when the HOLDER hacks a security tower, the tower's hack defense (its lock strength) is increased by a percentage that
//           depends on the force level of the mission (SECURITYHACKER_DEFENSE_PCT_LOW / _MID / _HIGH, see GetDefenseMultiplier), and when he gets the
//           BIGGEST reward of the tower (the highest MinHackSuccess of its list, normally the tier 2 one, see GetBiggestRewardIndex) he also earns
//           XCOM ability points on top of that reward's own effect. The amount depends on the difficulty of the reward
//           (GetAPReward: SECURITYHACKER_AP_MAX_DIFFICULTY / _BY_DIFFICULTY / _TOP) and is
//           SECURITYHACKER_AP_REWARD_LATE once the XCOM player is past turn SECURITYHACKER_LATE_TURN. The points are given by OnPreAcquiredHackReward_
//           SecurityHacker ('PreAcquiredHackReward', CHL #120, fired by X2HackRewardTemplateManager.AcquireHackRewards for each earned reward, with the
//           pending state of the finalize ability); the hacking screen adds a line about them to the description of that reward for the holder
//           (UIScreenListener_UT_HackingScreen: the hover preview of Perfect Information reads the original template and is left alone).
//           The price: a FAILED hack deals SECURITYHACKER_FAILURE_DAMAGE_PCT % of the hacker's MAX HP (rounded up) of damage to the hacker (a real
//           wound dealt by a hidden ability, going through armor and the ablative protection, that LWOTC's Failsafe cannot cancel since it is not a
//           hack reward), on top of the tower's normal failure penalty. Another soldier hacking the same tower gets the normal tower.
//           A hack is two abilities: the one that opens the hacking screen (its template has a FinalizeAbilityName) and the finalize / cancel
//           ability. So the defense is changed for the duration of the holder's attempt only (one handler, 'AbilityActivated', ELD_Immediate, inside
//           the pending state of the ability):
//           - Start (the ability that opens the screen, before the screen reads the lock strength): the lock strength becomes LockStrength * the
//             multiplier of the force level (SetLockStrengthExactly). The original value (it ALREADY includes the sitrep modifiers) is kept in a
//             UnitValue of the hacker (UT_SecHacker_*).
//           - End (the finalize / cancel abilities, after the rewards were awarded in that very state): the original value is restored EXACTLY (the
//             sitrep modifiers are not applied a second time). On a FINALIZE (not a cancel): if the hack succeeded, every other security tower is
//             marked hacked and gets its 'ObjectHacked' event (what the mission's Kismet reacts to: the same as hacking it); if it failed, the hacker
//             is flagged and takes the damage of a real ability right after (OnAbilityActivated_SecurityHackerBacklash).
//---------------------------------------------------------------------------------------
class UT_Trait_SecurityHacker extends UT_TraitBase config(UniqueTraits);

// Reinforcement of the tower's hack defense, in %, by force level of the mission: LOW below FORCE_LEVEL_MID, MID below FORCE_LEVEL_HIGH, HIGH from there on.
var config int SECURITYHACKER_DEFENSE_PCT_LOW, SECURITYHACKER_DEFENSE_PCT_MID, SECURITYHACKER_DEFENSE_PCT_HIGH;
var config int SECURITYHACKER_FORCE_LEVEL_MID, SECURITYHACKER_FORCE_LEVEL_HIGH;
var config int SECURITYHACKER_FAILURE_DAMAGE_PCT;
// XCOM ability points of the biggest reward: the first SECURITYHACKER_AP_BY_DIFFICULTY[i] whose SECURITYHACKER_AP_MAX_DIFFICULTY[i] is >= the MinHackSuccess of the
// reward, else SECURITYHACKER_AP_TOP; SECURITYHACKER_AP_REWARD_LATE when the XCOM player is past turn SECURITYHACKER_LATE_TURN.
var config array<int> SECURITYHACKER_AP_MAX_DIFFICULTY, SECURITYHACKER_AP_BY_DIFFICULTY;
var config int SECURITYHACKER_AP_TOP, SECURITYHACKER_AP_REWARD_LATE, SECURITYHACKER_LATE_TURN;
var config array<string> SECURITYHACKER_TOWER_KEYWORDS;
var config array<name> SECURITYHACKER_END_ABILITIES;
var config array<name> SECURITYHACKER_FINALIZE_ABILITIES;
var localized string SECURITYHACKER_FLYOVER;
var localized string SECURITYHACKER_AP_TEXT;   // added to the description of the biggest reward in the hacking screen, <Points/> = the amount

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

// UT_TextTags.ReplaceTokens: {SECURITYHACKER_AP_MIN} / {SECURITYHACKER_AP_MAX} = the smallest and the largest number of XCOM ability points the difficulty table can give (not the
// late one, which has its own placeholder), with the CURRENT values (ini or Mod Config Menu).
static function bool GetTextValue(string Key, out string OutString)
{
	local int i, Lowest, Highest;

	if (!(Key ~= "SECURITYHACKER_AP_MIN") && !(Key ~= "SECURITYHACKER_AP_MAX"))
		return false;

	Lowest = default.SECURITYHACKER_AP_TOP;
	Highest = default.SECURITYHACKER_AP_TOP;
	for (i = 0; i < default.SECURITYHACKER_AP_MAX_DIFFICULTY.Length && i < default.SECURITYHACKER_AP_BY_DIFFICULTY.Length; ++i)
	{
		Lowest = Min(Lowest, default.SECURITYHACKER_AP_BY_DIFFICULTY[i]);
		Highest = Max(Highest, default.SECURITYHACKER_AP_BY_DIFFICULTY[i]);
	}

	OutString = string((Key ~= "SECURITYHACKER_AP_MIN") ? Lowest : Highest);

	return true;
}

// Event registrations (X2EventListener_UniqueTraits.CreateTacticalListeners calls this for every trait of the pool that is not disabled).
static function OnCreateTacticalListeners(CHEventListenerTemplate Template)
{
	// Security hacker: while the HOLDER hacks a security tower (from the ability that opens the hacking screen to the finalize / cancel ability), the
	// tower's lock is raised by the force level (ELD_Immediate: inside the ability's pending state, before the screen reads it); if it succeeds, disables every security tower.
	Template.AddCHEvent('AbilityActivated', OnAbilityActivated_SecurityHacker, ELD_Immediate, 50);
	Template.AddCHEvent('AbilityActivated', OnAbilityActivated_SecurityHackerBacklash, ELD_OnStateSubmitted, 50);
	// Security hacker: the XCOM ability points on top of the biggest reward of the tower (CHL #120, fired by AcquireHackRewards for each earned reward).
	// Priority -100 on purpose: the listeners of this event can cancel the reward (Data[0].b = true, LWOTC's Failsafe does it for a bad reward); ours must run
	// after all of them to see the final decision and give the points only for a reward that is really given.
	Template.AddCHEvent('PreAcquiredHackReward', OnPreAcquiredHackReward_SecurityHacker, ELD_Immediate, -100);
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
// The biggest reward of a list = the one with the highest MinHackSuccess among the rewards that are not a bad thing (normally the tier 2 one, the last
// of the list). INDEX_NONE when there is none.
static final function int GetBiggestRewardIndex(array<name> Rewards)
{
	local X2HackRewardTemplateManager TemplateMan;
	local X2HackRewardTemplate Template;
	local int i, BestIndex, BestScore;

	TemplateMan = class'X2HackRewardTemplateManager'.static.GetHackRewardTemplateManager();
	BestIndex = INDEX_NONE;
	BestScore = -1;
	for (i = 0; i < Rewards.Length; ++i)
	{
		Template = TemplateMan.FindHackRewardTemplate(Rewards[i]);
		if (Template == none || Template.bBadThing)
			continue;

		// ">=": on a tie the later one (the better in the list order) is kept.
		if (Template.MinHackSuccess >= BestScore)
		{
			BestIndex = i;
			BestScore = Template.MinHackSuccess;
		}
	}

	return BestIndex;
}

// The factor applied to the tower's hack defense: 1 + (25 % below force level 8, 50 % below 15, 75 % from 15 on, by default) / 100. The force level is
// the one of the mission (BattleData.GetForceLevel, which is the alien headquarters' level when the mission was created).
static final function float GetDefenseMultiplier(XComGameState_BattleData BattleData)
{
	local int ForceLevel, Pct;

	ForceLevel = (BattleData != none) ? BattleData.GetForceLevel() : 1;

	if (ForceLevel < default.SECURITYHACKER_FORCE_LEVEL_MID)
		Pct = default.SECURITYHACKER_DEFENSE_PCT_LOW;
	else if (ForceLevel < default.SECURITYHACKER_FORCE_LEVEL_HIGH)
		Pct = default.SECURITYHACKER_DEFENSE_PCT_MID;
	else
		Pct = default.SECURITYHACKER_DEFENSE_PCT_HIGH;

	return 1.0 + float(Pct) / 100.0;
}

// True when the XCOM player of the hacker is past turn SECURITYHACKER_LATE_TURN: the ability points reward is then the reduced one.
static final function bool IsLateTurn(XComGameState_Unit Hacker)
{
	local XComGameState_Player PlayerState;

	PlayerState = XComGameState_Player(`XCOMHISTORY.GetGameStateForObjectID(Hacker.ControllingPlayer.ObjectID));

	return PlayerState != none && PlayerState.PlayerTurnCount > default.SECURITYHACKER_LATE_TURN;
}

// The XCOM ability points earned with the reward Template by Hacker: SECURITYHACKER_AP_REWARD_LATE past the turn limit, else by the difficulty of the
// reward (its MinHackSuccess, without the random modifier rolled for the hack).
static final function int GetAPReward(X2HackRewardTemplate Template, XComGameState_Unit Hacker)
{
	local int i;

	if (IsLateTurn(Hacker))
		return default.SECURITYHACKER_AP_REWARD_LATE;

	for (i = 0; i < default.SECURITYHACKER_AP_MAX_DIFFICULTY.Length && i < default.SECURITYHACKER_AP_BY_DIFFICULTY.Length; ++i)
	{
		if (Template.MinHackSuccess <= default.SECURITYHACKER_AP_MAX_DIFFICULTY[i])
			return default.SECURITYHACKER_AP_BY_DIFFICULTY[i];
	}

	return default.SECURITYHACKER_AP_TOP;
}

// True when Template is the biggest reward of the list the tower offers (private list + deck, GetBiggestRewardIndex), Hacker holds the trait and the
// tower is a security tower, ie: when the reward is the one that gives ability points.
static final function bool IsAPReward(X2HackRewardTemplate Template, XComGameState_Unit Hacker, XComGameState_InteractiveObject Tower)
{
	local array<name> Rewards;
	local int Index;

	if (Template == none || Template.bBadThing || Hacker == none || Tower == none || !IsTower(Tower)
		|| !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Hacker, 'UT_SecurityHacker'))
		return false;

	Rewards = Tower.GetHackRewards('');
	Index = GetBiggestRewardIndex(Rewards);

	return Index != INDEX_NONE && Rewards[Index] == Template.DataName;
}

// 'PreAcquiredHackReward' (CHL #120, ELD_Immediate: GameState is the pending state of the finalize ability): the data is a tuple 'OverrideHackRewards'
// [0] bool (override), [1] the hacker, [2] the hack target; the source is the reward template about to be given. Gives the ability points when it is
// the biggest reward of a security tower hacked by a holder.
static function EventListenerReturn OnPreAcquiredHackReward_SecurityHacker(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;
	local X2HackRewardTemplate Template;
	local XComGameState_Unit Hacker;
	local XComGameState_InteractiveObject Tower;
	local int Points;

	Tuple = XComLWTuple(EventData);
	Template = X2HackRewardTemplate(EventSource);
	if (Tuple == none || Template == none || GameState == none || Tuple.Id != 'OverrideHackRewards' || Tuple.Data.Length < 3 || Tuple.Data[0].b)
		return ELR_NoInterrupt;

	Hacker = XComGameState_Unit(Tuple.Data[1].o);
	Tower = XComGameState_InteractiveObject(Tuple.Data[2].o);
	if (!IsAPReward(Template, Hacker, Tower))
		return ELR_NoInterrupt;

	Points = GetAPReward(Template, Hacker);
	GiveAbilityPoints(GameState, Points);
	`log("UniqueTraits : Security hacker -- reward" @ Template.DataName @ "(difficulty" @ Template.MinHackSuccess $ "): +" $ Points @ "XCOM ability point(s) for" @ Hacker.GetFullName(),, 'UniqueTraits');

	return ELR_NoInterrupt;
}

// Not capped: unlike the tactical ability point events, which stop at MaxTacticalEventAbilityPointsPerBattle, the amount is the exact one.
static final function GiveAbilityPoints(XComGameState NewGameState, int Points)
{
	local XComGameState_HeadquartersXCom XComHQ;

	if (Points <= 0)
		return;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return;

	XComHQ = XComGameState_HeadquartersXCom(NewGameState.ModifyStateObject(class'XComGameState_HeadquartersXCom', XComHQ.ObjectID));
	XComHQ.AddResource(NewGameState, 'AbilityPoint', Points);
}

// Sets the lock strength to exactly Target. The only way to write it is XComGameState_InteractiveObject.SetLocked, which applies the sitrep
// hack-defense modifiers (X2SitRepEffect_ModifyHackDefenses) to the value it is given: the stored LockStrength already includes them, so
// SetLocked(LockStrength) would apply them a second time. The modifiers are a pure function of the value (and exist only with such a sitrep),
// so the input that gives Target is searched: the value itself first (no sitrep: immediate), then a scan.
// SetLocked also sets bOffersStrategyHackRewards = true (XComGameState_InteractiveObject.uc:597), which we never want to keep (LWOTC's
// SeqAct_GetAssociatedObjectiveObjects counts the hackable objects that have it): the flag is put back as it was. SetLocked needs the object's visualizer
// (it spawns a lock info on it without a null check): without one nothing is changed.
static final function SetLockStrengthExactly(XComGameState_InteractiveObject Obj, int Target)
{
	local int Candidate;
	local bool bOffersStrategy;

	if (Obj.GetVisualizer() == none)
	{
		`log("UniqueTraits [WARN] : Security hacker -- no visualizer for" @ GetArchetypeText(Obj) @ ", the hack defense is left as it is",, 'UniqueTraits');
		return;
	}

	bOffersStrategy = Obj.bOffersStrategyHackRewards;

	Obj.SetLocked(Target);
	if (Obj.LockStrength != Target)
	{
		for (Candidate = 0; Candidate <= Target * 4 + 20; ++Candidate)
		{
			Obj.SetLocked(Candidate);
			if (Obj.LockStrength == Target)
				break;
		}

		if (Obj.LockStrength != Target)
			Obj.SetLocked(Target);
	}

	Obj.bOffersStrategyHackRewards = bOffersStrategy;
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
	local UnitValue ActiveValue, LockValue;
	local XComGameState_BattleData BattleData;
	local int OldStrength, NewStrength;

	if (!ParseAbilityActivation(GameState, EventSource, 'UT_SecurityHacker', AbilityContext, Hacker))
		return ELR_NoInterrupt;

	AbilityState = XComGameState_Ability(EventData);
	if (AbilityState == none)
		return ELR_NoInterrupt;

	// End of an attempt: the original defense of the tower comes back (the rewards were awarded in this state already).
	if (Hacker.GetUnitValue('UT_SecHacker_Object', ActiveValue) && ActiveValue.fValue > 0)
	{
		if (default.SECURITYHACKER_END_ABILITIES.Find(AbilityState.GetMyTemplateName()) == INDEX_NONE)
			return ELR_NoInterrupt;

		Hacker.GetUnitValue('UT_SecHacker_Lock', LockValue);

		MutableObj = XComGameState_InteractiveObject(GameState.ModifyStateObject(class'XComGameState_InteractiveObject', int(ActiveValue.fValue)));

		// A carried-out hack (not a cancel): on success every tower is disabled, on failure the hacker takes damage. The tower keeps its tactical
		// flag, so the vanilla finalize uses up the tactical hack itself (no more retries, as in the base game).
		if (default.SECURITYHACKER_FINALIZE_ABILITIES.Find(AbilityState.GetMyTemplateName()) != INDEX_NONE)
		{
			MutableHacker = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', Hacker.ObjectID));
			if (MutableObj.bHasBeenHacked)
				DisableOtherTowers(MutableHacker, MutableObj.ObjectID, GameState);
			else
				MutableHacker.SetUnitFloatValue('UT_SecHacker_Backlash', 1, eCleanup_BeginTactical);	// see OnAbilityActivated_SecurityHackerBacklash
		}

		if (LockValue.fValue > 0 && MutableObj.LockStrength != int(LockValue.fValue))
			SetLockStrengthExactly(MutableObj, int(LockValue.fValue));

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

	BattleData = XComGameState_BattleData(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_BattleData'));
	NewStrength = Round(float(OldStrength) * GetDefenseMultiplier(BattleData));
	`log("UniqueTraits : Security hacker -- force level" @ (BattleData != none ? BattleData.GetForceLevel() : 0) @ ": hack defense" @ OldStrength @ "->" @ NewStrength,, 'UniqueTraits');
	if (OldStrength > 0 && NewStrength != OldStrength)
		SetLockStrengthExactly(MutableObj, NewStrength);

	`log("UniqueTraits : Security hacker -- tower AFTER:" @ DescribeHackable(MutableObj),, 'UniqueTraits');

	return ELR_NoInterrupt;
}
