#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION	"1.0"
#define PLUGIN_DESC	"Experience Pings in Source! Oh no!"
#define PLUGIN_NAME	"[ANY] Ping Simulator"
#define PLUGIN_AUTH	"Glubbable"
#define PLUGIN_URL	"https://steamcommunity.com/groups/GlubsServers"

#define PINGNAME "ping_sprite"
#define EMPTY "models/empty.mdl"
#define MAX_PINGS 32
#define MAX_PING_SOUNDS 6

public const Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTH,
	description = PLUGIN_DESC,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL,
};

int g_iCurrentPingCount;
KeyValues g_kvPingConfig = null;

char g_sPingSounds[MAX_PINGS][MAX_PING_SOUNDS][PLATFORM_MAX_PATH];

int g_iPingSoundCount[MAX_PINGS];
int g_iPingSoundPitch[MAX_PINGS];
int g_iPingSoundLevel[MAX_PINGS];
float g_flPingSoundVolume[MAX_PINGS];

char g_sPingSprite[MAX_PINGS][PLATFORM_MAX_PATH];
int g_iPingParticle[MAX_PINGS];

Handle g_hPingTimer[MAXPLAYERS + 1];
int g_iPingCount[MAXPLAYERS + 1][2];
float g_flNextPingTime[MAXPLAYERS + 1];

// =====================================================================
// 				CORE		CORE		CORE		CORE				
// =====================================================================

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("playercommands.phrases");
	
	if (!SetupConfig())
		SetFailState("Failed to load! Config file was missing!");
		
	RegAdminCmd("sm_pingsim", Command_PingSimulate, ADMFLAG_RCON, "@everyone!");
	
	PrecacheModel(EMPTY, true);
}

public void OnPluginEnd()
{
	int iEntity = IsValidEntity(MaxClients + 1) ? MaxClients + 1 : -1;
	while ((iEntity = FindEntityByClassname(iEntity, "prop_dynamic")) > MaxClients)
	{
		char sName[64];
		GetEntPropString(iEntity, Prop_Data, "m_iName", sName, sizeof(sName));
		if (strcmp(sName, PINGNAME, false) == 0)
		{
			AcceptEntityInput(iEntity, "KillHierarchy");
		}
	}
	
	iEntity = IsValidEntity(MaxClients + 1) ? MaxClients + 1 : -1;
	while ((iEntity = FindEntityByClassname(iEntity, "env_sprite")) > MaxClients)
	{
		char sName[64];
		GetEntPropString(iEntity, Prop_Data, "m_iName", sName, sizeof(sName));
		if (strcmp(sName, PINGNAME, false) == 0)
		{
			AcceptEntityInput(iEntity, "KillHierarchy");
		}
	}
}

bool SetupConfig()
{
	char sBuffer[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sBuffer, sizeof(sBuffer), "configs/pinglist.cfg");
	KeyValues kvConfig = new KeyValues("root");
	if (!kvConfig.ImportFromFile(sBuffer))
	{
		delete kvConfig;
		g_kvPingConfig = null;
		return false;
	}

	g_kvPingConfig = kvConfig;
	return true;
}

public void OnConfigsExecuted()
{
	PrecacheModel(EMPTY, true);
	
	ClearPingData();
	
	if (!SetupPings())
		SetFailState("Failed to update ping list! Something went wrong while reading the config!");
}

void ClearPingData()
{
	for (int i = 0; i < MAX_PINGS; i++)
	{
		g_iPingSoundCount[i] = 0;
		g_iPingSoundPitch[i] = SNDPITCH_NORMAL;
		g_iPingSoundLevel[i] = SNDLEVEL_NORMAL;
		g_flPingSoundVolume[i] = SNDVOL_NORMAL;
		g_sPingSprite[i] = "";
		g_iPingParticle[i] = -1;
	}
	
	g_iCurrentPingCount = -1;
}

