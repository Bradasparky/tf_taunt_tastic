#pragma semicolon 1
#pragma newdecls required

#include <tf2_stocks>

#define TF_CLASS_ANY -1
#define TF_MAX_CLASS_COUNT 10
#define THERMAL_THRUSTER 1179
#define CONFIG "configs/tf_taunt_tastic.cfg"
#define PLUGIN_TAG "[Taunt-tastic]"
#define PLUGIN_VERSION "1.0.0"

public Plugin myinfo =
{
	name = "[TF2] Taunt-tastic",
	author = "Bradasparky",
	description = "Allows players to use any taunt in the game",
	version = PLUGIN_VERSION,
	url = "https://github.com/Bradasparky/tf_taunt_tastic"
};

char szTFClassNameProper[][] =
{
    "Unknown",
    "Scout",
    "Soldier",
    "Pyro",
    "Demoman",
    "Heavy",
    "Engineer",
    "Medic",
    "Sniper",
    "Spy"
};

enum struct Taunt
{
    char szTauntIndex[16];
    char szName[64];
}

int iClassMenu[MAXPLAYERS + 1];
ConVar cvAllowTauntWhileTaunting;
Menu hTauntMenu[TF_MAX_CLASS_COUNT];
ArrayList hClassTaunts[TF_MAX_CLASS_COUNT];
ArrayList hFullTauntList;

