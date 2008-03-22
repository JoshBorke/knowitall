--[[ The tree format will be arranged to separate the content from the meta
	metadata.  All data fields will be contained within a data table.
	Thus, the format of a tree is:

	treeName = {
		name = <string>, -- name of the current node
		path = <string>, -- full path to this node
		treeModTime = <number>, -- to hold the maximum of all branch node times
		nodeModeTime = <number>, -- to hold the modification of this branch
		data = <table>, -- table to hold the generic data
		nodeSync = <boolean>, -- holds if the local node is synchronized
		treeSync = <boolean>, -- holds if the full tree is synchronized
		branches = {
			'treeBranch1', 'treeBranch2', 'treeBranch3', ...,
			['treeBranch1'] = {
				treeModTime = <number>,
				nodeModTime = <number>,
				data = <table>,
				branches = {},
			},
		}
	}

	comparing 2 trees:
	it's not practical to have entire copies of both trees locally, too much data would need to be transferred.
	comparisons have to be made tree node by tree node
	propogate treeModTime up the tree for quick comparisons
	compare nodeModTime to check the current node

	generate new tables for comparing nodes, the format should be:
	treeName = {
		treeModTime = <number>,
		nodeModeTime = <number>,
		branches = {
			['treeBranch1'] = <string>, -- string being treeModTime:nodeModTime
			etc
		}
	}

	compare the 2 tree entries if the local node is newer then send the local nodes information out
	if the remote node is newer, then request the node information
	data can be populated at any time which means we can continue processing the sub trees


	commands will be sent: <command>:<everything else> through AceSerializer-3.0 (for splitting up messages)
	]]--

local major, minor = "TreeSync-1.0", 1
local treeSync = LibStub:NewLibrary(major, minor)
if not treeSync then return end

local AceComm = LibStub:GetLibrary("AceComm-3.0")
local serializer = LibStub:GetLibrary("AceSerializer-3.0")
local myprefix = "GB"
local sep = '\004'
local __me = UnitName('player')

local smatch,format = string.match, string.format
local next, pairs, type, tostring = next, pairs, type, tostring
local abs, GetTime = math.abs, GetTime
local tremove, tinsert = table.remove, table.insert
local thisPlayer = UnitName('player')
local nodeCompareTables, nodeSendTables = {}, {}
local synched = {}
local timeOffsets = {}
local targetCommands = {}
local responseQue, requestQue, announceQue = {}, {}, {}
local pathToNode = {}
local registeredPrefix = {}
local rootNode

local debug = true
local logFile = {}

local function log(msg, ...)
	local msg = format(msg, ...)
	tinsert(logFile, msg)
	if debug then
		ChatFrame1:AddMessage(msg)
	end
end

do
	local telapsed = 0
	local function _onUpdate(f, elapsed)
		telapsed = telapsed + elapsed
		local path, command
		if telapsed > 0.5 then
			-- process 1 response message
			repeat
				path = tremove(responseQue,1)
				command = targetCommands[path]
			until (command or not path)
			if path and command then
				targetCommands[path] = nil
				AceComm:SendCommMessage(myprefix, command, "GUILD", nil, "BULK")
			end
			-- process 1 request message
			command = tremove(requestQue, 1)
			if command then
				AceComm:SendCommMessage(myprefix, command, "GUILD", nil, "BULK")
			end
			-- process 1 announce message
			command = tremove(announceQue, 1)
			if command then
				AceComm:SendCommMessage(myprefix, command, "GUILD", nil, "BULK")
			end
			telapsed = 0
		end
	end
	local f = CreateFrame("Frame")
	f:SetScript("OnUpdate", _onUpdate)
	f:Show()
end

local function cpyTbl(origTbl)
	local t = {}
	for k, v in pairs(origTbl) do
		log(format("key: %s value: %s", tostring(k), tostring(v)))
		if type(k) == "table" then k = cpyTbl(k) end
		if (type(v) == "table" and v ~= origTbl) then v = cpyTbl(v) end
		t[k] = v
	end
	return t
end

local function generateComparisonTable(treeNode)
	local t = next(nodeCompareTables) or { ['branches'] = {} }
	nodeCompareTables[t] = nil
	t.treeModTime = treeNode.treeModTime
	t.nodeModTime = treeNode.nodeModTime
	t.path = treeNode.path
	local b = t.branches
	for branch, info in pairs(treeNode.branches) do
		b[branch] = format("%d:%d",info.treeModTime, info.nodeModTime)
	end
	return t
end

