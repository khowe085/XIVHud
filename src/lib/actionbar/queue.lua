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

--[[ The action queue: FFXIV's, for FFXI. A bar press made during a cast or the
     lock after it is held, and goes as invoked the moment the lock clears.

     No packet says a lock is over, so its LENGTH is the one constant here, and
     it is measured from the finish packet with nothing taken off for latency.
     The server starts the lock no later than it sends that packet, so a release
     can only arrive late, by about a round trip, and never early. Everything
     else is a packet: what went out, what started, what finished and what was
     refused - a macro's as much as a bar's. Nothing computes a cast time.

     It holds ONE press, the newest, and sends it once. It never waits on a
     recast, which is the defect that made Selindrile's MiniQueue unusable: a
     press on recast goes out as it always did and the game refuses it, and a
     held press whose recast is running when the lock clears is dropped. ]]

--[[ The seconds after a finish before the next action goes. UNVERIFIED: each
     is the longer of bg-wiki and Selindrile's aftercast, and ranged, which only
     Selindrile gives, is rounded up to a second: too long costs a moment and
     too short loses the press. `//hud queue debug` brackets the real ones. ]]
local LOCK_SECONDS = {
  spell = 3,
  weaponskill = 2.7,
  ability = 1,
  item = 1.5,
  ranged = 1,
  interrupted = 1.75,
}

