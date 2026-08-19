local voice = {}

function voice.init(mod)
    math.randomseed(os.time())

    -- ================================================================
    -- FRAMEWORK -- settings, shared state, and the helpers everything
    -- below actually calls into. Nothing in here fires on its own.
    -- ================================================================

    -- ---- Voice pack discovery ----
    -- Scans assets/characters/ and assets/milestones/ for subfolders
    -- and builds CHARACTER/MILESTONE VOICE's choices from whatever's
    -- actually there -- same trick Crystal's kris.lua uses for its
    -- sprite picker. Drop a folder in with an optional meta.json
    -- ({ "label": "..." }) and it just shows up, no code changes.
    local Json = require("src.link.Json")

    local function readPackMeta(dir, key)
      local metaPath = dir .. "/" .. key .. "/meta.json"
      local ok1, info = pcall(function() return mod.assets:info(metaPath) end)
      if ok1 and info then
        local ok2, decoded = pcall(function() return Json.decode(mod:read(metaPath)) end)
        if ok2 and type(decoded) == "table" then return decoded end
      end
      return {}
    end

    -- Falls back to one hardcoded choice if the scan finds nothing --
    -- a settings row should never end up with zero options.
    local function discoverPacks(dir, preferredDefault, fallbackLabel)
      local found = {}
      local ok, list = pcall(function() return mod.assets:list(dir) end)
      if ok and list then
        for _, key in ipairs(list) do
          local ok2, info = pcall(function() return mod.assets:info(dir .. "/" .. key) end)
          if ok2 and info and info.type == "directory" then
            local meta = readPackMeta(dir, key)
            local label = meta.label or key:upper()
            table.insert(found, { label = label, key = key })
          end
        end
      end
      if #found == 0 then
        table.insert(found, { label = fallbackLabel, key = preferredDefault })
      end
      table.sort(found, function(a, b) return a.label < b.label end)
      local choicePairs = {}
      local defaultKey, sawPreferred = found[1].key, false
      for _, entry in ipairs(found) do
        table.insert(choicePairs, { entry.label, entry.key })
        if entry.key == preferredDefault then sawPreferred = true end
      end
      if sawPreferred then defaultKey = preferredDefault end
      return choicePairs, defaultKey
    end

    local characterChoices, characterDefault =
      discoverPacks("assets/characters", "kris", "KRIS")
    local milestoneChoices, milestoneDefault =
      discoverPacks("assets/milestones", "leaders", "GYM LEADER VOICES")

    mod.options:define({
      -- global controls
      { key = "voice_lines", type = "toggle", label = "VOICE LINES", default = true },
      { key = "voice_vol", type = "number", label = "VOICE VOL",
        min = 0, max = 7, step = 1, default = 7 },
      -- 0 also means "no ducking" -- see duckSeconds() below
      { key = "duck_seconds", type = "number", label = "DUCK TIME",
        min = 0, max = 5, step = 0.5, default = 2.5 },
      { key = "character", type = "choice", label = "CHARACTER",
        choices = characterChoices,
        default = characterDefault },
      -- Independent of CHARACTER -- who voices gym/E4/Champion wins,
      -- not who's escorting the player everywhere else.
      { key = "milestone_voice", type = "choice", label = "MILESTONE VOICE",
        choices = milestoneChoices,
        default = milestoneDefault },

      -- per-category on/off. VOICE LINES/VOICE VOL above still gate
      -- everything regardless of these.
      { key = "cat_game_start", type = "toggle", label = "GAME START", default = true },
      -- OFF here is just a 0x multiplier, so this one row covers both
      -- on/off and frequency. A multiplier (not a raw percent) so
      -- BATTLE STATUS stays rarer than BATTLE HITS at every tier.
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
      -- same multiplier shape as BATTLE BARKS/DAY-NIGHT above -- each
      -- reaction (hit_crit, move_miss, catch_fail, run_success/fail)
      -- keeps its own base percentage, scaled by this.
      { key = "freq_reactions", type = "choice", label = "REACTIONS",
        choices = {
          { "OFF", 0 },
          { "RARE", 0.5 },
          { "NORMAL", 1 },
          { "FREQUENT", 2 },
        },
        default = 1 },
      -- a different shape on purpose -- faints are a bigger moment
      -- than a miss or a failed catch, so this starts at guaranteed
      -- and steps down, rather than starting at a baseline and
      -- multiplying up/down the way the dial above does. Stores the
      -- actual percent directly, not a multiplier.
      { key = "freq_faint", type = "choice", label = "FAINT REACTIONS",
        choices = {
          { "OFF", 0 },
          { "SOMETIMES", 30 },
          { "OFTEN", 60 },
          { "ALWAYS", 100 },
        },
        default = 100 },
      { key = "cat_moments", type = "toggle", label = "MOMENTS", default = true },
      { key = "cat_gym_badges", type = "toggle", label = "GYM BADGES", default = true },
      { key = "cat_elite_four", type = "toggle", label = "ELITE FOUR", default = true },
      { key = "cat_champion", type = "toggle", label = "CHAMPION", default = true },
    })

    -- ---- Playback core ----
    local duckUntil = 0

    local function voiceVolume()
      return mod.options:get("voice_vol") or 7
    end

    local function duckSeconds()
      return mod.options:get("duck_seconds") or 2.5
    end

    -- Both the toggle AND volume>0 have to hold, so muting never
    -- clobbers your saved volume number.
    local function voiceLinesOn()
      return mod.options:get("voice_lines") and voiceVolume() > 0
    end

    -- Returns "characters/<key>", not just the key -- every path
    -- built elsewhere as "assets/" .. folder .. "/file.ogg" resolves
    -- correctly without needing any other changes.
    local function characterFolder()
      return "characters/" .. (mod.options:get("character") or characterDefault)
    end

    local function milestoneFolder()
      return "milestones/" .. (mod.options:get("milestone_voice") or milestoneDefault)
    end

    -- pcall so a missing file just stays silent instead of crashing
    -- the whole mod
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
    mod.hooks:wrap("music.volume", function(next, vol, ctx)
      vol = next(vol, ctx)
      if love.timer.getTime() < duckUntil then
        return vol * 0.3
      end
      return vol
    end)

    -- ---- Frequency & chance ----
    local function chance(percent)
      return math.random(100) <= percent
    end

    local function frequencyMultiplier(key)
      return mod.options:get(key) or 1
    end

    -- ---- Bark cooldown & delay queue ----
    -- Shared cooldown so hit and status barks can never stack.
    local BARK_COOLDOWN = 5
    local lastBarkAt = -math.huge

    local function attemptBark(pool)
      local now = love.timer.getTime()
      if now - lastBarkAt < BARK_COOLDOWN then return end
      lastBarkAt = now
      playRandom(pool)
    end

    -- damage_dealt fires before the hit animation plays, so we queue
    -- the bark and let it go off a beat later instead of talking over
    -- the animation.
    local pendingBarks = {}
    local function scheduleBark(pool, delay)
      table.insert(pendingBarks, { at = love.timer.getTime() + delay, pool = pool })
    end

    -- Separate from the bark queue on purpose -- a meaningful line
    -- like blackout.ogg shouldn't get eaten just because an unrelated
    -- bark happens to be on cooldown at the same moment.
    local pendingMoments = {}
    local function scheduleMoment(path, delay)
      table.insert(pendingMoments, { at = love.timer.getTime() + delay, path = path })
    end

    mod.hooks:wrap("input.step", function(next, ...)
      local now = love.timer.getTime()
      for i = #pendingBarks, 1, -1 do
        if now >= pendingBarks[i].at then
          local entry = table.remove(pendingBarks, i)
          attemptBark(entry.pool)
        end
      end
      for i = #pendingMoments, 1, -1 do
        if now >= pendingMoments[i].at then
          local entry = table.remove(pendingMoments, i)
          playSound(entry.path)
        end
      end
      return next(...)
    end)

    -- ================================================================
    -- EVENTS -- wires the framework above into actual game moments.
    -- ================================================================

    -- ---- Game start (New Game / Continue) ----
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
        mod.assets:path("assets/" .. folder .. "/continue5.ogg"),
      })
    end)

    -- ---- Battle barks (hit / status) ----
    mod.events:on("battle.damage_dealt", function(ev)
      -- user.isPlayer confirmed against the real event reference --
      -- this fires for either side landing a hit, so without this
      -- check an enemy's hit would trigger the same pleased bark a
      -- player hit does. Deliberately player-only for now, not split
      -- into a matching enemy/player pair the way status is.
      if not (ev.user and ev.user.isPlayer) then return end
      if not chance(15 * frequencyMultiplier("freq_battle_barks")) then return end
      local folder = characterFolder()
      scheduleBark({
        mod.assets:path("assets/" .. folder .. "/hit1.ogg"),
        mod.assets:path("assets/" .. folder .. "/hit2.ogg"),
        mod.assets:path("assets/" .. folder .. "/hit3.ogg"),
      }, 1.5)
    end)

    mod.events:on("battle.status_inflicted", function(ev)
      if not chance(10 * frequencyMultiplier("freq_battle_barks")) then return end
      local folder = characterFolder()
      -- target.isPlayer confirmed against real source
      -- (StatusRegistry.lua's own displayName(b) uses b.isPlayer on
      -- this exact target object) -- this fires for a status landing
      -- on EITHER side, not just the opponent, so it needs the same
      -- isPlayer check battle.fainted already uses.
      if ev.target and ev.target.isPlayer then
        attemptBark({
          mod.assets:path("assets/" .. folder .. "/status_player.ogg"),
          mod.assets:path("assets/" .. folder .. "/status_player2.ogg"),
        })
      else
        attemptBark({
          mod.assets:path("assets/" .. folder .. "/status_enemy.ogg"),
          mod.assets:path("assets/" .. folder .. "/status_enemy2.ogg"),
        })
      end
    end)

    -- ---- Day/Night ambient lines ----
    -- Gen 1 has no real day/night clock, so this mostly only fires on
    -- Gold saves.
    mod.events:on("world.tod_changed", function(ev)
      if not chance(5 * frequencyMultiplier("freq_day_night")) then return end
      local period = tostring(ev.daytime or ev.tod or ""):upper()
      local folder = characterFolder()
      if period == "NITE" or period == "DARK" or period:find("NIGHT") then
        playRandom({
          mod.assets:path("assets/" .. folder .. "/night1.ogg"),
          mod.assets:path("assets/" .. folder .. "/night2.ogg"),
          mod.assets:path("assets/" .. folder .. "/night3.ogg"),
        })
      elseif period == "MORN" or period:find("MORNING") then
        playRandom({
          mod.assets:path("assets/" .. folder .. "/morning1.ogg"),
          mod.assets:path("assets/" .. folder .. "/morning2.ogg"),
        })
      end
    end)

    -- ---- Reactions ----
    -- Small, wordless battle nuance: crits, misses, catches, escapes,
    -- faints.

    mod.events:on("battle.damage_dealt", function(ev)
      if not ev.crit then return end
      -- same user.isPlayer check as the hit1/2/3 pool above -- a crit
      -- landed BY the enemy shouldn't play the same pleased bark.
      if not (ev.user and ev.user.isPlayer) then return end
      if not chance(50 * frequencyMultiplier("freq_reactions")) then return end
      local folder = characterFolder()
      attemptBark({
        mod.assets:path("assets/" .. folder .. "/hit_crit.ogg"),
        mod.assets:path("assets/" .. folder .. "/hit_crit2.ogg"),
      })
    end)

    -- battle.accuracy is a hook, not an event -- nothing fires on a
    -- miss otherwise.
    mod.hooks:wrap("battle.accuracy", function(next, ctx)
      local hit = next(ctx)
      -- user.isPlayer confirmed against the real hook reference --
      -- this wraps EITHER side's accuracy roll, so without this check
      -- an enemy's miss would trigger the same disappointed bark a
      -- player's miss does.
      local isPlayerMove = ctx.user and ctx.user.isPlayer
      if not hit and isPlayerMove and chance(20 * frequencyMultiplier("freq_reactions")) then
        local folder = characterFolder()
        attemptBark({
          mod.assets:path("assets/" .. folder .. "/move_miss.ogg"),
          mod.assets:path("assets/" .. folder .. "/move_miss2.ogg"),
        })
      end
      return hit
    end)

    -- same deal for a failed catch -- pokemon.caught only fires on
    -- success.
    mod.hooks:wrap("catch.rate", function(next, ball, mon, def, opts)
      local caught, shakes = next(ball, mon, def, opts)
      if not caught and chance(25 * frequencyMultiplier("freq_reactions")) then
        local folder = characterFolder()
        attemptBark({
          mod.assets:path("assets/" .. folder .. "/catch_fail.ogg"),
          mod.assets:path("assets/" .. folder .. "/catch_fail2.ogg"),
        })
      end
      return caught, shakes
    end)

    mod.hooks:wrap("battle.run", function(next, ctx)
      local escaped = next(ctx)
      if chance(25 * frequencyMultiplier("freq_reactions")) then
        local folder = characterFolder()
        if escaped then
          attemptBark({
            mod.assets:path("assets/" .. folder .. "/run_success.ogg"),
            mod.assets:path("assets/" .. folder .. "/run_success2.ogg"),
          })
        else
          attemptBark({
            mod.assets:path("assets/" .. folder .. "/run_fail.ogg"),
            mod.assets:path("assets/" .. folder .. "/run_fail2.ogg"),
          })
        end
      end
      return escaped
    end)

    -- own dial (freq_faint), not freq_reactions -- a faint is a
    -- bigger deal than a miss or a failed catch, defaults to firing
    -- every time rather than sharing the others' baseline.
    mod.events:on("battle.fainted", function(ev)
      if not chance(mod.options:get("freq_faint") or 100) then return end
      local folder = characterFolder()
      if ev.battler and ev.battler.isPlayer then
        attemptBark({
          mod.assets:path("assets/" .. folder .. "/faint_player.ogg"),
          mod.assets:path("assets/" .. folder .. "/faint_player2.ogg"),
        })
      else
        attemptBark({
          mod.assets:path("assets/" .. folder .. "/faint_enemy.ogg"),
          mod.assets:path("assets/" .. folder .. "/faint_enemy2.ogg"),
        })
      end
    end)

    -- ---- Moments ----
    -- Bigger, rarer beats -- evolving, a first catch, blacking out.
    -- No chance-gating needed, these are already rare on their own.
    -- (Ordinary trainer win/loss shares this toggle too, but the
    -- handler for it lives down with Gym Badges/Elite Four, since
    -- it's the same battle.ended listener.)

    mod.events:on("pokemon.evolved", function(ev)
      if not mod.options:get("cat_moments") then return end
      local folder = characterFolder()
      playSound(mod.assets:path("assets/" .. folder .. "/evolved.ogg"))
    end)

    mod.events:on("pokemon.caught", function(ev)
      if not mod.options:get("cat_moments") then return end
      if not ev.isNew then return end
      local folder = characterFolder()
      playRandom({
        mod.assets:path("assets/" .. folder .. "/new_catch.ogg"),
        mod.assets:path("assets/" .. folder .. "/new_catch2.ogg"),
      })
    end)

    -- Delayed so it lands after the loss reaction and the warp back
    -- to a Pokemon Center, rather than stacked on top of either.
    mod.events:on("world.blacked_out", function(ev)
      if not mod.options:get("cat_moments") then return end
      local folder = characterFolder()
      local blackoutPaths = {
        mod.assets:path("assets/" .. folder .. "/blackout.ogg"),
        mod.assets:path("assets/" .. folder .. "/blackout2.ogg"),
      }
      scheduleMoment(blackoutPaths[math.random(#blackoutPaths)], 3)
    end)

    -- ---- Gym Badges & Elite Four ----
    -- Two voice sources: CHARACTER reacts to walking into the room;
    -- MILESTONE VOICE handles both the per-trainer challenge line
    -- (on engaging that specific leader) and the win, since both are
    -- really about the leader, not about who's escorting the player.

    -- Trainer class -> base name, shared by both _intro (on engage,
    -- below) and _outro (on win, in battle.ended further down).
    local GYM_LEADERS = {
      OPP_BROCK = "brock",
      OPP_MISTY = "misty",
      OPP_LT_SURGE = "surge",
      OPP_ERIKA = "erika",
      OPP_KOGA = "koga",
      OPP_SABRINA = "sabrina",
      OPP_BLAINE = "blaine",
      OPP_GIOVANNI = "giovanni",
    }
    local ELITE_FOUR = {
      OPP_LORELEI = "lorelei",
      OPP_BRUNO = "bruno",
      OPP_AGATHA = "agatha",
      OPP_LANCE = "lance",
    }

    -- Map IDs, for map.entered below -- a different identifier space
    -- from the trainer classes above.
    local GYM_MAPS = {
      PEWTER_GYM = true, CERULEAN_GYM = true, VERMILION_GYM = true,
      CELADON_GYM = true, FUCHSIA_GYM = true, SAFFRON_GYM = true,
      CINNABAR_GYM = true, VIRIDIAN_GYM = true,
    }
    local E4_MAPS = {
      LORELEIS_ROOM = true, BRUNOS_ROOM = true,
      AGATHAS_ROOM = true, LANCES_ROOM = true,
    }

    -- Confirmed against real source (data/scripts/story.lua): the
    -- Champion battle is always OPP_RIVAL3 (distinct from the earlier
    -- OPP_RIVAL1/OPP_RIVAL2 rival fights), fought in a real, confirmed
    -- map, CHAMPIONS_ROOM. Long treated as unconfirmed/impossible to
    -- detect -- it isn't, it just needed tracing properly.
    local CHAMPION_TRAINER = "OPP_RIVAL3"

    -- Just the character's own reaction to the room -- fires every
    -- time it's entered, not suppressed after the first visit, since
    -- that's rare enough in practice not to need it. The leader's own
    -- challenge line comes later, in world.trainer_engaged below, once
    -- the battle actually starts rather than as soon as you walk in.
    mod.events:on("map.entered", function(ev)
      if GYM_MAPS[ev.mapId] then
        if not mod.options:get("cat_gym_badges") then return end
        local charFolder = characterFolder()
        playRandom({
          mod.assets:path("assets/" .. charFolder .. "/gym_enter.ogg"),
          mod.assets:path("assets/" .. charFolder .. "/gym_enter2.ogg"),
          mod.assets:path("assets/" .. charFolder .. "/gym_enter3.ogg"),
        })
      elseif E4_MAPS[ev.mapId] then
        if not mod.options:get("cat_elite_four") then return end
        local charFolder = characterFolder()
        playRandom({
          mod.assets:path("assets/" .. charFolder .. "/e4_enter.ogg"),
          mod.assets:path("assets/" .. charFolder .. "/e4_enter2.ogg"),
        })
      elseif ev.mapId == "CHAMPIONS_ROOM" then
        if not mod.options:get("cat_champion") then return end
        local charFolder = characterFolder()
        playRandom({
          mod.assets:path("assets/" .. charFolder .. "/champion_enter.ogg"),
          mod.assets:path("assets/" .. charFolder .. "/champion_enter2.ogg"),
        })
      end
    end)

    -- Tracks who's about to be fought (for the outcome below) AND
    -- plays that specific leader's own challenge line right now, e.g.
    -- brock_intro.ogg. Same pattern for the Champion (CHAMPION_TRAINER)
    -- as for a gym leader or E4 member, just a single trainer instead
    -- of a lookup table.
    local pendingTrainerClass = nil
    mod.events:on("world.trainer_engaged", function(ev)
      pendingTrainerClass = ev.trainerClass
      local gymBase = GYM_LEADERS[ev.trainerClass]
      local e4Base = ELITE_FOUR[ev.trainerClass]
      if gymBase and mod.options:get("cat_gym_badges") then
        local folder = milestoneFolder()
        playSound(mod.assets:path("assets/" .. folder .. "/" .. gymBase .. "_intro.ogg"))
      elseif e4Base and mod.options:get("cat_elite_four") then
        local folder = milestoneFolder()
        playSound(mod.assets:path("assets/" .. folder .. "/" .. e4Base .. "_intro.ogg"))
      elseif ev.trainerClass == CHAMPION_TRAINER and mod.options:get("cat_champion") then
        local folder = milestoneFolder()
        playSound(mod.assets:path("assets/" .. folder .. "/champion_intro.ogg"))
      end
    end)

    -- Delayed so it doesn't land on top of a faint bark from the
    -- finishing blow. Originally 1.5s -- reduced after real
    -- playtesting showed the actual battle-end-to-overworld transition
    -- is faster than that, so the line was landing as a noticeable
    -- beat of silence after the player was already back on the map.
    local OUTCOME_DELAY = 0.8

    mod.events:on("battle.ended", function(ev)
      local trainerClass = pendingTrainerClass
      pendingTrainerClass = nil
      if ev.result == "win" then
        local gymBase = GYM_LEADERS[trainerClass]
        local e4Base = ELITE_FOUR[trainerClass]
        if gymBase then
          if not mod.options:get("cat_gym_badges") then return end
          local folder = milestoneFolder()
          scheduleMoment(mod.assets:path("assets/" .. folder .. "/" .. gymBase .. "_outro.ogg"), OUTCOME_DELAY)
        elseif e4Base then
          if not mod.options:get("cat_elite_four") then return end
          local folder = milestoneFolder()
          scheduleMoment(mod.assets:path("assets/" .. folder .. "/" .. e4Base .. "_outro.ogg"), OUTCOME_DELAY)
        else
          -- Champion is deliberately excluded here, not just falling
          -- through to the generic case -- its real outro plays via
          -- screen.pushed below (the confirmed Hall of Fame signal),
          -- and used to double up with this generic line before
          -- CHAMPION_TRAINER existed to tell the two apart.
          if trainerClass == CHAMPION_TRAINER then return end
          if not mod.options:get("cat_moments") then return end
          local folder = characterFolder()
          local winPaths = {
            mod.assets:path("assets/" .. folder .. "/battle_win.ogg"),
            mod.assets:path("assets/" .. folder .. "/battle_win2.ogg"),
          }
          scheduleMoment(winPaths[math.random(#winPaths)], OUTCOME_DELAY)
        end
      elseif ev.result == "lose" then
        if not mod.options:get("cat_moments") then return end
        local folder = characterFolder()
        local lossPaths = {
          mod.assets:path("assets/" .. folder .. "/battle_loss.ogg"),
          mod.assets:path("assets/" .. folder .. "/battle_loss2.ogg"),
        }
        scheduleMoment(lossPaths[math.random(#lossPaths)], OUTCOME_DELAY)
      end
    end)

    -- ---- Champion ----
    -- Beating the Champion pushes a "HallOfFame" screen -- a reliable
    -- signal, confirmed against real engine source. This is the
    -- outro; the challenge line (champion_intro.ogg) lives up in
    -- world.trainer_engaged above, and used to not exist at all before
    -- CHAMPION_TRAINER ("OPP_RIVAL3", confirmed against
    -- data/scripts/story.lua) was traced down.
    mod.events:on("screen.pushed", function(ev)
      if not mod.options:get("cat_champion") then return end
      if not (ev.state and ev.state.screenId == "HallOfFame") then return end
      local folder = milestoneFolder()
      scheduleMoment(mod.assets:path("assets/" .. folder .. "/champion_outro.ogg"), OUTCOME_DELAY)
    end)

end

return voice
