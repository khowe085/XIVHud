--[[ XIVHud entry point. See CLAUDE.md > Modular design & testing.

     This is the ONLY file allowed to touch Windower globals. It builds a plain
     `deps` table from the live API and injects it into the pure modules under
     lib/. Everything testable lives in lib/; this file just wires the real
     Windower surface in and registers events. ]]

_addon.name = "XIVHud"
_addon.author = "Azureblood2"
_addon.version = "0.1.0"
_addon.command = "xh"

local new_status = require("lib.status")

-- The real Windower surface, injected into the pure module.
local status = new_status({
  get_player = function()
    return windower.ffxi.get_player()
  end,
})

windower.register_event("addon command", function(cmd)
  if cmd == "status" then
    windower.add_to_chat(207, "Status: " .. (status.player_status() or "not logged in"))
  end
end)
