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

--[[ inputspike - the crossbar input model, running for real, before CB0
     commits to it. NOT part of XIVHud; throwaway.

     dikecho answered "what DIKs arrive". This answers the harder half: does
     the v4 hold-state model behave, and does selective blocking actually
     stop the game seeing a key. It is a working prototype of input.lua with
     an on-screen readout, so the model can be judged by using it rather than
     by reading a spec.

     It implements four of the component's six guards - chat, focus, edge
     detection and inbound-blocked - plus the latch. Suppression and edit
     mode need the framework, so they are the component's to prove, not
     this addon's.

     Install: copy this folder to Windower4/addons/inputspike/, then
     //lua load inputspike.

     SAFETY. Blocking starts OFF and must be turned on deliberately. The whole
     handler is wrapped: if anything in it errors while blocking is on,
     blocking disables itself and says so, because a dead handler that keeps
     swallowing input is indistinguishable from a frozen client. `//is panic`
     kills blocking from the chat box, which is never blocked.

     WHAT TO LOOK FOR
       1. Hold states, v4 keys. Hold [ -> xhb_left. ] -> xhb_right. Add
          backslash to either -> the wxhb pair. [ then ] -> expanded_lr; ]
          then [ -> expanded_rl. Release one of a pair -> falls back to the
          survivor, and re-pressing the released one makes the OTHER the
          first of the pair. The readout should never disagree with you.
       2. Blocking (`//is block`), the one that matters. With a side held,
          press 1-8: nothing should reach the game. Ctrl+9/Ctrl+0 must still
          fire their macros, since we never touch modified keys now. (v3
          failed here: Ctrl+N chords fire regardless of blocking.)
       3. Blocking OUR keys. With blocking on, press [ ] backslash backtick
          and = one at a time: none of them may open the chat log. This is
          new - an earlier build let the sides and layer through, and an
          unblocked side key opens chat on its way to activating a side,
          which then makes the whole crossbar inert. With blocking off they
          should each open chat, which is how you know they reached the game.
       4. Auto-repeat. Hold a slot key down: `fires` must increment once, not
          once per repeat. `repeats` counts what the OS sent.
       5. Chat. Open the chat box and type numbers: nothing fires, nothing is
          blocked, and the numbers reach the box. Then release a held
          activator while chat is open and close it - the readout must show
          `none`, not a stranded hold state.
       6. Focus. Alt-tab away mid-hold and back: state must be clear.
       7. Inbound blocked. Informational only - nothing to produce. If some
          other addon consumes a key before this one sees it, `blocked-in`
          counts it. With no other keyboard-blocking addon loaded it stays 0,
          which is a pass.
       8. setkey names and echo. Type `//setkey e down` then `//setkey e up`
          in the console. The message confirms the name parsed; then check
          whether `events` moved - if injected keys re-enter our own handler,
          the component needs to ignore its own injections.
       9. Chord vs bare blocking (`//is bare`). Blocks the number row with no
          modifier held. Already answered once - bare 3 was swallowed while
          Ctrl+3 fired its macro anyway, which is why v4 holds no modifiers -
          but the toggle is kept for re-testing after any map change.

     COMMANDS
       //is             status + this checklist in brief
       //is block       toggle selective blocking (default off)
       //is bare        toggle blocking the number row with no modifier
       //is panic       force blocking off
       //is show|hide   the on-screen readout
       //is reset       zero the counters
]]

_addon.name = "inputspike"
_addon.author = "Azureblood2"
_addon.version = "0.1"
_addon.command = "is"

-- Windower's require returns the library; the same-named global is a
-- convention the caller has to establish. A bare require("texts") loads it
-- and leaves `texts` nil, which is how v0.1 died at load.
texts = require("texts")

--[[ The v4 map: no modifiers anywhere.

     v3 used Ctrl/Alt/Shift as activators, which put every slot press on a
     Ctrl+number chord - and in-client those chords fire FFXI's own macros
     even when this handler returns true. Bare keys block fine; modified ones
     do not, so the game must be reading chords by a route Windower's hook
     does not cover. (xivcrossbar sat on Ctrl+F1-F12, chords FFXI ignores, so
     it never had to find this out.)

     An activator does not have to be a modifier - only a key the game
     ignores and the bridge can hold. These are punctuation and the number
     row; press anything unmapped and the note line reports its DIK, which is
     how to check a replacement is free. ]]
local XHB_LEFT = { [26] = true } -- [
local XHB_RIGHT = { [27] = true } -- ]
local W_LAYER = { [43] = true } -- backslash
local SET_SWITCH = 41 -- backtick
local SHORTCUT = 13 -- '='
local SLOTS = { [2] = 1, [3] = 2, [4] = 3, [5] = 4, [6] = 5, [7] = 6, [8] = 7, [9] = 8 }

local blocking = false
-- Blocks the number row with NO hold state required, to answer whether
-- Windower can block a key at all versus only an unchorded one. Safe: chat
-- opens with Enter, so this cannot lock you out of `//is panic`.
local bare_block = false
local showing = true

