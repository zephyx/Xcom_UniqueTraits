//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Coroner.uc
//  PURPOSE: Coroner. While a Coroner is alive in the squad, every alien that dies has CORONER_DROP_CHANCE_PCT percent to leave a green loot zone (in addition to its
//           ordinary yellow one, on a neighbouring tile so that the two stay apart) for 3 turns (the base game's loot timer). The zone holds a fictive item, "Autopsy: <type>"
//           (UT_AutopsyItemTemplate), that ONLY the Coroner can pick up (the template's CanBeLootedByUnit). Picking it up (OnItemLooted_Coroner) leaves the item in the backpack
//           and notes the autopsy on the Coroner (UnitValues, cleared when the next mission starts). At the END of the mission (OnPostMission) the autopsy items the base game moved
//           to the loot recap (backpacks of living / recovered soldiers, zones left behind in a swept mission) are added to the campaign tally (XComGameState_UT_Autopsy).
//           Drawback: -CORONER_DAMAGE_MALUS_PCT % on all the damage he deals, and CORONER_AUTOPSY_DAMAGE_MALUS_PCT % more
//           for the rest of a mission in which he has done at least one autopsy (X2Effect_UT_Coroner).
//           The strategic effects of the tally (research time, black market price, resources of the recycling researches) are UT_AutopsyBonuses. The "autopsy board" ability (UT_CoronerBoard)
//           lists the tally in its description.
//           The blue colour: the zone's visualizer is a UT_LootDropActor (recolored base game marker), see PrepareAutopsyMarker.
//---------------------------------------------------------------------------------------
class UT_Trait_Coroner extends UT_TraitBase config(UniqueTraits);

var config int CORONER_DROP_CHANCE_PCT;
var config int CORONER_DAMAGE_MALUS_PCT;
var config int CORONER_AUTOPSY_DAMAGE_MALUS_PCT;

// The Coroner is at full strength only with a LIGHT weapon as primary (WeaponCat in CORONER_LIGHT_WEAPON_CATS), otherwise his zone chance AND his damage malus are multiplied by
// CORONER_HEAVY_WEAPON_FACTOR_PCT percent (50: 10 % becomes 5 %).
var config int CORONER_HEAVY_WEAPON_FACTOR_PCT;
var config array<name> CORONER_LIGHT_WEAPON_CATS;

// The strategic bonus of the autopsies (UT_AutopsyBonuses): CORONER_BONUS_PER_AUTOPSY_PCT percent per autopsy of an alien type, up to CORONER_MAX_AUTOPSIES autopsies of that type (the Coroner
// gets no more zones for a type once XCOM has that many). The TYPE of an autopsy is the corpse the dead alien left (see FindCorpseLeft).
var config int CORONER_BONUS_PER_AUTOPSY_PCT;
var config int CORONER_MAX_AUTOPSIES;
// Runtime memory (never written in an ini): the corpses of the state CLAIM_STATE_INDEX already attributed to a dead unit, because one state can hold several deaths (a grenade) and the
// auto loot of all of them is added to the same bucket.
var config int CLAIM_STATE_INDEX;
var config array<name> CLAIMED_CORPSES;

// A research whose name starts with one of these ("Render": LWOTC's corpse recycling) and whose cost lists a corpse gives CORONER_BONUS_PER_AUTOPSY_PCT percent more resources per
// autopsy of that type (rounded to the nearest: 1 Elerium Core at +40 % stays 1).
var config array<string> CORONER_RECYCLE_TECH_PREFIXES;

// The colour of the zone's marker, as percentages (0 to 100, 100 = 1.0) of red, green and blue, and the material parameters it is applied to (see UT_LootDropActor).
var config int CORONER_MARKER_RED;
var config int CORONER_MARKER_GREEN;
var config int CORONER_MARKER_BLUE;
var config array<name> CORONER_MARKER_PARAMS;

// The texture of the zone's counter badge ("Icon" parameter of its material), as a package path ("UniqueTraits_Icons.loot_counter_green"), loaded at run time. The badge (yellow body,
// black number, red chevron) is baked in the base game's texture UI_3D.Waypoint.loot_counter and the material's colour parameter does not reach it: only another texture can recolor it.
// Empty or not found: the base game's yellow badge stays (see UT_LootDropActor).
var config string CORONER_MARKER_COUNTER_TEXTURE;

var localized string CORONER_ITEM_NAME;      // "Autopsy: %TYPE"
var localized string CORONER_ITEM_NAME_BASE; // "Autopsy"
var localized string CORONER_ITEM_SUMMARY;
var localized string CORONER_BOARD_LINE;  // "%TYPE : %COUNT/%MAX"
var localized string CORONER_BOARD_EMPTY;
var localized string CORONER_CORPSE_STRIP;  // words removed from a corpse's name to name its type ("|" separated, longest first)
var localized string CORONER_RECYCLE_BANNER; // banner title when a recycling research gives bonus resources

const UV_AUTOPSY_PREFIX = "UT_Coroner_Autopsy_";

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Coroner());
	Templates.AddItem(CoronerBoard());

	return Templates;
}

