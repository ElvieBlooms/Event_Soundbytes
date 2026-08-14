return function(mod)
    math.randomseed(os.time())

    mod.options:define({
      { key = "voice_lines", type = "toggle", label = "VOICE LINES", default = true },
      { key = "character", type = "choice", label = "CHARACTER",
        choices = {
          { "KRIS", "kris" },
          -- add future character packs here, e.g.:
          { "JESSIE", "jessie" },
        },
        default = "kris" },
    })

    local duckUntil = 0

    local function voiceLinesOn()
      return mod.options:get("voice_lines")
    end

    local function characterFolder()
      return mod.options:get("character") or "kris"
    end

    local function playSound(path)
      if not voiceLinesOn() then return end
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

    local function playRandom(paths)
      playSound(paths[math.random(#paths)])
    end

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
  end
