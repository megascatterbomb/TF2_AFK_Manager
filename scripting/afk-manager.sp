#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>

// TF2 ConVars
ConVar g_hIdleMaxTime;	// ConVar for idle max time

// Plugin ConVars
ConVar g_hAFKTime;				  // ConVar for AFK time
ConVar g_hAFKIgnoreDead;		  // ConVar for ignoring dead players
ConVar g_hAFKAction;			  // ConVar for AFK action
ConVar g_hAdminImmune;		  // ConVar for admin immunity
ConVar g_hDisplayAFKMessage;	  // ConVar for displaying AFK message notification
ConVar g_hTextFont;		  // ConVar for font number
ConVar g_hDisplayTextEntities;	  // ConVar for displaying text entities

const float AFK_CHECK_INTERVAL = 1.0; // Maximum number of players

float  g_fLastAction[MAXPLAYERS + 1];
bool   g_bIsAFK[MAXPLAYERS + 1];
int	   g_iAFKTextEntity[MAXPLAYERS + 1];
int	   g_iAFKTimerEntity[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name		= "[TF2] AFK Manager",
	author		= "roxrosykid",
	description = "Notifies others if player went AFK and renders AFK message above players' head.",
	version		= "1.1.0",
	url			= "https://github.com/roxrosykid"
};

public void OnPluginStart()
{
	g_hIdleMaxTime		   = FindConVar("mp_idlemaxtime");	// Get the idle max time ConVar

	// Create the ConVar for AFK time
	g_hAFKTime			   = CreateConVar("sm_afk_time", "120.0", "Time in seconds before a player is considered AFK", FCVAR_NONE, true, 0.0);

	// Create the ConVar for ignoring dead players
	g_hAFKIgnoreDead	   = CreateConVar("sm_afk_ignore_dead", "0", "Pause AFK timer for dead players (0 = No, 1 = Yes)", FCVAR_NONE, true, 0.0, true, 1.0);

	// Create the ConVar for AFK action
	g_hAFKAction		   = CreateConVar("sm_afk_action", "1", "Action to take when a player has been AFK for mp_idlemaxtime minutes (0 = none, 1 = move to spectator then kick if still idle, 2 = kick)", FCVAR_NONE, true, 0.0, true, 2.0);

	// Create the ConVar for admin immunity
	g_hAdminImmune 	       = CreateConVar("sm_afk_admin_immune", "1", "Admin immunity for AFK action (0 = no, 1 = immune to all actions, 2 = immune to kicks only", FCVAR_NONE, true, 0.0, true, 2.0);

	// Create the ConVar for displaying AFK message notification
	g_hDisplayAFKMessage   = CreateConVar("sm_afk_message", "1", "Display AFK message notification (1 = Yes, 0 = No)", FCVAR_NONE, true, 0.0, true, 1.0);

	// Create the ConVar for font number
	g_hTextFont		   = CreateConVar("sm_afk_text_font", "0", "Font number for AFK message notification. See https://developer.valvesoftware.com/wiki/Point_worldtext", FCVAR_NONE, true, 0.0, true, 12.0);

	// Create the ConVar for displaying text entities
	g_hDisplayTextEntities = CreateConVar("sm_afk_text", "1", "Display text entities above AFK players (1 = Yes, 0 = No)", FCVAR_NONE, true, 0.0, true, 1.0);

	// Create default config and execute it for plugin
	AutoExecConfig(true, "afk-manager")

	HookEvent("player_team", OnPlayerTeamChange);
	HookEvent("teamplay_round_start", OnRoundStart);

	// Hook the ConVar change
	g_hDisplayTextEntities.AddChangeHook(OnDisplayTextEntitiesChanged);

	CreateTimer(AFK_CHECK_INTERVAL, Timer_CheckAFK, _, TIMER_REPEAT);

	float fTime = GetEngineTime();
	for (int i = 0; i <= MaxClients; i++)
	{
		g_fLastAction[i] = fTime;
	}

	DeleteEntitiesWithTargetname("afk_entity");
}

