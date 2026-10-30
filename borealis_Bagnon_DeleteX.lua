-- Bagnon Delete X
--
-- 1. Окно игры «впишите слово УДАЛИТЬ» (для синих и лучше вещей) открывается уже со вписанным словом,
--    остаётся нажать «Да». Это работает везде, в том числе при обычном удалении перетаскиванием.
-- 2. Маленький крестик в углу ячейки Bagnon под мышью удаляет предмет. По умолчанию без вопросов;
--    в настройках можно включить подтверждение отдельно для зелёных, синих и фиолетовых вещей.
--    Крестик не показывается на чужих персонажах и на банке вне банка (это сохранённые копии).
-- 3. Когда свободных ячеек в сумках мало, внизу инвентаря Bagnon появляется кнопка «Мусор»:
--    клик удаляет самую дешёвую серую вещь (только продаваемую торговцу и не для заданий). В бою кнопка прячется.
-- Настройки: Интерфейс → Модификации → «Крестик удаления» или /delx.

local Bagnon = LibStub('AceAddon-3.0'):GetAddon('Bagnon')
local ItemSlot = Bagnon.ItemSlot
local PREFIX = "|cffff5555Крестик|r: "
local MIN_SIZE, MAX_SIZE = 8, 32
local MAX_JUNK_SLOTS = 20
local DEFAULTS = { askGreen = false, askBlue = false, askPurple = true, size = 14, junkButton = true, junkSlots = 3 }
local db

local function say(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

--[[ Слово в окне подтверждения ]]--

local function fillWord(dialog)
	local name = dialog:GetName()
	local editBox = dialog.editBox or _G[name .. "EditBox"]
	editBox:SetText(DELETE_ITEM_CONFIRM_STRING)
	local yes = dialog.button1 or _G[name .. "Button1"]
	yes:Enable()
end

local function visibleDialog(which)
	for i = 1, STATICPOPUP_NUMDIALOGS do
		local dialog = _G["StaticPopup" .. i]
		if dialog and dialog:IsShown() and dialog.which == which then return dialog end
	end
end

hooksecurefunc("StaticPopup_Show", function(which)
	if which == "DELETE_GOOD_ITEM" then
		local dialog = visibleDialog(which)
		if dialog then fillWord(dialog) end
	end
end)

--[[ Удаление крестиком ]]--

-- что ждёт подтверждения в нашем окне; пока оно открыто, вещь на курсоре наша, другого удаления быть не может
local pending

hooksecurefunc("DeleteCursorItem", function()
	local p = pending
	pending = nil
	if p and p.dialog:IsShown() and p.dialog.which == p.which then
		say("удалено " .. p.text)
	end
end)

-- окно закрыли отменой: забываем, иначе следующее обычное удаление напишет чужое имя
local watcher = CreateFrame("Frame")
watcher:Hide()
watcher:SetScript("OnUpdate", function(self)
	if not (pending and pending.dialog:IsShown() and pending.dialog.which == pending.which) then
		pending = nil
		self:Hide()
	end
end)

local function confirm(which, link, text)
	local dialog = StaticPopup_Show(which, link)
	if not dialog then
		ClearCursor()
		return
	end
	pending = { which = which, text = text, dialog = dialog }
	watcher:Show()
end

local function needsConfirm(quality)
	if quality >= 4 then return db.askPurple end
	if quality == 3 then return db.askBlue end
	if quality == 2 then return db.askGreen end
	return false
end

local function delete(bag, slot)
	if CursorHasItem() or SpellIsTargeting() then return end
	local _, count, locked, quality, _, _, link = GetContainerItemInfo(bag, slot)
	if not link or locked then return end
	if not quality or quality < 0 then quality = select(3, GetItemInfo(link)) or 1 end
	local text = link .. ((count or 1) > 1 and (" x" .. count) or "")

	PickupContainerItem(bag, slot)
	if not CursorHasItem() then return end

	if needsConfirm(quality) then
		confirm(quality >= 3 and "DELETE_GOOD_ITEM" or "DELETE_ITEM", link, text)
	else
		DeleteCursorItem()
		say("удалено " .. text)
	end
end

-- один крестик на все сумки, переезжает на ячейку под мышью
local button = CreateFrame("Button", "BagnonDeleteXButton")
button:SetNormalTexture([[Interface\RaidFrame\ReadyCheck-NotReady]])
button:SetHighlightTexture([[Interface\RaidFrame\ReadyCheck-NotReady]], "ADD")
button:RegisterForClicks("LeftButtonUp")
button:Hide()

button:SetScript("OnClick", function(self)
	local slot = self.owner
	if slot and slot:GetItem() and not slot:IsCached() then
		delete(slot:GetBag(), slot:GetID())
	end
end)

button:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Удалить предмет", 1, 0.3, 0.3)
	GameTooltip:Show()
end)

