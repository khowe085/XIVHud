--[[ Reusable fakes for the injected Windower surface.

     With dependency injection a "mock" is just a plain table of functions, so
     tests stay framework-light. Build a deps table here and pass it to a lib
     module's constructor. Override only the fields a given test cares about. ]]

local M = {}

-- A fake `deps` for lib/status.lua. Pass a player table (or nil for logged-out).
function M.status_deps(player)
  return {
    get_player = function()
      return player
    end,
  }
end

return M