--[[ How long a press may take to be seen leaving. A GearSwap filter cancels a
     press with no packet at all, and the next press must not wait out an answer
     that cannot come. UNVERIFIED: a guess past the client's send cadence. ]]
local LEAVE_BACKSTOP = 0.6
-- How long what left may go unanswered.
local ANSWER_BACKSTOP = 2
-- Past the longest cast there is, and the longest a press is held.
local FINISH_BACKSTOP = 30

local MODES = { "off", "on", "debug" }
local KNOWN_MODES = { off = true, on = true, debug = true }

-- What can be held: the bar types that are the game's own actions.
local HELD_TYPES = { ma = true, ja = true, ws = true, pet = true, item = true, ra = true }

-- The 0x028 categories, as atom0s' GP_SERV_COMMAND_BATTLE2 notes number them.
local START_KINDS = { [7] = "weaponskill", [8] = "spell", [9] = "item", [12] = "ranged" }
local FINISH_KINDS = {
  [2] = "ranged",
  [3] = "weaponskill",
  [4] = "spell",
  [5] = "item",
  [6] = "ability",
  -- A monster skill of your own, in Monstrosity.
  [11] = "weaponskill",
  [14] = "ability",
  [15] = "ability",
}
-- A start-shaped packet carrying this param is the interrupt of that start.
local INTERRUPT_PARAM = 28787

local ACTION_OUT = 0x01A
local ITEM_OUT = 0x037
-- GearSwap's outgoing_action_category_table, and its 0x037 for an item.
local OUTGOING_KINDS = { [3] = "spell", [7] = "weaponskill", [9] = "ability", [16] = "ranged", [25] = "monster skill" }
-- 1-based, header included.
local CATEGORY_OFFSET = 11
local ACTOR_OFFSET = 5
local MESSAGE_OFFSET = 25

-- GearSwap's `unable_to_use` (statics.lua): the 0x029 messages that mean the
-- last action did not happen. 94 stays out, as it does there: it answers an
-- engage.
local REFUSALS = {}
for message in
  ([[
  12 16 17 18 34 35 40 47 48 49 55 56 62 71 72 76 78 84 87 88 89 90 91 92 95 96
  104 106 111 128 154 155 190 191 192 193 198 199 215 216 217 218 219 220 233 246 247
  307 308 313 315 316 325 328 337 338 346 347 348 349 356
  410 411 428 429 443 444 445 446
  514 516 517 518 523 524 525 547 561 568 569 574 575 579 580 581
  649 660 661 662 665 666 700 701 717
]]):gmatch("%d+")
do
  REFUSALS[tonumber(message)] = true
end

local function u16(data, offset)
  local low, high = data:byte(offset, offset + 1)
  return low + high * 256
end

local function u32(data, offset)
  local b1, b2, b3, b4 = data:byte(offset, offset + 3)
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function new(deps)
  local self = { modes = MODES }

  local held = nil
  -- The press that last went out, for as long as nothing has answered it.
  local going = nil
  -- Each nil until its packet sets it, and the moment it stops counting after.
  local sent_until, acting_until, lock_until = nil, nil, nil
  -- Whether what `sent_until` waits on has been seen leaving the client.
  local sent_left = false
  local finished_at = nil

  local function now()
    return deps.now()
  end

  function self.defaults()
    return { queue = "off" }
  end

  --- A hand-broken value reads as off: this holds presses back, so it has to
  --- be asked for.
  function self.mode()
    local live = deps.config()
    local mode = type(live) == "table" and live.queue or nil
    return KNOWN_MODES[mode] and mode or "off"
  end

  function self.enabled()
    return self.mode() ~= "off"
  end

  local function note(line)
    if self.mode() == "debug" then
      local stamped = ("queue %.2f: %s"):format(now(), line)
      deps.say(stamped)
      deps.log(stamped)
    end
  end

  -- How long after the last finish this happened: printed on what went out,
  -- what started and what was refused, which together bracket the real lock.
  local function since_finish()
    if finished_at == nil then
      return ""
    end
    return (" +%.2fs after finish"):format(now() - finished_at)
  end

  local function running(until_at)
    return until_at ~= nil and now() < until_at
  end

  --- Nothing can be sent yet: an action is unanswered, casting, or locking.
  function self.busy()
    return running(sent_until) or running(acting_until) or running(lock_until)
  end

  --- A press or a release on its way out. Nothing says how soon `outgoing
  --- chunk` fires after one, and a second press inside that gap must not go
  --- straight out too.
  local function leaving(record)
    sent_until, sent_left, going = now() + LEAVE_BACKSTOP, false, record
  end

  local function answered()
    sent_until, going = nil, nil
  end

  --[[ A double tap: a weaponskill or an item has no recast to stop it, and held,
       the second tap would spend the TP or the item a second time. Asked only
       while the first is unanswered, so the same action pressed again once it
       is on its way is an ordinary press. ]]
  local function already_going(record)
    return running(sent_until)
      and going ~= nil
      and going.type == record.type
      and going.action == record.action
      and going.target == record.target
  end

  local function forget()
    held, going, sent_until, acting_until, lock_until, finished_at = nil, nil, nil, nil, nil, nil
  end

  --- What is held, or nil. Introspection.
  function self.held()
    return held
  end

  --- Lets go of what is held. The lock is the player's and carries on.
  function self.drop(reason)
    if held ~= nil then
      note("dropped " .. held.name .. ": " .. reason)
      held = nil
    end
  end

  --- A moment that ended everything: the lock goes with what is held.
  function self.clear(reason)
    if held ~= nil or self.busy() then
      note("cleared: " .. reason)
    end
    forget()
  end

  --[[ A bar's press, with the command it resolved to. Answers whether it was
       held: false sends it as it always was, which is every press made while
       nothing is busy. A press that is not held leaves one that is alone. ]]
  function self.press(record, command)
    if not self.enabled() or not HELD_TYPES[record.type] then
      return false
    end
    local name = record.action or record.type
    -- Asked first because it counts for nothing either way: a GearSwap filter
    -- may well cancel it, and nothing that follows should wait on that.
    if deps.recast_left(record) > 0 then
      note("not held: " .. name .. " on recast")
      return false
    end
    if not self.busy() then
      -- The lock can run out between two frames, with the release still owed.
      self.drop("replaced by " .. name)
      leaving(record)
      return false
    end
    local blocked = deps.blocked()
    if blocked ~= nil then
      note("not held: " .. name .. ", " .. blocked)
      return false
    end
    if already_going(record) then
      note("not held: " .. name .. ", already going")
      return false
    end
    local pinned = command
    if record.target ~= nil then
      pinned = deps.pin(command, record.target)
      if pinned == nil then
        note("not held: " .. name .. ", <" .. record.target .. "> cannot be pinned")
        return false
      end
    end
    note("hold " .. name .. (held ~= nil and ", replacing " .. held.name or ""))
    held = { name = name, record = record, command = pinned, at = now() }
    return true
  end

  --- A parsed 0x028.
  function self.on_action(act)
    if not self.enabled() or type(act) ~= "table" then
      return
    end
    local started, finished = START_KINDS[act.category], FINISH_KINDS[act.category]
    if started == nil and finished == nil then
      return
    end
    local player = deps.get_player()
    if player == nil or act.actor_id ~= player.id then
      return
    end
    answered()
    if started ~= nil and act.param ~= INTERRUPT_PARAM then
      note("start " .. started .. since_finish())
      acting_until = now() + FINISH_BACKSTOP
      lock_until = nil
      return
    end
    local lock = finished ~= nil and LOCK_SECONDS[finished] or LOCK_SECONDS.interrupted
    note(("%s, lock %.2fs"):format(finished ~= nil and "finish " .. finished or "interrupted " .. started, lock))
    acting_until = nil
    finished_at = now()
    lock_until = finished_at + lock
  end

  --- A raw 0x029. A refusal ends the wait for an answer and nothing else: if
  --- a lock is what refused it, that lock is still running.
  function self.on_message(data)
    if not self.enabled() or type(data) ~= "string" or #data < MESSAGE_OFFSET + 1 then
      return
    end
    local message = u16(data, MESSAGE_OFFSET) % 32768
    if not REFUSALS[message] then
      return
    end
    local player = deps.get_player()
    if player == nil or u32(data, ACTOR_OFFSET) ~= player.id then
      return
    end
    note("refused, message " .. message .. since_finish())
    answered()
  end

  --- A raw outgoing packet, whoever sent it: a bar, a macro, GearSwap.
  function self.on_outgoing(id, data)
    if (id ~= ACTION_OUT and id ~= ITEM_OUT) or not self.enabled() then
      return
    end
    local kind = "item"
    if id == ACTION_OUT then
      if type(data) ~= "string" or #data < CATEGORY_OFFSET + 1 then
        return
      end
      kind = OUTGOING_KINDS[u16(data, CATEGORY_OFFSET)]
      if kind == nil then
        return
      end
    end
    note("out " .. kind .. since_finish())
    sent_until, sent_left = now() + ANSWER_BACKSTOP, true
  end

  local function expire()
    local clock = now()
    if sent_until ~= nil and clock >= sent_until then
      answered()
      note(sent_left and "no answer to the last send" or "nothing went out for the last press")
    end
    if acting_until ~= nil and clock >= acting_until then
      acting_until = nil
      note("no finish for the last start")
      self.drop("no finish for the last start")
    end
    if lock_until ~= nil and clock >= lock_until then
      lock_until = nil
      note("lock over")
    end
  end

  --[[ Once per frame. Answers the command to send, or nil, and a release has
       only this one chance: what the game makes of it is the game's. ]]
  function self.step()
    if not self.enabled() then
      forget()
      return nil
    end
    expire()
    if held == nil then
      return nil
    end
    local blocked = deps.blocked()
    if blocked ~= nil then
      self.drop(blocked)
      return nil
    end
    if now() - held.at >= FINISH_BACKSTOP then
      self.drop("held too long")
      return nil
    end
    if self.busy() then
      return nil
    end
    if deps.recast_left(held.record) > 0 then
      self.drop("on recast")
      return nil
    end
    local release = held
    held = nil
    note(("release %s after %.2fs"):format(release.name, now() - release.at))
    leaving(release.record)
    return release.command
  end

  return self
end

return new
