/******************************************************************/
/*                                                                */
/*                           entWatch                             */
/*                                                                */
/*                                                                */
/*  File:          entWatch.sp                                    */
/*  Description:   Notify players about entity interactions.      */
/*                                                                */
/*                                                                */
/*  Copyright (C) 2018 - 2019  Kyle                               */
/*  2018/05/08 20:13:14                                           */
/*                                                                */
/*  This code is licensed under the GPLv3 License.                */
/*                                                                */
/******************************************************************/


#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <smutils>          //https://github.com/Kxnrl/sourcemod-utils
#include <cstrike>
#include <sdkhooks>
#include <entWatch>

#undef REQUIRE_EXTENSIONS
#include <dhooks>
#include <clientprefs>
#include <topmenus>
#define REQUIRE_EXTENSIONS

#undef REQUIRE_PLUGIN
#include <ZombieEscape>
#include <zombiereloaded>
#include <fys.opts>
#include <fys.menu>
#include <fys.bans>
#include <adminmenu>
#include <leader>
#define REQUIRE_PLUGIN

// load translations
#define USE_TRANSLATIONS  
// wanna print preconfig message
//#define PRINT_PRECONFIGS  
// wanna wallhack icon
//#define USE_WALLHACK
// wanna auto disabled radar
//#define AUTO_HIDERADAR

#define PI_NAME "[CSGO] entWatch"
#define PI_AUTH "Kyle"
#define PI_DESC "Notify players about entity interactions."
#define PI_VERS "1.5.1"
#define PI_URLS "https://kxnrl.com"

public Plugin myinfo = 
{
    name        = PI_NAME,
    author      = PI_AUTH,
    description = PI_DESC,
    version     = PI_VERS,
    url         = PI_URLS
};

#define MAXENT 256
#define MAXPLY  65
#define ZOMBIE   0
#define HUMANS   1
#define GLOBAL   0
#define COOLDN   1

enum struct CEntity
{
    char ent_name[32];
    char ent_short[32];
    char ent_buttonclass[32];
    char ent_filtername[32];
    bool ent_hasfiltername;
    int  ent_ownerid;
    int  ent_hammerid;
    int  ent_buttonid;
    int  ent_weaponref;
    int  ent_glowref;
    int  ent_mode;               // 0 = No button, 1 = Spam protection only, 2 = Cooldowns, 3 = Limited uses, 4 = Limited uses with cooldowns, 5 = Cooldowns after multiple uses.
    int  ent_uses;
    int  ent_maxuses;
    int  ent_startcd;
    int  ent_cooldown;
    int  ent_cooldowntime;
    int  ent_team;
    bool ent_displayhud;
    bool ent_weaponglow;
    bool ent_pickedup;
    bool ent_autotrasfer;
}

enum struct AdminMenuType
{
    TopMenuObject sm_eban;
    TopMenuObject sm_eunban;
    TopMenuObject sm_etransfer;
}

enum struct Forward
{
    Handle OnPick;
    Handle OnPicked;
    Handle OnDropped;
    Handle OnUse;
    Handle OnTransfered;
    Handle OnBanned;
    Handle OnUnban;
}

enum struct Cookies
{
    Handle Restricted;
    Handle BanByAdmin;
    Handle BanTLength;
    Handle DisplayHud;
}

enum struct PreConf
{
    ArrayList Button;
    ArrayList Weapon;
    ArrayList Locked;
}

static CEntity g_CEntity[MAXENT];
static Forward g_Forward;
static Cookies g_Cookies;
static PreConf g_PreConf;

static Handle g_tRound         = null;
static Handle g_tKnife[MAXPLY] = null;
static Handle g_tCooldown      = null;

static int  g_iEntCounts      = 0;
static int  g_iScores[MAXPLY] = {0, ...};

#if defined USE_WALLHACK
static int  g_iIconRef[MAXPLY] = {INVALID_ENT_REFERENCE, ...};
#endif

static bool g_bConfigLoaded    = false;
#if defined AUTO_HIDERADAR
static bool g_bMapsDDSRadar    = false;
#endif
static bool g_bHasEnt[MAXPLY]  = false;
static bool g_bBanned[MAXPLY]  = false;
static bool g_bEntHud[MAXPLY]  = false;

static char g_szGlobalHud[2][4096];
static char g_szClantag[MAXPLY][32];

static float g_fPickup[MAXPLY] = {0.0, ...};

static bool g_pZombieEscape = false;
static bool g_pZombieReload = false;

static bool g_bLateload;

// DHook
static bool g_pDHooks;
static Handle hAcceptInput;

static int g_iTeam[MAXPLY];
static int g_iEntTeam[4096];

// cookies
static bool g_pClientPrefs;
static bool g_pfysOptions;

// menu
static AdminMenuType g_TopItem;
static TopMenuObject entwatch_commands = INVALID_TOPMENUOBJECT;

// bans
static bool g_pfysAdminSys;

// leader
static bool g_pLeader3Sys;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    RegPluginLibrary("entWatch");

    CreateNative("entWatch_HasbeenBanned", Native_HasBanned);
    CreateNative("entWatch_ClientHasItem", Native_HasItem);
    CreateNative("entWatch_EntityIsItem",  Native_IsItem);

    MarkNativeAsOptional("ZE_IsAvenger");
    MarkNativeAsOptional("ZE_IsInfector");
    MarkNativeAsOptional("ZR_IsClientHuman");
    MarkNativeAsOptional("ZR_IsClientZombie");
    
    g_bLateload = late;

    return APLRes_Success;
}

public int Native_HasBanned(Handle plugin, int numParams)
{
    return g_bBanned[GetNativeCell(1)];
}

public int Native_HasItem(Handle plugin, int numParams)
{
    return g_bHasEnt[GetNativeCell(1)];
}

public int Native_IsItem(Handle plugin, int numParams)
{
    if(!g_bConfigLoaded)
        return false;

    int entity = GetNativeCell(1);
    int entref = EntIndexToEntRef(entity);

    for(int i = 0; i < g_iEntCounts; ++i)
        if(g_CEntity[i].ent_weaponref == entref)
            return true;

    return false;
}

public void OnPluginStart()
{
    if(GetEngineVersion() != Engine_CSGO)
        SetFailState("CSGO only!");

    SMUtils_SetChatPrefix("[\x04entWatch\x01]");
    SMUtils_SetChatSpaces("   ");
    SMUtils_SetChatConSnd(true);
    SMUtils_SetTextDest(HUD_PRINTCENTER);

    HookEventEx("round_start",    Event_RoundStart,   EventHookMode_Post);
    HookEventEx("round_end",      Event_RoundEnd,     EventHookMode_Post);
#if defined AUTO_HIDERADAR
    HookEventEx("player_spawn",   Event_PlayerSpawn,  EventHookMode_Post);
#endif
    HookEventEx("player_death",   Event_PlayerDeath,  EventHookMode_Post);
    HookEventEx("player_team",    Event_PlayerTeams,  EventHookMode_Post);

    g_Forward.OnPick       = CreateGlobalForward("entWatch_OnPickItem",        ET_Event,  Param_Cell, Param_String);
    g_Forward.OnPicked     = CreateGlobalForward("entWatch_OnPickedItem",      ET_Ignore, Param_Cell, Param_String);
    g_Forward.OnDropped    = CreateGlobalForward("entWatch_OnDroppedItem",     ET_Ignore, Param_Cell, Param_Cell, Param_String);
    g_Forward.OnUse        = CreateGlobalForward("entWatch_OnItemUse",         ET_Event,  Param_Cell, Param_String);
    g_Forward.OnTransfered = CreateGlobalForward("entWatch_OnItemTransfered",  ET_Ignore, Param_Cell, Param_Cell, Param_String);
    g_Forward.OnBanned     = CreateGlobalForward("entWatch_OnClientBanned",    ET_Ignore, Param_Cell);
    g_Forward.OnUnban      = CreateGlobalForward("entWatch_OnClientUnban",     ET_Ignore, Param_Cell);

    RegConsoleCmd("sm_entwatch", Command_entWatch);
    RegConsoleCmd("sm_estats",   Command_Stats);
    RegConsoleCmd("sm_ehud",     Command_DisplayHud);

    RegAdminCmd("sm_eban",       Command_Restrict,   ADMFLAG_BAN);
    RegAdminCmd("sm_eunban",     Command_Unrestrict, ADMFLAG_BAN);
    RegAdminCmd("sm_etransfer",  Command_Transfer,   ADMFLAG_BAN);

    RegServerCmd("sm_ereload",   Command_Reload);

    g_PreConf.Button = new ArrayList();
    g_PreConf.Weapon = new ArrayList();
    g_PreConf.Locked = new ArrayList();

#if defined USE_TRANSLATIONS
    LoadTranslations("entWatch.phrases");
#endif

    if(g_bLateload)
    {
        for(int client = 1; client <= MaxClients; ++client)
        if(ClientIsValid(client))
        {
            OnClientConnected(client);
            OnClientPutInServer(client);
            if(g_pClientPrefs && AreClientCookiesCached(client))
                OnClientCookiesCached(client);
            if(g_pfysOptions && Opts_IsClientLoaded(client))
                Opts_OnClientLoad(client);
        }
    }
}

public void OnAllPluginsLoaded()
{
    if(LibraryExists("dhooks"))
        OnLibraryAdded("dhooks");

    if(LibraryExists("clientprefs"))
        OnLibraryAdded("clientprefs");

    if(LibraryExists("fys-Bans"))
        OnLibraryAdded("fys-Bans");

    if(LibraryExists("leader"))
        OnLibraryAdded("leader");

    if(g_bLateload)
    {
        if(LibraryExists("fys-Opts"))
            OnLibraryAdded("fys-Opts");

        if(LibraryExists("adminmenu"))
            OnLibraryAdded("adminmenu");
    }
}