bool SetupPings()
{
	KeyValues kvConfig = g_kvPingConfig;
	if (kvConfig == null) return false;
	
	kvConfig.Rewind();
	if (!kvConfig.GotoFirstSubKey())
		return false;
	
	char sPingName[128];
	int iPingIndex = -1;
	do
	{
		iPingIndex++;
		
		kvConfig.GetSectionName(sPingName, sizeof(sPingName));
		
		char sSprite[PLATFORM_MAX_PATH];
		kvConfig.GetString("sprite_path", sSprite, sizeof(sSprite), "");
		if (!sSprite[0])
			return false;
			
		strcopy(g_sPingSprite[iPingIndex], sizeof(g_sPingSprite[]), sSprite);
		
		char sParticle[PLATFORM_MAX_PATH];
		kvConfig.GetString("particle", sParticle, sizeof(sParticle), "");
		g_iPingParticle[iPingIndex] = sParticle[0] ? PrecacheParticleSystem(sParticle) : -1;
		
		int iPitch = kvConfig.GetNum("sound_pitch", SNDPITCH_NORMAL);
		if (iPitch < 0) iPitch = 0;
		g_iPingSoundPitch[iPingIndex] = iPitch;
		
		float flVolume = kvConfig.GetFloat("sound_volume", SNDVOL_NORMAL);
		if (flVolume < 0.0) flVolume = 0.0;
		else if (flVolume > 1.0) flVolume = 1.0;
		g_flPingSoundVolume[iPingIndex] = flVolume;
		
		int iLevel = kvConfig.GetNum("sound_level", SNDLEVEL_NORMAL);
		if (iLevel < SNDLEVEL_NONE) iLevel = SNDLEVEL_NONE;
		else if (iLevel > SNDLEVEL_ROCKET) iLevel = SNDLEVEL_ROCKET;
		g_iPingSoundLevel[iPingIndex] = iLevel;
		
		g_iPingSoundCount[iPingIndex] = 0;
		if (kvConfig.JumpToKey("sounds", false))
		{
			for (; g_iPingSoundCount[iPingIndex] < MAX_PING_SOUNDS; g_iPingSoundCount[iPingIndex]++)
			{
				char sKey[6], sBuffer[PLATFORM_MAX_PATH];
				Format(sKey, sizeof(sKey), "%i", g_iPingSoundCount[iPingIndex]);
				kvConfig.GetString(sKey, sBuffer, sizeof(sBuffer), "");
				if (!sBuffer[0])
				{
					g_iPingSoundCount[iPingIndex]--;
					if (g_iPingSoundCount[iPingIndex] < 0)
						g_iPingSoundCount[iPingIndex] = 0;
					break;
				}
				PrecacheSound2(sBuffer);
				strcopy(g_sPingSounds[iPingIndex][g_iPingSoundCount[iPingIndex]], sizeof(g_sPingSounds[][]), sBuffer);
				
				Format(sBuffer, sizeof(sBuffer), "#%s", sBuffer);
				PrecacheSound(sBuffer);
			}
			kvConfig.GoBack();
		}
		if (kvConfig.JumpToKey("download_materials", false))
		{
			for (int i = 0;; i++)
			{
				char sKey[6], sBuffer[PLATFORM_MAX_PATH];
				Format(sKey, sizeof(sKey), "%i", i);
				kvConfig.GetString(sKey, sBuffer, sizeof(sBuffer), "");
				if (!sBuffer[0])
					break;
					
				PrecacheMaterial2(sBuffer);
			}
			kvConfig.GoBack();
		}
		if (kvConfig.JumpToKey("download", false))
		{
			for (int i = 0;; i++)
			{
				char sKey[6], sBuffer[PLATFORM_MAX_PATH];
				Format(sKey, sizeof(sKey), "%i", i);
				kvConfig.GetString(sKey, sBuffer, sizeof(sBuffer), "");
				if (!sBuffer[0])
					break;
					
				AddFileToDownloadsTable(sBuffer);
			}
			kvConfig.GoBack();
		}
	}
	while (kvConfig.GotoNextKey() && iPingIndex < MAX_PINGS);
	
	g_iCurrentPingCount = iPingIndex;
	return (iPingIndex != -1);
}