public void OnClientPutInServer(int client)
{
	g_fLastAction[client]	  = GetEngineTime();
	g_bIsAFK[client]		  = false;
	g_iAFKTextEntity[client]  = -1;
	g_iAFKTimerEntity[client] = -1;
}

public void OnClientDisconnect(int client)
{
	RemoveAFKEntity(client);
}

// If a player goes in or out of spectator, reset their AFK status.
public void OnPlayerTeamChange(Handle event, const char[] name, bool dontBroadcast) {
    int userid = GetEventInt(event, "userid"); // Get the user ID of the player
	int oldteam = GetEventInt(event, "oldteam"); // Get the old team of the player
	int newteam = GetEventInt(event, "team"); // Get the new team of the player
	int client = GetClientOfUserId(userid); // Get the client index from the user ID

	 // We don't want to affect players going between RED and BLU to avoid messing with VSH, ZI, etc.
	if (client <= 0 || (oldteam != 1 && newteam != 1)) 
	{
		return;
	}

	g_fLastAction[client] = GetEngineTime();
	g_bIsAFK[client]	  = false;

	RemoveAFKEntity(client); // Remove the AFK entity
}

// Clean up entity handles when a round reset deletes them all.
public void OnRoundStart(Handle event, const char[] name, bool dontBroadcast) {

	// Run for full reset only
	bool full_reset = GetEventBool(event, "full_reset");

	if (!full_reset)
	{
		return;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		// Wipe entity arrays
		g_iAFKTextEntity[i]  = -1;
		g_iAFKTimerEntity[i] = -1;

		// Recreate entity if need be
		if (g_bIsAFK[i] && g_hDisplayTextEntities.BoolValue)
		{
			float timeSinceLastAction = GetEngineTime() - g_fLastAction[i];
			CreateAFKEntity(i, timeSinceLastAction);
		}
	}
}

bool IsImmune(client, isKick)
{
	int iFlags = GetUserFlagBits(client);

	if (iFlags & (ADMFLAG_GENERIC | ADMFLAG_ROOT) <= 0)
	{
		return false;
	}
	if (g_hAdminImmune.IntValue == 1)
	{
		return true;
	}
	else if (g_hAdminImmune.IntValue == 2 && isKick)
	{
		return true;
	}
	return false;
}

