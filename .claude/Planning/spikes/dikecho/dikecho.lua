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

--[[ dikecho v0.2 - throwaway input spike for the crossbar plan. NOT part of XIVHud.

     Install: copy this folder to Windower4/addons/dikecho/ and //lua load dikecho.

     v0.2: every handler line is pcall-guarded (v0.1's get_info() call could
     silently kill the handler), echo no longer gates on chat state, and a
     per-key counter distinguishes "handler dead" from "this key never arrives".

     Test sequence, logged into a character:
       //dik echo        then press, one at a time, releasing between:
         a               (sanity: any event at all?)
         3               (number row: expect dik=4)
         LCtrl LShift LAlt, RCtrl RShift RAlt   (expect 29 42 56, 157 54 184)
         Ctrl+3 held together (does 3's event still arrive? note its flags
                          value vs the bare 3 press)
       //dik             prints total events seen + per-dik tallies: if the
                         total moved while a key printed nothing, that key
                         genuinely produced no event; if the total never moves,
                         the handler or event itself is dead.
       Then the same modifier presses from Steam Input / your send_input tool
       (injected input may behave differently from physical - xivcrossbar's
       AHK bridge injects Ctrl and its dik==29 check works for its users).

     //dik        - status: total event count + the dik tallies seen so far
     //dik echo   - toggle per-key chat output
     //dik block  - toggle the block test (swallow dik 2-9 while 29 is down)
     //dik reset  - clear counters
]]

_addon.name = "dikecho"
_addon.author = "Azureblood2"
_addon.version = "0.2"
_addon.command = "dik"

local echoing = false
local blocking = false
local lctrl_down = false
local total_events = 0
local seen = {} -- dik -> count

local function say(message)
  pcall(function()
    windower.add_to_chat(207, "[dikecho] " .. message)
  end)
end

windower.register_event("keyboard", function(dik, pressed, flags, blocked)
  total_events = total_events + 1
  if type(dik) == "number" then
    seen[dik] = (seen[dik] or 0) + 1
    if dik == 29 then
      lctrl_down = pressed and true or false
    end
  end

  if echoing then
    say(
      string.format(
        "dik=%s pressed=%s flags=%s blocked=%s",
        tostring(dik),
        tostring(pressed),
        tostring(flags),
        tostring(blocked)
      )
    )
  end

  -- Block test: swallow ONLY the number row (DIK 2-9) while LCtrl is held.
  if blocking and lctrl_down and type(dik) == "number" and dik >= 2 and dik <= 9 then
    return true
  end
end)

windower.register_event("gain focus", function()
  say("gain focus")
end)

windower.register_event("lose focus", function()
  say("lose focus (LCtrl believed down: " .. tostring(lctrl_down) .. ")")
end)

windower.register_event("load", function()
  say("v0.2 loaded - //dik for status, //dik echo to start")
end)

windower.register_event("addon command", function(command)
  command = command and command:lower() or ""
  if command == "echo" then
    echoing = not echoing
    say("echo " .. (echoing and "on" or "off"))
  elseif command == "block" then
    blocking = not blocking
    say("block test " .. (blocking and "on - hold LCtrl, press 1-8" or "off"))
  elseif command == "reset" then
    total_events = 0
    seen = {}
    say("counters reset")
  else
    say("total keyboard events seen: " .. total_events)
    local diks = {}
    for dik in pairs(seen) do
      diks[#diks + 1] = dik
    end
    table.sort(diks)
    local parts = {}
    for _, dik in ipairs(diks) do
      parts[#parts + 1] = dik .. "x" .. seen[dik]
    end
    say("diks seen: " .. (next(seen) and table.concat(parts, " ") or "none"))
    say("expected: LCtrl 29 / RCtrl 157, LAlt 56 / RAlt 184, LShift 42 / RShift 54, '1'-'8' = 2-9")
  end
end)
