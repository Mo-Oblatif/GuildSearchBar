-- Guild Search Bar
-- Adds a search bar at the top left of the guild roster (Guild & Communities
-- window, roster view). While a search is active, the matching members are shown
-- in place of the roster, with Blizzard's own row template, and right-click opens
-- Blizzard's own guild member menu.
--
-- How it stays out of Blizzard's way (taint):
--   * Blizzard's roster is never re-anchored, resized, re-sorted or given data.
--     The only change is the alpha of its scroll box and scroll bar while a
--     search is active, so our list can sit exactly where it is.
--   * Our list is our own ScrollBox built the same way as Blizzard's
--     (CommunitiesMemberListMixin:OnLoad): rows from CommunitiesMemberListEntryTemplate,
--     parented row -> ScrollTarget -> ScrollBox -> "proxy", because the row mixin
--     reaches its list with GetParent():GetParent():GetParent(). The proxy answers
--     the few questions the rows ask (selected club, voice channel).
--   * Member data is copied without any secret value before a row sees it.
--   * Right-click calls Blizzard's own CommunitiesMemberListMixin:OnClubMemberButtonClicked,
--     which builds the context menu and opens it with UnitPopup_OpenMenu
--     ("COMMUNITIES_GUILD_MEMBER"), exactly as a click on a roster row does.
--     The menu is opened from addon code, so any entry the game reserves for its
--     own interface can be refused by the game (same trade as LFG Forever).

local ADDON, ns = ...
local L = ns.L

local BOX_W, BOX_H = 170, 20
local ROW_TEMPLATE = "CommunitiesMemberListEntryTemplate"
local PROFESSION_COLUMN = 2           -- EXTRA_GUILD_COLUMN_PROFESSION in Blizzard_Communities

local db
local holder, box, proxy, scrollBox, scrollBar, emptyText
local members = {}                    -- sanitized ClubMemberInfo copies + search keys
local membersDirty = true
local searchActive = false
local wasShown = false

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local issecret = _G.issecretvalue
local function IsSecret(v)
	return v ~= nil and issecret and issecret(v) or false
end

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7Guild Search Bar|r: " .. msg)
end

-- Fold accents and case so "eleonore" finds "Éléonore".
local ACCENTS = {}
do
	local groups = {
		a = "àáâãäåÀÁÂÃÄÅ", c = "çÇ", e = "èéêëÈÉÊË", i = "ìíîïÌÍÎÏ",
		n = "ñÑ", o = "òóôõöøÒÓÔÕÖØ", u = "ùúûüÙÚÛÜ", y = "ýÿÝ", ae = "æÆ", oe = "œŒ",
	}
	for plain, chars in pairs(groups) do
		for ch in chars:gmatch("[\194-\244][\128-\191]*") do ACCENTS[ch] = plain end
	end
end
local function fold(s)
	if type(s) ~= "string" or s == "" then return "" end
	s = s:gsub("[\194-\244][\128-\191]*", ACCENTS)
	return s:lower()
end

local function GetMemberList()
	return CommunitiesFrame and CommunitiesFrame.MemberList
end

local function GetGuildClubId()
	local f = CommunitiesFrame
	local clubId = f and f.GetSelectedClubId and f:GetSelectedClubId()
	if not clubId and C_Club and C_Club.GetGuildClubId then clubId = C_Club.GetGuildClubId() end
	return clubId
end

---------------------------------------------------------------------------
-- Member data
---------------------------------------------------------------------------

local function Sanitize(info)
	local copy = {}
	for k, v in pairs(info) do
		if not IsSecret(v) then copy[k] = v end
	end
	return copy
end

