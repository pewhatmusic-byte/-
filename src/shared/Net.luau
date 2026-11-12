--!strict
-- Remote registry. The server creates every remote at startup; the client waits for them.
--
-- RemoteEvents
--   Fishing : client -> server ("Cast", target) | ("Hook") | ("Finish", success) | ("Cancel")
--             server -> client ("Casted", bobberPos) | ("Bite") | ("Hooked", params) | ("Caught", fish, info) | ("Escaped", reason) | ("Reset", reason?)
--   Profile : server -> client ("Full", profile) | ("Patch", {key=value}) | ("FishAdded", fish) | ("FishRemoved", {uid}) | ("Bestiary", fishId, entry)
--   Notify  : server -> client (kind, text)   kind = "info" | "success" | "error" | "levelup" | "discover" | "dialogue"
--   Interact: server -> client ("OpenWindow", windowName, payload)
-- RemoteFunctions (client -> server, all return { ok = boolean, message = string?, ... })
--   GetProfile(), SellFish(uids | "all"), Purchase(kind, id, amount?), Equip(kind, id?), DiscardFish(uid)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Events = { "Fishing", "Profile", "Notify", "Interact" }
Net.Functions = { "GetProfile", "SellFish", "Purchase", "Equip", "DiscardFish" }

local folder: Folder? = nil

local function getFolder(): Folder
	if folder then
		return folder
	end
	local result: Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild("Remotes")
		if existing and existing:IsA("Folder") then
			result = existing
		else
			local f = Instance.new("Folder")
			f.Name = "Remotes"
			f.Parent = ReplicatedStorage
			result = f
		end
	else
		result = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	folder = result
	return result
end

-- Server only: create every remote up front so clients can WaitForChild safely.
function Net.Init()
	assert(RunService:IsServer(), "Net.Init is server-only")
	local f = getFolder()
	for _, name in ipairs(Net.Events) do
		if not f:FindFirstChild(name) then
			local ev = Instance.new("RemoteEvent")
			ev.Name = name
			ev.Parent = f
		end
	end
	for _, name in ipairs(Net.Functions) do
		if not f:FindFirstChild(name) then
			local fn = Instance.new("RemoteFunction")
			fn.Name = name
			fn.Parent = f
		end
	end
end

function Net.Event(name: string): RemoteEvent
	local f = getFolder()
	if RunService:IsServer() then
		local ev = f:FindFirstChild(name)
		assert(ev and ev:IsA("RemoteEvent"), "Unknown RemoteEvent " .. name)
		return ev
	end
	return f:WaitForChild(name) :: RemoteEvent
end

function Net.Function(name: string): RemoteFunction
	local f = getFolder()
	if RunService:IsServer() then
		local fn = f:FindFirstChild(name)
		assert(fn and fn:IsA("RemoteFunction"), "Unknown RemoteFunction " .. name)
		return fn
	end
	return f:WaitForChild(name) :: RemoteFunction
end

export type Response = { ok: boolean, message: string?, [string]: any }

-- Client only: invoke a RemoteFunction safely. Always returns a response table.
function Net.Invoke(name: string, ...: any): Response
	assert(RunService:IsClient(), "Net.Invoke is client-only")
	local fn = Net.Function(name)
	local success, result = pcall(fn.InvokeServer, fn, ...)
	if not success then
		warn("[Net] " .. name .. " failed: " .. tostring(result))
		return { ok = false, message = "Request failed, try again." }
	end
	if type(result) ~= "table" then
		return { ok = false, message = "Bad response." }
	end
	return result
end

return Net