local function returnComparisonTable(t)
	local b = t.branches
	for k, v in pairs(b) do
		b[k] = nil
	end
	b[true]=true
	b[true]=nil
	nodeCompareTables[t] = true
end

local function generateSendTable(treeNode)
	local t = next(nodeSendTables) or {}
	nodeSendTables[t] = nil
	t.data = cpyTbl(treeNode.data)
	t.path = treeNode.path
	t.treeModTime = treeNode.treeModTime
	t.nodeModTime = treeNode.nodeModTime
	return t
end

local function returnSendTable(t)
	t.path = nil
	nodeSendTables[t] = true
end

local function normalizeTimes(sentNode, sender)
	local offset = timeOffsets[sender] or 0
	sentNode.treeModTime = sentNode.treeModTime + offset
	sentNode.nodeModTime = sentNode.nodeModTime + offset
	if (sentNode.branches) then
		for branch, times in pairs(sentNode.branches) do
			local rTreeTime, rNodeTime = smatch(times, "(%d+):(-?%d+)")
			sentNode.branches[branch] = format("%d:%d", rTreeTime + offset, rNodeTime + offset)
		end
	end
	return sentNode
end

local function sendResponse(command, path)
	tinsert(responseQue, path)
	targetCommands[path] = command
end

local function updatePaths(treeNode, path)
	pathToNode[path] = treeNode
	if (treeNode.branches) then
		for branch, info in pairs(treeNode.branches) do
			updatePaths(info, format("%s%s%s",path,sep,branch))
		end
	end
end

local function sendRequest(command, path)
	tinsert(requestQue, command)
end

local function sendAnnounce(command)
	tinsert(announceQue, command)
end

local function getLocalNode(path)
	return pathToNode[path]
end

-- this sends data for remote copies to update against
local function sendNodeData(localTreeNode)
	local t = generateSendTable(localTreeNode)
	local serialized = serializer:Serialize("sendNodeData", t)
	sendResponse(serialized, t.path)
	returnSendTable(t)
end

-- this sends an entire tree to be synced against
local function sendTree(localTreeNode)
	sendNodeData(localTreeNode)
	for branch, info in pairs(localTreeNode.branches) do
		sendNodeData(info)
	end
end

-- this requests for node data to be sent so the local copy can update
local function requestNodeData(localTreeNode)
	local serialized = serializer:Serialize("requestNodeData", localTreeNode.path)
	sendRequest(serialized, localTreeNode.path)
end

-- this requests that a synchronizing message be sent for comparison
local function requestTreeSync(localTreePath)
	local serialized = serializer:Serialize("requestTreeSync", localTreePath)
	sendRequest(serialized, localTreePath)
end

-- this propogates the sync attribute to an entire tree
local function syncTree(treeNode, synced)
	if not treeNode then return end
	if (treeNode.branches) then
		for branch, info in pairs(treeNode.branches) do
			info.nodeSync = synced
			info.treeSync = synced
			syncTree(info, synced)
		end
	end
end

local function checkSync(treeNode)
	if not treeNode.nodeSync then return false end
	local synced = true
	for branch, info in pairs(treeNode.branches) do
		synced = synced and checkSync(info)
	end
	return synced
end

local function processTree(localTreeNode, remoteTree)
	local localTree = generateComparisonTable(localTreeNode)
	local localModTime = abs(localTree.nodeModTime)
	local remoteModTime = abs(remoteTree.remoteModTime)
	if localModTime > remoteModTime then
		-- send this branch data
		sendNodeData(localTreeNode) -- this function should handle if it is deleted
		localTreeNode.nodeSync = true
	elseif localModTime < remoteModTime then
		-- request this branch data
		requestNodeData(localTreeNode) -- go ahead and get the last valid data
		localTreeNode.nodeSync = false
	else
		localTreeNode.nodeSync = true
		-- they are the same
	end
	if localTreeNode.treeModTime ~= remoteTree.treeModTime then
		syncTree(localTreeNode, false)
		for rNode, timestamps in pairs(remoteTree.branches) do
			local rTreeTime, rNodeTime = smatch(timestamps, "(%d+):(-?%d+)")
			local lNode = localTreeNode.branches[rNode]
			local lTreeTime, lNodeTime
			if lNode then
				lTreeTime, lNodeTime = lNode.treeModTime, lNode.nodeModTime
			end
			if not lNode or lTreeTime ~= rTreeTime or lNodeTime ~= rNodeTime then
				requestTreeSync(localTreeNode.path .. '>'.. lNode)
			else
				lNode.nodeSync = true
				lNode.treeSync = true
				syncTree(lNode, true)
			end
		end
		for lNode, timestamps in pairs(localTree.branches) do
			local lTreeTime, lNodeTime = smatch(timestamps, "(%d+):(-?%d+)")
			local timestamp = remoteTree.branches[lNode]
			local rTreeTime, rNodeTime
			if timestamp then
				rTreeTime, rNodeTime = smatch(timestamp, "(%d+):(-?%d+)")
				if lTreeTime ~= rTreeTime or lNodeTime ~= rNodeTime then
					requestTreeSync(localTreeNode.path .. '>'.. lNode)
				end
			else
				sendTree(localTreeNode.branches[lNode])
			end
		end
	else
		syncTree(localTreeNode, true)
	end
	returnComparisonTable(localTree)
