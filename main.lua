return function(mod)
    math.randomseed(os.time())

    local newGamePath  = mod.assets:path("assets/new_game.ogg")
    -- local continuePath = mod.assets:path("assets/continue.ogg")
    local duckUntil = 0

    local function playSound(path)
    local ok, src = pcall(love.audio.newSource, path, "static")
      if ok and src then
      duckUntil = love.timer.getTime() + 2
      src:play()
      end
    end

    mod.hooks:wrap("music.volume", function(next, vol, ctx)
      vol = next(vol, ctx)
      if love.timer.getTime() < duckUntil then
      return vol * 0.3
      end
    return vol
    end)

    local voicePool = {
         mod.assets:path("assets/continue1.ogg"),
         mod.assets:path("assets/continue2.ogg"),
         mod.assets:path("assets/continue3.ogg"),
       }
       local function playRandom(pool)
         playSound(pool[math.random(#pool)])
       end

    mod.events:once("intro.oak_speech.finished", function() playSound(newGamePath) end)
    mod.events:once("save.loaded", function() playRandom(voicePool) end)
  end