-- Held activators, and the order the two sides were pressed in - the only
-- thing that separates expanded_lr from expanded_rl.
local held = { left = false, right = false, layer = false, switch = false }
local first_side = nil

-- Keys whose press we blocked. A release is blocked if and only if its press
-- was: letting a release through that we swallowed the press for leaves the
-- game believing the key is still down.
local latched = {}

-- Slot keys currently down, so an auto-repeat stream fires once.
local down = {}

local counts = { events = 0, fires = 0, repeats = 0, blocked = 0, blocked_in = 0 }
local last = { fire = "-", note = "-" }
local seen_switch, seen_shortcut = false, false

-- Degrade to chat rather than dying: this runs in a live client, and a spike
-- that fails to load teaches nothing.
local box_ok, box = pcall(function()
  return texts.new({ flags = { draggable = false } })
end)
if not box_ok then
  box = nil
end

local function say(message)
  pcall(function()
    windower.add_to_chat(207, "[inputspike] " .. message)
  end)
end

local function chat_open()
  local ok, info = pcall(windower.ffxi.get_info)
  return ok and info and info.chat_open or false
end

-- The whole model, in one pure function of what is held.
local function hold_state()
  if held.left and held.right then
    if first_side == "left" then
      return "expanded_lr"
    end
    return "expanded_rl"
  end
  if held.left then
    return held.layer and "wxhb_left" or "xhb_left"
  end
  if held.right then
    return held.layer and "wxhb_right" or "xhb_right"
  end
  return "none"
end

local function role_of(dik)
  if XHB_LEFT[dik] then
    return "left"
  elseif XHB_RIGHT[dik] then
    return "right"
  elseif W_LAYER[dik] then
    return "layer"
  elseif dik == SET_SWITCH then
    return "switch"
  elseif dik == SHORTCUT then
    return "shortcut"
  elseif SLOTS[dik] then
    return "slot"
  end
  return nil
end

local function refresh()
  if not box then
    return
  end
  if not showing then
    box:hide()
    return
  end
  box:pos(400, 200)
  box:size(10)
  local layout = table.concat({
    "inputspike  blocking=%s  bare=%s  chat=%s",
    "hold: %s   held [=%s ]=%s \\=%s `=%s",
    "last fire: %s",
    "note: %s",
    "events=%d fires=%d repeats=%d blocked=%d blocked-in=%d",
    "dead keys seen: backtick=%s equals=%s",
    "//is block | //is bare | //is panic | //is reset",
  }, "\n")
  box:text(
    layout:format(
      tostring(blocking),
      tostring(bare_block),
      tostring(chat_open()),
      hold_state(),
      tostring(held.left),
      tostring(held.right),
      tostring(held.layer),
      tostring(held.switch),
      last.fire,
      last.note,
      counts.events,
      counts.fires,
      counts.repeats,
      counts.blocked,
      counts.blocked_in,
      tostring(seen_switch),
      tostring(seen_shortcut)
    )
  )
  box:show()
end