public void OnPluginStart() 
{
    hFullTauntList = new ArrayList(sizeof(Taunt));

    RegConsoleCmd("sm_taunt", Command_Taunt, "Usage: sm_taunt | sm_taunt <tauntid|full/partial taunt name> | Usage: <target> <tauntid|full/partial taunt name>");
    RegConsoleCmd("sm_taunts", Command_TauntList, "Lists all available taunts for your class in your console");
    RegConsoleCmd("sm_taunt_list", Command_TauntList, "Lists all available taunts for your class in your console");
    RegAdminCmd("sm_taunt_cache", Command_CacheTaunts, ADMFLAG_ROOT);

    CreateConVar("sm_taunt_tastic_version", PLUGIN_VERSION, "[TF2] Taunt-tastic version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    cvAllowTauntWhileTaunting = CreateConVar("sm_taunt_allow_while_taunting", "0", "Whether players should be able to taunt while already in a taunt", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    
    AutoExecConfig(true, "tf_taunt_tastic");
    LoadTranslations("common.phrases");
}

public void OnMapStart()
{
    ParseConfig();
}

/*
*   Commands
*/

Action Command_TauntList(int iClient, int iArgs)
{
    if (!iClient)
    {
        ReplyToCommand(iClient, "%s This command can only be used in-game.", PLUGIN_TAG);
        return Plugin_Handled;
    }

    int iClass = ConvertClassID(TF2_GetPlayerClass(iClient));
    if (!(0 < iClass < TF_MAX_CLASS_COUNT))
    {
        return Plugin_Handled;
    }
    
    if (!hClassTaunts[iClass].Length)
    {
        ReplyToCommand(iClient, "%s No %s taunts were found on this server", PLUGIN_TAG, szTFClassNameProper[iClass]);
        return Plugin_Handled;
    }
    
    if(GetCmdReplySource() == SM_REPLY_TO_CHAT)
		ReplyToCommand(iClient, "%s %t", "See console for output");
        
    PrintToConsole(iClient, "\nTaunt list for %s:", szTFClassNameProper[iClass]);

    int iLength = hClassTaunts[iClass].Length;
    for (int i; i < iLength; i++)
    {
        Taunt tTaunt;
        hClassTaunts[iClass].GetArray(i, tTaunt, sizeof(tTaunt));
        PrintToConsole(iClient, "- (%s) %s", tTaunt.szTauntIndex, tTaunt.szName);
    }

    PrintToConsole(iClient, "Use !taunt <tauntid | full/partial name> to use a taunt");
    return Plugin_Handled;
}

Action Command_CacheTaunts(int iClient, int iArgs)
{
    ParseConfig();
    ReplyToCommand(iClient, "%s Successfully cached %s!", PLUGIN_TAG, CONFIG);
    return Plugin_Handled;
}

Action Command_Taunt(int iClient, int iArgs)
{
    if (!iClient)
    {
        ReplyToCommand(iClient, "%s This command can only be used in-game.", PLUGIN_TAG);
        return Plugin_Handled;
    }

    if (!IsPlayerAlive(iClient))
    {
        ReplyToCommand(iClient, "%s You must be alive to use this command.", PLUGIN_TAG);
        return Plugin_Handled;
    }

    int iClass = ConvertClassID(TF2_GetPlayerClass(iClient));
    if (!(0 < iClass < TF_MAX_CLASS_COUNT))
        return Plugin_Handled;

    if (iArgs < 1)
    {
        hTauntMenu[iClass].Display(iClient, MENU_TIME_FOREVER);
        return Plugin_Handled;
    }
    
    char szPattern[32], szTauntID[128];
    if (iArgs > 1)
    {
        GetCmdArg(1, szPattern, sizeof(szPattern));
        GetCmdArg(2, szTauntID, sizeof(szTauntID));
    }
    else
        GetCmdArg(1, szTauntID, sizeof(szTauntID));
    
    Taunt tTaunt;
    bool bIsInputNumeric = true;
    for (int i; i < sizeof(szTauntID) && szTauntID[i] != '\0'; i++)
    {
        if (!IsCharNumeric(szTauntID[i]))
        {
            bIsInputNumeric = false;
            break;
        }
    }
        
    if (iArgs == 1)
    {
        if (bIsInputNumeric)
        {
            if (!FindClassTauntByIndex(szTauntID, iClass, tTaunt))
            {
                ReplyToCommand(iClient, "%s The taunt index \"%s\" does not exist for %s or is not defined on this server.", PLUGIN_TAG, szTauntID, szTFClassNameProper[iClass]);
                return Plugin_Handled;
            }
        }
        else
        {
            if (!FindClassTauntByName(szTauntID, iClass, tTaunt))
            {
                ReplyToCommand(iClient, "%s A %s taunt containing \"%s\" does not exist or is not defined on this server.", PLUGIN_TAG, szTFClassNameProper[iClass], szTauntID);
                return Plugin_Handled;
            }
        }

        if (!cvAllowTauntWhileTaunting.BoolValue && TF2_IsPlayerInCondition(iClient, TFCond_Taunting))
        {
            ReplyToCommand(iClient, "%s You cannot taunt while already in a taunt.", PLUGIN_TAG);
            return Plugin_Handled;
        }

        ForceTaunt(iClient, StringToInt(tTaunt.szTauntIndex));
    }
    else
    {
        if (!CheckCommandAccess(iClient, "tf_taunt_tastic", ADMFLAG_CHEATS))
        {
            ReplyToCommand(iClient, "%s You do not have access to this command.", PLUGIN_TAG);
            return Plugin_Handled;
        }
        
        if (bIsInputNumeric)
        {
            if (!FindTauntByIndex(szTauntID, tTaunt))
            {
                ReplyToCommand(iClient, "%s The taunt index \"%s\" is not defined on this server.", PLUGIN_TAG, szTauntID, szTFClassNameProper[iClass]);
                return Plugin_Handled;
            }
        }
        else
        {
            if (!FindTauntByName(szTauntID, tTaunt))
            {
                ReplyToCommand(iClient, "%s A %s taunt containing \"%s\" is not defined on this server.", PLUGIN_TAG, szTFClassNameProper[iClass], szTauntID);
                return Plugin_Handled;
            }
        }

        char szTargetName[MAX_TARGET_LENGTH];
        int iTargetList[MAXPLAYERS];
        int iTargetCount;
        bool bTargetNameIsMultilingual;

        if ((iTargetCount = ProcessTargetString(
            szPattern,
            iClient,
            iTargetList,
            MAXPLAYERS,
            COMMAND_FILTER_ALIVE | (StrEqual(szPattern, "@me") ? COMMAND_FILTER_NO_IMMUNITY : 0),
            szTargetName,
            sizeof(szTargetName),
            bTargetNameIsMultilingual)) <= 0)
        {
            ReplyToTargetError(iClient, iTargetCount);
            return Plugin_Handled;
        }
        
        for (int i; i < iTargetCount; i++)
            ForceTaunt(iTargetList[i], StringToInt(tTaunt.szTauntIndex));
        
        if (bTargetNameIsMultilingual)
            ShowActivity2(iClient, "%s ", "Forced the taunt %s on %t", tTaunt.szName, szTargetName);
        else
            ShowActivity2(iClient, "%s ", "Forced the taunt %s on %s", tTaunt.szName, szTargetName);
    }
    
    return Plugin_Handled;
}

/*
*   Config
*/

void ParseConfig()
{
    hFullTauntList.Clear();
    for (int i; i < sizeof(hClassTaunts); i++)
    {
        if (hClassTaunts[i] != INVALID_HANDLE)
            delete hClassTaunts[i];
        hClassTaunts[i] = new ArrayList(sizeof(Taunt));
    }

    char szPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, szPath, sizeof(szPath), CONFIG);
    KeyValues kv = new KeyValues("taunts");
    if (!FileExists(szPath))
        SetFailState("%s :: Error: Failed to find required config file %s", PLUGIN_TAG, CONFIG);

    if (!kv.ImportFromFile(szPath))
        SetFailState("%s :: Error: Failed to import keyvalues from %s", PLUGIN_TAG, CONFIG);

    char szRootKey[32];
    kv.GetSectionName(szRootKey, sizeof(szRootKey));
    if (!StrEqual(szRootKey, "taunts"))
        SetFailState("%s :: Error: Failed to find root key named \"taunts\"", PLUGIN_TAG);
    
    if (!kv.GotoFirstSubKey())
    {
        LogMessage("%s :: Warning: No taunts were found in %s", PLUGIN_TAG, CONFIG);
        delete kv;
        return;
    }

    do
    {
        char szClass[9];
        kv.GetSectionName(szClass, sizeof(szClass));
        int iClass = ConvertClassID(TF2_GetClass(szClass));
        if (StrEqual(szClass, "any"))
            iClass = TF_CLASS_ANY;
        else if (!iClass)
            SetFailState("%s :: Error: Failed to parse config %s. Invalid class name found \"%s\"", PLUGIN_TAG, CONFIG, szClass);
        
        if (!kv.GotoFirstSubKey(false))
            continue;
        
        do
        {
            Taunt tTaunt;
            if (!kv.GetSectionName(tTaunt.szTauntIndex, sizeof(tTaunt.szTauntIndex)))
                SetFailState("%s :: Error: Failed to parse config %s. Error when trying to get section name", PLUGIN_TAG, CONFIG);
            
            kv.GetString(NULL_STRING, tTaunt.szName, sizeof(tTaunt.szName));
            if (tTaunt.szName[0] == '\0')
                SetFailState("%s :: Error: Failed to parse config %s. Found null value for key \"%s\"", PLUGIN_TAG, CONFIG);

            if (iClass == TF_CLASS_ANY)
            {
                for (int i; i < TF_MAX_CLASS_COUNT; i++)
                    hClassTaunts[i].PushArray(tTaunt, sizeof(tTaunt));
            }
            else
                hClassTaunts[iClass].PushArray(tTaunt, sizeof(tTaunt));

            hFullTauntList.PushArray(tTaunt, sizeof(tTaunt));
        }
        while(kv.GotoNextKey(false));

        kv.GoBack();
    }
    while (kv.GotoNextKey());

    delete kv;

    // Sort list in ascending order
    for (int i; i < TF_MAX_CLASS_COUNT; i++)
        hClassTaunts[i].SortCustom(SortClassTaunts);
    
    CreateTauntMenu();
}

