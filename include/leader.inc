#if defined _leader_included_
    #endinput
#endif
#define _leader_included_

/**
 * Returns current leader
 *
 * @return int    Client index of the leader (-1 = null)
 */
native int Leader_CurrentLeader();
/**
 * Sets the leader
 *
 * @param client    Client index to be set as leader
 */
native void Leader_SetLeader(int client);

public SharedPlugin __pl_Leader =
{
    name = "Leader",
    file = "leader3.smx",
#if defined REQUIRE_PLUGIN
    required = 1
#else
    required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __ext_Leader_SetNTVOptional()
{
    MarkNativeAsOptional("Leader_CurrentLeader");
    MarkNativeAsOptional("Leader_SetLeader");
}
#endif