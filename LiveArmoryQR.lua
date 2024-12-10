
local _, ADDONSELF = ...

local qrcode = ADDONSELF.qrcode

local BLOCK_SIZE = 2
local PLAYER = "player";
local CHAR_FIELD_SEPARATOR = "$";
local CHAR_VALUE_SEPARATOR = "-";
local CHAR_SUB_VALUE_SEPARATOR = "+";
local IDX_WOW_API_ITEM_STRING_PERMANENT_ENCHANT = 3;
local IDX_WOW_API_ITEM_STRING_RANDOM_ENCHANTMENT = 8;
local CHAR_PADDING = "%";
local REPAINT_CD_SEC = 0.250;


local MIN_MESSAGE_SIZE = 225;
local EQUIPMENT_SLOTS = { "HEADSLOT", "NECKSLOT", "SHOULDERSLOT", "BACKSLOT", "CHESTSLOT", "SHIRTSLOT", "TABARDSLOT", "WRISTSLOT", "HANDSSLOT", "WAISTSLOT", "LEGSSLOT", "FEETSLOT", "FINGER0SLOT", "FINGER1SLOT", "TRINKET0SLOT", "TRINKET1SLOT", "MAINHANDSLOT", "SECONDARYHANDSLOT", "RANGEDSLOT"};
local BASE_32_DIGITS = {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V"};
local CHARACTER_RACES = { NONE = 0, HUMAN = 1, NIGHTELF = 2, DWARF = 3, GNOME = 4, ORC = 5, TROLL = 6, SCOURGE = 7, TAUREN = 8 };
local CHARACTER_CLASSES = { NONE = 0, WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 6, MAGE = 7, WARLOCK = 8, DRUID = 9 };

local mainFrame;
local debugMode = false;
local repaintCdRemainingSec = 0;

local repaint = 0;
local lastMessage = nil;
local lastPrintedQR = nil;

local qrRefreshCoroutine = nil;

local function PrintDebug(message)
    if debugMode then
        DEFAULT_CHAT_FRAME:AddMessage(message);
    end
end

local function CreateQRTip(qrsize, containerFrame)
    if containerFrame.boxes ~= nil then
        return mainFrame;
    end

    local function CreateBlock(idx)
        local blockFrame = CreateFrame("Frame", nil, mainFrame, BackdropTemplateMixin and "BackdropTemplate")
        blockFrame:SetWidth(BLOCK_SIZE)
        blockFrame:SetHeight(BLOCK_SIZE)
        blockFrame.texture = blockFrame:CreateTexture(nil, "OVERLAY")
        blockFrame.texture:SetAllPoints(blockFrame)
        blockFrame.texture:SetColorTexture(0, 0, 0, 1);
        blockFrame:Hide();
        local x = (idx % qrsize) * BLOCK_SIZE
        local y = (math.floor(idx / qrsize)) * BLOCK_SIZE
        blockFrame:SetPoint("TOPLEFT", mainFrame, x, -y);
        return blockFrame
    end

    do
        containerFrame:SetFrameStrata("BACKGROUND");
        containerFrame:SetWidth(qrsize * BLOCK_SIZE);
        containerFrame:SetHeight(qrsize * BLOCK_SIZE);
        containerFrame:SetMovable(true);
        containerFrame:EnableMouse(true);
        containerFrame:RegisterForDrag("LeftButton") ;
        containerFrame:SetScript("OnDragStart", function(self) self:StartMoving() end);
        containerFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end);
        containerFrame.texture = containerFrame:CreateTexture(nil, "OVERLAY");
        containerFrame.texture:SetAllPoints(containerFrame);
        containerFrame.texture:SetColorTexture(1, 1, 1);
    end

    containerFrame.boxes = {}

    containerFrame.SetBlack = function(idx)
        containerFrame.boxes[idx]:Show();
    end

    containerFrame.SetWhite = function(idx)
        containerFrame.boxes[idx]:Hide();
    end

    for i = 1, qrsize * qrsize do
        tinsert(containerFrame.boxes, CreateBlock(i - 1))
    end
    containerFrame:Show();

    return containerFrame
end

local function CalculateAndPrintQrCode()
    PrintDebug("Requested repaint at "..GetTime());
    local ok, qrcodeOrErrorMessage = qrcode(lastMessage, 1);
    if not ok then
        print(qrcodeOrErrorMessage);
    else
        local tab = qrcodeOrErrorMessage
        local size = #tab

        local f = CreateQRTip(size, mainFrame)
        
        for x = 1, #tab do
            for y = 1, #tab do
                if lastPrintedQR == nil or tab[x][y] ~= lastPrintedQR[x][y] then
                    if tab[x][y] > 0 then
                        f.SetBlack((y - 1) * size + x - 1 + 1)
                    else
                        f.SetWhite((y - 1) * size + x - 1 + 1)
                    end
                end
            end
        end
        lastPrintedQR = tab;
    end
    PrintDebug("Finished repaint at "..GetTime());
    repaint = repaint + 1;
    PrintDebug("QR Code repaint count: "..repaint);
