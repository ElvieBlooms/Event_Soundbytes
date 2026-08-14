return function(mod)
  local soundPath = mod.assets:path("assets/event.ogg")
  local duckUntil = 0

  local function playSound()
    local ok, src = pcall(love.audio.newSource, soundPath, "static")
    if ok and src then
      duckUntil = love.timer.getTime() + 2.5
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

  mod.events:once("intro.oak_speech.finished", playSound)
  mod.events:once("save.loaded", playSound)
end
