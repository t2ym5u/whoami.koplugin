local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InfoMessage     = require("ui/widget/infomessage")
local InputContainer  = require("ui/widget/container/inputcontainer")
local InputDialog     = require("ui/widget/inputdialog")
local LineWidget      = require("ui/widget/linewidget")
local RenderText      = require("ui/rendertext")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local MenuHelper = require("menu_helper")
local ScreenBase = require("screen_base")
local Game       = lrequire("game")

local DeviceScreen = Device.screen
local DPI_SCALE = DeviceScreen:scaleBySize(1000) / 1000

local function pxFace(px)
    return Font:getFace("cfont", math.max(8, math.floor(px / DPI_SCALE)))
end

local function textWidth(face, text, bold)
    return RenderText:sizeUtf8Text(0, DeviceScreen:getWidth() * 8, face, text, true, bold).x
end

-- One line of text at up to `px` pixels, shrunk until it fits `max_w`.
local function fitLine(text, px, max_w, bold)
    local face = pxFace(px)
    while px > 12 do
        if textWidth(face, text, bold) <= max_w then break end
        px   = math.floor(px * 0.9)
        face = pxFace(px)
    end
    return TextWidget:new{ text = text, face = face, max_width = max_w, bold = bold }
end

local function wrapText(text, face, width, bold)
    return TextBoxWidget:new{ text = text, face = face, width = width, alignment = "center", bold = bold }
end

-- A card's word as big as `max_w` × `max_h` allows: every word of it on one
-- line (never cut mid-word), wrapping between words.
local function fitCard(text, px, max_w, max_h)
    while true do
        local face = pxFace(px)
        local ok = true
        for w in text:gmatch("%S+") do
            if textWidth(face, w, true) > max_w then ok = false; break end
        end
        if ok then
            local tb = wrapText(text, face, max_w, true)
            if tb:getSize().h <= max_h or px <= 14 then return tb end
            tb:free()
        elseif px <= 14 then
            return wrapText(text, face, max_w, true)
        end
        px = math.floor(px * 0.92)
    end
end

-- ---------------------------------------------------------------------------
-- Box -- fixed-size area; remembers where it was painted (so the timer can be
-- refreshed on its own) and runs `callback(ges)` when tapped, if given.
-- ---------------------------------------------------------------------------

local Box = InputContainer:extend{
    width = nil, height = nil, callback = nil,
    align = "center", vertical_align = "center",
}

function Box:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    if self.callback then
        self.ges_events = {
            Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        }
    end
end

function Box:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

-- The Tap event is offered to children before their parent: a Box used only
-- for layout (no callback) must let it through, or the timer box inside the
-- play area would swallow every tap meant for the play area.
function Box:onTap(_, ges)
    if not self.callback then return false end
    self.callback(ges)
    return true
end

-- ---------------------------------------------------------------------------
-- Categories
-- ---------------------------------------------------------------------------

-- One file per category and language: cards/<lang>/<id>.lua, loaded only
-- when the category is played (or counted for the menu).
local CATEGORY_ORDER = {
    "people", "characters", "heroes", "cartoons", "mythology", "movies",
    "sports", "animals", "jobs", "places", "monuments", "art", "inventions",
    "objects", "food", "instruments", "actions", "kids",
}

local function categoryLabel(id)
    local labels = {
        people     = _("Famous people"),
        characters = _("Pop culture characters"),
        movies     = _("Movies & series"),
        animals    = _("Animals"),
        jobs       = _("Jobs"),
        places     = _("Countries & cities"),
        monuments  = _("Monuments"),
        objects    = _("Objects"),
        actions    = _("Mimes & actions"),
        mythology  = _("Mythology & legends"),
        heroes     = _("Superheroes & villains"),
        cartoons   = _("Cartoons & comics"),
        sports     = _("Sports legends"),
        inventions = _("Inventions & discoveries"),
        food       = _("Food & dishes"),
        instruments = _("Musical instruments"),
        art        = _("Famous paintings & sculptures"),
        kids       = _("Kids (easy)"),
    }
    return labels[id] or id
