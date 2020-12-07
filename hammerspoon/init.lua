-- this package must be cloned into ~/.hammerspoon/stackline
-- https://github.com/AdamWagner/stackline.git
stackline = require "stackline.stackline.stackline"

stackline:init({
    appearance = {showIcons = false}
})


function rateLimited(nanoSeconds, fn)
  lastTs = nil
  return function (event)
    cutOff = (lastTs or 0) + nanoSeconds
    if event:timestamp() > cutOff then
      fn(event)
      lastTs = event:timestamp()
    end
  end
end


function yabaiPath()
  shell = table.concat({os.getenv("SHELL"), "-c", " "}, " ")
  response = hs.execute(shell .. "'which yabai'")
  return string.gsub(response, "\n", "")
end


function focusWindowInStack (yabai_path, stackPosition)
  cmd = table.concat({yabai_path, "-m", "window", "--focus", "stack." .. stackPosition}, " ")
  hs.execute(cmd)
end


yabai_path = yabaiPath()


-- pressing hyper while vertical scrolling will scroll through the yabai window stack if there is one
scrollWatcher = hs.eventtap.new(
  {hs.eventtap.event.types.scrollWheel},
  -- 90 million ns delay
  rateLimited(90000000, function (event)
    if event:getFlags():containExactly({"cmd", "ctrl", "alt", "shift"}) then
      deltaY = event:getProperty(hs.eventtap.event.properties["scrollWheelEventDeltaAxis1"])

      -- match macOS "natural" scroll direction
      -- TODO base this on the OS setting
      if deltaY > 0 then
        -- if pulling up, look at the previous window
        focusWindowInStack(yabai_path, "prev")
      elseif deltaY < 0 then
        -- if pushing down, look at the next window
        focusWindowInStack(yabai_path, "next")
      end

      -- override so the scroll doesn't bubble to other applications
      event:setProperty(hs.eventtap.event.properties["scrollWheelEventDeltaAxis1"], 0)

    end
  end)
):start()
