/*
 * ============================================================================
 *
 *  Zombie:Reloaded
 *
 *  File:          zombiereloaded.inc
 *  Type:          Include
 *  Description:   Main API include file.
 *  Notes:         Include this file to include the whole ZR API. 
 *
 *  Copyright (C) 2009-2013  Greyscale, Richard Helgeby
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * ============================================================================
 */
 
 #if defined __zombiereloaded__
    #endinput
#endif

#define __zombiereloaded__


//infection
native bool ZR_IsClientZombie(int client);
native bool ZR_IsClientHuman(int client);
native void ZR_InfectClient(int client, int attacker = -1, bool motherInfect = false, bool respawnOverride = false, bool respawn = false);
native void ZR_HumanClient(int client, bool respawn = false, bool protect = false);

forward Action ZR_OnClientInfect(int &client, int &attacker, bool &motherInfect, bool &respawnOverride, bool &respawn);
forward Action ZR_OnClientHuman(int &client, bool &respawn, bool &protect);
forward void   ZR_OnClientInfected(int client, int attacker, bool motherInfect, bool respawnOverride, bool respawn);
forward void   ZR_OnClientHumanPost(int client, bool respawn, bool protect);


//respawn
enum ZR_RespawnCondition
{
    ZR_Repsawn_Default = -1,    /** Let ZR decide according to its settings. */
    ZR_Respawn_Human = 0,       /** Respawn as a human. */
    ZR_Respawn_Zombie,          /** Respawn as a zombie. */
    ZR_Respawn_ZombieIfSuicide  /** Respawn as a zombie if killed by world damage. */
}

native void ZR_RespawnClient(int client, ZR_RespawnCondition condition = ZR_Repsawn_Default);
native void ZR_SetKilledByWorld(int client, bool suicide);
native bool ZR_GetKilledByWorld(int client);

forward Action ZR_OnClientRespawn(int &client, ZR_RespawnCondition &condition);
forward void   ZR_OnClientRespawned(int client, ZR_RespawnCondition condition);


//class
#define ZR_CLASS_CACHE_ORIGINAL 0   /** Original class data loaded from file. */
#define ZR_CLASS_CACHE_MODIFIED 1   /** Default cache. Class data modified by eventual multipliers, map configs, commands, etc. */
#define ZR_CLASS_CACHE_PLAYER   2   /** Current player class attributes. The class index parameter is used as client index when reading from this cache. */

enum ClassSelectResult
{
    ClassSelected_NoChange,     /** No class change was necessary (class already selected). */
    ClassSelected_Instant,      /** Class was instantly changed. */
    ClassSelected_NextSpawn     /** Class will be used next spawn. */
}

native bool ZR_IsValidClassIndex(int classIndex);
native bool ZR_GetActiveClass(int client);
native ClassSelectResult ZR_SelectClientClass(int client, int classIndex, bool applyIfPossible = true, bool saveIfEnabled = true);
native void ZR_GetClassByName(const char[] className, int cacheType = ZR_CLASS_CACHE_MODIFIED);
native void ZR_GetClassDisplayName(int index, char[] buffer, int maxlen, int cacheType = ZR_CLASS_CACHE_MODIFIED);