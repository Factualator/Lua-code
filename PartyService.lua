local PartyService = {}
PartyService.__index = PartyService

-------------------// SERVICES \\--------------------

local TeleportService = game:GetService("TeleportService")
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local AS = game:GetService("AnalyticsService")
local HTTPS = game:GetService("HttpService")
local Players = game:GetService("Players")

--------------------// MODULES \\--------------------

local ModuleLoader = require(SSS.Server.ServerManager.ModuleLoader)
local Utilities = require(RS.Shared.Utilities.GeneralUtilities)
local BridgetNet2 = require(RS.Packages.BridgeNet2)
local Bridges = require(RS.Shared.Bridges)

--------------------// REMOTES \\--------------------

local Signals = RS.Signals
local Functions = Signals.Functions
local Bindables = Signals.Bindables

------------------// REFERENCES \\-------------------

--// Variables
local activeInvites = {}
local party = {}
local DEST_PLACE_ID = 108258187781438

----------------// INITIALIZATION \\-----------------

function PartyService.init()

	----------------// EVENTS \\----------------
	
	Bridges.StartMatch:Connect(function(hostPlr)
		PartyService.StartMatch(hostPlr)
	end)
	
	Bridges.InvitePlayer:Connect(function(inviterPlr, data)
		PartyService.SendInvite(inviterPlr, data.invitee)
	end)

	Bridges.AcceptInvite:Connect(function(joinerPlr, data)
		PartyService.JoinParty(joinerPlr, data.hostName)
	end)

	Bridges.KickPartyMember:Connect(function(hostPlr, data)
		PartyService.KickMember(hostPlr, data.targetUserId, data.selfLeave)
	end)

	-- Store device on server
	Bridges.DeviceUpdate:Connect(function(plr, data)
		if typeof(data) ~= "table" then return end

		local device = data.device
		if typeof(device) ~= "string" then return end

		-- Whitelist (Prevents spoofing)
		if device ~= "PC" and device ~= "Mobile" and device ~= "Console" then
			device = "Unknown"
		end

		plr:SetAttribute("Device", device)
	end)
end

function PartyService.SetupPlayer(player: Player)
	if not party[player] then
		party[player] = true

		local partyID = HTTPS:GenerateGUID(false)
		party[partyID] = {}
		table.insert(party[partyID], player)

		player:SetAttribute("PartyID", partyID)
	end
end

------------------// FUNCTIONS \\--------------------

local function cleanPlayers(list)
	local cleaned = {}
	for _, plr in ipairs(list) do
		if typeof(plr) == "Instance" and plr:IsA("Player") and plr.Parent == Players then
			table.insert(cleaned, plr)
		end
	end
	return cleaned
end

function PartyService.StartMatch(hostPlr: Player)
	local partyID = hostPlr:GetAttribute("PartyID")
	if not partyID or typeof(party[partyID]) ~= "table" then return end
	
	local members = cleanPlayers(party[partyID])
	if #members == 0 then return end
	
	if members[1] ~= hostPlr then
		Bridges.Notification:Fire(hostPlr, { message = "Only the host can start."})
		return
	end
	
	-- Reserve a private server so everyone goes to the same instance
	local accessCode
	local okReserve, errReserve = pcall(function()
		accessCode = (TeleportService:ReserveServerAsync(DEST_PLACE_ID))
	end)
	if not okReserve then
		warn("Reserve failed:", errReserve)
		Bridges.Notification:Fire(hostPlr, { message = "Could not reserve server." })
		return
	end

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	options:SetTeleportData({
		partyID = partyID,
		hostUserId = hostPlr.UserId,
	})

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(DEST_PLACE_ID, members, options)
	end)

	if not ok then
		warn("Teleport failed:", err)
		Bridges.Notification:Fire(hostPlr, { message = "Teleport failed. Try again." })
	end
end