public void OnLibraryAdded(const char[] name)
{
    if(strcmp(name, "dhooks") == 0)
    {
        Handle GameConf = LoadGameConfigFile("sdktools.games\\engine.csgo");

        if(GameConf == null)
        {
            SetFailState("Why not has gamedata?");
            return;
        }

        int offset = GameConfGetOffset(GameConf, "AcceptInput");
        hAcceptInput = DHookCreate(offset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity, Event_AcceptInput);
        if(hAcceptInput == null)
        {
            LogError("Failed to DHook \"AcceptInput\".");
            return;
        }
        
        delete GameConf;

        DHookAddParam(hAcceptInput, HookParamType_CharPtr);
        DHookAddParam(hAcceptInput, HookParamType_CBaseEntity);
        DHookAddParam(hAcceptInput, HookParamType_CBaseEntity);
        DHookAddParam(hAcceptInput, HookParamType_Object, 20);
        DHookAddParam(hAcceptInput, HookParamType_Int);

        g_pDHooks = true;
    }
    else if(strcmp(name, "clientprefs") == 0)
    {
        g_pClientPrefs = true;

        g_Cookies.Restricted = RegClientCookie("entwatch_restricted", "", CookieAccess_Private);
        g_Cookies.BanByAdmin = RegClientCookie("entwatch_banbyadmin", "", CookieAccess_Private);
        g_Cookies.BanTLength = RegClientCookie("entwatch_bantLength", "", CookieAccess_Private);
        g_Cookies.DisplayHud = RegClientCookie("entwatch_displayhud", "", CookieAccess_Private);
    }
    else if(strcmp(name, "fys-Opts") == 0)
    {
        g_pfysOptions = true;
    }
    else if(strcmp(name, "fys-Bans") == 0)
    {
        g_pfysAdminSys = true;
    }
    else if(strcmp(name, "fys-Bans") == 0)
    {
        g_pLeader3Sys = true;
    }
    else if(LibraryExists("fys-Menu"))
    {
        TopMenu menu = Menu_GetAdminMenu();
        if(menu != null)
            OnAdminMenuReady(menu);
    }
    else if(LibraryExists("adminmenu"))
    {
        TopMenu menu = GetAdminTopMenu();
        if(menu != null)
            OnAdminMenuReady(menu);
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if(strcmp(name, "dhooks") == 0)
    {
        g_pDHooks = false;
        LogError("Dhook library has been removed.");
    }
    else if(strcmp(name, "clientprefs") == 0)
    {
        g_pClientPrefs = false;

        g_Cookies.Restricted = null;
        g_Cookies.BanByAdmin = null;
        g_Cookies.BanTLength = null;
        g_Cookies.DisplayHud = null;
    }
    else if(strcmp(name, "fys-Opts") == 0)
    {
        g_pfysOptions = false;
    }
    else if(strcmp(name, "fys-Bans") == 0)
    {
        g_pfysAdminSys = false;
    }
    else if(strcmp(name, "fys-Bans") == 0)
    {
        g_pLeader3Sys = false;
    }
}

public void Menu_OnAdminMenuReady(Handle aTopMenu)
{
    AddToAdminMenu(TopMenu.FromHandle(aTopMenu));
}

public void OnAdminMenuReady(Handle aTopMenu)
{
    AddToAdminMenu(TopMenu.FromHandle(aTopMenu));
}

static void AddToAdminMenu(TopMenu topmenu)
{
    if (entwatch_commands != INVALID_TOPMENUOBJECT)
        return;

    entwatch_commands = topmenu.AddCategory("entwatch", AdminMenuHandler, "ehud", ADMFLAG_BAN);

    if(entwatch_commands != INVALID_TOPMENUOBJECT)
    {
        g_TopItem.sm_eban      = topmenu.AddItem("sm_eban",      AdminMenuHandler, entwatch_commands, "sm_eban",      ADMFLAG_BAN);
        g_TopItem.sm_eunban    = topmenu.AddItem("sm_eunban",    AdminMenuHandler, entwatch_commands, "sm_eunban",    ADMFLAG_BAN);
        g_TopItem.sm_etransfer = topmenu.AddItem("sm_etransfer", AdminMenuHandler, entwatch_commands, "sm_etransfer", ADMFLAG_BAN);
    }
}

public void AdminMenuHandler(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength)
{
    if(action == TopMenuAction_DisplayTitle)
    {
        if(topobj_id == entwatch_commands)
            FormatEx(buffer, maxlength, "entWatch: ");
    }
    else if(action == TopMenuAction_DisplayOption)
    {
        if(topobj_id == entwatch_commands)             FormatEx(buffer, maxlength, "entWatch");
        else if(topobj_id == g_TopItem.sm_eban)        FormatEx(buffer, maxlength, "Ban client");
        else if(topobj_id == g_TopItem.sm_eunban)      FormatEx(buffer, maxlength, "Unban client");
        else if(topobj_id == g_TopItem.sm_etransfer)   FormatEx(buffer, maxlength, "Transfer Item");
        else                                           FormatEx(buffer, maxlength, "entWatch");
    }
    else if(action == TopMenuAction_SelectOption)
    {
        if(topobj_id == entwatch_commands)             { }
        else if(topobj_id == g_TopItem.sm_eban)        DisplayMenu_Restrict(param);
        else if(topobj_id == g_TopItem.sm_eunban)      DisplayMenu_Unrestrict(param);
        else if(topobj_id == g_TopItem.sm_etransfer)   DisplayMenu_Transfer(param);
    }
}

public Action Command_Reload(int args)
{
    OnMapEnd();
    OnMapStart();
    OnConfigsExecuted();
}

public void OnMapStart()
{
#if defined USE_WALLHACK
    AddFileToDownloadsTable("materials/maoling/sprites/ze/entwatch_2017.vmt");
    AddFileToDownloadsTable("materials/maoling/sprites/ze/entwatch_2017.vtf");
    PrecacheModel("materials/maoling/sprites/ze/entwatch_2017.vmt", true);
#endif
}

public void OnConfigsExecuted()
{
#if defined AUTO_HIDERADAR
    char map[128];
    GetCurrentMap(map, 128);
    g_bMapsDDSRadar = CheckMapRadar(map);
#endif

    g_PreConf.Weapon.Clear();
    g_PreConf.Button.Clear();
    g_PreConf.Locked.Clear();

    for(int index = 0; index < MAXENT; index++)
    {
        g_CEntity[index].ent_name[0]        = '\0';
        g_CEntity[index].ent_short[0]       = '\0';
        g_CEntity[index].ent_buttonclass[0] = '\0';
        g_CEntity[index].ent_filtername[0]  = '\0';
        g_CEntity[index].ent_hasfiltername  = false;
        g_CEntity[index].ent_hammerid       = -1;
        g_CEntity[index].ent_weaponref      = -1;
        g_CEntity[index].ent_buttonid       = -1;
        g_CEntity[index].ent_ownerid        = -1;
        g_CEntity[index].ent_mode           = 0;
        g_CEntity[index].ent_uses           = 0;
        g_CEntity[index].ent_maxuses        = 0;
        g_CEntity[index].ent_cooldown       = 0;
        g_CEntity[index].ent_cooldowntime   = -1;
        g_CEntity[index].ent_weaponglow     = false;
        g_CEntity[index].ent_displayhud     = false;
        g_CEntity[index].ent_team           = -1;
        g_CEntity[index].ent_glowref   = INVALID_ENT_REFERENCE;
    }

    LoadConfig();

#if defined __ZombieEscape__
    g_pZombieEscape = (LibraryExists("ZombieEscape") && GetFeatureStatus(FeatureType_Native, "ZE_IsAvenger") == FeatureStatus_Available);
#endif
#if defined __zombiereloaded__
    g_pZombieReload = (LibraryExists("zombiereloaded") && GetFeatureStatus(FeatureType_Native, "ZR_IsClientZombie") == FeatureStatus_Available);
#endif
}

public void OnMapEnd()
{
    StopTimer(g_tRound);
    StopTimer(g_tCooldown);
}

public void OnClientConnected(int client)
{
    g_bBanned[client] = false;
    g_bEntHud[client] = false;
}

public void OnClientCookiesCached(int client)
{
    LoadClientState(client);
}

public void Opts_OnClientLoad(int client)
{
    LoadClientState(client);
}

static void LoadClientState(int client)
{
    if(g_pfysOptions)
    {
        g_bEntHud[client] = Opts_GetOptBool(client, "entWatch.Hud.Disabled", false);
        g_bBanned[client] = Opts_GetOptBool(client, "entWatch.Ban.Banned",   false);
    }
    else if(g_pClientPrefs)
    {
        char buffer[32];

        GetClientCookie(client, g_Cookies.DisplayHud, buffer, 32);
        if(StringToInt(buffer) == 1)
            g_bEntHud[client] = true;

        GetClientCookie(client, g_Cookies.Restricted, buffer, 32);
        if(StringToInt(buffer) == 1)
            g_bBanned[client] = true;
    }

    CheckBanState(client);
}

static void CheckBanState(int client)
{
    if(!g_bBanned[client])
        return;

    int expired = -1;

    if(g_pfysOptions)
    {
        expired = Opts_GetOptInteger(client, "entWatch.Ban.Length", -1);
    }
    else if(g_pClientPrefs)
    {
        char buffer[32];
        GetClientCookie(client, g_Cookies.BanTLength, buffer, 32);
        expired = StringToInt(buffer);
    }

    if (expired > 0 && expired < GetTime())
    {
        // expired
        EunbanClient(client);
    }
}

static void EBanClient(int client, int length, const char[] admin)
{
    if(g_pfysOptions)
    {
        Opts_SetOptBool   (client, "entWatch.Ban.Banned", true);
        Opts_SetOptInteger(client, "entWatch.Ban.Length", length);
        Opts_SetOptString (client, "entWatch.Ban.IAdmin", "null");
    }
    else if(g_pClientPrefs)
    {
        char buffer[32];
        IntToString(length, buffer, 32);

        SetClientCookie(client, g_Cookies.Restricted, "1");
        SetClientCookie(client, g_Cookies.BanTLength, buffer);
        SetClientCookie(client, g_Cookies.BanByAdmin, admin);
    }

    g_bBanned[client] = true;
}

static void EunbanClient(int client)
{
    if(g_pfysOptions)
    {
        Opts_SetOptBool   (client, "entWatch.Ban.Banned", false);
        Opts_SetOptInteger(client, "entWatch.Ban.Length", -1);
        Opts_SetOptString (client, "entWatch.Ban.IAdmin", "null");
    }
    else if(g_pClientPrefs)
    {
        SetClientCookie(client, g_Cookies.Restricted, "0");
        SetClientCookie(client, g_Cookies.BanTLength, "-1");
        SetClientCookie(client, g_Cookies.BanByAdmin, "null");
    }

    g_bBanned[client] = false;
}

static bool GetEBanInfo(int client, char[] iadmin, int maxLen, int &expired)
{
    if(g_pfysOptions)
    {
        expired = Opts_GetOptInteger(client, "entWatch.Ban.Length", -1);
        Opts_GetOptString(client, "entWatch.Ban.IAdmin", iadmin, maxLen);
        return true;
    }
    else if(g_pClientPrefs)
    {
        char buffer[32];
        GetClientCookie(client, g_Cookies.BanByAdmin, iadmin, maxLen);
        GetClientCookie(client, g_Cookies.BanTLength, buffer, 32);
        expired = StringToInt(buffer);
        return true;
    }
    return false;
}

static void SetHudState(int client)
{
    if(g_pfysOptions)
    {
        Opts_SetOptBool(client, "entWatch.Hud.Disabled", g_bEntHud[client]);
    }
    else if(g_pClientPrefs)
    {
        SetClientCookie(client, g_Cookies.DisplayHud, g_bEntHud[client] ? "1" : "0");
    }
}

public void OnClientPutInServer(int client)
{
    if(!ClientIsValid(client))
        return;

    CS_GetClientClanTag(client, g_szClantag[client], 32);

    g_iScores[client] = 0;
    g_bHasEnt[client] = false;

    SDKHook(client, SDKHook_WeaponDropPost,  Event_WeaponDropPost);
    SDKHook(client, SDKHook_WeaponEquipPost, Event_WeaponEquipPost);
    SDKHook(client, SDKHook_WeaponCanUse,    Event_WeaponCanUse);
}

public void OnClientCommandKeyValues_Post(int client, KeyValues kv)
{
    char szCommmand[32];
    if(kv.GetSectionName(szCommmand, 32) && strcmp(szCommmand, "ClanTagChanged", false) == 0)
        kv.GetString("tag", g_szClantag[client], 32);
}

public void OnClientDisconnect(int client)
{
    if(!IsClientInGame(client))
        return;

    SDKUnhook(client, SDKHook_WeaponDropPost,  Event_WeaponDropPost);
    SDKUnhook(client, SDKHook_WeaponEquipPost, Event_WeaponEquipPost);
    SDKUnhook(client, SDKHook_WeaponCanUse,    Event_WeaponCanUse);

    StopTimer(g_tKnife[client]);

    if(g_bConfigLoaded && g_bHasEnt[client])
    {
        for(int index = 0; index < MAXENT; ++index)
            if(g_CEntity[index].ent_ownerid == client)
            {
                if(g_CEntity[index].ent_autotrasfer)
                {
                    int target = AutoTarget(client);
                    if(target != -1)
                    {
                        TransferClientEnt(target, client, true);
                        continue;
                    }
                }

                int weapon = EntRefToEntIndex(g_CEntity[index].ent_weaponref);

                g_CEntity[index].ent_ownerid = -1;

                if(IsValidEdict(weapon))
                {
                    SDKHooks_DropWeapon(client, weapon);
                    RequestFrame(SetWeaponGlow, index);
                }

                //if(g_CEntity[index].ent_buttonid != -1)
                //    SDKUnhook(g_CEntity[index].ent_buttonid, SDKHook_Use, Event_ButtonUse);

                Call_StartForward(g_Forward.OnDropped);
                Call_PushCell(client);
                Call_PushCell(DR_OnDisconnect);
                Call_PushString(g_CEntity[index].ent_name);
                Call_Finish();

#if defined USE_TRANSLATIONS
                tChatTeam(g_CEntity[index].ent_team, true, "%t", "disconnected with ent", client, g_CEntity[index].ent_name);
#else
                ChatTeam(g_CEntity[index].ent_team, true, "\x0C%N\x01离开游戏时带着神器\x04%s", client, g_CEntity[index].ent_name);
#endif
            }

#if defined USE_WALLHACK
        ClearIcon(client);
#endif

        RefreshHud();
    }
    
    g_bHasEnt[client] = false;

    if (IsPlayerAlive(client))
        StripWeapon(client, true);
}

static void ResetAllStats()
{
    for(int client = 1; client <= MaxClients; ++client)
        if(ClientIsValid(client))
            SetClientDefault(client);

    for(int index = 0; index < g_iEntCounts; index++)
    {
        if(g_CEntity[index].ent_buttonid != -1)
            SDKUnhook(g_CEntity[index].ent_buttonid, SDKHook_Use, Event_ButtonUse);

        RemoveWeaponGlow(index);

        g_CEntity[index].ent_weaponref      = -1;
        g_CEntity[index].ent_buttonid       = -1;
        g_CEntity[index].ent_ownerid        = -1;
        g_CEntity[index].ent_cooldowntime   = -1;
        g_CEntity[index].ent_uses           = 0;
        g_CEntity[index].ent_pickedup       = false;
    }
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if(!g_bConfigLoaded)
    {
        for(int index = 0; index < g_PreConf.Locked.Length; ++index)
            g_PreConf.Locked.Set(index, -1.0);
        
        return;
    }

    g_szGlobalHud[ZOMBIE][0] = '\0';
    g_szGlobalHud[HUMANS][0] = '\0';
    ResetAllStats();

    if(g_tRound != null)
        KillTimer(g_tRound);
    g_tRound = CreateTimer(5.0, Timer_RoundStart);

    static ConVar mp_disconnect_kills_players = null;
    if(mp_disconnect_kills_players == null)
        mp_disconnect_kills_players = FindConVar("mp_disconnect_kills_players");

    mp_disconnect_kills_players.SetInt(0, true, true);

    static ConVar mp_weapons_glow_on_ground = null;
    if(mp_weapons_glow_on_ground == null)
        mp_weapons_glow_on_ground = FindConVar("mp_weapons_glow_on_ground");

    mp_weapons_glow_on_ground.SetInt(0, true, true);
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if(!g_bConfigLoaded)
        return;

    StopTimer(g_tRound);
}

public Action Timer_RoundStart(Handle timer)
{
    g_tRound = null;

#if defined USE_TRANSLATIONS
    tChatAll("%t", "welcome message");
#else
    ChatAll("\x07当前服务器已启动entWatch \x0A::\x04Kyle Present\x0A::");
#endif

    return Plugin_Stop;
}

public void ZE_OnFirstInfected(int[] clients, int numClients, bool teleportOverride, bool teleport)
{
    for(int client = 0; client < numClients; ++client)
        DropClientEnt(client);
}

public void ZR_OnClientInfected(int client, int attacker, bool motherInfect, bool respawnOverride, bool respawn)
{
    if(!motherInfect)
        return;
    
    DropClientEnt(client);
}

#if defined AUTO_HIDERADAR
public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    RequestFrame(SetClientRadar, event.GetInt("userid"));
}

