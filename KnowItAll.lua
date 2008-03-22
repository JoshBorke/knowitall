-- Here we go
--
--
--
-- for speedups
local _
local pairs = pairs

local treeSync = LibStub and LibStub:GetLibrary("TreeSync-1.0", true)
local md5sum = LibStub and LibStub:GetLibrary("MDFive-1.0", true)

local _now -- for time stamps
local _version = '0.14-20003'
local _rank = {}
local _playerName = UnitName('player')
local _L

if (not KnowItAll) then KnowItAll = {} end
if (not KnowItAll.crc) then KnowItAll.crcs = {} end
if (not print) then print = function(msg) DEFAULT_CHAT_FRAME:AddMessage(msg) end end
if (not UnitName) then UnitName = function(unit) return 'Hamarian' end end
if (not time) then time = os.time end
local paths = {}
local nodeParents = {}

KnowItAll.timeDiff = 0

local function _copyTbl(src,dst)
	dst['content'] = src['content']
	dst['tagline'] = src['tagline']
	dst['author'] = src['author']
	dst['timestamp'] = src['timestamp']
end

function KnowItAll.Error(func,msg)
	DEFAULT_CHAT_FRAME:AddMessage(string.format('GB Error (%s): %s',func,KnowItAll.localise(msg)))
end

function KnowItAll.localise(msg)
	return ((msg and KnowItAll.localisation[msg]) or msg or 'no msg passed to localise')
end

function KnowItAll.GetTime()
	return time() + KnowItAll.timeDiff
end

function KnowItAll.ImportNode(node, path)
	nodeParents[node] = parent
	parent['branches'][node.name] = node
	while (parent) do
		parent['treeModTime'] = math.max(node.treeModTime,parent['treeModTime'] or 0)
		node = parent
		parent = parent.data['parent']
	end
end

-- updated to KnowItAll Ace3
function KnowItAll.AddData(name,tagline,content,parent,author,timestamp,
	                       editors,deleters,perms,key,remote)
	local _now = KnowItAll.GetTime()
	if (not name) then
		KnowItAll.Error('AddData','No name passed')
		return false
	end
	if (not parent) then parent = getglobal('KnowItAllKB') end
	if (parent and parent['branches'] and parent['branches'][name]) then
		KnowItAll.ModifyData(parent['branches'][name],name,tagline,contente,author,timestamp,editors,deleters,perms,key,remote)
		return
	end
	local node = {
		name = name,
		treeModTime = timestamp or _now,
		nodeModTime = timestamp or _now,
		path = (parent.path or KnowItAll.GetTreePath(parent)) .. '>' .. name,
		branches = {},
		data = {
			['content'] = content or tagline or name,
			['tagline'] = tagline or summary or name,
			['author'] = author or UnitName('player'),

			--['parent'] = parent or getglobal('KnowItAllKB'),
			['name'] = name,
			['hash2'] = key,
			['editors'] = editors or parent['editors'],
			['deleters'] = deleters or parent['deleters'],
		}
	}
	if md5sum then
		node.data.hash1 = md5sum:ComputeHash(node.data)
	end
	nodeParents[node] = parent
	if (not parent['branches']) then parent['branches'] = {} end
	parent['branches'][name] = node
	while (parent) do
		parent['treeModTime'] = math.max(_now,parent['treeModTime'] or 0)
		parent = parent.data['parent']
	end
	-- this sends the change over the line
	if (not remote) then
		treeSync:SendUpdate("GB", node)
	end
	return node
end