// =====================================================================
// 				CLIENTS		CLIENTS		CLIENTS		CLIENTS				
// =====================================================================

public void OnClientPutInServer(int iClient)
{
	g_hPingTimer[iClient] = INVALID_HANDLE;
	g_iPingCount[iClient][0] = 0;
	g_iPingCount[iClient][1] = 0;
	g_flNextPingTime[iClient] = 0.0;
}

public Action Command_PingSimulate(int iClient, int iArgs)
{
	if (g_iCurrentPingCount == -1)
	{
		ReplyToCommand(iClient, "[SM] Error: No Pings available.");
		return Plugin_Handled;
	}
	
	if (iArgs <= 0 || iArgs != 3)
	{
		ReplyToCommand(iClient, "[SM] Usage: sm_pingsim <#userid|@target|name> <index> <maxcount>");
		return Plugin_Handled;
	}

	char sTarget[65];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	
	char sIndex[PLATFORM_MAX_PATH];
	int iIndex, iMaxCount;

	GetCmdArg(2, sIndex, sizeof(sIndex));
	if (!sIndex[0])
	{
		ReplyToCommand(iClient, "[SM] Usage: sm_pingsim <#userid|@target|name> <index> <maxcount>");
		return Plugin_Handled;
	}
	
	iIndex = StringToInt(sIndex);
	if (iIndex < 0 || iIndex > g_iCurrentPingCount)
		iIndex = 0;

	GetCmdArg(3, sIndex, sizeof(sIndex));
	if (!sIndex[0])
	{
		ReplyToCommand(iClient, "[SM] Usage: sm_pingsim <#userid|@target|name> <index> <maxcount>");
		return Plugin_Handled;
	}
	
	iMaxCount = StringToInt(sIndex);
	if (iMaxCount < 40)
		iMaxCount = 40;
	
	char sTargetName[MAX_TARGET_LENGTH];
	int iTargetList[MAXPLAYERS], iTargetCount;
	bool bTargetIsML;
	
	if ((iTargetCount = ProcessTargetString(sTarget, iClient, iTargetList, MAXPLAYERS + 1, COMMAND_FILTER_ALIVE, sTargetName, sizeof(sTargetName), bTargetIsML)) <= 0)
	{
		ReplyToTargetError(iClient, iTargetCount);
		return Plugin_Handled;
	}
	
	for (int i = 0; i < iTargetCount; i++)
	{
		int iTarget = iTargetList[i];
		g_iPingCount[iTarget][0] = 0;
		g_iPingCount[iTarget][1] = iMaxCount;
		g_flNextPingTime[iTarget] = 0.0;
		
		DataPack dPack;
		g_hPingTimer[iTarget] = CreateDataTimer(0.1, Timer_PingClient, dPack, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		dPack.WriteCell(GetClientUserId(iTarget));
		dPack.WriteCell(iIndex);
	}
	
	char sClientName[MAX_NAME_LENGTH];
	GetClientName(iClient, sClientName, sizeof(sClientName));
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i)) continue;
		if (CheckCommandAccess(i, "showadminactivity", ADMFLAG_GENERIC))
		{
			PrintToChat(i, "[SM] %s Pinged %s", sClientName, sTargetName);
		}
	}

	return Plugin_Handled;
}

public Action Timer_PingClient(Handle hTimer, DataPack dPack)
{
	dPack.Reset();
	int iClient = GetClientOfUserId(dPack.ReadCell());
	if (!iClient)
		return Plugin_Stop;
	
	if (hTimer != g_hPingTimer[iClient])
		return Plugin_Stop;
	
	if (!IsClientInGame(iClient) || !IsPlayerAlive(iClient))
		return Plugin_Stop;
	
	int iCount = g_iPingCount[iClient][0];
	int iMaxCount = g_iPingCount[iClient][1];
	if (iCount >= iMaxCount)
		return Plugin_Stop;
	
	float flGameTime = GetGameTime();
	if (g_flNextPingTime[iClient] > flGameTime)
		return Plugin_Continue;
		
	int iThreshold[4];
	iThreshold[0] = iMaxCount / 10;
	iThreshold[1] = iMaxCount / 8;
	iThreshold[2] = iMaxCount / 4;
	iThreshold[3] = iMaxCount / 2;
	
	float flTime = 0.0;
	if (iCount <= iThreshold[0])
		flTime = 1.0;
	else if (iCount <= iThreshold[1])
		flTime = 0.6;
	else if (iCount <= iThreshold[2])
		flTime = 0.3;
	else if (iCount <= iThreshold[3])
		flTime = 0.1;
	
	g_iPingCount[iClient][0]++;
	g_flNextPingTime[iClient] = flGameTime + flTime;
	PingClient(iClient, dPack.ReadCell());
	return Plugin_Continue;
}