static void SetClientRadar(int userid)
{
    int client = GetClientOfUserId(userid);
    if (IsClientInGame(client))
    {
        static int defaultHud = -10086;
        if(defaultHud == -10086) 
            defaultHud = GetEntProp(client, Prop_Send, "m_iHideHUD");

        SetEntProp(client, Prop_Send, "m_iHideHUD", g_bMapsDDSRadar ? defaultHud : 1<<12);
    }
}
#endif

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if(!g_bConfigLoaded)
        return;
    
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);

    DropClientEnt(client);
    
#if defined AUTO_HIDERADAR
    RequestFrame(SetClientRadar, userid);
#endif
}

static void DropClientEnt(int client)
{
    if(!g_bHasEnt[client])
        return;

    for(int index = 0; index < MAXENT; ++index)
        if(g_CEntity[index].ent_ownerid == client)
        {
            int weaponid = EntRefToEntIndex(g_CEntity[index].ent_weaponref);

            if(IsValidEdict(weaponid))
            {
                SDKHooks_DropWeapon(client, weaponid);
                RequestFrame(SetWeaponGlow, index);
            }

            g_CEntity[index].ent_ownerid = -1;

            //if(g_CEntity[index].ent_buttonid != -1)
            //    SDKUnhook(g_CEntity[index].ent_buttonid, SDKHook_Use, Event_ButtonUse);

            Call_StartForward(g_Forward.OnDropped);
            Call_PushCell(client);
            Call_PushCell(DR_OnDeath);
            Call_PushString(g_CEntity[index].ent_name);
            Call_Finish();

#if defined USE_TRANSLATIONS
            tChatTeam(g_CEntity[index].ent_team, true, "%t", "died with ent", client, g_CEntity[index].ent_name);
#else
            ChatTeam(g_CEntity[index].ent_team, true, "\x0C%N\x01死亡时带着神器\x04%s", client, g_CEntity[index].ent_name);
#endif
        }

    RefreshHud();
    SetClientDefault(client);
}

public void Event_PlayerTeams(Event e, const char[] name, bool dontBroadcast)
{
    if (e.GetBool("disconnect"))
        return;

    int client = GetClientOfUserId(e.GetInt("userid"));
    int nxteam = e.GetInt("team");
    int prteam = e.GetInt("oldteam");

    g_iTeam[client] = nxteam;

    if (nxteam == CS_TEAM_SPECTATOR && prteam >= CS_TEAM_T)
    {
        // force DROP
        DropClientEnt(client);
    }
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if(StrContains(classname, "weapon_", false) != 0)
        return;

    SDKHook(entity, SDKHook_SpawnPost, Event_WeaponCreated);
}

public void Event_WeaponCreated(int entity)
{
    SDKUnhook(entity, SDKHook_SpawnPost, Event_WeaponCreated);

    if(!IsValidEdict(entity))
        return;

    RequestFrame(Event_CreatedPost, entity);
}

static void Event_CreatedPost(int entity)
{
    if(!IsValidEdict(entity))
        return;

    char classname[32];

    if(!GetEdictClassname(entity, classname, 32))
        return;

    int hammerid = GetEntityHammerID(entity);

    if(hammerid <= 0)
        return;

    for(int index = 0; index < g_iEntCounts; ++index)
        if(g_CEntity[index].ent_hammerid == hammerid)
        {
            //PrintToServer("Event_WeaponCreated -> %d -> match -> %d", entity, hammerid);
            if(g_CEntity[index].ent_weaponref == -1)
            {
                g_CEntity[index].ent_weaponref = EntIndexToEntRef(entity);
                RequestFrame(SetWeaponGlow, index);
                if(g_CEntity[index].ent_buttonid == -1 && g_CEntity[index].ent_mode > 0 && strcmp(g_CEntity[index].ent_buttonclass, "func_button", false) == 0)
                {
                    char buffer_targetname[32], buffer_parentname[32];
                    GetEntityTargetName(entity, buffer_targetname, 32);

                    int button = -1;
                    while((button = FindEntityByClassname(button, g_CEntity[index].ent_buttonclass)) != -1)
                    {
                        GetEntityParentName(button, buffer_parentname, 32);

                        if(strcmp(buffer_targetname, buffer_parentname) == 0)
                        {
                            SDKHookEx(button, SDKHook_Use, Event_ButtonUse);
                            g_CEntity[index].ent_buttonid = button;
                            //LogMessage("%N first picked %d:%d", client, weapon, button);
                            break;
                        }
                    }
                }
                //PrintToServer("Event_WeaponCreated -> %d -> Validate -> %d", entity, index);
                break;
            }
        }

    //PrintToServer("Event_WeaponCreated -> %d -> not found -> %d", entity, hammerid);
}

