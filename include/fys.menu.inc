#if defined _fys_Menu_Include_
    #endinput
#endif

#define _fsy_Menu_Include_

native TopMenu Menu_GetAdminMenu();
native TopMenu Menu_GetUsersMenu();

forward void Menu_OnAdminMenuReady(Handle adminMenu);
forward void Menu_OnUsersMenuReady(Handle usersMenu);

#define ADMIN_PLAYERCOMMAND "PlayerCommands" //"m_Player"
#define ADMIN_SERVERCOMMAND "ServerCommands" //"m_Server"
#define ADMIN_PLUGINCOMMAND "PluginCommands" //"m_Plugin"
#define ADMIN_CONFIGCOMMAND "ConfigCommands" //"m_Config"
#define ADMIN_VOTINGCOMMAND "VotingCommands" //"m_Voting"
#define ADMIN_ADMINSCOMMAND "AdminsCommands" //"m_Admins"

public SharedPlugin __pl_fys_Menu =
{
    name = "fys-Menu",
    file = "fys.menu.smx",
#if defined REQUIRE_PLUGIN
    required = 1
#else
    required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __ext_fys_Menu_SetNTVOptional()
{
    MarkNativeAsOptional("Menu_GetAdminMenu");
    MarkNativeAsOptional("Menu_GetUsersMenu");
}
#endif