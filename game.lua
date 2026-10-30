-- ---------------------------------------------------------------------------
-- Who Am I? -- game logic (pure Lua, no UI, so the specs can drive it)
--
-- Players take turns holding the reader facing the others. During a timed
-- turn the others give clues; each card is either found (+1) or passed (0).
-- After every player has had `rounds` turns, the game is over.
-- Cards come from a deck built from the chosen categories, never repeated in
-- a game until the deck runs out (then it is reshuffled).
-- ---------------------------------------------------------------------------

local Game = {}
Game.__index = Game

Game.MIN_PLAYERS = 2
Game.MAX_PLAYERS = 12

-- content: { { id = "animals", cards = { "Lion", ... } }, ... }
-- selected: nil = every category, else { [id] = true, ... }
-- Returns a flat list of { word = ..., cat = id }.
function Game.buildDeck(content, selected)
    local deck, seen = {}, {}
    for _, cat in ipairs(content or {}) do
        if selected == nil or selected[cat.id] then
            for _, w in ipairs(cat.cards or {}) do
                -- The same name can sit in two categories (a monument that is
                -- also a city); the deck keeps one.
                if not seen[w] then
                    seen[w] = true
                    deck[#deck + 1] = { word = w, cat = cat.id }
                end
            end
        end
    end
    return deck
end

local function shuffle(t, rng)
    for i = #t, 2, -1 do
        local j = rng(i)
        t[i], t[j] = t[j], t[i]
    end
end

-- opts: players = { "Alice", "Bob" }, rounds = 2, deck = buildDeck(...),
--       used = { [word] = true } (restored game), rng = function(n)
function Game.new(opts)
    local self = setmetatable({}, Game)
    self.rng     = opts.rng or math.random
    self.rounds  = math.max(1, opts.rounds or 1)
    self.players = {}
    for i, p in ipairs(opts.players or {}) do
        if type(p) == "table" then
            self.players[i] = { name = p.name, score = p.score or 0 }
        else
            self.players[i] = { name = p, score = 0 }
        end
    end
    self.round    = opts.round or 1
    self.current  = opts.current or 1
    self.finished = opts.finished or false
    self.used     = {}
    for w in pairs(opts.used or {}) do self.used[w] = true end
    self.history  = {}    -- one entry per finished turn
    self:setDeck(opts.deck or {})
    self.turn = nil
    return self
end

-- Replace the deck (new categories, new language). Cards already played this
-- game go to the back, so they only come back once everything else has.
function Game:setDeck(deck)
    local fresh, old = {}, {}
    for _, c in ipairs(deck) do
        if self.used[c.word] then old[#old + 1] = c else fresh[#fresh + 1] = c end
    end
    shuffle(fresh, self.rng)
    shuffle(old, self.rng)
    for _, c in ipairs(old) do fresh[#fresh + 1] = c end
    self.deck = fresh
    self.pos  = 1
end

function Game:deckSize()
    return #self.deck
end

function Game:currentPlayer()
    return self.players[self.current]
end

function Game:isOver()
    return self.finished
end

function Game:startTurn()
    if self.finished then return nil end
    self.turn = { found = {}, passed = {}, card = nil }
    return self:_draw()
end

function Game:_draw()
    if #self.deck == 0 then
        self.turn.card = nil
        return nil
    end
    if self.pos > #self.deck then
        -- Everything has been played: start over with a fresh shuffle.
        self.used = {}
        shuffle(self.deck, self.rng)
        self.pos = 1
    end
    local c = self.deck[self.pos]
    self.pos = self.pos + 1
    self.used[c.word] = true
    self.turn.card = c
    return c
end

function Game:currentCard()
    return self.turn and self.turn.card
end

function Game:found()
    local t = self.turn
    if not (t and t.card) then return nil end
    t.found[#t.found + 1] = t.card
    return self:_draw()
end

function Game:pass()
    local t = self.turn
    if not (t and t.card) then return nil end
    t.passed[#t.passed + 1] = t.card
    return self:_draw()
end

-- End the current turn (time's up or stopped). The card still on screen goes
-- to the passed list, flagged, so the holder sees it in the summary.
-- Returns the summary { player, found, passed, points, last_round }.
function Game:endTurn()
    local t = self.turn
    if not t then return nil end
    if t.card then
        t.passed[#t.passed + 1] = { word = t.card.word, cat = t.card.cat, timeout = true }
        t.card = nil
    end
    local p = self.players[self.current]
    p.score = p.score + #t.found
    local summary = {
        player = p.name,
        found  = t.found,
        passed = t.passed,
        points = #t.found,
    }
    self.history[#self.history + 1] = summary
    self.turn = nil
    self.current = self.current + 1
    if self.current > #self.players then
        self.current = 1
        self.round   = self.round + 1
        if self.round > self.rounds then
            self.round    = self.rounds
            self.finished = true
        end
    end
    summary.game_over = self.finished
    return summary
end

-- Players sorted by score (stable on ties: seating order).
function Game:ranking()
    local list = {}
    for i, p in ipairs(self.players) do list[i] = { name = p.name, score = p.score, seat = i } end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.seat < b.seat
    end)
    return list
end

-- Names of everyone sharing the top score.
function Game:winners()
    local r = self:ranking()
    local out = {}
    for _, p in ipairs(r) do
        if p.score == r[1].score then out[#out + 1] = p.name end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Persistence. The deck itself isn't saved (it is rebuilt from the content
-- files); the words already played are, so a restored game doesn't repeat
-- them. A turn in progress is dropped: the player starts it again.
-- ---------------------------------------------------------------------------

function Game:serialize()
    local players, used = {}, {}
    for i, p in ipairs(self.players) do players[i] = { name = p.name, score = p.score } end
    for w in pairs(self.used) do used[#used + 1] = w end
    table.sort(used)
    return {
        players  = players,
        rounds   = self.rounds,
        round    = self.round,
        current  = self.current,
        finished = self.finished,
        used     = used,
    }
end

function Game.deserialize(t, deck, rng)
    if type(t) ~= "table" or type(t.players) ~= "table" or #t.players < Game.MIN_PLAYERS then
        return nil
    end
    local used = {}
    for _, w in ipairs(t.used or {}) do used[w] = true end
    local players = {}
    for i, p in ipairs(t.players) do
        if type(p) ~= "table" or type(p.name) ~= "string" then return nil end
        players[i] = { name = p.name, score = tonumber(p.score) or 0 }
    end
    local g = Game.new{
        players  = players,
        rounds   = tonumber(t.rounds) or 1,
        round    = tonumber(t.round) or 1,
        current  = tonumber(t.current) or 1,
        finished = t.finished and true or false,
        used     = used,
        deck     = deck,
        rng      = rng,
    }
    if g.current > #g.players then g.current = 1 end
    return g
end

return Game