public void Event_WeaponEquipPost(int client, int weapon)
{
    if(!g_bConfigLoaded)
    {
        CheckPreConfigs(client, weapon);
        return;
    }

    int hamid = GetEntityHammerID(weapon);
    
    if(hamid <= 0)
        return;

    int iref = EntIndexToEntRef(weapon);
    
    int index = -1;
    for(int x = 0; x < g_iEntCounts; ++x)
        if(g_CEntity[x].ent_hammerid == hamid)
            if(g_CEntity[x].ent_weaponref == iref)
            {
                index = x;
                break;
            }

    if(index < 0)
        return;

    g_CEntity[index].ent_team = g_iTeam[client];
    
	if(!g_CEntity[index].ent_pickedup)
	{
		if(g_CEntity[index].ent_startcd != 0)
			g_CEntity[index].ent_cooldowntime = g_CEntity[index].ent_startcd;
		else
			g_CEntity[index].ent_cooldowntime = -1;
	}

    g_CEntity[index].ent_ownerid   = client;
    g_CEntity[index].ent_pickedup  = true;

#if defined USE_WALLHACK
    CreateIcon(client);
#endif 

    RemoveWeaponGlow(index);

    g_bHasEnt[client] = true;
    g_iScores[client] = 99966 - CS_GetClientContributionScore(client);
    g_fPickup[client] = GetGameTime();

    int leader = g_pLeader3Sys ? Leader_CurrentLeader() : -1;
    if (leader != client)
    CS_SetClientContributionScore(client, 99966);

    //if(IsValidEdict(g_CEntity[index].ent_buttonid))
    //    SDKHookEx(g_CEntity[index].ent_buttonid, SDKHook_Use, Event_ButtonUse);
    //else 

    if(g_CEntity[index].ent_buttonid == -1 && g_CEntity[index].ent_mode > 0 && strcmp(g_CEntity[index].ent_buttonclass, "func_button", false) == 0)
    {
        char buffer_targetname[32], buffer_parentname[32];
        GetEntityTargetName(weapon, buffer_targetname, 32);

        int button = -1;
        while((button = FindEntityByClassname(button, g_CEntity[index].ent_buttonclass)) != -1)
        {
            GetEntityParentName(button, buffer_parentname, 32);

            if(strcmp(buffer_targetname, buffer_parentname) == 0)
            {
                SDKHookEx(button, SDKHook_Use, Event_ButtonUse);
                g_CEntity[index].ent_buttonid = button;
                //LogMessage("%N first picked %d:%d", client, weapon, button);
                break;
            }
        }
    }

    if(g_CEntity[index].ent_hasfiltername)
        DispatchKeyValue(client, "targetname", g_CEntity[index].ent_filtername);

#if defined USE_TRANSLATIONS
    tChatTeam(g_CEntity[index].ent_team, true, "%t", "pickup ent", client, g_CEntity[index].ent_name);
#else
    ChatTeam(g_CEntity[index].ent_team, true, "\x0C%N\x01捡起了神器\x04%s", client, g_CEntity[index].ent_name);
#endif

    Call_StartForward(g_Forward.OnPicked);
    Call_PushCell(client);
    Call_PushString(g_CEntity[index].ent_name);
    Call_Finish();

    RefreshHud();
}

static void CheckPreConfigs(int client, int weapon)
{
    // Get HammerID
    int hammerid = GetEntityHammerID(weapon);
    if(hammerid <= 0) return;

    // if was stored.
    if(g_PreConf.Weapon.FindValue(hammerid) != -1)
    {
#if defined PRINT_PRECONFIGS
        ChatAll("\x04PreConfigs \x01->\x10 Already record \x01[\x07%d\x01]", hammerid);
#endif
        return;
    }

    // Check targetname
    char targetname[128];
    GetEntityTargetName(weapon, targetname, 128);

#if defined PRINT_PRECONFIGS
    ChatAll("\x04PreConfigs \x01->\x05 targetname\x01[\x07%s\x01]", targetname);
#endif

    if(targetname[0] == '\0')
        return;

    // Find button
    int button = MaxClients+1;
    bool found = false;
    char parentname[128];
    while((button = FindEntityByClassname(button, "func_button")) != -1)
    {
        GetEntPropString(button, Prop_Data, "m_iParent", parentname, 128);

        // if match
        if(strcmp(targetname, parentname) == 0)
        {
            found = true;
            break;
        }
    }
    
    if(!found)
        button = -1;
#if defined PRINT_PRECONFIGS
    else ChatAll("\x04PreConfigs \x01->\x05 funcbutton\x01[\x07%d\x01]", button);
#endif

    DataPack pack;
    CreateDataTimer(0.2, Timer_CheckFilter, pack);
    pack.WriteCell(client);
    pack.WriteCell(weapon);
    pack.WriteCell(button);
    pack.WriteString(targetname);
    pack.WriteString(parentname);
}

static void SavePreConfigs(int weapon_hammerid, float cooldown)
{
    KeyValues kv = new KeyValues("entWatchPre");

    char path[256];
    GetCurrentMap(path, 256);
    BuildPath(Path_SM, path, 256, "configs/entWatchPre/%s.cfg", path);
    
    if(FileExists(path))
        kv.ImportFromFile(path);

    kv.Rewind();

    char buffer[32];
    IntToString(weapon_hammerid, buffer, 32);
    
    // check key exists
    if(!kv.JumpToKey(buffer, false))
    {
        delete kv;
        return;
    }

    kv.SetNum("cooldown", RoundToFloor(cooldown));

    // Save
    kv.Rewind();
    kv.ExportToFile(path);
    
    // close
    delete kv;
}

public Action Timer_CheckFilter(Handle timer, DataPack pack)
{
    pack.Reset();
    int client = pack.ReadCell();
    int weapon = pack.ReadCell();
    int button = pack.ReadCell();
    char targetname[128], parentname[128];
    pack.ReadString(targetname, 128);
    pack.ReadString(parentname, 128);

    if(!IsClientInGame(client) || !IsPlayerAlive(client) || !IsValidEdict(client))
        return Plugin_Stop;
    
    int hammerid = GetEntityHammerID(weapon);
    
    char filtername[128], clientname[128];
    GetEntityTargetName(client, clientname, 128);

#if defined PRINT_PRECONFIGS
    ChatAll("\x04PreConfigs \x01->\x05 clientname\x01[\x07%s\x01]", clientname);
#endif

    int iFilter = -1;
    bool found = false;
    while((iFilter = FindEntityByClassname(iFilter, "filter_activator_name")) != -1)
    {
        GetEntPropString(iFilter, Prop_Data, "m_iFilterName", filtername, 128);
        
        if(strcmp(clientname, filtername) == 0)
        {
            found = true;
            break;
        }
    }
    
    if(!found)
        strcopy(filtername, 128, "null");

#if defined PRINT_PRECONFIGS
    ChatAll("\x04PreConfigs \x01->\x05 filtername\x01[\x07%s\x01]", filtername);
#endif

    KeyValues kv = new KeyValues("entWatchPre");

    char path[256];
    GetCurrentMap(path, 256);
    BuildPath(Path_SM, path, 256, "configs/entWatchPre/%s.cfg", path);

    if(FileExists(path))
        kv.ImportFromFile(path);

    kv.Rewind();

    char kvstringid[16];
    IntToString(hammerid, kvstringid, 16);
    
    // store in array
    g_PreConf.Weapon.Push(hammerid);
    g_PreConf.Button.Push(button == -1 ? -1 : GetEntityHammerID(button));
    g_PreConf.Locked.Push(-1.0);

    if(kv.JumpToKey(kvstringid, false))
    {
        int cooldown = kv.GetNum("cooldown");
        if(cooldown > 0)
        {
            g_PreConf.Button.Set(g_PreConf.Button.Length-1, -1);
            g_PreConf.Locked.Set(g_PreConf.Locked.Length-1, cooldown);
        }
        return Plugin_Stop;
    }

    // create key
    kv.JumpToKey(kvstringid, true);

    // set name
    kv.SetString("name",      targetname);
    kv.SetString("shortname", targetname);
 
    // set button
    kv.SetString("buttonclass", button == -1 ? "" : "func_button");
    
    // filtername
    kv.SetString("filtername",    found ? filtername : "null");
    kv.SetString("hasfiltername", found ? "true"     : "false");
    
    // hammerid
    kv.SetString("hammerid", kvstringid);

    // set default
    kv.SetString("mode",      "0");
    kv.SetString("maxuses",   "0");
    kv.SetString("cooldown",  "0");
    kv.SetString("maxamount", "1");
    kv.SetString("glow",      "true");
    kv.SetString("team",      IsInfector(client) ? "zombie" : "human");
    kv.SetString("hud",       "true");

    // Save
    kv.Rewind();
    kv.ExportToFile(path);
    
    // close
    delete kv;

    if(button != -1 && g_pDHooks)
    {
        //PrintToServer("DHookEntity func_button [%d]", button);
        DHookEntity(hAcceptInput, true, button);
    }

#if defined PRINT_PRECONFIGS
    ChatAll("\x04PreConfigs \x01->\x10 Record the data successfully", filtername);
#endif

    return Plugin_Stop;
}

public void Event_WeaponDropPost(int client, int weapon)
{
    if(!IsValidEdict(weapon))
        return;

    if(g_bConfigLoaded)
    {
        bool other = false;

        for(int index = 0; index < g_iEntCounts; index++)
        {
            if(g_CEntity[index].ent_ownerid != client)
                continue;

            if(EntIndexToEntRef(weapon) == g_CEntity[index].ent_weaponref)
            {
                RequestFrame(SetWeaponGlow, index);

                g_CEntity[index].ent_ownerid = -1;
                
                //if(g_CEntity[index].ent_buttonid != -1)
                //    SDKUnhook(g_CEntity[index].ent_buttonid, SDKHook_Use, Event_ButtonUse);

#if defined USE_TRANSLATIONS
                tChatTeam(g_CEntity[index].ent_team, true, "%t", "droped ent", client, g_CEntity[index].ent_name);
#else
                ChatTeam(g_CEntity[index].ent_team, true, "\x0C%N\x01丟掉了神器\x04%s", client, g_CEntity[index].ent_name);
#endif

                RefreshHud();
                
                Call_StartForward(g_Forward.OnDropped);
                Call_PushCell(client);
                Call_PushCell(DR_NormalDrop);
                Call_PushString(g_CEntity[index].ent_name);
                Call_Finish();
            }
            else other = true;
        }

        if(!other) SetClientDefault(client);
    }

    char targetname[32];
    GetEntityTargetName(weapon, targetname, 32);
    if(targetname[0] != '\0')
        return;

    if(GetEntPropEnt(weapon, Prop_Data, "m_hMoveChild") != -1)
        return;

    AcceptEntityInput(weapon, "KillHierarchy");
    //if(!SelfKillEntityEx(weapon, 15.0)) AcceptEntityInput(weapon, "KillHierarchy");
}

public Action Event_SetTransmit(int entity, int client)
{
    if(g_iEntTeam[entity] <= 1 || g_iTeam[client] <= CS_TEAM_SPECTATOR)
        return Plugin_Continue;

    return g_iEntTeam[entity] == g_iTeam[client] ? Plugin_Continue : Plugin_Handled;
}

static void SetClientDefault(int client)
{
#if defined USE_WALLHACK
    ClearIcon(client);
#endif

    g_bHasEnt[client] = false;

    int leader = g_pLeader3Sys ? Leader_CurrentLeader() : -1;
    if (leader != client)
    CS_SetClientContributionScore(client, CS_GetClientContributionScore(client) - g_iScores[client]);

    CS_SetClientClanTag(client, g_szClantag[client]);

    //DispatchKeyValue(client, "targetname", "human");
}

static bool IsWeaponKnife(int weapon)
{
    char classname[32];
    GetEdictClassname(weapon, classname, 32);
    return (strcmp(classname, "weapon_knife") == 0);
}

