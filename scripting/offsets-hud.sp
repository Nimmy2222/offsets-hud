#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <sdkhooks>
#include <clientprefs>

#pragma semicolon 1
#pragma newdecls required

#define LEFT 0
#define RIGHT 1
#define BHOP_FRAMES 10
#define RED 0
#define GREEN 1
#define BLUE 2


public Plugin myinfo = 
{
    name = "offsets-hud",
    author = "Nimmy2222",
    description = "display strafe offsets to players",
    version = "public-1.0",
    url = "https://github.com/Nimmy2222"
}

Handle g_hHudSync;
Handle g_hCookieEnabled;

bool g_bEnabled[MAXPLAYERS + 1];
bool g_bOverlap[MAXPLAYERS + 1];
bool g_bNoPress[MAXPLAYERS + 1];

int g_iRgb[3];
int g_iGroundTicks[MAXPLAYERS + 1];
int g_iLastOffset[MAXPLAYERS + 1];
int g_iTurnTick[MAXPLAYERS + 1];
int g_iKeyTick[MAXPLAYERS + 1];
int g_iTurnDir[MAXPLAYERS + 1];
int g_iCmdNum[MAXPLAYERS + 1];
int g_iRepeatedOffsets[MAXPLAYERS + 1];

float g_fLastYaw[MAXPLAYERS + 1];
float g_fYawDifference[MAXPLAYERS + 1];
float g_fLastSidemove[MAXPLAYERS + 1];

public void OnPluginStart()
{
    RegConsoleCmd("sm_offset", Command_ToggleOffsets);
    RegConsoleCmd("sm_offsets", Command_ToggleOffsets);

    g_hCookieEnabled = RegClientCookie("offsets-on", "Are offsets displayed?", CookieAccess_Protected);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            OnClientCookiesCached(i);
        }
    }
    
    g_hHudSync = CreateHudSynchronizer();
    AutoExecConfig();
}

public void OnClientCookiesCached(int client) {
    char sCookie[8];
    GetClientCookie(client, g_hCookieEnabled, sCookie, 8);
    
    if (StringToInt(sCookie) == 0) {
        SetClientCookie(client, g_hCookieEnabled, "false");
    }
    GetClientCookie(client, g_hCookieEnabled, sCookie, 8);

    g_bEnabled[client] = view_as<bool>(StringToInt(sCookie));
}