end

local function ConcatenateStatusValue(status, value)
    if string.len(status) == 0 then
        return "" .. value;
    else 
        return status .. CHAR_FIELD_SEPARATOR .. value
    end
end

local function IntToBase32String(integer)
    local int = tonumber(integer); 
    if int == nil or int == 0 then
        return "0";
    end
    local base32String = "";
    local divisionResult = int;
    while divisionResult > 0 do
        local modulo = divisionResult % 32;
        local digit = BASE_32_DIGITS[modulo + 1];
        base32String = digit..base32String;
        divisionResult = math.floor(divisionResult / 32);
    end
    return base32String;
end

local function GetCharacterTalentsInWowheadFormat()
    local wowheadTalentString = "";
    local tabBuffer = "";
    local numTabs = GetNumTalentTabs();
    for tabIndex = 1, numTabs do
        local tabActive = false;
        local numTalents = GetNumTalents(tabIndex);
        local talentTree = {};
        local maxTier = 0;
        local maxColumn = 0;
        for talent = 1, numTalents do
            local nameTalent, icon, tier, column, currRank, maxRank = GetTalentInfo(tabIndex, talent);
            if talentTree[tier] == nil then
                talentTree[tier] = {};
            end
            talentTree[tier][column] = currRank;
            if tier > maxTier then
                maxTier = tier;
            end
            if column > maxColumn then
                maxColumn = column;
            end
        end
        local tierBuffer = "";
        for tier = 1, maxTier do
            for column = 1, maxColumn do
                if talentTree[tier][column] ~= nil then
                    tierBuffer = tierBuffer..talentTree[tier][column];
                    if talentTree[tier][column] ~= 0 then
                        tabBuffer = tabBuffer..tierBuffer;
                        tierBuffer = "";
                        tabActive = true;
                    end
                end
            end
        end
        if tabIndex < numTabs then
            tabBuffer = tabBuffer..CHAR_VALUE_SEPARATOR;
        end
        if tabActive then
            wowheadTalentString = wowheadTalentString..tabBuffer;
            tabBuffer = "";
        end
    end
    return wowheadTalentString;
end

local function GetCharacterEquipment()
    local characterEquipment = "";
    for index, inventorySlot in ipairs(EQUIPMENT_SLOTS) do
        if index > 1 then
            characterEquipment = characterEquipment..CHAR_VALUE_SEPARATOR;
        end
        local slotId, _ = GetInventorySlotInfo(inventorySlot);
        local equippedItemId = GetInventoryItemID(PLAYER, slotId);
        if equippedItemId ~= nil then
            local itemOutputBuffer = IntToBase32String(equippedItemId);
            local equippedItemLink = GetInventoryItemLink(PLAYER, slotId);
            if equippedItemLink then
                local itemString, itemName = equippedItemLink:match("|H(.*)|h%[(.*)%]|h");
                local itemStringIdx = 1;
                local permanentEnchant;
                local randomEnchantment;
                for part in (itemString .. ":").gmatch(itemString, "([^:]*):") do
                    if string.len(part) > 0 then
                        if itemStringIdx == IDX_WOW_API_ITEM_STRING_PERMANENT_ENCHANT then
                            permanentEnchant = part;
                        end
                        if itemStringIdx == IDX_WOW_API_ITEM_STRING_RANDOM_ENCHANTMENT then
                            randomEnchantment = part;
                        end
                    end
                    itemStringIdx = itemStringIdx + 1;
                end
                if permanentEnchant or randomEnchantment then
                    if permanentEnchant then
                        itemOutputBuffer = itemOutputBuffer..CHAR_SUB_VALUE_SEPARATOR..IntToBase32String(permanentEnchant);
                    else
                        itemOutputBuffer = itemOutputBuffer..CHAR_SUB_VALUE_SEPARATOR;
                    end
                    if randomEnchantment then
                        itemOutputBuffer = itemOutputBuffer..CHAR_SUB_VALUE_SEPARATOR..IntToBase32String(randomEnchantment);
                    end
                end
            end
            characterEquipment = characterEquipment..itemOutputBuffer;
        end
    end
    return characterEquipment;
end