-- Returns true to swallow the key. Everything here is deliberately explicit:
-- this is the shape input.lua has to end up with, so a surprise here is worth
-- more than a tidy implementation.
local function on_key(dik, pressed, flags, blocked_in)
  counts.events = counts.events + 1

  local role = role_of(dik)
  if dik == SET_SWITCH then
    seen_switch = true
  end
  if dik == SHORTCUT then
    seen_shortcut = true
  end

  -- State tracks FIRST, whatever the guards say below: an event another addon
  -- blocked, or one arriving while chat is open, still moved a physical key,
  -- and forgetting that strands the model out of sync with the hand.
  if role == "left" or role == "right" then
    -- Press order is "whichever of the currently-held pair went down first".
    -- Pressing into a pair where the other side is ALREADY held makes that
    -- other side the first one - not this one, and not whatever was first
    -- last time. (Kevin, in-client: LT->RT, release LT, hold LT again gave
    -- expanded_lr where the held ] should have made it expanded_rl.)
    local other = role == "left" and "right" or "left"
    if pressed and not held[role] then
      first_side = held[other] and other or role
    end
    held[role] = pressed
    if not held.left and not held.right then
      first_side = nil
    end
  elseif role == "layer" then
    held.layer = pressed
  elseif role == "switch" then
    held.switch = pressed
  end

  -- Slot-key down-state is bookkeeping, not action: releases must clear it
  -- even when a guard below swallows the rest, or the next press after chat
  -- closes reads as an auto-repeat. (Round 11.)
  -- Slot-key down-state is bookkeeping, not action: it tracks through every
  -- guard, in both directions. Tracking only releases meant a key held down
  -- while typing read as a fresh press when chat closed.
  local was_down = down[dik]
  if role == "slot" then
    down[dik] = pressed and true or nil
  end

  -- Guard: another addon consumed the key. No fire, no block of ours - but a
  -- release we latched still stays swallowed-consistent by clearing the latch.
  if blocked_in then
    counts.blocked_in = counts.blocked_in + 1
    last.note = "inbound blocked dik=" .. tostring(dik) .. " (state tracked)"
    -- The latch outranks every guard: a release whose press we swallowed stays
    -- swallowed, or the game sees a key-up it never saw a key-down for.
    if not pressed and latched[dik] then
      latched[dik] = nil
      return true
    end
    return false
  end

  -- Guard: the chat box has the keyboard. Nothing fires and nothing new is
  -- blocked, but a release whose press we blocked is still ours to swallow.
  if chat_open() then
    last.note = "chat open - passed through"
    if not pressed and latched[dik] then
      latched[dik] = nil
      return true
    end
    return false
  end

  local state = hold_state()

  if role == "slot" then
    -- The switch is inert while any side is held, so a slot key means "fire"
    -- there, never "jump"; and with neither a side nor the switch, nothing
    -- fires at all.
    local jumping = held.switch and state == "none"
    local want_block = bare_block or state ~= "none" or held.switch
    if pressed then
      if was_down then
        counts.repeats = counts.repeats + 1
      else
        local slot = SLOTS[dik]
        if jumping then
          counts.fires = counts.fires + 1
          last.fire = ("jump to set %d"):format(slot)
        elseif state ~= "none" then
          counts.fires = counts.fires + 1
          last.fire = ("%s slot %d"):format(state, slot)
        else
          last.note = ("slot %d with nothing held - falls through"):format(slot)
        end
      end
      if blocking and want_block then
        latched[dik] = true
        counts.blocked = counts.blocked + 1
        return true
      end
      latched[dik] = nil
      return false
    end

    -- Latch: a release is blocked if and only if its press was - checked
    -- outside the `blocking` toggle, so switching blocking off mid-hold
    -- cannot leak a key-up the game never saw the key-down for.
    if latched[dik] then
      latched[dik] = nil
      return true
    end
    return false
  end

  if role == "switch" or role == "shortcut" then
    if pressed and role == "shortcut" then
      last.fire = state ~= "none" and "shortcut (chorded)" or "shortcut (bare)"
      counts.fires = counts.fires + 1
    end
    if pressed then
      if blocking then
        latched[dik] = true
        counts.blocked = counts.blocked + 1
        return true
      end
      latched[dik] = nil
      return false
    end
    if latched[dik] then
      latched[dik] = nil
      return true
    end
    return false
  end

  -- Sides and the layer are ours as much as the switch is: unblocked, they
  -- reach the game and open the chat log, which then makes everything else
  -- inert. Blocked at press, latched for the release.
  if role == "left" or role == "right" or role == "layer" then
    if pressed then
      if blocking then
        latched[dik] = true
        counts.blocked = counts.blocked + 1
        return true
      end
      latched[dik] = nil
      return false
    end
    if latched[dik] then
      latched[dik] = nil
      return true
    end
    return false
  end

  if role == nil then
    last.note = ("unmapped dik=%s flags=%s"):format(tostring(dik), tostring(flags))
  end
  return false
end

windower.register_event("keyboard", function(dik, pressed, flags, blocked_in)
  local ok, result = pcall(on_key, dik, pressed, flags, blocked_in)
  if not ok then
    -- Never keep swallowing input after a failure.
    blocking = false
    say("handler error, blocking forced OFF: " .. tostring(result))
    return false
  end
  pcall(refresh)
  return result
end)

windower.register_event("lose focus", function()
  held = { left = false, right = false, layer = false, switch = false }
  first_side = nil
  latched = {}
  down = {}
  last.note = "lose focus - state cleared"
  pcall(refresh)
end)

windower.register_event("load", function()
  say("loaded. //is for status. Blocking is OFF until //is block.")
  if not box then
    say("texts library unavailable - readout disabled, //is still reports.")
  end
  pcall(refresh)
end)

windower.register_event("unload", function()
  if box then
    pcall(function()
      box:destroy()
    end)
  end
end)

windower.register_event("addon command", function(command)
  command = command and command:lower() or ""
  if command == "block" then
    blocking = not blocking
    say("blocking " .. (blocking and "ON - hold [ and press 1-8; nothing should reach the game" or "off"))
  elseif command == "bare" then
    bare_block = not bare_block
    say("bare number-row block " .. (bare_block and "ON - press 3 with NO modifier held" or "off"))
  elseif command == "panic" then
    blocking = false
    bare_block = false
    latched = {}
    say("blocking forced OFF")
  elseif command == "show" then
    showing = true
  elseif command == "hide" then
    showing = false
    if box then
      box:hide()
    end
  elseif command == "reset" then
    counts = { events = 0, fires = 0, repeats = 0, blocked = 0, blocked_in = 0 }
    last = { fire = "-", note = "-" }
    seen_switch, seen_shortcut = false, false
    say("counters reset")
  else
    say("blocking=" .. tostring(blocking) .. " hold=" .. hold_state() .. " events=" .. counts.events)
    say("1) hold [ ] and \\ and watch `hold`  2) //is block, then press [ - chat must NOT open")
    say("3) hold a slot key: fires must not climb with repeats  4) type in chat: nothing fires")
  end
  pcall(refresh)
end)