int SortClassTaunts(int Index1, int Index2, ArrayList hTaunts, Handle hndl)
{
    Taunt tTaunt1, tTaunt2;
    int iTauntIndex1, iTauntIndex2;
    hTaunts.GetArray(Index1, tTaunt1, sizeof(tTaunt1));
    hTaunts.GetArray(Index2, tTaunt2, sizeof(tTaunt2));
    iTauntIndex1 = StringToInt(tTaunt1.szTauntIndex);
    iTauntIndex2 = StringToInt(tTaunt2.szTauntIndex);
    return iTauntIndex1 < iTauntIndex2 ? -1 : view_as<int>(iTauntIndex1 > iTauntIndex2);
}

/*
*   Menu
*/

void CreateTauntMenu()
{
    for (int i; i < TF_MAX_CLASS_COUNT; i++)
    {
        if (hTauntMenu[i] != INVALID_HANDLE)
            delete hTauntMenu[i];
        hTauntMenu[i] = new Menu(MenuHandler_OnTauntSelected, MenuAction_Display);

        if (!hClassTaunts[i].Length)
            continue;

        hTauntMenu[i].SetTitle("%s Taunts\n \nYou can also type !taunt <tauntid | full/partial name>\n ", szTFClassNameProper[i]);
        
        int iLength = hClassTaunts[i].Length;
        for (int j; j < iLength; j++)
        {
            char szDisplay[64];
            Taunt tTaunt;
            hClassTaunts[i].GetArray(j, tTaunt, sizeof(tTaunt));
            FormatEx(szDisplay, sizeof(szDisplay), "(%s) %s", tTaunt.szTauntIndex, tTaunt.szName);
            hTauntMenu[i].AddItem(tTaunt.szTauntIndex, szDisplay);
        }
    }
}