// Event registrations (X2EventListener_UniqueTraits.CreateTacticalListeners calls this for every trait of the pool that is not disabled).
static function OnCreateTacticalListeners(CHEventListenerTemplate Template)
{
	// Submitted, not immediate: the base game rolls the loot of the dead unit (and sets bKilledByExplosion) after the immediate event, so only the finished state tells whether a body was left.
	Template.AddCHEvent('UnitDied', OnUnitDied_Coroner, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('ItemLooted', OnItemLooted_Coroner, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('UT_AutopsyDropCreated', OnAutopsyDropCreated_Coroner, ELD_OnStateSubmitted, 50);
}

// Event registrations of the strategy layer (X2EventListener_UniqueTraits.CreateStrategyListeners calls this for every trait of the pool that is not disabled).
static function OnCreateStrategyListeners(CHEventListenerTemplate Template)
{
	// After the template's own ResearchCompletedFn has given its reward (the base game fires the event once it has run).
	Template.AddCHEvent('ResearchCompleted', OnResearchCompleted_Coroner, ELD_Immediate, 50);
}

// The passive carries the damage drawback. The icon is the generic one until the trait has its own in UniqueTraits_Icons (UT_Coroner).
static function X2AbilityTemplate Coroner()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_Coroner DamageEffect;

	Template = PurePassive('UT_Coroner', "img:///UniqueTraits_Icons.UT_Coroner", true);

	DamageEffect = new class'X2Effect_UT_Coroner';
	DamageEffect.EffectName = 'UT_Coroner_DamageMalus';
	DamageEffect.BuildPersistentEffect(1, true, false);
	DamageEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(DamageEffect);

	return Template;
}

// "Autopsy board": an icon holder whose description is the campaign's autopsy tally (Nemesis' hunting board does the same with the kills). PurePassive keeps the RAW LocLongDescription
// in the buff, so the tag <Ability:UT_CoronerBoard/> is expanded each time it is displayed (ExpandAbilityTag), with the live tally. Generic icon until it has one of its own.
static function X2AbilityTemplate CoronerBoard()
{
	return PurePassive('UT_CoronerBoard', "img:///UniqueTraits_Icons.UT_Nemesis_2", false);
}

// UT_TraitBase.ExpandAbilityTag: <Ability:UT_CoronerBoard/>. The tally is the campaign's, whoever looks at it.
static function bool ExpandAbilityTag(string InString, out string OutString, Object ParseObj, Object StrategyParseObj, XComGameState GameState)
{
	if (!(InString ~= "UT_CoronerBoard"))
		return false;

	OutString = BuildBoardText();

	return true;
}

// One line per alien type XCOM has autopsied at least once, most autopsies first: "Sectoid : 3/4" (autopsies counted / the cap).
static final function string BuildBoardText()
{
	local XComGameState_UT_Autopsy Tally;
	local array<name> Groups;
	local array<int> Counts;
	local int i, j, TmpCount, Max;
	local name TmpGroup;
	local string Line, Result;

	Tally = class'XComGameState_UT_Autopsy'.static.GetState();
	if (Tally == none)
		return default.CORONER_BOARD_EMPTY;

	Tally.GetTotals(Groups, Counts);
	for (i = Groups.Length - 1; i >= 0; --i)
	{
		if (Counts[i] <= 0)
		{
			Groups.Remove(i, 1);
			Counts.Remove(i, 1);
		}
	}

	if (Groups.Length == 0)
		return default.CORONER_BOARD_EMPTY;

	for (i = 0; i < Groups.Length - 1; ++i)
	{
		for (j = i + 1; j < Groups.Length; ++j)
		{
			if (Counts[j] > Counts[i])
			{
				TmpCount = Counts[i];
				Counts[i] = Counts[j];
				Counts[j] = TmpCount;
				TmpGroup = Groups[i];
				Groups[i] = Groups[j];
				Groups[j] = TmpGroup;
			}
		}
	}

	Max = default.CORONER_MAX_AUTOPSIES;
	for (i = 0; i < Groups.Length; ++i)
	{
		Line = Repl(default.CORONER_BOARD_LINE, "%TYPE", GetTypeLabel(Groups[i]));
		Line = Repl(Line, "%COUNT", string(Min(Counts[i], Max)));
		Line = Repl(Line, "%MAX", string(Max));
		Result = (Result == "") ? Line : Result $ "\n" $ Line;
	}

	return Result;
}

// The fictive item (registered by X2Item_UniqueTraits). Never built, bought, sold or kept: it is looted in the mission, listed by the loot recap and credited to the tally by OnPostMission, then deleted.
static function UT_AutopsyItemTemplate CreateAutopsyItem()
{
	local UT_AutopsyItemTemplate Template;

	`CREATE_X2TEMPLATE(class'UT_AutopsyItemTemplate', Template, 'UT_AutopsyReport');

	Template.strImage = "img:///UILibrary_StrategyImages.X2InventoryIcons.Inv_Alien_Datapad";
	Template.LootStaticMesh = StaticMesh'UI_3D.Loot.AlienDatapad';
	Template.FriendlyName = default.CORONER_ITEM_NAME_BASE;
	Template.CanBeBuilt = false;
	Template.bAlwaysUnique = true;
	Template.OnAcquiredFn = OnAutopsyAcquired;

	return Template;
}

// The autopsy items only exist to be listed by the loot recap screen after a mission (OnPostMission). When the loot is moved to the HQ inventory (the template is HideInInventory,
// so PutItemInInventory calls this right after adding the item) the item is taken out again and deleted: nothing stays in the HQ.
static function bool OnAutopsyAcquired(XComGameState NewGameState, XComGameState_Item ItemState)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local int i;

	foreach NewGameState.IterateByClassType(class'XComGameState_HeadquartersXCom', XComHQ)
		break;

	if (XComHQ == none)
		return false;

	i = XComHQ.Inventory.Find('ObjectID', ItemState.ObjectID);
	if (i != INDEX_NONE)
		XComHQ.Inventory.Remove(i, 1);

	NewGameState.RemoveStateObject(ItemState.ObjectID);

	return true;
}

// Every ability that loots by area (the base game's Loot) refuses an autopsy zone as a target for anybody but the Coroner (X2Condition_UT_AutopsyLoot). Abilities are not
// varied by difficulty, so the current cache is enough.
static function OnPostTemplatesCreated()
{
	local X2AbilityTemplateManager AbilityManager;
	local X2DataTemplate DataTemplate;
	local X2AbilityTemplate AbilityTemplate;
	local int Patched;

	AbilityManager = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();
	foreach AbilityManager.IterateTemplates(DataTemplate, none)
	{
		AbilityTemplate = X2AbilityTemplate(DataTemplate);
		if (AbilityTemplate == none || X2AbilityMultiTarget_Loot(AbilityTemplate.AbilityMultiTargetStyle) == none)
			continue;

		// Both lists: the zone must neither be the PRIMARY target (an empty loot window opened for a soldier who cannot take anything) nor come along as an area target.
		AbilityTemplate.AbilityTargetConditions.AddItem(new class'X2Condition_UT_AutopsyLoot');
		AbilityTemplate.AbilityMultiTargetConditions.AddItem(new class'X2Condition_UT_AutopsyLoot');
		++Patched;
	}

	`log("UniqueTraits : Coroner -- autopsy zones closed to other looters in" @ Patched @ "loot ability template(s)",, 'UniqueTraits');
}

// ---------------------------------------------------------------------------------------- names

// The corpse the base game really left for this unit (the TYPE of an autopsy is the corpse, and there is no autopsy without a body). Runs once the death state is
// SUBMITTED: the base game has then rolled the unit's loot (RollForAutoLoot adds the corpse to BattleData.AutoLootBucket, or nothing when an explosion destroyed it, the unit has no loot, or
// a perk changed the kill)
static final function name FindCorpseLeft(XComGameState_Unit DeadUnit, XComGameState GameState, out string Why)
{
	local X2CharacterTemplate CharTemplate;
	local XComGameState_BattleData BattleData, OldBattleData;
	local LootReference Ref;
	local name Corpse;
	local int ForceLevel, i, Have, Claimed;

	CharTemplate = DeadUnit.GetMyTemplate();
	if (CharTemplate == none)
	{
		Why = "no character template";
		return '';
	}

	BattleData = XComGameState_BattleData(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_BattleData'));
	ForceLevel = (BattleData != none) ? BattleData.GetForceLevel() : 0;

	foreach CharTemplate.Loot.LootReferences(Ref)
	{
		if (Ref.ForceLevel > ForceLevel)
			continue;

		Corpse = FindCorpseInTable(Ref.LootTableName, 0);
		if (Corpse != '')
			break;
	}

	if (Corpse == '')
	{
		Why = "no corpse in its loot tables";
		return '';
	}

	// What this state added to the mission's auto loot.
	if (BattleData != none)
		BattleData = XComGameState_BattleData(GameState.GetGameStateForObjectID(BattleData.ObjectID));
	if (BattleData == none)
	{
		Why = "the base game left no corpse (" $ Corpse $ "; killed by explosion" @ DeadUnit.bKilledByExplosion $ ")";
		return '';
	}

	OldBattleData = XComGameState_BattleData(BattleData.GetPreviousVersion());
	for (i = (OldBattleData != none) ? OldBattleData.AutoLootBucket.Length : 0; i < BattleData.AutoLootBucket.Length; ++i)
	{
		if (BattleData.AutoLootBucket[i] == Corpse)
			++Have;
	}

	if (default.CLAIM_STATE_INDEX != GameState.HistoryIndex)
	{
		default.CLAIM_STATE_INDEX = GameState.HistoryIndex;
		default.CLAIMED_CORPSES.Length = 0;
	}

	for (i = 0; i < default.CLAIMED_CORPSES.Length; ++i)
	{
		if (default.CLAIMED_CORPSES[i] == Corpse)
			++Claimed;
	}

	if (Have <= Claimed)
	{
		Why = "the base game left no corpse (" $ Corpse $ "; killed by explosion" @ DeadUnit.bKilledByExplosion $ ")";
		return '';
	}

	default.CLAIMED_CORPSES.AddItem(Corpse);

	return Corpse;
}

// The corpse a loot table can give (an item named "Corpse..."), following the tables it references.
static final function name FindCorpseInTable(name TableName, int Depth)
{
	local array<LootTable> Tables;
	local array<LootTableEntry> Entries;
	local LootTableEntry Entry;
	local name Corpse;
	local int i;

	if (Depth > 4)
		return '';

	Tables = class'X2LootTableManager'.static.GetLootTableManager().LootTables;
	for (i = 0; i < Tables.Length; ++i)
	{
		if (Tables[i].TableName != TableName)
			continue;

		Entries = Tables[i].Loots;
		foreach Entries(Entry)
		{
			if (Entry.TemplateName != '' && Left(string(Entry.TemplateName), 6) ~= "Corpse" && Entry.Chance > 0)
				return Entry.TemplateName; // the real roll is checked against the auto loot bucket (FindCorpseLeft)
			else if (Entry.TableRef != '' && Entry.TableRef != TableName)
			{
				Corpse = FindCorpseInTable(Entry.TableRef, Depth + 1);
				if (Corpse != '')
					return Corpse;
			}
		}
	}

	return '';
}

// A name without leading and trailing spaces.
static final function string TrimSpaces(string Text)
{
	while (Len(Text) > 0 && Left(Text, 1) == " ")
		Text = Mid(Text, 1);
	while (Len(Text) > 0 && Right(Text, 1) == " ")
		Text = Left(Text, Len(Text) - 1);

	return Text;
}

// The name the player knows the type by: for a corpse item, its name without the words of CORONER_CORPSE_STRIP ("Cadavre de Muton" -> "Muton"). For an older entry keyed by character group,
// the character template that gives its name to the group, else any template of the group, else the name itself.
static final function string GetTypeLabel(name Group)
{
	local X2CharacterTemplateManager CharacterManager;
	local X2ItemTemplate ItemTemplate;
	local X2DataTemplate DataTemplate;
	local X2CharacterTemplate CharacterTemplate;
	local array<string> Words;
	local string Label, Word;
	local name TemplateGroup;

	ItemTemplate = class'X2ItemTemplateManager'.static.GetItemTemplateManager().FindItemTemplate(Group);
	if (ItemTemplate != none)
	{
		Label = ItemTemplate.GetItemFriendlyNameNoStats();
		ParseStringIntoArray(default.CORONER_CORPSE_STRIP, Words, "|", true);
		foreach Words(Word)
		{
			if (Word != "")
				Label = Repl(Label, Word, "", false);
		}

		Label = TrimSpaces(Label);

		return (Label != "") ? Label : ItemTemplate.GetItemFriendlyNameNoStats();
	}

	CharacterManager = class'X2CharacterTemplateManager'.static.GetCharacterTemplateManager();
	foreach CharacterManager.IterateTemplates(DataTemplate, none)
	{
		CharacterTemplate = X2CharacterTemplate(DataTemplate);
		if (CharacterTemplate == none || CharacterTemplate.strCharacterName == "")
			continue;

		TemplateGroup = CharacterTemplate.CharacterGroupName;
		if (TemplateGroup == '')
			TemplateGroup = CharacterTemplate.DataName;

		if (TemplateGroup != Group)
			continue;

		Label = CharacterTemplate.strCharacterName;
		if (CharacterTemplate.DataName == Group)
			break;
	}

	return (Label != "") ? Label : string(Group);
}

static final function string GetAutopsyName(name Group)
{
	return Repl(default.CORONER_ITEM_NAME, "%TYPE", GetTypeLabel(Group));
}

// Every type name the Coroner's per-mission UnitValues can be named after (they cannot be listed): the corpse items of the game, and the character groups of older versions.
static final function array<name> GetAllGroups()
{
	local X2CharacterTemplateManager CharacterManager;
	local X2DataTemplate DataTemplate;
	local X2CharacterTemplate CharacterTemplate;
	local array<name> Groups;
	local name Group;

	foreach class'X2ItemTemplateManager'.static.GetItemTemplateManager().IterateTemplates(DataTemplate, none)
	{
		if (Left(string(DataTemplate.DataName), 6) ~= "Corpse" && Groups.Find(DataTemplate.DataName) == INDEX_NONE)
			Groups.AddItem(DataTemplate.DataName);
	}

	CharacterManager = class'X2CharacterTemplateManager'.static.GetCharacterTemplateManager();
	foreach CharacterManager.IterateTemplates(DataTemplate, none)
	{
		CharacterTemplate = X2CharacterTemplate(DataTemplate);
		if (CharacterTemplate == none)
			continue;

		Group = CharacterTemplate.CharacterGroupName;
		if (Group == '')
			Group = CharacterTemplate.DataName;

		if (Groups.Find(Group) == INDEX_NONE)
			Groups.AddItem(Group);
	}

	return Groups;
}

static final function name AutopsyValueName(name Group)
{
	return name(UV_AUTOPSY_PREFIX $ string(Group));
}

// ---------------------------------------------------------------------------------------- the drop

// The Coroner of the squad, still in the fight (none if there is no such soldier).
static final function XComGameState_Unit FindCoroner(XComGameState GameState)
{
	local XComGameStateHistory History;
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference SquadRef;
	local XComGameState_Unit SquadUnit;

	History = `XCOMHISTORY;
	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return none;

	foreach XComHQ.Squad(SquadRef)
	{
		SquadUnit = XComGameState_Unit(GameState.GetGameStateForObjectID(SquadRef.ObjectID));
		if (SquadUnit == none)
			SquadUnit = XComGameState_Unit(History.GetGameStateForObjectID(SquadRef.ObjectID));

		if (SquadUnit != none && !SquadUnit.IsDead() && !SquadUnit.bRemovedFromPlay && class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SquadUnit, 'UT_Coroner'))
			return SquadUnit;
	}

	return none;
}

// A light primary weapon (pistol, autopistol, SMG, bullpup, arc thrower: the ini list of weapon categories) in the primary slot. A pistol carried as a secondary does not count.
static final function bool HasLightPrimary(XComGameState_Unit Unit)
{
	local XComGameState_Item PrimaryWeapon;
	local X2WeaponTemplate WeaponTemplate;

	if (Unit == none)
		return false;

	PrimaryWeapon = Unit.GetPrimaryWeapon();
	if (PrimaryWeapon == none)
		return false;

	WeaponTemplate = X2WeaponTemplate(PrimaryWeapon.GetMyTemplate());

	return WeaponTemplate != none && default.CORONER_LIGHT_WEAPON_CATS.Find(WeaponTemplate.WeaponCat) != INDEX_NONE;
}

// 100 with a light primary weapon, CORONER_HEAVY_WEAPON_FACTOR_PCT otherwise: the share of the trait's zone chance and damage malus the soldier keeps.
static final function int GetWeaponFactorPct(XComGameState_Unit Unit)
{
	return HasLightPrimary(Unit) ? 100 : default.CORONER_HEAVY_WEAPON_FACTOR_PCT;
}

// 'UnitDied' (EventSource = the dead unit), ELD_OnStateSubmitted: an enemy of the regular force (not a ghost copy, not a summoned unit, which would make the zones farmable) that left a body
// (FindCorpseLeft) leaves a zone with the chance, if a Coroner is still alive. The zone is created in a change container of its own, after the death (its fountain and marker are visualized
// by that container). It is moved to a free neighbouring tile: on the unit's own tile it would sit exactly under the ordinary loot marker.
static function EventListenerReturn OnUnitDied_Coroner(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit DeadUnit;
	local X2ItemTemplate ItemTemplate;
	local XComGameState_Item AutopsyItem;
	local X2CharacterTemplate CharTemplate;
	local XComGameState_Unit Coroner;
	local XComGameState ZoneState;
	local name Group;
	local string Why;
	local int ChancePct, Roll, Count;

	DeadUnit = XComGameState_Unit(EventSource);
	if (DeadUnit == none)
		return ELR_NoInterrupt;

	// Until the corpse is known, the unit is named in the logs by its character template.
	Group = DeadUnit.GetMyTemplateName();

	// Only the regular enemy force (team Alien) leaves zones. The others are logged (but not XCOM's own dead) to see what team a unit created by a mission script really has.
	if (DeadUnit.GetTeam() != eTeam_Alien)
	{
		if (DeadUnit.GetTeam() != eTeam_XCom)
			NoZone(DeadUnit, Group, "team" @ GetEnum(enum'ETeam', DeadUnit.GetTeam()));

		return ELR_NoInterrupt;
	}

	if (DeadUnit.GhostSourceUnit.ObjectID > 0)
	{
		NoZone(DeadUnit, Group, "ghost copy");
		return ELR_NoInterrupt;
	}

	if (class'UT_Trait_BountyHunter'.static.IsSummonedUnit(DeadUnit))
	{
		NoZone(DeadUnit, Group, "summoned unit");
		return ELR_NoInterrupt;
	}

	// Aliens only: ADVENT troops (captains, officers...) and robots (MECs...) have a body but nothing to dissect. The flags are the character template's own.
	CharTemplate = DeadUnit.GetMyTemplate();
	if (CharTemplate == none || !CharTemplate.bIsAlien || CharTemplate.bIsAdvent || CharTemplate.bIsRobotic)
	{
		if (CharTemplate == none)
			NoZone(DeadUnit, Group, "no character template");
		else
			NoZone(DeadUnit, Group, "not an alien (alien" @ string(CharTemplate.bIsAlien) $ ", advent" @ string(CharTemplate.bIsAdvent) $ ", robotic" @ string(CharTemplate.bIsRobotic) $ ")");

		return ELR_NoInterrupt;
	}

	Coroner = FindCoroner(GameState);
	if (Coroner == none)
	{
		NoZone(DeadUnit, Group, "no Coroner alive in the squad");
		return ELR_NoInterrupt;
	}

	// No body, no autopsy. The type is the corpse.
	Group = FindCorpseLeft(DeadUnit, GameState, Why);
	if (Group == '')
	{
		NoZone(DeadUnit, DeadUnit.GetMyTemplateName(), Why);
		return ELR_NoInterrupt;
	}

	// A type autopsied CORONER_MAX_AUTOPSIES times already (counting this mission's autopsies and the zones still lying on the map) gives nothing more.
	Count = CountAutopsies(Group, GameState);
	if (Count >= default.CORONER_MAX_AUTOPSIES)
	{
		NoZone(DeadUnit, Group, "type already autopsied" @ Count @ "time(s)");
		return ELR_NoInterrupt;
	}

	// With a heavy primary weapon the chance is only a share of the base one (50 %: 10 % becomes 5 %).
	ChancePct = default.CORONER_DROP_CHANCE_PCT * GetWeaponFactorPct(Coroner) / 100;
	Roll = `SYNC_RAND_STATIC(100);
	if (Roll >= ChancePct)
	{
		NoZone(DeadUnit, Group, "roll" @ Roll @ ">= chance" @ ChancePct $ "% (weapon share" @ GetWeaponFactorPct(Coroner) $ "%)");
		return ELR_NoInterrupt;
	}

	ItemTemplate = class'X2ItemTemplateManager'.static.GetItemTemplateManager().FindItemTemplate('UT_AutopsyReport');
	if (ItemTemplate == none)
		return ELR_NoInterrupt;

	ZoneState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Coroner autopsy zone");

	AutopsyItem = ItemTemplate.CreateInstanceFromTemplate(ZoneState);
	AutopsyItem.Nickname = string(Group);

	CreateAutopsyDrop(ZoneState, AutopsyItem, DeadUnit);

	// First in the list: the visualizer of the zone must exist (recolored) before the base game's loot fountain asks for it.
	ZoneState.GetContext().PostBuildVisualizationFn.InsertItem(0, PrepareAutopsyMarker);

	`GAMERULES.SubmitGameState(ZoneState);

	`log("UniqueTraits : Coroner -- autopsy zone for" @ Group,, 'UniqueTraits');

	return ELR_NoInterrupt;
}

// Why an enemy that died left no autopsy zone (one log line per refusal, enemy team only).
static final function NoZone(XComGameState_Unit DeadUnit, name Group, string Reason)
{
	`log("UniqueTraits : Coroner -- no zone for" @ Group @ "(" $ DeadUnit.GetMyTemplateName() $ "):" @ Reason,, 'UniqueTraits');
}

// How many autopsies of this type XCOM has, or is about to have: the campaign tally, the Coroner's autopsies of this mission (not in the tally before the mission is over) and the
// zones of this type lying on the map or created in the state being built (not looted yet).
static final function int CountAutopsies(name Group, XComGameState GameState)
{
	local XComGameStateHistory History;
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_Unit SquadUnit;
	local XComGameState_LootDrop Drop;
	local StateObjectReference SquadRef;
	local int Total;

	History = `XCOMHISTORY;
	Total = class'XComGameState_UT_Autopsy'.static.GetCount(Group);

	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ != none)
	{
		foreach XComHQ.Squad(SquadRef)
		{
			SquadUnit = XComGameState_Unit(GameState.GetGameStateForObjectID(SquadRef.ObjectID));
			if (SquadUnit == none)
				SquadUnit = XComGameState_Unit(History.GetGameStateForObjectID(SquadRef.ObjectID));

			if (SquadUnit != none && class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SquadUnit, 'UT_Coroner'))
				Total += int(GetUnitFloat(SquadUnit, AutopsyValueName(Group)));
		}
	}

	foreach History.IterateByClassType(class'XComGameState_LootDrop', Drop)
	{
		if (Drop.HasLoot() && IsAutopsyDropOfGroup(Drop, Group, GameState))
			++Total;
	}

	foreach GameState.IterateByClassType(class'XComGameState_LootDrop', Drop)
	{
		if (Drop.HasLoot() && IsAutopsyDropOfGroup(Drop, Group, GameState) && History.GetGameStateForObjectID(Drop.ObjectID) == none)
			++Total;
	}

	return Total;
}

