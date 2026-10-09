//---------------------------------------------------------------------------------------
//  FILE:   UT_MecConversion.uc
//  PURPOSE: A soldier who starts the conversion into a MEC (the optional mods "Playable MEC Troopers", workshop 1452700934, and "Ted MEC
//           Troopers for LWOTC", 3230815381) loses his trait. Not a trait: a rule of the mod.
//           - Cancelling: both mods disable it in their staff slot screen ("Mec Augmentation cannot be cancelled once started", UIFacility_
//             MecAugmentationSlot.ShowDropDown), so the trait is not given back. (Only the destruction of the facility would stop the project.)
//           - Detection: 'StaffUpdated' (fired right after the slot's FillFn created the project, both mods) -> every headquarters project whose
//             CLASS NAME is in MECCONVERSION_PROJECT_CLASS_NAMES and whose focus unit has a trait. Names only: this mod must not reference the other
//             mods' classes (they are optional, a reference would fail the compile), and without them the list matches nothing. Both mods name
//             their project class XComGameState_HeadquartersProjectAugmentSoldier. Scanning every project also cleans a soldier who was already
//             being converted when this was added, at the next staff change.
//           - No new trait is drawn: the converted soldier is not a rookie any more (squaddie at least).
//---------------------------------------------------------------------------------------
class UT_MecConversion extends Object config(UniqueTraits);

var config array<name> MECCONVERSION_PROJECT_CLASS_NAMES;

static function EventListenerReturn OnStaffUpdated_MecConversion(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateHistory History;
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_HeadquartersProject Project;
	local XComGameState_Unit Unit;
	local StateObjectReference ProjectRef;
	local array<StateObjectReference> UnitRefs;
	local int TraitIndex, i;

	if (default.MECCONVERSION_PROJECT_CLASS_NAMES.Length == 0)
		return ELR_NoInterrupt;

	History = `XCOMHISTORY;
	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	foreach XComHQ.Projects(ProjectRef)
	{
		Project = XComGameState_HeadquartersProject(History.GetGameStateForObjectID(ProjectRef.ObjectID));
		if (Project == none || default.MECCONVERSION_PROJECT_CLASS_NAMES.Find(Project.Class.Name) == INDEX_NONE)
			continue;

		Unit = XComGameState_Unit(History.GetGameStateForObjectID(Project.ProjectFocus.ObjectID));
		if (Unit != none && UnitRefs.Find('ObjectID', Unit.ObjectID) == INDEX_NONE
			&& class'X2DownloadableContentInfo_UniqueTraits'.static.GetAssignedTraitIndex(Unit, TraitIndex))
		{
			UnitRefs.AddItem(Unit.GetReference());
		}
	}

	for (i = 0; i < UnitRefs.Length; ++i)
	{
		Unit = XComGameState_Unit(History.GetGameStateForObjectID(UnitRefs[i].ObjectID));
		`log("UniqueTraits : MEC conversion started --" @ Unit.GetFullName() @ "loses his trait",, 'UniqueTraits');
		class'X2DownloadableContentInfo_UniqueTraits'.static.RemoveUnitTrait(UnitRefs[i], "MEC conversion removes the trait");
	}

	return ELR_NoInterrupt;
}
