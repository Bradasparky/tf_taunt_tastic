#include <sdkhooks>
#include <tf2_stocks>
#include "stocksoup/textparse.inc"

#pragma semicolon 1
#pragma newdecls required

#define TF_MAX_CLASS_COUNT 10
#define THERMAL_THRUSTER 1179
#define PATTACH_ABSORIGIN_FOLLLOW 1
#define ITEM_SCHEMA "scripts/items/items_game.txt"

#define PLUGIN_TAG "[Taunt-tastic]"
#define PLUGIN_VERSION "2.0.0"

public Plugin myinfo =
{
	name = "[TF2] Taunt-tastic",
	author = "Bradasparky",
	description = "Allows players to use any taunt in the game",
	version = PLUGIN_VERSION,
	url = "https://github.com/Bradasparky/tf_taunt_tastic"
};

char g_sTFClassNameProper[][] =
{
    "Unknown",
    "Scout",
    "Sniper",
    "Soldier",
    "Demoman",
    "Medic",
    "Heavy",
    "Pyro",
    "Spy",
    "Engineer"
};

enum struct Taunt
{
    char sID[8];
    char sName[MAX_NAME_LENGTH];
}

enum struct Unusual
{
    char sID[8];
    char sName[MAX_NAME_LENGTH];
    char sEffect[MAX_NAME_LENGTH];

    void Reset()
    {
        this.sID = "";
        this.sEffect = "";
        Format(this.sName, sizeof(this.sName), "%t", "None");
    }
}

bool g_bUnusualTauntsEnabled;
bool g_bAllowTauntWhileTaunting;
float g_flTauntWhileTauntingCooldown;

ConVar cvUnusualTauntsEnabled;
ConVar cvAllowTauntWhileTaunting;
ConVar cvTauntWhileTauntingCooldown;

int g_iTriggerParticle = -1;
int g_iClassMenu[MAXPLAYERS + 1];
int g_iLastSlot[MAXPLAYERS + 1] = { -1, ... };
int g_iLastWeapon[MAXPLAYERS + 1] = { -1, ... };
int g_iTauntWeapon[MAXPLAYERS + 1] = { -1, ... };
float g_flLastTauntTime[MAXPLAYERS + 1];
bool g_bUnusualMenuOpen[MAXPLAYERS + 1];
bool g_bUsedUnusualTaunt[MAXPLAYERS + 1];
Unusual g_tCurrUnusual[MAXPLAYERS + 1];
Menu g_hUnusualMenu;
Menu g_hTauntMenu[TF_MAX_CLASS_COUNT];
ArrayList g_hClassTaunts[TF_MAX_CLASS_COUNT];
ArrayList g_hTauntList;
ArrayList g_hUnusualList;