-- A joiner player joins a host's party
function PartyService.JoinParty(joinerPlr: Player, hostName: string)
	local hostPlr: Player = nil
	for _, plr: Player in Players:GetChildren() do if plr.Name == hostName then hostPlr = plr end end
	if not hostPlr then 
		Bridges.Notification:Fire(joinerPlr, {
			message = "Invalid invite",
		})
		return
	end

	-- Getting Host's party ID
	local hostPartyId = hostPlr:GetAttribute("PartyID")
	if not hostPartyId then warn("[PartyService.JoinPart()] Could not find host's party ID") return end

	-- Cleaning Joiner Player's party existance from table
	local joinerPartyId = joinerPlr:GetAttribute("PartyID")
	local joinerMembers = joinerPartyId and party[joinerPartyId]
	if typeof(joinerMembers) == "table" then
		
		-- Only clear party table if there was only 1 person in it
		if #party[joinerPartyId] == 1 then 
			party[joinerPartyId] = nil

			-- Kick out the other person
		elseif #party[joinerPartyId] == 2 then
			local otherPlr: Player = nil
			for _, plr: Player in ipairs(party[joinerPartyId]) do
				if plr == joinerPlr then continue end
				otherPlr = plr
			end
			PartyService.KickMember(joinerPlr, otherPlr.UserId)
		end

		-- Set joiner's party ID to the host's party ID
		party[joinerPlr] = nil
		joinerPlr:SetAttribute("PartyID", hostPartyId)

		-- Notify existing members (Host and any current members)
		local msg = joinerPlr.Name .. " has joined the party"
		Bridges.Notification:Fire(BridgetNet2.Players(party[hostPartyId]), {
			message = Utilities.FormatText(msg, {joinerPlr.Name}, nil, true),
		})

		-- Adding Joiner Player to host's party table
		table.insert(party[hostPartyId], joinerPlr)

		-- Notifying all party members
		Bridges.AcceptInvite:Fire(BridgetNet2.Players(party[hostPartyId]), party[hostPartyId])
	end
end

-- Player leaves a party
function PartyService.LeaveParty(player: Player)
	local partyID = player:GetAttribute("PartyID")
	if not partyID then return end
	
	local members = party[partyID]
	if typeof(members) ~= "table" then return end
	
	local idx = table.find(members, player)
	if not idx then return end
	
	table.remove(members, idx)
	party[player] = nil
	
	if #members == 0 then
		party[partyID] = nil
		return
	end
	
	-- Notify player leaving to existing party members
	local msg = player.Name .. " has left the party"
	Bridges.Notification:Fire(BridgetNet2.Players(members), {
		message = Utilities.FormatText(msg, {player.Name}, nil, true),
	})
	
	-- Send info all party members
	Bridges.AcceptInvite:Fire(BridgetNet2.Players(members), members)
end

function PartyService.KickMember(hostPlr: Player, targetUserId: number, selfLeave: boolean?)
	if selfLeave then 
		PartyService.LeaveParty(hostPlr) 
		PartyService.SetupPlayer(hostPlr) 
		
		-- Notify left player
		task.defer(function()
			local newID = hostPlr:GetAttribute("PartyID")
			if newID and party[newID] then
				Bridges.AcceptInvite:Fire(hostPlr, party[newID])
			end
		end)
		return
	end
	
	local partyID = hostPlr:GetAttribute("PartyID")
	if not partyID then return end

	local members = party[partyID]
	if typeof(members) ~= "table" then return end

	-- only the host can kick (index 1)
	if members[1] ~= hostPlr then return end

	local targetPlr = Players:GetPlayerByUserId(targetUserId)
	if not targetPlr then return end

	local idx = table.find(members, targetPlr)
	if not idx or idx == 1 then return end -- Can't kick host

	table.remove(members, idx)
	party[targetPlr] = nil

	-- Give kicked player their own party again and notify they have been kicked
	PartyService.SetupPlayer(targetPlr)
	Bridges.Notification:Fire(targetPlr, {
		message = "You have been kicked out of the party",
	})

	-- Notify remaining party members
	Bridges.AcceptInvite:Fire(BridgetNet2.Players(members), members)
	
	local msg = targetPlr.Name .. " was kicked out of the party"
	Bridges.Notification:Fire(BridgetNet2.Players(members), {
		message = Utilities.FormatText(msg, {targetPlr.Name}, nil, true),
	})
	task.wait()
	
	-- Notify kicked player
	task.defer(function()
		local newID = targetPlr:GetAttribute("PartyID")
		if newID and party[newID] then
			Bridges.AcceptInvite:Fire(targetPlr, party[newID])
		end
	end)
end

-- Host sends an invite to a player
function PartyService.SendInvite(inviterPlr: Player, inviteeName: string): ()
	local inviteePlr: Player = nil
	for _, plr: Player in Players:GetChildren() do if plr.Name == inviteeName then inviteePlr = plr end end
	if not inviteePlr then 
		Bridges.Notification:Fire(inviterPlr, {
			message = "Player left the game",
		})
		return
	end
	if activeInvites[inviterPlr] then return end

	local invite = Bridges.InvitePlayer:Fire(inviteePlr, {inviter = inviterPlr.Name})
	activeInvites[inviterPlr] = invite

	task.delay(7, function()
		activeInvites[inviterPlr] = nil
	end)
end

function PartyService.CleanupPlayer(player: Player)
	PartyService.LeaveParty(player)
end

return PartyService