button:SetScript("OnLeave", function()
	GameTooltip:Hide()
end)

-- прячем, когда мышь ушла с ячейки (переход с ячейки на сам крестик не считается)
button:SetScript("OnUpdate", function(self)
	local slot = self.owner
	if not (slot and slot:IsVisible() and MouseIsOver(slot) and slot:GetItem()) then
		self:Hide()
		self.owner = nil
	end
end)

local function attach(slot)
	if not slot:GetItem() or slot:IsCached() then return end
	button.owner = slot
	button:SetParent(slot)
	button:ClearAllPoints()
	button:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 2, 2)
	button:SetFrameLevel(slot:GetFrameLevel() + 5)
	button:Show()
end

-- все созданные ячейки, нужны для предпросмотра крестиков в настройках
local slots = setmetatable({}, { __mode = "k" })

-- Bagnon создаёт ячейки при первом открытии сумок, то есть уже после загрузки этого аддона
local create = ItemSlot.Create
function ItemSlot:Create(...)
	local slot = create(self, ...)
	slot:HookScript("OnEnter", attach)
	slots[slot] = true
	return slot
end

-- Предпросмотр: пока открыта страница настроек, на всех вещах в сумках нарисованы крестики текущего размера.
-- Это просто картинки, нажать на них нельзя.
local previewing = false

local function refreshPreview()
	for slot in pairs(slots) do
		local mark = slot.deleteXPreview
		if previewing and slot:IsVisible() and slot:GetItem() and not slot:IsCached() then
			if not mark then
				mark = slot:CreateTexture(nil, "OVERLAY")
				mark:SetTexture([[Interface\RaidFrame\ReadyCheck-NotReady]])
				mark:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 2, 2)
				slot.deleteXPreview = mark
			end
			mark:SetWidth(db.size)
			mark:SetHeight(db.size)
			mark:Show()
		elseif mark then
			mark:Hide()
		end
	end
end

--[[ Кнопка «Мусор» ]]--

-- свободные ячейки только в обычных сумках: в сумки для профессий серые вещи всё равно не лягут
local function freeSlots()
	local free = 0
	for bag = 0, NUM_BAG_SLOTS do
		local n, bagType = GetContainerNumFreeSlots(bag)
		if bagType == 0 then free = free + n end
	end
	return free
end

local QUEST_CLASS = select(12, GetAuctionItemClasses()) -- «Задания»

-- Хлам: серая вещь, которую покупает торговец и которая не относится к заданиям.
-- Серые вещи без цены и квестовые бывают нужными, их кнопка не трогает.
local function isJunk(bag, slot, quality, link)
	local _, _, itemQuality, _, _, itemType, _, _, _, _, price = GetItemInfo(link)
	if not (quality == 0 or (quality == -1 and itemQuality == 0)) then return false end
	if not price or price <= 0 then return false end
	if itemType == QUEST_CLASS then return false end
	if GetContainerItemQuestInfo and GetContainerItemQuestInfo(bag, slot) then return false end
	return true, price
end

-- хлам в сумках: сколько его и где самая дешёвая вещь (по цене всего стака у торговца)
local function scanJunk()
	local count, total, cheapBag, cheapSlot, cheapLink, cheapValue = 0, 0
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			local _, stack, locked, quality, _, _, link = GetContainerItemInfo(bag, slot)
			if link and not locked then
				local junkItem, price = isJunk(bag, slot, quality, link)
				if junkItem then
					local value = price * (stack or 1)
					count = count + 1
					total = total + value
					if not cheapValue or value < cheapValue then
						cheapBag, cheapSlot, cheapLink, cheapValue = bag, slot, link, value
					end
				end
			end
		end
	end
	return count, total, cheapBag, cheapSlot, cheapLink, cheapValue
end

-- стандартная красная кнопка Blizzard, как «Закрыть» в окнах игры
local junk = CreateFrame("Button", "BagnonDeleteXJunk", nil, "UIPanelButtonTemplate")
junk:SetHeight(20)
junk:RegisterForClicks("LeftButtonUp")
junk:Hide()
junk:SetText(" ")

