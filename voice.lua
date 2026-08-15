local voice = {}

function voice.init(mod)
    math.randomseed(os.time())

    -- ================================================================
    -- FRAMEWORK -- options, shared state, and helper functions.
    -- everything below this block is what the event handlers further
    -- down the file actually call into. nothing in here fires on its
    -- own; it's all just setup for the EVENTS section.
    -- ================================================================

    -- ---- Mods manager options ----
    -- every row below shows up on Trainer Talk's own page in the
    -- manager. grouped here in the order they're described:
    --   1. global controls (mute, volume, ducking, which voice pack)
    --   2. per-category on/off + frequency controls
    -- ||Telling on myself here, I spent more time on this than I should've||.
    mod.options:define({
      -- global controls
      { key = "voice_lines", type = "toggle", label = "VOICE LINES", default = true },
      { key = "voice_vol", type = "number", label = "VOICE VOL",
        min = 0, max = 7, step = 1, default = 7 },
      -- 0 doubles as "no ducking" -- see duckSeconds() below, no special
      -- case needed since a 0-second window just closes immediately
      { key = "duck_seconds", type = "number", label = "DUCK TIME",
        min = 0, max = 5, step = 0.5, default = 2.5 },
      { key = "character", type = "choice", label = "CHARACTER",
        choices = {
          { "KRIS", "kris" },
          { "JESSIE", "jessie" },
        },
        default = "kris" },
      -- separate from CHARACTER on purpose -- a stadium announcer isn't
      -- really a "character" the way Kris/Jessie are (no New Game line,
      -- no hit barks, just the big outcome moments), so it gets its own
      -- pack instead of living inside assets/kris/ or assets/jessie/.
      -- "match" is the default so nobody's affected unless they
      -- deliberately pick something else -- see milestoneFolder() below.
      -- only wired into GYM BADGES / ELITE FOUR / CHAMPION; the ordinary
      -- battle-win/loss line under MOMENTS still follows CHARACTER.
      { key = "milestone_voice", type = "choice", label = "MILESTONE VOICE",
        choices = {
          { "MATCH CHARACTER", "match" },
          { "STADIUM ANNOUNCER", "stadium" },
        },
        default = "match" },

      -- per-category controls. VOICE LINES/VOICE VOL above still gate
      -- everything regardless of these; these just let someone turn off
      -- (or turn up/down) one kind of line without losing the others.
      -- to add a new category down the road: add a row here, then gate
      -- that category's event handler(s) the same way the others do.
      { key = "cat_game_start", type = "toggle", label = "GAME START", default = true },
      -- BATTLE BARKS and DAY/NIGHT used to be plain toggles. since both
      -- are already chance()-gated, OFF and "0% chance" are the same
      -- thing -- so instead of a toggle AND a separate frequency
      -- control, one choice row does both jobs. the stored value is a
      -- MULTIPLIER applied to that event's own baseline chance (see
      -- frequencyMultiplier() below), not a raw percent -- that way
      -- BATTLE STATUS stays rarer than BATTLE HITS at every tier
      -- instead of the two becoming identical.
      { key = "freq_battle_barks", type = "choice", label = "BATTLE BARKS",
        choices = {
          { "OFF", 0 },
          { "RARE", 0.5 },
          { "NORMAL", 1 },
          { "FREQUENT", 2 },
        },
        default = 1 },
      { key = "freq_day_night", type = "choice", label = "DAY/NIGHT",
        choices = {
          { "OFF", 0 },
          { "RARE", 0.5 },
          { "NORMAL", 1 },
          { "FREQUENT", 2 },
        },
        default = 1 },
      -- REACTIONS/MOMENTS gate commented-out sections further down --
      -- the rows are live now so the toggle exists and is ready the
      -- moment real assets replace the filler names and the code gets
      -- uncommented.
      { key = "cat_reactions", type = "toggle", label = "REACTIONS", default = true },
      { key = "cat_moments", type = "toggle", label = "MOMENTS", default = true },
      -- split out from MOMENTS since these three are chunky enough (and
      -- personal enough, individual trainer lines rather than shared
      -- filler) to deserve their own on/off switches.
      { key = "cat_gym_badges", type = "toggle", label = "GYM BADGES", default = true },
      { key = "cat_elite_four", type = "toggle", label = "ELITE FOUR", default = true },
      { key = "cat_champion", type = "toggle", label = "CHAMPION", default = true },
    })

    -- ---- Playback core ----
    -- everything a line actually plays through, regardless of which
    -- category triggered it.
    local duckUntil = 0

    local function voiceVolume()
      return mod.options:get("voice_vol") or 7
    end

    local function duckSeconds()
      return mod.options:get("duck_seconds") or 2.5
    end

    -- need both the toggle on AND volume above 0 - that way muting
    -- through the toggle doesn't touch your saved volume number, but
    -- dragging volume down to 0 still shuts everything off too
    local function voiceLinesOn()
      return mod.options:get("voice_lines") and voiceVolume() > 0
    end

    local function characterFolder()
      return mod.options:get("character") or "kris"
    end

    -- "match" falls through to whatever CHARACTER is set to; anything
    -- else (e.g. "stadium") is its own folder, independent of CHARACTER
    local function milestoneFolder()
      local choice = mod.options:get("milestone_voice") or "match"
      if choice == "match" then return characterFolder() end
      return choice
    end

    -- pcall here so a missing file (like picking a character that
    -- doesn't have assets yet) just fails quietly instead of taking the
    -- whole mod down with it
    local function playSound(path)
      if not voiceLinesOn() then return end
      local ok, src = pcall(love.audio.newSource, path, "static")
      if ok and src then
        src:setVolume(voiceVolume() / 7)
        duckUntil = love.timer.getTime() + duckSeconds()
        src:play()
      end
    end

    local function playRandom(paths)
      playSound(paths[math.random(#paths)])
    end

    -- ---- Music ducking ----
    -- scales the music down for a configurable window whenever a line
    -- plays, so it doesn't get drowned out by the soundtrack
    mod.hooks:wrap("music.volume", function(next, vol, ctx)
      vol = next(vol, ctx)
      if love.timer.getTime() < duckUntil then
        return vol * 0.3
      end
      return vol
    end)

    -- ---- Frequency & chance ----
    -- rolls true `percent` percent of the time - this is what keeps the
    -- battle barks from playing on literally every hit/status proc
    local function chance(percent)
      return math.random(100) <= percent
    end

    -- reads a freq_* choice row -- see the options block above for why
    -- this is a multiplier and not a raw percent
    local function frequencyMultiplier(key)
      return mod.options:get(key) or 1
    end

    -- ---- Bark cooldown & delay queue ----
    -- shared cooldown between hit and status barks - both go through
    -- attemptBark and check against the same lastBarkAt, so they can't
    -- ever stack on top of each other no matter which one fires first
    local BARK_COOLDOWN = 6
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

    -- ================================================================
    -- EVENTS -- everything from here down just wires the framework
    -- above into actual game events. grouped by what kind of moment
    -- they're tied to. LIVE sections first, then everything still
    -- commented out pending real assets.
    -- ================================================================

    -- ---- Game start (New Game / Continue) [LIVE] ----
    -- only need to fire once per boot
    mod.events:once("intro.oak_speech.finished", function()
      if not mod.options:get("cat_game_start") then return end
      local folder = characterFolder()
      playSound(mod.assets:path("assets/" .. folder .. "/new_game.ogg"))
    end)

    mod.events:once("save.loaded", function()
      if not mod.options:get("cat_game_start") then return end
      local folder = characterFolder()
      playRandom({
        mod.assets:path("assets/" .. folder .. "/continue1.ogg"),
        mod.assets:path("assets/" .. folder .. "/continue2.ogg"),
        mod.assets:path("assets/" .. folder .. "/continue3.ogg"),
        mod.assets:path("assets/" .. folder .. "/continue4.ogg"),
      })
    end)

    -- ---- Battle barks (hit / status) [LIVE] ----
    -- these use :on instead of :once since they need to keep listening
    -- for the whole play session, not just the first time.
    mod.events:on("battle.damage_dealt", function(ev)
      if not chance(15 * frequencyMultiplier("freq_battle_barks")) then return end
      local folder = characterFolder()
      scheduleBark({
        mod.assets:path("assets/" .. folder .. "/hit1.ogg"),
        mod.assets:path("assets/" .. folder .. "/hit2.ogg"),
      }, 1.5)
    end)

    mod.events:on("battle.status_inflicted", function(ev)
      if not chance(10 * frequencyMultiplier("freq_battle_barks")) then return end
      local folder = characterFolder()
      attemptBark({
        mod.assets:path("assets/" .. folder .. "/status1.ogg"),
      })
    end)

    -- ---- Day/Night ambient lines [LIVE] ----
    -- fires very rarely on purpose, and only when the time of day
    -- actually changes, not continuously.
    -- worth knowing: Gen 1 (red/blue/yellow) has no real day/night clock
    -- built in - world.tod always reports DAY there unless some other
    -- mod adds a real clock. Gold does have one, and reports daytime as
    -- one of MORN/DAY/NITE/DARK, which is what we're matching on below.
    -- tod is also included as a loose fallback in case a different
    -- day/night mod uses different naming than Gold's
    -- || I haven't been able to test this on an actual Gold save yet||.
    mod.events:on("world.tod_changed", function(ev)
      if not chance(5 * frequencyMultiplier("freq_day_night")) then return end
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

    -- ---- Reactions [NOT YET ACTIVE] ----
    -- -- smaller, wordless emotive sounds tied to battle nuance -- crits,
    -- -- misses, catch attempts, escapes, faints. gated by cat_reactions.
    -- -- filenames below are filler; swap in real assets and uncomment a
    -- -- block when it's ready. left commented rather than deleted so the
    -- -- wiring/asset names are easy to reference later.

    -- -- crit laugh: battle.damage_dealt already carries a crit flag, so
    -- -- this reuses the event rather than needing the battle.crit hook.
    -- mod.events:on("battle.damage_dealt", function(ev)
    --   if not mod.options:get("cat_reactions") then return end
    --   if not ev.crit then return end
    --   if not chance(50) then return end
    --   local folder = characterFolder()
    --   attemptBark({ mod.assets:path("assets/" .. folder .. "/hit_crit.ogg") })
    -- end)

    -- -- missed move grunt: battle.accuracy is a HOOK, not an event -- no
    -- -- event fires on a miss at all, so this is the only way to catch
    -- -- one. hooks must call next() exactly once and return the same
    -- -- shape vanilla expects; the sound is just a side effect riding
    -- -- along on that.
    -- mod.hooks:wrap("battle.accuracy", function(next, ctx)
    --   local hit = next(ctx)
    --   if not hit and mod.options:get("cat_reactions") and chance(20) then
    --     local folder = characterFolder()
    --     attemptBark({ mod.assets:path("assets/" .. folder .. "/move_miss.ogg") })
    --   end
    --   return hit
    -- end)

    -- -- failed catch sigh: same deal -- pokemon.caught (the event) only
    -- -- fires on success, so catch.rate (the hook) is the only way to
    -- -- react to a throw that didn't land.
    -- mod.hooks:wrap("catch.rate", function(next, ball, mon, def, opts)
    --   local caught, shakes = next(ball, mon, def, opts)
    --   if not caught and mod.options:get("cat_reactions") and chance(25) then
    --     local folder = characterFolder()
    --     attemptBark({ mod.assets:path("assets/" .. folder .. "/catch_fail.ogg") })
    --   end
    --   return caught, shakes
    -- end)

    -- -- escape reaction: battle.run returns true on a successful escape,
    -- -- so both outcomes are available from the same hook.
    -- mod.hooks:wrap("battle.run", function(next, ctx)
    --   local escaped = next(ctx)
    --   if mod.options:get("cat_reactions") and chance(25) then
    --     local folder = characterFolder()
    --     if escaped then
    --       attemptBark({ mod.assets:path("assets/" .. folder .. "/run_success.ogg") })
    --     else
    --       attemptBark({ mod.assets:path("assets/" .. folder .. "/run_fail.ogg") })
    --     end
    --   end
    --   return escaped
    -- end)

    -- -- faint reactions: same event, opposite sides. NOTE -- battler.isPlayer
    -- -- is assumed to match the pattern used elsewhere in the hook docs
    -- -- (see the battle.damage hook example); worth confirming this is
    -- -- the real field before uncommenting.
    -- mod.events:on("battle.fainted", function(ev)
    --   if not mod.options:get("cat_reactions") then return end
    --   local folder = characterFolder()
    --   if ev.battler and ev.battler.isPlayer then
    --     attemptBark({ mod.assets:path("assets/" .. folder .. "/faint_player.ogg") })
    --   else
    --     attemptBark({ mod.assets:path("assets/" .. folder .. "/faint_enemy.ogg") })
    --   end
    -- end)

    -- ---- Moments [NOT YET ACTIVE] ----
    -- -- bigger, rarer milestones -- evolving, a first-time catch, and
    -- -- blacking out. these don't need chance-gating the way REACTIONS
    -- -- does, since the events themselves are already rare. gated by
    -- -- cat_moments. (ordinary trainer win/loss also lives under this
    -- -- toggle, but the handler for it sits with GYM BADGES/ELITE FOUR
    -- -- below since it's the same battle.ended listener.)

    -- mod.events:on("pokemon.evolved", function(ev)
    --   if not mod.options:get("cat_moments") then return end
    --   local folder = characterFolder()
    --   playSound(mod.assets:path("assets/" .. folder .. "/evolved.ogg"))
    -- end)

    -- mod.events:on("pokemon.caught", function(ev)
    --   if not mod.options:get("cat_moments") then return end
    --   if not ev.isNew then return end
    --   local folder = characterFolder()
    --   playSound(mod.assets:path("assets/" .. folder .. "/new_catch.ogg"))
    -- end)

    -- mod.events:on("world.blacked_out", function(ev)
    --   if not mod.options:get("cat_moments") then return end
    --   local folder = characterFolder()
    --   playSound(mod.assets:path("assets/" .. folder .. "/blackout.ogg"))
    -- end)

    -- ---- Gym Badges & Elite Four [NOT YET ACTIVE] ----
    -- -- an encounter wrapped on both ends: an intro line when the
    -- -- trainer engages, and an outcome line when the battle ends in a
    -- -- win. gated separately (cat_gym_badges / cat_elite_four) from
    -- -- the rest of MOMENTS since these are chunkier, more personal
    -- -- categories -- individual trainer lines rather than shared
    -- -- filler.

    -- -- gym leader / Elite Four class IDs, matching data/scripts/victories.lua
    -- -- keys exactly (confirmed against real engine source, not guessed).
    -- -- one file per trainer rather than a shared line, so e.g. Misty can
    -- -- have her own "congrats" line distinct from Brock's.
    -- local GYM_LEADERS = {
    --   OPP_BROCK = "gym_brock",
    --   OPP_MISTY = "gym_misty",
    --   OPP_LT_SURGE = "gym_surge",
    --   OPP_ERIKA = "gym_erika",
    --   OPP_KOGA = "gym_koga",
    --   OPP_SABRINA = "gym_sabrina",
    --   OPP_BLAINE = "gym_blaine",
    --   OPP_GIOVANNI = "gym_giovanni",
    -- }
    -- local ELITE_FOUR = {
    --   OPP_LORELEI = "e4_lorelei",
    --   OPP_BRUNO = "e4_bruno",
    --   OPP_AGATHA = "e4_agatha",
    --   OPP_LANCE = "e4_lance",
    -- }

    -- -- world.trainer_engaged fires right as a battle is challenged and
    -- -- carries the same trainerClass id used above -- remembered here so
    -- -- battle.ended (below) knows who was just fought, AND used right
    -- -- here to play a "here we go" intro line, so the encounter is
    -- -- wrapped on both ends (intro on engage, outcome on win). intro
    -- -- is one shared line per category rather than per-trainer, to
    -- -- keep the asset list from doubling -- swap in per-trainer intro
    -- -- filenames later the same way GYM_LEADERS/ELITE_FOUR already work
    -- -- for the win lines, if that's wanted.
    -- -- NOTE -- Champion doesn't have a confirmed engage-time trainerClass
    -- -- the way gym/E4 do (only the post-battle HallOfFame signal is
    -- -- confirmed), so there's no Champion intro here yet.
    -- local pendingTrainerClass = nil
    -- mod.events:on("world.trainer_engaged", function(ev)
    --   pendingTrainerClass = ev.trainerClass
    --   local folder = milestoneFolder()
    --   if GYM_LEADERS[ev.trainerClass] and mod.options:get("cat_gym_badges") then
    --     playSound(mod.assets:path("assets/" .. folder .. "/gym_intro.ogg"))
    --   elseif ELITE_FOUR[ev.trainerClass] and mod.options:get("cat_elite_four") then
    --     playSound(mod.assets:path("assets/" .. folder .. "/e4_intro.ogg"))
    --   end
    -- end)

    -- -- also handles the ordinary trainer win/loss fallback (cat_moments)
    -- -- since it's the same battle.ended listener as gym/E4.
    -- mod.events:on("battle.ended", function(ev)
    --   local trainerClass = pendingTrainerClass
    --   pendingTrainerClass = nil
    --   -- NOTE -- confirm the exact win/loss values in ev.result before
    --   -- uncommenting; the reference doc only confirms "caught"/"run"/
    --   -- "skipped" explicitly, so "won"/"lost" here are a best guess.
    --   if ev.result == "won" then
    --     local gymFile = GYM_LEADERS[trainerClass]
    --     local e4File = ELITE_FOUR[trainerClass]
    --     if gymFile then
    --       if not mod.options:get("cat_gym_badges") then return end
    --       local folder = milestoneFolder()
    --       playSound(mod.assets:path("assets/" .. folder .. "/" .. gymFile .. ".ogg"))
    --     elseif e4File then
    --       if not mod.options:get("cat_elite_four") then return end
    --       local folder = milestoneFolder()
    --       playSound(mod.assets:path("assets/" .. folder .. "/" .. e4File .. ".ogg"))
    --     else
    --       if not mod.options:get("cat_moments") then return end
    --       local folder = characterFolder()
    --       playSound(mod.assets:path("assets/" .. folder .. "/battle_win.ogg"))
    --     end
    --   elseif ev.result == "lost" then
    --     if not mod.options:get("cat_moments") then return end
    --     local folder = characterFolder()
    --     playSound(mod.assets:path("assets/" .. folder .. "/battle_loss.ogg"))
    --   end
    -- end)

    -- ---- Champion [NOT YET ACTIVE] ----
    -- -- Champion victory / Hall of Fame induction -- confirmed via source
    -- -- (not a guess like the win/loss values above): beating the
    -- -- Champion runs Commands.record_hall_of_fame, which does
    -- -- Screens.push(game, "HallOfFame", ...); Screens.build() stamps
    -- -- inst.screenId = "HallOfFame" on the pushed state, and
    -- -- StateStack:push emits screen.pushed with that same state right
    -- -- after. checking ev.state.screenId is the real, reliable signal.
    -- -- no confirmed engage-time signal exists for Champion (see the
    -- -- NOTE above GYM BADGES & ELITE FOUR), so this is outcome-only.
    -- mod.events:on("screen.pushed", function(ev)
    --   if not mod.options:get("cat_champion") then return end
    --   if not (ev.state and ev.state.screenId == "HallOfFame") then return end
    --   local folder = milestoneFolder()
    --   playSound(mod.assets:path("assets/" .. folder .. "/champion.ogg"))
    -- end)

end

return voice
