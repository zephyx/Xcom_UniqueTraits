//---------------------------------------------------------------------------------------
//  FILE:   UT_AIHazardFix.uc
//  PURPOSE: An enemy standing IN a poison / fire / acid cloud cannot leave it: the base game's destination search never offers a hazard tile
//           (its reachable-tiles cache leaves them all out), so an exposed unit boxed in by a cloud stays in the open and shoots. This lets an EXPOSED unit that stands IN a hazard go
//           to cover, even on a hazard tile and through the hazard; anywhere else the base game's behavior is left alone.
//           - The behavior tree node UT_FlankedEscape = Sequence(IsAbilityAvailable-StandardMove, UTFindHazardCover, SelectAbility-StandardMove) is inserted right after DoIfFlankedMove
//             in every selector that lists it (PatchFlankedMoves), so it is only tried when the base game's own flanked move found nothing.
//           - UTFindHazardCover (X2AIBT_UT_Actions, node type UTAction registered in Config/XComAI.ini) tests every condition BEFORE changing anything and picks the destination.
//           - The move itself is UT_XGAIBehavior.MoveToPoint (UseHazardBehaviorClass swaps the behavior class of the character templates): the path through the hazard is built there.
//           No LWOTC class or node is needed: only nodes of the base game's behavior tree (DoIfFlankedMove, IsAbilityAvailable-StandardMove, SelectAbility-StandardMove).
//           The tree is edited at the start of a mission (after LWOTC, if present, applied its own tree changes at the main menu, which would overwrite ours) and idempotent.
//           The console command UTHazardFix on|off switches the tree part in the running game (SetEnabled / Revert).
//           Nothing of it is applied (no tree edit, no behavior class swap) unless the ini option AI_HAZARD_FIX_ENABLED is true (default true, [UniqueTraits.UT_AIHazardFix]).
//---------------------------------------------------------------------------------------
class UT_AIHazardFix extends Object config(UniqueTraits);

// Ini option: the whole fix is applied only when it is true. The default (true) lives in Config/XComUniqueTraits.ini, as for every option of the mod (a missing line reads false).
// Also a checkbox of the Mod Config Menu (Advanced options, flags RB: applies at the next launch): UniqueTraits_MCMOptions.ApplyOverrides writes the player's choice into this default
// before any template is built.
var config bool AI_HAZARD_FIX_ENABLED;

// Set by the console command "UTHazardFix off" (SetEnabled): the fix is then not applied again at the next mission of the session either. Only a runtime flag: it is `config` just
// because the defaults of a class can only be written when the variable is (a non-config one is refused at compile time); nothing ever saves it, so it is back to false (absent from
// the ini) at each launch.
var config bool bManualOff;

// Called once the templates exist (X2DownloadableContentInfo_UniqueTraits.OnPostTemplatesCreated): every character template that uses the base game's XGAIBehavior gets
// UT_XGAIBehavior instead (it only differs in MoveToPoint, and only when UTFindHazardCover asked for it). A template whose class was changed by another mod is left alone.
static function UseHazardBehaviorClass()
{
	local X2CharacterTemplateManager CharacterManager;
	local X2DataTemplate DataTemplate;
	local X2CharacterTemplate CharTemplate;

	if (!default.AI_HAZARD_FIX_ENABLED)
		return;

	CharacterManager = class'X2CharacterTemplateManager'.static.GetCharacterTemplateManager();
	foreach CharacterManager.IterateTemplates(DataTemplate, none)
	{
		CharTemplate = X2CharacterTemplate(DataTemplate);
		if (CharTemplate != none && CharTemplate.BehaviorClass == class'XGAIBehavior')
			CharTemplate.BehaviorClass = class'UT_XGAIBehavior';
	}
}

// Console command side (X2DownloadableContentInfo_UniqueTraits.UTHazardFix): switches the fix on or off in the running game, to compare the two behaviors on the same scene.
static function SetEnabled(bool bEnable)
{
	if (bEnable)
	{
		default.bManualOff = false;
		Apply();
	}
	else
	{
		default.bManualOff = true;
		Revert();
	}

	if (IsApplied())
		class'Helpers'.static.OutputMsg("UniqueTraits AI hazard fix: ON");
	else
		class'Helpers'.static.OutputMsg("UniqueTraits AI hazard fix: OFF");
}