local function updateJunk()
	local frame = junk.owner
	if not (db and db.junkButton and frame and frame:IsVisible()) or InCombatLockdown()
			or freeSlots() > db.junkSlots then
		junk:Hide()
		return
	end
	local count, total = scanJunk()
	if count == 0 then
		junk:Hide()
		return
	end
	junk:SetText("Мусор: " .. count)
	junk:SetWidth(junk:GetFontString():GetStringWidth() + 24)
	junk.total = total
	junk:Show()
end

junk:SetScript("OnClick", function(self)
	local _, _, bag, slot = scanJunk()
	if bag then delete(bag, slot) end
end)

junk:SetScript("OnEnter", function(self)
	local count, total, _, _, link, value = scanJunk()
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Удалить самую дешёвую серую вещь")
	if link then
		GameTooltip:AddLine("Следующей удалится: " .. link .. " (" .. GetCoinTextureString(value) .. ")", 1, 1, 1)
	end
	GameTooltip:AddLine("Хлама в сумках: " .. count .. ", всего на " .. GetCoinTextureString(total), 0.8, 0.8, 0.8)
	GameTooltip:AddLine("Свободных ячеек: " .. freeSlots(), 0.8, 0.8, 0.8)
	GameTooltip:Show()
end)

junk:SetScript("OnLeave", function()
	GameTooltip:Hide()
end)

-- кнопка живёт в инвентаре Bagnon, слева от золота; Layout вызывается при каждой перестройке окна
hooksecurefunc(Bagnon.Frame, "Layout", function(frame)
	if frame:GetFrameID() ~= "inventory" or not frame:IsVisible() then return end
	junk.owner = frame
	junk:SetParent(frame)
	junk:ClearAllPoints()
	local money = frame:HasMoneyFrame() and frame:GetMoneyFrame()
	if money then
		junk:SetPoint("RIGHT", money, "LEFT", -4, 0)
	else
		junk:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 12)
	end
	junk:SetFrameLevel(frame:GetFrameLevel() + 10)
	updateJunk()
end)

-- содержимое сумок меняется пачками событий, поэтому пересчитываем не чаще раза в 0,2 с
local junkEvents = CreateFrame("Frame")
local junkDirty, junkWait = true, 0
junkEvents:RegisterEvent("BAG_UPDATE")
junkEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
junkEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
junkEvents:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_REGEN_DISABLED" then
		junk:Hide()
	else
		junkDirty = true
	end
end)
junkEvents:SetScript("OnUpdate", function(self, delta)
	junkWait = junkWait + delta
	if junkDirty and junkWait > 0.2 then
		junkDirty, junkWait = false, 0
		updateJunk()
	end
end)

--[[ Настройки ]]--

local OPTIONS = {
	{ key = "askGreen", text = "Подтверждение удаления |cff1eff00зелёных|r вещей:" },
	{ key = "askBlue", text = "Подтверждение удаления |cff0070ddсиних|r вещей:" },
	{ key = "askPurple", text = "Подтверждение удаления |cffa335eeфиолетовых|r вещей:" },
}

-- без родителя страница рисуется под окном «Интерфейс» и выглядит пустой
local panel = CreateFrame("Frame", "BagnonDeleteXOptions", InterfaceOptionsFramePanelContainer)
panel.name = "Крестик удаления"
panel:Hide()

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Крестик удаления")

local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
hint:SetWidth(560)
hint:SetJustifyH("LEFT")
hint:SetText("Крестик появляется в углу вещи под мышью в сумках Bagnon. Серые и белые вещи он удаляет сразу. "
	.. "Если подтверждение включено, откроется окно игры; там, где игра просит вписать слово, оно уже вписано. "
	.. "Настройка фиолетовых действует и на легендарные вещи. "
	.. "Пока открыта эта страница, сумки открыты и крестики видны на всех вещах, чтобы подобрать размер.")

local function showState(check, on)
	check:SetChecked(on)
	check.state:SetText(on and "|cff00ff00да|r" or "|cffff5555нет|r")
end

local checks = {}
local function addCheck(i, key, text, anchor, y, after)
	local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
	label:SetWidth(300)
	label:SetJustifyH("LEFT")
	label:SetText(text)

	local check = CreateFrame("CheckButton", "BagnonDeleteXCheck" .. i, panel, "InterfaceOptionsCheckButtonTemplate")
	check:SetPoint("LEFT", label, "RIGHT", 4, 0)
	check.state = _G[check:GetName() .. "Text"]
	check:SetScript("OnClick", function(self)
		db[key] = self:GetChecked() and true or false
		showState(self, db[key])
		if after then after() end
	end)
	checks[key] = check
	return label
