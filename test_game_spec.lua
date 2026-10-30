local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

local Game = dofile(DIR .. "game.lua")

-- The original categories need 350+ cards, the ones added later 200+.
local CATEGORIES = {
    people = 350, characters = 350, movies = 350, animals = 350, jobs = 350,
    places = 350, monuments = 350, objects = 350, actions = 350,
    mythology = 200, heroes = 200, cartoons = 200, sports = 200, inventions = 200,
    food = 200, instruments = 200, art = 200, kids = 200,
}

local function lcg(seed)
    local s = seed
    return function(n)
        s = (s * 1103515245 + 12345) % 2147483648
        return (s % n) + 1
    end
end

local CONTENT = {
    { id = "a", cards = { "a1", "a2", "a3", "a4" } },
    { id = "b", cards = { "b1", "b2", "shared" } },
    { id = "c", cards = { "shared", "c2" } },
}

describe("whoami deck", function()
    it("keeps the selected categories and drops cross-category duplicates", function()
        local all = Game.buildDeck(CONTENT, nil)
        assert.are.equal(8, #all)
        local only_b = Game.buildDeck(CONTENT, { b = true })
        assert.are.equal(3, #only_b)
        for _, c in ipairs(only_b) do assert.are.equal("b", c.cat) end
    end)
end)

describe("whoami game", function()
    local function newGame(players, rounds)
        return Game.new{ players = players, rounds = rounds, deck = Game.buildDeck(CONTENT), rng = lcg(1) }
    end

    it("scores found cards and lists found / passed / timed-out cards", function()
        local g = newGame({ "Alice", "Bob" }, 1)
        local first = g:startTurn()
        assert.is_table(first)
        g:found(); g:pass(); g:found()
        local last = g:currentCard()
        local s = g:endTurn()
        assert.are.equal("Alice", s.player)
        assert.are.equal(2, s.points)
        assert.are.equal(2, #s.found)
        assert.are.equal(2, #s.passed)
        assert.are.equal(last.word, s.passed[2].word)
        assert.is_true(s.passed[2].timeout)
        assert.are.equal(2, g.players[1].score)
        assert.are.equal("Bob", g:currentPlayer().name)
    end)

    it("never repeats a card until the deck runs out, then reshuffles", function()
        local g = newGame({ "A", "B" }, 3)
        local seen = {}
        g:startTurn()
        for _ = 1, 7 do
            local c = g:currentCard()
            assert.is_nil(seen[c.word], "repeated " .. c.word)
            seen[c.word] = true
            g:found()
        end
        -- 8 distinct cards in the deck: the 8th is new, the 9th starts over.
        assert.is_nil(seen[g:currentCard().word])
        g:found()
        assert.is_table(g:currentCard())
    end)

    it("ends after every player has played each round", function()
        local g = newGame({ "A", "B", "C" }, 2)
        for turn = 1, 6 do
            assert.is_false(g:isOver(), "over too early at turn " .. turn)
            g:startTurn()
            if turn == 5 then g:found(); g:found() end
            local s = g:endTurn()
            assert.are.equal(turn == 6, s.game_over)
        end
        assert.is_true(g:isOver())
        assert.is_nil(g:startTurn())
        assert.are.same({ "B" }, g:winners())
        assert.are.equal("B", g:ranking()[1].name)
    end)

    it("reports ties", function()
        local g = newGame({ "A", "B" }, 1)
        g:startTurn(); g:found(); g:endTurn()
        g:startTurn(); g:found(); g:endTurn()
        assert.are.same({ "A", "B" }, g:winners())
    end)

    it("round-trips through serialize", function()
        local g = newGame({ "A", "B" }, 2)
        g:startTurn(); g:found(); g:endTurn()
        local t = g:serialize()
        local h = Game.deserialize(t, Game.buildDeck(CONTENT), lcg(2))
        assert.are.same(t, h:serialize())
        assert.are.equal("B", h:currentPlayer().name)
        assert.is_nil(Game.deserialize({ players = { { name = "solo" } } }, {}))
        assert.is_nil(Game.deserialize(nil, {}))
    end)

    it("puts already played cards at the back when the deck changes", function()
        local g = newGame({ "A", "B" }, 1)
        g:startTurn()
        local played = g:currentCard().word
        g:found()
        -- found() drew the next card, so two cards are now used: both at the back.
        g:setDeck(Game.buildDeck(CONTENT))
        local back = { g.deck[#g.deck].word, g.deck[#g.deck - 1].word }
        assert.is_true(back[1] == played or back[2] == played)
    end)
end)

-- Names the content must never contain (see the content rules in README).
local EXCLUDED = {
    "hitler", "staline", "stalin", "pol pot", "ben laden", "bin laden", "mussolini", "mao zedong",
    "mao tsé", "pinochet", "idi amin", "saddam", "kadhafi", "gaddafi", "lénine", "lenin",
    "robespierre", "attila", "gengis", "genghis", "goebbels", "himmler", "al capone", "escobar", "caligula", "néron",
    "jack l'éventreur", "jack the ripper", "landru", "ted bundy",
}

describe("whoami content", function()
    for _, lang in ipairs({ "en", "fr" }) do
        it(lang .. ": every category, enough distinct cards, nothing excluded", function()
            for id, min in pairs(CATEGORIES) do
                local ok, list = pcall(dofile, DIR .. "cards/" .. lang .. "/" .. id .. ".lua")
                local cat = ok and { cards = list } or nil
                assert.is_table(cat, lang .. " is missing " .. id)
                assert.is_true(#cat.cards >= min, lang .. "/" .. id .. ": only " .. #cat.cards)
                local seen = {}
                for _, w in ipairs(cat.cards) do
                    assert.is_string(w)
                    assert.is_nil(seen[w:lower()], lang .. "/" .. id .. " duplicate: " .. w)
                    seen[w:lower()] = true
                    local low = w:lower()
                    for _, bad in ipairs(EXCLUDED) do
                        assert.is_nil(low:find(bad, 1, true), lang .. " excluded name: " .. w)
                    end
                end
            end
        end)
    end
end)
