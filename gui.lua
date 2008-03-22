
if (not KnowItAll) then KnowItAll = {} end

local _hooked = false
local _currentPath = nil
local _currentNode = nil
local _resetForward = false
local _backPath = {}
local _forwardPath = {}
local _tmpPath = {}
local _defaultNode = {
	['name'] = 'Set Name',
	['tagline'] = 'Set tagline',
	['content'] = '<H1>Set Content</H1>',
}
local _roots = {}
StaticPopupDialogs["GUILDBOOKCONFIRM"] = {
	text = "Delete this page?",
	button1 = "Yes",
	button2 = "No",
	timeout = 0,
	whileDead = 1,
	OnAccept = function()
		KnowItAll.RemData(_currentNode)
		-- change to the previous location
		_currentPath = table.remove(_backPath)
		_currentNode = KnowItAll.TraverseTreePath(_currentPath)
		KnowItAll.UpdateHTMLFrame()
	end
}

local L = setmetatable({}, {__index = function(t, k) rawset(t,k,k) return k end})

do
	local _f
	local _showTooltip
	local _elapsed = 0
	local _timeToShow = 2
	local _timeOut = 0.5
	local _state = 1
	local function _showTooltips(frame,elapsed)
		_elapsed = _elapsed + elapsed
		if (_showTooltip) then
			if (_elapsed > _timeToShow and _state == 1) then
				GameTooltip_SetDefaultAnchor(GameTooltip,UIParent)
				GameTooltip:AddLine(KnowItAll.Buttons[_showTooltip][1])
				GameTooltip:AddLine(KnowItAll.Buttons[_showTooltip][2],.85,.85,.85,1)
				GameTooltip:Show()
				_state = 2
				_elapsed = 0
			end
			if (_elapsed < _timeOut and _state == 2) then
				GameTooltip_SetDefaultAnchor(GameTooltip,UIParent)
				GameTooltip:AddLine(KnowItAll.Buttons[_showTooltip][1])
				GameTooltip:AddLine(KnowItAll.Buttons[_showTooltip][2],.85,.85,.85,1)
				GameTooltip:Show()
				_state = 2
				_elapsed = 0
			end
		else
			if (_elapsed > _timeOut) then
				_state = 1
				_f:Hide()
			end
		end
	end
	_f = CreateFrame('Frame')
	_f:SetScript("OnUpdate",_showTooltips)

	function KnowItAll.HideTooltip()
		_elapsed = 0
		_showTooltip = nil
		_state = 2
		GameTooltip:Hide()
	end

	function KnowItAll.Tooltip()
		local which = this:GetName()
		if (KnowItAll.Buttons and KnowItAll.Buttons[which]) then
			_showTooltip = which
			if (_state ~= 2) then _state = 1 end
			_elapsed = 0
			_f:Show()
		end
	end
end

