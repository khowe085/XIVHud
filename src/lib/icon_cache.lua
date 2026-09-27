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
]]

--[[ The item-icon extraction pipeline: which icons to pull out of the game's
     DATs, when, and where they land.

     The pure byte-work is lib/icons; this module owns the discipline around
     it, promoted from the Equip Viewer with its hard-won behaviour intact:

     - `request_icon` only queues - nothing is read where the packet arrives.
     - `drain_queue` extracts ONE icon per call. The reference extracted
       inside the packet handler, so a first login with nothing cached meant
       sixteen DAT opens, decodes and file writes in a single frame.
     - An item that fails is abandoned for the session rather than retried
       every frame; `reset` (a detach) clears that, because the likeliest
       cause - a wrong game path - is a setting the player can fix.
     - `cached_icon` remembers every icon it has found on disk, so a redraw
       costs no file lookups.

     The cache lives at `<addon>/icons/<item_id>.bmp` - deliberately NOT under
     data/: `//hud copy` enumerates every directory there as a character, so a
     cache alongside them would be offered as one, and `//hud copy icons
     <name>` would wipe that character's configuration. It is not
     per-character anyway; item art is the same for everyone, and every
     component using this module shares one directory by construction. ]]

local icons = require("lib/icons")

local ICON_CACHE_DIR = "icons/"

