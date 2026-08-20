--[[
Copyright © 2026, Azureblood2
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of XIVHud nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Azureblood2 BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Ported from xivcrossbar's libs/mountroulette/mountroulette.lua, whose notice
BSD clause 1 requires retained in derived source:

Copyright © 2020, Dean James (Xurion of Bismarck)
All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Mount Roulette nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Dean James (Xurion of Bismarck) BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

--[[ Pure mount roulette: owned-mount tracking plus the ride pick. The `mr`
     built-in resolves through here; ride() answers a command string (or nil
     for the no-op) rather than sending anything, so the module stays pure.

     Owned mounts are key items of category Mounts (minus the quest-only
     trainer's whistle - excluded by the note prefix, not by name; see the
     refresh), matched against the mount resource names. A mount KI
     name is the mount's name behind a music-note prefix, written as byte
     escapes because FFXI chat is not UTF-8 and sources_spec forbids non-ASCII
     bytes outside comments. Upstream matches with `windower.wc_match` and a
     trailing wildcard; the pure equivalent is a plain prefix match -- an
     equality-after-strip would drop KI names carrying a suffix ("Raptor
     Companion" for the Raptor mount). ]]

local NOTE = "\226\153\170"
local MOUNTED_BUFF = 252
local KEY_ITEM_CHUNK = 0x055

local function new(deps)
  local self = {}

  local owned = {}
  -- command form -> the resource's own casing, filled by refresh().
  local shown_as = {}

  -- Mount resource ids in a fixed order, so a KI that several names could
  -- prefix-match resolves the same way every refresh.
  local mount_ids = {}
  for id in pairs(deps.mounts) do
    mount_ids[#mount_ids + 1] = id
  end
  table.sort(mount_ids)

  --[[ The name `/mount` takes, and the name the game writes, for one key
       item. Lower case is the COMMAND form and the only thing that may
       reach a command line; the resource's own casing exists so a label
       does not have to read "mount chocobo" back at the player. The field
       is `name` because that is the field this component's mount lookup has
       always used - `en` is the usual Windower spelling, but swapping to it
       here would be an unverified change to a lookup that works. ]]
  local function mount_for(ki_name)
    ki_name = ki_name:lower()
    for _, id in ipairs(mount_ids) do
      local shown = deps.mounts[id].name
      local prefix = NOTE .. shown:lower()
      if ki_name:sub(1, #prefix) == prefix then
        return shown:lower(), shown
      end
    end
  end

  function self.refresh()
    owned = {}
    shown_as = {}
    local seen = {}
    for _, id in ipairs(deps.get_key_items() or {}) do
      local ki = deps.key_items[id]
      --[[ There is no name check here, and there must not be one. Upstream
           excludes the quest-only trainer's whistle by name; the prefix
           match below already excludes it, because a mount key item's name
           carries the music-note prefix and the whistle's does not. A
           second, name-based test would be a string literal that has to
           track a resource file to stay true - and would silently stop
           working the day the name changed, with nothing failing. ]]
      if ki ~= nil and ki.category == "Mounts" then
        local mount, shown = mount_for(ki.name)
        if mount and not seen[mount] then
          seen[mount] = true
          owned[#owned + 1] = mount
          shown_as[mount] = shown
        end
      end
    end
  end

  function self.on_chunk(id)
    if id == KEY_ITEM_CHUNK then
      self.refresh()
    end
  end

  --- The game's own casing for an owned mount's command name; anything
  --- else comes back untouched, so a caller never has to guard it.
  function self.display(name)
    if name == nil then
      return nil
    end
    return shown_as[name] or name
  end

  function self.owned()
    return owned
  end

  -- Is a mount up? The one buff read behind both the ride and the travel
  -- delay's summon/dismount question, so the two can never disagree about
  -- which of the two a press is.
  function self.mounted()
    for _, buff in ipairs(deps.get_buffs() or {}) do
      if buff == MOUNTED_BUFF then
        return true
      end
    end
    return false
  end

  -- Mounted -> dismount; nothing owned -> nil (the caller's no-op); else a
  -- random owned mount. ride() never sends -- it answers the command to send.
  function self.ride()
    if self.mounted() then
      return "input /dismount"
    end
    if #owned == 0 then
      return nil
    end
    local index = math.ceil(deps.random() * #owned)
    if index < 1 then
      index = 1
    end
    return 'input /mount "' .. owned[index] .. '"'
  end

  self.refresh()

  return self
end

return new
