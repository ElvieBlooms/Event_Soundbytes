return function(mod)
    math.randomseed(os.time())

    -- ============================================================
    -- FRAMEWORK -- options, shared state, and helper functions.
    -- everything below this block is what the event handlers at the
    -- bottom of the file actually call into.
    -- ============================================================

    -- Mods manager options - all three show up on Event Soundbytes' own
    -- page in the manager. Kept VOICE LINES and VOICE VOL separate on
    -- purpose so muting doesn't wipe out whatever volume you had it set
    -- to. Heads up: CHARACTER's value gets used as a literal folder name
    -- under assets/, so it has to match the real folder exactly, caps
    -- and all
    -- ||Telling on myself here, I spent more time on wrong case troubleshooting than I should've||.
    mod.options:define({
      { key = "voice_lines", type = "toggle", label = "VOICE LINES", default = true },
      { key = "voice_vol", type = "number", label = "VOICE VOL",
        min = 0, max = 7, step = 1, default = 7 },
      { key = "character", type = "choice", label = "CHARACTER",
        choices = {
          { "KRIS", "kris" },
          { "JESSIE", "jessie" },
        },
        default = "kris" },
    })

    local duckUntil = 0

    local function voiceVolume()
      return mod.options:get("voice_vol") or 7
    end

    -- need both the toggle on AND volume above 0 - that way muting
    -- through the toggle doesn't touch your saved volume number, but
    -- taking volume down to 0 still shuts everything off too
    local function voiceLinesOn()
      return mod.options:get("voice_lines") and voiceVolume() > 0
    end

    local function characterFolder()
      return mod.options:get("character") or "kris"
    end

    -- pcall here so a missing file (like picking a character that
    -- doesn't have assets yet) just fails quietly instead of taking the
    -- whole mod down with it
    local function playSound(path)
      if not voiceLinesOn() then return end
      local ok, src = pcall(love.audio.newSource, path, "static")
      if ok and src then
        src:setVolume(voiceVolume() / 7)
        duckUntil = love.timer.getTime() + 2.5
        src:play()
      end
    end

    local function playRandom(paths)
      playSound(paths[math.random(#paths)])
    end

    -- ducks the music for a couple seconds whenever a line plays so it
    -- doesn't get drowned out by the soundtrack
    mod.hooks:wrap("music.volume", function(next, vol, ctx)
      vol = next(vol, ctx)
      if love.timer.getTime() < duckUntil then
        return vol * 0.3
      end
      return vol
    end)

    -- rolls true `percent` percent of the time - this is what keeps the
    -- battle barks from playing on literally every hit/status proc
    local function chance(percent)
      return math.random(100) <= percent
    end

    -- shared cooldown between hit and status barks - both go through
    -- attemptBark and check against the same lastBarkAt, so they can't
    -- ever stack on top of each other no matter which one fires first
    local BARK_COOLDOWN = 5
    local lastBarkAt = -math.huge

    local function attemptBark(pool)
      local now = love.timer.getTime()
      if now - lastBarkAt < BARK_COOLDOWN then return end
      lastBarkAt = now
      playRandom(pool)
    end

    -- damage_dealt fires before the hit animation actually plays, so
    -- instead of playing the bark right away we queue it and let it go
    -- off ~1.5s later once the animation's had time to land. input.step
    -- runs every frame, so it just checks the queue each tick for
    -- anything that's ready. if a few hits land close together they all
    -- get queued but only the first one that clears the cooldown
    -- actually plays - the rest just get dropped instead of piling up.
    -- status barks don't need this since they don't have the same
    -- animation delay ||still need to test and confirm||,
    -- so they call attemptBark directly further down.
    local pendingBarks = {}
    local function scheduleBark(pool, delay)
      table.insert(pendingBarks, { at = love.timer.getTime() + delay, pool = pool })
    end

    mod.hooks:wrap("input.step", function(next, ...)
      local now = love.timer.getTime()
      for i = #pendingBarks, 1, -1 do
        if now >= pendingBarks[i].at then
          local entry = table.remove(pendingBarks, i)
          attemptBark(entry.pool)
        end
      end
      return next(...)
    end)

    -- ============================================================
    -- EVENTS -- everything from here down just wires the framework
    -- above into actual game events. grouped by what kind of moment
    -- they're tied to.
    -- ============================================================

    -- ---- Game start (New Game / Continue) ----
    -- only need to fire once per boot
    mod.events:once("intro.oak_speech.finished", function()
      local folder = characterFolder()
      playSound(mod.assets:path("assets/" .. folder .. "/new_game.ogg"))
    end)

    mod.events:once("save.loaded", function()
      local folder = characterFolder()
      playRandom({
        mod.assets:path("assets/" .. folder .. "/continue1.ogg"),
        mod.assets:path("assets/" .. folder .. "/continue2.ogg"),
        mod.assets:path("assets/" .. folder .. "/continue3.ogg"),
        mod.assets:path("assets/" .. folder .. "/continue4.ogg"),
      })
    end)

    -- ---- Battles ----
    -- these use :on instead of :once since they need to keep listening
    -- for the whole play session, not just the first time.
    mod.events:on("battle.damage_dealt", function(ev)
      if not chance(15) then return end
      local folder = characterFolder()
      scheduleBark({
        mod.assets:path("assets/" .. folder .. "/hit1.ogg"),
        mod.assets:path("assets/" .. folder .. "/hit2.ogg"),
      }, 1.5)
    end)

    mod.events:on("battle.status_inflicted", function(ev)
      if not chance(10) then return end
      local folder = characterFolder()
      attemptBark({
        mod.assets:path("assets/" .. folder .. "/status1.ogg"),
      })
    end)

    -- ---- World events ----
    -- day/night ambient lines - fires very rarely on purpose (5%), and
    -- only when the time of day actually changes, not continuously.
    -- worth knowing: Gen 1 (red/blue/yellow) has no real day/night clock
    -- built in - world.tod always reports DAY there unless some other
    -- mod adds a real clock. Gold does have one, and reports daytime as
    -- one of MORN/DAY/NITE/DARK, which is what we're matching on below.
    -- tod is also included as a loose fallback in case a different
    -- day/night mod uses different naming than Gold's
    -- || I haven't been able to test this on an actual Gold save yet||.
    mod.events:on("world.tod_changed", function(ev)
      if not chance(5) then return end
      local period = tostring(ev.daytime or ev.tod or ""):upper()
      local folder = characterFolder()
      if period == "NITE" or period == "DARK" or period:find("NIGHT") then
        playRandom({
          mod.assets:path("assets/" .. folder .. "/night1.ogg"),
          mod.assets:path("assets/" .. folder .. "/night2.ogg"),
        })
      elseif period == "MORN" or period:find("MORNING") then
        playSound(mod.assets:path("assets/" .. folder .. "/morning1.ogg"))
      end
    end)
  end
