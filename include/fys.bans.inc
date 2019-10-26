#if defined _fys_Bans_Include_
    #endinput
#endif

#define _fys_Bans_Include_

native bool Admin_IsAuthAdmin(const char[] auth);
native bool Admin_IsClientAdmin(int client);
native int  Admin_GetAdminId(int client);
native void Admin_GetAdminName(int client, char[] buffer, int maxLen);
native void Admin_LogAction(int admin, const char[] action, const char[] message, any ...);


/*
 *  Ban_Type
 */
// 0 = 全服封禁
// 1 = 游戏封禁
// 2 = 模式封禁
// 3 = 单服封禁
native bool Bans_BanClient(int admin, int target, int ban_type, int ban_length, const char[] ban_reason);
native bool Bans_BanIdentity(int admin, const char[] identity, int ban_type, int ban_length, const char[] ban_reason);

public SharedPlugin __pl_fys_Bans =
{
    name = "fys-Bans",
    file = "fys.bans.smx",
#if defined REQUIRE_PLUGIN
    required = 1
#else
    required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __ext_fys_Bans_SetNTVOptional()
{
	MarkNativeAsOptional("Admin_IsAuthAdmin");
	MarkNativeAsOptional("Admin_IsClientAdmin");
	MarkNativeAsOptional("Admin_GetAdminId");
	MarkNativeAsOptional("Admin_GetAdminName");
	MarkNativeAsOptional("Admin_LogAction");

	MarkNativeAsOptional("Bans_BanClient");
	MarkNativeAsOptional("Bans_BanIdentity");
}
#endif