-- Titlebar button clicks
function KnowItAll.OnClick()

	local which = this:GetName()

	if which=="KnowItAllNew" then
		KnowItAll.EditNode()
	elseif which=="KnowItAllDelete" then
		if not IsShiftKeyDown() then
			StaticPopup_Show("GUILDBOOKCONFIRM")
		else
			KnowItAll.RemData(_currentNode) -- delete empty pages without confirmation
			-- change to the previous location
			_currentPath = table.remove(_backPath)
			_currentNode = KnowItAll.TraverseTreePath(_currentPath)
		end
		KnowItAll.UpdateHTMLFrame()
	elseif which == "KnowItAllEdit" then
		KnowItAll.EditNode(_currentNode)
	elseif which == 'KnowItAllEditClose' then
		KnowItAllFrameEditFrame:Hide()
	elseif which == 'KnowItAllUndo' then
		KnowItAll.EditNode(_currentNode)
	elseif which == 'KnowItAllSave' then
		local text
		text = KnowItAll.toHTML(KnowItAllEditBox:GetText())
		if (not KnowItAllEditBox.name) then -- we added a new node
			KnowItAll.AddData(KnowItAllFrameNameBox:GetText(),KnowItAllFrameTaglineBox:GetText(),text,_currentNode)
			table.insert(_backPath,_currentPath)
			_currentPath = _currentPath..'>'..KnowItAllFrameNameBox:GetText()
		elseif (KnowItAll.ValidateContent(text)) then
			if (KnowItAllEditBox.name ~= KnowItAllFrameNameBox:GetText()) then
				KnowItAll.ModifyData(_currentNode,KnowItAllFrameNameBox:GetText(),KnowItAllFrameTaglineBox:GetText(),text,UnitName('player'),time())
				_currentPath = string.gsub(_currentPath,'(.+>)'..KnowItAllEditBox.name,'%1'..KnowItAllFrameNameBox:GetText())
				_currentNode = KnowItAll.TraverseTreePath(_currentPath)
			else
				KnowItAll.ModifyData(_currentNode,nil,KnowItAllFrameTaglineBox:GetText(),text,UnitName('player'),time())
			end
		end
		if (_resetForward) then
			for k,vi in pairs(_forwardPath) do
				_forwardPath[k] = nil
			end
			--table.setn(_forwardPath,0)
			_resetForward = false
		end
		KnowItAllFrameEditFrame:Hide()
		KnowItAll.UpdateHTMLFrame()
	elseif which=="KnowItAllClose" then
		KnowItAllFrame:Hide()
	elseif which=="KnowItAllFramePin" then
		KnowItAllFrame.lock = not KnowItAllFrame.lock
		KnowItAll.UpdateLock()
	elseif which=="KnowItAllFont" then
		KnowItAllOptions['frame'].Font = KnowItAllSettings.Font+1
		KnowItAll.UpdateFont()
	elseif which=='KnowItAllBackButton' then
		_tmpPath = table.remove(_backPath)
		if (KnowItAll.TraverseTreePath(_tmpPath)) then
			table.insert(_forwardPath,_currentPath)
			_currentPath = _tmpPath
			KnowItAll.UpdateHTMLFrame()
		end
	elseif which == "KnowItAllUpButton" then
		table.insert(_backPath,_currentPath)
		_,_,_currentPath = string.find(_currentPath,'^(.+)>.-$')
		KnowItAll.UpdateHTMLFrame()
	elseif which=='KnowItAllForwardButton' then
		_tmpPath = table.remove(_forwardPath)
		if (KnowItAll.TraverseTreePath(_tmpPath)) then
			table.insert(_backPath,_currentPath)
			_currentPath = _tmpPath
			KnowItAll.UpdateHTMLFrame()
		end
	end
end

function KnowItAll.EditNode(node)
	local content = node and node.data.content
	local name = node and node.data.name
	local tagline = node and node.data.tagline
	KnowItAllEditBox.content = content
	KnowItAllEditBox.name = name
	KnowItAllEditBox.tagline = tagline
	if (not node) then
		node = _defaultNode
		_resetForward = true
	end
	KnowItAllEditBox:SetText(KnowItAll.fromHTML(content) or '<H1>Set Content</H1>')
	KnowItAllFrameNameBox:SetText(name or L['Set Name'])
	KnowItAllFrameTaglineBox:SetText(tagline or L['Set Tagline'])
	KnowItAllUndo:Disable()
	SetDesaturation(KnowItAllUndo:GetNormalTexture(),true)
	KnowItAllUndo:SetAlpha(0.5)
	KnowItAllFrameEditFrame:Show()
	KnowItAll.HookItemClicks()
	KnowItAllEditBox:SetWidth(KnowItAllFrameEditFrame:GetWidth()-50)
	KnowItAllFrameTaglineBoxFrame:SetWidth(KnowItAllFrameEditFrame:GetWidth()-185)
	KnowItAllFrameTaglineBox:SetWidth(KnowItAllFrameEditFrame:GetWidth()-195)
end