public Action Event_WeaponCanUse(int client, int weapon)
{
    if(!IsValidEdict(weapon))
        return Plugin_Handled;

    if(!IsPlayerAlive(client))
        return Plugin_Handled;
    
    bool knife = IsWeaponKnife(weapon);

    if(IsInfector(client) && !knife)
        return Plugin_Handled;

    if(!g_bConfigLoaded)
        return Plugin_Continue;

    if(GetEntPropEnt(weapon, Prop_Data, "m_hMoveChild") == -1)
        return Plugin_Continue;

    int index = FindIndexByHammerId(GetEntityHammerID(weapon));

    if(index < 0)
        return Plugin_Continue;

    bool allow = true;
    Call_StartForward(g_Forward.OnPick);
    Call_PushCell(client);
    Call_PushString(g_CEntity[index].ent_name);
    Call_Finish(allow);

    if(allow && CanClientUseEnt(client))
    {
        // allow to pick up
        return Plugin_Continue;
    }

    if(knife)
    {
        // knife stripper?
        CheckClientKnife(client);
    }

    return Plugin_Handled;
}

static bool CanClientUseEnt(int client)
{
    if(g_bBanned[client])
    {
#if defined USE_TRANSLATIONS
        Text(client, "%t", "has been banned centertext");
#else
        Text(client, "你神器被BAN了,\n请到论坛申诉!");
#endif
        return false;
    }

    return true;
}

public Action Event_ButtonUse(int button, int activator, int caller, UseType type, float value)
{
    if(!g_bConfigLoaded)
        return Plugin_Continue;

    if(!IsValidEdict(button) || !ClientIsAlive(activator))
        return Plugin_Handled;

    //LogMessage("%N pressing %d : %d", activator, button, GetEntityHammerID(button));
    //LogMessage("%d parent is %d", button, GetEntPropEnt(button, Prop_Data, "m_pParent"));

    int index = FindIndexByButton(button);

    if(index < 0)
    {
        //LogMessage("Event_ButtonUse -> %N -> FindIndexByButton -> %d : %d", activator, button, GetEntityHammerID(button));
        return Plugin_Handled;
    }

    if(g_CEntity[index].ent_ownerid != activator)
    {
        //LogMessage("Event_ButtonUse -> %N -> activator", activator);
        return Plugin_Handled;
    }

    if(g_fPickup[activator]+1.5 > GetGameTime())
    {
        //LogMessage("Event_ButtonUse -> %N -> g_fPickup", activator);
        return Plugin_Handled;
    }

    int iOffset = FindDataMapInfo(button, "m_bLocked");

    if(iOffset != -1 && GetEntData(button, iOffset, 1))
    {
        //LogMessage("Event_ButtonUse -> %N -> iOffset", activator);
        return Plugin_Handled;
    }

    if(g_CEntity[index].ent_team != g_iTeam[activator])
    {
        //LogMessage("Event_ButtonUse -> %N -> GetClientTeam");
        return Plugin_Handled;
    }

    if(g_CEntity[index].ent_hasfiltername)
        DispatchKeyValue(activator, "targetname", g_CEntity[index].ent_filtername);
    
    bool allow = true;
    Call_StartForward(g_Forward.OnUse);
    Call_PushCell(activator);
    Call_PushString(g_CEntity[index].ent_name);
    Call_Finish(allow);

    if(!allow)
        return Plugin_Handled;

    if(g_CEntity[index].ent_mode == 1)
    {
        AddClientScore(activator, 1);
        return Plugin_Continue;
    }
    else if(g_CEntity[index].ent_mode == 2 && g_CEntity[index].ent_cooldowntime <= -1)
    {
        g_CEntity[index].ent_cooldowntime = g_CEntity[index].ent_cooldown;

#if defined USE_TRANSLATIONS
        tChatTeam(g_CEntity[index].ent_team, true, "%t", "used ent and cooldown", activator, g_CEntity[index].ent_name, g_CEntity[index].ent_cooldown);
#else
        ChatTeam(g_CEntity[index].ent_team, true, "\x0C%N\x01使用了神器\x04%s\x01[\x04CD\x01:\x07%d\x04秒\x01]", activator, g_CEntity[index].ent_name, g_CEntity[index].ent_cooldown);
#endif

        RefreshHud();
        AddClientScore(activator, 3);

        return Plugin_Continue;
    }
    else if(g_CEntity[index].ent_mode == 3 && g_CEntity[index].ent_uses < g_CEntity[index].ent_maxuses, activator, g_CEntity[index].ent_name, g_CEntity[index].ent_maxuses-g_CEntity[index].ent_uses)
    {
        g_CEntity[index].ent_uses++;

#if defined USE_TRANSLATIONS
        tChatTeam(g_CEntity[index].ent_team, true, "%t", "used ent and maxuses", activator, g_CEntity[index].ent_name, g_CEntity[index].ent_maxuses-g_CEntity[index].ent_uses);
#else       
        ChatTeam(g_CEntity[index].ent_team, true, "\x0C%N\x01使用了神器\x04%s\x01[\x04剩余\x01:\x07%d\x04次\x01]", activator, g_CEntity[index].ent_name, g_CEntity[index].ent_maxuses-g_CEntity[index].ent_uses);
#endif

        RefreshHud();
        AddClientScore(activator, 3);
        
        return Plugin_Continue;
    }
    else if(g_CEntity[index].ent_mode == 4 && g_CEntity[index].ent_uses < g_CEntity[index].ent_maxuses && g_CEntity[index].ent_cooldowntime <= -1)
    {
        g_CEntity[index].ent_cooldowntime = g_CEntity[index].ent_cooldown;
        g_CEntity[index].ent_uses++;

#if defined USE_TRANSLATIONS
        tChatTeam(g_CEntity[index].ent_team, true, "%t", "used ent and cd maxuses", activator, g_CEntity[index].ent_name, g_CEntity[index].ent_cooldown, g_CEntity[index].ent_maxuses-g_CEntity[index].ent_uses);
#else
        ChatTeam(g_CEntity[index].ent_team, true, "\x0C%N\x01使用了神器\x04%s\x01[\x04CD\x01:\x07%ds\x01|\x04剩余\x01:\x07%d\x04次\x01]", activator, g_CEntity[index].ent_name, g_CEntity[index].ent_cooldown, g_CEntity[index].ent_maxuses-g_CEntity[index].ent_uses);
#endif
        
        RefreshHud();
        AddClientScore(activator, 5);

        return Plugin_Continue;
    }
    else if(g_CEntity[index].ent_mode == 5 && g_CEntity[index].ent_cooldowntime <= -1)
    {
#if defined USE_TRANSLATIONS
        tChatTeam(g_CEntity[index].ent_team, true, "%t", "used ent and times cd", activator, g_CEntity[index].ent_name, g_CEntity[index].ent_maxuses-g_CEntity[index].ent_uses);
#else
        ChatTeam(g_CEntity[index].ent_team, true, "\x0C%N\x01使用了神器\x04%s\x01[\x04使用%d次后冷却\x01]", activator, g_CEntity[index].ent_name, g_CEntity[index].ent_maxuses-g_CEntity[index].ent_uses);
#endif

        g_CEntity[index].ent_uses++;
        
        if(g_CEntity[index].ent_uses >= g_CEntity[index].ent_maxuses)
        {
#if defined USE_TRANSLATIONS
            tChatTeam(g_CEntity[index].ent_team, true, "%t", "used ent and used times into cd", g_CEntity[index].ent_name, g_CEntity[index].ent_cooldown);
#else
            ChatTeam(g_CEntity[index].ent_team, true, "神器\x04%s\x01[\x04CD\x01:\x07%d\x04秒\x01]", g_CEntity[index].ent_name, g_CEntity[index].ent_cooldown);
#endif

            g_CEntity[index].ent_cooldowntime = g_CEntity[index].ent_cooldown;
            g_CEntity[index].ent_uses = 0;
        }

        RefreshHud();
        AddClientScore(activator, 3);
        
        return Plugin_Continue;
    }

    return Plugin_Handled;
}

public MRESReturn Event_AcceptInput(int pThis, Handle hReturn, Handle hParams)
{
    if(!IsValidEntity(pThis))
        return MRES_Ignored;
    
    char classname[32];
    GetEntityClassname(pThis, classname, 32);

    char command[128];
    DHookGetParamString(hParams, 1, command, 128);
    //PrintToServer("Event_AcceptInput pThis -> %d.%s -> %s", pThis, classname, command);

    // Tested on ze_sandstorm_go_v1_3
    if(strcmp(classname, "func_button") == 0)
    {
        if(strcmp(command, "Lock", false) == 0)
        {
            int index = g_PreConf.Button.FindValue(GetEntityHammerID(pThis));
            if(index > -1)
                g_PreConf.Locked.Set(index, GetGameTime());
        }
        else if(strcmp(command, "Unlock", false) == 0)
        {
            int index = g_PreConf.Button.FindValue(GetEntityHammerID(pThis));
            if(index > -1)
            {
                float locked = g_PreConf.Locked.Get(index);
                if(locked > 0.0)
                {
                    float cooldown = GetGameTime() - locked;
                    SavePreConfigs(g_PreConf.Weapon.Get(index), cooldown);
                    g_PreConf.Button.Set(index, -1);
                }
            }
        }
    }

    return MRES_Ignored;
}

public Action Timer_Cooldowns(Handle timer)
{
    if(!g_bConfigLoaded)
    {
        g_tCooldown = null;
        return Plugin_Stop;
    }

    for(int index = 0; index < MAXPLAYERS; index++)
        g_bHasEnt[index] = false;

    for(int index = 0; index < g_iEntCounts; index++)
        if(g_CEntity[index].ent_cooldowntime >= 0)
            g_CEntity[index].ent_cooldowntime--;

    RefreshHud();

    return Plugin_Continue;
}

static void RefreshHud()
{
    strcopy(g_szGlobalHud[ZOMBIE], 4096, "[!ehud]:");
    strcopy(g_szGlobalHud[HUMANS], 4096, "[!ehud]:");

    for(int index = 0; index < g_iEntCounts; index++)
    {
        CountdownMessage(index);
        BuildHUDandScoreboard(index);
    }

    if(strcmp(g_szGlobalHud[ZOMBIE], "[!ehud]:") == 0)
        g_szGlobalHud[ZOMBIE][0] = '\0';
        //Format(g_szGlobalHud[ZOMBIE], 4096, "%s\n", g_szGlobalHud[ZOMBIE]);

    if(strcmp(g_szGlobalHud[HUMANS], "[!ehud]:") == 0)
        g_szGlobalHud[HUMANS][0] = '\0';
        //Format(g_szGlobalHud[HUMANS], 4096, "%s\n", g_szGlobalHud[HUMANS]);

    SetHudTextParams(0.160500, 0.099000, 2.0, 57, 197, 187, 255, 0, 30.0, 0.0, 0.0);

    for(int client = 1; client <= MaxClients; ++client)
        if(IsClientInGame(client) && !g_bEntHud[client])
            ShowHudText(client, 5, IsInfector(client) ? g_szGlobalHud[ZOMBIE] : g_szGlobalHud[HUMANS]);
}

