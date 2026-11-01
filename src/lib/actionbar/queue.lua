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
     held press whose recast is running when the lock clears is dropped. A
     weaponskill under its TP goes nowhere, for want of anything to wait on. A
     cursor slot is judged the same way at OK, when its command is really sent,
     rather than at the press. ]]

--[[ The seconds after a finish before the next action goes: too long costs a
     moment and too short loses the press. These are the shipped lengths, and
     `//hud queue lock` stores a player's own over them, one kind at a time.

     `spell` is measured (Kevin's logs, 2026-10-31). The server answers on a 0.4s
     beat. A send that makes the beat near +2.8 after the finish is a coin toss
     (refused up to +2.58, accepted down to +2.19), and every send from +2.66 on
     makes the next one and was accepted. 3.0 lost a further beat as often as not.

     `weaponskill` is measured too: sends at +2.09 went one each way, shorter ones
     were refused, and all 27 releases at 2.4 were accepted.

     `interrupted` takes the spell's: after a real interrupt a send was refused up
     to +2.23 and accepted down to +2.01, and Selindrile's 1.75 lost the press.

     `ability` is measured: all 9 spells held at 0.4 started, about 0.8s sooner than
     at 1.0, and it ships a step above that.

     `item` rests on two samples: a spell +0.64 after one started and an ability
     +0.86 after one went, so it sits above them rather than at them.

     `ranged` is UNVERIFIED: Selindrile's is the only figure there is, and it is
     rounded up to a second.
     `//hud queue debug` brackets the real one. ]]
local LOCK_SECONDS = {
  spell = 2.7,
  weaponskill = 2.4,
  ability = 0.5,
  item = 1,
  ranged = 1,
  interrupted = 2.7,
}
-- The order `//hud queue lock` and the settings window list them in.
local LOCK_KINDS = { "spell", "weaponskill", "ability", "item", "ranged", "interrupted" }
-- What the command takes, the window steps through and a stored length is held to.
local LOCK_RANGE = { min = 0, max = 5, step = 0.1 }

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

-- GearSwap's st_targs: the targets the player picks with a cursor.
local CURSOR_TARGETS = { st = true, stpc = true, stal = true, stnpc = true, stpt = true }
-- The numbers the game has sent back when OK is pressed: see on_text.
local NUMBERS_AT_OK = 2
-- What any weaponskill takes.
local WEAPONSKILL_TP = 1000

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
local SPELL_FINISH = 4

local ACTION_OUT = 0x01A
local ITEM_OUT = 0x037
-- GearSwap's outgoing_action_category_table, and its 0x037 for an item.
local OUTGOING_KINDS = { [3] = "spell", [7] = "weaponskill", [9] = "ability", [16] = "ranged", [25] = "monster skill" }
-- 1-based, header included.
local CATEGORY_OFFSET = 11
local PARAM_OFFSET = 13
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

local function first_message(act)
  local target = type(act.targets) == "table" and act.targets[1] or nil
  local actions = type(target) == "table" and target.actions or nil
  local action = type(actions) == "table" and actions[1] or nil
  return type(action) == "table" and action.message or nil
end

local function new(deps)
  local self = { modes = MODES, lock_kinds = LOCK_KINDS, lock_range = LOCK_RANGE }

  local held = nil
  -- The press that last went out, for as long as nothing has answered it.
  local going = nil
  -- A cursor this opened, waiting for OK.
  local cursor = nil
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

  --- The length in force. Nothing is seeded, so a kind never set follows the
  --- shipped length, and a hand-broken one reads as it.
  function self.lock(kind)
    local live = deps.config()
    local stored = type(live) == "table" and live.queue_locks or nil
    local seconds = type(stored) == "table" and stored[kind] or nil
    if type(seconds) == "number" and seconds >= LOCK_RANGE.min and seconds <= LOCK_RANGE.max then
      return seconds
    end
    return LOCK_SECONDS[kind]
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

  --[[ A mash. Held, a second tap would spend a weaponskill's TP or an item
       again, since neither has a recast to stop it. Sent, it could only be
       refused, and GearSwap takes that refusal for the end of the cast and
       swaps out of the midcast set. So it goes nowhere. Asked only while the
       first is unanswered: the same action pressed again once it is on its way
       is an ordinary press. ]]
  local function already_going(record)
    return running(sent_until)
      and going ~= nil
      and going.type == record.type
      and going.action == record.action
      and going.target == record.target
  end

  --[[ No packet leaves for a weaponskill under its TP, so there is no answer to
       wait out, and held across one that spent the TP it cannot go (73 of 73 in
       Kevin's logs). A client that reports no TP leaves it to the game. ]]
  local function no_tp(record)
    if record.type ~= "ws" then
      return false
    end
    local player = deps.get_player()
    local vitals = player ~= nil and player.vitals or nil
    local tp = type(vitals) == "table" and vitals.tp or nil
    return type(tp) == "number" and tp < WEAPONSKILL_TP
  end

  local function forget()
    held, going, cursor = nil, nil, nil
    sent_until, acting_until, lock_until, finished_at = nil, nil, nil, nil
  end

  local function hold(name, record, command)
    note("hold " .. name .. (held ~= nil and ", replacing " .. held.name or ""))
    held = { name = name, record = record, command = command, at = now() }
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

  --[[ A cursor slot is judged at OK, when the command is really sent. Nothing
       can be said of it at the press: its target does not exist yet, its recast
       may be up by then, and a lock may have begun, since GearSwap sends
       weaponskills of its own. So the same cursor opens over /ta, free or busy,
       because GearSwap acts on a /ma the moment OK sends it and nothing after
       that can stop it, where it ignores a /ta.

       With an arrow already up the token raises no new one, and the game answers
       it "You cannot perform that action on the selected sub-target". OK would
       then be counted as the arrow, the /ta would run and nothing would cast, so
       nothing is sent and the press only changes what OK will cast. An arrow
       this did not open is a macro's, and its OK sends its own command. ]]
  local function open_cursor(record, command, name)
    local blocked = deps.blocked()
    if blocked ~= nil then
      note("not held: " .. name .. ", " .. blocked)
      return false
    end
    if deps.arrow_up() then
      if cursor == nil then
        return false
      end
      note("cursor up, OK takes " .. name)
      cursor.record, cursor.command, cursor.name, cursor.at = record, command, name, now()
      return true
    end
    note("cursor " .. name .. " <" .. record.target .. ">")
    cursor = { record = record, command = command, name = name, numbers = 0, at = now() }
    return true, "input /ta <" .. record.target .. ">"
  end

  --[[ A bar's press, with the command it resolved to. Answers whether it was
       taken: false sends it as it always was, which is every press made while
       nothing is busy, and a second answer is what to send in its place. A
       press that is not held leaves one that is alone. ]]
  function self.press(record, command)
    if not self.enabled() or not HELD_TYPES[record.type] then
      return false
    end
    local name = record.action or record.type
    if type(record.target) == "string" and CURSOR_TARGETS[record.target:lower()] then
      return open_cursor(record, command, name)
    end
    if no_tp(record) then
      note("swallowed " .. name .. ", no TP")
      return true
    end
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
      note("swallowed " .. name .. ", already going")
      return true
    end
    local pinned = command
    if record.target ~= nil then
      pinned = deps.pin(command, record.target)
      if pinned == nil then
        note("not held: " .. name .. ", <" .. record.target .. "> cannot be pinned")
        return false
      end
    end
    hold(name, record, pinned)
    return true
  end

  --[[ The outgoing text, for a cursor this opened. The game puts a cursor command
       back through here with a number for the token: the arrow's first id at once,
       which raises the arrow and must reach the game, then the chosen id on OK
       (Byrth; GearSwap's st_flag skips the first the same way). Answers true to
       keep the line from the game, so a /ta never moves your target, and a
       second answer is what to send now. ]]
  function self.on_text(text)
    if cursor == nil or type(text) ~= "string" then
      return false
    end
    local id = text:match("^/ta%a*%s+(%d+)%s*$")
    if id == nil then
      -- A token with no arrow up after ours means ours has gone, by ESC or
      -- otherwise, and the numbers to come are not ours. With one up the game
      -- refuses the token, and OK is still ours.
      if cursor.numbers > 0 and text:match("^/ta%a*%s+<") and not deps.arrow_up() then
        note("no OK for " .. cursor.name)
        cursor = nil
      end
      return false
    end
    cursor.numbers = cursor.numbers + 1
    if cursor.numbers < NUMBERS_AT_OK then
      note("arrow " .. id)
      return false
    end
    local open = cursor
    cursor = nil
    note("OK " .. open.name .. " at " .. id)
    if no_tp(open.record) then
      note("swallowed " .. open.name .. ", no TP")
      return true
    end
    local aimed = open.command:gsub("<[^<>]*>$", id)
    if deps.recast_left(open.record) > 0 then
      note("not held: " .. open.name .. " on recast")
      return true, aimed
    end
    if not self.busy() then
      self.drop("replaced by " .. open.name)
      leaving(open.record)
      return true, aimed
    end
    hold(open.name, open.record, aimed)
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
    --[[ A spell finish with no cast running is not one: a cast always sends its
         start first. These came a melee round apart while Kevin was paralyzed,
         and sends straight after them were accepted, so nothing locks. ]]
    if act.category == SPELL_FINISH and not running(acting_until) then
      local message = first_message(act)
      note("ignored a finish with no cast running" .. (message ~= nil and ", message " .. message or ""))
      return
    end
    answered()
    if started ~= nil and act.param ~= INTERRUPT_PARAM then
      note("start " .. started .. since_finish())
      acting_until = now() + FINISH_BACKSTOP
      lock_until = nil
      return
    end
    local lock = self.lock(finished or "interrupted")
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
    local kind, name = "item", ""
    if id == ACTION_OUT then
      if type(data) ~= "string" or #data < CATEGORY_OFFSET + 1 then
        return
      end
      kind = OUTGOING_KINDS[u16(data, CATEGORY_OFFSET)]
      if kind == nil then
        return
      end
      local action = #data > PARAM_OFFSET and u16(data, PARAM_OFFSET) or 0
      if action ~= 0 then
        name = " " .. tostring(deps.name_of(kind, action) or action)
      end
    end
    note("out " .. kind .. name .. since_finish())
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
    -- Never with its arrow up: its OK is still to come, and with no cursor to
    -- catch it the /ta would move your target.
    if cursor ~= nil and clock - cursor.at >= FINISH_BACKSTOP and not deps.arrow_up() then
      note("no OK for " .. cursor.name)
      cursor = nil
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
    if no_tp(held.record) then
      self.drop("no TP")
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