void PingClient(int iClient, int iIndex)
{
	int iSprite = CreatePing(iIndex);
	if (iSprite <= MaxClients) return;
	
	float vecPos[3], vecAng[3];
	GetClientAbsOrigin(iClient, vecPos);
	GetClientAbsAngles(iClient, vecAng);
	GetPositionForward(vecPos, vecAng, vecPos, GetRandomFloat(60.0, 80.0));

	vecPos[1] += GetRandomInt(0, 1) == 0 ? GetRandomFloat(-70.0, 0.0) : GetRandomFloat(0.0, 70.0);
	vecPos[2] += GetRandomFloat(30.0, 90.0);
	
	TeleportEntity(iSprite, vecPos, NULL_VECTOR, NULL_VECTOR);
	
	int iProp = CreateEntityByName("prop_dynamic_override");
	if (iProp > MaxClients)
	{
		DispatchKeyValue(iProp, "targetname", PINGNAME);
		DispatchKeyValue(iProp, "model", EMPTY);
		DispatchSpawn(iProp);
		
		SetEntProp(iProp, Prop_Send, "m_nSolidType", 0);
		TeleportEntity(iProp, vecPos, NULL_VECTOR, NULL_VECTOR);
		
		SetVariantString("!activator");
		AcceptEntityInput(iSprite, "SetParent", iProp);
		
		SetVariantString("!activator");
		AcceptEntityInput(iProp, "SetParent", iClient);
	}
	
	int iParticle = g_iPingParticle[iIndex];
	if (iParticle != -1)
	{
		TE_Particle(iParticle, vecPos, vecPos);
		TE_SendToAllInRange(vecPos, RangeType_Visibility);
	}
	
	int iSoundIndex = g_iPingSoundCount[iIndex];
	if (iSoundIndex > 0)
		iSoundIndex = GetRandomInt(0, iSoundIndex);
		
	char sSound[PLATFORM_MAX_PATH];
	Format(sSound, sizeof(sSound), "#%s", g_sPingSounds[iIndex][iSoundIndex]);
	EmitSoundToAll(sSound, iClient, _, g_iPingSoundLevel[iIndex], _, g_flPingSoundVolume[iIndex], g_iPingSoundPitch[iIndex]);
	
	CreateTimer(1.0, Timer_KillEntity, EntIndexToEntRef(iSprite), TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(1.0, Timer_KillEntity, EntIndexToEntRef(iProp), TIMER_FLAG_NO_MAPCHANGE);
}

int CreatePing(int iIndex)
{
	int iSprite = CreateEntityByName("env_sprite");
	if (iSprite > MaxClients)
	{
		DispatchKeyValue(iSprite, "targetname", PINGNAME); 
		DispatchKeyValue(iSprite, "spawnflags", "1"); 
		DispatchKeyValue(iSprite, "rendermode", "1");
		DispatchKeyValue(iSprite, "scale", "0.05");
		DispatchKeyValue(iSprite, "rendercolor", "255 255 255");
		DispatchKeyValue(iSprite, "model", g_sPingSprite[iIndex]);
		DispatchSpawn(iSprite);
	}
	
	return iSprite;
}

// =====================================================================
// 				STOCKS		STOCKS		STOCKS		STOCKS				
// =====================================================================

public Action Timer_KillEntity(Handle hTimer, int iRef)
{
	int iEnt = EntRefToEntIndex(iRef);
	if (iEnt > MaxClients && IsValidEntity(iEnt))
	{
		AcceptEntityInput(iEnt, "KillHierarchy");
	}
}

stock void GetPositionForward(float vPos[3], float vAng[3], float vReturn[3], float fDistance)
{
	float vDir[3];
	GetAngleVectors(vAng, vDir, NULL_VECTOR, NULL_VECTOR);
	vReturn = vPos;
	for (int i = 0; i < 3; i++)
		vReturn[i] += vDir[i] * fDistance;
}

stock void PrecacheMaterial2(const char[] path)
{
	char buffer[PLATFORM_MAX_PATH];
	Format(buffer, sizeof(buffer), "materials/%s.vmt", path);
	AddFileToDownloadsTable(buffer);
	Format(buffer, sizeof(buffer), "materials/%s.vtf", path);
	AddFileToDownloadsTable(buffer);
}

stock void PrecacheSound2(const char[] path)
{
	PrecacheSound(path, true);
	
	char buffer[PLATFORM_MAX_PATH];
	Format(buffer, sizeof(buffer), "sound/%s", path);
	AddFileToDownloadsTable(buffer);
}

stock int PrecacheParticleSystem(const char[] sParticleSystem)
{
	static int iParticleEffectNames = INVALID_STRING_TABLE;
	if (iParticleEffectNames == INVALID_STRING_TABLE) 
	{
		if ((iParticleEffectNames = FindStringTable("ParticleEffectNames")) == INVALID_STRING_TABLE) 
		{
			return INVALID_STRING_INDEX;
		}
	}

	int iIndex = FindStringIndex2(iParticleEffectNames, sParticleSystem);
	if (iIndex == INVALID_STRING_INDEX)
	{
		int iNumStrings = GetStringTableNumStrings(iParticleEffectNames);
		if (iNumStrings >= GetStringTableMaxStrings(iParticleEffectNames))
		{
			return INVALID_STRING_INDEX;
		}
		
		AddToStringTable(iParticleEffectNames, sParticleSystem);
		iIndex = iNumStrings;
	}
	
	return iIndex;
}

stock int FindStringIndex2(int iTableIndex, const char[] sString)
{
	char sBuffer[1024];
	int iNumStrings = GetStringTableNumStrings(iTableIndex);
	for (int i = 0; i < iNumStrings; i++)
	{
		ReadStringTable(iTableIndex, i, sBuffer, sizeof(sBuffer));
		if (StrEqual(sBuffer, sString))
		{
			return i;
		}
	}
	
	return INVALID_STRING_INDEX;
}

stock void TE_Particle(int iParticleIndex, float vecOrigin[3] = NULL_VECTOR, float vecStart[3] = NULL_VECTOR, float vecAngles[3] = NULL_VECTOR, int iEntIndex = -1, int iAttachType = -1, int iAttachPoint = -1, bool bResetParticles = true)
{
	TE_Start("TFParticleEffect");
	TE_WriteFloat("m_vecOrigin[0]", vecOrigin[0]);
	TE_WriteFloat("m_vecOrigin[1]", vecOrigin[1]);
	TE_WriteFloat("m_vecOrigin[2]", vecOrigin[2]);
	TE_WriteFloat("m_vecStart[0]", vecStart[0]);
	TE_WriteFloat("m_vecStart[1]", vecStart[1]);
	TE_WriteFloat("m_vecStart[2]", vecStart[2]);
	TE_WriteVector("m_vecAngles", vecAngles);
	TE_WriteNum("m_iParticleSystemIndex", iParticleIndex);
	TE_WriteNum("entindex", iEntIndex);

	if (iAttachType != -1)
	{
		TE_WriteNum("m_iAttachType", iAttachType);
	}
	if (iAttachPoint != -1)
	{
		TE_WriteNum("m_iAttachmentPointIndex", iAttachPoint);
	}

	TE_WriteNum("m_bResetParticles", bResetParticles ? 1 : 0);
}