function KnowItAll.OnShow()
	if (KnowItAll.canEdit) then
		KnowItAllNew:Show()
		KnowItAllDelete:Show()
	else
		KnowItAllNew:Hide()
		KnowItAllDelete:Hide()
	end
	KnowItAllHTMLContent:SetWidth(KnowItAllFrame:GetWidth()-50)
	KnowItAll.UpdateHTMLFrame()
end

function KnowItAll.UpdateHTMLFrame()
	_currentNode = KnowItAll.TraverseTreePath(_currentPath)
	if (not _currentNode) then
		KnowItAll.Error('UpdateHTMLFrame','Couldn\'t find the current node, going back one')
		_tmpPath = table.remove(_backPath)
		if (not _tmpPath) then
			KnowItAll.ResetRoot()
			return
		end
		if (KnowItAll.TraverseTreePath(_tmpPath)) then
			_currentPath = _tmpPath
			KnowItAll.UpdateHTMLFrame()
		end
		return
	end
	if (not _currentPath) then _currentPath = KnowItAll.GetTreePath(_currentNode) end
	local text = KnowItAll.GetContent(_currentNode)
	KnowItAllKB.currentPath = _currentPath
	KnowItAllHTMLContent:SetText(text)
	KnowItAllFramePath:SetText(_currentPath)
	if (table.getn(_backPath) > 0) then
		if (not KnowItAllBackButton.isEnabled) then
			KnowItAllBackButton:Enable()
			SetDesaturation(KnowItAllBackButton:GetNormalTexture(),false)
			KnowItAllBackButton:SetAlpha(1)
			KnowItAllBackButton.isEnabled = true
		end
	else
		KnowItAllBackButton:Disable()
		SetDesaturation(KnowItAllBackButton:GetNormalTexture(),true)
		KnowItAllBackButton:SetAlpha(.5)
		KnowItAllBackButton.isEnabled = false
	end
	if (table.getn(_forwardPath) > 0) then
		if (not KnowItAllForwardButton.isEnabled) then
			KnowItAllForwardButton:Enable()
			SetDesaturation(KnowItAllForwardButton:GetNormalTexture(),false)
			KnowItAllForwardButton:SetAlpha(1)
			KnowItAllForwardButton.isEnabled = true
		end
	else
		KnowItAllForwardButton:Disable()
		SetDesaturation(KnowItAllForwardButton:GetNormalTexture(),true)
		KnowItAllForwardButton:SetAlpha(.5)
		KnowItAllForwardButton.isEnabled = false
	end
	if (_currentPath ~= "KnowItAllKB") then
		if (not KnowItAllUpButton.isEnabled) then
			KnowItAllUpButton:Enable()
			SetDesaturation(KnowItAllUpButton:GetNormalTexture(),false)
			KnowItAllUpButton:SetAlpha(1)
			KnowItAllUpButton.isEnabled = true
		end
	else
		if (KnowItAllUpButton.isEnabled) then
			KnowItAllUpButton:Disable()
			KnowItAllUpButton.isEnabled = false
			SetDesaturation(KnowItAllUpButton:GetNormalTexture(),true)
			KnowItAllUpButton:SetAlpha(.5)
		end
	end

	KnowItAllHTMLContent:GetParent():UpdateScrollChildRect()
	local scrollBar = getglobal(KnowItAllHTMLContent:GetParent():GetName().."ScrollBar")
	local min, max = scrollBar:GetMinMaxValues()
	if ( max > 0 and (this.max ~= max) ) then
		this.max = max
		scrollBar:SetValue(max)
	end
	if (not KnowItAll.NameCanDelete(KnowItAll.playerName,_currentNode)) then KnowItAllDelete:Hide() else KnowItAllDelete:Show() end
	if (not KnowItAll.NameCanEdit(KnowItAll.playerName,_currentNode)) then
		KnowItAllNew:Hide()
		KnowItAllEdit:Hide()
	else
		KnowItAllEdit:Show()
		KnowItAllNew:Show()
	end
end