static void CountdownMessage(int index)
{
    if(g_CEntity[index].ent_mode == 4 || g_CEntity[index].ent_mode == 2 || g_CEntity[index].ent_mode == 5)
    {
        if(ClientIsAlive(g_CEntity[index].ent_ownerid))
        {
            if(g_bEntHud[g_CEntity[index].ent_ownerid])
            {
                if(g_CEntity[index].ent_cooldowntime > 0)
                {
                    SetHudTextParams(-1.0, 0.05, 2.0, 205, 173, 0, 255, 0, 30.0, 0.0, 0.0);
                    ShowHudText(g_CEntity[index].ent_ownerid, 5, ">>> [%s] :  %ds <<< ", g_CEntity[index].ent_name, g_CEntity[index].ent_cooldowntime);
                }
                else
                {
                    SetHudTextParams(-1.0, 0.05, 2.0, 0, 255, 0, 255, 0, 30.0, 0.0, 0.0);
#if defined USE_TRANSLATIONS
                    ShowHudText(g_CEntity[index].ent_ownerid, 5, "%t[%s]%t", "Item", g_CEntity[index].ent_name, "Ready");
#else
                    ShowHudText(g_CEntity[index].ent_ownerid, 5, "神器[%s]就绪", g_CEntity[index].ent_name);
#endif
                }
            }
        }
        else if(g_CEntity[index].ent_cooldowntime == 1)
        {
            SMUtils_SkipNextChatCS();
#if defined USE_TRANSLATIONS
            tChatTeam(g_CEntity[index].ent_team, true, "%t", "cooldown end no owner", g_CEntity[index].ent_name);
#else        
            ChatTeam(g_CEntity[index].ent_team, true, "\x07%s\x04冷却时间已结束\x01[\x07无人使用\x01]", g_CEntity[index].ent_name);
#endif
            CreateTimer(1.1, Timer_RefreshGlow, index);
        }
    }
    else if(ClientIsValid(g_CEntity[index].ent_ownerid))
    {
        if(g_CEntity[index].ent_mode == 3 && g_CEntity[index].ent_uses >= g_CEntity[index].ent_maxuses)
        {
            if(g_bEntHud[g_CEntity[index].ent_ownerid])
            {
                SetHudTextParams(-1.0, 0.05, 2.0, 255, 0, 0, 233, 0, 30.0, 0.0, 0.0);
#if defined USE_TRANSLATIONS
                ShowHudText(g_CEntity[index].ent_ownerid, 5, "%t[%s]%t", "Item", g_CEntity[index].ent_name, "Deplete");
#else
                ShowHudText(g_CEntity[index].ent_ownerid, 5, "神器[%s]耗尽", g_CEntity[index].ent_name);
#endif
            }
        }
        else
        {
            if(g_bEntHud[g_CEntity[index].ent_ownerid])
            {
                SetHudTextParams(-1.0, 0.05, 2.0, 0, 255, 0, 255, 0, 30.0, 0.0, 0.0);
#if defined USE_TRANSLATIONS
                ShowHudText(g_CEntity[index].ent_ownerid, 5, "%t[%s]%t", "Item", g_CEntity[index].ent_name, "Ready");
#else
                ShowHudText(g_CEntity[index].ent_ownerid, 5, "神器[%s]就绪", g_CEntity[index].ent_name);
#endif
            }
        }
    }
}

public Action Timer_RefreshGlow(Handle timer, int index)
{
    if(ClientIsAlive(g_CEntity[index].ent_ownerid))
        return Plugin_Stop;

    RemoveWeaponGlow(index);
    //PrintToServer("[Timer_RefreshGlow] -> %d", index);
    RequestFrame(SetWeaponGlow, index);

    return Plugin_Stop;
}

static void BuildHUDandScoreboard(int index)
{
    bool alive = ClientIsAlive(g_CEntity[index].ent_ownerid);
    if (alive)
        g_bHasEnt[g_CEntity[index].ent_ownerid] = true;

    if(!g_CEntity[index].ent_displayhud)
        return;

    char szClantag[32], szGameText[256], szName[16];
    strcopy(szClantag, 32, g_CEntity[index].ent_short);

    if(alive)
    {
        GetClientName(g_CEntity[index].ent_ownerid, szName, 16);

        switch(g_CEntity[index].ent_mode)
        {
            case 1: FormatEx(szGameText, 256, "%s[R]: %s", g_CEntity[index].ent_name, szName);
            case 2:
            {
                if(g_CEntity[index].ent_cooldowntime <= 0)
                    FormatEx(szGameText, 256, "%s[R]: %s", g_CEntity[index].ent_name, szName);
                else
                    FormatEx(szGameText, 256, "%s[%d]: %s", g_CEntity[index].ent_name, g_CEntity[index].ent_cooldowntime, szName);
            }
            case 3:
            {
                if(g_CEntity[index].ent_maxuses > g_CEntity[index].ent_uses)
                    FormatEx(szGameText, 256, "%s[R]: %s", g_CEntity[index].ent_name, szName);
                else
                    FormatEx(szGameText, 256, "%s[N]: %s", g_CEntity[index].ent_name, szName);
            }
            case 4:
            {
                if(g_CEntity[index].ent_cooldowntime <= 0)
                {
                    if(g_CEntity[index].ent_maxuses > g_CEntity[index].ent_uses)
                        FormatEx(szGameText, 256, "%s[R]: %s", g_CEntity[index].ent_name, szName);
                    else
                        FormatEx(szGameText, 256, "%s[N]: %s", g_CEntity[index].ent_name, szName);
                }
                else
                    FormatEx(szGameText, 256, "%s[%d]: %s", g_CEntity[index].ent_name, g_CEntity[index].ent_cooldowntime, szName);
            }
            case 5:
            {
                if(g_CEntity[index].ent_cooldowntime <= 0)
                    FormatEx(szGameText, 256, "%s[R]: %s", g_CEntity[index].ent_name, szName);
                else
                    FormatEx(szGameText, 256, "%s[%d]: %s", g_CEntity[index].ent_name, g_CEntity[index].ent_cooldowntime, szName);
            }
            default: FormatEx(szGameText, 256, "%s[R]: %s", g_CEntity[index].ent_name, szName);
        }

        CS_SetClientClanTag(g_CEntity[index].ent_ownerid, szClantag);
        Format(g_szGlobalHud[g_CEntity[index].ent_team - 2], 4096, "%s\n%s", g_szGlobalHud[g_CEntity[index].ent_team - 2], szGameText);
    }
}

public Action Command_entWatch(int client, int args)
{
    // ....
    // Todo
    // ....
    Command_Stats(client, 0);
    return Plugin_Handled;
}

public Action Command_Stats(int client, int args)
{
    if(!AreClientCookiesCached(client))
    {
#if defined USE_TRANSLATIONS
        Chat(client, "%T", "ent data not cached", client);
#else
        Chat(client, "请等待你的数据加载完毕...");
#endif
        return Plugin_Handled;
    }

    if(!g_bBanned[client])
    {
#if defined USE_TRANSLATIONS
        Chat(client, "%T", "ent not ban", client);
#else
        Chat(client, "你的神器信用等级\x04良好\x01...");
#endif
        return Plugin_Handled;
    }

    int expired = -1;
    char buffer_admin[32], buffer_timer[32];
    if(!GetEBanInfo(client, buffer_admin, 32, expired))
    {
#if defined USE_TRANSLATIONS
        Chat(client, "%T", "ent data not cached", client);
#else
        Chat(client, "请等待你的数据加载完毕...");
#endif
        return Plugin_Handled;
    }
    FormatTime(buffer_timer, 32, "%Y/%m/%d - %H:%M:%S", expired);

#if defined USE_TRANSLATIONS
    Chat(client, "%T", "ent ban info", client, buffer_admin, buffer_timer);
#else
    Chat(client, "你的神器被 \x0C%N\x01 封禁了 [到期时间 \x07%s\x01]", buffer_admin, buffer_timer);
#endif

    return Plugin_Handled;
}

public Action Command_DisplayHud(int client, int args)
{
    if((g_pClientPrefs && !AreClientCookiesCached(client)) || (g_pfysOptions && !Opts_IsClientLoaded(client)))
    {
#if defined USE_TRANSLATIONS
        Chat(client, "%T", "ent data not cached", client);
#else
        Chat(client, "请等待你的数据加载完毕...");
#endif
        return Plugin_Handled;
    }

    g_bEntHud[client] = !g_bEntHud[client];
    SetHudState(client);
    Chat(client, "entWatch HUD is \x02%s\x01!", g_bEntHud[client] ? "\x07Off\x01" : "\x04On\x01");

    return Plugin_Handled;
}

public Action Command_Restrict(int client, int args)
{
    if(!client)
        return Plugin_Handled;
    
    DisplayMenu_Restrict(client);

    return Plugin_Handled;
}

static void DisplayMenu_Restrict(int client)
{
    Menu menu = new Menu(MenuHandler_Ban);
    
    menu.SetTitle("[entWatch]  Ban Menu\n ");

    char m_szId[8], m_szName[64];
    
    for(int x = 1; x <= MaxClients; ++x)
    {
        if(!IsClientInGame(x) || g_bBanned[x])
            continue;

        FormatEx(m_szId,    8, "%d", GetClientUserId(x));
        FormatEx(m_szName, 64, "  %N (%s)", x, m_szId);

        menu.AddItem(m_szId, m_szName);
    }

    if(menu.ItemCount < 1)
    {
        Chat(client, "No player in target list");
        delete menu;
        return;
    }

    menu.Display(client, 30);
}

public int MenuHandler_Ban(Menu menu, MenuAction action, int client, int itemNum) 
{
    if(action == MenuAction_Select) 
    {
        char info[32];
        menu.GetItem(itemNum, info, 32);
        BuildBanLengthMenu(client, info);
    }
    else if(action == MenuAction_End)
        delete menu;
}

static void BuildBanLengthMenu(int client, const char[] target)
{
    int m = GetClientOfUserId(StringToInt(target));
    if(!m)
    {
        Chat(client, "Target client disconnected.");
        return;
    }

    Menu menu = new Menu(MenuHandler_Time);
    
    menu.SetTitle("[entWatch]  Select Time\n Target: %N\n ", m);

    menu.AddItem(target, "", ITEMDRAW_IGNORE);

    menu.AddItem("1",   "1 Hour");
    menu.AddItem("24",  "1 Day");
    menu.AddItem("168", "1 Week");
    menu.AddItem("0",   "Permanent");

    menu.Display(client, 30);
}

public int MenuHandler_Time(Menu menu, MenuAction action, int client, int itemNum) 
{
    if(action == MenuAction_Select) 
    {
        char info[32];
        menu.GetItem(0, info, 32);
        int target = StringToInt(info);

        menu.GetItem(itemNum, info, 32);
        BanClientEnt(client, GetClientOfUserId(target), StringToInt(info));
    }
    else if(action == MenuAction_End)
        delete menu;
}