public Action Timer_CheckAFK(Handle timer)
{
	float currentTime = GetEngineTime();
	float afkTime	  = g_hAFKTime.FloatValue;	  // Get the AFK time from the ConVar
	float actionTime  = g_hIdleMaxTime.FloatValue * 60.0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			float timeSinceLastAction = currentTime - g_fLastAction[i];
			int team = GetClientTeam(i); 

			if (g_hAFKIgnoreDead.IntValue == 1 && (team == 2 || team == 3) && !IsPlayerAlive(i)) // Ignore AFK time for dead players
			{
				// We increment the lastAction time at the same interval that this function is called.
				// This effectively pauses the AFK timer for dead players.
				g_fLastAction[i] = g_fLastAction[i] + AFK_CHECK_INTERVAL; 
				continue;
			}

			if (timeSinceLastAction >= actionTime && g_hAFKAction.IntValue > 0) // has been AFK for mp_idlemaxtime minutes
			{
				if (g_hAFKAction.IntValue == 1 && !IsImmune(i, false)) // Move to spectator
				{
					if (team == 1 && !IsImmune(i, true)) // If already in spectator, kick
					{
						RemoveAFKEntity(i);
						KickClient(i, "Kicked for being AFK.");
						continue;
					}
					else if (team != 1) // Move player to spectator team
					{
						// Last action time will reset on team change. This prevents immediate kick.
						PrintToChatAll("%N has been moved to spectator for being AFK.", i);
						ChangeClientTeam(i, 1);
					}
				}
				else if (g_hAFKAction.IntValue == 2 && !IsImmune(i, true)) // Kick
				{
					RemoveAFKEntity(i);
					KickClient(i, "Kicked for being AFK.");
					continue;
				}
			}

			if (team != 2 && team != 3)
			{
				continue;
			}

			if (timeSinceLastAction >= afkTime && !g_bIsAFK[i]) // has been AFK for sm_afk_time
			{
				g_bIsAFK[i] = true;
				if (g_hDisplayAFKMessage.BoolValue)
				{
					PrintToChatAll("%N is now AFK.", i);
				}
				if (g_hDisplayTextEntities.BoolValue)
				{
					CreateAFKEntity(i, timeSinceLastAction);
				}
			}
			else if (timeSinceLastAction < afkTime && g_bIsAFK[i]) // Is no longer AFK
			{
				g_bIsAFK[i] = false;
				if (g_hDisplayAFKMessage.BoolValue)
				{
					PrintToChatAll("%N is no longer AFK.", i);
				}
				if (g_hDisplayTextEntities.BoolValue)
				{
					RemoveAFKEntity(i);
				}
			}
			else if (g_bIsAFK[i] && g_hDisplayTextEntities.BoolValue)
			{
				UpdateAFKEntity(i, timeSinceLastAction);
			}
		}
	}

	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (IsClientInGame(client) && !IsFakeClient(client))
	{
		if (buttons != 0 || impulse != 0)
		{
			g_fLastAction[client] = GetEngineTime();
			RemoveAFKEntity(client);
		}
	}

	return Plugin_Continue;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (client && IsClientInGame(client) && !IsFakeClient(client))
	{
		g_fLastAction[client] = GetEngineTime();
		if (g_bIsAFK[client])
		{
			g_bIsAFK[client] = false;
			if (g_hDisplayAFKMessage.BoolValue)
			{
				PrintToChatAll("%N is no longer AFK.", client);
			}
			if (g_hDisplayTextEntities.BoolValue)
			{
				RemoveAFKEntity(client);
			}
		}
	}

	return Plugin_Continue;
}