function KnowItAll.HyperLinkClicked(linkID,button)
    if (string.match(linkID,"item:%-?%d+:%-?%d+:%-?%d+:%-?%d+:%-?%d+:%-?%d+:%-?%d+:%-?%d+")) then
		local name,link = GetItemInfo(linkID)
		if ( IsControlKeyDown() ) then
			DressUpItemLink(link);
		elseif ( IsShiftKeyDown() ) then
			if ( ChatFrameEditBox:IsVisible() ) then
				ChatFrameEditBox:Insert(link);
			end
		else
			ShowUIPanel(ItemRefTooltip);
			if ( not ItemRefTooltip:IsVisible() ) then
				ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE");
			end
			ItemRefTooltip:SetHyperlink(link);
		end
	else
		table.insert(_backPath,_currentPath)
		if (not string.find(linkID,'^KnowItAllKB>')) then
			_currentPath = _currentPath..'>'..linkID
		else
			_currentPath = linkID
		end
		-- reset the forward links on a hyperlink click
		for k,vi in pairs(_forwardPath) do
			_forwardPath[k] = nil
		end
		--table.setn(_forwardPath,0)
		KnowItAll.UpdateHTMLFrame()
	end
end

-- changes border and resize grip depending on lock status
function KnowItAll.UpdateLock()
	if KnowItAllFrame.lock then
		KnowItAllFramePin:SetNormalTexture("Interface/Addons/KnowItAll/buttons/pinned.tga")
		KnowItAllFrame:SetBackdropBorderColor(0,0,0,1)
		KnowItAllFrameResizeGrip:Hide()
	else
		KnowItAllFramePin:SetNormalTexture("Interface/Addons/KnowItAll/buttons/pin.tga")
		KnowItAllFrame:SetBackdropBorderColor(1,1,1,1)
		KnowItAllFrameResizeGrip:Show()
	end
end

function KnowItAll.OnTextChanged()
	if (this:GetName() == "GulidBookEditBox") then
		local scrollBar = getglobal(this:GetParent():GetName().."ScrollBar")
		this:GetParent():UpdateScrollChildRect()
		local min, max = scrollBar:GetMinMaxValues()
		if ( max > 0 and (this.max ~= max) ) then
			this.max = max
			scrollBar:SetValue(max)
		end
	end
	 if (KnowItAllEditBox:GetText() ~= KnowItAllEditBox.content or
		 KnowItAllFrameNameBox:GetText() ~= KnowItAllEditBox.name or
		 KnowItAllFrameTaglineBox:GetText() ~= KnowItAllEditBox.tagline) then
		SetDesaturation(KnowItAllUndo:GetNormalTexture(),false)
		KnowItAllUndo:Enable()
		KnowItAllUndo:SetAlpha(1)
	 else
		KnowItAllUndo:Disable()
		SetDesaturation(KnowItAllUndo:GetNormalTexture(),true)
		KnowItAllUndo:SetAlpha(0.5)
	 end
end

function KnowItAll.ResetRoot()
	_currentNode = KnowItAllKB
	_currentPath = KnowItAll.GetTreePath(_currentNode)
	_backPath = {}
	_forwardPath = {}
	KnowItAll.UpdateHTMLFrame()
end

function KnowItAll.RestoreCurrentPath(path)
	_currentPath = path
	KnowItAll.UpdateHTMLFrame()
end

local function myClickAction(link,text,button)
	if (KnowItAllEditBox:IsShown()) then
		if (IsShiftKeyDown()) then
			if (not link) then return end
			local name,link = GetItemInfo(link)
			KnowItAllEditBox:Insert(link)
		end
	end
end

local function myClickAction2(text)
	if (KnowItAllEditBox:IsShown() and not ChatFrameEditBox:IsVisible()) then
		if (not text) then return end
		local name,link = GetItemInfo(text)
		KnowItAllEditBox:Insert(link)
	end
end

function KnowItAll.HookItemClicks()
	if (not _hooked) then
		hooksecurefunc('SetItemRef',myClickAction)
		hooksecurefunc('ChatEdit_InsertLink',myClickAction2)
		_hooked = true
	end
end
