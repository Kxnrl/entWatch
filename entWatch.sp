/******************************************************************/
/*                                                                */
/*                           entWatch                             */
/*                                                                */
/*                                                                */
/*  File:          entWatch.sp                                    */
/*  Description:   Notify players about entity interactions.      */
/*                                                                */
/*                                                                */
/*  Copyright (C) 2018  Kyle                                      */
/*  2018/05/08 20:13:14                                           */
/*                                                                */
/*  This code is licensed under the GPLv3 License.                */
/*                                                                */
/******************************************************************/


#pragma semicolon 1
#pragma newdecls required

#include <smutils>          //https://github.com/Kxnrl/sourcemod-utils
#include <cstrike>
#include <sdkhooks>
#include <clientprefs>
#include <entWatch>

#undef REQUIRE_EXTENSIONS
#include <dhooks>
#define REQUIRE_EXTENSIONS

#undef REQUIRE_PLUGIN
#include <ZombieEscape>
#include <zombiereloaded>
#define REQUIRE_PLUGIN

#define USE_TRANSLATIONS  // if load translations

#define PI_NAME "[CSGO] entWatch"
#define PI_AUTH "Kyle"
#define PI_DESC "Notify players about entity interactions."
#define PI_VERS "1.3.2"
#define PI_URLS "https://kxnrl.com"

public Plugin myinfo = 
{
    name        = PI_NAME,
    author      = PI_AUTH,
    description = PI_DESC,
    version     = PI_VERS,
    url         = PI_URLS
};


#define MAXENT 128
#define MAXPLY  65
#define ZOMBIE   0
#define HUMANS   1
#define GLOBAL   0
#define COOLDN   1

#define Pre_Button 0
#define Pre_Weapon 1
#define Pre_Locked 2

enum Entity
{
    String:ent_name[32],
    String:ent_short[32],
    String:ent_buttonclass[32],
    String:ent_filtername[32],
    bool:ent_hasfiltername,
    ent_ownerid,
    ent_hammerid,
    ent_buttonid,
    ent_weaponref,
    ent_glowref,
    ent_mode,               // 0 = No button, 1 = Spam protection only, 2 = Cooldowns, 3 = Limited uses, 4 = Limited uses with cooldowns, 5 = Cooldowns after multiple uses.
    ent_uses,
    ent_maxuses,
    ent_startcd,
    ent_cooldown,
    ent_cooldowntime,
    ent_team,               //  2 = Zombies , 3 = Humans
    bool:ent_displayhud,
    bool:ent_weaponglow,
    bool:ent_pickedup
}

enum Forward
{
    Handle:OnPick,
    Handle:OnPicked,
    Handle:OnDropped,
    Handle:OnUse,
    Handle:OnTransfered,
    Handle:OnBanned,
    Handle:OnUnban
}

enum Cookies
{
    Handle:Restricted,
    Handle:BanByAdmin,
    Handle:BanTLength,
    Handle:DisplayHud
}

static any g_EntArray[MAXENT][Entity];
static any g_Forward[Forward];
static any g_Cookies[Cookies];

static ArrayList g_aPreHammerId[3];

static Handle g_tRound         = null;
static Handle g_tKnife[MAXPLY] = null;
static Handle g_tCooldown      = null;

static int  g_iEntCounts      = MAXENT;
static int  g_iScores[MAXPLY] = {0, ...};
static int  g_iIconRef[MAXPLY] = {INVALID_ENT_REFERENCE, ...};

static bool g_bConfigLoaded    = false;
static bool g_bHasEnt[MAXPLY]  = false;
static bool g_bBanned[MAXPLY]  = false;
static bool g_bEntHud[MAXPLY]  = false;

static char g_szGlobalHud[2][2048];
static char g_szClantag[MAXPLY][32];

static float g_fPickup[MAXPLY] = {0.0, ...};

static bool g_pZombieEscape = false;
static bool g_pZombieReload = false;

static bool g_bLateload;

// DHook
static bool g_extDHook;
static Handle hAcceptInput;

static int g_iTeam[MAXPLY];
static int g_iEntTeam[2048];

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
        if(g_EntArray[i][ent_weaponref] == entref)
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
    HookEventEx("player_death",   Event_PlayerDeath,  EventHookMode_Post);
    HookEventEx("player_team",    Event_PlayerTeams,  EventHookMode_Post);

    g_Cookies[Restricted] = RegClientCookie("entwatch_restricted", "", CookieAccess_Private);
    g_Cookies[BanByAdmin] = RegClientCookie("entwatch_banbyadmin", "", CookieAccess_Private);
    g_Cookies[BanTLength] = RegClientCookie("entwatch_bantLength", "", CookieAccess_Private);
    g_Cookies[DisplayHud] = RegClientCookie("entwatch_displayhud", "", CookieAccess_Private);

    g_Forward[OnPick]       = CreateGlobalForward("entWatch_OnPickItem",        ET_Event,  Param_Cell, Param_String);
    g_Forward[OnPicked]     = CreateGlobalForward("entWatch_OnPickedItem",      ET_Ignore, Param_Cell, Param_String);
    g_Forward[OnDropped]    = CreateGlobalForward("entWatch_OnDroppedItem",     ET_Ignore, Param_Cell, Param_Cell, Param_String);
    g_Forward[OnUse]        = CreateGlobalForward("entWatch_OnItemUse",         ET_Event,  Param_Cell, Param_String);
    g_Forward[OnTransfered] = CreateGlobalForward("entWatch_OnItemTransfered",  ET_Ignore, Param_Cell, Param_Cell, Param_String);
    g_Forward[OnBanned]     = CreateGlobalForward("entWatch_OnClientBanned",    ET_Ignore, Param_Cell);
    g_Forward[OnUnban]      = CreateGlobalForward("entWatch_OnClientUnban",     ET_Ignore, Param_Cell);

    RegConsoleCmd("sm_estats",  Command_Stats);
    RegConsoleCmd("sm_ehud",    Command_DisplayHud);

    RegAdminCmd("sm_eban",      Command_Restrict,   ADMFLAG_BAN);
    RegAdminCmd("sm_eunban",    Command_Unrestrict, ADMFLAG_BAN);
    RegAdminCmd("sm_etransfer", Command_Transfer,   ADMFLAG_BAN);

    RegServerCmd("sm_ereload",  Command_Reload);

    g_aPreHammerId[Pre_Button] = new ArrayList();
    g_aPreHammerId[Pre_Weapon] = new ArrayList();
    g_aPreHammerId[Pre_Locked] = new ArrayList();

