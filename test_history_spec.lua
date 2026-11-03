-- Cards played in one game do not come back in the next game (or the next
-- evening) until the rest of the deck has been played (game.lua +
-- game-common seen_history).
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. DIR .. "common/?.lua;" .. package.path

local Game = dofile(DIR .. "game.lua")

local function fakePlugin()
    local store = {}
    return {
        store = store,
        getSetting  = function(_self, k, d) if store[k] == nil then return d end return store[k] end,
        saveSetting = function(_self, k, v) store[k] = v end,
    }
end

local function category(lang, id)
    return { { id = id, cards = dofile(DIR .. "cards/" .. lang .. "/" .. id .. ".lua") } }
end

-- One evening: the history reopened from the settings, a new game, `n` cards.
local function session(plugin, lang, content, n)
    local g = Game.new{ players = { "A", "B" }, deck = Game.buildDeck(content),
                        seen = Game.openHistory(plugin, lang) }
    g:startTurn()
    local out = { g:currentCard().word }
    for _i = 2, n do out[#out + 1] = g:found().word end
    return out
end

describe("who am I history across sessions", function()
    it("plays a whole category over several evenings before any repeat", function()
        local p = fakePlugin()
        local content = category("en", "sports")
        local total = #Game.buildDeck(content)
        local got, n = {}, 0
        while n + 40 <= total do
            for _i, w in ipairs(session(p, "en", content, 40)) do
                assert.is_nil(got[w], "repeated: " .. w)
                got[w] = true
                n = n + 1
            end
        end
        session(p, "en", content, total - n)
        -- Everything seen: the next game starts a new cycle.
        assert.equals(10, #session(p, "en", content, 10))
    end)

    it("restored games keep the history", function()
        local p = fakePlugin()
        local content = category("fr", "food")
        local first = {}
        for _i, w in ipairs(session(p, "fr", content, 30)) do first[w] = true end
        local seen = Game.openHistory(p, "fr")
        local g = Game.deserialize({ players = { { name = "A" }, { name = "B" } } },
            Game.buildDeck(content), nil, seen)
        g:startTurn()
        assert.is_nil(first[g:currentCard().word])
    end)

    it("keeps one history per language, every category in full", function()
        local p = fakePlugin()
        session(p, "fr", category("fr", "kids"), 5)
        assert.equals(5, #p.store.seen_cards_fr)
        assert.is_nil(p.store.seen_cards_en)
        for _i, lang in ipairs({ "en", "fr" }) do
            for f in io.popen('ls "' .. DIR .. 'cards/' .. lang .. '"'):lines() do
                local id = f:gsub("%.lua$", "")
                assert.is_true(Game.HISTORY_MAX >= #Game.buildDeck(category(lang, id)), id)
            end
        end
    end)

    it("plays without a history as before", function()
        local g = Game.new{ players = { "A", "B" }, deck = Game.buildDeck(category("en", "art")) }
        g:startTurn()
        assert.is_string(g:currentCard().word)
    end)
end)
