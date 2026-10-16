//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_SelfReinforcement.uc
//  PURPOSE: Self-reinforcement. Two sides, both on a covert operation that has NOT started yet, kept up to date every time a staff slot is
//           filled or emptied ('StaffUpdated', ELD_OnStateSubmitted, own change container: SyncCovertAction, idempotent, driven by who is in the slots):
//           - duration: if at least one holder of the trait is in a SOLDIER slot, the operation lasts SELFREINFORCEMENT_DURATION_PCT % longer (HoursToComplete),
//             ONCE whatever the number of holders. The hours added are remembered on the holder that "owns" the increase
//             (UnitValues UT_SR_ActionID = the operation, UT_SR_Hours), so they are taken back exactly when nobody holds the trait there anymore; if the owner
//             leaves and another holder stays, the mark moves to that one. The game changes nothing after the launch, so a started operation is left alone.
//           - stat gain: the soldier slots of "training" operations carry a reward Reward_StatBoost<Stat> whose item (StatBoost_<Stat>) stores the rolled
//             StatBoosts; GiveStatBoostReward / OnStatBoostAcquired (X2StrategyElement_XpackRewards / X2Item_XpackResources) read them when the operation completes. A holder
//             placed in such a slot multiplies those StatBoosts by SELFREINFORCEMENT_STAT_MULT (2 = doubled) right away, so the preview of the operation screen
//             already shows the doubled value; if he leaves the slot they are divided back (the multiplier used is remembered on him: UT_SR_ItemID = the item,
//             UT_SR_ItemMult). The rank-up reward is not a stat and is left alone.
//           A holder who gets or loses the trait while he is already in an unlaunched operation is only taken into account at the next staff change of that operation.
//---------------------------------------------------------------------------------------
class UT_Trait_SelfReinforcement extends UT_TraitBase config(UniqueTraits);

var config int SELFREINFORCEMENT_DURATION_PCT;
var config int SELFREINFORCEMENT_STAT_MULT;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(SelfReinforcement());

	return Templates;
}

// Self-reinforcement: a bare passive, everything happens in OnStaffUpdated_SelfReinforcement.
static function X2AbilityTemplate SelfReinforcement()
{
	return PurePassive('UT_SelfReinforcement', "img:///UILibrary_PerkIcons.UIPerk_standard", true);
}