public Action Command_ToggleOffsets(int client, int args) {
    g_bEnabled[client] = !g_bEnabled[client];
    char sCookie[8];
    IntToString(g_bEnabled[client], sCookie, 8);
    SetClientCookie(client, g_hCookieEnabled, sCookie);
    PrintToChat(client, "Offsets: %s", g_bEnabled[client] ? "On":"Off");

    if(g_bEnabled[client]) {
        PrintToChat(client, "Check console for an explanation.\nOffsets will be displayed on the HUD while bhopping/strafing.");
        PrintToConsole(client, "An ideal offet is -1, this is what most if not all top strafers get most of the time.");
        PrintToConsole(client, "A positive number means you pressed the key to turn too late, or you were overlapping.");
        PrintToConsole(client, "A negative number means you pressed the key to turn too early.");
        PrintToConsole(client, "When Nulls is on, it is impossible to overlap keypresses. This makes offsets more accurate.");
        PrintToConsole(client, "If you do not have nulls, you might get a late offset because you were overlapping and not because you pressed too late.");
        PrintToConsole(client, "By Nimmy");
    }
    return Plugin_Handled;
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
    //To someone in the future, this plugin shows offests to specs if they have it g_bEnabled, so don't add a guard for if the client has g_bEnabled true.
    if(IsFakeClient(client) || !IsClientInGame(client) || !IsPlayerAlive(client)) {
        return;
    }

    MoveType movetype = GetEntityMoveType(client);
    if(movetype == MOVETYPE_NONE || movetype == MOVETYPE_NOCLIP || movetype == MOVETYPE_LADDER || GetEntProp(client, Prop_Data, "m_nWaterLevel") >= 2) {
        return;
    }

    int flags = GetEntityFlags(client);
    if(flags & FL_ONGROUND == FL_ONGROUND)
    {
        g_iGroundTicks[client]++;
        if ((buttons & IN_JUMP) > 0 && g_iGroundTicks[client] == 1) {
            g_iGroundTicks[client] = 0;
        }
    } else {
        g_iGroundTicks[client] = 0;
    }
    if(g_iGroundTicks[client] > BHOP_FRAMES) {
        g_iTurnTick[client] = -1;
        g_iKeyTick[client] = -1;
        g_iCmdNum[client] = 0;
        g_bNoPress[client] = false;
        g_bOverlap[client] = false;
        return;
    }

    if(g_iCmdNum[client] >= 1) {
        int ilvel, icvel;
        ilvel = RoundToFloor(g_fLastSidemove[client]) / 10;
        icvel = RoundToFloor(vel[1]) / 10;
        if(ilvel * icvel < 0 || (g_fLastSidemove[client] == 0 && vel[1] != 0)) {
            g_iKeyTick[client] = g_iCmdNum[client];
        }
    }

    g_fYawDifference[client] = GetAngleDiff(angles[1], g_fLastYaw[client]);
    if(g_fYawDifference[client] > 0) {
        if(g_iTurnDir[client] == RIGHT && g_iCmdNum[client] > 1)
        {
            g_iTurnTick[client] = g_iCmdNum[client];
        }
        g_iTurnDir[client] = LEFT;
    } else if(g_fYawDifference[client] < 0) {
        if(g_iTurnDir[client] == LEFT && g_iCmdNum[client] > 1)
        {
            g_iTurnTick[client] = g_iCmdNum[client];
        }
        g_iTurnDir[client] = RIGHT;
    }

    if ((!(buttons & IN_MOVELEFT) && !(buttons & IN_MOVERIGHT))) {
        g_bNoPress[client] = true;
    }

    if(((buttons & IN_MOVELEFT) && (buttons & IN_MOVERIGHT)) || ((buttons & IN_FORWARD) && (buttons & IN_BACK))) {
        g_bOverlap[client] = true;
    }

    if( (g_iTurnTick[client] == g_iCmdNum[client] || g_iKeyTick[client] == g_iCmdNum[client]) && ((g_iTurnDir[client] == RIGHT && vel[1] > 0) || (g_iTurnDir[client] == LEFT && vel[1] < 0) ) ) {
        int offset = g_iKeyTick[client] - g_iTurnTick[client];
        if(offset == g_iLastOffset[client]) {
            g_iRepeatedOffsets[client]++;
        } else {
            g_iRepeatedOffsets[client] = 0;
        }
        //PrintToChat(client, "Of: %i KT: %i TT: %i TurnDir: %i Vel: %f", offset, g_iKeyTick[client], g_iTurnTick[client], g_iTurnDir[client], vel[1]);
        g_iLastOffset[client] = offset;
        SetRgb(offset, g_bOverlap[client], g_bNoPress[client]);
        SetHudTextParams(-1.0, 0.35, 0.5, g_iRgb[RED], g_iRgb[GREEN], g_iRgb[BLUE], 255, 0, 0.0, 0.0, 0.1);

        char msg[256];
        Format(msg, 256, "%d (%i)", offset, g_iRepeatedOffsets[client]);
        if(g_bOverlap[client]) {
            Format(msg, 256, "%s Overlap", msg);
        }
        if(g_bNoPress[client]) {
            Format(msg, 256, "%s No Press", msg);
        }

        for (int i = 1; i < MaxClients; i++)
        {
            if(!g_bEnabled[i] || !IsClientInGame(i) || IsFakeClient(i)) {
                continue;
            }
            if (((i == client)) || (!IsPlayerAlive(i) && GetEntPropEnt(i, Prop_Data, "m_hObserverTarget") == client && GetEntProp(i, Prop_Data, "m_iObserverMode") != 7)) {
                ShowSyncHudText(i, g_hHudSync, msg);
            }
        }
        g_bOverlap[client] = false;
        g_bNoPress[client] = false;
    }

    g_iCmdNum[client]++;
    g_fLastYaw[client] = angles[1];
    g_fLastSidemove[client] = vel[1];
    return;
}

float GetAngleDiff(float current, float previous)
{
	float diff = current - previous;
	return diff - 360.0 * RoundToFloor((diff + 180.0) / 360.0);
}

void SetRgb(int offset, bool overlap, bool nopress) {
    if(overlap || nopress || offset > 0) {
        g_iRgb[RED] = 255;
        g_iRgb[GREEN] = 0;
        g_iRgb[BLUE] = 0;
        return;
    }
    if(offset == 0) {
        g_iRgb[RED] = 255;
        g_iRgb[GREEN] = 255;
        g_iRgb[BLUE] = 255;
    } else if(offset == -1) {
        g_iRgb[RED] = 3;
        g_iRgb[GREEN] = 255;
        g_iRgb[BLUE] = 242;
    } else if(offset == -2) {
        g_iRgb[RED] = 4;
        g_iRgb[GREEN] = 196;
        g_iRgb[BLUE] = 3;
    } else {
        g_iRgb[RED] = 255;
        g_iRgb[GREEN] = 0;
        g_iRgb[BLUE] = 0;
    }
}