end

for i, opt in ipairs(OPTIONS) do
	addCheck(i, opt.key, opt.text, hint, -20 - (i - 1) * 30)
end

local function applySize()
	button:SetWidth(db.size)
	button:SetHeight(db.size)
end

local slider = CreateFrame("Slider", "BagnonDeleteXSize", panel, "OptionsSliderTemplate")
slider:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 4, -20 - #OPTIONS * 30 - 24)
slider:SetWidth(240)
slider:SetMinMaxValues(MIN_SIZE, MAX_SIZE)
slider:SetValueStep(1)
_G[slider:GetName() .. "Low"]:SetText(MIN_SIZE)
_G[slider:GetName() .. "High"]:SetText(MAX_SIZE)
slider:SetScript("OnValueChanged", function(self, value)
	value = math.floor(value + 0.5)
	_G[self:GetName() .. "Text"]:SetText("Размер крестика: " .. value)
	if db then
		db.size = value
		applySize()
		refreshPreview()
	end
end)

local junkTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
junkTitle:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, -30)
junkTitle:SetText("Кнопка «Мусор»")

local junkHint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
junkHint:SetPoint("TOPLEFT", junkTitle, "BOTTOMLEFT", 0, -6)
junkHint:SetWidth(560)
junkHint:SetJustifyH("LEFT")
junkHint:SetText("Появляется внизу инвентаря слева от золота, когда свободных ячеек мало и в сумках есть серые вещи. "
	.. "Клик удаляет самую дешёвую серую вещь. Серые вещи для заданий и те, что торговец не покупает, кнопка не трогает. "
	.. "В бою кнопка прячется.")

local junkLabel = addCheck(#OPTIONS + 1, "junkButton", "Показывать кнопку «Мусор»:", junkHint, -16, updateJunk)

local junkSlider = CreateFrame("Slider", "BagnonDeleteXJunkSlots", panel, "OptionsSliderTemplate")
junkSlider:SetPoint("TOPLEFT", junkLabel, "BOTTOMLEFT", 4, -30)
junkSlider:SetWidth(240)
junkSlider:SetMinMaxValues(0, MAX_JUNK_SLOTS)
junkSlider:SetValueStep(1)
_G[junkSlider:GetName() .. "Low"]:SetText(0)
_G[junkSlider:GetName() .. "High"]:SetText(MAX_JUNK_SLOTS)
junkSlider:SetScript("OnValueChanged", function(self, value)
	value = math.floor(value + 0.5)
	_G[self:GetName() .. "Text"]:SetText("Показывать, когда свободных ячеек: " .. value .. " и меньше")
	if db then
		db.junkSlots = value
		updateJunk()
	end
end)

-- инвентарь открываем на время настроек, чтобы крестики было видно; закрываем, только если открыли сами
local openedInventory = false
local elapsed = 0

panel:SetScript("OnShow", function()
	for key, check in pairs(checks) do showState(check, db[key]) end
	slider:SetValue(db.size)
	junkSlider:SetValue(db.junkSlots)
	local inventory = Bagnon:GetFrame("inventory")
	openedInventory = not (inventory and inventory:IsShown())
	if openedInventory then Bagnon:ShowFrame("inventory") end
	previewing = true
	refreshPreview()
end)

panel:SetScript("OnHide", function()
	previewing = false
	refreshPreview()
	if openedInventory then Bagnon:HideFrame("inventory") end
	openedInventory = false
end)

-- ячейки появляются и меняются уже после открытия сумок, поэтому обновляем картинки по таймеру
panel:SetScript("OnUpdate", function(self, delta)
	elapsed = elapsed + delta
	if elapsed > 0.25 then
		elapsed = 0
		refreshPreview()
	end
end)

InterfaceOptions_AddCategory(panel)

SLASH_BAGNONDELETEX1 = "/delx"
SlashCmdList.BAGNONDELETEX = function()
	-- первый вызов в 3.3.5 иногда открывает не ту страницу, второй её исправляет
	InterfaceOptionsFrame_OpenToCategory(panel)
	InterfaceOptionsFrame_OpenToCategory(panel)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, addon)
	if addon ~= "borealis_Bagnon_DeleteX" then return end
	BagnonDeleteXDB = BagnonDeleteXDB or {}
	db = BagnonDeleteXDB
	for key, value in pairs(DEFAULTS) do
		if db[key] == nil then db[key] = value end
	end
	applySize()
	self:UnregisterEvent("ADDON_LOADED")
end)