local function RebuildMembers()
	wipe(members)
	membersDirty = false
	local clubId = GetGuildClubId()
	if not (clubId and C_Club and C_Club.GetClubMembers) then return end
	local ids = C_Club.GetClubMembers(clubId) or {}
	for _, memberId in ipairs(ids) do
		local ok, info = pcall(C_Club.GetMemberInfo, clubId, memberId)
		if ok and info then
			local m = Sanitize(info)
			if type(m.name) == "string" and m.name ~= "" then
				local short = m.name:match("^[^-]+") or m.name
				m.gsbKey = fold(short)
				m.gsbNoteKey = fold((m.memberNote or "") .. " " .. (m.officerNote or ""))
				m.gsbOnline = m.presence ~= Enum.ClubMemberPresence.Offline
				members[#members + 1] = m
			end
		end
	end
end

local function FindMatches(text)
	local q = fold(strtrim(text or ""))
	local found = {}
	if q == "" then return found end
	if membersDirty then RebuildMembers() end
	for _, m in ipairs(members) do
		local pos = m.gsbKey:find(q, 1, true)
		local score
		if pos then
			score = (pos == 1) and 0 or 1
		elseif db.searchNotes and m.gsbNoteKey:find(q, 1, true) then
			score = 2
		end
		if score then
			m.gsbScore = score
			found[#found + 1] = m
		end
	end
	table.sort(found, function(a, b)
		if a.gsbScore ~= b.gsbScore then return a.gsbScore < b.gsbScore end
		if a.gsbOnline ~= b.gsbOnline then return a.gsbOnline end
		return a.gsbKey < b.gsbKey
	end)
	return found
end

---------------------------------------------------------------------------
-- Result rows (Blizzard's roster row template)
---------------------------------------------------------------------------

local function Row_OnEnter(self)
	local m = self.GetMemberInfo and self:GetMemberInfo()
	if not m then return end
	GameTooltip:SetOwner(self)
	GameTooltip:AddLine(m.name)
	if m.guildRank then GameTooltip:AddLine(m.guildRank) end
	if m.level and m.classID then
		local classInfo = C_CreatureInfo.GetClassInfo(m.classID)
		if classInfo then
			GameTooltip:AddLine(("%s %d %s"):format(LEVEL or "", m.level, classInfo.className), 1, 1, 1, true)
		end
	end
	if m.presence == Enum.ClubMemberPresence.OnlineMobile then
		GameTooltip:AddLine(COMMUNITIES_PRESENCE_MOBILE_CHAT or L.MOBILE, 1, 1, 1, true)
	elseif m.presence == Enum.ClubMemberPresence.Offline then
		if m.lastOnlineYear and TimeUtil and TimeUtil.GetRecentTimeDate then
			GameTooltip:AddLine(TimeUtil.GetRecentTimeDate(m.lastOnlineYear, m.lastOnlineMonth, m.lastOnlineDay, m.lastOnlineHour), 0.6, 0.6, 0.6, true)
		end
	elseif m.zone then
		GameTooltip:AddLine(m.zone, 1, 1, 1, true)
	end
	if m.memberNote and m.memberNote ~= "" then
		GameTooltip:AddLine((COMMUNITY_MEMBER_NOTE_FORMAT or L.NOTE):format(m.memberNote), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
	end
	if m.officerNote and m.officerNote ~= "" then
		GameTooltip:AddLine(L.OFFICER_NOTE:format(m.officerNote), 1, 0.5, 0.25, true)
	end
	GameTooltip:Show()
end

local function Row_OnClick(self, button)
	if button ~= "RightButton" then return end
	local ml = GetMemberList()
	if ml and ml.OnClubMemberButtonClicked then
		-- Blizzard's own handler: same context data, same menu as a roster row.
		ml:OnClubMemberButtonClicked(self, "RightButton")
	end
end

local function InitRow(button, elementData)
	if not button.gsbHooked then
		button.gsbHooked = true
		-- Our list refreshes itself; the row's own roster-update handler would
		-- re-read raw member data (possibly secret) into the row.
		button:SetScript("OnEvent", nil)
		button:SetScript("OnEnter", Row_OnEnter)
		button:SetScript("OnClick", Row_OnClick)
	end
	button:Init(elementData, true)
	local ml = GetMemberList()
	local col = ml and ml.GetGuildColumnIndex and ml:GetGuildColumnIndex()
	if col == PROFESSION_COLUMN then col = nil end
	if button.SetGuildColumnIndex then button:SetGuildColumnIndex(col) end
end

---------------------------------------------------------------------------
-- Our list, laid over the roster
---------------------------------------------------------------------------

local function SetBlizzardListAlpha(a)
	local ml = GetMemberList()
	if not ml then return end
	if ml.ScrollBox then ml.ScrollBox:SetAlpha(a) end
	if ml.ScrollBar then ml.ScrollBar:SetAlpha(a) end
end

local function SetSearchActive(active)
	if active == searchActive then return end
	searchActive = active
	proxy:SetShown(active)
	SetBlizzardListAlpha(active and 0 or 1)
end

local function RefreshResults()
	if not proxy then return end
	local text = box:GetText() or ""
	if strtrim(text) == "" or not box:IsVisible() then
		SetSearchActive(false)
		return
	end
	local found = FindMatches(text)
	local provider = CreateDataProvider()
	for _, m in ipairs(found) do provider:Insert({ memberInfo = m }) end
	scrollBox:SetDataProvider(provider)
	emptyText:SetShown(#found == 0)
	SetSearchActive(true)
end

local function CreateProxy()
	local ml = GetMemberList()

	proxy = CreateFrame("Frame", nil, holder)
	proxy:SetPoint("TOPLEFT", ml, "TOPLEFT")
	proxy:SetPoint("BOTTOMRIGHT", ml, "BOTTOMRIGHT")
	proxy:SetFrameLevel(ml:GetFrameLevel() + 50)   -- above Blizzard's rows, below its inset border (100)
	proxy:EnableMouse(true)                         -- nothing reaches the hidden roster rows
	proxy:Hide()

	-- What the row mixin asks its list (see CommunitiesMemberListEntryMixin).
	function proxy:GetSelectedClubInfo() return CommunitiesFrame:GetSelectedClubInfo() end
	function proxy:GetSelectedClubId() return CommunitiesFrame:GetSelectedClubId() end
	function proxy:GetCommunitiesFrame() return CommunitiesFrame end
	function proxy:GetVoiceChannelID() return nil end
	function proxy:GetVoiceChannel() return nil end
	function proxy:SetProfessionCollapsed() end
	function proxy:CancelInvitation() end
	function proxy:OnClubMemberButtonClicked(entry, button) Row_OnClick(entry, button) end

	scrollBox = CreateFrame("Frame", nil, proxy, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT")
	scrollBox:SetPoint("BOTTOMRIGHT")

	scrollBar = CreateFrame("EventFrame", nil, proxy, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", proxy, "TOPRIGHT", 4, -3)
	scrollBar:SetPoint("BOTTOMLEFT", proxy, "BOTTOMRIGHT", 4, 2)

	local view = CreateScrollBoxListLinearView()
	view:SetElementInitializer(ROW_TEMPLATE, InitRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

	emptyText = proxy:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	emptyText:SetPoint("TOP", 0, -24)
	emptyText:SetText(L.NO_RESULT)
	emptyText:Hide()
end

---------------------------------------------------------------------------
-- Search bar placement and visibility
---------------------------------------------------------------------------

-- Top left of the roster, right after the "Show offline members" check box.
local function PlaceBox()
	local ml = GetMemberList()
	if not ml then return end
	box:ClearAllPoints()
	local cb = ml.ShowOfflineButton
	local label = cb and cb.Text
	box.gsbNextToCheckbox = cb and cb:IsShown() or false
	if box.gsbNextToCheckbox then
		local after = (label and label:GetText() and label:GetText() ~= "") and label or cb
		box:SetPoint("LEFT", after, "RIGHT", 16 + (db.dx or 0), (db.dy or 0))
	else
		box:SetPoint("BOTTOMLEFT", ml, "TOPLEFT", 6 + (db.dx or 0), 32 + (db.dy or 0))
	end
end

local function IsGuildRosterView()
	local f = CommunitiesFrame
	if not (f and f:IsShown() and f.MemberList and f.MemberList:IsShown()) then return false end
	if not IsInGuild() then return false end
	local modes = COMMUNITIES_FRAME_DISPLAY_MODES
	if modes and modes.ROSTER and f.GetDisplayMode and f:GetDisplayMode() ~= modes.ROSTER then
		return false
	end
	local info = f.GetSelectedClubInfo and f:GetSelectedClubInfo()
	if info and Enum.ClubType and info.clubType ~= Enum.ClubType.Guild then return false end
	return true
end

local function UpdateVisibility()
	local show = IsGuildRosterView()
	if show == wasShown then
		-- The check box can appear a moment after the roster view opens.
		local cb = show and GetMemberList().ShowOfflineButton
		if cb and (cb:IsShown() or false) ~= box.gsbNextToCheckbox and not box.gsbMoving then PlaceBox() end
		return
	end
	wasShown = show
	box:SetShown(show)
	if show then
		PlaceBox()
		membersDirty = true
		if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
		RefreshResults()
	else
		box:ClearFocus()
		SetSearchActive(false)
	end
end

local function CreateSearchBar()
	if holder then return end
	local f = CommunitiesFrame
	if not (f and f.MemberList) then return end

	holder = CreateFrame("Frame", nil, f)
	holder:SetSize(1, 1)
	holder:SetPoint("TOPLEFT")
	local elapsed = 0
	holder:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.2 then return end
		elapsed = 0
		UpdateVisibility()
	end)
	holder:SetScript("OnHide", function()
		wasShown = false
		if box then box:ClearFocus(); box:Hide() end
		if proxy then SetSearchActive(false) end
	end)

	local ok, eb = pcall(CreateFrame, "EditBox", "GuildSearchBarBox", holder, "SearchBoxTemplate")
	if not ok then
		eb = CreateFrame("EditBox", "GuildSearchBarBox", holder, "InputBoxTemplate")
	end
	box = eb
	box:SetSize(BOX_W, BOX_H)
	box:SetAutoFocus(false)
	box:SetMaxLetters(40)
	box:SetFrameLevel(f.MemberList:GetFrameLevel() + 60)
	if box.Instructions then box.Instructions:SetText(L.PLACEHOLDER) end

	box:HookScript("OnTextChanged", RefreshResults)
	box:HookScript("OnEnterPressed", function(self) self:ClearFocus() end)

	-- Alt + drag to move the bar if it overlaps something in your layout.
	box:SetMovable(true)
	box:RegisterForDrag("LeftButton")
	box:SetScript("OnDragStart", function(self)
		if IsAltKeyDown() then
			self.gsbStart = { self:GetLeft(), self:GetBottom() }
			self.gsbMoving = true
			self:StartMoving()
		end
	end)
	box:SetScript("OnDragStop", function(self)
		if not self.gsbMoving then return end
		self.gsbMoving = false
		self:StopMovingOrSizing()
		if self.SetUserPlaced then self:SetUserPlaced(false) end
		local start = self.gsbStart
		if start and start[1] and self:GetLeft() then
			db.dx = (db.dx or 0) + math.floor(self:GetLeft() - start[1] + 0.5)
			db.dy = (db.dy or 0) + math.floor(self:GetBottom() - start[2] + 0.5)
		end
		PlaceBox()
	end)
	box:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:AddLine(L.PLACEHOLDER)
		GameTooltip:AddLine(L.HINT_MENU, 0.8, 0.8, 0.8)
		GameTooltip:AddLine(L.HINT_MOVE, 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	box:HookScript("OnLeave", GameTooltip_Hide)
	box:Hide()

	CreateProxy()
end

---------------------------------------------------------------------------
-- Events and slash command
---------------------------------------------------------------------------

local ROSTER_EVENTS = {
	"GUILD_ROSTER_UPDATE", "CLUB_MEMBER_ADDED", "CLUB_MEMBER_REMOVED",
	"CLUB_MEMBER_UPDATED", "CLUB_MEMBERS_UPDATED", "CLUB_MEMBER_PRESENCE_UPDATED",
}

local refreshPending = false
local function QueueRefresh()
	membersDirty = true
	if refreshPending or not searchActive then return end
	refreshPending = true
	C_Timer.After(0.3, function()
		refreshPending = false
		if searchActive then RefreshResults() end
	end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
for _, e in ipairs(ROSTER_EVENTS) do pcall(events.RegisterEvent, events, e) end
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON then
			GuildSearchBarDB = GuildSearchBarDB or {}
			db = GuildSearchBarDB
			if db.searchNotes == nil then db.searchNotes = true end
			local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
			if isLoaded("Blizzard_Communities") then CreateSearchBar() end
		elseif arg1 == "Blizzard_Communities" and db then
			CreateSearchBar()
		end
	else
		QueueRefresh()
	end
end)

SLASH_GUILDSEARCHBAR1 = "/gsb"
SLASH_GUILDSEARCHBAR2 = "/guildsearchbar"
SlashCmdList.GUILDSEARCHBAR = function(msg)
	msg = strtrim((msg or ""):lower())
	if msg == "notes" then
		db.searchNotes = not db.searchNotes
		Print(L.NOTES_TOGGLED:format(db.searchNotes and L.ON or L.OFF))
		if box and box:IsShown() then RefreshResults() end
	elseif msg == "reset" then
		db.dx, db.dy = 0, 0
		if box then PlaceBox() end
		Print(L.RESET_DONE)
	else
		Print(L.HELP_TITLE)
		Print(L.HELP_NOTES:format(db.searchNotes and L.ON or L.OFF))
		Print(L.HELP_RESET)
	end
end