#if defined USE_TRANSLATIONS
    LoadTranslations("entWatch.phrases");
#endif

    if(g_bLateload)
    {
        g_bLateload = false;
        
        for(int client = 1; client <= MaxClients; ++client)
        if(ClientIsValid(client))
        {
            OnClientConnected(client);
            OnClientPutInServer(client);
            if(AreClientCookiesCached(client))
                OnClientCookiesCached(client);
        }
        
        if(LibraryExists("dhooks"))
            OnLibraryAdded("dhooks");
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

        g_extDHook = true;
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if(strcmp(name, "dhooks") == 0)
    {
        g_extDHook = false;
        LogError("Dhook library has been removed.");
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
    AddFileToDownloadsTable("materials/maoling/sprites/ze/entwatch_2017.vmt");
    AddFileToDownloadsTable("materials/maoling/sprites/ze/entwatch_2017.vtf");
    PrecacheModel("materials/maoling/sprites/ze/entwatch_2017.vmt", true);
}

public void OnConfigsExecuted()
{
    g_aPreHammerId[Pre_Weapon].Clear();
    g_aPreHammerId[Pre_Button].Clear();
    g_aPreHammerId[Pre_Locked].Clear();

    for(int index = 0; index < MAXENT; index++)
    {
        g_EntArray[index][ent_name][0]        = '\0';
        g_EntArray[index][ent_short][0]       = '\0';
        g_EntArray[index][ent_buttonclass][0] = '\0';
        g_EntArray[index][ent_filtername][0]  = '\0';
        g_EntArray[index][ent_hasfiltername]  = false;
        g_EntArray[index][ent_hammerid]       = -1;
        g_EntArray[index][ent_weaponref]      = -1;
        g_EntArray[index][ent_buttonid]       = -1;
        g_EntArray[index][ent_ownerid]        = -1;
        g_EntArray[index][ent_mode]           = 0;
        g_EntArray[index][ent_uses]           = 0;
        g_EntArray[index][ent_maxuses]        = 0;
        g_EntArray[index][ent_cooldown]       = 0;
        g_EntArray[index][ent_cooldowntime]   = -1;
        g_EntArray[index][ent_weaponglow]     = false;
        g_EntArray[index][ent_displayhud]     = false;
        g_EntArray[index][ent_team]           = -1;
        g_EntArray[index][ent_glowref]   = INVALID_ENT_REFERENCE;
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

//public void OnEntityCreated(int entity, const char[] classname)
//{
//    if(g_extDHook && classname[0] == 'l' && strcmp(classname, "logic_compare", false) == 0)
//    {
//        PrintToServer("DHookEntity %s [%d]", classname, entity);
//        DHookEntity(hAcceptInput, true, entity);
//    }
//}

public void OnClientConnected(int client)
{
    g_bBanned[client] = false;
    g_bEntHud[client] = false;
}

public void OnClientCookiesCached(int client)
{
    char buffer_hud[32];
    GetClientCookie(client, g_Cookies[DisplayHud], buffer_hud, 32);
    if(StringToInt(buffer_hud) == 1)
        g_bEntHud[client] = true;

    char buffer_rej[32];
    GetClientCookie(client, g_Cookies[Restricted], buffer_rej, 32);
    if(StringToInt(buffer_rej) == 1)
        g_bBanned[client] = true;

    if(!g_bBanned[client])
        return;

    char buffer_ban[32];
    GetClientCookie(client, g_Cookies[BanTLength], buffer_ban, 32);
    int exp = StringToInt(buffer_ban);
    if(exp > 0 && exp < GetTime())
    {
        SetClientCookie(client, g_Cookies[Restricted], "0");
        SetClientCookie(client, g_Cookies[BanTLength], "-1");
        SetClientCookie(client, g_Cookies[BanByAdmin], "null");

        g_bBanned[client] = false;
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

    StopTimer(g_tKnife[client]);

    if(g_bConfigLoaded && g_bHasEnt[client])
    {
        for(int index = 0; index < MAXENT; ++index)
            if(g_EntArray[index][ent_ownerid] == client)
            {
                int weapon = EntRefToEntIndex(g_EntArray[index][ent_weaponref]);

                g_EntArray[index][ent_ownerid] = -1;

                if(IsValidEdict(weapon))
                {
                    SDKHooks_DropWeapon(client, weapon);
                    RequestFrame(SetWeaponGlow, index);
                }

                ClearIcon(client);
                RefreshHud();

                Call_StartForward(g_Forward[OnDropped]);
                Call_PushCell(client);
                Call_PushCell(DR_OnDisconnect);
                Call_PushString(g_EntArray[index][ent_name]);
                Call_Finish();

#if defined USE_TRANSLATIONS
                tChatTeam(g_EntArray[index][ent_team], true, "%t", "disconnected with ent", client, g_EntArray[index][ent_name]);
#else
                ChatTeam(g_EntArray[index][ent_team], true, "\x0C%N\x01离开游戏时带着神器\x04%s", client, g_EntArray[index][ent_name]);
#endif
            }
    }

    SDKUnhook(client, SDKHook_WeaponDropPost,  Event_WeaponDropPost);
    SDKUnhook(client, SDKHook_WeaponEquipPost, Event_WeaponEquipPost);
    SDKUnhook(client, SDKHook_WeaponCanUse,    Event_WeaponCanUse);
}

static void ResetAllStats()
{
    for(int client = 1; client <= MaxClients; ++client)
        if(ClientIsValid(client))
            SetClientDefault(client);

    for(int index = 0; index < g_iEntCounts; index++)
    {
        if(g_EntArray[index][ent_buttonid] != -1)
            SDKUnhook(g_EntArray[index][ent_buttonid], SDKHook_Use, Event_ButtonUse);

        RemoveWeaponGlow(index);

        g_EntArray[index][ent_weaponref]      = -1;
        g_EntArray[index][ent_buttonid]       = -1;
        g_EntArray[index][ent_ownerid]        = -1;
        g_EntArray[index][ent_cooldowntime]   = -1;
        g_EntArray[index][ent_uses]           = 0;
        g_EntArray[index][ent_pickedup]       = false;
    }
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if(!g_bConfigLoaded)
    {
        for(int index = 0; index < g_aPreHammerId[Pre_Locked].Length; ++index)
            g_aPreHammerId[Pre_Locked].Set(index, -1.0);
        
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

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if(!g_bConfigLoaded)
        return;
    
    int client = GetClientOfUserId(event.GetInt("userid"));

    DropClientEnt(client);
}

static void DropClientEnt(int client)
{
    if(!g_bHasEnt[client])
        return;

    for(int index = 0; index < MAXENT; ++index)
        if(g_EntArray[index][ent_ownerid] == client)
        {
            int weaponid = EntRefToEntIndex(g_EntArray[index][ent_weaponref]);

            if(IsValidEdict(weaponid))
            {
                SDKHooks_DropWeapon(client, weaponid);
                RequestFrame(SetWeaponGlow, index);
            }

            g_EntArray[index][ent_ownerid] = -1;
            
            Call_StartForward(g_Forward[OnDropped]);
            Call_PushCell(client);
            Call_PushCell(DR_OnDeath);
            Call_PushString(g_EntArray[index][ent_name]);
            Call_Finish();
            
#if defined USE_TRANSLATIONS
            tChatTeam(g_EntArray[index][ent_team], true, "%t", "died with ent", client, g_EntArray[index][ent_name]);
#else
            ChatTeam(g_EntArray[index][ent_team], true, "\x0C%N\x01死亡时带着神器\x04%s", client, g_EntArray[index][ent_name]);
#endif
        }

    RefreshHud();
    SetClientDefault(client);
}

public void Event_PlayerTeams(Event e, const char[] name, bool dontBroadcast)
{
    g_iTeam[GetClientOfUserId(e.GetInt("userid"))] = e.GetInt("team");
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
        if(g_EntArray[index][ent_hammerid] == hammerid)
        {
            //PrintToServer("Event_WeaponCreated -> %d -> match -> %d", entity, hammerid);
            if(g_EntArray[index][ent_weaponref] == -1)
            {
                g_EntArray[index][ent_weaponref] = EntIndexToEntRef(entity);
                RequestFrame(SetWeaponGlow, index);
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
        if(g_EntArray[x][ent_hammerid] == hamid)
            if(g_EntArray[x][ent_weaponref] == iref)
            {
                index = x;
                break;
            }

    if(index < 0)
        return;

    g_EntArray[index][ent_team] = g_iTeam[client];
    
    if(!g_EntArray[index][ent_pickedup])
        g_EntArray[index][ent_cooldowntime] = g_EntArray[index][ent_startcd];

    g_EntArray[index][ent_ownerid]   = client;
    g_EntArray[index][ent_pickedup]  = true;

    CreateIcon(client);
    RemoveWeaponGlow(index);

    g_bHasEnt[client] = true;
    g_iScores[client] = 999 - CS_GetClientContributionScore(client);
    g_fPickup[client] = GetGameTime();

    CS_SetClientContributionScore(client, 999);

    if(IsValidEdict(g_EntArray[index][ent_buttonid]))
        SDKHookEx(g_EntArray[index][ent_buttonid], SDKHook_Use, Event_ButtonUse);
    else if(g_EntArray[index][ent_buttonid] == -1 && g_EntArray[index][ent_mode] > 0 && strcmp(g_EntArray[index][ent_buttonclass], "func_button", false) == 0)
    {
        char buffer_targetname[32], buffer_parentname[32];
        GetEntityTargetName(weapon, buffer_targetname, 32);

        int button = -1;
        while((button = FindEntityByClassname(button, g_EntArray[index][ent_buttonclass])) != -1)
        {
            GetEntityParentName(button, buffer_parentname, 32);

            if(strcmp(buffer_targetname, buffer_parentname) == 0)
            {
                SDKHookEx(button, SDKHook_Use, Event_ButtonUse);
                g_EntArray[index][ent_buttonid] = button;
                //LogMessage("%N first picked %d:%d", client, weapon, button);
                break;
            }
        }
    }

#if defined USE_TRANSLATIONS
    tChatTeam(g_EntArray[index][ent_team], true, "%t", "pickup ent", client, g_EntArray[index][ent_name]);
#else
    ChatTeam(g_EntArray[index][ent_team], true, "\x0C%N\x01捡起了神器\x04%s", client, g_EntArray[index][ent_name]);
#endif

    Call_StartForward(g_Forward[OnPicked]);
    Call_PushCell(client);
    Call_PushString(g_EntArray[index][ent_name]);
    Call_Finish();

    RefreshHud();
}

static void CheckPreConfigs(int client, int weapon)
{
    // Get HammerID
    int hammerid = GetEntityHammerID(weapon);
    if(hammerid <= 0) return;

    // if was stored.
    if(g_aPreHammerId[Pre_Weapon].FindValue(hammerid) != -1)
    {
        ChatAll("\x04PreConfigs \x01->\x10 Already record \x01[\x07%d\x01]", hammerid);
        return;
    }

    // Check targetname
    char targetname[128];
    GetEntityTargetName(weapon, targetname, 128);

    ChatAll("\x04PreConfigs \x01->\x05 targetname\x01[\x07%s\x01]", targetname);

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
    else ChatAll("\x04PreConfigs \x01->\x05 funcbutton\x01[\x07%d\x01]", button);

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

    ChatAll("\x04PreConfigs \x01->\x05 clientname\x01[\x07%s\x01]", clientname);
    
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

    ChatAll("\x04PreConfigs \x01->\x05 filtername\x01[\x07%s\x01]", filtername);

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
    g_aPreHammerId[Pre_Weapon].Push(hammerid);
    g_aPreHammerId[Pre_Button].Push(button == -1 ? -1 : GetEntityHammerID(button));
    g_aPreHammerId[Pre_Locked].Push(-1.0);

    if(kv.JumpToKey(kvstringid, false))
    {
        int cooldown = kv.GetNum("cooldown");
        if(cooldown > 0)
        {
            g_aPreHammerId[Pre_Button].Set(g_aPreHammerId[Pre_Button].Length-1, -1);
            g_aPreHammerId[Pre_Locked].Set(g_aPreHammerId[Pre_Locked].Length-1, cooldown);
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

    if(button != -1 && g_extDHook)
    {
        //PrintToServer("DHookEntity func_button [%d]", button);
        DHookEntity(hAcceptInput, true, button);
    }

    ChatAll("\x04PreConfigs \x01->\x10 Record the data successfully", filtername);

    return Plugin_Stop;
}

public void Event_WeaponDropPost(int client, int weapon)
{
    if(!IsValidEdict(weapon))
        return;

    if(g_bConfigLoaded)
    {
        int index = FindIndexByEntityRef(EntIndexToEntRef(weapon));

        if(index >= 0)
        {
            SetClientDefault(client);
            RequestFrame(SetWeaponGlow, index);

            g_EntArray[index][ent_ownerid] = -1;
            
            if(g_EntArray[index][ent_buttonid] != -1)
                SDKUnhook(g_EntArray[index][ent_buttonid], SDKHook_Use, Event_ButtonUse);

#if defined USE_TRANSLATIONS
            tChatTeam(g_EntArray[index][ent_team], true, "%t", "droped ent", client, g_EntArray[index][ent_name]);
#else
            ChatTeam(g_EntArray[index][ent_team], true, "\x0C%N\x01丟掉了神器\x04%s", client, g_EntArray[index][ent_name]);
#endif

            RefreshHud();
            
            Call_StartForward(g_Forward[OnDropped]);
            Call_PushCell(client);
            Call_PushCell(DR_NormalDrop);
            Call_PushString(g_EntArray[index][ent_name]);
            Call_Finish();

            return;
        }
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
    return g_iEntTeam[entity] == g_iTeam[client] ? Plugin_Continue : Plugin_Handled;
}

static void SetClientDefault(int client)
{
    ClearIcon(client);

    g_bHasEnt[client] = false;

    CS_SetClientContributionScore(client, CS_GetClientContributionScore(client) - g_iScores[client]);
    CS_SetClientClanTag(client, g_szClantag[client]);
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
    Call_StartForward(g_Forward[OnPick]);
    Call_PushCell(client);
    Call_PushString(g_EntArray[index][ent_name]);
    Call_Finish(allow);

    if(!allow && CanClientUseEnt(client))
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
    if(!g_bConfigLoaded || !IsValidEdict(button) || !ClientIsAlive(activator))
        return Plugin_Continue;
    
    //LogMessage("%N pressing %d : %d", activator, button, GetEntityHammerID(button));
    //LogMessage("%d parent is %d", button, GetEntPropEnt(button, Prop_Data, "m_pParent"));

    int index = FindIndexByButton(button);

    if(index < 0)
    {
        //LogMessage("Event_ButtonUse -> %N -> FindIndexByButton -> %d : %d", activator, button, GetEntityHammerID(button));
        return Plugin_Handled;
    }

    if(g_EntArray[index][ent_ownerid] != activator)
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

    if(g_EntArray[index][ent_team] != g_iTeam[activator])
    {
        //LogMessage("Event_ButtonUse -> %N -> GetClientTeam");
        return Plugin_Handled;
    }

    if(g_EntArray[index][ent_hasfiltername])
        DispatchKeyValue(activator, "targetname", g_EntArray[index][ent_filtername]);
    
    bool allow = true;
    Call_StartForward(g_Forward[OnUse]);
    Call_PushCell(activator);
    Call_PushString(g_EntArray[index][ent_name]);
    Call_Finish(allow);

    if(!allow)
        return Plugin_Handled;

    if(g_EntArray[index][ent_mode] == 1)
    {
        AddClientScore(activator, 1);
        return Plugin_Continue;
    }
    else if(g_EntArray[index][ent_mode] == 2 && g_EntArray[index][ent_cooldowntime] <= 0)
    {
        g_EntArray[index][ent_cooldowntime] = g_EntArray[index][ent_cooldown];

#if defined USE_TRANSLATIONS
        tChatTeam(g_EntArray[index][ent_team], true, "%t", "used ent and cooldown", activator, g_EntArray[index][ent_name], g_EntArray[index][ent_cooldown]);
#else
        ChatTeam(g_EntArray[index][ent_team], true, "\x0C%N\x01使用了神器\x04%s\x01[\x04CD\x01:\x07%d\x04秒\x01]", activator, g_EntArray[index][ent_name], g_EntArray[index][ent_cooldown]);
#endif

        RefreshHud();
        AddClientScore(activator, 3);

        return Plugin_Continue;
    }
    else if(g_EntArray[index][ent_mode] == 3 && g_EntArray[index][ent_uses] < g_EntArray[index][ent_maxuses], activator, g_EntArray[index][ent_name], g_EntArray[index][ent_maxuses]-g_EntArray[index][ent_uses])
    {
        g_EntArray[index][ent_uses]++;

#if defined USE_TRANSLATIONS
        tChatTeam(g_EntArray[index][ent_team], true, "%t", "used ent and maxuses", activator, g_EntArray[index][ent_name], g_EntArray[index][ent_maxuses]-g_EntArray[index][ent_uses]);
#else       
        ChatTeam(g_EntArray[index][ent_team], true, "\x0C%N\x01使用了神器\x04%s\x01[\x04剩余\x01:\x07%d\x04次\x01]", activator, g_EntArray[index][ent_name], g_EntArray[index][ent_maxuses]-g_EntArray[index][ent_uses]);
#endif

        RefreshHud();
        AddClientScore(activator, 3);
        
        return Plugin_Continue;
    }
    else if(g_EntArray[index][ent_mode] == 4 && g_EntArray[index][ent_uses] < g_EntArray[index][ent_maxuses] && g_EntArray[index][ent_cooldowntime] <= 0)
    {
        g_EntArray[index][ent_cooldowntime] = g_EntArray[index][ent_cooldown];
        g_EntArray[index][ent_uses]++;

#if defined USE_TRANSLATIONS
        tChatTeam(g_EntArray[index][ent_team], true, "%t", "used ent and cd maxuses", activator, g_EntArray[index][ent_name], g_EntArray[index][ent_cooldown], g_EntArray[index][ent_maxuses]-g_EntArray[index][ent_uses]);
#else
        ChatTeam(g_EntArray[index][ent_team], true, "\x0C%N\x01使用了神器\x04%s\x01[\x04CD\x01:\x07%ds\x01|\x04剩余\x01:\x07%d\x04次\x01]", activator, g_EntArray[index][ent_name], g_EntArray[index][ent_cooldown], g_EntArray[index][ent_maxuses]-g_EntArray[index][ent_uses]);
#endif
        
        RefreshHud();
        AddClientScore(activator, 5);

        return Plugin_Continue;
    }
    else if(g_EntArray[index][ent_mode] == 5 && g_EntArray[index][ent_cooldowntime] <= 0)
    {
#if defined USE_TRANSLATIONS
        tChatTeam(g_EntArray[index][ent_team], true, "%t", "used ent and times cd", activator, g_EntArray[index][ent_name], g_EntArray[index][ent_maxuses]-g_EntArray[index][ent_uses]);
#else
        ChatTeam(g_EntArray[index][ent_team], true, "\x0C%N\x01使用了神器\x04%s\x01[\x04使用%d次后冷却\x01]", activator, g_EntArray[index][ent_name], g_EntArray[index][ent_maxuses]-g_EntArray[index][ent_uses]);
#endif

        g_EntArray[index][ent_uses]++;
        
        if(g_EntArray[index][ent_uses] >= g_EntArray[index][ent_maxuses])
        {
#if defined USE_TRANSLATIONS
            tChatTeam(g_EntArray[index][ent_team], true, "%t", "used ent and used times into cd", g_EntArray[index][ent_name], g_EntArray[index][ent_cooldown]);
#else
            ChatTeam(g_EntArray[index][ent_team], true, "神器\x04%s\x01[\x04CD\x01:\x07%d\x04秒\x01]", g_EntArray[index][ent_name], g_EntArray[index][ent_cooldown]);
#endif

            g_EntArray[index][ent_cooldowntime] = g_EntArray[index][ent_cooldown];
            g_EntArray[index][ent_uses] = 0;
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
            int index = g_aPreHammerId[Pre_Button].FindValue(GetEntityHammerID(pThis));
            if(index > -1)
                g_aPreHammerId[Pre_Locked].Set(index, GetGameTime());
        }
        else if(strcmp(command, "Unlock", false) == 0)
        {
            int index = g_aPreHammerId[Pre_Button].FindValue(GetEntityHammerID(pThis));
            if(index > -1)
            {
                float locked = g_aPreHammerId[Pre_Locked].Get(index);
                if(locked > 0.0)
                {
                    float cooldown = GetGameTime() - locked;
                    SavePreConfigs(g_aPreHammerId[Pre_Weapon].Get(index), cooldown);
                    g_aPreHammerId[Pre_Button].Set(index, -1);
                }
            }
        }
    }
    // Tested on ze_FFVII_Mako_Reactor_v5_3_v5 ? bug
    //else if(strcmp(classname, "logic_compare") == 0)
    //{
    //    int type = -1;
    //    float fVal = 0.0;
    //    type = DHookGetParamObjectPtrVar(hParams, 4, 16, ObjectValueType_Int);
    //
    //    if(type == 1) 
    //        fVal = DHookGetParamObjectPtrVar(hParams, 4, 0, ObjectValueType_Float);
    //    else if(type == 2)
    //    {
    //        char val[32];
    //        DHookGetParamObjectPtrString(hParams, 4, 0, ObjectValueType_String, val, 128);
    //        StringToFloatEx(val, fVal);
    //    }
    //
    //    if(strcmp(command, "SetCompareValue", false) == 0)
    //    {
    //        int index = g_aPreHammerId[Pre_Button].FindValue(GetEntityHammerID(pThis));
    //        if(index > -1)
    //        {
    //            float locked = g_aPreHammerId[Pre_Locked].Get(index);
    //            if(locked == -1.0)
    //            {
    //                g_aPreHammerId[Pre_Locked].Set(index, GetGameTime());
    //            }
    //            else
    //            {
    //                float cooldown = GetGameTime() - locked;
    //                SavePreConfigs(g_aPreHammerId[Pre_Weapon].Get(index), cooldown);
    //                g_aPreHammerId[Pre_Button].Set(index, -1);
    //            }
    //        }
    //    }
    //}

    return MRES_Ignored;
}

public Action Timer_Cooldowns(Handle timer)
{
    if(!g_bConfigLoaded)
    {
        g_tCooldown = null;
        return Plugin_Stop;
    }
    
    for(int index = 0; index < g_iEntCounts; index++)
        if(g_EntArray[index][ent_cooldowntime] > 0)
            g_EntArray[index][ent_cooldowntime]--;

    RefreshHud();

    return Plugin_Continue;
}

static void RefreshHud()
{
    strcopy(g_szGlobalHud[ZOMBIE], 2048, "[!ehud] Zombie entWatch: ");
    strcopy(g_szGlobalHud[HUMANS], 2048, "[!ehud] Humans entWatch: ");

    for(int index = 0; index < g_iEntCounts; index++)
    {
        CountdownMessage(index);
        BuildHUDandScoreboard(index);
    }

    if(strcmp(g_szGlobalHud[ZOMBIE], "[!ehud] Zombie entWatch: ") == 0)
        g_szGlobalHud[ZOMBIE][0] = '\0';
        //Format(g_szGlobalHud[ZOMBIE], 2048, "%s\n", g_szGlobalHud[ZOMBIE]);

    if(strcmp(g_szGlobalHud[HUMANS], "[!ehud] Humans entWatch: ") == 0)
        g_szGlobalHud[HUMANS][0] = '\0';
        //Format(g_szGlobalHud[HUMANS], 2048, "%s\n", g_szGlobalHud[HUMANS]);

    SetHudTextParams(0.160500, 0.099000, 2.0, 57, 197, 187, 255, 0, 30.0, 0.0, 0.0);

    for(int client = 1; client <= MaxClients; ++client)
        if(IsClientInGame(client) && !g_bEntHud[client])
            ShowHudText(client, 5, IsInfector(client) ? g_szGlobalHud[ZOMBIE] : g_szGlobalHud[HUMANS]);
}

static void CountdownMessage(int index)
{
    if(g_EntArray[index][ent_mode] == 4 || g_EntArray[index][ent_mode] == 2 || g_EntArray[index][ent_mode] == 5)
    {
        if(ClientIsAlive(g_EntArray[index][ent_ownerid]))
        {
            if(g_bEntHud[g_EntArray[index][ent_ownerid]])
            {
                if(g_EntArray[index][ent_cooldowntime] > 0)
                {
                    SetHudTextParams(-1.0, 0.05, 2.0, 205, 173, 0, 255, 0, 30.0, 0.0, 0.0);
                    ShowHudText(g_EntArray[index][ent_ownerid], 6, ">>> [%s] :  %ds <<< ", g_EntArray[index][ent_name], g_EntArray[index][ent_cooldowntime]);
                }
                else
                {
                    SetHudTextParams(-1.0, 0.05, 2.0, 0, 255, 0, 255, 0, 30.0, 0.0, 0.0);
#if defined USE_TRANSLATIONS
                    ShowHudText(g_EntArray[index][ent_ownerid], 6, "%t[%s]%t", "Item", g_EntArray[index][ent_name], "Ready");
#else
                    ShowHudText(g_EntArray[index][ent_ownerid], 6, "神器[%s]就绪", g_EntArray[index][ent_name]);
#endif
                }
            }
        }
        else if(g_EntArray[index][ent_cooldowntime] == 1)
        {
            SMUtils_SkipNextChatCS();
#if defined USE_TRANSLATIONS
            tChatTeam(g_EntArray[index][ent_team], true, "%t", "cooldown end no owner", g_EntArray[index][ent_name]);
#else        
            ChatTeam(g_EntArray[index][ent_team], true, "\x07%s\x04冷却时间已结束\x01[\x07无人使用\x01]", g_EntArray[index][ent_name]);
#endif
            CreateTimer(1.1, Timer_RefreshGlow, index);
        }
    }
    else if(ClientIsValid(g_EntArray[index][ent_ownerid]))
    {
        if(g_EntArray[index][ent_mode] == 3 && g_EntArray[index][ent_uses] >= g_EntArray[index][ent_maxuses])
        {
            if(g_bEntHud[g_EntArray[index][ent_ownerid]])
            {
                SetHudTextParams(-1.0, 0.05, 2.0, 255, 0, 0, 233, 0, 30.0, 0.0, 0.0);
#if defined USE_TRANSLATIONS
                ShowHudText(g_EntArray[index][ent_ownerid], 6, "%t[%s]%t", "Item", g_EntArray[index][ent_name], "Deplete");
#else
                ShowHudText(g_EntArray[index][ent_ownerid], 6, "神器[%s]耗尽", g_EntArray[index][ent_name]);
#endif
            }
        }
        else
        {
            if(g_bEntHud[g_EntArray[index][ent_ownerid]])
            {
                SetHudTextParams(-1.0, 0.05, 2.0, 0, 255, 0, 255, 0, 30.0, 0.0, 0.0);
#if defined USE_TRANSLATIONS
                ShowHudText(g_EntArray[index][ent_ownerid], 6, "%t[%s]%t", "Item", g_EntArray[index][ent_name], "Ready");
#else
                ShowHudText(g_EntArray[index][ent_ownerid], 6, "神器[%s]就绪", g_EntArray[index][ent_name]);
#endif
            }
        }
    }
}

public Action Timer_RefreshGlow(Handle timer, int index)
{
    if(ClientIsAlive(g_EntArray[index][ent_ownerid]))
        return Plugin_Stop;

    RemoveWeaponGlow(index);
    //PrintToServer("[Timer_RefreshGlow] -> %d", index);
    RequestFrame(SetWeaponGlow, index);

    return Plugin_Stop;
}

static void BuildHUDandScoreboard(int index)
{
    if(!g_EntArray[index][ent_displayhud])
        return;

    char szClantag[32], szGameText[128];
    strcopy(szClantag, 32, g_EntArray[index][ent_short]);

    if(ClientIsAlive(g_EntArray[index][ent_ownerid]))
    {   
        switch(g_EntArray[index][ent_mode])
        {
            case 1: FormatEx(szGameText, 128, "%s[R]: %N", g_EntArray[index][ent_name], g_EntArray[index][ent_ownerid]);
            case 2:
            {
                if(g_EntArray[index][ent_cooldowntime] <= 0)
                    FormatEx(szGameText, 128, "%s[R]: %N", g_EntArray[index][ent_name], g_EntArray[index][ent_ownerid]);
                else
                    FormatEx(szGameText, 128, "%s[%d]: %N", g_EntArray[index][ent_name], g_EntArray[index][ent_cooldowntime], g_EntArray[index][ent_ownerid]);
            }
            case 3:
            {
                if(g_EntArray[index][ent_maxuses] > g_EntArray[index][ent_uses])
                    FormatEx(szGameText, 128, "%s[R]: %N", g_EntArray[index][ent_name], g_EntArray[index][ent_ownerid]);
                else
                    FormatEx(szGameText, 128, "%s[N]: %N", g_EntArray[index][ent_name], g_EntArray[index][ent_ownerid]);
            }
            case 4:
            {
                if(g_EntArray[index][ent_cooldowntime] <= 0)
                {
                    if(g_EntArray[index][ent_maxuses] > g_EntArray[index][ent_uses])
                        FormatEx(szGameText, 128, "%s[R]: %N", g_EntArray[index][ent_name], g_EntArray[index][ent_ownerid]);
                    else
                        FormatEx(szGameText, 128, "%s[N]: %N", g_EntArray[index][ent_name], g_EntArray[index][ent_ownerid]);
                }
                else
                    FormatEx(szGameText, 128, "%s[%d]: %N", g_EntArray[index][ent_name], g_EntArray[index][ent_cooldowntime], g_EntArray[index][ent_ownerid]);
            }
            case 5:
            {
                if(g_EntArray[index][ent_cooldowntime] <= 0)
                    FormatEx(szGameText, 128, "%s[R]: %N", g_EntArray[index][ent_name], g_EntArray[index][ent_ownerid]);
                else
                    FormatEx(szGameText, 128, "%s[%d]: %N", g_EntArray[index][ent_name], g_EntArray[index][ent_cooldowntime], g_EntArray[index][ent_ownerid]);
            }
            default: FormatEx(szGameText, 128, "%s[R]: %N", g_EntArray[index][ent_name], g_EntArray[index][ent_ownerid]);
        }

        CS_SetClientClanTag(g_EntArray[index][ent_ownerid], szClantag);
        Format(g_szGlobalHud[g_EntArray[index][ent_team] - 2], 2048, "%s\n%s", g_szGlobalHud[g_EntArray[index][ent_team] - 2], szGameText);
    }
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

    char buffer_admin[32], buffer_timer[32];
    GetClientCookie(client, g_Cookies[BanByAdmin], buffer_admin, 32);
    GetClientCookie(client, g_Cookies[BanTLength], buffer_timer, 32);
    
    int exp = StringToInt(buffer_timer);
    FormatTime(buffer_timer, 32, "%Y/%m/%d - %H:%M:%S", exp);

#if defined USE_TRANSLATIONS
    Chat(client, "%T", "ent ban info", client, buffer_admin, buffer_timer);
#else
    Chat(client, "你的神器被 \x0C%N\x01 封禁了 [到期时间 \x07%s\x01]", buffer_admin, buffer_timer);
#endif

    return Plugin_Handled;
}

public Action Command_DisplayHud(int client, int args)
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

    g_bEntHud[client] = !g_bEntHud[client];
    
    Chat(client, "entWatch HUD is \x02%s\x01!", g_bEntHud[client] ? "\x07Off\x01" : "\x04On\x01");

    return Plugin_Handled;
}

public Action Command_Restrict(int client, int args)
{
    if(!client || !IsClientInGame(client))
        return Plugin_Handled;
    
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

    if(menu.ItemCount >= 1)
    {
        menu.ExitButton = false;
        menu.Display(client, 30);
    }
    else
    {
        Chat(client, "No player in target list");
        delete menu;
    }

    return Plugin_Handled;
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
    Menu menu = new Menu(MenuHandler_Time);
    
    menu.SetTitle("[entWatch]  Select Time\n ");

    menu.AddItem(target, "", ITEMDRAW_IGNORE);

    menu.AddItem("1",   "1 Hour");
    menu.AddItem("2",   "1 Day");
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
            if(g_EntArray[index][ent_ownerid] == client)
            {
                g_EntArray[index][ent_ownerid] = -1;

                int weapon_index_1 = GetPlayerWeaponSlot(target, 1);
                int weapon_index_2 = GetPlayerWeaponSlot(target, 2);
                
                int weapon = EntRefToEntIndex(g_EntArray[index][ent_weaponref]);
                
                if(IsValidEdict(weapon))
                {
                    if(weapon_index_1 == weapon || weapon_index_2 == weapon)
                    {
                        SDKHooks_DropWeapon(target, weapon);
                        RequestFrame(SetWeaponGlow, index);

#if defined USE_TRANSLATIONS
                        tChatTeam(g_EntArray[index][ent_team], true, "%t", "ent dropped", g_EntArray[index][ent_name]);
#else
                        ChatTeam(g_EntArray[index][ent_team], true, "\x04%s\x0C已掉落", g_EntArray[index][ent_name]);
#endif

                        Call_StartForward(g_Forward[OnDropped]);
                        Call_PushCell(client);
                        Call_PushCell(DR_OnBanned);
                        Call_PushString(g_EntArray[index][ent_name]);
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

    g_bBanned[target] = true;
    SetClientCookie(target, g_Cookies[Restricted], "1");
    SetClientCookie(target, g_Cookies[BanByAdmin], szAdmin);
    SetClientCookie(target, g_Cookies[BanTLength], szTime);

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

    Call_StartForward(g_Forward[OnBanned]);
    Call_PushCell(target);
    Call_Finish();

#if defined USE_TRANSLATIONS
    tChatAll("%t", "ban ent", target, client, szTime);
#else
    ChatAll("小朋友\x07%N\x01因为乱玩神器,被dalao\x04%N\x07ban神器[%s]", target, client, szTime);
#endif

    LogAction(client, -1, "%L ban %L => %s [entWatch]", client, target, szTime);
}

public Action Command_Unrestrict(int client, int args)
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

    if(menu.ItemCount >= 1)
    {
        menu.ExitButton = false;
        menu.Display(client, 30);
    }
    else
    {
        Chat(client, "No player in ban list");
        delete menu;
    }

    return Plugin_Handled;
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

    g_bBanned[target] = false;
    SetClientCookie(target, g_Cookies[Restricted], "0");
    SetClientCookie(target, g_Cookies[BanTLength], "-1");
    SetClientCookie(target, g_Cookies[BanByAdmin], "null");

#if defined USE_TRANSLATIONS
    tChatAll("%t", "unban ent", target, client);
#else
    ChatAll("小朋友\x07%N\x01的\x07ban神器\x01被dalao\x04%N\x01解开了", target, client);
#endif

    LogAction(client, -1, "%L unban %L [entWatch]", client, target);

    Call_StartForward(g_Forward[OnUnban]);
    Call_PushCell(target);
    Call_Finish();
}

public Action Command_Transfer(int client, int args)
{
    if(!g_bConfigLoaded)
        return Plugin_Handled;

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

    if(menu.ItemCount >= 1)
    {
        SetMenuExitButton(menu, false);
        DisplayMenu(menu, client, 0);
    }
    else
    {
        Chat(client, "No one pickup item.");
        CloseHandle(menu);
    }
    
    return Plugin_Handled;
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
        CloseHandle(menu);
    }
}

static void TransferClientEnt(int client, int target)
{
    if(!ClientIsAlive(target))
    {
        Chat(client, "Target is invalid.");
        return;
    }

    for(int index = 0; index < MAXENT; ++index)
        if(g_EntArray[index][ent_ownerid] == target)
        {
            int weapon = EntRefToEntIndex(g_EntArray[index][ent_weaponref]);
            
            char buffer_classname[64];
            GetEdictClassname(weapon, buffer_classname, 64);
            
            SDKHooks_DropWeapon(target, weapon);
            GivePlayerItem(target, buffer_classname);
            EquipPlayerWeapon(client, weapon);
            
#if defined USE_TRANSLATIONS
            tChatAll("%t", "transfer ent", client, target, g_EntArray[index][ent_name]);
#else
            ChatAll("\x0C%N\x01拿走了\x0C%N\x01手上的神器[\x04%s\x01]", client, target, g_EntArray[index][ent_name]);
#endif

            LogAction(client, -1, "%L transfer %L item %s [entWatch]", client, target, g_EntArray[index][ent_name]);

            RemoveWeaponGlow(index);

            Call_StartForward(g_Forward[OnTransfered]);
            Call_PushCell(client);
            Call_PushCell(target);
            Call_PushString(g_EntArray[index][ent_name]);
            Call_Finish();
        }

    g_bHasEnt[client] = true;
    g_bHasEnt[target] = false;

    RefreshHud();
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
    else
        LogError("Loaded %s but not found any data", path);
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
            strcopy(g_EntArray[g_iEntCounts][ent_name], 32, temp);

            kv.GetString("shortname", temp, 32);
            strcopy(g_EntArray[g_iEntCounts][ent_short], 32, temp);
            
            kv.GetString("buttonclass", temp, 32);
            strcopy(g_EntArray[g_iEntCounts][ent_buttonclass], 32, temp);

            kv.GetString("filtername", temp, 32);
            strcopy(g_EntArray[g_iEntCounts][ent_filtername], 32, temp);
            
            kv.GetString("hasfiltername", temp, 32);
            g_EntArray[g_iEntCounts][ent_hasfiltername] = (strcmp(temp, "true", false) == 0);
            
            kv.GetString("hammerid", temp, 32);
            g_EntArray[g_iEntCounts][ent_hammerid] = StringToInt(temp);

            kv.GetString("mode", temp, 32);
            g_EntArray[g_iEntCounts][ent_mode] = StringToInt(temp);

            kv.GetString("maxuses", temp, 32);
            g_EntArray[g_iEntCounts][ent_maxuses] = StringToInt(temp);
            
            kv.GetString("startcd", temp, 32);
            g_EntArray[g_iEntCounts][ent_startcd] = StringToInt(temp);

            kv.GetString("cooldown", temp, 32);
            g_EntArray[g_iEntCounts][ent_cooldown] = StringToInt(temp);

            kv.GetString("glow", temp, 32);
            g_EntArray[g_iEntCounts][ent_weaponglow] = (strcmp(temp, "true", false) == 0);

            kv.GetString("hud", temp, 32);
            g_EntArray[g_iEntCounts][ent_displayhud] = (strcmp(temp, "true", false) == 0);

            kv.GetString("team", temp, 32);
            if(strcmp(temp, "human", false) == 0)
                g_EntArray[g_iEntCounts][ent_team] = 3;
            else
                g_EntArray[g_iEntCounts][ent_team] = 2;

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
    if(g_tKnife[client] != null)
        KillTimer(g_tKnife[client]);
    g_tKnife[client] = CreateTimer(0.1, Timer_CheckKnife, client);
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
        if(g_EntArray[index][ent_hammerid] == hammerid)
            return index;

    return -1;
}

static int FindIndexByEntityRef(int ref)
{
    for(int index = 0; index < g_iEntCounts; index++)
        if(g_EntArray[index][ent_weaponref] == ref)
            return index;

    return -1;
}

static int FindIndexByButton(int button)
{
    for(int index = 0; index < g_iEntCounts; index++)
        if(g_EntArray[index][ent_buttonid] != -1 && g_EntArray[index][ent_buttonid] == button)
            return index;

    return -1;
}

static int GetGlowType(int index)
{
    if(!g_EntArray[index][ent_pickedup])
        return 0;

    switch(g_EntArray[index][ent_mode])
    {
        case 0: return 1;
        case 1: return 1;
        case 2: return (g_EntArray[index][ent_cooldowntime] <= 0) ? 1 : 2;
        case 3: return (g_EntArray[index][ent_uses] < g_EntArray[index][ent_maxuses]) ? 1 : 3;
        case 4: return (g_EntArray[index][ent_uses] < g_EntArray[index][ent_maxuses] && g_EntArray[index][ent_cooldowntime] <= 0) ? 1 : ((g_EntArray[index][ent_uses] >= g_EntArray[index][ent_maxuses]) ? 3 : 2);
        case 5: return (g_EntArray[index][ent_cooldowntime] <= 0) ? 1 : 2;
    }

    return 1;
}

static void SetWeaponGlow(int index)
{
    if(!g_EntArray[index][ent_weaponglow])
        return;

    if(IsValidEdict(EntRefToEntIndex(g_EntArray[index][ent_glowref])))
    {
        //PrintToServer("[SetWeaponGlow] Blocked -> %d -> by Ref", index);
        return;
    }

    float origin[3];
    float angle[3];
    char model[256];

    int weapon = EntRefToEntIndex(g_EntArray[index][ent_weaponref]);
    
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
    
    g_iEntTeam[glow] = g_EntArray[index][ent_team];

    g_EntArray[index][ent_glowref] = EntIndexToEntRef(glow);
    
    SDKHookEx(glow, SDKHook_SetTransmit, Event_SetTransmit);
    
    //PrintToServer("[SetWeaponGlow] Created -> %d", index);
}

static void RemoveWeaponGlow(int index)
{
    if(!g_EntArray[index][ent_weaponglow])
        return;

    if(g_EntArray[index][ent_glowref] != INVALID_ENT_REFERENCE)
    {
        int entity = EntRefToEntIndex(g_EntArray[index][ent_glowref]);

        if(IsValidEdict(entity))
            AcceptEntityInput(entity, "KillHierarchy");

        g_EntArray[index][ent_glowref] = INVALID_ENT_REFERENCE;
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
    CS_SetClientContributionScore(client, CS_GetClientContributionScore(client) + score);
}

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

static bool IsInfector(int client)
{
    if(!IsPlayerAlive(client))
        return true;

    if(g_pZombieEscape)
        return (ZE_IsInfector(client) || ZE_IsAvenger(client));

    if(g_pZombieReload)
        return ZR_IsClientZombie(client);

    return (g_iTeam[client] == 2);
}
