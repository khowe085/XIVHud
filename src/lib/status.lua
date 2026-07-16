--[[ Illustrative dependency-injection module (see CLAUDE.md > Modular design & testing).

     Pure logic. It receives the Windower surface it needs as `deps` and never
     reads globals, so unit tests inject fakes instead of a live client.
     Factory style: `require` returns a constructor `new(deps) -> instance`. ]]

local STATUS = { [0] = "Idle", [1] = "Engaged", [2] = "Dead", [3] = "Resting" }

local function new(deps)
  local self = {}

  -- Human-readable status for the logged-in player, or nil when not logged in.
  function self.player_status()
    local player = deps.get_player()
    if not player then
      return nil
    end
    return STATUS[player.status] or "Unknown"
  end

  return self
end

return new