-- updated to Ace3
function KnowItAll.ModifyData(node,name,tagline,content,author,timestamp,editors,deleters,perms,key,remote)
	if (not node) then
		KnowItAll.Error('ModifyData','Node not passed')
		return
	end
	local parent = nodeParents[node]
	local data = node.data
	data['content'] = content or data['content']
	data['tagline'] = tagline or data['tagline']
	data['author'] = author or data['author']
	data['editors'] = editors or data['editors']
	data['deleters'] = deleters or data['deleters']
	node.nodeModTime = timestamp or node.nodeModTime
	node.treeModTime = math.max(node.treeModTime or 0,node.nodeModTime or 0)
	if (name and data.name ~= name) then
		local parent = nodeParents[node]
		parent['branches'][name] = parent['branches'][data['name']]
		parent['branches'][data['name']] = nil
		data['name'] = name or data['name']
	end
	while (parent) do
		parent['treeModTime'] = math.max(node.treeModTime,parent['treeModTime'])
		node = parent
		parent = nodeParents[parent]
	end
	-- this sends the change over the line
	--if (node['synch'] and author == _playerName and not remote) then KnowItAllSynch:ModifyData(node,nil,remote) end
end

-- update to Ace3
function KnowItAll.RemData(nameOrNode,parent,remote)
	local name = nameOrNode
	if (type(nameOrNode) == 'table') then
		parent = nodeParents[nameOrNode]
		name = nameOrNode.data['name']
	end
	if (not parent) then
		KnowItAll.Error('RemData','No parent passed')
		return false
	elseif (not parent['branches']) then
		KnowItAll.Error('RemData','Invalid parent passed')
		return false
	end
	--if data.nodeModTime > 0 then -- make sure it isn't deleted
	local tbl = parent['branches'][name]
	tbl.nodeModTime = format("-%d",time())
	--[[tbl.parent = nil -- don't remove the reference
	--parent['objects'][name] = nil -- don't remove the reference
	if (tbl.objects) then
		for obj,_ in pairs(tbl.objects) do
			KnowItAll.DelData(obj,tbl)
		end
	end]]--
	-- this sends the change over the line
	--if (tbl.synch and not remote) then KnowItAllSynch:RemData(tbl) end
end

function KnowItAll.DelData(nameOrNode,parent)
	local name = nameOrNode
	if (type(nameOrNode) == 'table') then
		parent = nameOrNode['parent']
		name = nameOrNode['name']
	end
	if (not parent) then
		KnowItAll.Error('RemData','No parent passed')
		return false
	elseif (not parent['branches']) then
		KnowItAll.Error('RemData','Invalid parent passed')
		return false
	end
	local tbl = parent['branches'][name]
	parent['branches'][name] = nil
	if (tbl.branches) then
		for obj,_ in pairs(tbl.branches) do
			KnowItAll.RemData(obj,tbl)
		end
	end
end

function KnowItAll.RestoreParents(node)
	if (not node) then return end
	if (node and type(node) == 'table' and node['branches']) then
		for name,tbl in pairs(node['branches']) do
			nodeParents[tbl] = node
			KnowItAll.RestoreParents(tbl)
		end
	end
end

function KnowItAll.SetKey(node,key)
	node.key = key
end

function KnowItAll.CheckKey(node,key)
	return KnowItAllSynch:ComputeHash(key) == node.hash2
end

function KnowItAll.DumpNode(node)
	print(KnowItAll.GetTreePath(node))
	for k,v in pairs(node) do
		if (type(v) ~= 'table') then
			print(string.format('%s: %s',k,v))
		end
	end
end

function KnowItAll.GetNode(name,root)
	return root['branches'][name]
end

-- returns a string
-- update to Ace3
function KnowItAll.GetTreePath(node)
	if (not node) then
		KnowItAll.Error('GetTreePath','No node passed')
		return
	end
	local path = tostring(node.data.name)
	local parent = nodeParents[node]
	while (parent) do
		path = parent.data.name..'>'..path
		parent = nodeParents[parent]
	end
	return path
end

-- takes a string, returns a node or nil
-- updated to KnowItAll Ace3
function KnowItAll.TraverseTreePath(path)
	local newPath
	if (not path) then
		return KnowItAllKB
	end
	if (not string.find(path,'>')) then return getglobal(path) end
	local stopName = string.match(path,'^.+>(.-)$')
	local nodeName,path = string.match(path,'^(.-)>(.+)$')
	local node = getglobal(nodeName)
	if (node and node['branches']) then
		nodeName,newPath = string.match(path,'^(.-)>(.+)$')
		if (newPath) then path = newPath end
		while (newPath and node['branches'] and node['branches'][nodeName]) do
			node = node['branches'][nodeName]
			nodeName,newPath = string.match(path,'^(.-)>(.+)$')
			if (newPath) then path = newPath end
		end
		if (node and node['branches'] and node['branches'][path] and node['branches'][path]['data']['name'] == stopName) then
			return node['branches'][path]
		end
	end
	return nil