local function GetCharacterStatus() 
    local characterStatus = "";

    -- TODO: Figure out encoding of character name (ideally we want only uppercase letters for smaller QR codes)
    -- Name currently removed because it is a major pain to encode and it's typically visible on UI at a glance
    -- local characterStatus = ConcatenateStatusValue(characterStatus, UnitName(PLAYER));
    
    -- CLASS
    local _, englishClass, _ = UnitClass(PLAYER);
    englishClass = string.upper(englishClass);
    local classId = CHARACTER_CLASSES[englishClass];
    if classId == nil then
        classId = 0;
    end
    characterStatus = ConcatenateStatusValue(characterStatus, classId);
    -- RACE
    local _, raceEn, _ = UnitRace(PLAYER);
    raceEn = string.upper(raceEn);
    local raceId = CHARACTER_RACES[raceEn];
    if raceId == nil then
        raceId = 0;
    end
    characterStatus = ConcatenateStatusValue(characterStatus, raceId);
    -- LEVEL
    characterStatus = ConcatenateStatusValue(characterStatus, IntToBase32String(UnitLevel(PLAYER)));
    -- TALENTS
    characterStatus = ConcatenateStatusValue(characterStatus, GetCharacterTalentsInWowheadFormat());
    -- EQUIPMENT
    characterStatus = ConcatenateStatusValue(characterStatus, GetCharacterEquipment());
    -- CURRENT HP
    characterStatus = ConcatenateStatusValue(characterStatus, IntToBase32String(UnitHealth(PLAYER)));
    -- MAX HP
    characterStatus = ConcatenateStatusValue(characterStatus, IntToBase32String(UnitHealthMax(PLAYER)));
    -- CURRENT POWER TYPE: MANA/ENERGY/RAGE
    characterStatus = ConcatenateStatusValue(characterStatus, UnitPowerType(PLAYER));
    -- CURRENT MANA/ENERGY/RAGE
    characterStatus = ConcatenateStatusValue(characterStatus, IntToBase32String(UnitPower(PLAYER)));
    -- MAX MANA/ENERGY/RAGE
    characterStatus = ConcatenateStatusValue(characterStatus, IntToBase32String(UnitPowerMax(PLAYER)));
    -- GOLD
    characterStatus = ConcatenateStatusValue(characterStatus, IntToBase32String(GetMoney()));
    -- DEAD OR GHOST
    characterStatus = ConcatenateStatusValue(characterStatus, UnitIsDeadOrGhost(PLAYER) and "1" or "0");

    return characterStatus;
end

local function PadMessageToMinLength(message, minLength, paddingChar) 
    if message == nil then
        return message;
    end
    local messageLength = string.len(message);
    if messageLength < minLength then
        local paddedMessage = message..CHAR_FIELD_SEPARATOR;
        for i = 1, minLength - messageLength - 1 do
            paddedMessage = paddedMessage..paddingChar;
        end
        return paddedMessage;
    else 
        return message;
    end
end

local function RefreshQRCode() 
    if qrRefreshCoroutine ~= nil and coroutine.status(qrRefreshCoroutine) ~= "dead" then
        -- If we haven't finished re-painting the previous message, do not re-paint (just let it finish)
        return;
    end
    local characterStatus = GetCharacterStatus();
    local message = PadMessageToMinLength(characterStatus, MIN_MESSAGE_SIZE, CHAR_PADDING);
    if message == lastMessage then
        -- If the message hasn't changed, there is no need to re-paint
        return;
    end
    
    lastMessage = message;
    PrintDebug(lastMessage);
    qrRefreshCoroutine = coroutine.create(CalculateAndPrintQrCode);
end

local function RefreshMainFramePosition() 
    DEFAULT_CHAT_FRAME:AddMessage("About to set position");
    mainFrame:ClearAllPoints();
    mainFrame:SetPoint("TOPLEFT", UIParent, LiveArmoryQRPosition.x, LiveArmoryQRPosition.y);
end

local function OnUpdateHandler(self, elapsed)
    if elapsed > 0.01 then
        PrintDebug(elapsed);
    end
    if qrRefreshCoroutine ~= nil and coroutine.status(qrRefreshCoroutine) == "suspended" then
        coroutine.resume(qrRefreshCoroutine);
    end
    repaintCdRemainingSec = repaintCdRemainingSec - elapsed;
    if repaintCdRemainingSec <= 0 then
        RefreshQRCode();
        repaintCdRemainingSec = repaintCdRemainingSec + REPAINT_CD_SEC;
    end
end

mainFrame = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate");
mainFrame:SetScript("OnUpdate", OnUpdateHandler);
mainFrame:RegisterEvent("ADDON_LOADED");

mainFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == 'LiveArmoryQR' then
        DEFAULT_CHAT_FRAME:AddMessage("Config loaded");
        if LiveArmoryQRPosition == nil then
            LiveArmoryQRPosition = { x = 0, y = 0 };
        end
        RefreshMainFramePosition();
    end
end)


SlashCmdList["LAQR"] = function(cmdParam, editbox)
    if cmdParam == "debug" then
        debugMode = not debugMode;
        DEFAULT_CHAT_FRAME:AddMessage("LiveArmoryQR debug mode set to "..tostring(debugMode));
    else if cmdParam == "reset" then
        LiveArmoryQRPosition = { x = 0, y = 0 };
        RefreshMainFramePosition();
        DEFAULT_CHAT_FRAME:AddMessage("Resetting QR position");
    end
        RefreshQRCode();
    end
end

SLASH_LAQR1 = "/laqr"