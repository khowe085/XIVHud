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

--[[ The extensible open-action table: name -> how to open that game UI.

     An entry opens with either a slash `command` (sent as `input <command>`,
     instant from any hold state) or a `chord` of key names injected through
     Windower's `setkey` console command (for game UI with no slash command).
     Exactly one of the two, never both. A chord is HELD - see CHORD_HOLD in
     actions.lua - because the client samples the keyboard once a frame and
     never saw the edges when they went out back to back. The table grows by small code
     additions; each new chord entry needs in-client verification, and the
     chords assume the client's default keyboard bindings.

     `icon` is per entry, not per kind: only `map` and the bag family have
     matches in the default pack's top-level singles. An entry without one
     takes the render-time fallback (a generic opener glyph plus the slot's
     name label). ]]

local openers = {
  equipment = { chord = { "ctrl", "e" } },
  inventory = { chord = { "ctrl", "i" }, icon = "item" },
  wardrobe = { command = "/wardrobe", icon = "item" },
  wardrobe2 = { command = "/wardrobe2", icon = "item" },
  wardrobe3 = { command = "/wardrobe3", icon = "item" },
  wardrobe4 = { command = "/wardrobe4", icon = "item" },
  wardrobe5 = { command = "/wardrobe5", icon = "item" },
  wardrobe6 = { command = "/wardrobe6", icon = "item" },
  wardrobe7 = { command = "/wardrobe7", icon = "item" },
  wardrobe8 = { command = "/wardrobe8", icon = "item" },
  case = { command = "/case", icon = "item" },
  sack = { command = "/sack", icon = "item" },
  satchel = { command = "/satchel", icon = "item" },
  quests = { command = "/quest" }, -- needs in-client verification: a wrong slash command fails silently
  linkshell = { command = "/sea all linkshell" },
  map = { command = "/map", icon = "map" }, -- needs in-client verification: a wrong slash command fails silently
}

return openers