static void BanClientEnt(int client, int target, int time)
{
    if(!ClientIsValid(target))
    {
        Chat(client, "Target is not in server");
        return;
    }

    if(g_bHasEnt[target])
    {
        for(int index = 0; index < MAXENT; ++index)
            if(g_CEntity[index].ent_ownerid == client)
            {
                g_CEntity[index].ent_ownerid = -1;

                int weapon_index_1 = GetPlayerWeaponSlot(target, 1);
                int weapon_index_2 = GetPlayerWeaponSlot(target, 2);
                
                int weapon = EntRefToEntIndex(g_CEntity[index].ent_weaponref);
                
                if(IsValidEdict(weapon))
                {
                    if(weapon_index_1 == weapon || weapon_index_2 == weapon)
                    {
                        SDKHooks_DropWeapon(target, weapon);
                        RequestFrame(SetWeaponGlow, index);

#if defined USE_TRANSLATIONS
                        tChatTeam(g_CEntity[index].ent_team, true, "%t", "ent dropped", g_CEntity[index].ent_name);
#else
                        ChatTeam(g_CEntity[index].ent_team, true, "\x04%s\x0C已掉落", g_CEntity[index].ent_name);
#endif

                        Call_StartForward(g_Forward.OnDropped);
                        Call_PushCell(client);
                        Call_PushCell(DR_OnBanned);
                        Call_PushString(g_CEntity[index].ent_name);
                        Call_Finish();
                    }
                }
            }

        SetClientDefault(client);
    }
    
    char szTime[32];
    if(time == 0)
        strcopy(szTime, 32, "0");
    else
        FormatEx(szTime, 32, "%d", GetTime()+60*time);
    
    char szAdmin[32];
    GetClientName(client, szAdmin, 32);
    EBanClient(target, GetTime()+60*time, szAdmin);

#if defined USE_TRANSLATIONS
    switch(time)
    {
        case   0: FormatEx(szTime, 32, "%T", "permanent", client);
        case   1: FormatEx(szTime, 32, "%T", "1 hour",    client);
        case  24: FormatEx(szTime, 32, "%T", "1 day",     client);
        case 168: FormatEx(szTime, 32, "%T", "1 week",    client);
    }
#else
    switch(time)
    {
        case   0: strcopy(szTime, 32, "永久");
        case   1: strcopy(szTime, 32, "1时");
        case  24: strcopy(szTime, 32, "1天");
        case 168: strcopy(szTime, 32, "1周");
    }
#endif

    Call_StartForward(g_Forward.OnBanned);
    Call_PushCell(target);
    Call_Finish();

#if defined USE_TRANSLATIONS
    tChatAll("%t", "ban ent", target, client, szTime);
#else
    ChatAll("小朋友\x07%N\x01因为乱玩神器,被dalao\x04%N\x07ban神器[%s]", target, client, szTime);
#endif

    if(g_pfysAdminSys)
    Admin_LogAction(client, "EBan", "玩家 [%L]  时长 [%s]", target, szTime);
    else
    LogAction(client, -1, "%L ban %L => %s [entWatch]", client, target, szTime);
}

public Action Command_Unrestrict(int client, int args)
{
    if(!client)
        return Plugin_Handled;
    
    DisplayMenu_Unrestrict(client);

    return Plugin_Handled;
}

static void DisplayMenu_Unrestrict(int client)
{
    Menu menu = new Menu(MenuHandler_Unban);

    menu.SetTitle("[entWatch]  UnBan\n ");

    char m_szId[8], m_szName[64];

    for(int x = 1; x <= MaxClients; ++x)
    {
        if(!IsClientInGame(x))
            continue;
        
        if(!g_bBanned[x])
            continue;

        FormatEx(m_szId,    8, "%d", GetClientUserId(x));
        FormatEx(m_szName, 64, "  %N (%s)", x, m_szId);
        
        menu.AddItem(m_szId, m_szName);
    }

    if(menu.ItemCount < 1)
    {
        Chat(client, "No player in target list");
        delete menu;
        return;
    }

    menu.Display(client, 30);
}

public int MenuHandler_Unban(Menu menu, MenuAction action, int client, int itemNum) 
{
    if(action == MenuAction_Select) 
    {
        char info[32];
        menu.GetItem(itemNum, info, 32);

        int target = GetClientOfUserId(StringToInt(info));

        UnestrictClientEnt(client, target);
    }
    else if(action == MenuAction_End)
        delete menu;
}

static void UnestrictClientEnt(int client, int target)
{
    if(!IsClientInGame(client))
        return;
    
    if(!ClientIsValid(target))
    {
        Chat(client, "Target is not in server.");
        return;
    }

    EunbanClient(target);

#if defined USE_TRANSLATIONS
    tChatAll("%t", "unban ent", target, client);
#else
    ChatAll("小朋友\x07%N\x01的\x07ban神器\x01被dalao\x04%N\x01解开了", target, client);
#endif

    if(g_pfysAdminSys)
    Admin_LogAction(client, "EUnban", "玩家 [%L]", target);
    else
    LogAction(client, -1, "%L unban %L [entWatch]", client, target);

    Call_StartForward(g_Forward.OnUnban);
    Call_PushCell(target);
    Call_Finish();
}

public Action Command_Transfer(int client, int args)
{
    if(!g_bConfigLoaded || !client)
        return Plugin_Handled;

    DisplayMenu_Transfer(client);
    
    return Plugin_Handled;
}

static void DisplayMenu_Transfer(int client)
{
    Menu menu = new Menu(MenuHandler_Transfer);
    
    menu.SetTitle("[entWatch]  Transfer\n ");

    char m_szId[8], m_szName[64];
    
    for(int x = 1; x <= MaxClients; ++x)
    {
        if(!IsClientInGame(x))
            continue;
        
        if(!g_bHasEnt[x])
            continue;

        if(g_iTeam[client] != g_iTeam[x])
            continue;

        FormatEx(m_szId,    8, "%d", GetClientUserId(x));
        FormatEx(m_szName, 64, "  %N (%s)", x, m_szId);
        
        menu.AddItem(m_szId, m_szName);
    }

    if(menu.ItemCount < 1)
    {
        Chat(client, "No one pickup item.");
        delete menu;
        return;
    }

    menu.Display(client, 30);
}

public int MenuHandler_Transfer(Menu menu, MenuAction action, int client, int itemNum) 
{
    if(action == MenuAction_Select) 
    {
        char info[32];
        menu.GetItem(itemNum, info, 32);
        
        int target = GetClientOfUserId(StringToInt(info));
        
        TransferClientEnt(client, target);
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }
}

static void TransferClientEnt(int client, int target, bool autoTransfer = false)
{
    if(!ClientIsAlive(target))
    {
        Chat(client, "Target is invalid.");
        return;
    }

    for(int index = 0; index < MAXENT; ++index)
        if(g_CEntity[index].ent_ownerid == target)
        {
            int weapon = EntRefToEntIndex(g_CEntity[index].ent_weaponref);
            
            char buffer_classname[64];
            GetEdictClassname(weapon, buffer_classname, 64);

            //if(g_CEntity[index].ent_buttonid != -1)
            //    SDKUnhook(g_CEntity[index].ent_buttonid, SDKHook_Use, Event_ButtonUse);
            
            SDKHooks_DropWeapon(target, weapon);
            GivePlayerItem(target, buffer_classname);
            EquipPlayerWeapon(client, weapon);

            if(!autoTransfer)
            {

#if defined USE_TRANSLATIONS
                tChatAll("%t", "transfer ent", client, target, g_CEntity[index].ent_name);
#else
                ChatAll("\x0C%N\x01拿走了\x0C%N\x01手上的神器[\x04%s\x01]", client, target, g_CEntity[index].ent_name);
#endif
                if(g_pfysAdminSys)
                Admin_LogAction(client, "ETransfer", "神器 [%s]  玩家 [%L]", g_CEntity[index].ent_name, target);
                else
                LogAction(client, -1, "%L transfer %L item %s [entWatch]", client, target, g_CEntity[index].ent_name);
            }
            else
            {
#if defined USE_TRANSLATIONS
                tChatAll("%t", "autotransfer ent", target, client, g_CEntity[index].ent_name);
#else
                ChatAll("\x0C%N\x01的遗志由\x0C%N\x01来继承: [\x04%s\x01]", target, client, g_CEntity[index].ent_name);
#endif
            }

            RemoveWeaponGlow(index);

            //if(g_CEntity[index].ent_buttonid != -1)
            //    SDKHookEx(g_CEntity[index].ent_buttonid, SDKHook_Use, Event_ButtonUse);

            if(g_CEntity[index].ent_hasfiltername)
                DispatchKeyValue(client, "targetname", g_CEntity[index].ent_filtername);

#if defined USE_WALLHACK
            CreateIcon(client);
#endif 

            g_iScores[client] = 99966 - CS_GetClientContributionScore(client);
            g_fPickup[client] = GetGameTime();

            int leader = g_pLeader3Sys ? Leader_CurrentLeader() : -1;
            if (leader != client)
            CS_SetClientContributionScore(client, 99966);

            Call_StartForward(g_Forward.OnDropped);
            Call_PushCell(target);
            Call_PushCell(DR_OnTransfer);
            Call_PushString(g_CEntity[index].ent_name);
            Call_Finish();

            Call_StartForward(g_Forward.OnPicked);
            Call_PushCell(client);
            Call_PushString(g_CEntity[index].ent_name);
            Call_Finish();

            Call_StartForward(g_Forward.OnTransfered);
            Call_PushCell(client);
            Call_PushCell(target);
            Call_PushString(g_CEntity[index].ent_name);
            Call_Finish();
        }

    g_bHasEnt[client] = true;
    g_bHasEnt[target] = false;

    SetClientDefault(client);

    RefreshHud();
}

static int AutoTarget(int source)
{
    for(int client = 0; client <= MaxClients; ++client)
    {
        if(!ClientIsAlive(client) || g_iTeam[source] != g_iTeam[client] || g_bHasEnt[client])
            continue;

        if (GetUserAdmin(client) == INVALID_ADMIN_ID)
            continue;

        return client;
    }
    return -1;
}

static void LoadConfig()
{
    StopTimer(g_tCooldown);
    
    g_iEntCounts = 0;
    g_bConfigLoaded = false;

    char path[128];
    GetCurrentMap(path, 128);
    Format(path, 128, "cfg/sourcemod/map-entwatch/%s.cfg", path);

    if(!FileExists(path))
    {
        LogMessage("Loading %s but does not exists", path);
        return;
    }

    KeyValues kv = new KeyValues("entities");

    kv.ImportFromFile(path);
    kv.Rewind();
    
    ImportKeyValies(kv);

    delete kv;

    if(g_iEntCounts)
    {
        g_bConfigLoaded = true;
        LogMessage("Load %s successful", path);
        g_tCooldown = CreateTimer(1.0, Timer_Cooldowns, _, TIMER_REPEAT);
    }
    else LogError("Loaded %s but not found any data", path);
}