-- deps: `asset` (addon-relative -> absolute path), `file_exists` (absolute),
-- `read_dat`, `write_binary` (addon-relative), and `game_path` - already
-- resolved by the caller, so a component's config override wins there, not
-- here. game_path is consulted per attempt: a corrected setting must count.
local function new(deps)
  local self = {}

  --[[ Item ids waiting to be pulled out of a DAT, and the ones already spoken
       for: `queued` stops an item being asked for twice, `abandoned` stops a
       failure being retried every frame for the rest of the session, and
       `resolved` remembers the icons already on disk. ]]
  local pending = {}
  local queued = {}
  local abandoned = {}
  local abandoned_count = 0
  local resolved = {}
  -- Ids a refresh has asked to be read again, whatever is already on disk.
  local forced = {}

  local function icon_file(item_id)
    return ICON_CACHE_DIR .. item_id .. ".bmp"
  end

  -- The icon on disk for an item, or nil if it has not been extracted yet.
  -- An item already given up on is not looked for again: this runs on the
  -- packet path, and the file is not going to appear.
  function self.cached_icon(item_id)
    -- A forced id answers nothing until it has actually been read again, which
    -- is what makes the caller request it rather than settle for the file.
    if forced[item_id] then
      return nil
    end
    if resolved[item_id] then
      return resolved[item_id]
    end
    if abandoned[item_id] then
      return nil
    end
    local path = deps.asset(icon_file(item_id))
    if not deps.file_exists(path) then
      return nil
    end
    resolved[item_id] = path
    return path
  end

  -- An icon the cache does not have is asked for once. Nothing is read here:
  -- this too runs on the packet path.
  function self.request_icon(item_id)
    if queued[item_id] or abandoned[item_id] then
      return
    end
    queued[item_id] = true
    pending[#pending + 1] = item_id
  end

  -- One icon per call, and only while something is waiting. True when an
  -- icon landed on disk, so the caller knows a redraw is worth it.
  function self.drain_queue()
    local item_id = table.remove(pending, 1)
    if not item_id then
      return false
    end
    queued[item_id] = nil

    -- Whatever the reason, it will be the same reason next frame: an item is
    -- given exactly one attempt.
    abandoned[item_id] = true
    abandoned_count = abandoned_count + 1

    local located = icons.locate(item_id)
    local path = located and icons.dat_path(deps.game_path(), located.dat)
    if not path then
      return false
    end

    local bmp = icons.to_bmp(deps.read_dat(path, located.offset, located.length))
    if not bmp or not deps.write_binary(icon_file(item_id), bmp) then
      return false
    end

    abandoned[item_id] = nil
    abandoned_count = abandoned_count - 1
    forced[item_id] = nil
    resolved[item_id] = deps.asset(icon_file(item_id))
    return true
  end

  --[[ How much of the record to sample for a probe. The icon sits 0x2BD in,
       so this is the head of the record BEFORE it - whatever the DAT keeps
       there is the only evidence of which item the offset actually landed on,
       which is the question a wrong icon asks. ]]
  local SAMPLE_LENGTH = 32

  --[[ Read an icon again on the next request, whatever is already on disk.
       Without this a cached icon is PERMANENT - `cached_icon` hands back the
       file without ever looking at it, and an abandoned item is not retried
       for the rest of the session - so a corrupt or half-written icon survives
       every login with no way in from the game.

       The file is deliberately not deleted. Three cache instances share one
       `icons/` directory (the equip viewer's, and one per action bar) and each
       remembers separately what it resolved, so a deletion here would leave
       the other two pointing at a texture that no longer exists - and Windower
       draws nothing, silently, for a missing texture path. The re-extraction
       overwrites the file in place, which every instance already points at.

       What this can and cannot do: re-running the same code over the same DAT
       gives the same bytes, so it cannot fix an icon our current decode gets
       wrong. It does replace a file that is stale, half-written or written by
       an older build, and retries one abandoned after a `game_path`
       correction - which is a real candidate fix for the two bad icons of
       2026-09-18, the reference addon having drawn both correctly from a
       cache of its own.

       Answers whether it had anything to forget. ]]
  function self.refresh(item_id)
    local knew = resolved[item_id] ~= nil or abandoned[item_id] == true
    resolved[item_id] = nil
    forced[item_id] = true
    if abandoned[item_id] then
      abandoned[item_id] = nil
      abandoned_count = abandoned_count - 1
    end
    -- `queued` is left alone on purpose: the id may still be sitting in
    -- `pending`, and clearing it would let a second request queue it twice.
    return knew
  end

  --[[ Every number the extraction would use for an item, for a diagnostic to
       print. It reads the DAT but writes nothing and remembers nothing: a
       probe must not mark an item resolved or abandoned, or asking about a
       broken icon would change whether it is retried.

       `sample_raw` is the head of the RECORD rather than of the icon, and is
       handed back as the bytes that came off disk - turning them into
       something printable belongs to whoever is printing. ]]
  function self.probe(item_id)
    local located = icons.locate(item_id)
    local path = located and icons.dat_path(deps.game_path(), located.dat)
    local report = {
      id = item_id,
      dat = located and located.dat,
      record = located and located.record,
      offset = located and located.offset,
      path = path,
      read = 0,
      -- What `cached_icon` would answer, not merely what is on disk: after a
      -- refresh the file is still there but the icon is being read again.
      cached = not forced[item_id] and deps.file_exists(deps.asset(icon_file(item_id))) == true,
    }
    if not path then
      return report
    end

    local block = deps.read_dat(path, located.offset, located.length)
    report.read = block and #block or 0
    report.sample_raw = deps.read_dat(path, located.record_offset, SAMPLE_LENGTH)
    return report
  end

  --[[ The per-character reset, for a detach: the queue goes with the
       character, and so does everything abandoned - correcting the game_path
       setting has to be worth something. `resolved` stays: a file already on
       disk is still there whoever logs in next. ]]
  function self.reset()
    pending = {}
    queued = {}
    abandoned = {}
    abandoned_count = 0
  end

  -- Whether an item has been given up on this session - the caller's "stop
  -- waiting for this one" test. reset() forgives it with the rest.
  function self.is_abandoned(item_id)
    return abandoned[item_id] == true
  end

  -- How many icons have been given up on, for whoever owns a chat channel to
  -- say so.
  function self.abandoned_count()
    return abandoned_count
  end

  return self
end

return new