// 'StaffUpdated' (a staff slot was filled or emptied): resyncs the covert operation that slot belongs to, if it is one and not launched yet.
static function EventListenerReturn OnStaffUpdated_SelfReinforcement(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_StaffSlot SlotState;
	local XComGameState_CovertAction Action;

	SlotState = XComGameState_StaffSlot(EventData);
	if (SlotState == none || SlotState.CovertAction.ObjectID == 0)
		return ELR_NoInterrupt;

	Action = XComGameState_CovertAction(`XCOMHISTORY.GetGameStateForObjectID(SlotState.CovertAction.ObjectID));
	if (Action == none || Action.bStarted)
		return ELR_NoInterrupt;

	SyncCovertAction(Action);

	return ELR_NoInterrupt;
}

// The pending object of the change container, which is created the first time something must change (nothing is submitted when nothing changed).
static final function XComGameState_BaseObject GetMutableObject(out XComGameState NewGameState, class<XComGameState_BaseObject> ObjectClass, int ObjectID)
{
	local XComGameState_BaseObject Pending;

	if (NewGameState == none)
		NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Self-reinforcement");

	Pending = NewGameState.GetGameStateForObjectID(ObjectID);
	if (Pending == none)
		Pending = NewGameState.ModifyStateObject(ObjectClass, ObjectID);

	return Pending;
}

// Writes the two marks of a pair (ID + amount) on a unit; ID 0 clears the pair.
static final function SetMarks(out XComGameState NewGameState, int UnitID, name IDName, name AmountName, int MarkID, int Amount)
{
	local XComGameState_Unit MutableUnit;

	MutableUnit = XComGameState_Unit(GetMutableObject(NewGameState, class'XComGameState_Unit', UnitID));
	MutableUnit.SetUnitFloatValue(IDName, float(MarkID), eCleanup_Never);
	MutableUnit.SetUnitFloatValue(AmountName, float(Amount), eCleanup_Never);
}

// The soldier that carries the mark IDName == MarkID, or none.
static final function XComGameState_Unit FindMarkedSoldier(array<XComGameState_Unit> Soldiers, name IDName, int MarkID)
{
	local XComGameState_Unit Soldier;

	foreach Soldiers(Soldier)
	{
		if (int(GetUnitFloat(Soldier, IDName, 0)) == MarkID)
			return Soldier;
	}

	return none;
}

// Brings the duration and the stat rewards of a not yet launched covert operation in line with who is in its soldier slots. Idempotent.
static final function SyncCovertAction(XComGameState_CovertAction Action)
{
	local XComGameStateHistory History;
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Unit> Soldiers;
	local XComGameState_Unit Holder, FirstHolder, DurationOwner, ItemDoubler;
	local XComGameState_StaffSlot SlotState;
	local XComGameState_Reward RewardState;
	local XComGameState_Item ItemState, MutableItem;
	local XComGameState_CovertAction MutableAction;
	local XComGameState NewGameState;
	local array<int> HolderIDs;
	local int i, j, Mult, AppliedMult, ItemID, Hours;

	History = `XCOMHISTORY;
	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return;

	Soldiers = XComHQ.GetSoldiers();
	Mult = Max(1, default.SELFREINFORCEMENT_STAT_MULT);
	DurationOwner = FindMarkedSoldier(Soldiers, 'UT_SR_ActionID', Action.ObjectID);

	for (i = 0; i < Action.StaffSlots.Length; i++)
	{
		// The holder of the trait in this slot, if any.
		Holder = none;
		SlotState = Action.GetStaffSlot(i);
		if (SlotState != none && SlotState.IsSoldierSlot() && SlotState.IsSlotFilled())
		{
			Holder = SlotState.GetAssignedStaff();
			if (Holder != none && !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Holder, 'UT_SelfReinforcement'))
				Holder = none;
		}
		if (Holder != none)
		{
			HolderIDs.AddItem(Holder.ObjectID);
			if (FirstHolder == none)
				FirstHolder = Holder;
		}

		// The stat reward of this slot (an item that stores the rolled boosts), if there is one.
		if (Action.StaffSlots[i].RewardRef.ObjectID == 0)
			continue;
		RewardState = XComGameState_Reward(History.GetGameStateForObjectID(Action.StaffSlots[i].RewardRef.ObjectID));
		if (RewardState == none)
			continue;
		ItemState = XComGameState_Item(History.GetGameStateForObjectID(RewardState.RewardObjectReference.ObjectID));
		if (ItemState == none || ItemState.StatBoosts.Length == 0)
			continue;

		ItemID = ItemState.ObjectID;
		ItemDoubler = FindMarkedSoldier(Soldiers, 'UT_SR_ItemID', ItemID);

		if (Holder != none && ItemDoubler == none)
		{
			// A holder takes the slot: double the boosts.
			if (Mult > 1)
			{
				MutableItem = XComGameState_Item(GetMutableObject(NewGameState, class'XComGameState_Item', ItemID));
				for (j = 0; j < MutableItem.StatBoosts.Length; j++)
					MutableItem.StatBoosts[j].Boost = MutableItem.StatBoosts[j].Boost * Mult;

				SetMarks(NewGameState, Holder.ObjectID, 'UT_SR_ItemID', 'UT_SR_ItemMult', ItemID, Mult);
			}
		}
		else if (Holder == none && ItemDoubler != none)
		{
			// The holder left the slot: give the boosts back, with the multiplier that was really applied.
			AppliedMult = Max(1, int(GetUnitFloat(ItemDoubler, 'UT_SR_ItemMult', 1)));
			if (AppliedMult > 1)
			{
				MutableItem = XComGameState_Item(GetMutableObject(NewGameState, class'XComGameState_Item', ItemID));
				for (j = 0; j < MutableItem.StatBoosts.Length; j++)
					MutableItem.StatBoosts[j].Boost = MutableItem.StatBoosts[j].Boost / AppliedMult;
			}

			SetMarks(NewGameState, ItemDoubler.ObjectID, 'UT_SR_ItemID', 'UT_SR_ItemMult', 0, 0);
		}
		else if (Holder != none && ItemDoubler != none && Holder.ObjectID != ItemDoubler.ObjectID)
		{
			// Still doubled, by a unit that is no longer there: the new holder takes the mark over.
			AppliedMult = int(GetUnitFloat(ItemDoubler, 'UT_SR_ItemMult', 1));
			SetMarks(NewGameState, ItemDoubler.ObjectID, 'UT_SR_ItemID', 'UT_SR_ItemMult', 0, 0);
			SetMarks(NewGameState, Holder.ObjectID, 'UT_SR_ItemID', 'UT_SR_ItemMult', ItemID, AppliedMult);
		}
	}

	// Duration: once for the whole operation, owned by one holder.
	if (HolderIDs.Length > 0 && DurationOwner == none)
	{
		Hours = Round(Action.HoursToComplete * default.SELFREINFORCEMENT_DURATION_PCT / 100.0);
		if (Hours > 0)
		{
			MutableAction = XComGameState_CovertAction(GetMutableObject(NewGameState, class'XComGameState_CovertAction', Action.ObjectID));
			MutableAction.HoursToComplete += Hours;
			SetMarks(NewGameState, FirstHolder.ObjectID, 'UT_SR_ActionID', 'UT_SR_Hours', Action.ObjectID, Hours);
		}
	}
	else if (HolderIDs.Length > 0 && HolderIDs.Find(DurationOwner.ObjectID) == INDEX_NONE)
	{
		// The owner of the increase is gone but another holder stays: the increase stays, its mark moves.
		Hours = int(GetUnitFloat(DurationOwner, 'UT_SR_Hours', 0));
		SetMarks(NewGameState, DurationOwner.ObjectID, 'UT_SR_ActionID', 'UT_SR_Hours', 0, 0);
		SetMarks(NewGameState, FirstHolder.ObjectID, 'UT_SR_ActionID', 'UT_SR_Hours', Action.ObjectID, Hours);
	}
	else if (HolderIDs.Length == 0 && DurationOwner != none)
	{
		// Nobody holds the trait in this operation anymore: take the hours back.
		Hours = int(GetUnitFloat(DurationOwner, 'UT_SR_Hours', 0));
		MutableAction = XComGameState_CovertAction(GetMutableObject(NewGameState, class'XComGameState_CovertAction', Action.ObjectID));
		MutableAction.HoursToComplete = FMax(0.0, MutableAction.HoursToComplete - Hours);
		SetMarks(NewGameState, DurationOwner.ObjectID, 'UT_SR_ActionID', 'UT_SR_Hours', 0, 0);
	}

	if (NewGameState != none)
		`GAMERULES.SubmitGameState(NewGameState);
}