static void ImportKeyValies(KeyValues kv)
{
    if(!kv.GotoFirstSubKey())
        return;
    
    char temp[32];
    int buffer_amount;

    do
    {
        kv.GetString("maxamount", temp, 32);
        buffer_amount = StringToInt(temp);

        if(buffer_amount == 0)
            buffer_amount = 1;

        for(int i = 0; i < buffer_amount; i++)
        {
            kv.GetString("name", temp, 32);
            strcopy(g_CEntity[g_iEntCounts].ent_name, 32, temp);

            kv.GetString("shortname", temp, 32);
            strcopy(g_CEntity[g_iEntCounts].ent_short, 32, temp);
            
            kv.GetString("buttonclass", temp, 32);
            strcopy(g_CEntity[g_iEntCounts].ent_buttonclass, 32, temp);

            kv.GetString("filtername", temp, 32);
            strcopy(g_CEntity[g_iEntCounts].ent_filtername, 32, temp);
            
            kv.GetString("hasfiltername", temp, 32);
            g_CEntity[g_iEntCounts].ent_hasfiltername = (strcmp(temp, "true", false) == 0);
            
            kv.GetString("hammerid", temp, 32);
            g_CEntity[g_iEntCounts].ent_hammerid = StringToInt(temp);

            kv.GetString("mode", temp, 32);
            g_CEntity[g_iEntCounts].ent_mode = StringToInt(temp);

            kv.GetString("maxuses", temp, 32);
            g_CEntity[g_iEntCounts].ent_maxuses = StringToInt(temp);
            
            kv.GetString("startcd", temp, 32);
            g_CEntity[g_iEntCounts].ent_startcd = StringToInt(temp);

            kv.GetString("cooldown", temp, 32);
            g_CEntity[g_iEntCounts].ent_cooldown = StringToInt(temp);

            kv.GetString("glow", temp, 32, "true");
            g_CEntity[g_iEntCounts].ent_weaponglow = (strcmp(temp, "true", false) == 0);

            kv.GetString("hud", temp, 32, "true");
            g_CEntity[g_iEntCounts].ent_displayhud = (strcmp(temp, "true", false) == 0);

            kv.GetString("autotrasfer", temp, 32, "true");
            g_CEntity[g_iEntCounts].ent_autotrasfer = (strcmp(temp, "true", false) == 0);

            g_iEntCounts++;
            
            if(g_iEntCounts == MAXENT)
            {
                LogError("Entities array is full. current: %d  limit: %d", g_iEntCounts, MAXENT);
                return;
            }
        }
    }
    while(kv.GotoNextKey());
}

static void CheckClientKnife(int client)
{
    StopTimer(
    g_tKnife[client]);
    g_tKnife[client] = CreateTimer(0.3, Timer_CheckKnife, client);
}

public Action Timer_CheckKnife(Handle timer, int client)
{
    g_tKnife[client] = INVALID_HANDLE;

    if(!ClientIsAlive(client))
        return Plugin_Stop;

    if(GetPlayerWeaponSlot(client, 2) == -1) 
        GivePlayerItem(client, "weapon_knife");

    return Plugin_Stop;
}

static int GetEntityHammerID(int entity)
{
    return GetEntProp(entity, Prop_Data, "m_iHammerID");
}

static int GetEntityTargetName(int entity, char[] buffer, int size)
{
    return GetEntPropString(entity, Prop_Data, "m_iName", buffer, size);
}

static int GetEntityParentName(int entity, char[] buffer, int size)
{
    return GetEntPropString(entity, Prop_Data, "m_iParent", buffer, size);
}

static int FindIndexByHammerId(int hammerid)
{
    for(int index = 0; index < g_iEntCounts; index++)
        if(g_CEntity[index].ent_hammerid == hammerid)
            return index;

    return -1;
}

static int FindIndexByButton(int button)
{
    for(int index = 0; index < g_iEntCounts; index++)
        if(g_CEntity[index].ent_buttonid != -1 && g_CEntity[index].ent_buttonid == button)
            return index;

    return -1;
}

static int GetGlowType(int index)
{
    if(!g_CEntity[index].ent_pickedup)
        return 0;

    switch(g_CEntity[index].ent_mode)
    {
        case 0: return 1;
        case 1: return 1;
        case 2: return (g_CEntity[index].ent_cooldowntime <= 0) ? 1 : 2;
        case 3: return (g_CEntity[index].ent_uses < g_CEntity[index].ent_maxuses) ? 1 : 3;
        case 4: return (g_CEntity[index].ent_uses < g_CEntity[index].ent_maxuses && g_CEntity[index].ent_cooldowntime <= 0) ? 1 : ((g_CEntity[index].ent_uses >= g_CEntity[index].ent_maxuses) ? 3 : 2);
        case 5: return (g_CEntity[index].ent_cooldowntime <= 0) ? 1 : 2;
    }

    return 1;
}

static void SetWeaponGlow(int index)
{
    if(!g_CEntity[index].ent_weaponglow)
        return;

    if(IsValidEdict(EntRefToEntIndex(g_CEntity[index].ent_glowref)))
    {
        //PrintToServer("[SetWeaponGlow] Blocked -> %d -> by Ref", index);
        return;
    }

    float origin[3];
    float angle[3];
    char model[256];

    int weapon = EntRefToEntIndex(g_CEntity[index].ent_weaponref);
    
    if(!IsValidEdict(weapon))
    {
        //PrintToServer("[SetWeaponGlow] Blocked -> %d -> by weapon", index);
        return;
    }

    GetEntPropVector(weapon, Prop_Send, "m_vecOrigin", origin);
    GetEntPropVector(weapon, Prop_Send, "m_angRotation", angle);

    float fForward[3];
    float fRight[3];
    float fUp[3];
    float fOffset[3] = {0.0, -5.0, 0.0};
    GetAngleVectors(angle, fForward, fRight, fUp);
    origin[0] += fRight[0]*fOffset[0]+fForward[0]*fOffset[1]+fUp[0]*fOffset[2];
    origin[1] += fRight[1]*fOffset[0]+fForward[1]*fOffset[1]+fUp[1]*fOffset[2];
    origin[2] += fRight[2]*fOffset[0]+fForward[2]*fOffset[1]+fUp[2]*fOffset[2];

    GetEntPropString(weapon, Prop_Data, "m_ModelName", model, 256);
    ReplaceString(model, 256, "_dropped", "", false);

    int glow = CreateEntityByName("prop_dynamic_glow");

    if(glow == -1)
        return;

    DispatchKeyValue(glow, "model",                 model);
    DispatchKeyValue(glow, "disablereceiveshadows", "1");
    DispatchKeyValue(glow, "disableshadows",        "1");
    DispatchKeyValue(glow, "solid",                 "0");
    DispatchKeyValue(glow, "spawnflags",            "256");

    DispatchSpawn(glow);

    SetEntProp(glow, Prop_Send, "m_CollisionGroup", 11);
    SetEntProp(glow, Prop_Send, "m_bShouldGlow",    true, true);

    SetEntPropFloat(glow, Prop_Send, "m_flGlowMaxDist", 100000.0);

    SetEntityRenderMode(glow,  RENDER_TRANSCOLOR);
    SetEntityRenderColor(glow, 255, 50, 150, 0);

    switch(GetGlowType(index))
    {
        case 0 : SetGlowColor(glow, 57,  197, 187);
        case 1 : SetGlowColor(glow, 0,   255, 0);
        case 2 : SetGlowColor(glow, 255,  50, 150);
        case 3 : SetGlowColor(glow, 255,   0, 0);
        default: SetGlowColor(glow, 255,  50, 150);
    }

    TeleportEntity(glow, origin, angle, NULL_VECTOR);

    SetEntityParent(glow, weapon);
    
    g_iEntTeam[glow] = g_CEntity[index].ent_team;

    g_CEntity[index].ent_glowref = EntIndexToEntRef(glow);

    SDKHookEx(glow, SDKHook_SetTransmit, Event_SetTransmit);
}

static void RemoveWeaponGlow(int index)
{
    if(!g_CEntity[index].ent_weaponglow)
        return;

    if(g_CEntity[index].ent_glowref != INVALID_ENT_REFERENCE)
    {
        int entity = EntRefToEntIndex(g_CEntity[index].ent_glowref);

        if(IsValidEdict(entity))
            AcceptEntityInput(entity, "KillHierarchy");

        g_CEntity[index].ent_glowref = INVALID_ENT_REFERENCE;
    }
}

static void SetGlowColor(int entity, int r, int g, int b)
{
    int colors[4];
    colors[0] = r;
    colors[1] = g;
    colors[2] = b;
    colors[3] = 255;
    SetVariantColor(colors);
    AcceptEntityInput(entity, "SetGlowColor");
}

static void AddClientScore(int client, int score)
{
    int leader = g_pLeader3Sys ? Leader_CurrentLeader() : -1;
    if (leader != client)
    CS_SetClientContributionScore(client, CS_GetClientContributionScore(client) + score);
}

#if defined USE_WALLHACK
static void CreateIcon(int client)
{
    if(!ClientIsAlive(client))
        return;

    ClearIcon(client);

    float fOrigin[3];
    GetClientAbsOrigin(client, fOrigin);                
    fOrigin[2] = fOrigin[2] + 88.5;

    int iEnt = CreateEntityByName("env_sprite");
 
    DispatchKeyValue(iEnt, "model",         "materials/maoling/sprites/ze/entwatch_2017.vmt");
    DispatchKeyValue(iEnt, "classname",     "env_sprite");
    DispatchKeyValue(iEnt, "spawnflags",    "1");
    DispatchKeyValue(iEnt, "scale",         "0.01");
    DispatchKeyValue(iEnt, "rendermode",    "1");
    DispatchKeyValue(iEnt, "rendercolor",   "255 255 255");
    
    DispatchSpawn(iEnt);
    
    TeleportEntity(iEnt, fOrigin, NULL_VECTOR, NULL_VECTOR);

    SetEntityParent(iEnt, client);
    
    g_iEntTeam[iEnt] = g_iTeam[client];

    g_iIconRef[client] = EntIndexToEntRef(iEnt);

    SDKHookEx(iEnt, SDKHook_SetTransmit, Event_SetTransmit);
}

static void ClearIcon(int client)
{
    if(g_iIconRef[client] != INVALID_ENT_REFERENCE)
    {
        int iEnt = EntRefToEntIndex(g_iIconRef[client]);
        if(IsValidEdict(iEnt))
            AcceptEntityInput(iEnt, "KillHierarchy");
    }

    g_iIconRef[client] = INVALID_ENT_REFERENCE;
}
#endif 

static bool IsInfector(int client)
{
    if(!IsPlayerAlive(client))
        return true;

    if(g_pZombieEscape)
        return (ZE_IsInfector(client) || ZE_IsAvenger(client));

    if(g_pZombieReload)
        return ZR_IsClientZombie(client);

    return (g_iTeam[client] == CS_TEAM_T);
}

#if defined AUTO_HIDERADAR
static bool CheckMapRadar(const char[] map)
{
    char txt[128];
    FormatEx(txt, 128, "resource/overviews/%s.txt", map);

    if (!FileExists(txt, true))
    {
        LogError("Failed to find [%s].", txt);
        return false;
    }

    KeyValues kv = new KeyValues(map);
    if (!kv.ImportFromFile(txt))
    {
        delete kv;
        LogError("Failed to import [%s].", txt);
        return false;
    }

    char material[128];
    kv.GetString("material", material, 128, map);
    
    delete kv;

    char dds[128];
    FormatEx(dds, 128, "resource/%s", material);

    return FileExists(dds, true);
}
#endif
