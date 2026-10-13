//---------------------------------------------------------------------------------------
//  FILE:   UIScreenListener_UT_MCM.uc
//  PURPOSE: The only link with Mod Config Menu, and an OPTIONAL one: the interfaces of its API are compiled into this mod (Src/ModConfigMenuAPI),
//           so nothing is loaded from MCM. The listener hears every screen, but as soon as the first one has been looked at it only answers for screens of the
//           class that implements MCM_API (MCM's options screen). Without MCM no screen implements it: the listener never answers and the mod is unchanged.
//---------------------------------------------------------------------------------------
class UIScreenListener_UT_MCM extends UIScreenListener;

event OnInit(UIScreen Screen)
{
	local UniqueTraits_MCMScreen MCMScreen;

	if (ScreenClass == none)
	{
		if (MCM_API(Screen) != none)
			ScreenClass = Screen.Class;
		else
			return;
	}

	MCMScreen = new class'UniqueTraits_MCMScreen';
	MCMScreen.OnInit(Screen);
}

defaultproperties
{
	ScreenClass = none;
}