end

-- update to KnowItAll Ace3
local sTbl = {}
function KnowItAll.GetContent(node)
	if (not node) then return '' end
	local str= string.format('<HTML><BODY>%s<p align="right">By %s</p>',node.data['content'],node.data['author']) or ''
	if (node['branches']) then
		str= string.format('%s<p align="left">-------<br/>',str)
		for k, v in pairs(sTbl) do sTbl[k] = nil end
		for name,data in pairs(node['branches']) do
			if name and type(data) == "table" then
				if data.nodeModTime and data.nodeModTime > 0 then -- make sure it isn't deleted
					if data.data.tagline then -- make sure it has a tagline
						tinsert(sTbl, name)
					end
				end
			end
		end
		table.sort(sTbl)
		for i=1,#sTbl do
			local name,tbl = sTbl[i],node['branches'][sTbl[i]]
			str= string.format('%s<A href="%s">%s</A>: %s<BR/>',str,name,name,tbl.data.tagline)
		end
		str= string.format('%s</p>',str)
	end
	str = string.format('%s</BODY></HTML>',str)
	return str
end

function KnowItAll.ValidateContent(text)
	-- jump out for now, eventually i'll actually do something here
	return true
end

function KnowItAll.CommandHandler(msg)
	msg = string.lower(msg)
	if (msg == 'show') then
		KnowItAllFrame:Show()
	elseif (msg == 'hide') then
		KnowItAllFrame:Hide()
	elseif (msg == 'resetkb') then
		KnowItAll.ResetKB()
	elseif (msg == 'resetsync') then
		KnowItAll.ResetSync()
	elseif (msg == 'version') then
		DEFAULT_CHAT_FRAME:AddMessage(string.format('|cFFFFFF00KnowItAll|r: version %s',_version))
	elseif (msg == '' or not msg) then
		if (KnowItAllFrame:IsVisible()) then
			KnowItAllFrame:Hide()
		else
			KnowItAllFrame:Show()
		end
	--[[elseif (msg == 'sync') then
		if (KnowItAllSynch:IsEnabled()) then
			--KnowItAllSynch:Disable()
			KnowItAllOptions.sync.enabled = false
			DEFAULT_CHAT_FRAME:AddMessage(string.format('|cFFFFFF00KnowItAll|r: Synchronization is now |cFFFF0000disabled|r.'))
		else
			DEFAULT_CHAT_FRAME:AddMessage(string.format('|cFFFFFF00KnowItAll|r: Synchronization is now |cFF00FF00enabled|r.'))
			KnowItAllOptions.sync.enabled = true
			--KnowItAllSynch:Enable()
		end]]
	elseif (msg == 'help') then
		DEFAULT_CHAT_FRAME:AddMessage(string.format('|cFFFFFF00KnowItAll|r (show/hide): Show/hide the KnowItAll window'))
		DEFAULT_CHAT_FRAME:AddMessage(string.format('|cFFFFFF00KnowItAll|r (sync): Enable/Disable synchronization'))
		DEFAULT_CHAT_FRAME:AddMessage(string.format('|cFFFFFF00KnowItAll|r (version): Display the KnowItAll version.'))
		DEFAULT_CHAT_FRAME:AddMessage(string.format('|cFFFFFF00KnowItAll|r (resetkb): Reset the KnowItAll knowledge base.  |cFFFF0000WARNING IRREVERSIBLE YOU LOSE ALL SAVED DATA|r.'))
		--DEFAULT_CHAT_FRAME:AddMessage(string.format('|cFFFFFF00KnowItAll|r (resetsync): Reset the KnowItAll synchronized knowledge base.  |cFFFF0000WARNING IRREVERSIBLE YOU LOSE ALL SAVED DATA|r.'))
	else
		DEFAULT_CHAT_FRAME:AddMessage(string.format('|cFFFFFF00KnowItAll|r Invalid command (|cFFFF0000%s|r).  Please type /KnowItAll help',msg))
	end