static final function bool IsAutopsyDropOfGroup(XComGameState_LootDrop Drop, name Group, XComGameState GameState)
{
	local XComGameState_Item ItemState;
	local StateObjectReference ItemRef;

	foreach Drop.LootableItemRefs(ItemRef)
	{
		ItemState = XComGameState_Item(GameState.GetGameStateForObjectID(ItemRef.ObjectID));
		if (ItemState == none)
			ItemState = XComGameState_Item(`XCOMHISTORY.GetGameStateForObjectID(ItemRef.ObjectID));

		if (ItemState != none && UT_AutopsyItemTemplate(ItemState.GetMyTemplate()) != none && name(ItemState.Nickname) == Group)
			return true;
	}

	return false;
}

// The base game's XComGameState_LootDrop.CreateLootDrop WITHOUT its 'LootDropCreated' event. That event's listener (XComGameState_LootDrop.OnLootDropCreated) makes the FIRST soldier with
// the Loot ability within range loot the new drop at once, whoever he is and without asking whether he can take anything: a soldier standing next to the corpse got an empty loot window
// (title = the dead unit's name, no item) for each autopsy zone. The Coroner still loots the zone at the end of a move (the Loot ability's own
// trigger asks the right questions) or by hand. The rest is a copy of CreateLootDrop: the turn listener that makes the zone expire (the base game's 3 turns), the fountain / marker
// visualization.
static final function CreateAutopsyDrop(XComGameState GameState, XComGameState_Item AutopsyItem, XComGameState_Unit DeadUnit)
{
	local XComGameState_LootDrop Drop;
	local Object DropObject;

	Drop = XComGameState_LootDrop(GameState.CreateNewStateObject(class'XComGameState_LootDrop'));

	DropObject = Drop;
	`XEVENTMGR.RegisterForEvent(DropObject, 'PlayerTurnBegun', Drop.OnPlayerTurnBegun, ELD_OnStateSubmitted);

	Drop.LootExpirationTurnsRemaining = class'XComGameState_LootDrop'.const.MaxLootExpirationTurns;
	Drop.TileLocation = PickMarkerTile(DeadUnit);
	Drop.LastLootOwnerName = DeadUnit.GetLootingName();
	Drop.LootSourceID = DeadUnit.ObjectID;
	Drop.LootableItemRefs.AddItem(AutopsyItem.GetReference());

	GameState.GetContext().PostBuildVisualizationFn.AddItem(Drop.VisualizeLootFountain);

	// Our own version of 'LootDropCreated': only a Coroner is looked for, see OnAutopsyDropCreated_Coroner.
	`XEVENTMGR.TriggerEvent('UT_AutopsyDropCreated', Drop, Drop, GameState);
}

// 'UT_AutopsyDropCreated' (ELD_OnStateSubmitted), the Coroner's share of XComGameState_LootDrop.OnLootDropCreated: if a Coroner of the squad, able to act and with the Loot ability, stands
// within the base game's loot range of the new zone (typically next to the corpse), he loots it at once, exactly as the base game does for ordinary loot. Nobody else is considered:
// the base game's handler takes the first soldier in range, whoever he is.
static function EventListenerReturn OnAutopsyDropCreated_Coroner(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateHistory History;
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_LootDrop Drop;
	local XComGameState_Unit Coroner;
	local XComGameState_Ability AbilityState;
	local XComGameStateContext_Ability AbilityContext;
	local StateObjectReference SquadRef, AbilityRef;
	local XComWorldData World;
	local vector TargetPos, SourcePos;

	History = `XCOMHISTORY;
	World = `XWORLD;

	Drop = XComGameState_LootDrop(History.GetGameStateForObjectID(XComGameState_LootDrop(EventData).ObjectID));
	if (Drop == none || !Drop.HasLoot())
		return ELR_NoInterrupt;

	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	TargetPos = World.GetPositionFromTileCoordinates(Drop.TileLocation);

	foreach XComHQ.Squad(SquadRef)
	{
		Coroner = XComGameState_Unit(History.GetGameStateForObjectID(SquadRef.ObjectID));
		if (Coroner == none || !Coroner.IsAbleToAct() || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Coroner, 'UT_Coroner'))
			continue;

		AbilityRef = Coroner.FindAbility('Loot');
		if (AbilityRef.ObjectID <= 0)
			continue;

		SourcePos = World.GetPositionFromTileCoordinates(Coroner.TileLocation);
		if (VSizeSq(TargetPos - SourcePos) >= Square(class'X2Ability_DefaultAbilitySet'.default.LOOT_RANGE))
			continue;

		AbilityState = XComGameState_Ability(History.GetGameStateForObjectID(AbilityRef.ObjectID));
		if (AbilityState == none)
			continue;

		AbilityContext = class'XComGameStateContext_Ability'.static.BuildContextFromAbility(AbilityState, Drop.ObjectID);
		if (AbilityContext.Validate())
			`XCOMGAME.GameRuleset.SubmitGameStateContext(AbilityContext);

		break;
	}

	return ELR_NoInterrupt;
}

// A free tile next to the dead unit (the unit's own tile if there is none).
static final function TTile PickMarkerTile(XComGameState_Unit DeadUnit)
{
	local XComWorldData World;
	local TTile Candidate;
	local int dx, dy;

	World = `XWORLD;

	for (dx = -1; dx <= 1; ++dx)
	{
		for (dy = -1; dy <= 1; ++dy)
		{
			if (dx == 0 && dy == 0)
				continue;

			Candidate = DeadUnit.TileLocation;
			Candidate.X += dx;
			Candidate.Y += dy;
			if (World.IsFloorTileAndValidDestination(Candidate, DeadUnit))
				return Candidate;
		}
	}

	return DeadUnit.TileLocation;
}

static final function bool IsAutopsyDrop(XComGameState_LootDrop Drop)
{
	local XComGameState_Item ItemState;
	local StateObjectReference ItemRef;

	foreach Drop.LootableItemRefs(ItemRef)
	{
		ItemState = XComGameState_Item(`XCOMHISTORY.GetGameStateForObjectID(ItemRef.ObjectID));
		if (ItemState != none && UT_AutopsyItemTemplate(ItemState.GetMyTemplate()) != none)
			return true;
	}

	return false;
}