end

local DURATIONS = { 30, 60, 90 }

local GAME_RULES_EN = [[
Who Am I? — Rules

Players take turns. The player whose turn it is holds the reader against their forehead (or chest), screen facing the others, without looking at it.

The others give clues — words, sounds, mimes — but never say the word on the screen. The holder tries to guess as many cards as possible before the time runs out:
• found it? tap with the RIGHT hand (+1);
• pass? tap with the LEFT hand (no point).
The holder can't see the screen: their right hand is on the half the others see on their LEFT. The labels under the card say which hand is which. The hands can be swapped in the menu ("Found side: holder's right hand"). On readers with page-turn buttons, "next page" is Found and "previous page" is Pass.

When the time is up, the holder sees the cards of the turn: those found and those passed or missed. Then the reader goes to the next player.

After the chosen number of rounds (each player plays once per round), the player with the most cards found wins.

Pick the categories in the menu (18 of them, from Famous people to Kids); "Mix" plays them all. "Mimes & actions" cards are best mimed, without a word; "Kids (easy)" suits young players.
]]

local GAME_RULES_FR = [[
Qui suis-je ? — Règles

Les joueurs jouent à tour de rôle. Celui dont c'est le tour tient la liseuse contre son front (ou sa poitrine), écran tourné vers les autres, sans le regarder.

Les autres donnent des indices — mots, bruitages, mimes — sans jamais prononcer le mot affiché. Le joueur essaie d'en deviner le plus possible avant la fin du temps :
• trouvé ? il touche l'écran de la main DROITE (+1) ;
• il passe ? il touche de la main GAUCHE (pas de point).
Le joueur ne voit pas l'écran : sa main droite tombe sur la moitié que les autres voient à GAUCHE. Les libellés sous la carte indiquent quelle main est laquelle. Les mains s'inversent dans le menu (« Côté Trouvé : main droite du joueur »). Sur les liseuses à boutons, « page suivante » vaut Trouvé et « page précédente » Passer.

Quand le temps est écoulé, le joueur voit les cartes de son tour : trouvées, passées ou manquées. Puis la liseuse passe au joueur suivant.

Après le nombre de manches choisi (chaque joueur joue une fois par manche), celui qui a trouvé le plus de cartes gagne.

Choisissez les catégories dans le menu (18, des Personnages célèbres aux Enfants) ; « Mélange » les joue toutes. Les cartes « Mimes et actions » se miment, sans un mot ; « Enfants (facile) » convient aux plus jeunes.
]]

-- ---------------------------------------------------------------------------
-- WhoAmIScreen
--
-- phase "handover": pass the reader to the next player, tap when ready
--       "ready":    3-2-1 so the holder can turn the screen away
--       "playing":  the card, the countdown, Found / Pass halves
--       "summary":  the cards of the turn just played
--       "over":     final scores
-- ---------------------------------------------------------------------------

local WhoAmIScreen = ScreenBase:extend{}

local READY_SECONDS = 3

function WhoAmIScreen:init()
    local default_lang = _.lang() == "fr" and "fr" or "en"
    self.lang       = self.plugin:getSetting("lang", default_lang)
    self.duration   = self.plugin:getSetting("duration", 60)
    self.rounds     = self.plugin:getSetting("rounds", 2)
    -- The holder faces away from the screen, so the hand that means "Found"
    -- is stored from the holder's side: their right hand (the default) is the
    -- screen's LEFT half as the others see it.
    self.found_hand = self.plugin:getSetting("found_hand", "right")
    self.found_left = self.found_hand == "right"
    self.selected   = self:_loadSelection()
    self.names      = self.plugin:getSetting("players", nil)
    if type(self.names) ~= "table" or #self.names < Game.MIN_PLAYERS then
        self.names = { T(_("Player %1"), 1), T(_("Player %1"), 2) }
    end

    local saved = self.plugin:loadState()
    self.game = saved and Game.deserialize(saved, self:_deck())
    if not self.game then self:_newGame() end
    self.phase = self.game:isOver() and "over" or "handover"
    self.last_action = 0

    ScreenBase.init(self)

    -- Page-turn buttons, when the reader has them: next = Found, previous = Pass.
    if Device:hasKeys() and Device.input and Device.input.group then
        self.key_events = self.key_events or {}
        if Device.input.group.PgFwd then
            self.key_events.FoundKey = { { Device.input.group.PgFwd } }
        end
        if Device.input.group.PgBack then
            self.key_events.PassKey = { { Device.input.group.PgBack } }
        end
    end