public void OnPluginStart() 
{
    LoadTranslations("common.phrases");
    LoadTranslations("tf_taunt_tastic.phrases");

    g_hTauntList = new ArrayList(sizeof(Taunt));
    g_hUnusualList = new ArrayList(sizeof(Unusual));
    
    g_hUnusualMenu = new Menu(MenuHandler_OnUnusualSelected, MenuAction_Display);
    for (int i = 1; i < TF_MAX_CLASS_COUNT; i++)
        g_hTauntMenu[i] = new Menu(MenuHandler_OnTauntSelected, MenuAction_Display);
    
    for (int i = MaxClients; i; i--)
        if (IsClientConnected(i))
            OnClientConnected(i);

    RegConsoleCmd("sm_taunt", Command_Taunt, "Usage: sm_taunt [tauntid|full/partial taunt name]");
    RegAdminCmd("sm_forcetaunt", Command_ForceTaunt, ADMFLAG_ROOT, "sm_forcetaunt <#userid|target> <tauntid|full/partial taunt name>");
    RegConsoleCmd("sm_taunts", Command_TauntList, "Lists all available taunts for your class in your console");
    RegConsoleCmd("sm_taunt_list", Command_TauntList, "Lists all available taunts for your class in your console");
    RegAdminCmd("sm_utaunt", Command_TauntUnusual, ADMFLAG_ROOT, "Usage: sm_utaunt [unusualid|full/partial unusual name] (For testing purposes only! Some particles can't be removed.)");
    RegAdminCmd("sm_utaunts", Command_TauntUnusualList, ADMFLAG_ROOT, "Lists all available taunt unusuals in your console");
    RegAdminCmd("sm_utaunt_list", Command_TauntUnusualList, ADMFLAG_ROOT, "Lists all available taunt unusuals in your console");

    CreateConVar("sm_taunt_tastic_version", PLUGIN_VERSION, "Plugin version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    cvUnusualTauntsEnabled = CreateConVar("sm_utaunt_enabled", "0", "Whether taunt unusuals should be selectable (For testing purposes only! Some particles can't be removed.)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    cvAllowTauntWhileTaunting = CreateConVar("sm_taunt_allow_while_taunting", "0", "Whether players should be able to taunt while already in a taunt (Prone to invisible taunt props)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    cvTauntWhileTauntingCooldown = CreateConVar("sm_taunt_while_taunting_cooldown", "2", "How long until another taunt can be performed. (Very low values can lag or crash the server if spammed)", FCVAR_NOTIFY, true, 0.5);
    
    cvUnusualTauntsEnabled.AddChangeHook(OnConVarChanged);
    cvAllowTauntWhileTaunting.AddChangeHook(OnConVarChanged);
    cvTauntWhileTauntingCooldown.AddChangeHook(OnConVarChanged);

    HookEvent("post_inventory_application", OnPlayerResupply, EventHookMode_Pre);

    AutoExecConfig(true, "tf_taunt_tastic");
    ParseItemSchema();   
}

public void OnPluginEnd()
{
    for (int i = MaxClients; i; i--)
    {
        if (IsClientInGame(i) && EntRefToEntIndex(g_iTauntWeapon[i]) != -1)
        {
            TF2_RemoveCondition(i, TFCond_Taunting);
            OnTauntEnd(i, true);
        }
    }
}

public void OnConfigsExecuted()
{
    g_bUnusualTauntsEnabled = cvUnusualTauntsEnabled.BoolValue;
    g_bAllowTauntWhileTaunting = cvAllowTauntWhileTaunting.BoolValue;
    g_flTauntWhileTauntingCooldown = cvTauntWhileTauntingCooldown.FloatValue;
}

void OnConVarChanged(ConVar hConVar, const char[] sOldValue, const char[] sNewValue)
{
    if (StrEqual(sOldValue, sNewValue))
        return;
    
    if (hConVar == cvUnusualTauntsEnabled)
    {
        if (g_bUnusualTauntsEnabled == hConVar.BoolValue)
            return;

        g_bUnusualTauntsEnabled = hConVar.BoolValue;

        if (!g_bUnusualTauntsEnabled)
        {
            g_hUnusualMenu.Cancel();

            for (int i = MaxClients; i; i--)
                g_tCurrUnusual[i].Reset();
        }
    }
    else if (hConVar == cvAllowTauntWhileTaunting)
    {
        if (g_bAllowTauntWhileTaunting == hConVar.BoolValue)
            return;
        
        g_bAllowTauntWhileTaunting = hConVar.BoolValue;
        CreateTauntMenu(true);
    }
    else if (hConVar == cvTauntWhileTauntingCooldown)
    {
        g_flTauntWhileTauntingCooldown = cvTauntWhileTauntingCooldown.FloatValue;
        if (g_bAllowTauntWhileTaunting)   
            CreateTauntMenu(true);
    }
}

public void OnClientConnected(int iClient)
{
    g_iClassMenu[iClient] = 0;
    g_bUnusualMenuOpen[iClient] = false;
    g_bUsedUnusualTaunt[iClient] = false;
    g_tCurrUnusual[iClient].Reset();
    g_iLastSlot[iClient] = -1;
    g_iLastWeapon[iClient] = -1;
    g_iTauntWeapon[iClient] = -1;
}

/*
*   Commands
*/

Action Command_Taunt(int iClient, int iArgs)
{
    if (!iClient)
    {
        TT_ReplyToCommand(iClient, "%t", "Command is in-game only");
        return Plugin_Handled;
    }

    int iClass = TF2_GetPlayerClass(iClient);
    if (!(0 < iClass < TF_MAX_CLASS_COUNT))
        return Plugin_Handled;

    if (iArgs == 0)
    {
        if (g_hClassTaunts[iClass].Length > 0)
            g_hTauntMenu[iClass].Display(iClient, MENU_TIME_FOREVER);
        else
            TT_ReplyToCommand(iClient, "%t", "No class taunts were found", g_sTFClassNameProper[iClass]);
        return Plugin_Handled;
    }

    if (!IsPlayerAlive(iClient))
    {
        TT_ReplyToCommand(iClient, "%t", "You must be alive to taunt");
        return Plugin_Handled;
    }

    char sPattern[MAX_NAME_LENGTH];
    GetCmdArg(1, sPattern, sizeof(sPattern));

    Taunt tTaunt;
    bool bIsInputNumeric = true;
    for (int i; i < sizeof(sPattern) && sPattern[i] != '\0'; i++)
    {
        if (!IsCharNumeric(sPattern[i]))
        {
            bIsInputNumeric = false;
            break;
        }
    }
    
    if (bIsInputNumeric)
    {
        if (!FindClassTauntByIndex(sPattern, iClass, tTaunt))
        {
            TT_ReplyToCommand(iClient, "%t", "Class taunt not found by index", g_sTFClassNameProper[iClass], sPattern);
            return Plugin_Handled;
        }
    }
    else
    {
        if (!FindClassTauntByName(sPattern, iClass, tTaunt))
        {
            TT_ReplyToCommand(iClient, "%t", "Class taunt not found by name", g_sTFClassNameProper[iClass], sPattern);
            return Plugin_Handled;
        }
    }
    
    if (TF2_IsPlayerInCondition(iClient, TFCond_Taunting))
    {
        if (g_bAllowTauntWhileTaunting)
        {
            if (g_flLastTauntTime[iClient] > GetGameTime())
                return Plugin_Handled;
        }
        else
            return Plugin_Handled;
    }
    
    ForceTaunt(iClient, StringToInt(tTaunt.sID));

    return Plugin_Handled;
}

Action Command_ForceTaunt(int iClient, int iArgs)
{
    if (iArgs < 2)
    {
        TT_ReplyToCommand(iClient, "Usage: sm_forcetaunt <#userid|target> <tauntid|full/partial taunt name>");
        return Plugin_Handled;
    }

    char sPattern[MAX_NAME_LENGTH];
    GetCmdArg(1, sPattern, sizeof(sPattern));
    

    bool bTargetNameIsMultilingual;
    char sTargetName[MAX_TARGET_LENGTH];
    int iTargetList[MAXPLAYERS], iTargetCount;
    if ((iTargetCount = ProcessTargetString(
        sPattern,
        iClient,
        iTargetList,
        MAXPLAYERS,
        COMMAND_FILTER_ALIVE | (StrEqual(sPattern, "@me") ? COMMAND_FILTER_NO_IMMUNITY : 0),
        sTargetName,
        sizeof(sTargetName),
        bTargetNameIsMultilingual)) <= 0)
    {
        ReplyToTargetError(iClient, iTargetCount);
        return Plugin_Handled;
    }

    GetCmdArg(2, sPattern, sizeof(sPattern));

    Taunt tTaunt;
    bool bIsInputNumeric = true;
    for (int i; i < sizeof(sPattern) && sPattern[i] != '\0'; i++)
    {
        if (!IsCharNumeric(sPattern[i]))
        {
            bIsInputNumeric = false;
            break;
        }
    }
    
    if (bIsInputNumeric)
    {
        if (!FindTauntByIndex(sPattern, tTaunt))
        {
            TT_ReplyToCommand(iClient, "%t", "Taunt not found by index", sPattern);
            return Plugin_Handled;
        }
    }
    else
    {
        if (!FindTauntByName(sPattern, tTaunt))
        {
            TT_ReplyToCommand(iClient, "%t", "Taunt not found by name", sPattern);
            return Plugin_Handled;
        }
    }
    
    for (int i; i < iTargetCount; i++)
    {
        int iClass = TF2_GetPlayerClass(iTargetList[i]);
        if (bIsInputNumeric)
        {
            if (!FindClassTauntByIndex(sPattern, iClass, tTaunt))
                continue;
        }
        else
        {
            if (!FindClassTauntByName(sPattern, iClass, tTaunt))
                continue;
        }
        
        ForceTaunt(iTargetList[i], StringToInt(tTaunt.sID));
    }

    if (bTargetNameIsMultilingual)
        ShowActivity2(iClient, PLUGIN_TAG ... " ", "%t", "Force taunt", tTaunt.sName, sTargetName);
    else
        ShowActivity2(iClient, PLUGIN_TAG ... " ", "%t", "Force taunt", tTaunt.sName, "_s", sTargetName);
    
    return Plugin_Handled;
}

Action Command_TauntUnusual(int iClient, int iArgs)
{
    if (!g_bUnusualTauntsEnabled)
    {
        TT_ReplyToCommand(iClient, "%t", "Unusual taunts are disabled");
        return Plugin_Handled;
    }

    if (!iClient)
    {
        TT_ReplyToCommand(iClient, "%t", "Command is in-game only");
        return Plugin_Handled;
    }

    if (iArgs < 1)
    {
        if (g_hUnusualList.Length > 0)
            g_hUnusualMenu.Display(iClient, MENU_TIME_FOREVER);
        else
            TT_ReplyToCommand(iClient, "%t", "No taunt unusuals were found");
        return Plugin_Handled;
    }
    
    char sPattern[MAX_NAME_LENGTH];
    GetCmdArg(1, sPattern, sizeof(sPattern));
    
    Unusual tUnusual;
    bool bIsInputNumeric = true;
    for (int i; i < sizeof(sPattern) && sPattern[i] != '\0'; i++)
    {
        if (!IsCharNumeric(sPattern[i]))
        {
            bIsInputNumeric = false;
            break;
        }
    }
    
    if (bIsInputNumeric)
    {
        if (!FindUnusualByIndex(sPattern, tUnusual))
        {
            TT_ReplyToCommand(iClient, "%t", "Unusual not found by index", sPattern);
            return Plugin_Handled;
        }
    }
    else
    {
        if (!FindUnusualByName(sPattern, tUnusual))
        {
            TT_ReplyToCommand(iClient, "%t", "Unusual not found by name", sPattern);
            return Plugin_Handled;
        }
    }

    g_tCurrUnusual[iClient] = tUnusual;
    TT_ReplyToCommand(iClient, "%t", "Set unusual", tUnusual.sName);
    
    return Plugin_Handled;
}

Action Command_TauntList(int iClient, int iArgs)
{
    if (!iClient)
    {
        TT_ReplyToCommand(iClient, "%t", "Command is in-game only");
        return Plugin_Handled;
    }

    int iClass = TF2_GetPlayerClass(iClient);
    if (!(0 < iClass < TF_MAX_CLASS_COUNT))
        return Plugin_Handled;

    if (!g_hClassTaunts[iClass].Length)
    {
        TT_ReplyToCommand(iClient, "%t", "No class taunts found", g_sTFClassNameProper[iClass]);
        return Plugin_Handled;
    }
    
    if (GetCmdReplySource() == SM_REPLY_TO_CHAT)
		TT_ReplyToCommand(iClient, "%t",  "See console for output.");
        
    PrintToConsole(iClient, "\n%t:", "Taunt list", g_sTFClassNameProper[iClass]);

    int iLength = g_hClassTaunts[iClass].Length;
    for (int i; i < iLength; i++)
    {
        Taunt tTaunt;
        g_hClassTaunts[iClass].GetArray(i, tTaunt, sizeof(tTaunt));
        PrintToConsole(iClient, "- (%s) %s", tTaunt.sID, tTaunt.sName);
    }

    PrintToConsole(iClient, "%t !taunt [tauntid | full/partial name]", "Use");
    return Plugin_Handled;
}

Action Command_TauntUnusualList(int iClient, int iArgs)
{
    if (!iClient)
    {
        TT_ReplyToCommand(iClient, "%t", "Command is in-game only");
        return Plugin_Handled;
    }

    if (!g_hUnusualList.Length)
    {
        TT_ReplyToCommand(iClient, "%t", "No taunt unusuals were found");
        return Plugin_Handled;
    }
    
    if (GetCmdReplySource() == SM_REPLY_TO_CHAT)
		TT_ReplyToCommand(iClient, "%t", "See console for output.");
        
    PrintToConsole(iClient, "\n%t:", "Unusual list");

    int iLength = g_hUnusualList.Length;
    for (int i; i < iLength; i++)
    {
        Unusual tUnusual;
        g_hUnusualList.GetArray(i, tUnusual, sizeof(tUnusual));
        PrintToConsole(iClient, "- %s", tUnusual.sName);
    }

    PrintToConsole(iClient, "%t !utaunt [full/partial name]", "Use");
    return Plugin_Handled;
}

/*
*   Taunt Data
*/

StringMap g_hTranslations;

void OnKeyValue(const char[] sKey, const char[] sVal)
{
    g_hTranslations.SetString(sKey, sVal);
}

bool ParseTauntData()
{
    char sDataPath[64];
    BuildPath(Path_SM, sDataPath, sizeof(sDataPath), "data/tf_taunt_tastic/taunt_data.txt");
    PrintToServer(sDataPath);
    if (!FileExists(sDataPath, true))
        return false;

    KeyValues kv = new KeyValues("taunt_data");
    if (!kv.ImportFromFile(sDataPath))
    {
        LogMessage("Failed to import from '%s'");
        return false;
    }
    
    if (FileExists(ITEM_SCHEMA))
    {
        if (kv.GetNum("last_modified") != GetFileTime(ITEM_SCHEMA, FileTime_LastChange))
        {
            LogMessage("Taunt data is out of date!");
            delete kv;
            return false;
        }
    }
    else
        LogMessage("Failed to validate taunt data against the item schema!");

    // Check that these keys exist before reading their data
    
    if (!kv.JumpToKey("taunts"))
    {
        delete kv;
        return false;
    }
    kv.GoBack();

    if (!kv.JumpToKey("unusuals"))
    {
        delete kv;
        return false;
    }
    kv.GoBack();
    
    kv.JumpToKey("taunts");
    kv.GotoFirstSubKey();

    Taunt tItem;

    do
    {
        kv.GetSectionName(tItem.sID, sizeof(tItem.sID));
        kv.GetString("name", tItem.sName, sizeof(tItem.sName));
        int iClassBits = kv.GetNum("classbits");
        for (int i = 1; i < TF_MAX_CLASS_COUNT; i++)
            if (iClassBits & (1 << i))
                g_hClassTaunts[i].PushArray(tItem, sizeof(tItem));

        g_hTauntList.PushArray(tItem, sizeof(tItem));
    }
    while(kv.GotoNextKey());

    kv.Rewind();
    kv.JumpToKey("unusuals");
    kv.GotoFirstSubKey();

    Unusual tUnusual;

    do
    {
        kv.GetSectionName(tUnusual.sID, sizeof(tUnusual.sID));
        kv.GetString("name", tUnusual.sName, sizeof(tUnusual.sName));
        kv.GetString("effect", tUnusual.sEffect, sizeof(tUnusual.sEffect));
        g_hUnusualList.PushArray(tUnusual, sizeof(tUnusual));
    }
    while(kv.GotoNextKey());

    delete kv;
    
    LogMessage("Successfully loaded taunt data!");

    return true;
}

void ParseItemSchema()
{
    g_hTauntList.Clear();
    g_hUnusualList.Clear();
    for (int i = 1; i < sizeof(g_hClassTaunts); i++)
    {
        if (g_hClassTaunts[i] != INVALID_HANDLE)
            delete g_hClassTaunts[i];
        g_hClassTaunts[i] = new ArrayList(sizeof(Taunt));
    }

    if (ParseTauntData())
    {
        CreateTauntMenu();
        return;
    }
    
    static const char sTranslationFile[24] = "resource/tf_english.txt";
    File hFile = OpenFile(sTranslationFile, "r", true);
    if (!hFile)
        SetFailState("Failed to open '%s'.", sTranslationFile);
    g_hTranslations = new StringMap();
    
    LogMessage("Parsing %s...", sTranslationFile);

    TranslationFileParser hParser;
    hParser.OnKeyValue = OnKeyValue;
    TranslationFileParseResult eResult = hParser.ParseOpenUTF16File(hFile);
    
    if (eResult != TranslationFileParse_OK)
    {
        char sError[64];
        hParser.GetErrorString(eResult, sError, sizeof(sError));
        SetFailState("Failed to parse '%s'. %s.", sTranslationFile, sError);
    }
    
    // Store item schema data in taunt_data.txt as we parse
    char sPath[PLATFORM_MAX_PATH] = "data/tf_taunt_tastic/";
    BuildPath(Path_SM, sPath, sizeof(sPath), sPath);

    if (!DirExists(sPath, true))
        CreateDirectory(sPath, _, true);
    
    StrCat(sPath, sizeof(sPath), "taunt_data.txt");

    KeyValues hTauntData = new KeyValues("taunt_data");
    hTauntData.SetNum("last_modified", GetFileTime(ITEM_SCHEMA, FileTime_LastChange));
    hTauntData.JumpToKey("taunts", true);

    char sSection[64], sVal[64];

    if (!FileExists(ITEM_SCHEMA))
        SetFailState("File does not exist '%s'", ITEM_SCHEMA);
    
    LogMessage("Parsing %s...", ITEM_SCHEMA);
    KeyValues kv = new KeyValues("items");

    if (!kv.ImportFromFile(ITEM_SCHEMA))
        SetFailState("Failed to import '%s'.", ITEM_SCHEMA);
	
	if (!kv.JumpToKey("items"))
		SetFailState("Failed to find key 'items' in '%s'", ITEM_SCHEMA);
	
	if (!kv.GotoFirstSubKey(false))
		SetFailState("Failed to find keys within 'items' in '%s'", ITEM_SCHEMA);

    Taunt tItem;
    
	do
	{
		kv.GetString("prefab", sVal, sizeof(sVal));
		if (StrContains(sVal, "taunt") == -1)
			continue;
        
        kv.GetSectionName(tItem.sID, sizeof(tItem.sID));   
        kv.GetString("item_name", tItem.sName, sizeof(tItem.sName));
        strcopy(tItem.sName, sizeof(tItem.sName), tItem.sName[1]);

		if (!kv.JumpToKey("used_by_classes") || !kv.GotoFirstSubKey(false))
			continue;
        
        if (!g_hTranslations.GetString(tItem.sName, tItem.sName, sizeof(tItem.sName)))
            SetFailState("Failed to find translation for '%s'", tItem.sName);

        if (StrContains(tItem.sName, "Taunt: ") == 0)
            strcopy(tItem.sName, sizeof(tItem.sName), tItem.sName[7]);

        hTauntData.JumpToKey(tItem.sID, true);
        hTauntData.SetString("name", tItem.sName);

        int iClassNum, iClassBits;
        
		do
		{
			if (kv.GetNum(NULL_STRING, 0) == 1)
			{
				kv.GetSectionName(sSection, sizeof(sSection));
                iClassNum = TF2_GetClass(sSection);
                iClassBits += (1 << iClassNum);
                g_hClassTaunts[iClassNum].PushArray(tItem, sizeof(tItem));
			}

            g_hTauntList.PushArray(tItem, sizeof(tItem));
		}
		while (kv.GotoNextKey(false));
        kv.GoBack();
        kv.GoBack();

        hTauntData.SetNum("classbits", iClassBits);
        hTauntData.GoBack();
	}
	while (kv.GotoNextKey());
    
    LogMessage("Saved taunt data at '%s'", sPath);
    hTauntData.Rewind();

    kv.Rewind();

    if (!kv.JumpToKey("attribute_controlled_attached_particles"))
		SetFailState("Failed to find key 'attribute_controlled_attached_particles' in '%s'", ITEM_SCHEMA);

    if (!kv.JumpToKey("taunt_unusual_effects"))
        SetFailState("Failed to find key 'taunt_unusual_effects' in '%s'", ITEM_SCHEMA);
	
	if (!kv.GotoFirstSubKey())
		SetFailState("Failed to find keys within 'taunt_unusual_effects' in '%s'", ITEM_SCHEMA);

    hTauntData.JumpToKey("unusuals", true);

    Unusual tUnusual;
    
    do
    {
        kv.GetSectionName(tUnusual.sID, sizeof(tUnusual.sID));
        kv.GetString("system", tUnusual.sEffect, sizeof(tUnusual.sEffect));

        tUnusual.sName = "Attrib_Particle";
        StrCat(tUnusual.sName, sizeof(tUnusual.sName), tUnusual.sID);
        if (!g_hTranslations.GetString(tUnusual.sName, tUnusual.sName, sizeof(tUnusual.sName)))
            SetFailState("Failed to find translation for '%s'");

        if (StrContains(tUnusual.sEffect, "teamcolor_red") != -1)
            StrCat(tUnusual.sName, sizeof(tUnusual.sName), " (Red)");
        else if (StrContains(tUnusual.sEffect, "teamcolor_blu") != -1)
            StrCat(tUnusual.sName, sizeof(tUnusual.sName), " (Blue)");

        g_hUnusualList.PushArray(tUnusual, sizeof(tUnusual));

        hTauntData.JumpToKey(tUnusual.sID, true);
        hTauntData.SetString("name", tUnusual.sName);
        hTauntData.SetString("effect", tUnusual.sEffect);
        hTauntData.GoBack();
    }
    while(kv.GotoNextKey());
    
    hTauntData.Rewind();
    hTauntData.ExportToFile(sPath);

    delete kv;
    delete hTauntData;
    delete g_hTranslations;
    
    CreateTauntMenu();
}

/*
*   Hooks
*/

void OnPlayerResupply(Event hEvent, const char[] sName, bool bDontBroadcast)
{
    // Clean up the taunt
    int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
    if (EntRefToEntIndex(g_iTauntWeapon[iClient]) == -1)
        return;

    TF2_RemoveCondition(iClient, TFCond_Taunting);
    RemoveEntity(g_iTauntWeapon[iClient]);
    RequestFrame(NextFrame_ClearTauntParticle, GetClientSerial(iClient));
    g_iLastSlot[iClient] = -1;
    g_iLastWeapon[iClient] = -1;
    g_iTauntWeapon[iClient] = -1;
}

void OnPostThinkPost(int iClient)
{
    if (TF2_IsPlayerInCondition(iClient, TFCond_Taunting) || g_iTauntWeapon[iClient] == -1)
        return;
    
    SDKUnhook(iClient, SDKHook_PostThinkPost, OnPostThinkPost);
    OnTauntEnd(iClient);
    g_iLastSlot[iClient] = -1;
    g_iLastWeapon[iClient] = -1;
    g_iTauntWeapon[iClient] = -1;
}

/*
*   Menu
*/

void CreateTauntMenu(bool bTauntOnly = false)
{
    int iLastClassMenu[MAXPLAYERS + 1];
    for (int i = MaxClients; i; i--)
    {
        iLastClassMenu[i] = g_iClassMenu[i];
        if (iLastClassMenu[i] > 0)
            g_hTauntMenu[iLastClassMenu[i]].Cancel();
    }

    for (int i = 1; i < TF_MAX_CLASS_COUNT; i++)
    {
        g_hTauntMenu[i].RemoveAllItems();

        if (!g_hClassTaunts[i].Length)
            continue;

        char sTitle[256];
        FormatEx(sTitle, sizeof(sTitle), "%s Taunts\n \n%t !taunt <tauntid|full/partial name>", g_sTFClassNameProper[i], "You can also type");

        if (g_bAllowTauntWhileTaunting)
            Format(sTitle, sizeof(sTitle), "%s\n%t\n ", sTitle, "Taunt while taunting enabled", g_flTauntWhileTauntingCooldown);
        else
            Format(sTitle, sizeof(sTitle), "%s\n%t\n ", sTitle, "Taunt while taunting disabled");
        
        g_hTauntMenu[i].SetTitle(sTitle);
        
        int iLength = g_hClassTaunts[i].Length;
        for (int j; j < iLength; j++)
        {
            char sDisplay[64];
            Taunt tTaunt;
            g_hClassTaunts[i].GetArray(j, tTaunt, sizeof(tTaunt));
            FormatEx(sDisplay, sizeof(sDisplay), "(%s) %s", tTaunt.sID, tTaunt.sName);
            g_hTauntMenu[i].AddItem(tTaunt.sID, sDisplay);
        }
    }

    for (int i = MaxClients; i; i--)
    {
        if (IsClientInGame(i) && iLastClassMenu[i] > 0 && g_hClassTaunts[iLastClassMenu[i]].Length > 0)
        {
            int iClass = TF2_GetPlayerClass(i);
            g_hTauntMenu[iClass].Display(i, MENU_TIME_FOREVER);
            TT_PrintToChat(i, "%t", "Updated the taunt menu description");
        }
    }

    if (bTauntOnly)
        return;
    
    g_hUnusualMenu.RemoveAllItems();
    
    int iLength = g_hUnusualList.Length;
    if (!iLength)
        return;
    
    char sNone[32];
    FormatEx(sNone, sizeof(sNone), "(%t)", "None");
    g_hUnusualMenu.AddItem("None", sNone);
    
    Unusual tUnusual;
    for (int i; i < iLength; i++)
    {
        g_hUnusualList.GetArray(i, tUnusual, sizeof(tUnusual));
        Format(tUnusual.sName, sizeof(tUnusual.sName), "(%s) %s", tUnusual.sID, tUnusual.sName);
        g_hUnusualMenu.AddItem(tUnusual.sEffect, tUnusual.sName);
    }
}

void NextFrame_DrawTauntMenu(int iClient)
{
    if (g_iClassMenu[iClient])
        g_hTauntMenu[g_iClassMenu[iClient]].Display(iClient, MENU_TIME_FOREVER);
}

void MenuHandler_OnTauntSelected(Menu hMenu, MenuAction eAction, int iClient, int iItem)
{
    switch (eAction)
    {
        case MenuAction_Display: 
        {
            int iClass = TF2_GetPlayerClass(iClient);
            if (!g_iClassMenu[iClient])
            {
                g_iClassMenu[iClient] = iClass;
                return;
            }
            
            if (g_iClassMenu[iClient] != iClass)
            {
                g_iClassMenu[iClient] = iClass;
                RequestFrame(NextFrame_DrawTauntMenu, iClient);
                TT_PrintToChat(iClient, "%t", "Redraw taunt menu", g_sTFClassNameProper[iClass]);
            }
        }
        case MenuAction_Select:
        {
            if (!g_iClassMenu[iClient])
                return;
            
            if (!IsPlayerAlive(iClient))
            {
                hMenu.DisplayAt(iClient, iItem / 7 * 7, MENU_TIME_FOREVER);
                TT_PrintToChat(iClient, "%t", "You must be alive to taunt");
                return;
            }
            
            int iClass = TF2_GetPlayerClass(iClient);
            if (g_iClassMenu[iClient] != iClass)
            {
                g_iClassMenu[iClient] = iClass;
                g_hTauntMenu[iClass].Display(iClient, MENU_TIME_FOREVER);
                TT_PrintToChat(iClient, "%t", "Redraw taunt menu", g_sTFClassNameProper[iClass]);
                return;
            }

            bool bTaunt = true;
            if (TF2_IsPlayerInCondition(iClient, TFCond_Taunting))
            {
                if (g_bAllowTauntWhileTaunting)
                {
                    if (g_flLastTauntTime[iClient] > GetGameTime())
                        bTaunt = false;
                }
                else
                    bTaunt = false;
            }

            char sID[8];
            hMenu.GetItem(iItem, sID, sizeof(sID)); 
            if (bTaunt)
                ForceTaunt(iClient, StringToInt(sID));

            hMenu.DisplayAt(iClient, iItem / 7 * 7, MENU_TIME_FOREVER);
        }
        case MenuAction_Cancel: g_iClassMenu[iClient] = 0;
    }
}

void MenuHandler_OnUnusualSelected(Menu hMenu, MenuAction eAction, int iClient, int iItem)
{
    switch (eAction)
    {
        case MenuAction_Display: 
        {
            Unusual tUnusual;
            hMenu.GetItem(iItem, tUnusual.sEffect, sizeof(tUnusual.sEffect), _, tUnusual.sName, sizeof(tUnusual.sName));

            char sTitle[256];
            FormatEx(sTitle, sizeof(sTitle), 
                "Taunt Unusuals\n \n%t !utaunt <unusualid|full/partial name>\nUnusual: %s\n ", "You can also type", g_tCurrUnusual[iClient].sName);
            g_hUnusualMenu.SetTitle(sTitle);
            g_bUnusualMenuOpen[iClient] = true;
        }
        case MenuAction_Select:
        {
            Unusual tUnusual;
            hMenu.GetItem(iItem, tUnusual.sEffect, sizeof(tUnusual.sEffect), _, tUnusual.sName, sizeof(tUnusual.sName));

            if (iItem == 0)
                tUnusual.Reset();
            
            PrintToServer("Setting Effect %s", tUnusual.sEffect);
            g_tCurrUnusual[iClient] = tUnusual;
            hMenu.DisplayAt(iClient, iItem / 7 * 7, MENU_TIME_FOREVER);
        }
        case MenuAction_Cancel: g_bUnusualMenuOpen[iClient] = false;
    }
}

/*
*   Utility
*/

void ForceTaunt(int iClient, int iTauntIndex)
{
    VScript_StopTaunt(iClient);
    TF2_RemoveCondition(iClient, TFCond_Taunting);

    int iTaunt = EntRefToEntIndex(g_iTauntWeapon[iClient]);
    if (iTaunt != -1)
    {
        if (g_iLastWeapon[iClient] == -1)
            SetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon", -1);
        else if (EntRefToEntIndex(g_iLastWeapon[iClient]) == -1)
            SwitchToNextBestWeapon(iClient);
        else
            SetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon", EntRefToEntIndex(g_iLastWeapon[iClient]));

        if (g_bUsedUnusualTaunt[iClient])
        {
            g_bUsedUnusualTaunt[iClient] = false;
            RequestFrame(NextFrame_ClearTauntParticle, GetClientSerial(iClient));
        }
        
        RemoveEntity(g_iTauntWeapon[iClient]);
    }

    char sClassname[64];
    int iActiveWeapon = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
    if (iActiveWeapon == -1)
    {
        switch (TF2_GetPlayerClass(iClient))
        {
            case TFClass_Scout: sClassname = "tf_weapon_bat";
            case TFClass_Soldier: sClassname = "tf_weapon_shovel";
            case TFClass_Pyro: sClassname = "tf_weapon_fireaxe";
            case TFClass_DemoMan: sClassname = "tf_weapon_bottle";
            case TFClass_Heavy: sClassname = "tf_weapon_fists";
            case TFClass_Engineer: sClassname = "tf_weapon_wrench";
            case TFClass_Medic: sClassname = "tf_weapon_bonesaw";
            case TFClass_Sniper: sClassname = "tf_weapon_club";
            case TFClass_Spy: sClassname = "tf_weapon_knife";
            default: sClassname = "tf_weapon_bat";
        }

        g_iLastSlot[iClient] = -1;
        g_iLastWeapon[iClient] = -1;
    }
    else
    {
        // Thermal Thruster is the only weapon which needs a different classname to work
        if (GetEntProp(iActiveWeapon, Prop_Send, "m_iItemDefinitionIndex") == THERMAL_THRUSTER)
            strcopy(sClassname, sizeof(sClassname), "tf_weapon_shotgun_pyro");
        else
            GetEntityClassname(iActiveWeapon, sClassname, sizeof(sClassname));

        g_iLastSlot[iClient] = GetSlotForWeapon(iClient, iActiveWeapon);
        g_iLastWeapon[iClient] = EntIndexToEntRef(iActiveWeapon);
    }

    iTaunt = CreateEntityByName(sClassname);

    DispatchSpawn(iTaunt);
    SetEntProp(iTaunt, Prop_Send, "m_bValidatedAttachedEntity", 1);
    SetEntProp(iTaunt, Prop_Send, "m_bInitialized", true);
    SetEntProp(iTaunt, Prop_Data, "m_bForcePurgeFixedupStrings", true);
    SetEntProp(iTaunt, Prop_Send, "m_iItemDefinitionIndex", iTauntIndex);
    SetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon", iTaunt);
    EquipPlayerWeapon(iClient, iTaunt);
    SetEntProp(iClient, Prop_Send, "m_iFOV", 0);
    VScript_ForceDefaultTaunt(iClient);
    
    // If we're not taunting that means IsAllowedToTaunt() failed inside HandleTauntCommand
    if (!TF2_IsPlayerInCondition(iClient, TFCond_Taunting))
    {
        SetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon", EntRefToEntIndex(g_iLastWeapon[iClient]));
        RemoveEntity(iTaunt);

        g_iLastSlot[iClient] = -1;
        g_iLastWeapon[iClient] = -1;
        return;
    }

    g_iTauntWeapon[iClient] = EntIndexToEntRef(iTaunt);
    g_flLastTauntTime[iClient] = GetGameTime() + g_flTauntWhileTauntingCooldown;

    if (g_tCurrUnusual[iClient].sEffect[0] != '\0')
    {
        g_bUsedUnusualTaunt[iClient] = true;

        DataPack hData;
        CreateDataTimer(0.0, Timer_AttachTauntParticle, hData, TIMER_FLAG_NO_MAPCHANGE);
        hData.WriteCell(GetClientSerial(iClient));
        hData.WriteString(g_tCurrUnusual[iClient].sEffect);
    }

    SDKHook(iClient, SDKHook_PostThinkPost, OnPostThinkPost);
}

void OnTauntEnd(int iClient, bool bClearParticleImmediately = false)
{
    // Player was ref posing
    if (g_iLastWeapon[iClient] == -1)
        SetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon", -1);
    else
    {   
        int iLastWeapon = EntRefToEntIndex(g_iLastWeapon[iClient]);
        if (iLastWeapon == -1)
            SwitchToNextBestWeapon(iClient);
        else
            SetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon", iLastWeapon);
    }

    int iTauntWeapon = EntRefToEntIndex(g_iTauntWeapon[iClient]);
    if (iTauntWeapon != -1)
        RemoveEntity(iTauntWeapon);

    if (g_bUsedUnusualTaunt[iClient])
    {
        g_bUsedUnusualTaunt[iClient] = false;
        if (bClearParticleImmediately)
            ClearTauntParticle(iClient);
        else
            RequestFrame(NextFrame_ClearTauntParticle, GetClientSerial(iClient));
    }
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

bool FindTauntByIndex(char[] sIndex, Taunt tTaunt)
{
    int iLength = g_hTauntList.Length;
    for (int i; i < iLength; i++)
    {
        Taunt tBuffer;
        g_hTauntList.GetArray(i, tBuffer, sizeof(tBuffer));
        if (StrEqual(tBuffer.sID, sIndex))
        {
            tTaunt = tBuffer;
            return true;
        }
    }

    return false;
}

bool FindTauntByName(char[] sName, Taunt tTaunt)
{
    int iLength = g_hTauntList.Length;
    for (int i; i < iLength; i++)
    {
        Taunt tBuffer;
        g_hTauntList.GetArray(i, tBuffer, sizeof(tBuffer));
        if (StrContains(tBuffer.sName, sName, false) != -1)
        {
            tTaunt = tBuffer;
            return true;
        }
    }

    return false;
}

bool FindClassTauntByIndex(char[] sIndex, int iClass, Taunt tTaunt)
{
    int iLength = g_hClassTaunts[iClass].Length;
    for (int i; i < iLength; i++)
    {
        Taunt tBuffer;
        g_hClassTaunts[iClass].GetArray(i, tBuffer, sizeof(tBuffer));
        
        if (StrEqual(tBuffer.sID, sIndex))
        {
            tTaunt = tBuffer;
            return true;
        }
    }

    return false;
}

bool FindClassTauntByName(char[] sName, int iClass, Taunt tTaunt)
{
    int iLength = g_hClassTaunts[iClass].Length;
    for (int i; i < iLength; i++)
    {
        Taunt tBuffer;
        g_hClassTaunts[iClass].GetArray(i, tBuffer, sizeof(tBuffer));
        if (StrContains(tBuffer.sName, sName, false) != -1)
        {
            tTaunt = tBuffer;
            return true;
        }
    }

    return false;
}

bool FindUnusualByIndex(char[] sIndex, Unusual tTaunt)
{
    int iLength = g_hUnusualList.Length;
    for (int i; i < iLength; i++)
    {
        Unusual tBuffer;
        g_hUnusualList.GetArray(i, tBuffer, sizeof(tBuffer));
        if (StrEqual(tBuffer.sID, sIndex))
        {
            tTaunt = tBuffer;
            return true;
        }
    }

    return false;
}

bool FindUnusualByName(char[] sName, Unusual tUnusual)
{
    int iLength = g_hUnusualList.Length;
    for (int i; i < iLength; i++)
    {
        Unusual tBuffer;
        g_hUnusualList.GetArray(i, tBuffer, sizeof(tBuffer));
        if (StrContains(tBuffer.sName, sName, false) != -1)
        {
            tUnusual = tBuffer;
            return true;
        }
    }

    return false;
}

void SwitchToNextBestWeapon(int iClient)
{
    for (int i; i <= TFWeaponSlot_PDA; i++)
    {
        int iWeapon = GetPlayerWeaponSlot(iClient, i);
        if (iWeapon != -1)
        {
            SetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon", iWeapon);
            return;
        }
    }

    SetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon", -1);
}

int GetSlotForWeapon(int iClient, int iWeapon)
{
    for (int i; i <= TFWeaponSlot_PDA; i++)
    {
        int iWeaponInSlot = GetPlayerWeaponSlot(iClient, i);
        if (iWeapon == iWeaponInSlot)
            return i;
    }

    return -1;
}

void Timer_AttachTauntParticle(Handle hTimer, DataPack hData)
{
    hData.Reset();
    int iClient = GetClientFromSerial(hData.ReadCell());
    if (!iClient || !IsPlayerAlive(iClient))
        return;

    char sEffect[MAX_NAME_LENGTH];
    hData.ReadString(sEffect, sizeof(sEffect));

    if (EntRefToEntIndex(g_iTriggerParticle) == -1)
    {
        g_iTriggerParticle = CreateEntityByName("trigger_particle");
        DispatchKeyValueInt(g_iTriggerParticle, "spawnflags", 1);
        DispatchKeyValueInt(g_iTriggerParticle, "IsEnabled", 1);
        DispatchKeyValueInt(g_iTriggerParticle, "attachment_type", PATTACH_ABSORIGIN_FOLLLOW);
        DispatchSpawn(g_iTriggerParticle);
        
        SetEntProp(g_iTriggerParticle, Prop_Send, "m_nSolidType", 0);
        EntityCollisionRulesChanged(g_iTriggerParticle);
    }
    
    SetEntPropString(g_iTriggerParticle, Prop_Data, "m_iszParticleName", sEffect);
	AcceptEntityInput(g_iTriggerParticle, "StartTouch", iClient, iClient);
}

void NextFrame_ClearTauntParticle(int iSerial)
{
    int iClient = GetClientFromSerial(iSerial);
    if (iClient)
        ClearTauntParticle(iClient);
}

void ClearTauntParticle(int iClient)
{
    SetVariantString("ParticleEffectStop");
    AcceptEntityInput(iClient, "DispatchEffect", iClient, iClient);
}

void TT_ReplyToCommand(int iClient, const char[] sFormat, any ...)
{
    char sBuffer[256];
	VFormat(sBuffer, sizeof(sBuffer), sFormat, 3);
    ReplyToCommand(iClient, "%s %s", PLUGIN_TAG, sBuffer);
}

void TT_PrintToChat(int iClient, const char[] sFormat, any ...)
{
    char sBuffer[256];
	VFormat(sBuffer, sizeof(sBuffer), sFormat, 3);
    PrintToChat(iClient, "%s %s", PLUGIN_TAG, sBuffer);
}