end

function KnowItAll.OnLoad()
	-- set minimum resize
	this:SetMinResize(236,96)
	KnowItAllFrameEditFrame:SetMinResize(236,96)
	SLASH_KnowItAll1 = '/KnowItAll'
	SLASH_KnowItAll2 = '/gb'
	SlashCmdList['KnowItAll'] = KnowItAll.CommandHandler
	KnowItAllFrame:RegisterForDrag('LeftButton')
	KnowItAllFrameEditFrame:RegisterForDrag('LeftButton')
	table.insert(UISpecialFrames,'KnowItAllFrame')
	table.insert(UISpecialFrames,'KnowItAllFrameEditFrame')
	KnowItAllHTMLContent.SetText2 = KnowItAllHTMLContent.SetText
	KnowItAllHTMLContent.SetText = function(self,text)
		KnowItAllHTMLContent.text = text
		KnowItAllHTMLContent:SetText2(text)
	end
	KnowItAllHTMLContent.GetText = function(self,text)
		return KnowItAllHTMLContent.text
	end
	KnowItAll.canEdit = true
	-- set the path into the right place
	KnowItAllFramePath:ClearAllPoints()
	KnowItAllFramePath:SetPoint('LEFT','KnowItAllForwardButton','RIGHT',2,0)
	KnowItAllFramePath:SetWidth(KnowItAllFrame:GetWidth()-170)
	KnowItAllFrameNameBoxFrame:SetPoint('TOPLEFT','KnowItAllUndo','TOPRIGHT',2,0)
	KnowItAllFrameTaglineBoxFrame:SetPoint('TOPLEFT','KnowItAllFrameNameBoxFrame','TOPRIGHT',2,0)
	KnowItAllFrame:RegisterEvent('VARIABLES_LOADED')
	KnowItAllFrame:RegisterEvent('ADDON_LOADED')
	KnowItAllFrame:RegisterEvent('GUILD_ROSTER_UPDATE')
	KnowItAllFrame:RegisterEvent('PLAYER_ENTERING_WORLD')
	if (IsInGuild()) then GuildRoster() end
end

function KnowItAll.SetDisplayOptions()
	if (not KnowItAllOptions) then KnowItAllOptions = {} end
	if (not KnowItAllOptions.display) then KnowItAllOptions.display = {} end
	if (not KnowItAllOptions.display.links) then KnowItAllOptions.display.links = '00FFFF' end
	local tbl = {'h1','h2','h3'}
	for _,label in ipairs(tbl) do
		if (not KnowItAllOptions.display[label]) then KnowItAllOptions.display[label] = {} end
	end
	if (not KnowItAllOptions.display.h1.size) then KnowItAllOptions.display.h1.size = 10 end
	if (not KnowItAllOptions.display.h2.size) then KnowItAllOptions.display.h2.size = 5 end
	if (not KnowItAllOptions.display.h3.size) then KnowItAllOptions.display.h3.size = -2 end
	local font,height,flags = KnowItAllHTMLContent:GetFont()
	for _,label in ipairs(tbl) do
		if (KnowItAllOptions.display[label]['font']) then
			font = KnowItAllOptions.display[label]['font']
		end
		KnowItAllHTMLContent:SetFont(string.upper(label),font,height+KnowItAllOptions.display[label]['size'],flags)
	end
	KnowItAllHTMLContent:SetHyperlinkFormat('\124H%s\124h\124cFF'..KnowItAllOptions.display.links..'%s\124r\124h')
end

function KnowItAll.ParseMiscOptions()
	if (not KnowItAllOptions) then KnowItAllOptions = {} end
	if (not KnowItAllOptions.sync) then KnowItAllOptions.sync = {} end
	--if (KnowItAllOptions.sync.enabled) then KnowItAllSynch:Enable() end
end

