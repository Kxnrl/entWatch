/******************************************************************/
/*                                                                */
/*                           entWatch                             */
/*                                                                */
/*                                                                */
/*  File:          entWatch.inc                                   */
/*  Description:   Notify players about entity interactions.      */
/*                                                                */
/*                                                                */
/*  Copyright (C) 2018  Kyle                                      */
/*  2018/05/08 20:13:14                                           */
/*                                                                */
/*  This code is licensed under the GPLv3 License.                */
/*                                                                */
/******************************************************************/

#if defined _EntWatch_Include_
    #endinput
#endif

#define _EntWatch_Include_

public SharedPlugin __pl_entWatch =
{
	name = "entWatch",
	file = "entWatch.smx",
#if defined REQUIRE_PLUGIN
    required = 1
#else
    required = 0
#endif
}; 

enum Drop_Reason
{
    DR_OnDeath,
    DR_OnDisconnect,
    DR_NormalDrop,
    DR_OnBanned,
    DR_OnTransfer,
}

native bool entWatch_HasbeenBanned(int client);
native bool entWatch_ClientHasItem(int client);
native bool entWatch_EntityIsItem(int entity);

forward bool entWatch_OnPickItem(int client, const char[] ent_name);
forward void entWatch_OnPickedItem(int client, const char[] ent_name);
forward void entWatch_OnDroppedItem(int client, Drop_Reason reason, const char[] ent_name);
forward bool entWatch_OnItemUse(int client, const char[] ent_name);
forward void entWatch_OnItemTransfered(int client, int target, const char[] ent_name);
forward void entWatch_OnClientBanned(int client);
forward void entWatch_OnClientUnban(int client);