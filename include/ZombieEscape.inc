/******************************************************************/
/*                                                                */
/*                         ZombieEscape                           */
/*                                                                */
/*                                                                */
/*  File:          ZombieEscape.inc                               */
/*  Description:   a CSGO game mode -> Infector vs Survivor.      */
/*                                                                */
/*                                                                */
/*  Copyright (C) 2018  Kyle                                      */
/*  2018/04/01 15:22:55                                           */
/*                                                                */
/*  This code is licensed under the GPLv3 License.                */
/*                                                                */
/******************************************************************/

#if defined __ZombieEscape__
    #endinput
#endif

#define __ZombieEscape__

//infection
native bool ZE_IsSurvivor(int client);
native bool ZE_IsInfector(int client);
native bool ZE_IsAvenger(int client);
native bool ZE_IsTerminator(int client);

native bool ZE_InfectPlayer(int client, int attacker = -1, bool motherZombie = false, bool teleportOverride = false, bool teleport = false);
native bool ZE_CurePlayer(int client, bool infectionImmunity = true, float &immunityTime = 0.0, bool teleportOverride = false, bool teleport = false);
native bool ZE_ForceAvenger(int client, int hp, int skill, bool bypassHook = true);
native bool ZE_ForceTerminator(int client, int hp, int skill, bool bypassHook = true);

forward Action ZE_OnPlayerInfect(int client, int &attacker, bool &motherZombie, bool &teleportOverride, bool &teleport);
forward Action ZE_OnPlayerCure(int client, bool &infectionImmunity, float &immunityTime, bool &teleportOverride, bool &teleport);
forward Action ZE_OnFirstInfect(int[] clients, int &numClients, bool &teleportOverride, bool &teleport);
forward Action ZE_OnAvengerSpawn(int avenger, int &hp, int &skill);
forward Action ZE_OnTerminatorSpawn(int terminator, int &hp, int &skill);
forward Action ZE_OnPlayerDeath(int client, int &attacker, bool &allowRespawn);
forward void ZE_OnPlayerInfected(int client, int attacker, bool motherZombie, bool teleportOverride, bool teleport);
forward void ZE_OnPlayerCured(int client, bool infectionImmunity, float immunityTime, bool teleportOverride, bool teleport);
forward void ZE_OnFirstInfected(int[] clients, int numClients, bool teleportOverride, bool teleport);
forward void ZE_OnAvengerSpawned(int avenger, int hp, int skill);
forward void ZE_OnTerminatorSpawned(int terminator, int hp, int skill);

//class
enum ZEClass
{
    ZEC_normalInfector,
    ZEC_motherInfector,
    ZEC_normalSurvivor,
    ZEC_commanderSurvivor,
    ZEC_avenger,
    ZEC_terminator
}

native       int ZE_GetPlayerClass(int client, ZEClass classType = ZEC_normalInfector);
native       int ZE_GetCurrentClass(int client);
native       int ZE_GetClassByName(const char[] name);
native      bool ZE_SetPlayerClass(int client, int classIndex, bool save = false);
native   ZEClass ZE_GetClassType(int classIndex);
native ArrayList ZE_GetClassArray(ZEClass classType);


//respawn
native void ZE_RespawnPlayer(int client, bool changeRole = false);
forward void ZE_OnRespawned(int client, bool teleportOverride, bool teleport);
forward Action ZE_OnRespawn(int client, bool &teleportOverride, bool &teleport);


//speed mod
native   int ZE_SetSpeed(int client, float mtpl, bool overrideSpeed = false, float keepTime = 0.0);
native float ZE_GetSpeed(int client);


//jump mod
native void ZE_SetJump(int client, float  high, float  dist, float  fall);
native void ZE_GetJump(int client, float &high, float &dist, float &fall);


//ammo mod
native void ZE_SetAmmo(int client, int  clip, int  ammo);
native void ZE_GetAmmo(int client, int &clip, int &ammo);


//weapon mod
native void ZE_RestrictWeapon(const char[] classname);
native void ZE_AllowWeapon(const char[] classname);
native bool ZE_IsRestrict(const char[] classname);
native void ZE_GiveWeapon(int client, const char[] classname);
native bool ZE_RemoveWeapon(int client, const char[] classname);
native void ZE_SpawnWeapon(const char[] classname, const float origin[3], const float angles[3]);