end

local commandParsers = {
	-- this RECEIVES the data
	['sendNodeData'] = function(sentNode, sender, target)
		normalizeTimes(sentNode, sender)
		-- if we don't know about the node, then create a table to hold teh
		-- data
		local lNode = getLocalNode(sentNode.path) or { ['branches'] = {} }
		lNode.data = cpyTbl(sentNode.data)
		lNode.nodeModTime = sentNode.nodeModTime
		lNode.nodeSync = true
		lNode.treeSync = checkSync(lNode)
	end,
	-- this SENDS the data
	['requestNodeData'] = function(path, sender)
		local lNode = getLocalNode(path)
		if lNode and synched[path] then
			local lNodeSend = generateSendTable(lNode)
			local data = serializer:Serialize("sendNodeData", lNodeSend, sender)
			AceComm:SendCommMessage(myprefix, data, "GUILD", "BULK")
			returnSendTable(lNodeSend)
		end
	end,
	-- this SENDS a comparison table
	['requestTreeSync'] = function(path, sender)
		local lNode = getLocalNode(path)
		if lNode and synched[path] then
			local lNodeSend = generateComparisonTable(lNode)
			local data = serializer:Serialize("sendNodeSync", lNodeSend, sender)
			AceComm:SendCommMessage(myprefix, data, "GUILD", "BULK")
			returnComparisonTable(lNodeSend)
		end
	end,
	-- this RECEIVES a comparison table
	['sendNodeSync'] = function(rNode, sender, target)
		if target and target ~= thisPlayer then
			targetCommands[rNode.path] = nil
			-- clear que for the target
			return
		end
		normalizeTimes(rNode, sender)
		local lNode = getLocalNode(rNode.path)
		if not lNode then
			requestNodeData(rNode.path)
			return
		end
		processTree(lNode, rNode)
	end,
	-- this RECEIVES a time broadcast (on initial login)
	['timeLogin'] = function(time, sender)
		timeOffsets[sender] = GetTime() - time
		local data = serializer:Serialize("timeResponse", GetTime(), sender)
		AceComm:SendCommMessage(myprefix, data, "GUILD", "ALERT")
		log("Sent response to a timeLogin: %s", data)
	end,
	-- this RECEIVES a time broadcast (in reply to login)
	['timeResponse'] = function(time, sender)
		timeOffsets[sender] = GetTime() - time
	end,
}
local function processMessage(prefix, message, distribution, sender)
	log("processMessage: %s, %s, %s", message, distribution, (sender or 'unknown sender'))
	if distribution == "GUILD" and sender ~= __me then
		local success, command, data, target = serializer:Deserialize(message)
		if not success then ChatFrame1:AddMessage("Bad: "..tostring(command)) return end
		log(format("Command: %s\n\tParam: %s", command, tostring(data)))
		local func = commandParsers[command]
		if func and type(func) == "function" then
			func(data, sender, target)
		end
	end
end

function treeSync:RegisterTable(prefix, root)
	AceComm:RegisterComm(prefix, processMessage)
	rootNode = root
	registeredPrefix[prefix] = root
	log(format("RegisterTable: prefix: %s", (prefix or "Unknown prefix")))
	updatePaths(root, sep)
	local data = serializer:Serialize("timeLogin", GetTime())
	AceComm:SendCommMessage(prefix, data, "GUILD", nil, "ALERT")
	log(format("Sent timeLogin: %s", data))
	syncTree(root, true)
	requestTreeSync(sep)
end

function treeSync:SendUpdate(prefix, localTreeNode)
	if not registeredPrefix[prefix] then return end
	log(format("SendUpdate: path: %s", (localTreeNode.path or 'Unknown path')))
	local t = generateSendTable(localTreeNode)
	local serialized = serializer:Serialize("sendNodeData", t)
	sendAnnounce(serialized)
	returnSendTable(t)
end

treeSync.log = logFile