-- event handlers
function KnowItAll.OnEvent(event,...)
	if (KnowItAll[event] and type(KnowItAll[event]) == 'function') then
		local func = KnowItAll[event]
		func(...)
	end
end

function KnowItAll.ADDON_LOADED(addon)
	if (addon == "KnowItAll") then
		L = KnowItAll.localisation
	end
end

function KnowItAll.GUILD_ROSTER_UPDATE()
	local name,rankIndex
	for i=1,GetNumGuildMembers(true) do
		name,_,rankIndex = GetGuildRosterInfo(i)
		if (name) then
			_rank[name] = rankIndex
		end
	end
end

function KnowItAll.VARIABLES_LOADED()
	-- populate the default information
	--if (not KnowItAllKB) then KnowItAll.ResetKB() end
	if (not KnowItAllOptions) then KnowItAllOptions = { } end
	if (not KnowItAllPerms) then KnowItAllPerms = {} end
	KnowItAll.BuildKB()
	KnowItAll.SetDisplayOptions()
	KnowItAll.ParseMiscOptions()
	-- hack to get around parent references not being restored
	KnowItAll.RestoreParents(KnowItAllKB)
	DEFAULT_CHAT_FRAME:AddMessage(string.format('|cFFFFFF00KnowItAll|r v%s loaded.  Type |cFF0000FF/KnowItAll|r or |cFF0000FF/gb|r to open the window',_version))
	KnowItAll.playerName = UnitName('player')
	--KnowItAll.RestoreCurrentPath(KnowItAllKB.currentPath)
	if (KnowItAll and KnowItAll.localisation and KnowItAll.localisation.help) then
		KnowItAll.RegisterAddon('KnowItAll',KnowItAll.localisation.help)
	end
	treeSync:RegisterTable("GB", KnowItAllKB.branches.sync)
end

function KnowItAll.BuildKB(reset)
	local now = time()
	if (not KnowItAllKB) then
		KnowItAll.ResetKB()
	end
	if (not KnowItAllKBLocal or reset) then
		if (KnowItAllKB['branches']['local'] and not reset) then
			KnowItAllKBLocal = KnowItAllKB['branches']['local']
		else
			KnowItAllKBLocal = {
				nodeModTime = now,
				treeModTime = now,
				name = 'local',
				data = {
					['name'] = 'local',
					['author'] = 'JoshBorke',
					['tagline'] = 'For storing your private information',
					['deleters'] = nil,
					['editors'] = nil,
					['content'] = '<H1 align="center">Change me!</H1>',
				},
				branches = {},
			}
		end
	end
	if (not KnowItAllKBSync or reset) then
		if (KnowItAllKB['branches']['sync'] and not reset) then
			KnowItAllKBSync = KnowItAllKB['branches']['sync']
		else
			KnowItAllKBSync = {
				nodeModTime = now,
				treeModTime = now,
				name = 'sync',
				data = {
					['name'] = 'sync',
					['author'] = 'JoshBorke',
					['tagline'] = 'For synchronized information.  Not yet implemented',
					['deleters'] = nil,
					['synch'] = true,
					['timeUpdate'] = now,
					['timestamp'] = now,
					['content'] = '<H1 align="center">Guild Book</H1><H2>Overview:</H2><p>This is the synchronized table.</p>',
				},
				branches = {},
			}
		end
	end
	KnowItAllKB['branches']['local'] = KnowItAllKBLocal
	KnowItAllKB['branches']['sync'] = KnowItAllKBSync
	KnowItAll.ResetRoot()
	KnowItAll.RestoreParents(KnowItAllKB)
end