void MenuHandler_OnTauntSelected(Menu hMenu, MenuAction eAction, int iClient, int iParam2)
{
    switch (eAction)
    {
        case MenuAction_Display: iClassMenu[iClient] = ConvertClassID(TF2_GetPlayerClass(iClient));
        case MenuAction_Select:
        {
            if (!IsPlayerAlive(iClient))
            {
                PrintToChat(iClient, "%s You must be alive to taunt.", PLUGIN_TAG);
                return;
            }
            
            char szTauntIndex[16];
            hMenu.GetItem(iParam2, szTauntIndex, sizeof(szTauntIndex)); 
            
            int iClass = ConvertClassID(TF2_GetPlayerClass(iClient));
            if (iClassMenu[iClient] != iClass)
            {
                hTauntMenu[iClass].Display(iClient, MENU_TIME_FOREVER);
                ReplyToCommand(iClient, "%s You selected an option on the wrong class's menu. Opening the menu for %s", PLUGIN_TAG, szTFClassNameProper[iClass]);
                return;
            }

            if (!cvAllowTauntWhileTaunting.BoolValue && TF2_IsPlayerInCondition(iClient, TFCond_Taunting))
                ReplyToCommand(iClient, "%s You cannot taunt while already taunting.", PLUGIN_TAG);
            else
                ForceTaunt(iClient, StringToInt(szTauntIndex));

            hMenu.DisplayAt(iClient, iParam2 / 7 * 7, MENU_TIME_FOREVER);
        }
        case MenuAction_Cancel: iClassMenu[iClient] = -1;
    }
}

/*
*   Utility
*/