static function bool IsApplied()
{
	local X2AIBTBehaviorTree BehaviorTree;

	BehaviorTree = `BEHAVIORTREEMGR;

	return BehaviorTree != none && BehaviorTree.Behaviors.Find('BehaviorName', 'UT_FlankedEscape') != INDEX_NONE;
}

// Takes our two nodes out of every tree that references them, then deletes them (the exact opposite of Apply), and rebuilds the name table.
static function Revert()
{
	local X2AIBTBehaviorTree BehaviorTree;
	local BehaviorTreeNode Node;
	local int i, ChildIndex, NodeIndex;
	local bool bChanged;
	local array<name> OurNodes;
	local name OurName;

	BehaviorTree = `BEHAVIORTREEMGR;
	if (BehaviorTree == none)
		return;

	OurNodes.AddItem('UT_FlankedEscape');
	OurNodes.AddItem('UTFindHazardCover');

	// First every reference to one of our nodes in the children of the other nodes...
	for (i = 0; i < BehaviorTree.Behaviors.Length; ++i)
	{
		Node = BehaviorTree.Behaviors[i];
		bChanged = false;

		foreach OurNodes(OurName)
		{
			ChildIndex = Node.Child.Find(OurName);
			while (ChildIndex != INDEX_NONE)
			{
				Node.Child.Remove(ChildIndex, 1);
				bChanged = true;
				ChildIndex = Node.Child.Find(OurName);
			}
		}

		if (bChanged)
			BehaviorTree.Behaviors[i] = Node;
	}

	// ... then the nodes themselves.
	foreach OurNodes(OurName)
	{
		NodeIndex = BehaviorTree.Behaviors.Find('BehaviorName', OurName);
		if (NodeIndex != INDEX_NONE)
			BehaviorTree.Behaviors.Remove(NodeIndex, 1);
	}

	BehaviorTree.InitBehaviors();
}

// Called by X2DownloadableContentInfo_UniqueTraits (OnPreMission, OnLoadedSavedGameToTactical) and by SetEnabled.
static function Apply()
{
	local X2AIBTBehaviorTree BehaviorTree;
	local BehaviorTreeNode Node;

	// Disabled in the ini, or switched off by hand for this session (console command).
	if (!default.AI_HAZARD_FIX_ENABLED || default.bManualOff)
		return;

	BehaviorTree = `BEHAVIORTREEMGR;
	if (BehaviorTree == none)
		return;

	// Already done in this session (the table lives as long as the game does).
	if (BehaviorTree.Behaviors.Find('BehaviorName', 'UT_FlankedEscape') != INDEX_NONE)
		return;

	// The leaf: our own action (node type UTAction, registered in Config/XComAI.ini).
	Node.BehaviorName = 'UTFindHazardCover';
	Node.NodeType = 'UTAction';
	BehaviorTree.Behaviors.AddItem(Node);

	// All the conditions (in a hazard, exposed, no reachable cover) are tested by the action itself BEFORE it changes anything, and it resets the destination search only when it has a
	// destination: so for a unit that is not in a hazard the node fails without a trace and the base game's behavior is untouched.
	Node.BehaviorName = 'UT_FlankedEscape';
	Node.NodeType = 'Sequence';
	Node.Child.AddItem('IsAbilityAvailable-StandardMove');
	Node.Child.AddItem('UTFindHazardCover');
	Node.Child.AddItem('SelectAbility-StandardMove');
	BehaviorTree.Behaviors.AddItem(Node);

	// No selector lists DoIfFlankedMove: nothing to patch, our two nodes go away again.
	if (PatchFlankedMoves(BehaviorTree) == 0)
	{
		Revert();
		return;
	}

	// Rebuilds the name table, as LWOTC does after its own changes.
	BehaviorTree.InitBehaviors();
}

// Every selector that tries the base game's flanked move (DoIfFlankedMove: the first action of the red alert trees) gets UT_FlankedEscape right after it: tried only when the
// vanilla flanked move found no tile out of the flank (typically because the cover is in a cloud), before the unit shoots or overwatches while still flanked. Selectors only: a
// node of another type would change meaning.
static final function int PatchFlankedMoves(X2AIBTBehaviorTree BehaviorTree)
{
	local BehaviorTreeNode Node;
	local int i, MoveIndex, Patched;

	for (i = 0; i < BehaviorTree.Behaviors.Length; ++i)
	{
		Node = BehaviorTree.Behaviors[i];
		if (Node.NodeType != 'Selector')
			continue;

		MoveIndex = Node.Child.Find('DoIfFlankedMove');
		if (MoveIndex == INDEX_NONE || Node.Child.Find('UT_FlankedEscape') != INDEX_NONE)
			continue;

		Node.Child.InsertItem(MoveIndex + 1, 'UT_FlankedEscape');
		BehaviorTree.Behaviors[i] = Node;
		++Patched;
	}

	return Patched;
}