function KnowItAll.ResetKB()
	local now = time()
	KnowItAllKB = {
		nodeModTime = now,
		treeModTime = now,
		data = {
			['name'] = 'KnowItAllKB',
			['author'] = 'JoshBorke',
			['deleters'] = '',
			['editors'] = nil,
			['content'] = L['intro'],
		},
		['branches'] = {
			['local'] = {
				nodeModTime = now,
				treeModTime = now,
				data = {
					['name'] = 'local',
					['author'] = 'JoshBorke',
					['tagline'] = 'For storing your private information',
					['deleters'] = nil,
					['editors'] = nil,
					['content'] = '<H1 align="center">Change me!</H1>',
				},
			},
			['sync'] = {
				nodeModTime = now,
				treeModTime = now,
				data = {
					['name'] = 'sync',
					['author'] = 'JoshBorke',
					['tagline'] = 'For synchronized information.  Not yet implemented',
					['deleters'] = nil,
					['synch'] = true,
					['timeUpdate'] = now,
					['timestamp'] = now,
					['content'] = '<H1 align="center">Guild Book</H1><H2>Overview:</H2><p>This is the synchronized table.</p>',
				},
			},
			['addons'] = {
				nodeModTime = now,
				treeModTime = now,
				data = {
					['name'] = 'addons',
					['author'] = 'JoshBorke',
					['deleters'] = '',
					['editors'] = '',
					['tagline'] = L['addon-tagline'],
					['content'] = L['addon-content'],
				},
			},
		}
	}
	KnowItAll.BuildKB(true)
	KnowItAll.ResetAddonHelp()
	KnowItAll.ResetRoot()
	KnowItAll.RestoreParents(KnowItAllKB)
end

function KnowItAll.ResetSync()
	local now = time()
	KnowItAllKB.branches.sync = {
		nodeModTime = now,
		treeModTime = now,
		data = {
			['name'] = 'sync',
			['author'] = 'JoshBorke',
			['tagline'] = 'For synchronized information.  Not yet implemented',
			['deleters'] = nil,
			['synch'] = true,
			['timeUpdate'] = now,
			['timestamp'] = now,
			['content'] = '<H1 align="center">Guild Book</H1><H2>Overview:</H2><p>This is the synchronized table.</p>',
		},
	}
	KnowItAllOptions.sync.enabled = true
	treeSync:RegisterTable("GB", KnowItAllKB.branches.sync)
end

--[[ For permission management ]]--
function KnowItAll.NameCanEdit(name,node)
	if (not name) then return false end
	if (not node['editors'] or string.find(node['editors'],':'..name..':') or (_rank and _rank[name] and string.find(node['editors'],':'.._rank[name]..':'))) then
		return true
	end
end

function KnowItAll.NameCanDelete(name,node)
	if (not name) then return false end
	if (not node['deleters'] or string.find(node['deleters'],':'..name..':') or (_rank and _rank[name] and string.find(node['deleters'],':'.._rank[name]..':'))) then
		return true
	end
end

--[[ for addons to register stuff ]]--
local _addonHelps = {}
function KnowItAll.RegisterAddon(addon,information)
	_addonHelps[addon] = information
	local _root = KnowItAllKB['branches']['addons']
	if (_root['branches'] and _root['branches'][addon]) then
		_root['branches'][addon] = nil
	end
	_root = KnowItAll.AddData(addon,information.shortDescription,information.description,_root,information.author, nil, nil, nil, nil, nil, true)
	if (_root and information.topics) then
		for cmd,info in pairs(information.topics) do
			KnowItAll.AddData(cmd,info.tagline,info.content,_root,information.author, nil, nil, nil, nil, nil, true)
		end
	end
end

function KnowItAll.ResetAddonHelp()
	local now = time()
	KnowItAllKB['branches']['addons'] = {
		nodeModTime = now,
		treeModTime = now,
		data = {
			['name'] = 'addons',
			['author'] = 'JoshBorke',
			['deleters'] = '',
			['editors'] = '',
			['tagline'] = 'For addon help',
			['content'] = '<H1 align="center">Guild Book</H1><H2>Addons:</H2><p>This is the root for addons to register to.</p>',
		}
	}
	local _root = KnowItAllKB['branches']['addons']
	for addon,information in pairs(_addonHelps) do
		_root = KnowItAll.AddData(addon,information.shortDescription,information.description,_root,information.author, nil, nil, nil, nil, nil, true)
		if (_root and information.topics) then
			for cmd,info in pairs(information.topics) do
				KnowItAll.AddData(cmd,info.tagline,info.content,_root,information.author)
			end
		end
	end
end
