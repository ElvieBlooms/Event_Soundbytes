return function(mod)
  local mapEnteredPath = mod.assets:path("assets/eventsounds/new_game.ogg")
  -- local saveLoadedPath = mod.assets:path("assets/eventsounds/continue.ogg")
  local duckUntil = 0

  local function playSound(path)
    local ok, src = pcall(love.audio.newSource, path, "static")
    if ok and src then
      duckUntil = love.timer.getTime() + 2.5
      src:play()
    end
  end

  -- To play a random sound from a pool instead of one fixed file, define a
  -- list of paths and pick one at play time:
  --
  -- local voicePool = {
  --   mod.assets:path("assets/voice1.ogg"),
  --   mod.assets:path("assets/voice2.ogg"),
  --   mod.assets:path("assets/voice3.ogg"),
  -- }
  -- local function playRandom(pool)
  --   playSound(pool[math.random(#pool)])
  -- end
  -- -- then call playRandom(voicePool) instead of playSound(mapEnteredPath),
  -- -- or playRandom(voicePool) instead of playSound(saveLoadedPath), below

  mod.hooks:wrap("music.volume", function(next, vol, ctx)
    vol = next(vol, ctx)
    if love.timer.getTime() < duckUntil then
      return vol * 0.3
    end
    return vol
  end)

  mod.events:once("map.entered", function() playSound(mapEnteredPath) end)
  -- mod.events:once("save.loaded", function() playSound(saveLoadedPath) end)
end