// PostBuildVisualizationFn of the death: puts a recolored UT_LootDropActor in place as the visualizer of the autopsy zones, exactly as XComGameState_LootDrop.FindOrCreateVisualizer
// would with the base game's actor (which then finds this one and keeps it). A zone created by a save loaded in the middle of a mission gets the ordinary yellow marker.
static function PrepareAutopsyMarker(XComGameState VisualizeGameState)
{
	local XComGameStateHistory History;
	local XComGameState_LootDrop Drop;
	local UT_LootDropActor MyVisualizer;
	local XComTacticalController TacticalController;
	local XGUnit ActiveUnit;
	local XComGameState_Unit SelectedUnit;

	History = `XCOMHISTORY;

	foreach VisualizeGameState.IterateByClassType(class'XComGameState_LootDrop', Drop)
	{
		if (!IsAutopsyDrop(Drop) || History.GetVisualizer(Drop.ObjectID) != none)
			continue;

		MyVisualizer = `XCOMGAME.Spawn(class'UT_LootDropActor', , , `XWORLD.GetPositionFromTileCoordinates(Drop.TileLocation));
		MyVisualizer.SetObjectID(Drop.ObjectID);
		`XCOMVISUALIZATIONMGR.RegisterObserver(MyVisualizer);
		History.SetVisualizer(Drop.ObjectID, MyVisualizer);

		MyVisualizer.InitMaterials();

		TacticalController = XComTacticalController(`XWORLDINFO.GetALocalPlayerController());
		ActiveUnit = TacticalController.GetActiveUnit();
		SelectedUnit = XComGameState_Unit(History.GetGameStateForObjectID(ActiveUnit.ObjectID));
		if (SelectedUnit != none)
			MyVisualizer.UpdateLootMarkersForSelectedUnit(SelectedUnit);
	}
}

// ---------------------------------------------------------------------------------------- the pickup and the tally

// 'ItemLooted' (EventSource = the looter, EventData = the item), ELD_OnStateSubmitted: the autopsy is noted on the Coroner (the type's counter, used for the cap of autopsies per type, and the
// flag that triggers the second damage malus). The item STAYS in his backpack: at the end of the mission the base game moves the backpack of every living (or
// recovered) soldier to the loot recap, like the autopsy items nobody picked up in the zones. OnPostMission credits the campaign tally from those recap lines, and OnAutopsyAcquired deletes
// them when the loot is moved to the HQ inventory. (Taking it out of the backpack in the loot's own state emptied the loot window. It is simply not removed now.)
// Only the Coroner can loot it, see UT_AutopsyItemTemplate.CanBeLootedByUnit.
static function EventListenerReturn OnItemLooted_Coroner(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateHistory History;
	local XComGameState NewGameState;
	local XComGameState_Unit Looter, MutableLooter;
	local XComGameState_Item LootedItem;
	local name ValueName;

	Looter = XComGameState_Unit(EventSource);
	LootedItem = XComGameState_Item(EventData);
	if (Looter == none || LootedItem == none || UT_AutopsyItemTemplate(LootedItem.GetMyTemplate()) == none)
		return ELR_NoInterrupt;

	History = `XCOMHISTORY;
	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Coroner autopsy");

	// The latest committed versions (the event's objects are those of the loot state).
	MutableLooter = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Looter.ObjectID));
	LootedItem = XComGameState_Item(History.GetGameStateForObjectID(LootedItem.ObjectID));

	ValueName = AutopsyValueName(name(LootedItem.Nickname));
	MutableLooter.SetUnitFloatValue(ValueName, GetUnitFloat(MutableLooter, ValueName) + 1, eCleanup_BeginTactical);
	MutableLooter.SetUnitFloatValue('UT_Coroner_Autopsied', 1, eCleanup_BeginTactical);

	`GAMERULES.SubmitGameState(NewGameState);

	`log("UniqueTraits : Coroner --" @ Looter.GetFullName() @ "did the autopsy of" @ LootedItem.Nickname,, 'UniqueTraits');

	return ELR_NoInterrupt;
}