void ForceTaunt(int iClient, int iTauntTauntIndex)
{
    int iActiveWeapon = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
    char szClassname[40];
    GetEdictClassname(iActiveWeapon, szClassname, sizeof(szClassname));
    
    // Thermal Thruster is the only weapon which needs a different classname to work
    if (GetEntProp(iActiveWeapon, Prop_Send, "m_iItemDefinitionIndex") == THERMAL_THRUSTER)
        strcopy(szClassname, sizeof(szClassname), "tf_weapon_shotgun_pyro");
    else
        GetEdictClassname(iActiveWeapon, szClassname, sizeof(szClassname));

    int iWeapon = CreateEntityByName(szClassname);
    VScript_StopTaunt(iClient);
    TF2_RemoveCondition(iClient, TFCond_Taunting);
    DispatchSpawn(iWeapon);
    SetEntProp(iWeapon, Prop_Send, "m_iItemDefinitionIndex", iTauntTauntIndex);
    SetEntProp(iWeapon, Prop_Send, "m_bInitialized", true);
    SetEntProp(iWeapon, Prop_Data, "m_bForcePurgeFixedupStrings", true);
    SetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon", iWeapon);
    SetEntProp(iClient, Prop_Send, "m_iFOV", 0);
    VScript_ForceDefaultTaunt(iClient);
    SetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon", iActiveWeapon);
    AcceptEntityInput(iWeapon, "Kill");
}

void VScript_StopTaunt(int iClient)
{
    SetVariantString("self.StopTaunt(true)");
    AcceptEntityInput(iClient, "RunScriptCode");
}

void VScript_ForceDefaultTaunt(int iClient)
{
    SetVariantString("self.HandleTauntCommand(0)");
    AcceptEntityInput(iClient, "RunScriptCode");
}

int ConvertClassID(TFClassType eTFClass)
{
    switch (eTFClass)
    {
        case TFClass_Scout: return 1;
        case TFClass_Soldier: return 2;
        case TFClass_Pyro: return 3;
        case TFClass_DemoMan: return 4;
        case TFClass_Heavy: return 5;
        case TFClass_Engineer: return 6;
        case TFClass_Medic: return 7;
        case TFClass_Sniper: return 8;
        case TFClass_Spy: return 9;
        default: return 0;
    }
}

bool FindTauntByIndex(char[] szIndex, Taunt tTaunt)
{
    int iLength = hFullTauntList.Length;
    for (int i; i < iLength; i++)
    {
        Taunt tBuffer;
        hFullTauntList.GetArray(i, tBuffer, sizeof(tBuffer));
        if (StrEqual(tBuffer.szTauntIndex, szIndex))
        {
            tTaunt = tBuffer;
            return true;
        }
    }

    return false;
}

bool FindTauntByName(char[] szName, Taunt tTaunt)
{
    int iLength = hFullTauntList.Length;
    for (int i; i < iLength; i++)
    {
        Taunt tBuffer;
        hFullTauntList.GetArray(i, tBuffer, sizeof(tBuffer));
        if (StrContains(tBuffer.szName, szName, false) != -1)
        {
            tTaunt = tBuffer;
            return true;
        }
    }

    return false;
}

bool FindClassTauntByIndex(char[] szIndex, int iClass, Taunt tTaunt)
{
    int iLength = hClassTaunts[iClass].Length;
    for (int i; i < iLength; i++)
    {
        Taunt tBuffer;
        hClassTaunts[iClass].GetArray(i, tBuffer, sizeof(tBuffer));
        
        if (StrEqual(tBuffer.szTauntIndex, szIndex))
        {
            tTaunt = tBuffer;
            return true;
        }
    }

    return false;
}

bool FindClassTauntByName(char[] szName, int iClass, Taunt tTaunt)
{
    int iLength = hClassTaunts[iClass].Length;
    for (int i; i < iLength; i++)
    {
        Taunt tBuffer;
        hClassTaunts[iClass].GetArray(i, tBuffer, sizeof(tBuffer));
        if (StrContains(tBuffer.szName, szName, false) != -1)
        {
            tTaunt = tBuffer;
            return true;
        }
    }

    return false;
}