end

-- ---------------------------------------------------------------------------
-- Content
-- ---------------------------------------------------------------------------

-- Cards of one category, nil when the file is missing. Not cached: the deck
-- keeps what it needs, and the menu only counts.
function WhoAmIScreen:_loadCategory(id, lang)
    local path = _dir .. "cards/" .. (lang or self.lang) .. "/" .. id .. ".lua"
    local chunk = loadfile(path)
    if not chunk then return nil end
    local ok, list = pcall(chunk)
    if ok and type(list) == "table" then return list end
end

-- The selected categories as { { id, cards }, ... } (all of them for Mix).
function WhoAmIScreen:_content(selected)
    local out = {}
    for _i, id in ipairs(CATEGORY_ORDER) do
        if selected == nil or selected[id] then
            local cards = self:_loadCategory(id) or self:_loadCategory(id, "en")
            if cards then out[#out + 1] = { id = id, cards = cards } end
        end
    end
    return out
end

function WhoAmIScreen:_deck()
    local deck = Game.buildDeck(self:_content(self.selected))
    if #deck == 0 then deck = Game.buildDeck(self:_content(nil)) end
    collectgarbage()
    return deck
end

function WhoAmIScreen:_loadSelection()
    local saved = self.plugin:getSetting("categories", "")
    if not saved or saved == "" then return nil end
    local sel = {}
    for id in saved:gmatch("[^,]+") do sel[id] = true end
    return sel
end

function WhoAmIScreen:_saveSelection()
    if not self.selected then
        self.plugin:saveSetting("categories", "")
        return
    end
    local parts = {}
    for id in pairs(self.selected) do parts[#parts + 1] = id end
    table.sort(parts)
    self.plugin:saveSetting("categories", table.concat(parts, ","))
end

function WhoAmIScreen:_newGame()
    self.game = Game.new{ players = self.names, rounds = self.rounds, deck = self:_deck() }
    self.summary = nil
end

function WhoAmIScreen:serializeState()
    return self.game:serialize()
end

function WhoAmIScreen:_save()
    self.plugin:saveState(self:serializeState())
end

function WhoAmIScreen:isRoundOver()
    return self.phase == "over"
end

function WhoAmIScreen:_redraw(mode)
    self:buildLayout()
    UIManager:setDirty(self, function() return mode or "ui", self.dimen end)
end

-- ---------------------------------------------------------------------------
-- Countdown: one tick a second, redrawing only the timer box.
-- ---------------------------------------------------------------------------

function WhoAmIScreen:_startTicks()
    self._tick_gen = (self._tick_gen or 0) + 1
    local gen = self._tick_gen
    UIManager:scheduleIn(1, function() self:_onTick(gen) end)
end

function WhoAmIScreen:_stopTicks()
    self._tick_gen = (self._tick_gen or 0) + 1
end

function WhoAmIScreen:_timerText()
    local s = math.max(0, self.time_left or 0)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

function WhoAmIScreen:_onTick(gen)
    if gen ~= self._tick_gen then return end
    self.time_left = (self.time_left or 0) - 1
    if self.phase == "ready" then
        if self.time_left <= 0 then
            return self:_beginPlay()
        end
        self:_setTimerText(tostring(self.time_left))
    elseif self.phase == "playing" then
        if self.time_left <= 0 then
            return self:onEndTurn()
        end
        self:_setTimerText(self:_timerText())
    else
        return
    end
    UIManager:scheduleIn(1, function() self:_onTick(gen) end)
end

function WhoAmIScreen:_setTimerText(text)
    if not self.timer_text then return end
    self.timer_text:setText(text)
    local box = self.timer_box
    UIManager:setDirty(self, function()
        return "fast", Geom:new{ x = box.dimen.x, y = box.dimen.y, w = box.dimen.w, h = box.dimen.h }
    end)
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

function WhoAmIScreen:onNewGame()
    self:_stopTicks()
    self:_newGame()
    self.phase = "handover"
    self:_save()
    self:_redraw("full")
end

-- Hand-over tapped: give the holder a few seconds to turn the screen away.
function WhoAmIScreen:onReady()
    if self.phase ~= "handover" then return end
    if self.game:deckSize() == 0 then
        UIManager:show(InfoMessage:new{ text = _("No cards in the chosen categories."), timeout = 3 })
        return
    end
    self.phase     = "ready"
    self.time_left = READY_SECONDS
    self:_redraw("full")
    self:_startTicks()
end

function WhoAmIScreen:_beginPlay()
    self.game:startTurn()
    self.phase     = "playing"
    self.time_left = self.duration
    self.last_action = 0
    self:_redraw("full")
    self:_startTicks()
end

-- A second tap landing right after the first (a bounce, or the holder tapping
-- twice to be sure) would skip a card nobody saw.
function WhoAmIScreen:_debounced()
    local ok, time = pcall(require, "ui/time")
    if not ok then return false end
    local now = time.now()
    if self.last_action and now - self.last_action < time.s(0.4) then return true end
    self.last_action = now
    return false
end

function WhoAmIScreen:onAnswer(found)
    if self.phase ~= "playing" or self:_debounced() then return end
    if found then self.game:found() else self.game:pass() end
    if not self.game:currentCard() then
        -- The deck is empty (tiny category): the turn ends early.
        return self:onEndTurn()
    end
    -- The card changes: a full-page "ui" refresh keeps e-ink ghosting away
    -- from the big word, the timer keeps ticking on its own.
    self:_redraw("ui")
end

-- `area`: the play area's dimen. Its middle splits Pass from Found (in
-- landscape the area is only the left part of the screen).
function WhoAmIScreen:onPlayTap(ges, area)
    if self.phase ~= "playing" or not (ges and ges.pos) then return end
    area = area or self.dimen
    local right = ges.pos.x >= area.x + area.w / 2
    self:onAnswer(right ~= self.found_left)
end

function WhoAmIScreen:onFoundKey()
    if self.phase == "playing" then self:onAnswer(true); return true end
end

function WhoAmIScreen:onPassKey()
    if self.phase == "playing" then self:onAnswer(false); return true end
end

function WhoAmIScreen:onEndTurn()
    if self.phase ~= "playing" then return end
    self:_stopTicks()
    self.summary = self.game:endTurn()
    self.phase = "summary"
    self:_save()
    self:_redraw("full")
end

function WhoAmIScreen:onNext()
    if self.phase ~= "summary" then return end
    self.phase = self.game:isOver() and "over" or "handover"
    self:_redraw("full")
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

function WhoAmIScreen:openLangMenu()
    MenuHelper.openPickerMenu{
        title      = _("Language"),
        items      = { { id = "fr", text = "Français" }, { id = "en", text = "English" } },
        current_id = self.lang,
        parent     = self,
        on_select  = function(lang)
            self.lang = lang
            self.plugin:saveSetting("lang", lang)
            self.game:setDeck(self:_deck())
            self:_redraw()
        end,
    }
end

function WhoAmIScreen:openPlayersDialog()
    local dialog
    dialog = InputDialog:new{
        title         = _("Player names (one per line)"),
        input         = table.concat(self.names, "\n"),
        allow_newline = true,
        buttons       = {
            {
                {
                    text     = _("Cancel"),
                    id       = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("OK"),
                    callback = function()
                        local names = {}
                        for line in (dialog:getInputText() .. "\n"):gmatch("(.-)\n") do
                            line = line:gsub("^%s+", ""):gsub("%s+$", "")
                            if line ~= "" and #names < Game.MAX_PLAYERS then names[#names + 1] = line end
                        end
                        UIManager:close(dialog)
                        if #names < Game.MIN_PLAYERS then
                            UIManager:show(InfoMessage:new{ text = _("At least two players are needed."), timeout = 3 })
                            return
                        end
                        self.names = names
                        self.plugin:saveSetting("players", names)
                        -- A different table of players is a different game.
                        self:onNewGame()
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function WhoAmIScreen:openRoundsMenu()
    local items = {}
    for n = 1, 5 do items[#items + 1] = { id = n, text = tostring(n) } end
    MenuHelper.openPickerMenu{
        title      = _("Rounds"),
        items      = items,
        current_id = self.rounds,
        parent     = self,
        on_select  = function(n)
            self.rounds = n
            self.plugin:saveSetting("rounds", n)
            self.game.rounds = math.max(n, self.game.round)
            self:_redraw()
        end,
    }
end

function WhoAmIScreen:openTimerMenu()
    local items = {}
    for _i, d in ipairs(DURATIONS) do items[#items + 1] = { id = d, text = T(_("%1 s"), d) } end
    MenuHelper.openPickerMenu{
        title      = _("Timer"),
        items      = items,
        current_id = self.duration,
        parent     = self,
        on_select  = function(d)
            self.duration = d
            self.plugin:saveSetting("duration", d)
            self:_redraw()
        end,
    }
end

-- Multi-select: re-opens after each toggle, like the theme picker in taboo.
function WhoAmIScreen:openCategoryMenu()
    if not self._counts or self._counts_lang ~= self.lang then
        self._counts, self._counts_lang = {}, self.lang
        for _i, id in ipairs(CATEGORY_ORDER) do
            local cards = self:_loadCategory(id)
            self._counts[id] = cards and #cards or nil
        end
        collectgarbage()
    end
    local counts = self._counts
    local all = self.selected == nil
    local items = { {
        id   = "__all__",
        text = (all and "★ " or "  ") .. _("Mix (all categories)"),
    } }
    for _i, id in ipairs(CATEGORY_ORDER) do
        if counts[id] then
            local on = all or self.selected[id]
            items[#items + 1] = {
                id   = id,
                text = (on and "✓ " or "○ ") .. categoryLabel(id) .. string.format("  (%d)", counts[id]),
            }
        end
    end
    MenuHelper.openPickerMenu{
        title     = _("Categories"),
        items     = items,
        parent    = self,
        on_select = function(id)
            if id == "__all__" then
                self.selected = nil
            elseif self.selected == nil then
                -- From "all": tapping one category keeps only that one.
                self.selected = { [id] = true }
            else
                self.selected[id] = not self.selected[id] or nil
                local n, total = 0, 0
                for _j, cid in ipairs(CATEGORY_ORDER) do
                    if counts[cid] then
                        total = total + 1
                        if self.selected[cid] then n = n + 1 end
                    end
                end
                if n == 0 or n == total then self.selected = nil end
            end
            self:_saveSelection()
            self.game:setDeck(self:_deck())
            self:_redraw()
            self:openCategoryMenu()
        end,
    }
end

function WhoAmIScreen:_categoriesText()
    if self.selected == nil then return T(_("Categories: %1"), _("Mix")) end
    local n, last = 0, nil
    for _i, id in ipairs(CATEGORY_ORDER) do
        if self.selected[id] then n = n + 1; last = id end
    end
    if n == 1 then return T(_("Categories: %1"), categoryLabel(last)) end
    return T(_("Categories: %1"), n .. "/" .. #CATEGORY_ORDER)
end

function WhoAmIScreen:onToggleSide()
    self.found_hand = self.found_hand == "right" and "left" or "right"
    self.found_left = self.found_hand == "right"
    self.plugin:saveSetting("found_hand", self.found_hand)
    self:_redraw()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function WhoAmIScreen:_titleBar()
    return self:buildTitleBar(_("Who Am I?"), function()
        local items = {
            { text = _("New game"), callback = function() self:onNewGame() end },
            { text = T(_("Language: %1"), self.lang:upper()), callback = function() self:openLangMenu() end },
            { text = T(_("Players: %1"), #self.names), callback = function() self:openPlayersDialog() end },
            { text = T(_("Rounds: %1"), self.rounds), callback = function() self:openRoundsMenu() end },
            { text = T(_("Timer: %1"), T(_("%1 s"), self.duration)), callback = function() self:openTimerMenu() end },
            { text = self:_categoriesText(), callback = function() self:openCategoryMenu() end },
            { text = T(_("Found side: %1"), self.found_hand == "right" and _("holder's right hand") or _("holder's left hand")),
              callback = function() self:onToggleSide() end },
        }
        if self.phase == "playing" then
            items[#items + 1] = { text = _("End turn"), callback = function() self:onEndTurn() end }
        end
        items[#items + 1] = self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR)
        return items
    end)
end

function WhoAmIScreen:_answerButtons()
    local pass  = { text = "✗  " .. _("Pass"),  callback = function() self:onAnswer(false) end }
    local found = { text = "✓  " .. _("Found"), callback = function() self:onAnswer(true) end }
    if self.found_left then return { found, pass } end
    return { pass, found }
end

function WhoAmIScreen:_controlRows()
    local p = self.phase
    if p == "handover" then
        return { { text = _("Ready"), callback = function() self:onReady() end } }
    elseif p == "ready" then
        return { { text = _("Cancel"), callback = function()
            self:_stopTicks(); self.phase = "handover"; self:_redraw()
        end } }
    elseif p == "playing" then
        return self:_answerButtons()
    elseif p == "summary" then
        local label
        if self.game:isOver() then
            label = _("Final scores")
        else
            label = T(_("Next player: %1"), self.game:currentPlayer().name)
        end
        return { { text = label, callback = function() self:onNext() end } }
    end
    return {}   -- over: the round-over bar (New game) takes its place
end

function WhoAmIScreen:buildLayout()
    self.timer_text, self.timer_box = nil, nil
    local title_bar = self:_titleBar()
    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar(self:_controlRows()),
    }
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local builder = self["_build_" .. self.phase] or self._build_handover
    local content = builder(self, bw, bh)

    if self:isLandscape() then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            content,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, content,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self[1] = self.layout
    self:updateStatus()
end

function WhoAmIScreen:_build_handover(bw, bh)
    local g = self.game
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    local inner = bw - 4 * Size.padding.large
    local frame_extra = 2 * (Size.padding.large + Size.border.thick)
    return Box:new{
        width = bw, height = bh,
        callback = function() self:onReady() end,
        FrameContainer:new{
            bordersize = Size.border.thick,
            padding    = Size.padding.large,
            radius     = Size.radius.window,
            CenterContainer:new{
                dimen = Geom:new{ w = bw - frame_extra, h = bh - frame_extra },
                VerticalGroup:new{
                    align = "center",
                    TextWidget:new{
                        text = T(_("Round %1/%2"), g.round, g.rounds),
                        face = pxFace(short * 0.045),
                    },
                    VerticalSpan:new{ width = vs * 2 },
                    wrapText(_("Pass the reader to"), pxFace(short * 0.05), inner),
                    VerticalSpan:new{ width = vs },
                    fitLine(g:currentPlayer().name, short * 0.13, inner, true),
                    VerticalSpan:new{ width = vs * 3 },
                    wrapText(_("Hold it facing the others, without looking. Tap when ready."),
                        pxFace(short * 0.042), inner),
                    VerticalSpan:new{ width = vs },
                    wrapText(self.found_hand == "right"
                            and _("Found: tap with your right hand. Pass: your left hand.")
                            or  _("Found: tap with your left hand. Pass: your right hand."),
                        pxFace(short * 0.042), inner, true),
                    VerticalSpan:new{ width = vs * 3 },
                    wrapText(self:joinStatus(self:_categoriesText(), T(_("Timer: %1"), T(_("%1 s"), self.duration))),
                        pxFace(short * 0.034), inner),
                },
            },
        },
    }
end

function WhoAmIScreen:_build_ready(bw, bh)
    local short = math.min(bw, bh)
    self.timer_text = TextWidget:new{ text = tostring(self.time_left or READY_SECONDS), face = pxFace(short * 0.4), bold = true }
    self.timer_box = Box:new{ width = bw, height = math.floor(short * 0.5), self.timer_text }
    return CenterContainer:new{
        dimen = Geom:new{ w = bw, h = bh },
        VerticalGroup:new{
            align = "center",
            wrapText(_("Turn the screen towards the others!"), pxFace(short * 0.055), bw),
            self.timer_box,
        },
    }
end

function WhoAmIScreen:_build_playing(bw, bh)
    local g = self.game
    local card = g:currentCard() or { word = "?", cat = "" }
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    local t = g.turn or { found = {}, passed = {} }

    self.timer_text = TextWidget:new{ text = self:_timerText(), face = pxFace(short * 0.09), bold = true }
    local timer_h = self.timer_text:getSize().h
    self.timer_box = Box:new{ width = math.floor(bw * 0.5), height = timer_h, self.timer_text }

    local top = HorizontalGroup:new{
        align = "center",
        Box:new{ width = math.floor(bw * 0.25), height = timer_h,
            TextWidget:new{ text = "✗ " .. #t.passed, face = pxFace(short * 0.05) } },
        self.timer_box,
        Box:new{ width = bw - math.floor(bw * 0.25) - math.floor(bw * 0.5), height = timer_h,
            TextWidget:new{ text = "✓ " .. #t.found, face = pxFace(short * 0.05) } },
    }
    if self.found_left then
        top[1], top[3] = top[3], top[1]
    end

    local cat = TextWidget:new{ text = categoryLabel(card.cat), face = pxFace(short * 0.045), max_width = bw }

    -- The two halves' labels, under the card. The onlookers read them, so
    -- each says which of the holder's hands it is: the holder's right hand
    -- is on the onlookers' left.
    local hint_face = pxFace(short * 0.06)
    local sub_face  = pxFace(short * 0.035)
    local half = math.floor(bw / 2)
    local function hint(found, w)
        local hand = (found == (self.found_hand == "right")) and _("holder's right hand") or _("holder's left hand")
        return VerticalGroup:new{
            align = "center",
            TextWidget:new{ text = found and ("✓ " .. _("Found")) or ("✗ " .. _("Pass")),
                face = hint_face, max_width = w, bold = true },
            TextWidget:new{ text = hand, face = sub_face, max_width = w },
        }
    end
    local left_found = self.found_left
    local hint_h = math.floor(short * 0.06 * 1.4 + short * 0.035 * 1.5)
    local hints = HorizontalGroup:new{
        align = "center",
        Box:new{ width = half, height = hint_h, hint(left_found, half) },
        LineWidget:new{ background = Blitbuffer.COLOR_DARK_GRAY,
            dimen = Geom:new{ w = Size.line.thick, h = hint_h } },
        Box:new{ width = bw - half - Size.line.thick, height = hint_h, hint(not left_found, half) },
    }

    local fixed_h = timer_h + cat:getSize().h + hints:getSize().h + 4 * vs
    local word_h  = math.max(40, bh - fixed_h)
    local word = fitCard(card.word, math.min(short * 0.22, word_h * 0.45), math.floor(bw * 0.96), word_h)

    -- The whole area is the tap target; left or right of the middle decides.
    local area
    area = Box:new{
        width = bw, height = bh,
        callback = function(ges) self:onPlayTap(ges, area.dimen) end,
        VerticalGroup:new{
            align = "center",
            top,
            VerticalSpan:new{ width = vs },
            cat,
            VerticalSpan:new{ width = vs },
            CenterContainer:new{ dimen = Geom:new{ w = bw, h = word_h }, word },
            VerticalSpan:new{ width = vs },
            hints,
        },
    }
    return area
end

-- Two columns, found | passed, in the largest font that fits.
function WhoAmIScreen:_build_summary(bw, bh)
    local s = self.summary or { player = "", found = {}, passed = {}, points = 0 }
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    local col_w = math.floor((bw - Size.padding.large) / 2)

    local head = VerticalGroup:new{
        align = "center",
        fitLine(_("Time's up!"), short * 0.06, bw, true),
        VerticalSpan:new{ width = vs },
        fitLine(T((s.points == 1 or (s.points == 0 and _.lang() == "fr")) and _("%1: %2 card found") or _("%1: %2 cards found"), s.player, s.points), short * 0.07, bw, true),
        VerticalSpan:new{ width = vs * 2 },
    }
    local avail = bh - head:getSize().h

    local function lines(list, mark)
        local out = {}
        for _i, c in ipairs(list) do
            out[#out + 1] = mark .. " " .. c.word .. (c.timeout and " ⏱" or "")
        end
        if #out == 0 then out[1] = "—" end
        return table.concat(out, "\n")
    end
    local found_txt  = lines(s.found, "✓")
    local passed_txt = lines(s.passed, "✗")

    local px = short * 0.055
    local cols
    while true do
        local face  = pxFace(px)
        local hface = pxFace(px * 0.85)
        local function column(title, body)
            return VerticalGroup:new{
                align = "center",
                TextWidget:new{ text = title, face = hface, bold = true, max_width = col_w },
                LineWidget:new{ background = Blitbuffer.COLOR_DARK_GRAY,
                    dimen = Geom:new{ w = math.floor(col_w * 0.8), h = Size.line.medium } },
                VerticalSpan:new{ width = Size.span.vertical_default },
                TextBoxWidget:new{ text = body, face = face, width = col_w, alignment = "center" },
            }
        end
        cols = HorizontalGroup:new{
            align = "top",
            column(T(_("Found (%1)"), #s.found), found_txt),
            HorizontalSpan:new{ width = Size.padding.large },
            column(T(_("Passed (%1)"), #s.passed), passed_txt),
        }
        if cols:getSize().h <= avail or px <= 14 then break end
        cols:free()
        px = px * 0.9
    end
    return CenterContainer:new{
        dimen = Geom:new{ w = bw, h = bh },
        VerticalGroup:new{ align = "center", head, cols },
    }
end

function WhoAmIScreen:_build_over(bw, bh)
    local g = self.game
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    local winners = g:winners()
    local title = #winners == 1 and T(_("%1 wins!"), winners[1])
                  or T(_("Tie: %1"), table.concat(winners, ", "))
    local rows = {}
    for i, p in ipairs(g:ranking()) do
        rows[#rows + 1] = T(_("%1. %2 — %3"), i, p.name, p.score)
    end
    local px = short * 0.06
    local list
    local head = VerticalGroup:new{
        align = "center",
        fitLine(_("Final scores"), short * 0.05, bw),
        VerticalSpan:new{ width = vs },
        fitLine(title, short * 0.09, bw, true),
        VerticalSpan:new{ width = vs * 3 },
    }
    while true do
        list = TextBoxWidget:new{ text = table.concat(rows, "\n"), face = pxFace(px), width = bw, alignment = "center" }
        if list:getSize().h <= bh - head:getSize().h or px <= 14 then break end
        list:free()
        px = px * 0.9
    end
    return CenterContainer:new{
        dimen = Geom:new{ w = bw, h = bh },
        VerticalGroup:new{ align = "center", head, list },
    }
end

-- "Alice: 3 · Bob: 5"
function WhoAmIScreen:updateStatus(msg)
    if msg then return ScreenBase.updateStatus(self, msg) end
    local parts = {}
    for _i, p in ipairs(self.game.players) do
        parts[#parts + 1] = T(_("%1: %2"), p.name, p.score)
    end
    ScreenBase.updateStatus(self, self:joinStatus((table.unpack or unpack)(parts)))
end

-- The title bar's close button calls closeScreen directly, not onClose.
function WhoAmIScreen:closeScreen()
    self:_stopTicks()
    ScreenBase.closeScreen(self)
end

return WhoAmIScreen