void CreateAFKEntity(int client, float timeSinceLastAction)
{
	float origin[3];
	if (!IsClientConnected(client) || !IsClientInGame(client) || IsFakeClient(client))
	{
		RemoveAFKEntity(client);
		return;
	}
	GetClientAbsOrigin(client, origin);
	origin[2] += 6.0;	 // Adjust height above player's head

	// Create AFK timer entity
	g_iAFKTimerEntity[client] = CreateEntityByName("point_worldtext");
	if (g_iAFKTimerEntity[client] > 0)
	{
		char font[64];
		Format(font, sizeof(font), "%d", g_hTextFont.IntValue);

		DispatchKeyValue(g_iAFKTimerEntity[client], "font", font);
		DispatchKeyValue(g_iAFKTimerEntity[client], "textsize", "6");
		DispatchKeyValue(g_iAFKTimerEntity[client], "orientation", "1");
		DispatchKeyValue(g_iAFKTimerEntity[client], "targetname", "afk_entity");	// Set targetname

		TeleportEntity(g_iAFKTimerEntity[client], origin, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(g_iAFKTimerEntity[client]);
		ActivateEntity(g_iAFKTimerEntity[client]);

		// Attach the entity to the player
		SetVariantString("!activator");
		AcceptEntityInput(g_iAFKTimerEntity[client], "SetParent", client);
		SetVariantString("head");
		AcceptEntityInput(g_iAFKTimerEntity[client], "SetParentAttachmentMaintainOffset");
	}

	// Create AFK text entity
	g_iAFKTextEntity[client] = CreateEntityByName("point_worldtext");
	if (g_iAFKTextEntity[client] > 0)
	{
		char font[64];
		Format(font, sizeof(font), "%d", g_hTextFont.IntValue);

		DispatchKeyValue(g_iAFKTextEntity[client], "message", "AFK");
		DispatchKeyValue(g_iAFKTextEntity[client], "font", font);
		DispatchKeyValue(g_iAFKTextEntity[client], "textsize", "8");
		DispatchKeyValue(g_iAFKTextEntity[client], "orientation", "1");
		DispatchKeyValue(g_iAFKTextEntity[client], "targetname", "afk_entity");	   // Set targetname

		origin[2] += 6.0;	 // Adjust height for the timer text
		TeleportEntity(g_iAFKTextEntity[client], origin, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(g_iAFKTextEntity[client]);
		ActivateEntity(g_iAFKTextEntity[client]);

		// Attach the entity to the player
		SetVariantString("!activator");
		AcceptEntityInput(g_iAFKTextEntity[client], "SetParent", client);
		SetVariantString("head");
		AcceptEntityInput(g_iAFKTextEntity[client], "SetParentAttachmentMaintainOffset");
	}

	UpdateAFKEntity(client, timeSinceLastAction);
}

void UpdateAFKEntity(int client, float timeSinceLastAction)
{
	if (g_iAFKTimerEntity[client] > 0)
	{
		char buffer[64];
		FormatTimeString(timeSinceLastAction, buffer, sizeof(buffer));
		DispatchKeyValue(g_iAFKTimerEntity[client], "message", buffer);

		// set alpha based on dead or alive (avoid having to recreate objects)
		if (!IsPlayerAlive(client) || TF2_IsPlayerInCondition(client, TFCond_Cloaked))
		{
			if (g_iAFKTextEntity[client] > 0)
			{
				DispatchKeyValue(g_iAFKTextEntity[client], "color", "255 255 255 0");
			}
			DispatchKeyValue(g_iAFKTimerEntity[client], "color", "255 255 255 0");
		}
		else
		{
			if (g_iAFKTextEntity[client] > 0)
			{
				int team = GetClientTeam(client);
				char color[64];
				if (team == 2) // RED
				{
					Format(color, sizeof(color), "255 100 100 255");
				}
				else // BLU
				{
					Format(color, sizeof(color), "100 100 255 255");
				}
				DispatchKeyValue(g_iAFKTextEntity[client], "color", color);
			}
			DispatchKeyValue(g_iAFKTimerEntity[client], "color", "255 255 255 255");
		}
	}
}

void RemoveAFKEntity(int client)
{
	if (g_iAFKTextEntity[client] > 0)
	{
		int index = g_iAFKTextEntity[client];
		g_iAFKTextEntity[client] = -1;
		RemoveEntity(index);
	}
	if (g_iAFKTimerEntity[client] > 0)
	{
		int index = g_iAFKTimerEntity[client];
		g_iAFKTimerEntity[client] = -1;
		RemoveEntity(index);
	}
}

void DeleteEntitiesWithTargetname(const char[] targetname)
{
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "point_worldtext")) != -1)
	{
		char entTargetname[64];
		GetEntPropString(entity, Prop_Data, "m_iName", entTargetname, sizeof(entTargetname));
		if (StrEqual(entTargetname, targetname))
		{
			RemoveEntity(entity);
		}
	}
}

void FormatTimeString(float time, char[] buffer, int maxlength)
{
	int hours	= RoundToFloor(time / 3600.0);
	int minutes = RoundToFloor((time - (hours * 3600.0)) / 60.0);
	int seconds = RoundToFloor(time - (hours * 3600.0) - (minutes * 60.0));

	if (hours > 0)
	{
		Format(buffer, maxlength, "%dh %dm %ds", hours, minutes, seconds);
	}
	else if (minutes > 0)
	{
		Format(buffer, maxlength, "%dm %ds", minutes, seconds);
	}
	else
	{
		Format(buffer, maxlength, "%ds", seconds);
	}
}

public void OnDisplayTextEntitiesChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (StringToInt(newValue) == 0)
	{
		// Remove all AFK text entities
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && g_bIsAFK[i])
			{
				RemoveAFKEntity(i);
			}
		}
	}
}