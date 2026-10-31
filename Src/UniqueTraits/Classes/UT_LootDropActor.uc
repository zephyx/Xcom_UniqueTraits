//---------------------------------------------------------------------------------------
//  FILE:   UT_LootDropActor.uc
//  PURPOSE: The visualizer of a Coroner loot zone (UT_Trait_Coroner): the base game's XComLootDropActor, whose ordinary (yellow) area is recolored. The base game has no other
//           colour than that one and the purple of the Templar's psi loot. The marker material is an instance created for THIS actor in InitMaterials, so only this zone changes.
//           The marker mesh (UI_3D.Waypoint.LootStatus) has two elements, each an instance of a parent with ONE vector parameter, "Color": element 0 Waypoint_LootingBase (the bar
//           between the zone and the counter) and element 1 Waypoint_Looting (the counter). The colour is written into "Color" and into the names of the ini list
//           CORONER_MARKER_PARAMS, and it is written AGAIN after every native SetLootMarker / UpdateLootMarkersForSelectedUnit (overrides below): those natives set the counter's
//           material every time the number changes or the selected unit changes, and reset it. The counter's badge is a baked texture, replaced by the one of
//           CORONER_MARKER_COUNTER_TEXTURE in the "Icon" parameter of each element.
//           The actor is put in place by UT_Trait_Coroner.PrepareAutopsyMarker before the base game's XComGameState_LootDrop.FindOrCreateVisualizer, which then finds it.
//---------------------------------------------------------------------------------------
class UT_LootDropActor extends XComLootDropActor;

// The recolored badge texture (UT_Trait_Coroner.CORONER_MARKER_COUNTER_TEXTURE), loaded once per actor. none = the base game's yellow badge.
var Texture CounterTexture;

function InitMaterials()
{
	local string TexturePath;

	super.InitMaterials();

	TexturePath = class'UT_Trait_Coroner'.default.CORONER_MARKER_COUNTER_TEXTURE;
	if (TexturePath != "")
	{
		CounterTexture = Texture(DynamicLoadObject(TexturePath, class'Texture', true));
		if (CounterTexture == none)
			`log("UniqueTraits [WARN] : Coroner marker: texture" @ TexturePath @ "not found, the counter badge stays yellow",, 'UniqueTraits');
	}

	ApplyTint();
}

// The natives below (re)set the marker's materials: the counter, then the colour of the selected unit. The tint goes back on afterwards.
function SetLootMarker(bool bVisible, int ExpirationCount, const out TTile TileLocation, bool bUsePsiMarker)
{
	super.SetLootMarker(bVisible, ExpirationCount, TileLocation, bUsePsiMarker);

	ApplyTint();
}

function UpdateLootMarkersForSelectedUnit(XComGameState_Unit NewActiveUnit)
{
	super.UpdateLootMarkersForSelectedUnit(NewActiveUnit);

	ApplyTint();
}

function ApplyTint()
{
	local int Scan;
	local MaterialInstanceConstant Instance;
	local LinearColor Tint;
	local name ParamName;

	Tint.R = float(class'UT_Trait_Coroner'.default.CORONER_MARKER_RED) / 100.0;
	Tint.G = float(class'UT_Trait_Coroner'.default.CORONER_MARKER_GREEN) / 100.0;
	Tint.B = float(class'UT_Trait_Coroner'.default.CORONER_MARKER_BLUE) / 100.0;
	Tint.A = 1.0;

	for (Scan = 0; Scan < LootMarkerMesh.GetNumElements(); ++Scan)
	{
		Instance = MaterialInstanceConstant(LootMarkerMesh.GetMaterial(Scan));
		if (Instance == none)
			continue;

		Instance.SetVectorParameterValue('Color', Tint);

		// The counter's material (element 1) has the badge texture in its "Icon" parameter; an element without that parameter ignores it.
		if (CounterTexture != none)
			Instance.SetTextureParameterValue('Icon', CounterTexture);

		foreach class'UT_Trait_Coroner'.default.CORONER_MARKER_PARAMS(ParamName)
			Instance.SetVectorParameterValue(ParamName, Tint);
	}
}