// UT_TraitBase.OnPostMission: the autopsies of the finished mission are added to the campaign tally. The source is what the BASE GAME recovered: the autopsy
// items in XComHQ.LootRecovered, i.e. the ones in the backpack of a living (or recovered) soldier and the ones left in the zones when the mission was swept. One recap line per item, nothing
// is created or merged here. Each item credits its type once (tally.CreditedItemIDs, so a second call does nothing). A Coroner whose body is not recovered takes his autopsies with him.
// The Coroner's per-mission counters are reset in the same transaction.
static function OnPostMission()
{
	local XComGameStateHistory History;
	local XComGameState NewGameState;
	local XComGameState_Unit Unit, MutableUnit;
	local XComGameState_UT_Autopsy AutopsyState;
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_Item ItemState;
	local array<name> Groups, CreditGroups;
	local array<int> CreditCounts, CreditItemIDs, UnitIDs;
	local name Group;
	local int Count, i;
	local bool bHasValues;

	History = `XCOMHISTORY;
	Groups = GetAllGroups();

	// The Coroners who have per-mission counters to reset.
	foreach History.IterateByClassType(class'XComGameState_Unit', Unit)
	{
		if (!Unit.IsSoldier() || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Unit, 'UT_Coroner'))
			continue;

		bHasValues = GetUnitFloat(Unit, 'UT_Coroner_Autopsied') > 0.0;
		foreach Groups(Group)
		{
			if (int(GetUnitFloat(Unit, AutopsyValueName(Group))) > 0)
				bHasValues = true;
		}

		if (bHasValues)
			UnitIDs.AddItem(Unit.ObjectID);
	}

	// The autopsy items of the loot recap that were not credited yet.
	AutopsyState = class'XComGameState_UT_Autopsy'.static.GetState();
	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ != none)
	{
		for (i = 0; i < XComHQ.LootRecovered.Length; ++i)
		{
			ItemState = XComGameState_Item(History.GetGameStateForObjectID(XComHQ.LootRecovered[i].ObjectID));
			if (ItemState == none || ItemState.GetMyTemplateName() != 'UT_AutopsyReport' || ItemState.Nickname == "")
				continue;

			if (AutopsyState != none && AutopsyState.CreditedItemIDs.Find(ItemState.ObjectID) != INDEX_NONE)
				continue;

			CreditGroups.AddItem(name(ItemState.Nickname));
			CreditCounts.AddItem(Max(1, ItemState.Quantity));
			CreditItemIDs.AddItem(ItemState.ObjectID);
		}
	}

	if (UnitIDs.Length == 0 && CreditGroups.Length == 0)
	{
		// Nothing to credit, but the templates may still carry another save's bonuses (a save loaded in the middle of a mission never went through OnCampaignReady).
		class'UT_AutopsyBonuses'.static.ApplyAll();
		return;
	}

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Coroner autopsies");

	if (AutopsyState == none)
		AutopsyState = XComGameState_UT_Autopsy(NewGameState.CreateNewStateObject(class'XComGameState_UT_Autopsy'));
	else
		AutopsyState = XComGameState_UT_Autopsy(NewGameState.ModifyStateObject(class'XComGameState_UT_Autopsy', AutopsyState.ObjectID));

	for (i = 0; i < CreditGroups.Length; ++i)
	{
		AutopsyState.AddAutopsies(CreditGroups[i], CreditCounts[i]);
		AutopsyState.CreditedItemIDs.AddItem(CreditItemIDs[i]);
		`log("UniqueTraits : Coroner -- autopsy of" @ CreditGroups[i] @ "x" $ CreditCounts[i] @ "added to the campaign tally",, 'UniqueTraits');
	}

	// The credited ids only matter while their items are in the recap: forget the others.
	for (i = AutopsyState.CreditedItemIDs.Length - 1; i >= 0; --i)
	{
		if (XComHQ == none || XComHQ.LootRecovered.Find('ObjectID', AutopsyState.CreditedItemIDs[i]) == INDEX_NONE)
			AutopsyState.CreditedItemIDs.Remove(i, 1);
	}

	// The corpses listed in the black market follow the new bonus (price recomputed from the remembered base).
	class'UT_AutopsyBonuses'.static.ReconcilePrices(NewGameState, AutopsyState);

	for (i = 0; i < UnitIDs.Length; ++i)
	{
		MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', UnitIDs[i]));
		foreach Groups(Group)
			MutableUnit.SetUnitFloatValue(AutopsyValueName(Group), 0, eCleanup_BeginTactical);

		MutableUnit.SetUnitFloatValue('UT_Coroner_Autopsied', 0, eCleanup_BeginTactical);
	}

	`GAMERULES.SubmitGameState(NewGameState);

	// The tally changed: the bonuses are recomputed from it.
	class'UT_AutopsyBonuses'.static.ApplyAll();
}

// 'ResearchCompleted' (EventData = the tech, in the pending state. The base game fires it AFTER the tech's ResearchCompletedFn): a "recycling" research (name prefix in
// CORONER_RECYCLE_TECH_PREFIXES) whose cost lists a corpse with an autopsy bonus gives that percentage more of every resource it has just given (rounded to the nearest, a bonus under half a unit gives nothing). The resources it gave are
// read as the increase of the HQ's resource items in the pending state (LWOTC's render techs call AddResource for an amount that only their own config knows).
static function EventListenerReturn OnResearchCompleted_Coroner(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateHistory History;
	local XComGameState_Tech TechState;
	local XComGameState_Item ItemState, PreviousItem;
	local XComGameState_HeadquartersXCom XComHQ;
	local X2ItemTemplate ResourceTemplate;
	local array<name> ResourceNames;
	local array<int> Extras;
	local string TechName, Prefix, BonusText;
	local bool bRecycling;
	local int Pct, Delta, Extra, i, Total;

	TechState = XComGameState_Tech(EventData);
	if (TechState == none)
		return ELR_NoInterrupt;

	TechName = string(TechState.GetMyTemplateName());
	foreach default.CORONER_RECYCLE_TECH_PREFIXES(Prefix)
	{
		if (Left(TechName, Len(Prefix)) ~= Prefix)
			bRecycling = true;
	}

	if (!bRecycling)
		return ELR_NoInterrupt;

	Pct = class'UT_AutopsyBonuses'.static.GetCostBonusPct(TechState.GetMyTemplate().Cost);
	if (Pct <= 0)
		return ELR_NoInterrupt;

	History = `XCOMHISTORY;

	foreach GameState.IterateByClassType(class'XComGameState_Item', ItemState)
	{
		if (ItemState.GetMyTemplate().ItemCat != 'resource')
			continue;

		PreviousItem = XComGameState_Item(History.GetGameStateForObjectID(ItemState.ObjectID));
		if (PreviousItem == none)
			continue;

		Delta = ItemState.Quantity - PreviousItem.Quantity;
		if (Delta <= 0)
			continue;

		Extra = Round(float(Delta) * float(Pct) / 100.0);
		if (Extra > 0)
		{
			ResourceNames.AddItem(ItemState.GetMyTemplateName());
			Extras.AddItem(Extra);
		}
	}

	if (ResourceNames.Length == 0)
		return ELR_NoInterrupt;

	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	for (i = 0; i < ResourceNames.Length; ++i)
	{
		XComHQ.AddResource(GameState, ResourceNames[i], Extras[i]);
		Total += Extras[i];
		`log("UniqueTraits : Coroner -- recycling" @ TechName $ ":" @ ResourceNames[i] @ "+" $ Extras[i] @ "(+" $ Pct $ "%)",, 'UniqueTraits');

		// "+3 Alien Alloy, +1 Elerium Dust": only the bonus, not what the research gives anyway.
		ResourceTemplate = class'X2ItemTemplateManager'.static.GetItemTemplateManager().FindItemTemplate(ResourceNames[i]);
		if (BonusText != "")
			BonusText $= ", ";
		BonusText $= "+" $ Extras[i] @ ((ResourceTemplate != none) ? ResourceTemplate.GetItemFriendlyName() : string(ResourceNames[i]));
	}

	// A banner of the strategy layer (like the completion banners of the base game's projects): the research it comes from and the bonus resources.
	if (`HQPRES != none)
		`HQPRES.NotifyBanner(default.CORONER_RECYCLE_BANNER, class'UIUtilities_Image'.const.EventQueue_Science, TechState.GetDisplayName(), BonusText, eUIState_Good);

	// LWOTC's research report reads the reward from IntelReward: keep it in step with what was really given.
	if (TechState.IntelReward > 0)
		TechState.IntelReward += Total;

	return ELR_NoInterrupt;
}

// UT_TraitBase.OnCampaignReady: a campaign was loaded into the strategy layer or started: the templates get the bonuses of ITS tally (and lose the ones of the campaign before).
static function OnCampaignReady()
{
	class'UT_AutopsyBonuses'.static.ApplyAll();
	class'UT_AutopsyBonuses'.static.ReconcileNow();
}
