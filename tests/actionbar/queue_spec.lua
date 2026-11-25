local new_queue = require("lib/actionbar/queue")

local ME = 777
local SOMEONE = 888
local MOB = 17000001

local MAGIC, WEAPONSKILL, ABILITY, RANGED = 3, 7, 9, 16
local INTERRUPTED = 28787
local STARTING = 24931

local function world(opts)
  opts = opts or {}
  local env = {
    now = 100,
    mode = opts.mode or "on",
    player = { id = ME },
    log = {},
    recast = {},
    names = {},
    casts = { spell = {}, item = {} },
    blocked = nil,
    pins = {},
    -- The id under each target token, and how often the queue asked for one.
    targets = { t = 12345 },
    target_asks = 0,
    -- The word of the game's own that names a mob now, beside <t> for what
    -- is under it, and how often the queue asked for one.
    words = { [ME] = "me" },
    aims = 0,
  }
  -- `pinned` stands for what <t> holds where a spec sets it.
  local function under_t()
    return env.pinned or env.targets.t
  end
  local queue = new_queue({
    no_packets = opts.no_packets,
    now = function()
      return env.now
    end,
    config = function()
      return { queue = env.mode, queue_locks = env.locks }
    end,
    get_player = function()
      return env.player
    end,
    log = function(line)
      env.log[#env.log + 1] = line
    end,
    recast_left = function(record)
      return env.recast[record.action] or 0
    end,
    pin = function(_, target)
      if target == "me" then
        return true
      end
      if target == "t" then
        local id = under_t()
        return id ~= nil, id
      end
      return false
    end,
    aim = function(command, id)
      env.aims = env.aims + 1
      local word = env.words[id] or (id == under_t() and "t") or nil
      if word == nil then
        return nil
      end
      return (command:gsub("<[^<>]*>$", "<" .. word .. ">")), word
    end,
    blocked = function()
      return env.blocked
    end,
    name_of = function(_, id)
      return env.names[id]
    end,
    cast_seconds = function(kind, id)
      return env.casts[kind] ~= nil and env.casts[kind][id] or nil
    end,
    arrow_up = function()
      return env.arrow_up == true
    end,
    target_id = function(token)
      env.target_asks = env.target_asks + 1
      return env.targets[token]
    end,
    -- What the client's mob table would say, which the queue must not ask.
    dead = opts.dead,
    -- AutoSpellTier's walk, where a spec stands one in.
    lower = opts.lower,
  })
  return queue, env
end

local function logged(env)
  return table.concat(env.log, "\n")
end

local function spell(name, target)
  return { type = "ma", action = name or "Cure", target = target or "me" }
end

local function command(name)
  return 'input /ma "' .. (name or "Cure") .. '" <me>'
end

local function action(category, param, actor)
  return { actor_id = actor or ME, category = category, param = param or 0, targets = {} }
end

local function start_cast(queue)
  queue.on_action(action(8, STARTING))
end

-- A start naming what it starts, where the game puts the spell or item id.
local function start_of(category, id)
  local start = action(category, STARTING)
  start.targets = { { actions = { { param = id } } } }
  return start
end

-- A cast's finish, with the start the game always sends ahead of one.
local function finish_cast(queue)
  start_cast(queue)
  queue.on_action(action(4, 1))
end

-- What the game sends for a melee round lost to paralysis, or for no cast at all.
local function paralyzed_round(message)
  local round = action(4, 0)
  round.targets = { { actions = { { message = message or 84 } } } }
  return round
end

-- What the game sends when a weaponskill that has started cannot land: too far away.
local function too_far()
  local finish = action(4, 0)
  finish.targets = { { actions = { { message = 78 } } } }
  return finish
end

-- A weaponskill's start, naming who it is aimed at.
local function weaponskill_at(target)
  local start = start_of(7, 42)
  start.targets[1].id = target
  return start
end

-- A raw outgoing 0x01A with its target's id at 0x04, its category at 0x0A and
-- its param at 0x0C.
local function outgoing_action(category, param, target)
  param = param or 0
  target = target or 0
  local low, high = category % 256, math.floor(category / 256)
  return string.rep("\0", 4)
    .. string.char(target % 256, math.floor(target / 256) % 256, math.floor(target / 65536) % 256)
    .. string.char(math.floor(target / 16777216))
    .. string.rep("\0", 2)
    .. string.char(low, high)
    .. string.char(param % 256, math.floor(param / 256))
    .. string.rep("\0", 14)
end

-- A raw incoming 0x029: the actor at 0x04, the message at 0x18.
local function battle_message(actor, message)
  local function u32(value)
    return string.char(value % 256, math.floor(value / 256) % 256, math.floor(value / 65536) % 256, 0)
  end
  return string.rep("\0", 4)
    .. u32(actor)
    .. string.rep("\0", 16)
    .. string.char(message % 256, math.floor(message / 256))
    .. string.rep("\0", 2)
end

-- A raw incoming 0x029 saying `target` fell: the actor at 0x04, the target at
-- 0x08, the message at 0x18.
local function fall_message(target, message, actor)
  local function u32(value)
    return string.char(
      value % 256,
      math.floor(value / 256) % 256,
      math.floor(value / 65536) % 256,
      math.floor(value / 16777216)
    )
  end
  message = message or 6
  return string.rep("\0", 4)
    .. u32(actor or SOMEONE)
    .. u32(target)
    .. string.rep("\0", 12)
    .. string.char(message % 256, math.floor(message / 256))
    .. string.rep("\0", 2)
end

-- The game's word that `target` fell, which is all the queue takes for a death.
local function falls(queue, target)
  queue.on_message(fall_message(target))
end

-- A 0x063 of the ninth order as the entry point's one parse hands it over: the
-- buffs on you by slot, with 255 in the empty ones.
local function buff_update(ids, order)
  local parsed = { Order = order or 9 }
  for slot = 1, 32 do
    parsed["Buffs " .. slot] = ids[slot] or 255
  end
  return parsed
end

-- A raw incoming 0x053: its parameter at 0x04, its message at 0x0C.
local function system_message(message, param)
  param = param or 0
  return string.rep("\0", 4)
    .. string.char(param % 256, math.floor(param / 256) % 256, 0, 0)
    .. string.rep("\0", 4)
    .. string.char(message % 256, math.floor(message / 256))
    .. string.rep("\0", 2)
end

-- A raw incoming 0x058: whose target it sets at 0x04 and the target at 0x08,
-- with the two indexes after them.
local function target_packet(player, target)
  local function u32(value)
    return string.char(
      value % 256,
      math.floor(value / 256) % 256,
      math.floor(value / 65536) % 256,
      math.floor(value / 16777216)
    )
  end
  return string.rep("\0", 4) .. u32(player) .. u32(target) .. string.rep("\0", 4)
end

-- A melee round of `actor`'s, landing on `target`.
local function round_at(target, actor)
  local round = action(1, 0, actor)
  round.targets = { { id = target, actions = { { message = 1 } } } }
  return round
end

describe("the action queue", function()
  describe("its mode", function()
    it("ships on, and reads a broken value as off", function()
      local queue, env = world({ mode = "off" })
      assert.are.same({ queue = "on" }, queue.defaults())
      assert.are.equal("off", queue.mode())
      assert.is_false(queue.enabled())
      env.mode = "sometimes"
      assert.are.equal("off", queue.mode())
      assert.is_false(queue.enabled())
      env.mode = 1
      assert.are.equal("off", queue.mode())
    end)

    it("is off with no packets coming, whatever the file says", function()
      local queue = world({ mode = "on", no_packets = true })
      assert.are.equal("off", queue.mode())
      assert.is_false(queue.enabled())
    end)

    it("is on in on and in debug", function()
      local queue, env = world({ mode = "on" })
      assert.are.equal("on", queue.mode())
      assert.is_true(queue.enabled())
      env.mode = "debug"
      assert.are.equal("debug", queue.mode())
      assert.is_true(queue.enabled())
    end)

    it("offers the words its mode reads", function()
      local queue = world()
      assert.are.same({ "off", "on", "debug" }, queue.modes)
    end)
  end)

  describe("the lock lengths", function()
    it("lists its kinds in the order the settings window shows them", function()
      local queue = world()
      assert.are.same({ "spell", "weaponskill", "ability", "item", "ranged", "interrupted" }, queue.lock_kinds)
    end)

    it("answers the shipped length with nothing stored", function()
      local queue = world()
      assert.are.equal(2.7, queue.lock("spell"))
      assert.are.equal(2.4, queue.lock("weaponskill"))
      assert.are.equal(0.5, queue.lock("ability"))
      assert.are.equal(1, queue.lock("item"))
      assert.are.equal(1, queue.lock("ranged"))
      assert.are.equal(2.7, queue.lock("interrupted"))
    end)

    it("answers a stored length over the shipped one, kind by kind", function()
      local queue, env = world()
      env.locks = { spell = 2.5 }
      assert.are.equal(2.5, queue.lock("spell"))
      assert.are.equal(2.4, queue.lock("weaponskill"))
    end)

    it("takes zero as a length, since it is one", function()
      local queue, env = world()
      env.locks = { ability = 0 }
      assert.are.equal(0, queue.lock("ability"))
    end)

    for name, broken in pairs({
      text = "soon",
      negative = -1,
      ["too long"] = 5.1,
      infinite = math.huge,
      ["not a number"] = 0 / 0,
    }) do
      it("reads a stored length that is " .. name .. " as the shipped one", function()
        local queue, env = world()
        env.locks = { spell = broken }
        assert.are.equal(2.7, queue.lock("spell"))
      end)
    end

    it("reads a stored table that is not one as nothing stored", function()
      local queue, env = world()
      env.locks = "broken"
      assert.are.equal(2.7, queue.lock("spell"))
    end)

    it("locks for the stored length", function()
      local queue, env = world()
      env.locks = { spell = 1.2 }
      finish_cast(queue)
      env.now = env.now + 1.19
      assert.is_true(queue.busy())
      env.now = env.now + 0.02
      assert.is_false(queue.busy())
    end)

    it("locks an interrupt for its own stored length", function()
      local queue, env = world()
      env.locks = { interrupted = 0.5 }
      start_cast(queue)
      queue.on_action(action(8, INTERRUPTED))
      env.now = env.now + 0.51
      assert.is_false(queue.busy())
    end)

    it("reads the length at the finish, so a change takes on the next one", function()
      local queue, env = world()
      finish_cast(queue)
      env.locks = { spell = 1 }
      assert.are.equal(1, queue.lock("spell"))
      env.now = env.now + 1.01
      assert.is_true(queue.busy(), "the lock already running keeps its length")
      finish_cast(queue)
      env.now = env.now + 1.01
      assert.is_false(queue.busy())
    end)

    it("says the length in force in debug", function()
      local queue, env = world({ mode = "debug" })
      env.locks = { spell = 2.5 }
      finish_cast(queue)
      assert.is_not_nil(logged(env):find("finish spell, lock 2.50s", 1, true))
    end)
  end)

  describe("a press while nothing is busy", function()
    it("is not held, so it goes out as it always did", function()
      local queue = world()
      assert.is_false(queue.press(spell(), command()))
      assert.is_nil(queue.held())
    end)

    it("makes the queue busy until something answers", function()
      local queue = world()
      queue.press(spell(), command())
      assert.is_true(queue.busy())
    end)

    it("never touches anything while off", function()
      local queue = world({ mode = "off" })
      assert.is_false(queue.press(spell(), command()))
      assert.is_false(queue.busy())
    end)

    it("does not make the queue busy for a press on its own recast, which GearSwap may cancel", function()
      local queue, env = world()
      env.recast.Cure = 4
      assert.is_false(queue.press(spell("Cure"), command("Cure")))
      assert.is_false(queue.busy())
    end)

    it("leaves what was held alone for a press on its own recast", function()
      local queue, env = world()
      finish_cast(queue)
      queue.press(spell("Cure"), command("Cure"))
      env.now = env.now + 3.01
      env.recast.Stone = 4
      assert.is_false(queue.press(spell("Stone"), command("Stone")))
      assert.are.equal(command("Cure"), queue.held().command)
    end)

    it("replaces what was held, if the lock ran out between two frames", function()
      local queue, env = world()
      finish_cast(queue)
      queue.press(spell("Cure"), command("Cure"))
      env.now = env.now + 3.01
      assert.is_false(queue.press(spell("Stone"), command("Stone")))
      assert.is_nil(queue.held())
    end)
  end)

  describe("a press while busy", function()
    it("is held through the cast", function()
      local queue = world()
      start_cast(queue)
      assert.is_true(queue.press(spell(), command()))
      assert.are.equal(command(), queue.held().command)
    end)

    it("is held through the lock", function()
      local queue, env = world()
      finish_cast(queue)
      env.now = env.now + 1
      assert.is_true(queue.press(spell(), command()))
    end)

    it("is held while the last action has not been answered", function()
      local queue = world()
      queue.press(spell("Cure"), command("Cure"))
      assert.is_true(queue.press(spell("Stone"), command("Stone")))
    end)

    --[[ A double tap on a weaponskill or an item has no recast to stop it, and
         held, the second tap would spend the TP or the item a second time. ]]
    it("swallows a second press of what is still unanswered, and sends nothing", function()
      local queue = world()
      local blade = { type = "ws", action = "Savage Blade", target = "t" }
      queue.press(blade, 'input /ws "Savage Blade" <t>')
      assert.is_true(queue.press(blade, 'input /ws "Savage Blade" <t>'))
      assert.is_nil(queue.held())
    end)

    it("swallows a second press of what was just released", function()
      local queue, env = world()
      finish_cast(queue)
      queue.press(spell("Cure"), command("Cure"))
      env.now = env.now + 3.01
      queue.step()
      assert.is_true(queue.press(spell("Cure"), command("Cure")))
      assert.is_nil(queue.held())
    end)

    it("holds the same action again once the first has been answered", function()
      local queue = world()
      queue.press(spell("Cure"), command("Cure"))
      start_cast(queue)
      assert.is_true(queue.press(spell("Cure"), command("Cure")))
    end)

    it("forgets what was going once a packet answers it, so a later send cannot revive it", function()
      local queue = world()
      queue.press(spell("Cure"), command("Cure"))
      finish_cast(queue)
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      assert.is_true(queue.press(spell("Cure"), command("Cure")))
    end)

    it("forgets what was going once it is refused", function()
      local queue = world()
      queue.press(spell("Cure"), command("Cure"))
      queue.on_message(battle_message(ME, 17))
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      assert.is_true(queue.press(spell("Cure"), command("Cure")))
    end)

    it("forgets what was going once the wait for an answer runs out", function()
      local queue, env = world()
      queue.press(spell("Cure"), command("Cure"))
      env.now = env.now + 2.01
      queue.step()
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      assert.is_true(queue.press(spell("Cure"), command("Cure")))
    end)

    it("holds the same action at another target", function()
      local queue = world()
      queue.press(spell("Cure", "me"), command("Cure"))
      assert.is_true(queue.press(spell("Cure", "t"), 'input /ma "Cure" <t>'))
    end)

    it("replaces what was held", function()
      local queue = world()
      start_cast(queue)
      queue.press(spell("Cure"), command("Cure"))
      queue.press(spell("Stone"), command("Stone"))
      assert.are.equal(command("Stone"), queue.held().command)
    end)

    for _, kind in ipairs({ "ma", "ja", "ws", "pet", "item", "ra" }) do
      it("holds a " .. kind, function()
        local queue = world()
        start_cast(queue)
        assert.is_true(queue.press({ type = kind, action = "Thing", target = "me" }, "input /thing"))
      end)
    end

    for _, kind in ipairs({
      "ct",
      "ex",
      "open",
      "mount",
      "mr",
      "warp",
      "draw",
      "jc",
      "enchanteditem",
      "sneak",
      "invisible",
      "reraise",
    }) do
      it("never holds a " .. kind, function()
        local queue = world()
        start_cast(queue)
        assert.is_false(queue.press({ type = kind, action = "Thing", target = "me" }, "input /thing"))
        assert.is_nil(queue.held())
      end)
    end

    it("leaves what was held alone when it is not held itself", function()
      local queue = world()
      start_cast(queue)
      queue.press(spell("Cure"), command("Cure"))
      queue.press({ type = "ct", action = "p hello" }, "input /p hello")
      assert.are.equal(command("Cure"), queue.held().command)
    end)

    it("does not hold a press whose own recast is running", function()
      local queue, env = world()
      start_cast(queue)
      env.recast.Cure = 4
      assert.is_false(queue.press(spell("Cure"), command("Cure")))
      assert.is_nil(queue.held())
    end)

    --[[ Cure IV went again at +2.72 every time, and all 16 presses made in its own
         lock went out on its recast and were refused. ]]
    describe("whose recast ends inside the lock", function()
      it("is held, the wait being the lock's", function()
        local queue, env = world()
        finish_cast(queue)
        env.recast.Cure = 1
        assert.is_true((queue.press(spell("Cure"), command("Cure"))))
        assert.are.equal(command("Cure"), queue.held().command)
      end)

      it("goes when the lock clears", function()
        local queue, env = world()
        finish_cast(queue)
        env.recast.Cure = 1
        queue.press(spell("Cure"), command("Cure"))
        env.recast.Cure = 0
        env.now = env.now + 2.71
        assert.are.equal(command("Cure"), queue.step())
      end)

      it("is dropped if its recast is still running more than two seconds on then", function()
        local queue, env = world()
        finish_cast(queue)
        env.recast.Cure = 1
        queue.press(spell("Cure"), command("Cure"))
        env.recast.Cure = 2.01
        env.now = env.now + 2.71
        assert.is_nil(queue.step())
        assert.is_nil(queue.held())
      end)

      it("is held when the two end together", function()
        local queue, env = world()
        finish_cast(queue)
        env.recast.Cure = 2.7
        assert.is_true((queue.press(spell("Cure"), command("Cure"))))
      end)

      it("measures against what is left of the lock", function()
        local queue, env = world()
        finish_cast(queue)
        env.now = env.now + 2
        env.recast.Cure = 2.71
        assert.is_false(queue.press(spell("Cure"), command("Cure")))
        assert.is_nil(queue.held())
      end)

      it("replaces what was held, as any held press does", function()
        local queue, env = world()
        finish_cast(queue)
        queue.press(spell("Stone"), command("Stone"))
        env.recast.Cure = 1
        queue.press(spell("Cure"), command("Cure"))
        assert.are.equal(command("Cure"), queue.held().command)
      end)

      it("is held during a cast when its recast is within two seconds, the lock being still to come", function()
        local queue, env = world()
        start_cast(queue)
        env.recast.Cure = 2
        assert.is_true((queue.press(spell("Cure"), command("Cure"))))
      end)

      it("is not held during a cast when its recast is longer, the cast's end being unknown", function()
        local queue, env = world()
        start_cast(queue)
        env.recast.Cure = 2.01
        assert.is_false(queue.press(spell("Cure"), command("Cure")))
      end)

      it("is not held with no lock running", function()
        local queue, env = world()
        env.recast.Cure = 1
        assert.is_false(queue.press(spell("Cure"), command("Cure")))
        assert.is_false(queue.busy())
      end)
    end)

    --[[ Shell V cast on target after target: its own recast ends a little after
         the lock, and a press sent on it at +2.45 was refused by the lock (Kevin,
         2026-11-07). Within two seconds of the lock it waits for the recast too. ]]
    describe("whose recast ends within two seconds of the lock", function()
      it("is held", function()
        local queue, env = world()
        finish_cast(queue)
        env.now = env.now + 2.43
        env.recast.Cure = 1.2
        assert.is_true((queue.press(spell("Cure"), command("Cure"))))
        assert.are.equal(command("Cure"), queue.held().command)
      end)

      -- Shell V's recast without haste ended 1.28 to 1.31s after the lock, eleven
      -- times of eleven (Kevin, 2026-11-08), and every one was refused.
      it("is held when its recast ends 1.3s after the lock", function()
        local queue, env = world()
        finish_cast(queue)
        env.recast.Cure = 4
        assert.is_true((queue.press(spell("Cure"), command("Cure"))))
        assert.are.equal(command("Cure"), queue.held().command)
      end)

      it("is dropped when its recast is more than 2s off as the lock ends", function()
        local queue, env = world()
        finish_cast(queue)
        env.recast.Cure = 4
        queue.press(spell("Cure"), command("Cure"))
        env.now = env.now + 2.71
        env.recast.Cure = 2.01
        assert.is_nil(queue.step())
        assert.is_nil(queue.held())
      end)

      it("is held when its recast ends exactly 2s after the lock", function()
        local queue, env = world()
        finish_cast(queue)
        env.recast.Cure = ((env.now + 2.7) - env.now) + 2
        assert.is_true((queue.press(spell("Cure"), command("Cure"))))
      end)

      it("waits when its recast is exactly 2s off as the lock ends", function()
        local queue, env = world()
        start_cast(queue)
        queue.press(spell("Cure"), command("Cure"))
        finish_cast(queue)
        env.now = env.now + 2.71
        env.recast.Cure = 2
        assert.is_nil(queue.step())
        assert.are.equal(command("Cure"), queue.held().command)
      end)

      it("waits out the recast once the lock is over", function()
        local queue, env = world()
        finish_cast(queue)
        env.recast.Cure = 3.5
        queue.press(spell("Cure"), command("Cure"))
        env.now = env.now + 2.71
        env.recast.Cure = 0.79
        assert.is_nil(queue.step())
        assert.are.equal(command("Cure"), queue.held().command)
        env.now = env.now + 0.79
        env.recast.Cure = 0
        assert.are.equal(command("Cure"), queue.step())
      end)

      --[[ Read as idle while it waited, a mash of the slot went out and could
           be accepted, and the held press then went too, into the cast. ]]
      it("takes a re-press while it waits on its recast, sending nothing", function()
        local queue, env = world()
        finish_cast(queue)
        env.recast.Cure = 1
        queue.press(spell("Cure"), command("Cure"))
        env.now = env.now + 2.71
        env.recast.Cure = 0.1
        queue.step()
        assert.is_true((queue.press(spell("Cure"), command("Cure"))))
        assert.are.equal(command("Cure"), queue.held().command)
      end)

      it("takes a re-press made as the lock ends, before the next frame", function()
        local queue, env = world()
        finish_cast(queue)
        env.recast.Cure = 1
        queue.press(spell("Cure"), command("Cure"))
        env.now = env.now + 2.71
        env.recast.Cure = 0.5
        assert.is_true((queue.press(spell("Cure"), command("Cure"))))
        assert.are.equal(command("Cure"), queue.held().command)
      end)

      it("is replaced while it waits by a newer press with no recast", function()
        local queue, env = world()
        finish_cast(queue)
        env.recast.Cure = 1
        queue.press(spell("Cure"), command("Cure"))
        env.now = env.now + 2.71
        env.recast.Cure = 0.5
        queue.step()
        assert.is_true((queue.press(spell("Stone"), command("Stone"))))
        assert.are.equal(command("Stone"), queue.step())
      end)

      it("leaves a newer press on a longer recast to the game while it waits", function()
        local queue, env = world()
        finish_cast(queue)
        env.recast.Cure = 1
        queue.press(spell("Cure"), command("Cure"))
        env.now = env.now + 2.71
        env.recast.Cure = 0.5
        queue.step()
        env.recast.Stone = 2.01
        assert.is_false(queue.press(spell("Stone"), command("Stone")))
        assert.are.equal(command("Cure"), queue.held().command)
      end)

      it("is not held further out than that", function()
        local queue, env = world()
        finish_cast(queue)
        env.recast.Cure = 4.71
        assert.is_false(queue.press(spell("Cure"), command("Cure")))
        assert.is_nil(queue.held())
      end)
    end)

    it("holds a press as it was typed, beside the id its target stood for", function()
      local queue = world()
      start_cast(queue)
      queue.press(spell("Stone", "t"), 'input /ma "Stone" <t>')
      assert.are.equal('input /ma "Stone" <t>', queue.held().command)
      assert.are.equal(12345, queue.held().target)
    end)

    it("does not hold a target it cannot pin", function()
      local queue = world()
      start_cast(queue)
      assert.is_false(queue.press(spell("Stone", "ft"), 'input /ma "Stone" <ft>'))
      assert.is_nil(queue.held())
    end)

    it("holds a slot with no target, verbatim", function()
      local queue = world()
      start_cast(queue)
      assert.is_true(queue.press({ type = "ma", action = "Stone" }, 'input /ma "Stone"'))
      assert.are.equal('input /ma "Stone"', queue.held().command)
    end)

    it("does not hold under a config mode or suppression", function()
      local queue, env = world()
      start_cast(queue)
      env.blocked = "edit mode"
      assert.is_false(queue.press(spell(), command()))
      assert.is_nil(queue.held())
    end)
  end)

  --[[ A cursor slot is judged at OK, when the command is really sent. The game
       puts a cursor command back through the outgoing text twice with a number
       where the token was: the arrow's first id at once, which raises it, and the
       chosen id on OK. ]]
  describe("a cursor slot", function()
    local SHELL = spell("Shell V", "stpc")
    local SHELL_COMMAND = 'input /ma "Shell V" <stpc>'
    -- 12345 is what <t> holds in these, so that is the word its pick goes under.
    local AIMED = 'input /ma "Shell V" <t>'

    -- The press and the arrow, leaving the cursor waiting for OK.
    local function cursor_up(queue)
      local taken, instead = queue.press(SHELL, SHELL_COMMAND)
      queue.on_text("/ta <stpc>")
      queue.on_text("/ta 777")
      return taken, instead
    end

    --[[ Kevin's Sleep II, pressed while free and OK'd in a lock nobody could have
         seen coming: GearSwap had sent a weaponskill in between. It went out at
         +1.80 and was refused. ]]
    it("opens over /ta while nothing is busy too, so OK is caught whenever it comes", function()
      local queue = world()
      local taken, instead = queue.press(SHELL, SHELL_COMMAND)
      assert.is_true(taken)
      assert.are.equal("input /ta <stpc>", instead)
    end)

    it("starts no wait at the press, since nothing has been sent", function()
      local queue = world()
      queue.press(SHELL, SHELL_COMMAND)
      assert.is_false(queue.busy())
    end)

    it("holds at OK when the lock began after the press", function()
      local queue = world()
      cursor_up(queue)
      finish_cast(queue)
      local swallowed, send = queue.on_text("/ta 12345")
      assert.is_true(swallowed)
      assert.is_nil(send)
      assert.are.equal(SHELL_COMMAND, queue.held().command)
    end)

    --[[ Kevin's Dia III and Sleep II: a second press raised no arrow, so OK was
         counted as one, the /ta ran and nothing cast. The game answers such a
         press "You cannot perform that action on the selected sub-target". ]]
    it("sends nothing for a press with the arrow already up", function()
      local queue, env = world()
      finish_cast(queue)
      cursor_up(queue)
      env.arrow_up = true
      local taken, instead = queue.press(SHELL, SHELL_COMMAND)
      assert.is_true(taken)
      assert.is_nil(instead)
    end)

    it("still reads OK as OK after one", function()
      local queue, env = world()
      finish_cast(queue)
      cursor_up(queue)
      env.arrow_up = true
      queue.press(SHELL, SHELL_COMMAND)
      queue.press(SHELL, SHELL_COMMAND)
      assert.is_true((queue.on_text("/ta 12345")))
      assert.are.equal(SHELL_COMMAND, queue.held().command)
    end)

    it("casts the newest press at OK when another slot is pressed with the arrow up", function()
      local queue, env = world()
      finish_cast(queue)
      cursor_up(queue)
      env.arrow_up = true
      queue.press(spell("Protect V", "stpc"), 'input /ma "Protect V" <stpc>')
      queue.on_text("/ta 12345")
      assert.are.equal('input /ma "Protect V" <stpc>', queue.held().command)
    end)

    it("gives a mashed cursor its full wait for OK", function()
      local queue, env = world()
      start_cast(queue)
      cursor_up(queue)
      env.arrow_up = true
      env.now = env.now + 20
      queue.press(SHELL, SHELL_COMMAND)
      env.now = env.now + 20
      env.arrow_up = false
      queue.step()
      assert.is_true((queue.on_text("/ta 12345")))
    end)

    --[[ Kevin's Dia III in Al Zahbi (2026-11-10): sent under an arrow it did not
         open, the press was refused ("You cannot perform that action on the
         selected sub-target"), GearSwap kept the st_flag it had set for it, and
         the next cursor's OK reached the game unparsed: "A command error occurred". ]]
    it("sends nothing for a press under an arrow it did not open", function()
      local queue, env = world()
      env.arrow_up = true
      local taken, instead = queue.press(SHELL, SHELL_COMMAND)
      assert.is_true(taken)
      assert.is_nil(instead)
    end)

    it("leaves that arrow's OK to whoever opened it", function()
      local queue, env = world()
      env.arrow_up = true
      queue.press(SHELL, SHELL_COMMAND)
      assert.is_false((queue.on_text("/ta 777")))
      assert.is_false((queue.on_text("/ta 12345")))
      assert.is_nil(queue.held())
    end)

    it("opens the same cursor over /ta while busy, which GearSwap ignores", function()
      local queue = world()
      start_cast(queue)
      local taken, instead = queue.press(SHELL, SHELL_COMMAND)
      assert.is_true(taken)
      assert.are.equal("input /ta <stpc>", instead)
      assert.is_nil(queue.held())
    end)

    for _, token in ipairs({ "st", "stpc", "stnpc", "stal", "stpt" }) do
      it("treats <" .. token .. "> as a cursor", function()
        local queue = world()
        start_cast(queue)
        local _, instead = queue.press(spell("Shell V", token), 'input /ma "Shell V" <' .. token .. ">")
        assert.are.equal("input /ta <" .. token .. ">", instead)
      end)
    end

    it("matches a token in any case", function()
      local queue = world()
      start_cast(queue)
      local _, instead = queue.press(spell("Shell V", "STPC"), 'input /ma "Shell V" <STPC>')
      assert.are.equal("input /ta <STPC>", instead)
    end)

    it("asks no recast at the press, since it may be up by OK", function()
      local queue, env = world()
      start_cast(queue)
      env.recast["Shell V"] = 4
      assert.is_true((queue.press(SHELL, SHELL_COMMAND)))
    end)

    it("lets the token and the arrow reach the game, or no cursor opens", function()
      local queue = world()
      start_cast(queue)
      queue.press(SHELL, SHELL_COMMAND)
      assert.is_false(queue.on_text("/ta <stpc>"))
      assert.is_false(queue.on_text("/ta 777"))
    end)

    it("takes OK, so the /ta never changes your target, and holds the action for the chosen id", function()
      local queue = world()
      finish_cast(queue)
      cursor_up(queue)
      local swallowed, send = queue.on_text("/ta 12345")
      assert.is_true(swallowed)
      assert.is_nil(send)
      assert.are.equal(SHELL_COMMAND, queue.held().command)
      assert.are.equal(12345, queue.held().target)
    end)

    it("reads the long form of the command too", function()
      local queue = world()
      finish_cast(queue)
      cursor_up(queue)
      assert.is_true((queue.on_text("/target 12345")))
    end)

    it("takes yourself, whose id is the arrow's too", function()
      local queue = world()
      finish_cast(queue)
      cursor_up(queue)
      assert.is_true((queue.on_text("/ta 777")))
      assert.are.equal(ME, queue.held().target)
    end)

    it("releases what OK held the tick the lock clears", function()
      local queue, env = world()
      finish_cast(queue)
      cursor_up(queue)
      queue.on_text("/ta 12345")
      env.now = env.now + 2.69
      assert.is_nil(queue.step())
      env.now = env.now + 0.02
      assert.are.equal(AIMED, queue.step())
    end)

    it("sends at OK if the lock has already cleared", function()
      local queue, env = world()
      finish_cast(queue)
      cursor_up(queue)
      env.now = env.now + 3.01
      queue.step()
      local swallowed, send = queue.on_text("/ta 12345")
      assert.is_true(swallowed)
      assert.are.equal(AIMED, send)
      assert.is_nil(queue.held())
      assert.is_true(queue.busy(), "and waits for its answer")
    end)

    it("judges the recast at OK, sending it to be refused as any press on recast is", function()
      local queue, env = world()
      finish_cast(queue)
      cursor_up(queue)
      env.recast["Shell V"] = 5
      local swallowed, send = queue.on_text("/ta 12345")
      assert.is_true(swallowed)
      assert.are.equal(AIMED, send)
      assert.is_nil(queue.held())
    end)

    it("holds at OK a spell whose recast ends inside the lock", function()
      local queue, env = world()
      finish_cast(queue)
      cursor_up(queue)
      env.recast["Shell V"] = 1
      local swallowed, send = queue.on_text("/ta 12345")
      assert.is_true(swallowed)
      assert.is_nil(send)
      assert.are.equal(SHELL_COMMAND, queue.held().command)
    end)

    it("holds at OK a spell whose recast ends within two seconds of the lock", function()
      local queue, env = world()
      finish_cast(queue)
      cursor_up(queue)
      env.now = env.now + 2.43
      env.recast["Shell V"] = 1.2
      local swallowed, send = queue.on_text("/ta 12345")
      assert.is_true(swallowed)
      assert.is_nil(send)
      assert.are.equal(SHELL_COMMAND, queue.held().command)
    end)

    it("sends OK at once on a recast with nothing busy, and the queue stays free", function()
      local queue, env = world()
      cursor_up(queue)
      env.recast["Shell V"] = 0.5
      local swallowed, send = queue.on_text("/ta 12345")
      assert.is_true(swallowed)
      assert.are.equal(AIMED, send)
      assert.is_false(queue.busy())
    end)

    it("replaces at OK a press waiting on its recast, the newest winning", function()
      local queue, env = world()
      finish_cast(queue)
      queue.press(spell("Cure"), command("Cure"))
      cursor_up(queue)
      env.recast.Cure = 0.5
      env.now = env.now + 2.71
      queue.step()
      env.recast["Shell V"] = 0.5
      local swallowed, send = queue.on_text("/ta 12345")
      assert.is_true(swallowed)
      assert.is_nil(send)
      assert.are.equal(SHELL_COMMAND, queue.held().command)
    end)

    it("replaces what was held at OK, not at the press: the newest command wins", function()
      local queue = world()
      finish_cast(queue)
      queue.press(spell("Cure"), command("Cure"))
      cursor_up(queue)
      assert.are.equal(command("Cure"), queue.held().command)
      queue.on_text("/ta 12345")
      assert.are.equal(SHELL_COMMAND, queue.held().command)
    end)

    it("starts over for a press once the arrow has gone", function()
      local queue = world()
      finish_cast(queue)
      cursor_up(queue)
      local _, instead = queue.press(spell("Protect V", "stpc"), 'input /ma "Protect V" <stpc>')
      assert.are.equal("input /ta <stpc>", instead)
      assert.is_false(queue.on_text("/ta 777"), "the new cursor's arrow")
      queue.on_text("/ta 12345")
      assert.are.equal('input /ma "Protect V" <stpc>', queue.held().command)
    end)

    it("takes one OK and goes back to leaving /ta alone", function()
      local queue = world()
      finish_cast(queue)
      cursor_up(queue)
      queue.on_text("/ta 12345")
      assert.is_false(queue.on_text("/ta 67890"))
    end)

    it("ignores every other line while a cursor is up", function()
      local queue, env = world()
      finish_cast(queue)
      cursor_up(queue)
      env.arrow_up = true
      assert.is_false(queue.on_text("/p hello 12345"))
      assert.is_false(queue.on_text("/ta <t>"))
      assert.is_false(queue.on_text("/ta 12345 now"))
      assert.is_false(queue.on_text(nil))
      assert.is_true((queue.on_text("/ta 12345")), "and OK is still OK")
    end)

    it("keeps its cursor through another's token with its arrow up, which the game refuses", function()
      local queue, env = world()
      finish_cast(queue)
      cursor_up(queue)
      env.arrow_up = true
      assert.is_false(queue.on_text("/ta <stnpc>"))
      assert.is_true((queue.on_text("/ta 12345")))
    end)

    it("gives a cursor up when another opens after its arrow: the game has closed ours", function()
      local queue = world()
      start_cast(queue)
      cursor_up(queue)
      assert.is_false(queue.on_text("/ta <stnpc>"))
      assert.is_false(queue.on_text("/ta 777"), "that cursor's arrow")
      assert.is_false(queue.on_text("/ta 12345"), "and its OK are not ours")
      assert.is_nil(queue.held())
    end)

    it("does not give a cursor up for its own token, which comes before the arrow", function()
      local queue = world()
      finish_cast(queue)
      queue.press(SHELL, SHELL_COMMAND)
      queue.on_text("/ta <stpc>")
      queue.on_text("/ta 777")
      assert.is_true((queue.on_text("/ta 12345")))
    end)

    --[[ A token that raises no arrow leaves nothing to OK. Kept for its 30s,
         such a cursor took the arrow and the OK of the next /ta cursor anyone
         opened, and cast its own spell there. ]]
    it("gives a cursor up when its token has raised no arrow", function()
      local queue, env = world()
      finish_cast(queue)
      queue.press(SHELL, SHELL_COMMAND)
      queue.on_text("/ta <stpc>")
      env.now = env.now + 2.01
      queue.step()
      assert.is_false(queue.on_text("/ta <stnpc>"))
      assert.is_false(queue.on_text("/ta 777"), "another cursor's arrow")
      assert.is_false(queue.on_text("/ta 12345"), "and its OK are not ours")
      assert.is_nil(queue.held())
    end)

    it("waits that long for its arrow", function()
      local queue, env = world()
      finish_cast(queue)
      queue.press(SHELL, SHELL_COMMAND)
      env.now = env.now + 1.99
      queue.step()
      queue.on_text("/ta 777")
      assert.is_true((queue.on_text("/ta 12345")))
    end)

    it("keeps a cursor that has counted no arrow while one is up", function()
      local queue, env = world()
      finish_cast(queue)
      queue.press(SHELL, SHELL_COMMAND)
      env.arrow_up = true
      env.now = env.now + 2.01
      queue.step()
      queue.on_text("/ta 777")
      assert.is_true((queue.on_text("/ta 12345")))
    end)

    it("replaces what was held if OK lands after the lock ran out between two frames", function()
      local queue, env = world()
      finish_cast(queue)
      queue.press(spell("Cure"), command("Cure"))
      cursor_up(queue)
      env.now = env.now + 3.01
      local _, send = queue.on_text("/ta 12345")
      assert.are.equal(AIMED, send)
      assert.is_nil(queue.held())
    end)

    it("leaves /ta alone when no cursor of ours is up", function()
      local queue = world()
      assert.is_false(queue.on_text("/ta 12345"))
    end)

    it("forgets a cursor nobody confirmed", function()
      local queue, env = world()
      start_cast(queue)
      cursor_up(queue)
      env.now = env.now + 30.01
      queue.step()
      assert.is_false(queue.on_text("/ta 12345"))
    end)

    it("keeps a cursor past the backstop for as long as its arrow is up", function()
      local queue, env = world()
      cursor_up(queue)
      env.arrow_up = true
      env.now = env.now + 30.01
      queue.step()
      local swallowed, send = queue.on_text("/ta 12345")
      assert.is_true(swallowed)
      assert.are.equal(AIMED, send)
    end)

    it("forgets it the tick its arrow goes, once past the backstop", function()
      local queue, env = world()
      cursor_up(queue)
      env.arrow_up = true
      env.now = env.now + 30.01
      queue.step()
      env.arrow_up = false
      queue.step()
      assert.is_false(queue.on_text("/ta 12345"))
    end)

    it("forgets the cursor on a clear", function()
      local queue = world()
      start_cast(queue)
      cursor_up(queue)
      queue.clear("zone")
      assert.is_false(queue.on_text("/ta 12345"))
    end)

    it("does not open one under a config mode or suppression", function()
      local queue, env = world()
      start_cast(queue)
      env.blocked = "edit mode"
      local taken, instead = queue.press(SHELL, SHELL_COMMAND)
      assert.is_false(taken)
      assert.is_nil(instead)
    end)

    it("does nothing while off", function()
      local queue = world({ mode = "off" })
      local taken, instead = queue.press(SHELL, SHELL_COMMAND)
      assert.is_false(taken)
      assert.is_nil(instead)
    end)

    --[[ The pick comes back as an id, which only GearSwap reads (Kevin,
         2026-11-25), so the cast goes under a word of the game's own that
         names the pick. Which word does is the action service's to say. ]]
    describe("the word its pick goes under", function()
      -- Neither yourself nor what <t> holds.
      local PICK = 23456
      local OK = "/ta " .. PICK

      it("sends at OK under a word that names the pick", function()
        local queue, env = world()
        cursor_up(queue)
        env.words[PICK] = "lastst"
        local swallowed, send = queue.on_text(OK)
        assert.is_true(swallowed)
        assert.are.equal('input /ma "Shell V" <lastst>', send)
      end)

      it("goes under <me> for yourself", function()
        local queue = world()
        cursor_up(queue)
        local _, send = queue.on_text("/ta " .. ME)
        assert.are.equal('input /ma "Shell V" <me>', send)
      end)

      --[[ Nothing says when the game takes its pick for <lastst>: before the
           line comes through here, or once this has answered. ]]
      it("waits a frame where nothing names the pick yet, keeping the /ta from the game", function()
        local queue, env = world()
        cursor_up(queue)
        local swallowed, send = queue.on_text(OK)
        assert.is_true(swallowed)
        assert.is_nil(send)
        env.words[PICK] = "lastst"
        assert.are.equal('input /ma "Shell V" <lastst>', queue.step())
        assert.is_true(queue.busy(), "and waits for its answer")
      end)

      it("sends a pick it waited a frame for once", function()
        local queue, env = world()
        cursor_up(queue)
        queue.on_text(OK)
        env.words[PICK] = "lastst"
        queue.step()
        assert.is_nil(queue.step())
        assert.is_nil(queue.held(), "and is not judged a second time, which would hold it")
      end)

      it("sends a pick on its recast under its word, to be refused as any press on recast is", function()
        local queue, env = world()
        cursor_up(queue)
        env.words[PICK] = "lastst"
        env.recast["Shell V"] = 5
        local _, send = queue.on_text(OK)
        assert.are.equal('input /ma "Shell V" <lastst>', send)
      end)

      it("drops a pick on its recast that nothing names, and counts no send for it", function()
        local queue, env = world({ mode = "debug" })
        cursor_up(queue)
        env.recast["Shell V"] = 5
        queue.on_text(OK)
        assert.is_nil(queue.step())
        assert.is_not_nil(logged(env):find("dropped Shell V: nothing names 23456", 1, true), logged(env))
        assert.is_nil(logged(env):find("not held: Shell V on recast", 1, true), logged(env))
      end)

      it("goes nowhere when nothing names the pick a frame later", function()
        local queue, env = world()
        cursor_up(queue)
        queue.on_text(OK)
        assert.is_nil(queue.step())
        assert.is_nil(queue.held())
        assert.is_false(queue.busy())
        env.words[PICK] = "lastst"
        assert.is_nil(queue.step(), "and is not tried again")
      end)

      it("leaves what was held alone for a pick that went nowhere", function()
        local queue, env = world()
        finish_cast(queue)
        queue.press(spell("Cure"), command("Cure"))
        cursor_up(queue)
        env.now = env.now + 3.01
        queue.on_text(OK)
        assert.are.equal(command("Cure"), queue.step())
      end)

      it("holds a pick it waited a frame for, where a lock is running", function()
        local queue = world()
        finish_cast(queue)
        cursor_up(queue)
        queue.on_text(OK)
        assert.is_nil(queue.held())
        assert.is_nil(queue.step())
        assert.are.equal(SHELL_COMMAND, queue.held().command)
        assert.are.equal(PICK, queue.held().target)
      end)

      it("holds a pick nothing names, since a word may name it by the release", function()
        local queue, env = world()
        finish_cast(queue)
        cursor_up(queue)
        queue.on_text(OK)
        queue.step()
        env.words[PICK] = "t"
        env.now = env.now + 2.71
        assert.are.equal(AIMED, queue.step())
      end)

      it("names a held pick at the release, not at OK", function()
        local queue, env = world()
        finish_cast(queue)
        cursor_up(queue)
        env.words[PICK] = "lastst"
        queue.on_text(OK)
        env.words[PICK] = "p2"
        env.now = env.now + 2.71
        assert.are.equal('input /ma "Shell V" <p2>', queue.step())
      end)

      it("drops a held pick nothing names at the release", function()
        local queue, env = world()
        finish_cast(queue)
        cursor_up(queue)
        env.words[PICK] = "lastst"
        queue.on_text(OK)
        env.words[PICK] = nil
        env.now = env.now + 2.71
        assert.is_nil(queue.step())
        assert.is_nil(queue.held())
        assert.is_false(queue.busy())
      end)

      it("forgets a pick waiting its frame on a clear", function()
        local queue, env = world()
        cursor_up(queue)
        queue.on_text(OK)
        queue.clear("zone")
        env.words[PICK] = "lastst"
        assert.is_nil(queue.step())
      end)

      it("forgets one with the queue switched off", function()
        local queue, env = world()
        cursor_up(queue)
        queue.on_text(OK)
        env.mode = "off"
        queue.step()
        env.mode = "on"
        env.words[PICK] = "lastst"
        assert.is_nil(queue.step())
      end)

      it("says in debug the word the pick went under", function()
        local queue, env = world({ mode = "debug" })
        cursor_up(queue)
        env.words[PICK] = "lastst"
        queue.on_text(OK)
        assert.is_not_nil(logged(env):find("Shell V aimed at <lastst>", 1, true), logged(env))
      end)

      it("says in debug that a pick waits a frame for a word", function()
        local queue, env = world({ mode = "debug" })
        cursor_up(queue)
        queue.on_text(OK)
        assert.is_not_nil(logged(env):find("nothing names 23456 yet", 1, true), logged(env))
      end)

      it("says in debug what <t> and <lastst> read for a pick that went nowhere", function()
        local queue, env = world({ mode = "debug" })
        cursor_up(queue)
        env.targets.lastst = 777
        queue.on_text(OK)
        queue.step()
        assert.is_not_nil(
          logged(env):find("dropped Shell V: nothing names 23456 (<t> 12345, <lastst> 777)", 1, true),
          logged(env)
        )
      end)
    end)
  end)

  --[[ Kevin, 2026-11-25: on a job whose GearSwap file had not loaded, four held
       weaponskills reached the game as `/ws "Slice" 17555873` and each drew "A
       command error occurred". Only GearSwap reads an id, so a held press goes
       under a word the game reads itself, and nowhere with none. ]]
  describe("a held press aimed at a target", function()
    local STONE = spell("Stone", "t")
    local STONE_COMMAND = 'input /ma "Stone" <t>'

    -- Pressed in a cast at 12345, with that cast's lock just over.
    local function held_through_a_lock(opts)
      local queue, env = world(opts)
      start_cast(queue)
      queue.press(STONE, STONE_COMMAND)
      queue.on_action(action(4, 1))
      env.now = env.now + 2.71
      return queue, env
    end

    it("goes as it was typed while that word still names its target", function()
      local queue = held_through_a_lock()
      assert.are.equal(STONE_COMMAND, queue.step())
    end)

    it("goes under another word once the one it was typed with has moved on", function()
      local queue, env = held_through_a_lock()
      env.targets.t = 5
      env.words[12345] = "p1"
      assert.are.equal('input /ma "Stone" <p1>', queue.step())
      assert.is_true(queue.busy(), "and waits for its answer")
    end)

    it("is dropped when no word names its target any more", function()
      local queue, env = held_through_a_lock()
      env.targets.t = 5
      assert.is_nil(queue.step())
      assert.is_nil(queue.held())
      assert.is_false(queue.busy())
    end)

    it("asks no word for a press pinned to nothing", function()
      local queue, env = world()
      start_cast(queue)
      queue.press(spell(), command())
      queue.on_action(action(4, 1))
      env.now = env.now + 2.71
      assert.are.equal(command(), queue.step())
      assert.are.equal(0, env.aims)
    end)

    it("says in debug the word it went under where that is not the one typed", function()
      local queue, env = held_through_a_lock({ mode = "debug" })
      env.targets.t = 5
      env.words[12345] = "p1"
      queue.step()
      assert.is_not_nil(logged(env):find("Stone aimed at <p1>", 1, true), logged(env))
    end)

    it("says nothing of the word for a press that went as typed", function()
      local queue, env = held_through_a_lock({ mode = "debug" })
      queue.step()
      assert.is_nil(logged(env):find("aimed at", 1, true), logged(env))
    end)

    it("says in debug what <t> and <lastst> read when nothing names its target", function()
      local queue, env = held_through_a_lock({ mode = "debug" })
      env.targets.t = 5
      queue.step()
      assert.is_not_nil(
        logged(env):find("dropped Stone: nothing names 12345 (<t> 5, <lastst> none)", 1, true),
        logged(env)
      )
    end)

    it("reads neither word with debug off", function()
      local queue, env = held_through_a_lock()
      env.targets.t = 5
      local asked = env.target_asks
      queue.step()
      assert.are.equal(asked, env.target_asks)
    end)
  end)

  describe("the packets", function()
    it("makes a cast busy, and only its finish ends that", function()
      local queue, env = world()
      start_cast(queue)
      env.now = env.now + 20
      assert.is_true(queue.busy())
    end)

    it("reads the four start categories' interrupts as a lock", function()
      for _, category in ipairs({ 7, 8, 9, 12 }) do
        local queue, env = world()
        queue.on_action(action(category, STARTING))
        queue.on_action(action(category, INTERRUPTED))
        env.now = env.now + 2.69
        assert.is_true(queue.busy(), category .. " still locked")
        env.now = env.now + 0.02
        assert.is_false(queue.busy(), category .. " lock over")
      end
    end)

    it("ignores everybody else's", function()
      local queue = world()
      queue.on_action(action(8, STARTING, SOMEONE))
      queue.on_action(action(4, 1, SOMEONE))
      assert.is_false(queue.busy())
    end)

    it("ignores a melee round", function()
      local queue = world()
      queue.on_action(action(1, 0))
      assert.is_false(queue.busy())
    end)

    it("reads an action as nobody's while the client names no player", function()
      local queue, env = world()
      env.player = nil
      assert.has_no.errors(function()
        start_cast(queue)
      end)
      assert.is_false(queue.busy())
    end)

    it("reads a refusal as nobody's while the client names no player", function()
      local queue, env = world()
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      env.player = nil
      assert.has_no.errors(function()
        queue.on_message(battle_message(ME, 17))
      end)
      assert.is_true(queue.busy())
    end)

    it("reads a malformed packet as nothing", function()
      local queue = world()
      assert.has_no.errors(function()
        queue.on_action(nil)
        queue.on_action("not a table")
        queue.on_message(nil)
        queue.on_message("short")
        queue.on_outgoing(0x01A, nil)
        queue.on_outgoing(0x01A, "short")
      end)
      assert.is_false(queue.busy())
    end)

    it("hears nothing while off", function()
      local queue, env = world({ mode = "off" })
      start_cast(queue)
      queue.on_outgoing(0x037, "item use")
      assert.is_false(queue.busy())
      env.mode = "on"
      assert.is_false(queue.busy())
    end)

    local LOCKS = {
      { category = 2, seconds = 1.0, name = "ranged" },
      { category = 3, seconds = 2.4, name = "weaponskill" },
      { category = 4, seconds = 2.7, name = "spell" },
      { category = 5, seconds = 1.0, name = "item" },
      { category = 6, seconds = 0.5, name = "ability" },
      { category = 11, seconds = 2.4, name = "weaponskill" },
      { category = 14, seconds = 0.5, name = "ability" },
      { category = 15, seconds = 0.5, name = "ability" },
    }
    for _, lock in ipairs(LOCKS) do
      it("locks " .. lock.seconds .. "s after category " .. lock.category, function()
        local queue, env = world()
        start_cast(queue)
        queue.on_action(action(lock.category, 1))
        env.now = env.now + lock.seconds - 0.01
        assert.is_true(queue.busy())
        env.now = env.now + 0.02
        assert.is_false(queue.busy())
      end)
    end

    --[[ Three of Kevin's sends went out +0.68, +1.23 and +1.49 after a category 4
         that had no start, all accepted, so nothing locks after one. They came
         a melee round apart while he was paralyzed. ]]
    it("reads a category 4 with no cast running as no finish at all", function()
      local queue = world()
      queue.on_action(paralyzed_round())
      assert.is_false(queue.busy())
    end)

    --[[ Kevin's lag (2026-11-06) lost seven starts whose finishes came, each a
         real cast, and the next send went into its lock: a Refresh III refused,
         a Cure IV that went unanswered. A spell that went out keeps the bar busy
         for its cast time, and a finish inside that is its own. ]]
    describe("a spell that went out but whose start was lost", function()
      local HASTE_II = 511

      local function haste_out(queue, env)
        env.casts.spell[HASTE_II] = 3
        queue.on_outgoing(0x01A, outgoing_action(MAGIC, HASTE_II))
      end

      it("keeps the bar busy for its cast time and the server's beat", function()
        local queue, env = world()
        haste_out(queue, env)
        env.now = env.now + 3.39
        assert.is_true(queue.busy())
        env.now = env.now + 0.02
        assert.is_false(queue.busy())
      end)

      it("keeps the bar busy the 2s an answer gets when the cast is shorter", function()
        local queue, env = world()
        env.casts.spell[HASTE_II] = 1
        queue.on_outgoing(0x01A, outgoing_action(MAGIC, HASTE_II))
        env.now = env.now + 1.99
        assert.is_true(queue.busy())
      end)

      it("keeps the 2s an answer gets when the cast time is unknown", function()
        local queue, env = world()
        queue.on_outgoing(0x01A, outgoing_action(MAGIC, 999))
        env.now = env.now + 1.99
        assert.is_true(queue.busy())
        env.now = env.now + 0.02
        assert.is_false(queue.busy())
      end)

      it("takes a finish inside the cast time for its own and locks", function()
        local queue, env = world()
        haste_out(queue, env)
        env.now = env.now + 2.36
        queue.on_action(action(4, HASTE_II))
        env.now = env.now + 2.69
        assert.is_true(queue.busy())
        env.now = env.now + 0.02
        assert.is_false(queue.busy())
      end)

      it("holds a press through the cast and its lock and then sends it", function()
        local queue, env = world()
        haste_out(queue, env)
        env.now = env.now + 2
        assert.is_true(queue.press(spell("Refresh III"), command("Refresh III")))
        env.now = env.now + 0.36
        queue.on_action(action(4, HASTE_II))
        assert.is_nil(queue.step())
        env.now = env.now + 2.69
        assert.is_nil(queue.step())
        env.now = env.now + 0.02
        assert.are.equal(command("Refresh III"), queue.step())
      end)

      it("takes the stored spell lock when a start's wait runs out", function()
        local queue, env = world()
        env.casts.spell[HASTE_II] = 3
        env.locks = { spell = 1.2 }
        queue.on_action(start_of(8, HASTE_II))
        env.now = env.now + 3.4
        queue.step()
        env.now = env.now + 1.19
        assert.is_true(queue.busy())
        env.now = env.now + 0.02
        assert.is_false(queue.busy())
      end)

      --[[ Kevin's log (2026-11-07): a Cure IV went out while he was paralyzed,
           and a finish came 0.49s later, ahead of its start, and locked. A
           finish answers what went out only when it names that spell. ]]
      it("ignores a finish naming another spell, and the wait ends on time", function()
        local queue, env = world()
        haste_out(queue, env)
        env.now = env.now + 2.36
        queue.on_action(action(4, 1))
        env.now = env.now + 1.05
        assert.is_false(queue.busy())
      end)

      it("ignores a paralyzed round inside the cast time", function()
        local queue, env = world()
        haste_out(queue, env)
        env.now = env.now + 2.36
        queue.on_action(paralyzed_round())
        env.now = env.now + 1.05
        assert.is_false(queue.busy())
      end)

      it("is ended at once by a refusal", function()
        local queue, env = world()
        haste_out(queue, env)
        queue.on_message(battle_message(ME, 17))
        assert.is_false(queue.busy())
      end)

      it("ignores a finish after the cast time", function()
        local queue, env = world()
        haste_out(queue, env)
        env.now = env.now + 3.41
        queue.on_action(action(4, HASTE_II))
        assert.is_false(queue.busy())
      end)

      it("ignores a finish after a refusal", function()
        local queue, env = world()
        haste_out(queue, env)
        queue.on_message(battle_message(ME, 17))
        queue.on_action(action(4, HASTE_II))
        assert.is_false(queue.busy())
      end)

      it("ignores a spell finish while what went out was not a spell", function()
        local queue, env = world()
        queue.on_outgoing(0x01A, outgoing_action(ABILITY, HASTE_II))
        queue.on_action(action(4, HASTE_II))
        env.now = env.now + 2.01
        assert.is_false(queue.busy())
      end)

      it("takes no finish as the answer to a spell sent without its id", function()
        local queue, env = world()
        queue.on_outgoing(0x01A, outgoing_action(MAGIC))
        env.now = env.now + 1.5
        queue.on_action(paralyzed_round())
        env.now = env.now + 0.51
        assert.is_false(queue.busy())
      end)

      it("ignores a spell finish once a later press is on its way instead", function()
        local queue, env = world()
        haste_out(queue, env)
        queue.on_message(battle_message(ME, 17))
        queue.press({ type = "ja", action = "Composure", target = "me" }, "input /ja Composure <me>")
        queue.on_action(action(4, HASTE_II))
        env.now = env.now + 0.61
        assert.is_false(queue.busy())
      end)
    end)

    it("leaves a held press alone through one", function()
      local queue, env = world()
      finish_cast(queue)
      queue.press(spell(), command())
      env.now = env.now + 2
      queue.on_action(paralyzed_round())
      env.now = env.now + 0.71
      assert.are.equal(command(), queue.step(), "the lock it did not extend has cleared")
    end)

    it("goes on waiting for an answer through one", function()
      local queue = world()
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      queue.on_action(paralyzed_round())
      assert.is_true(queue.busy())
    end)

    it("takes the interrupt's lock when a paralyzed cast's finish comes first", function()
      local queue, env = world()
      env.locks = { interrupted = 1 }
      start_cast(queue)
      queue.on_action(action(4, 1))
      queue.on_action(action(8, INTERRUPTED))
      env.now = env.now + 1.01
      assert.is_false(queue.busy())
    end)

    it("keeps the interrupt's lock when the finish comes after it", function()
      local queue, env = world()
      env.locks = { interrupted = 1 }
      start_cast(queue)
      queue.on_action(action(8, INTERRUPTED))
      queue.on_action(action(4, 1))
      env.now = env.now + 1.01
      assert.is_false(queue.busy())
    end)

    it("still takes a weaponskill's finish with no start to its name", function()
      local queue = world()
      queue.on_action(action(3, 42))
      assert.is_true(queue.busy())
    end)

    it("measures the lock from the finish, whatever the cast took", function()
      local queue, env = world()
      start_cast(queue)
      env.now = env.now + 12
      finish_cast(queue)
      env.now = env.now + 2.69
      assert.is_true(queue.busy())
      env.now = env.now + 0.02
      assert.is_false(queue.busy())
    end)

    for _, category in ipairs({ MAGIC, WEAPONSKILL, ABILITY, RANGED, 25 }) do
      it("counts outgoing action category " .. category, function()
        local queue = world()
        queue.on_outgoing(0x01A, outgoing_action(category))
        assert.is_true(queue.busy())
      end)
    end

    for _, category in ipairs({ 2, 4, 12, 15 }) do
      it("does not count outgoing category " .. category .. ", which is not an action", function()
        local queue = world()
        queue.on_outgoing(0x01A, outgoing_action(category))
        assert.is_false(queue.busy())
      end)
    end

    it("counts an item going out", function()
      local queue = world()
      queue.on_outgoing(0x037, "item use")
      assert.is_true(queue.busy())
    end)

    it("ignores every other outgoing packet", function()
      local queue = world()
      queue.on_outgoing(0x015, outgoing_action(MAGIC))
      assert.is_false(queue.busy())
    end)

    it("counts a macro's cast as much as a bar's", function()
      local queue = world()
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      assert.is_true(queue.press(spell(), command()))
    end)

    for _, message in ipairs({ 17, 18, 55, 56, 87, 88, 89, 90, 78, 34 }) do
      it("ends the wait for an answer on refusal " .. message, function()
        local queue = world()
        queue.on_outgoing(0x01A, outgoing_action(MAGIC))
        queue.on_message(battle_message(ME, message))
        assert.is_false(queue.busy())
      end)
    end

    it("masks the message's top bit, as GearSwap does", function()
      local queue = world()
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      queue.on_message(battle_message(ME, 17 + 32768))
      assert.is_false(queue.busy())
    end)

    it("ignores somebody else's refusal", function()
      local queue = world()
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      queue.on_message(battle_message(SOMEONE, 17))
      assert.is_true(queue.busy())
    end)

    it("ignores a message that is not a refusal", function()
      local queue = world()
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      queue.on_message(battle_message(ME, 94))
      assert.is_true(queue.busy())
    end)

    it("leaves the lock running through a refusal", function()
      local queue, env = world()
      finish_cast(queue)
      env.now = env.now + 1
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      queue.on_message(battle_message(ME, 17))
      assert.is_true(queue.busy())
      env.now = env.now + 2.01
      assert.is_false(queue.busy())
    end)

    --[[ Kevin, 2026-11-12: AutoTrust cast a Trust with the party full, the queue
         saw no refusal, and each such cast held the bar 2.4s, ten times in one
         run. These are LandSandBoat's six system messages for a Trust not
         called, the last four of them GearSwap's too; that they are what the
         game sends is unverified here. ]]
    describe("a Trust cast the game refuses", function()
      local TRUST = 900

      for _, message in ipairs({ 296, 297, 298, 299, 300, 301 }) do
        it("ends the wait for the spell that went out on system message " .. message, function()
          local queue = world()
          queue.on_outgoing(0x01A, outgoing_action(MAGIC, TRUST))
          queue.on_system_message(system_message(message))
          assert.is_false(queue.busy())
        end)
      end

      it("lets a press held behind that cast go", function()
        local queue = world()
        queue.on_outgoing(0x01A, outgoing_action(MAGIC, TRUST))
        assert.is_true(queue.press(spell(), command()))
        queue.on_system_message(system_message(298))
        assert.are.equal(command(), queue.step())
      end)

      it("takes no other system message for one", function()
        local queue = world()
        queue.on_outgoing(0x01A, outgoing_action(MAGIC, TRUST))
        queue.on_system_message(system_message(295))
        queue.on_system_message(system_message(302))
        assert.is_true(queue.busy())
      end)

      it("ends no wait but a spell's", function()
        local queue = world()
        queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42))
        queue.on_system_message(system_message(298))
        assert.is_true(queue.busy())
      end)

      it("leaves a press that has not left the client yet waiting", function()
        local queue = world()
        assert.is_false(queue.press(spell(), command()))
        queue.on_system_message(system_message(298))
        assert.is_true(queue.busy())
      end)

      it("ends no cast that has started", function()
        local queue = world()
        queue.on_outgoing(0x01A, outgoing_action(MAGIC, TRUST))
        queue.on_action(start_of(8, TRUST))
        queue.on_system_message(system_message(298))
        assert.is_true(queue.busy())
      end)

      it("leaves the lock running", function()
        local queue, env = world()
        finish_cast(queue)
        env.now = env.now + 1
        queue.on_outgoing(0x01A, outgoing_action(MAGIC, TRUST))
        queue.on_system_message(system_message(298))
        assert.is_true(queue.busy())
        -- Past the lock, and still inside the 2s that cast would have been waited on.
        env.now = env.now + 1.71
        assert.is_false(queue.busy())
      end)

      it("hears nothing while the queue is off", function()
        local queue, env = world()
        queue.on_outgoing(0x01A, outgoing_action(MAGIC, TRUST))
        env.mode = "off"
        queue.on_system_message(system_message(298))
        env.mode = "on"
        assert.is_true(queue.busy())
      end)
    end)
  end)

  describe("the backstops", function()
    it("gives a press a moment to leave, since GearSwap may cancel it", function()
      local queue, env = world()
      queue.press(spell(), command())
      env.now = env.now + 0.59
      queue.step()
      assert.is_true(queue.busy())
      env.now = env.now + 0.02
      queue.step()
      assert.is_false(queue.busy())
    end)

    it("waits for the answer in full once the press has left", function()
      local queue, env = world()
      queue.press(spell(), command())
      env.now = env.now + 0.5
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      env.now = env.now + 1.99
      queue.step()
      assert.is_true(queue.busy())
      env.now = env.now + 0.02
      queue.step()
      assert.is_false(queue.busy())
    end)

    it("gives a release the same moment to leave", function()
      local queue, env = world()
      finish_cast(queue)
      queue.press(spell(), command())
      env.now = env.now + 3.01
      queue.step()
      env.now = env.now + 0.61
      queue.step()
      assert.is_false(queue.busy())
    end)

    it("stops waiting for a finish that never came", function()
      local queue, env = world()
      start_cast(queue)
      env.now = env.now + 30.01
      queue.step()
      assert.is_false(queue.busy())
    end)

    it("waits on a spell's finish for its cast time and one server beat, then its lock", function()
      local queue, env = world()
      env.casts.spell[511] = 3
      queue.on_action(start_of(8, 511))
      env.now = env.now + 6.09
      queue.step()
      assert.is_true(queue.busy())
      env.now = env.now + 0.02
      queue.step()
      assert.is_false(queue.busy())
    end)

    it("still locks on a finish that lands after that wait", function()
      local queue, env = world()
      env.casts.spell[511] = 3
      queue.on_action(start_of(8, 511))
      env.now = env.now + 4
      queue.step()
      queue.on_action(action(4, 511))
      env.now = env.now + 2.2
      queue.step()
      assert.is_true(queue.busy())
    end)

    it("takes that wait's end for a finish, and sends what it held after the lock", function()
      local queue, env = world()
      env.casts.spell[511] = 3
      queue.on_action(start_of(8, 511))
      queue.press(spell(), command())
      env.now = env.now + 3.41
      assert.is_nil(queue.step())
      assert.is_not_nil(queue.held())
      env.now = env.now + 2.7
      assert.are.equal(command(), queue.step())
    end)

    it("holds a press that lands after that wait but before the next tick", function()
      local queue, env = world()
      env.casts.spell[511] = 3
      queue.on_action(start_of(8, 511))
      env.now = env.now + 3.41
      assert.is_true(queue.press(spell(), command()))
    end)

    it("lets a finish that lands after that wait replace the lock it was given", function()
      local queue, env = world()
      env.casts.spell[511] = 3
      queue.on_action(start_of(8, 511))
      env.now = env.now + 3.41
      queue.step()
      env.now = env.now + 1
      queue.on_action(action(4, 511))
      env.now = env.now + 2.69
      queue.step()
      assert.is_true(queue.busy())
    end)

    --[[ Once that wait has locked and the lock has cleared, the bar is idle,
         and a stray finish must not lock it again (Kevin, 2026-11-07). ]]
    local function past_the_wait(queue, env)
      env.casts.spell[511] = 3
      queue.on_action(start_of(8, 511))
      env.now = env.now + 3.41
      queue.step()
      env.now = env.now + 2.71
      queue.step()
    end

    it("ignores a finish naming another spell once that wait has locked", function()
      local queue, env = world()
      past_the_wait(queue, env)
      queue.on_action(action(4, 1))
      assert.is_false(queue.busy())
    end)

    it("ignores a paralyzed round once that wait has locked", function()
      local queue, env = world()
      past_the_wait(queue, env)
      queue.on_action(paralyzed_round())
      assert.is_false(queue.busy())
    end)

    it("takes a finish naming the started spell once that wait has locked", function()
      local queue, env = world()
      past_the_wait(queue, env)
      queue.on_action(action(4, 511))
      assert.is_true(queue.busy())
    end)

    it("takes any finish while the cast is still running", function()
      local queue, env = world()
      env.casts.spell[511] = 3
      queue.on_action(start_of(8, 511))
      env.now = env.now + 1
      queue.on_action(action(4, 1))
      env.now = env.now + 2.69
      assert.is_true(queue.busy())
      env.now = env.now + 0.02
      assert.is_false(queue.busy(), "the finish's own lock, not the start's wait")
    end)

    --[[ A paralysis round is a spell finish naming no spell. One arriving while
         a cast runs would start the lock early and close the window on the real
         finish (Kevin, 2026-11-08). ]]
    it("ignores a finish naming no spell while the cast is still running", function()
      local queue, env = world()
      env.casts.spell[511] = 3
      queue.on_action(start_of(8, 511))
      env.now = env.now + 1
      queue.on_action(action(4, 0))
      env.now = env.now + 2.71
      assert.is_true(queue.busy(), "still the start's wait")
      env.now = env.now + 2.5
      queue.step()
      assert.is_false(queue.busy(), "the start's wait and its lock are over")
      queue.on_action(action(4, 511))
      assert.is_true(queue.busy(), "the real finish locks")
    end)

    --[[ The server answers a weaponskill that started and then could not land
         with a finish naming no spell. Ignored as a paralysis round, it held
         the bar for the start's whole wait and a lock on top (Kevin, 2026-11-10). ]]
    it("ends a weaponskill on a finish naming no spell, and sends what it held after the weaponskill lock", function()
      local queue, env = world()
      queue.on_action(start_of(7, 42))
      queue.press(spell(), command())
      env.now = env.now + 0.02
      queue.on_action(too_far())
      env.now = env.now + 2.39
      assert.is_nil(queue.step())
      env.now = env.now + 0.02
      assert.are.equal(command(), queue.step())
    end)

    it("takes the weaponskill lock as set when a finish naming no spell ends one", function()
      local queue, env = world()
      env.locks = { weaponskill = 1 }
      queue.on_action(start_of(7, 42))
      queue.on_action(too_far())
      env.now = env.now + 0.99
      queue.step()
      assert.is_true(queue.busy())
      env.now = env.now + 0.02
      queue.step()
      assert.is_false(queue.busy())
    end)

    it("ends a weaponskill on any finish naming no spell, a paralysis round's included", function()
      local queue, env = world()
      queue.on_action(start_of(7, 42))
      env.now = env.now + 0.02
      queue.on_action(paralyzed_round())
      env.now = env.now + 2.41
      queue.step()
      assert.is_false(queue.busy())
    end)

    it("lets that weaponskill's own finish replace the lock if it comes after all", function()
      local queue, env = world()
      queue.on_action(start_of(7, 42))
      env.now = env.now + 0.02
      queue.on_action(too_far())
      env.now = env.now + 1
      queue.on_action(action(3, 42))
      env.now = env.now + 2.39
      queue.step()
      assert.is_true(queue.busy())
    end)

    it("leaves a finish naming no spell alone once the weaponskill's wait has run out", function()
      local queue, env = world()
      queue.on_action(start_of(7, 42))
      env.now = env.now + 1.3
      queue.step()
      queue.on_action(too_far())
      env.now = env.now + 2.35
      queue.step()
      assert.is_false(queue.busy(), "the wait's own lock, not one from the late finish")
    end)

    --[[ Kevin's Expiacion, 2026-11-11: its target died under it thirteen times
         in one run. Ten were sent as the mob died, the server answered none
         and the bar sat out its 2s each time. Three had started; no finish
         came, and the bar waited 1.2s and then a 2.4s lock with the TP kept. ]]
    describe("a weaponskill whose target dies", function()
      it("stops waiting for an answer once the target it left for is dead", function()
        local queue, env = world()
        queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
        env.now = env.now + 0.3
        queue.step()
        assert.is_true(queue.busy())
        falls(queue, MOB)
        queue.step()
        assert.is_false(queue.busy())
      end)

      it("sends what it held once that target is dead", function()
        local queue = world()
        queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
        queue.press(spell(), command())
        assert.is_nil(queue.step())
        falls(queue, MOB)
        assert.are.equal(command(), queue.step())
      end)

      it("waits out the answer in full while that target lives", function()
        local queue, env = world()
        queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
        env.now = env.now + 1.99
        queue.step()
        assert.is_true(queue.busy())
        env.now = env.now + 0.02
        queue.step()
        assert.is_false(queue.busy())
      end)

      it("waits out a spell's answer whose target is dead: a Raise is aimed at one", function()
        local queue, env = world()
        falls(queue, MOB)
        queue.on_outgoing(0x01A, outgoing_action(MAGIC, 12, MOB))
        env.now = env.now + 1.99
        queue.step()
        assert.is_true(queue.busy())
      end)

      --[[ Kevin's run of 2026-11-17: twice a weaponskill started and its target
           died before it landed. Freed at the death, the next weaponskill went
           unanswered 0.88s after the one start and was refused 2.45s after the
           other, while one sent 2.95s after a start was accepted: the lock a
           finish would have begun. ]]
      it("ends a start once its target is dead, and locks as its finish would", function()
        local queue, env = world()
        queue.on_action(weaponskill_at(MOB))
        queue.press(spell(), command())
        env.now = env.now + 0.76
        falls(queue, MOB)
        assert.is_nil(queue.step())
        env.now = env.now + 2.39
        assert.is_nil(queue.step())
        env.now = env.now + 0.02
        assert.are.equal(command(), queue.step())
      end)

      it("locks from a beat after the start when the death's word comes sooner than a finish could", function()
        local queue, env = world()
        queue.on_action(weaponskill_at(MOB))
        env.now = env.now + 0.1
        falls(queue, MOB)
        queue.step()
        env.now = env.now + 2.69
        queue.step()
        assert.is_true(queue.busy())
        env.now = env.now + 0.02
        queue.step()
        assert.is_false(queue.busy())
      end)

      it("takes the weaponskill lock as set when a death ends a start", function()
        local queue, env = world()
        env.locks = { weaponskill = 1 }
        queue.on_action(weaponskill_at(MOB))
        env.now = env.now + 0.5
        falls(queue, MOB)
        queue.step()
        env.now = env.now + 0.99
        queue.step()
        assert.is_true(queue.busy())
        env.now = env.now + 0.02
        queue.step()
        assert.is_false(queue.busy())
      end)

      it("leaves a spell's start alone when its target is dead", function()
        local queue, env = world()
        env.casts.spell[12] = 3
        falls(queue, MOB)
        local start = start_of(8, 12)
        start.targets[1].id = MOB
        queue.on_action(start)
        env.now = env.now + 1
        queue.step()
        assert.is_true(queue.busy())
      end)

      it("lets that weaponskill's finish replace the death's lock if it comes after all", function()
        local queue, env = world()
        queue.on_action(weaponskill_at(MOB))
        falls(queue, MOB)
        queue.step()
        env.now = env.now + 1
        queue.on_action(action(3, 42))
        env.now = env.now + 2.39
        queue.step()
        assert.is_true(queue.busy(), "the finish's lock, which outlasts the death's")
      end)

      it("keeps the lock a lost finish was given when the death shows only after it", function()
        local queue, env = world()
        queue.on_action(weaponskill_at(MOB))
        env.now = env.now + 1.21
        queue.step()
        falls(queue, MOB)
        env.now = env.now + 2.3
        queue.step()
        assert.is_true(queue.busy())
        env.now = env.now + 0.1
        queue.step()
        assert.is_false(queue.busy())
      end)

      it("locks from the start that comes after the answer it stopped waiting for", function()
        local queue, env = world()
        queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
        falls(queue, MOB)
        queue.step()
        assert.is_false(queue.busy())
        env.now = env.now + 0.3
        queue.on_action(weaponskill_at(MOB))
        queue.step()
        env.now = env.now + 2.79
        queue.step()
        assert.is_true(queue.busy())
        env.now = env.now + 0.02
        queue.step()
        assert.is_false(queue.busy())
      end)

      --[[ Kevin, 2026-11-16: the client's mob table shows a mob dead a third of
           a second or more before the packets of the weaponskill that killed
           it arrive, and 21 waits of 65 ended early on it over a weekend. ]]
      it("asks no mob table, which shows the death ahead of the killing blow's own packets", function()
        local queue, env = world({
          dead = function()
            return true
          end,
        })
        queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
        queue.step()
        assert.is_true(queue.busy())
        queue.on_action(weaponskill_at(MOB))
        env.now = env.now + 1.19
        queue.step()
        assert.is_true(queue.busy())
      end)

      --[[ The game says a death in a 0x029, by the messages the Debuffed addon
           reads one off, and that is all the queue takes for one. ]]
      for _, message in ipairs({ 6, 20, 113, 406, 605, 646 }) do
        it(("stops waiting once the game says the target fell, message %d"):format(message), function()
          local queue, env = world()
          queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
          env.now = env.now + 0.3
          queue.step()
          assert.is_true(queue.busy())
          queue.on_message(fall_message(MOB, message))
          queue.step()
          assert.is_false(queue.busy())
        end)
      end

      it("takes no notice of another target falling", function()
        local queue = world()
        queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
        queue.on_message(fall_message(MOB + 1))
        queue.step()
        assert.is_true(queue.busy())
      end)

      it("takes a death for no refusal, whoever dealt it", function()
        local queue = world()
        queue.on_outgoing(0x01A, outgoing_action(MAGIC, 12, MOB))
        queue.on_message(fall_message(MOB + 1, 6, ME))
        queue.step()
        assert.is_true(queue.busy())
      end)

      it("remembers a death for thirty seconds", function()
        local queue, env = world()
        queue.on_message(fall_message(MOB))
        env.now = env.now + 29.9
        queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
        queue.step()
        assert.is_false(queue.busy())
        env.now = env.now + 0.2
        queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
        queue.step()
        assert.is_true(queue.busy())
      end)

      it("takes a target that has acted since for alive", function()
        local queue = world()
        queue.on_message(fall_message(MOB))
        queue.on_action(action(1, 0, MOB))
        queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
        queue.step()
        assert.is_true(queue.busy())
      end)

      it("takes that target's interrupted cast for no sign of life", function()
        local queue = world()
        queue.on_message(fall_message(MOB))
        queue.on_action(action(8, INTERRUPTED, MOB))
        queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
        queue.step()
        assert.is_false(queue.busy())
      end)

      it("keeps a death while anyone else acts", function()
        local queue = world()
        queue.on_message(fall_message(MOB))
        queue.on_action(action(1, 0, SOMEONE))
        queue.on_action(action(1, 0, ME))
        queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
        queue.step()
        assert.is_false(queue.busy())
      end)

      it("remembers one death through the next", function()
        local queue, env = world()
        queue.on_message(fall_message(MOB))
        env.now = env.now + 1
        queue.on_message(fall_message(MOB + 1))
        queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
        queue.step()
        assert.is_false(queue.busy())
      end)

      it("forgets every death on a clear", function()
        local queue = world()
        queue.on_message(fall_message(MOB))
        queue.clear("zone")
        queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
        queue.step()
        assert.is_true(queue.busy())
      end)
    end)

    it("takes any finish after a wait whose start named nothing", function()
      local queue, env = world()
      queue.on_action(action(7, STARTING))
      env.now = env.now + 3.01
      queue.step()
      env.now = env.now + 2.41
      queue.step()
      queue.on_action(action(4, 1))
      assert.is_true(queue.busy())
    end)

    it("reads a cast time that is not a usable number as unknown", function()
      for _, seconds in ipairs({ -1, 0 / 0, "3" }) do
        local queue, env = world()
        env.casts.spell[511] = seconds
        queue.on_action(start_of(8, 511))
        env.now = env.now + 29.99
        queue.step()
        assert.is_true(queue.busy())
      end
    end)

    it("keeps a press held behind a later send when an old start's finish window closes", function()
      local queue, env = world()
      env.casts.spell[511] = 3
      queue.on_action(start_of(8, 511))
      env.now = env.now + 3.41
      queue.step()
      env.now = env.now + 26.2
      queue.step()
      assert.is_false(queue.press(spell("Cure"), command("Cure")))
      assert.is_true(queue.press(spell("Fire"), command("Fire")))
      env.now = env.now + 0.4
      queue.step()
      assert.is_not_nil(queue.held())
    end)

    it("waits out the full backstop on a spell whose cast time is unknown", function()
      local queue, env = world()
      queue.on_action(start_of(8, 511))
      env.now = env.now + 29.99
      queue.step()
      assert.is_true(queue.busy())
    end)

    it("waits on a weaponskill's finish for 1.2 seconds, then its lock", function()
      local queue, env = world()
      queue.on_action(start_of(7, 42))
      env.now = env.now + 3.59
      queue.step()
      assert.is_true(queue.busy())
      env.now = env.now + 0.02
      queue.step()
      assert.is_false(queue.busy())
    end)

    it("waits on an item's finish for its cast time and a second, then its lock", function()
      local queue, env = world()
      env.casts.item[4148] = 2
      queue.on_action(start_of(9, 4148))
      env.now = env.now + 3.99
      queue.step()
      assert.is_true(queue.busy())
      env.now = env.now + 0.02
      queue.step()
      assert.is_false(queue.busy())
    end)

    it("reads a finish after a clear as no finish, though the start's 30s window was open", function()
      local queue = world()
      queue.on_action(start_of(8, 511))
      queue.clear("zone")
      queue.on_action(action(4, 511))
      assert.is_false(queue.busy())
    end)

    it("sends a press that lands as the 30s backstop runs out, before the next tick", function()
      local queue, env = world()
      start_cast(queue)
      env.now = env.now + 30.01
      assert.is_false(queue.press(spell(), command()))
    end)

    it("waits out the full backstop on a ranged attack", function()
      local queue, env = world()
      queue.on_action(start_of(12, 0))
      env.now = env.now + 29.99
      queue.step()
      assert.is_true(queue.busy())
    end)

    it("drops what it held when the finish never came, rather than firing it late", function()
      local queue, env = world()
      start_cast(queue)
      env.now = env.now + 20
      queue.press(spell(), command())
      env.now = env.now + 10.01
      assert.is_nil(queue.step())
      assert.is_nil(queue.held())
    end)

    it("drops a press held too long behind a run of other casts", function()
      local queue, env = world()
      start_cast(queue)
      queue.press(spell(), command())
      for _ = 1, 4 do
        env.now = env.now + 8
        finish_cast(queue)
        start_cast(queue)
        queue.step()
      end
      assert.is_nil(queue.held())
    end)
  end)

  describe("the release", function()
    it("goes the tick the lock clears, and not before", function()
      local queue, env = world()
      finish_cast(queue)
      queue.press(spell(), command())
      env.now = env.now + 2.69
      assert.is_nil(queue.step())
      env.now = env.now + 0.02
      assert.are.equal(command(), queue.step())
      assert.is_nil(queue.held())
    end)

    it("goes once", function()
      local queue, env = world()
      finish_cast(queue)
      queue.press(spell(), command())
      env.now = env.now + 3.01
      queue.step()
      assert.is_nil(queue.step())
    end)

    it("waits for the finish of a cast it was pressed during", function()
      local queue, env = world()
      start_cast(queue)
      queue.press(spell(), command())
      env.now = env.now + 5
      assert.is_nil(queue.step())
      finish_cast(queue)
      assert.is_nil(queue.step())
      env.now = env.now + 3.01
      assert.are.equal(command(), queue.step())
    end)

    it("survives an interrupted cast", function()
      local queue, env = world()
      start_cast(queue)
      queue.press(spell(), command())
      queue.on_action(action(8, INTERRUPTED))
      assert.is_nil(queue.step())
      env.now = env.now + 2.71
      assert.are.equal(command(), queue.step())
    end)

    it("is busy again at once, so the next press holds too", function()
      local queue, env = world()
      finish_cast(queue)
      queue.press(spell("Cure"), command("Cure"))
      env.now = env.now + 3.01
      queue.step()
      assert.is_true(queue.press(spell("Stone"), command("Stone")))
    end)

    it("is dropped when its recast is running at the release, never waited on", function()
      local queue, env = world()
      start_cast(queue)
      queue.press(spell("Cure"), command("Cure"))
      finish_cast(queue)
      env.recast.Cure = 2.5
      env.now = env.now + 3.01
      assert.is_nil(queue.step())
      assert.is_nil(queue.held())
      env.recast.Cure = 0
      assert.is_nil(queue.step())
    end)

    it("is not re-sent when the game refuses it", function()
      local queue, env = world()
      finish_cast(queue)
      queue.press(spell(), command())
      env.now = env.now + 3.01
      queue.step()
      queue.on_message(battle_message(ME, 17))
      env.now = env.now + 10
      assert.is_nil(queue.step())
    end)
  end)

  --[[ Kevin, 2026-11-12: a held weaponskill was released at the corpse of the
       mob it was pinned to, and a held Sleepga at a statue 1.2s dead. No answer
       came for either, and the Sleepga meant for the pack went out four
       seconds late. ]]
  describe("a held press whose target has died", function()
    local BLADE = { type = "ws", action = "Savage Blade", target = "t" }
    local BLADE_COMMAND = 'input /ws "Savage Blade" <t>'
    local SLEEPGA = { type = "ma", action = "Sleepga", target = "t" }
    local SLEEPGA_COMMAND = 'input /ma "Sleepga" <t>'
    local PROVOKE = { type = "ja", action = "Provoke", target = "t" }
    local PROVOKE_COMMAND = 'input /ja "Provoke" <t>'
    -- An id from 0x01000000 up is a monster's, an NPC's or a pet's, never a player's.
    local MONSTER, PLAYER = 17000001, 71391

    -- Held through a cast, pinned to `target`, with the cast's lock running.
    local function held_at(target, record, line)
      local queue, env = world()
      env.player.vitals = { tp = 3000, hp = 1500 }
      env.pinned = target
      start_cast(queue)
      queue.press(record, line)
      queue.on_action(action(4, 1))
      return queue, env
    end

    local function release(queue, env)
      env.now = env.now + 2.71
      return queue.step()
    end

    it("drops a weaponskill whose target is dead at the release", function()
      local queue, env = held_at(MONSTER, BLADE, BLADE_COMMAND)
      falls(queue, MONSTER)
      assert.is_nil(release(queue, env))
      assert.is_nil(queue.held())
      assert.is_false(queue.busy())
    end)

    it("releases a weaponskill whose target lives", function()
      local queue, env = held_at(MONSTER, BLADE, BLADE_COMMAND)
      falls(queue, MONSTER + 1)
      assert.are.equal(BLADE_COMMAND, release(queue, env))
    end)

    it("drops a spell pinned to a dead monster", function()
      local queue, env = held_at(MONSTER, SLEEPGA, SLEEPGA_COMMAND)
      falls(queue, MONSTER)
      assert.is_nil(release(queue, env))
      assert.is_nil(queue.held())
    end)

    it("releases a spell pinned to a dead player: a Raise is aimed at one", function()
      local queue, env = held_at(PLAYER, { type = "ma", action = "Raise", target = "t" }, 'input /ma "Raise" <t>')
      falls(queue, PLAYER)
      assert.are.equal('input /ma "Raise" <t>', release(queue, env))
    end)

    it("releases an ability pinned to a dead monster, which is the game's to refuse", function()
      local queue, env = held_at(MONSTER, PROVOKE, PROVOKE_COMMAND)
      falls(queue, MONSTER)
      assert.are.equal(PROVOKE_COMMAND, release(queue, env))
    end)

    it("releases what was pinned to nothing", function()
      local queue, env = held_at(MONSTER, spell(), command())
      falls(queue, MONSTER)
      assert.are.equal(command(), release(queue, env))
    end)

    it("judges the target a newer press pinned", function()
      local queue, env = held_at(MONSTER, BLADE, BLADE_COMMAND)
      falls(queue, MONSTER)
      env.pinned = MONSTER + 1
      queue.press(BLADE, BLADE_COMMAND)
      assert.are.equal(MONSTER + 1, queue.held().target)
      assert.are.equal(BLADE_COMMAND, release(queue, env))
    end)

    it("drops a cursor's weaponskill whose target died after OK", function()
      local queue, env = world()
      env.player.vitals = { tp = 3000, hp = 1500 }
      env.words[MONSTER] = "lastst"
      start_cast(queue)
      queue.press({ type = "ws", action = "Savage Blade", target = "stnpc" }, 'input /ws "Savage Blade" <stnpc>')
      queue.on_text("/ta <stnpc>")
      queue.on_text("/ta 17000001")
      queue.on_text("/ta 17000001")
      queue.on_action(action(4, 1))
      falls(queue, MONSTER)
      assert.is_nil(release(queue, env))
      assert.is_nil(queue.held())
    end)
  end)

  --[[ Kevin, 2026-11-16: over a weekend 44 weaponskills went out at a mob that
       had just died. Each cost GearSwap its precast and a packet the server
       ignores, and GearSwap then cancelled the next press nine times. About
       13 of them were pressed after the game's word, which is all a rule at
       the press can see. ]]
  describe("a weaponskill pressed at a target that has fallen", function()
    local BLADE = { type = "ws", action = "Savage Blade", target = "t" }
    local BLADE_COMMAND = 'input /ws "Savage Blade" <t>'
    local MONSTER = 17000001

    local function ready()
      local queue, env = world()
      env.player.vitals = { tp = 3000, hp = 1500 }
      env.pinned = MONSTER
      return queue, env
    end

    it("goes nowhere while nothing is busy", function()
      local queue = ready()
      falls(queue, MONSTER)
      local taken, instead = queue.press(BLADE, BLADE_COMMAND)
      assert.is_true(taken)
      assert.is_nil(instead)
      assert.is_false(queue.busy())
    end)

    it("is not held either", function()
      local queue = ready()
      start_cast(queue)
      falls(queue, MONSTER)
      assert.is_true(queue.press(BLADE, BLADE_COMMAND))
      assert.is_nil(queue.held())
    end)

    it("goes nowhere while busy, and leaves what was held alone", function()
      local queue = ready()
      start_cast(queue)
      queue.press(spell("Stone"), command("Stone"))
      falls(queue, MONSTER)
      assert.is_true(queue.press(BLADE, BLADE_COMMAND))
      assert.are.equal(command("Stone"), queue.held().command)
    end)

    it("goes at a target that lives", function()
      local queue = ready()
      falls(queue, MONSTER + 1)
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
    end)

    it("goes once that target has acted again", function()
      local queue = ready()
      falls(queue, MONSTER)
      queue.on_action(action(1, 0, MONSTER))
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
    end)

    it("goes where nothing can say who it is aimed at", function()
      local queue = ready()
      falls(queue, MONSTER)
      local unpinned = { type = "ws", action = "Savage Blade", target = "ft" }
      assert.is_false(queue.press(unpinned, 'input /ws "Savage Blade" <ft>'))
    end)

    it("is judged at OK on a cursor", function()
      local queue = ready()
      falls(queue, MONSTER)
      queue.press({ type = "ws", action = "Savage Blade", target = "stnpc" }, 'input /ws "Savage Blade" <stnpc>')
      queue.on_text("/ta <stnpc>")
      queue.on_text("/ta 17000001")
      local kept, instead = queue.on_text("/ta 17000001")
      assert.is_true(kept)
      assert.is_nil(instead)
      assert.is_false(queue.busy())
      assert.is_nil(queue.held())
    end)

    it("leaves a spell pressed at a fallen monster to the game", function()
      local queue = ready()
      falls(queue, MONSTER)
      assert.is_false(queue.press({ type = "ma", action = "Sleepga", target = "t" }, 'input /ma "Sleepga" <t>'))
    end)

    --[[ A death is remembered 30s, and a mob back up under its id inside that
         would take no weaponskill from the bar until it acted, so this rule
         looks back three seconds and no further. It was two (Kevin,
         2026-11-16) until a run on it showed presses at a corpse up to 1.76s
         after the death, nine of 52 past a second (Kevin, 2026-11-18). ]]
    describe("more than a moment after the death", function()
      it("still goes nowhere just short of three seconds", function()
        local queue, env = ready()
        falls(queue, MONSTER)
        env.now = env.now + 2.99
        assert.is_true(queue.press(BLADE, BLADE_COMMAND))
      end)

      it("goes as it always did from three seconds on", function()
        local queue, env = ready()
        falls(queue, MONSTER)
        env.now = env.now + 3
        assert.is_false(queue.press(BLADE, BLADE_COMMAND))
      end)

      it("goes at a cursor's OK from three seconds on", function()
        local queue, env = ready()
        falls(queue, MONSTER)
        env.now = env.now + 3
        queue.press({ type = "ws", action = "Savage Blade", target = "stnpc" }, 'input /ws "Savage Blade" <stnpc>')
        queue.on_text("/ta <stnpc>")
        queue.on_text("/ta 17000001")
        local kept, instead = queue.on_text("/ta 17000001")
        assert.is_true(kept)
        assert.are.equal('input /ws "Savage Blade" <t>', instead)
      end)

      it("is held from three seconds on, and dropped at the release while the death is remembered", function()
        local queue, env = ready()
        falls(queue, MONSTER)
        env.now = env.now + 3
        finish_cast(queue)
        assert.is_true(queue.press(BLADE, BLADE_COMMAND))
        assert.is_not_nil(queue.held())
        env.now = env.now + 2.71
        assert.is_nil(queue.step())
        assert.is_nil(queue.held())
      end)
    end)
  end)

  describe("a weaponskill under 1000 TP", function()
    local BLADE = { type = "ws", action = "Savage Blade", target = "t" }
    local BLADE_COMMAND = 'input /ws "Savage Blade" <t>'

    local function finish_weaponskill(queue)
      queue.on_action(action(7, STARTING))
      queue.on_action(action(3, 1))
    end

    it("goes nowhere while nothing is busy", function()
      local queue, env = world()
      env.player.vitals = { tp = 999 }
      local taken, instead = queue.press(BLADE, BLADE_COMMAND)
      assert.is_true(taken)
      assert.is_nil(instead)
    end)

    it("starts no wait, so the next press goes at once", function()
      local queue, env = world()
      env.player.vitals = { tp = 999 }
      queue.press(BLADE, BLADE_COMMAND)
      assert.is_false(queue.busy())
      assert.is_false(queue.press(spell(), command()))
    end)

    it("goes nowhere while busy, and leaves what was held alone", function()
      local queue, env = world()
      env.player.vitals = { tp = 500 }
      start_cast(queue)
      queue.press(spell("Stone"), command("Stone"))
      assert.is_true(queue.press(BLADE, BLADE_COMMAND))
      assert.are.equal(command("Stone"), queue.held().command)
    end)

    it("goes as any press does at 1000", function()
      local queue, env = world()
      env.player.vitals = { tp = 1000 }
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
      assert.is_true(queue.busy())
    end)

    it("is held as any press is at 1000", function()
      local queue, env = world()
      env.player.vitals = { tp = 1000 }
      start_cast(queue)
      assert.is_true(queue.press(BLADE, BLADE_COMMAND))
      assert.are.equal(BLADE_COMMAND, queue.held().command)
    end)

    it("is left to the game while the client reports no TP", function()
      local queue = world()
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
    end)

    it("asks nothing of anything but a weaponskill", function()
      local queue, env = world()
      env.player.vitals = { tp = 0 }
      assert.is_false(queue.press(spell(), command()))
      assert.is_true(queue.busy())
    end)

    it("is dropped at the release when the weaponskill before it spent the TP", function()
      local queue, env = world()
      env.player.vitals = { tp = 3000 }
      start_cast(queue)
      queue.press(BLADE, BLADE_COMMAND)
      queue.on_action(action(3, 1))
      env.player.vitals.tp = 100
      env.now = env.now + 2.41
      assert.is_nil(queue.step())
      assert.is_nil(queue.held())
    end)

    it("starts no wait when dropped, so the next press goes at once", function()
      local queue, env = world()
      env.player.vitals = { tp = 3000 }
      start_cast(queue)
      queue.press(BLADE, BLADE_COMMAND)
      queue.on_action(action(3, 1))
      env.player.vitals.tp = 100
      env.now = env.now + 2.41
      queue.step()
      assert.is_false(queue.busy())
    end)

    it("is released as any press is with the TP still there", function()
      local queue, env = world()
      env.player.vitals = { tp = 3000 }
      finish_weaponskill(queue)
      queue.press(BLADE, BLADE_COMMAND)
      env.player.vitals.tp = 1000
      env.now = env.now + 2.41
      assert.are.equal(BLADE_COMMAND, queue.step())
    end)

    describe("on a cursor", function()
      local AIMED_BLADE = { type = "ws", action = "Savage Blade", target = "stnpc" }
      local AIMED_COMMAND = 'input /ws "Savage Blade" <stnpc>'

      local function cursor_up(queue)
        queue.press(AIMED_BLADE, AIMED_COMMAND)
        queue.on_text("/ta <stnpc>")
        queue.on_text("/ta 777")
      end

      it("goes nowhere at OK, and the /ta stays from the game", function()
        local queue, env = world()
        env.player.vitals = { tp = 999 }
        cursor_up(queue)
        local swallowed, send = queue.on_text("/ta 12345")
        assert.is_true(swallowed)
        assert.is_nil(send)
        assert.is_nil(queue.held())
        assert.is_false(queue.busy())
      end)

      it("is judged at OK, since the TP may be there by then", function()
        local queue, env = world()
        env.player.vitals = { tp = 999 }
        cursor_up(queue)
        env.player.vitals.tp = 1000
        local swallowed, send = queue.on_text("/ta 12345")
        assert.is_true(swallowed)
        assert.are.equal('input /ws "Savage Blade" <t>', send)
      end)
    end)
  end)

  describe("a weaponskill the player cannot use", function()
    local BLADE = { type = "ws", action = "Savage Blade", target = "t" }
    local BLADE_COMMAND = 'input /ws "Savage Blade" <t>'
    local HASTE, PARALYSIS, STUN, AMNESIA = 33, 4, 10, 16
    local IDLE, ENGAGED, RESTING = 0, 1, 33

    -- What Selindrile's check_disable and check_amnesia abort on, by the ids
    -- Windower's buffs resource gives those names.
    local STOPPERS = {
      { 2, "sleep" },
      { 7, "petrification" },
      { 10, "stun" },
      { 14, "charm" },
      { 16, "amnesia" },
      { 17, "charm" },
      { 19, "sleep" },
      { 28, "terror" },
      { 193, "lullaby" },
      { 261, "impairment" },
      { 633, "animated" },
    }

    -- With the TP for it, so only what a test adds can stop it.
    local function ready(env)
      env.player.vitals = { tp = 3000, hp = 1500 }
      env.player.status = ENGAGED
      env.player.buffs = { HASTE }
    end

    for _, stopper in ipairs(STOPPERS) do
      local id, name = stopper[1], stopper[2]
      it(("goes nowhere under %s (%d)"):format(name, id), function()
        local queue, env = world()
        ready(env)
        env.player.buffs = { HASTE, id }
        local taken, instead = queue.press(BLADE, BLADE_COMMAND)
        assert.is_true(taken)
        assert.is_nil(instead)
      end)
    end

    it("goes nowhere at no HP", function()
      local queue, env = world()
      ready(env)
      env.player.vitals.hp = 0
      local taken, instead = queue.press(BLADE, BLADE_COMMAND)
      assert.is_true(taken)
      assert.is_nil(instead)
    end)

    it("goes nowhere while neither idle nor engaged", function()
      local queue, env = world()
      ready(env)
      env.player.status = RESTING
      local taken, instead = queue.press(BLADE, BLADE_COMMAND)
      assert.is_true(taken)
      assert.is_nil(instead)
    end)

    it("starts no wait, so the next press goes at once", function()
      local queue, env = world()
      ready(env)
      env.player.buffs = { AMNESIA }
      queue.press(BLADE, BLADE_COMMAND)
      assert.is_false(queue.busy())
      assert.is_false(queue.press(spell(), command()))
    end)

    it("goes nowhere while busy, and leaves what was held alone", function()
      local queue, env = world()
      ready(env)
      env.player.buffs = { STUN }
      start_cast(queue)
      queue.press(spell("Stone"), command("Stone"))
      assert.is_true(queue.press(BLADE, BLADE_COMMAND))
      assert.are.equal(command("Stone"), queue.held().command)
    end)

    it("goes as any press does while idle", function()
      local queue, env = world()
      ready(env)
      env.player.status = IDLE
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
      assert.is_true(queue.busy())
    end)

    it("goes as any press does under a status that stops no weaponskill", function()
      local queue, env = world()
      ready(env)
      env.player.buffs = { HASTE, PARALYSIS }
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
      assert.is_true(queue.busy())
    end)

    it("is left to the game while the client reports no buffs, HP or status", function()
      local queue, env = world()
      env.player.vitals = { tp = 3000 }
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
    end)

    it("asks nothing of anything but a weaponskill", function()
      local queue, env = world()
      ready(env)
      env.player.buffs = { STUN, AMNESIA }
      env.player.status = RESTING
      env.player.vitals.hp = 0
      assert.is_false(queue.press(spell(), command()))
      assert.is_true(queue.busy())
    end)

    it("is dropped at the release when the status landed while it was held", function()
      local queue, env = world()
      ready(env)
      start_cast(queue)
      queue.press(BLADE, BLADE_COMMAND)
      queue.on_action(action(3, 1))
      env.player.buffs = { HASTE, STUN }
      env.now = env.now + 2.41
      assert.is_nil(queue.step())
      assert.is_nil(queue.held())
      assert.is_false(queue.busy())
    end)

    it("reads the client's list whatever its keys are", function()
      local queue, env = world()
      ready(env)
      env.player.buffs = { [0] = STUN, [1] = HASTE }
      assert.is_true(queue.press(BLADE, BLADE_COMMAND))
    end)

    it("takes no count the client's list carries for a status", function()
      local queue, env = world()
      ready(env)
      env.player.buffs = { HASTE, HASTE, n = 2 }
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
    end)

    --[[ Kevin, 2026-11-12: stunned, eight presses went to GearSwap and each was
         answered `Abort: You are stunned.`, the client's own list never naming
         the stun. GearSwap reads the 0x063 that lists your buffs, and nothing
         else. ]]
    describe("by the buffs the game's own packet lists", function()
      it("goes nowhere under a status the packet names, though the client's list does not", function()
        local queue, env = world()
        ready(env)
        queue.on_update(buff_update({ HASTE, STUN }))
        local taken, instead = queue.press(BLADE, BLADE_COMMAND)
        assert.is_true(taken)
        assert.is_nil(instead)
      end)

      it("reads the last of the thirty-two slots", function()
        local queue, env = world()
        ready(env)
        local ids = {}
        ids[32] = STUN
        queue.on_update(buff_update(ids))
        assert.is_true(queue.press(BLADE, BLADE_COMMAND))
      end)

      it("goes once the packet no longer names it, though the client's list still does", function()
        local queue, env = world()
        ready(env)
        env.player.buffs = { HASTE, STUN }
        queue.on_update(buff_update({ HASTE }))
        assert.is_false(queue.press(BLADE, BLADE_COMMAND))
        assert.is_true(queue.busy())
      end)

      it("takes the newest packet", function()
        local queue, env = world()
        ready(env)
        queue.on_update(buff_update({ STUN }))
        queue.on_update(buff_update({ HASTE }))
        assert.is_false(queue.press(BLADE, BLADE_COMMAND))
      end)

      it("ignores every other order of that packet", function()
        local queue, env = world()
        ready(env)
        queue.on_update(buff_update({ STUN }, 2))
        assert.is_false(queue.press(BLADE, BLADE_COMMAND))
      end)

      it("ignores a packet that did not parse, or parsed with no buffs in it", function()
        local queue, env = world()
        ready(env)
        env.player.buffs = { STUN }
        queue.on_update(nil)
        queue.on_update({ Order = 9 })
        assert.is_true(queue.press(BLADE, BLADE_COMMAND))
      end)

      it("asks the client's list again after a clear, until the next packet", function()
        local queue, env = world()
        ready(env)
        queue.on_update(buff_update({ STUN }))
        queue.clear("logout")
        assert.is_false(queue.press(BLADE, BLADE_COMMAND))
      end)

      it("keeps the list a packet gave it while it was off", function()
        local queue, env = world()
        ready(env)
        env.mode = "off"
        queue.on_update(buff_update({ AMNESIA }))
        queue.step()
        env.mode = "on"
        assert.is_true(queue.press(BLADE, BLADE_COMMAND))
      end)

      it("drops it at the release when the packet names a status that landed while it was held", function()
        local queue, env = world()
        ready(env)
        start_cast(queue)
        queue.press(BLADE, BLADE_COMMAND)
        queue.on_action(action(3, 1))
        queue.on_update(buff_update({ HASTE, STUN }))
        env.now = env.now + 2.41
        assert.is_nil(queue.step())
        assert.is_nil(queue.held())
      end)
    end)

    describe("on a cursor", function()
      local AIMED_BLADE = { type = "ws", action = "Savage Blade", target = "stnpc" }
      local AIMED_COMMAND = 'input /ws "Savage Blade" <stnpc>'

      local function cursor_up(queue)
        queue.press(AIMED_BLADE, AIMED_COMMAND)
        queue.on_text("/ta <stnpc>")
        queue.on_text("/ta 777")
      end

      it("goes nowhere at OK, and the /ta stays from the game", function()
        local queue, env = world()
        ready(env)
        env.player.buffs = { AMNESIA }
        cursor_up(queue)
        local swallowed, send = queue.on_text("/ta 12345")
        assert.is_true(swallowed)
        assert.is_nil(send)
        assert.is_nil(queue.held())
        assert.is_false(queue.busy())
      end)

      it("is judged at OK, since the status may have worn off by then", function()
        local queue, env = world()
        ready(env)
        env.player.buffs = { AMNESIA }
        cursor_up(queue)
        env.player.buffs = { HASTE }
        local swallowed, send = queue.on_text("/ta 12345")
        assert.is_true(swallowed)
        assert.are.equal('input /ws "Savage Blade" <t>', send)
      end)
    end)
  end)

  --[[ Kevin, 2026-11-22: with GearSwap casting on its own, its packet left a
       hair ahead of every release, and a mashed weaponskill sat held for 3 to
       17 seconds behind cast after cast. A held press never reaches GearSwap,
       which holds its own casts back only for a command it has seen. ]]
  describe("standing aside for a packet the bar did not send", function()
    local BLADE = { type = "ws", action = "Savage Blade", target = "t" }
    local BLADE_COMMAND = 'input /ws "Savage Blade" <t>'

    -- GearSwap's own cast, or a macro's: its packet, its start and its finish.
    local function outside_cast(queue)
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      finish_cast(queue)
    end

    -- The bar's own weaponskill leaving the client.
    local function blade_leaves(queue)
      queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, 12345))
    end

    it("sends a press made in the last second of the lock after it, as one went before the queue", function()
      local queue, env = world()
      outside_cast(queue)
      env.now = env.now + 1.75
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
      assert.is_nil(queue.held())
    end)

    --[[ Kevin's GearSwap answers a weaponskill by using a buff in its place,
         sending the weaponskill again 1.1s later and dropping every other
         weaponskill press for 5s. Sent earlier in the lock than its last
         second, that second send would land in the lock too. ]]
    it("holds a press made earlier in that lock, and lets one made in its last second replace it", function()
      local queue, env = world()
      outside_cast(queue)
      env.now = env.now + 1.65
      assert.is_true(queue.press(spell("Cure"), command("Cure")))
      assert.are.equal(command("Cure"), queue.held().command)
      env.now = env.now + 0.35
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
      assert.is_nil(queue.held())
    end)

    --[[ Sent, it could not go when the lock ends either, and past GearSwap's own
         wait its recast check aborts it unseen, with a line of chat. ]]
    it("holds a press still on its own recast in that second, as ever", function()
      local queue, env = world()
      outside_cast(queue)
      env.now = env.now + 2
      env.recast.Cure = 1
      assert.is_true(queue.press(spell("Cure"), command("Cure")))
      assert.are.equal(command("Cure"), queue.held().command)
    end)

    it("holds a cursor's cast still on its own recast at OK in that second, as ever", function()
      local queue, env = world()
      queue.press(spell("Shell V", "stpc"), 'input /ma "Shell V" <stpc>')
      queue.on_text("/ta <stpc>")
      queue.on_text("/ta 777")
      outside_cast(queue)
      env.now = env.now + 2
      env.recast["Shell V"] = 1
      local swallowed, send = queue.on_text("/ta 12345")
      assert.is_true(swallowed)
      assert.is_nil(send)
      assert.are.equal('input /ma "Shell V" <stpc>', queue.held().command)
    end)

    it("sends a press made anywhere in a lock shorter than a second", function()
      local queue, env = world()
      queue.on_outgoing(0x01A, outgoing_action(ABILITY, 31))
      queue.on_action(action(6, 31))
      env.now = env.now + 0.1
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
    end)

    it("stands aside for an item somebody else used, as for a cast", function()
      local queue, env = world()
      queue.on_outgoing(0x037, "item use")
      queue.on_action(action(5, 4112))
      env.now = env.now + 0.5
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
    end)

    -- Kevin, 2026-11-22: any packet the bar did not send, whatever became of it.
    it("stands aside for one the game refused, too", function()
      local queue, env = world()
      finish_cast(queue)
      env.now = env.now + 1
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      queue.on_message(battle_message(ME, 17))
      env.now = env.now + 1
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
    end)

    it("stands aside for no packet that is not an action", function()
      local queue, env = world()
      queue.on_outgoing(0x01A, outgoing_action(2))
      queue.on_outgoing(0x015, outgoing_action(MAGIC))
      finish_cast(queue)
      env.now = env.now + 2
      assert.is_true(queue.press(BLADE, BLADE_COMMAND))
    end)

    it("holds a press made while it is still casting", function()
      local queue = world()
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      start_cast(queue)
      assert.is_true(queue.press(BLADE, BLADE_COMMAND))
      assert.is_not_nil(queue.held())
    end)

    it("holds a press made before anything has answered it", function()
      local queue, env = world()
      finish_cast(queue)
      env.now = env.now + 2.3
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      assert.is_true(queue.press(BLADE, BLADE_COMMAND))
      assert.is_not_nil(queue.held())
    end)

    it("still releases a press held through its cast, when nothing else is pressed", function()
      local queue, env = world()
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      start_cast(queue)
      queue.press(spell(), command())
      queue.on_action(action(4, 1))
      env.now = env.now + 2.71
      assert.are.equal(command(), queue.step())
    end)

    it("replaces what was held with the press it sends", function()
      local queue, env = world()
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      start_cast(queue)
      queue.press(spell("Cure"), command("Cure"))
      queue.on_action(action(4, 1))
      env.now = env.now + 2
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
      assert.is_nil(queue.held())
      env.now = env.now + 3
      assert.is_nil(queue.step())
    end)

    it("swallows a second tap of the press it sent, while that is unanswered", function()
      local queue, env = world()
      outside_cast(queue)
      env.now = env.now + 2
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
      assert.is_true(queue.press(BLADE, BLADE_COMMAND))
      assert.is_nil(queue.held())
    end)

    it("goes on sending while the lock refuses each one", function()
      local queue, env = world()
      outside_cast(queue)
      env.now = env.now + 2
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
      blade_leaves(queue)
      queue.on_message(battle_message(ME, 90))
      env.now = env.now + 0.3
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
      assert.is_nil(queue.held())
    end)

    it("sends a cursor's cast at OK in that lock", function()
      local queue, env = world()
      queue.press(spell("Shell V", "stpc"), 'input /ma "Shell V" <stpc>')
      queue.on_text("/ta <stpc>")
      queue.on_text("/ta 777")
      outside_cast(queue)
      env.now = env.now + 2
      local swallowed, send = queue.on_text("/ta 12345")
      assert.is_true(swallowed)
      assert.are.equal('input /ma "Shell V" <t>', send)
      assert.is_nil(queue.held())
    end)

    it("holds again once one of the bar's own has gone", function()
      local queue, env = world()
      outside_cast(queue)
      env.now = env.now + 2.6
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
      blade_leaves(queue)
      queue.on_action(weaponskill_at(12345))
      queue.on_action(action(3, 42))
      env.now = env.now + 1.5
      assert.is_true(queue.press(spell(), command()))
    end)

    it("holds again once nothing is busy", function()
      local queue, env = world()
      outside_cast(queue)
      env.now = env.now + 2.71
      queue.step()
      finish_cast(queue)
      env.now = env.now + 2
      assert.is_true(queue.press(BLADE, BLADE_COMMAND))
    end)

    it("is forgotten on a clear", function()
      local queue, env = world()
      outside_cast(queue)
      queue.clear("zone")
      finish_cast(queue)
      env.now = env.now + 2
      assert.is_true(queue.press(BLADE, BLADE_COMMAND))
    end)

    it("is forgotten while the queue is off", function()
      local queue, env = world()
      outside_cast(queue)
      env.mode = "off"
      queue.step()
      env.mode = "on"
      finish_cast(queue)
      env.now = env.now + 2
      assert.is_true(queue.press(BLADE, BLADE_COMMAND))
    end)

    --[[ Kevin's GearSwap uses Berserk in a weaponskill's place and sends the
         weaponskill again after it: 1.08 to 1.12s after the ability left, 69
         times of 69 in his logs of 2026-11-21. ]]
    it("takes a packet within two seconds of a press it let through for the bar's own", function()
      local queue, env = world()
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
      queue.on_outgoing(0x01A, outgoing_action(ABILITY, 31))
      queue.on_action(action(6, 31))
      env.now = env.now + 1.1
      blade_leaves(queue)
      queue.on_action(weaponskill_at(12345))
      queue.on_action(action(3, 42))
      env.now = env.now + 1.5
      assert.is_true(queue.press(spell(), command()))
    end)

    it("takes one just inside two seconds for the bar's own, and one at two for somebody else's", function()
      for _, case in ipairs({ { after = 1.99, held = true }, { after = 2, held = false } }) do
        local queue, env = world()
        queue.press(BLADE, BLADE_COMMAND)
        blade_leaves(queue)
        queue.on_message(battle_message(ME, 90))
        env.now = env.now + case.after
        outside_cast(queue)
        env.now = env.now + 2
        assert.are.equal(case.held, queue.press(BLADE, BLADE_COMMAND), "after " .. case.after)
      end
    end)

    it("takes GearSwap's own cast, sent as the lock of the bar's weaponskill ends, for somebody else's", function()
      local queue, env = world()
      queue.press(BLADE, BLADE_COMMAND)
      blade_leaves(queue)
      queue.on_action(weaponskill_at(12345))
      queue.on_action(action(3, 42))
      env.now = env.now + 2.33
      outside_cast(queue)
      env.now = env.now + 2
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
    end)

    it("counts a press sent on its recast as a send of the bar's", function()
      local queue, env = world()
      finish_cast(queue)
      env.recast.Stone = 10
      assert.is_false(queue.press(spell("Stone"), command("Stone")))
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      queue.on_message(battle_message(ME, 17))
      env.now = env.now + 2
      assert.is_true(queue.press(spell("Cure"), command("Cure")))
    end)

    it("counts a press of a kind it never holds as a send of the bar's", function()
      local queue, env = world()
      finish_cast(queue)
      queue.press({ type = "ct", action = 'ma "Stone" <t>' }, 'input /ma "Stone" <t>')
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      queue.on_message(battle_message(ME, 17))
      env.now = env.now + 2
      assert.is_true(queue.press(spell("Cure"), command("Cure")))
    end)

    it("counts a cursor's cast sent on its recast at OK as a send of the bar's", function()
      local queue, env = world()
      queue.press(spell("Shell V", "stpc"), 'input /ma "Shell V" <stpc>')
      queue.on_text("/ta <stpc>")
      queue.on_text("/ta 777")
      finish_cast(queue)
      env.recast["Shell V"] = 10
      local swallowed, send = queue.on_text("/ta 12345")
      assert.is_true(swallowed)
      assert.are.equal('input /ma "Shell V" <t>', send)
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      queue.on_message(battle_message(ME, 17))
      env.now = env.now + 2
      assert.is_true(queue.press(spell("Cure"), command("Cure")))
    end)

    it("counts a release as a send of the bar's", function()
      local queue, env = world()
      finish_cast(queue)
      queue.press(spell("Cure"), command("Cure"))
      env.now = env.now + 2.71
      assert.are.equal(command("Cure"), queue.step())
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      finish_cast(queue)
      env.now = env.now + 2
      assert.is_true(queue.press(BLADE, BLADE_COMMAND))
    end)

    it("counts a cursor's cast sent at OK with nothing busy as a send of the bar's", function()
      local queue, env = world()
      queue.press(spell("Shell V", "stpc"), 'input /ma "Shell V" <stpc>')
      queue.on_text("/ta <stpc>")
      queue.on_text("/ta 777")
      env.now = env.now + 3
      local swallowed, send = queue.on_text("/ta 12345")
      assert.is_true(swallowed)
      assert.are.equal('input /ma "Shell V" <t>', send)
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      finish_cast(queue)
      env.now = env.now + 2
      assert.is_true(queue.press(BLADE, BLADE_COMMAND))
    end)

    it("counts no press it took as a send", function()
      local queue, env = world()
      finish_cast(queue)
      assert.is_true(queue.press(spell("Cure"), command("Cure")))
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      queue.on_message(battle_message(ME, 17))
      env.now = env.now + 2
      assert.is_false(queue.press(BLADE, BLADE_COMMAND))
    end)

    it("says in debug when it starts, each press it lets go and that nothing is busy", function()
      local queue, env = world({ mode = "debug" })
      env.names[7] = "Cocoon"
      queue.on_outgoing(0x01A, outgoing_action(MAGIC, 7))
      finish_cast(queue)
      env.now = env.now + 2
      queue.press(BLADE, BLADE_COMMAND)
      env.now = env.now + 0.71
      queue.step()
      local said = logged(env)
      assert.is_not_nil(said:find("standing aside for spell Cocoon", 1, true))
      assert.is_not_nil(said:find("not held: Savage Blade, standing aside", 1, true))
      assert.is_not_nil(said:find("no longer standing aside: nothing is busy", 1, true))
    end)

    it("says in debug that the bar's own went", function()
      local queue, env = world({ mode = "debug" })
      outside_cast(queue)
      env.now = env.now + 2.6
      queue.press(BLADE, BLADE_COMMAND)
      blade_leaves(queue)
      queue.on_action(weaponskill_at(12345))
      assert.is_not_nil(logged(env):find("no longer standing aside: the bar's own went", 1, true))
    end)

    it("says in debug that a cursor's cast went at OK for it", function()
      local queue, env = world({ mode = "debug" })
      queue.press(spell("Shell V", "stpc"), 'input /ma "Shell V" <stpc>')
      queue.on_text("/ta <stpc>")
      queue.on_text("/ta 777")
      outside_cast(queue)
      env.now = env.now + 2
      queue.on_text("/ta 12345")
      assert.is_not_nil(logged(env):find("not held: Shell V, standing aside", 1, true))
    end)

    it("says it once for one stretch, however many packets leave", function()
      local queue, env = world({ mode = "debug" })
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      local _, times = logged(env):gsub("standing aside for", "")
      assert.are.equal(1, times)
    end)

    it("says nothing of it for a press made with nothing busy", function()
      local queue, env = world({ mode = "debug" })
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      env.now = env.now + 2.01
      queue.press(BLADE, BLADE_COMMAND)
      assert.is_nil(logged(env):find("not held: Savage Blade, standing aside", 1, true))
    end)
  end)

  --[[ AutoSpellTier's walk is the action service's, and a dep here: asked at
       the two moments a command is settled after its press. ]]
  describe("a lower tier standing in for a spell that cannot go", function()
    -- A walk that knows one step, Sleep II to Sleep, and says what it was asked.
    local function sleep_steps_down(asked)
      return function(record, line, pinned)
        asked[#asked + 1] = { record.action, line, pinned }
        if record.action ~= "Sleep II" then
          return record, line
        end
        local lowered = { type = "ma", action = "Sleep", target = record.target }
        return lowered, 'input /ma "Sleep" <' .. record.target .. ">"
      end
    end

    describe("at OK", function()
      local SLEEP = spell("Sleep II", "stnpc")
      local SLEEP_COMMAND = 'input /ma "Sleep II" <stnpc>'

      local function ok(queue)
        queue.press(SLEEP, SLEEP_COMMAND)
        queue.on_text("/ta <stnpc>")
        queue.on_text("/ta 777")
        return queue.on_text("/ta 12345")
      end

      it("is asked with the cursor's own command and the id OK chose, and goes at that target", function()
        local asked = {}
        local queue = world({ lower = sleep_steps_down(asked) })
        local swallowed, send = ok(queue)
        assert.is_true(swallowed)
        assert.are.equal('input /ma "Sleep" <t>', send)
        assert.are.same({ { "Sleep II", SLEEP_COMMAND, 12345 } }, asked)
      end)

      it("is held under its own name when OK comes in a lock", function()
        local queue = world({ lower = sleep_steps_down({}) })
        finish_cast(queue)
        local swallowed, send = ok(queue)
        assert.is_true(swallowed)
        assert.is_nil(send)
        assert.are.equal('input /ma "Sleep" <stnpc>', queue.held().command)
        assert.are.equal(12345, queue.held().target)
        assert.are.equal("Sleep", queue.held().name)
        assert.are.equal("Sleep", queue.held().record.action)
      end)

      it("is judged on its own recast, not the pressed spell's", function()
        local queue, env = world({ lower = sleep_steps_down({}) })
        env.recast["Sleep II"] = 20
        local swallowed, send = ok(queue)
        assert.is_true(swallowed)
        assert.are.equal('input /ma "Sleep" <t>', send)
        assert.is_true(queue.busy(), "it left as a press of the bar's")
      end)

      it("is not asked at the press, where nothing is known of the cast yet", function()
        local asked = {}
        local queue = world({ lower = sleep_steps_down(asked) })
        queue.press(SLEEP, SLEEP_COMMAND)
        assert.are.same({}, asked)
      end)

      it("is told it is asked at OK, for the walk's debug line", function()
        local where
        local queue = world({
          lower = function(record, line, _, asked_at)
            where = asked_at
            return record, line
          end,
        })
        ok(queue)
        assert.are.equal("at OK", where)
      end)
    end)

    describe("at the release", function()
      local SLEEP = spell("Sleep II", "t")
      local SLEEP_COMMAND = 'input /ma "Sleep II" <t>'

      -- Sleep II pressed in a cast, its own recast running as the lock clears.
      local function held_on_recast(lower)
        local queue, env = world({ lower = lower, mode = "debug" })
        start_cast(queue)
        queue.press(SLEEP, SLEEP_COMMAND)
        finish_cast(queue)
        env.recast["Sleep II"] = 20
        env.now = env.now + 3.01
        return queue, env
      end

      it("takes the place of what is held, at the target that was pinned to", function()
        local asked = {}
        local queue = held_on_recast(sleep_steps_down(asked))
        assert.are.equal('input /ma "Sleep" <t>', queue.step())
        assert.is_nil(queue.held())
        assert.are.same({ { "Sleep II", SLEEP_COMMAND, 12345 } }, asked)
      end)

      it("waits on its own recast where that is nearly over, and goes when it is", function()
        local queue, env = held_on_recast(sleep_steps_down({}))
        env.recast.Sleep = 1.5
        assert.is_nil(queue.step())
        assert.are.equal("Sleep", queue.held().name)
        assert.is_not_nil(logged(env):find("Sleep waits 1.50s on its recast", 1, true))
        env.recast.Sleep = 0
        assert.are.equal('input /ma "Sleep" <t>', queue.step())
      end)

      it("is dropped with what is held where its own recast is as far off", function()
        local queue, env = held_on_recast(sleep_steps_down({}))
        env.recast.Sleep = 5
        assert.is_nil(queue.step())
        assert.is_nil(queue.held())
        assert.is_not_nil(logged(env):find("dropped Sleep: on recast 5.00s", 1, true))
      end)

      it("leaves what is held to be dropped, as ever, where the walk has no tier", function()
        local queue = held_on_recast(function(record, line)
          return record, line
        end)
        assert.is_nil(queue.step())
        assert.is_nil(queue.held())
      end)

      it("is not asked for a held press that can go, or one inside its grace", function()
        local asked = {}
        local queue, env = held_on_recast(sleep_steps_down(asked))
        env.recast["Sleep II"] = 1.5
        assert.is_nil(queue.step())
        env.recast["Sleep II"] = 0
        assert.are.equal(SLEEP_COMMAND, queue.step())
        assert.are.same({}, asked)
      end)

      it("is told it is asked at the release, for the walk's debug line", function()
        local where
        local queue = held_on_recast(function(record, line, _, asked_at)
          where = asked_at
          return record, line
        end)
        queue.step()
        assert.are.equal("at the release", where)
      end)
    end)

    describe("what the walk asks of the queue", function()
      it("says a recast running with nothing busy is one the game would refuse", function()
        local queue, env = world()
        env.recast.Cure = 0.5
        assert.is_true(queue.refused_on_recast(spell("Cure")))
        env.recast.Cure = 0
        assert.is_false(queue.refused_on_recast(spell("Cure")))
      end)

      it("says one that ends within two seconds of the lock is not", function()
        local queue, env = world()
        finish_cast(queue)
        env.recast.Cure = ((env.now + 2.7) - env.now) + 2
        assert.is_false(queue.refused_on_recast(spell("Cure")))
        env.recast.Cure = 4.8
        assert.is_true(queue.refused_on_recast(spell("Cure")))
      end)

      it("says a recast is far off only past the two seconds it would wait out", function()
        local queue, env = world()
        env.recast.Cure = 2
        assert.is_false(queue.far_off(spell("Cure")), "nothing busy, and nearly ready")
        env.recast.Cure = 2.01
        assert.is_true(queue.far_off(spell("Cure")))
        finish_cast(queue)
        env.recast.Cure = ((env.now + 2.7) - env.now) + 2
        assert.is_false(queue.far_off(spell("Cure")), "two seconds past the lock")
        env.recast.Cure = 4.8
        assert.is_true(queue.far_off(spell("Cure")))
      end)

      it("says what it is busy with, in a debug line's words", function()
        local queue, env = world()
        assert.are.equal("free", queue.doing())
        queue.on_outgoing(0x01A, outgoing_action(MAGIC))
        assert.are.equal("unanswered", queue.doing(), "a send nothing has answered")
        start_cast(queue)
        assert.are.equal("casting", queue.doing(), "a cast in progress is no lock")
        queue.on_action(action(4, 1))
        env.now = env.now + 1
        assert.are.equal("lock 1.70s", queue.doing())
        env.now = env.now + 2
        assert.are.equal("free", queue.doing(), "and nothing once it is over")
      end)

      it("says a cursor slot is judged at OK while the queue is on, and nothing else is", function()
        local queue, env = world()
        assert.is_true(queue.judged_at_ok(spell("Sleep II", "stnpc")))
        assert.is_true(queue.judged_at_ok(spell("Sleep II", "STPC")))
        assert.is_false(queue.judged_at_ok(spell("Cure", "t")))
        assert.is_false(queue.judged_at_ok({ type = "ma", action = "Cure" }))
        assert.is_false(queue.judged_at_ok({ type = "ex", action = "exec x.txt", target = "stnpc" }))
        env.mode = "off"
        assert.is_false(queue.judged_at_ok(spell("Sleep II", "stnpc")))
      end)

      it("writes a collaborator's line to the debug log as its own, in debug alone", function()
        local queue, env = world({ mode = "debug" })
        queue.note("Fire V on recast, down to Fire IV")
        assert.are.same({ "queue 100.00: Fire V on recast, down to Fire IV" }, env.log)
        env.mode = "on"
        queue.note("again")
        assert.are.equal(1, #env.log)
      end)
    end)
  end)

  describe("dropping", function()
    it("drops what is held under a config mode or suppression, and keeps the lock", function()
      local queue, env = world()
      finish_cast(queue)
      queue.press(spell(), command())
      env.blocked = "edit mode"
      assert.is_nil(queue.step())
      assert.is_nil(queue.held())
      assert.is_true(queue.busy())
    end)

    it("drops what is held the tick the mode goes off", function()
      local queue, env = world()
      finish_cast(queue)
      queue.press(spell(), command())
      env.mode = "off"
      env.now = env.now + 5
      assert.is_nil(queue.step())
      assert.is_nil(queue.held())
    end)

    it("forgets the lock on a clear", function()
      local queue = world()
      start_cast(queue)
      queue.press(spell(), command())
      queue.clear("zone")
      assert.is_nil(queue.held())
      assert.is_false(queue.busy())
    end)

    it("keeps the lock on a drop", function()
      local queue = world()
      finish_cast(queue)
      queue.press(spell(), command())
      queue.drop("re-attach")
      assert.is_nil(queue.held())
      assert.is_true(queue.busy())
    end)
  end)

  describe("debug", function()
    it("says nothing in on", function()
      local queue, env = world()
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      start_cast(queue)
      queue.press(spell(), command())
      finish_cast(queue)
      env.now = env.now + 3.01
      queue.step()
      assert.are.same({}, env.log)
    end)

    it("says nothing in off", function()
      local queue, env = world({ mode = "off" })
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      start_cast(queue)
      finish_cast(queue)
      assert.are.same({}, env.log)
    end)

    it("writes every line to the log, for a client nobody is sitting at", function()
      local queue, env = world({ mode = "debug" })
      finish_cast(queue)
      assert.are.equal(2, #env.log)
    end)

    it("names what went out", function()
      local queue, env = world({ mode = "debug" })
      env.names[143] = "Cure IV"
      queue.on_outgoing(0x01A, outgoing_action(MAGIC, 143))
      assert.is_not_nil(logged(env):find("out spell Cure IV", 1, true))
    end)

    it("says the id of what it cannot name", function()
      local queue, env = world({ mode = "debug" })
      queue.on_outgoing(0x01A, outgoing_action(MAGIC, 143))
      assert.is_not_nil(logged(env):find("out spell 143", 1, true))
    end)

    it("says a category 4 it ignored, with the message that explains it", function()
      local queue, env = world({ mode = "debug" })
      queue.on_action(paralyzed_round(84))
      assert.is_not_nil(logged(env):find("ignored a finish with no cast running, message 84", 1, true))
      assert.is_nil(logged(env):find("lock", 1, true))
    end)

    it("copes with one that carries no message", function()
      local queue, env = world({ mode = "debug" })
      assert.has_no.errors(function()
        queue.on_action(action(4, 0))
      end)
      assert.is_not_nil(logged(env):find("ignored a finish with no cast running", 1, true))
    end)

    it("says a finish naming no spell was ignored though a cast was running", function()
      local queue, env = world({ mode = "debug" })
      env.casts.spell[511] = 3
      queue.on_action(start_of(8, 511))
      env.now = env.now + 1
      queue.on_action(action(4, 0))
      assert.is_not_nil(logged(env):find("ignored a finish naming no spell", 1, true))
    end)

    it("says a finish naming no spell ended a weaponskill, with its message and lock", function()
      local queue, env = world({ mode = "debug" })
      queue.on_action(start_of(7, 42))
      queue.on_action(too_far())
      assert.is_not_nil(logged(env):find("finish weaponskill naming no spell, message 78, lock 2.40s", 1, true))
    end)

    it("says a finish naming another spell was ignored after a start's wait", function()
      local queue, env = world({ mode = "debug" })
      env.casts.spell[511] = 3
      queue.on_action(start_of(8, 511))
      env.now = env.now + 3.41
      queue.step()
      env.now = env.now + 2.71
      queue.step()
      queue.on_action(action(4, 1))
      assert.is_not_nil(logged(env):find("ignored a finish naming another spell", 1, true))
    end)

    it("says the arrow, so a cursor that never raised one shows", function()
      local queue, env = world({ mode = "debug" })
      start_cast(queue)
      queue.press(spell("Shell V", "stpc"), 'input /ma "Shell V" <stpc>')
      queue.on_text("/ta 777")
      assert.is_not_nil(logged(env):find("arrow 777", 1, true))
    end)

    it("says it swallowed a press under an arrow it did not open", function()
      local queue, env = world({ mode = "debug" })
      env.arrow_up = true
      queue.press(spell("Dia III", "stnpc"), 'input /ma "Dia III" <stnpc>')
      assert.is_not_nil(logged(env):find("swallowed Dia III, another arrow is up", 1, true))
    end)

    it("stamps every line with the clock", function()
      local queue, env = world({ mode = "debug" })
      env.now = 123.456
      start_cast(queue)
      assert.is_not_nil(logged(env):find("queue 123.46: ", 1, true))
    end)

    it("says what went out and how long after the last finish", function()
      local queue, env = world({ mode = "debug" })
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      assert.is_not_nil(logged(env):find("out spell", 1, true))
      finish_cast(queue)
      env.log = {}
      env.now = env.now + 2.41
      queue.on_outgoing(0x01A, outgoing_action(ABILITY))
      assert.is_not_nil(logged(env):find("out ability +2.41s after finish", 1, true))
    end)

    it("says what started, finished and was interrupted", function()
      local queue, env = world({ mode = "debug" })
      start_cast(queue)
      assert.is_not_nil(logged(env):find("start spell", 1, true))
      finish_cast(queue)
      assert.is_not_nil(logged(env):find("finish spell, lock 2.70s", 1, true))
      queue.on_action(action(7, STARTING))
      queue.on_action(action(7, INTERRUPTED))
      assert.is_not_nil(logged(env):find("interrupted weaponskill, lock 2.70s", 1, true))
    end)

    it("says a start's distance from the last finish, the other half of the bracket", function()
      local queue, env = world({ mode = "debug" })
      finish_cast(queue)
      env.log = {}
      env.now = env.now + 2.8
      start_cast(queue)
      assert.is_not_nil(logged(env):find("start spell +2.80s after finish", 1, true))
    end)

    it("says a refusal's message and distance from the last finish", function()
      local queue, env = world({ mode = "debug" })
      finish_cast(queue)
      env.log = {}
      env.now = env.now + 2.4
      queue.on_message(battle_message(ME, 17))
      assert.is_not_nil(logged(env):find("refused, message 17 +2.40s after finish", 1, true))
    end)

    it("stays quiet about a message that is not a refusal", function()
      local queue, env = world({ mode = "debug" })
      queue.on_message(battle_message(ME, 94))
      assert.are.same({}, env.log)
    end)

    it("says what it held, replaced, released and dropped", function()
      local queue, env = world({ mode = "debug" })
      finish_cast(queue)
      queue.press(spell("Cure"), command("Cure"))
      assert.is_not_nil(logged(env):find("hold Cure", 1, true))
      env.now = env.now + 1
      queue.press(spell("Stone"), command("Stone"))
      assert.is_not_nil(logged(env):find("hold Stone, replacing Cure", 1, true))
      env.now = env.now + 2.01
      queue.step()
      assert.is_not_nil(logged(env):find("release Stone after 2.01s", 1, true))
      queue.press(spell("Cure"), command("Cure"))
      queue.drop("re-attach")
      assert.is_not_nil(logged(env):find("dropped Cure: re-attach", 1, true))
    end)

    it("says why a press was not held", function()
      local queue, env = world({ mode = "debug" })
      start_cast(queue)
      env.recast.Cure = 4
      queue.press(spell("Cure"), command("Cure"))
      assert.is_not_nil(logged(env):find("not held: Cure on recast", 1, true))
      queue.press(spell("Stone", "ft"), 'input /ma "Stone" <ft>')
      assert.is_not_nil(logged(env):find("not held: Stone, <ft> cannot be pinned", 1, true))
      env.blocked = "edit mode"
      queue.press(spell("Stone"), command("Stone"))
      assert.is_not_nil(logged(env):find("not held: Stone, edit mode", 1, true))
    end)

    it("says a weaponskill that had no TP, at the press and at the release", function()
      local queue, env = world({ mode = "debug" })
      local blade = { type = "ws", action = "Savage Blade", target = "me" }
      env.player.vitals = { tp = 3000 }
      start_cast(queue)
      queue.press(blade, 'input /ws "Savage Blade" <me>')
      queue.on_action(action(3, 1))
      env.player.vitals.tp = 100
      queue.press(blade, 'input /ws "Savage Blade" <me>')
      assert.truthy(logged(env):find("swallowed Savage Blade, no TP", 1, true))
      env.now = env.now + 2.41
      queue.step()
      assert.truthy(logged(env):find("dropped Savage Blade: no TP", 1, true))
    end)

    it("says what kept a weaponskill from going, at the press and at the release", function()
      local queue, env = world({ mode = "debug" })
      local blade = { type = "ws", action = "Savage Blade", target = "me" }
      env.player.vitals = { tp = 3000, hp = 1500 }
      start_cast(queue)
      queue.press(blade, 'input /ws "Savage Blade" <me>')
      queue.on_action(action(3, 1))
      env.player.buffs = { 16 }
      queue.press(blade, 'input /ws "Savage Blade" <me>')
      assert.truthy(logged(env):find("swallowed Savage Blade, amnesia", 1, true))
      env.now = env.now + 2.41
      queue.step()
      assert.truthy(logged(env):find("dropped Savage Blade: amnesia", 1, true))
    end)

    it("says a weaponskill pressed dead, or in a status that takes no action", function()
      local queue, env = world({ mode = "debug" })
      local blade = { type = "ws", action = "Savage Blade", target = "me" }
      env.player.vitals = { tp = 3000, hp = 0 }
      env.player.status = 3
      queue.press(blade, 'input /ws "Savage Blade" <me>')
      assert.truthy(logged(env):find("swallowed Savage Blade, dead", 1, true))
      env.player.vitals.hp = 1500
      env.player.status = 33
      queue.press(blade, 'input /ws "Savage Blade" <me>')
      assert.truthy(logged(env):find("swallowed Savage Blade, status 33", 1, true))
    end)

    it("says when the client's own list does not show the status that stopped a weaponskill", function()
      local queue, env = world({ mode = "debug" })
      local blade = { type = "ws", action = "Savage Blade", target = "me" }
      env.player.vitals = { tp = 3000, hp = 1500 }
      env.player.buffs = { 33 }
      queue.on_update(buff_update({ 33, 10 }))
      queue.press(blade, 'input /ws "Savage Blade" <me>')
      assert.truthy(logged(env):find("swallowed Savage Blade, stun (not in the client's list)", 1, true))
      env.log = {}
      env.player.buffs = { 33, 10 }
      queue.press(blade, 'input /ws "Savage Blade" <me>')
      assert.truthy(logged(env):find("swallowed Savage Blade, stun", 1, true))
      assert.is_nil(logged(env):find("client", 1, true))
    end)

    it("says so when the client's list shows another status than the packet's", function()
      local queue, env = world({ mode = "debug" })
      local blade = { type = "ws", action = "Savage Blade", target = "me" }
      env.player.vitals = { tp = 3000, hp = 1500 }
      env.player.buffs = { 33, 2 }
      queue.on_update(buff_update({ 33, 10 }))
      queue.press(blade, 'input /ws "Savage Blade" <me>')
      assert.truthy(logged(env):find("swallowed Savage Blade, stun (not in the client's list)", 1, true))
    end)

    it("says when the client's list holds that status where an array walk does not reach", function()
      local queue, env = world({ mode = "debug" })
      local blade = { type = "ws", action = "Savage Blade", target = "me" }
      env.player.vitals = { tp = 3000, hp = 1500 }
      env.player.buffs = { [1] = 33, [3] = 10 }
      queue.on_update(buff_update({ 33, 10 }))
      queue.press(blade, 'input /ws "Savage Blade" <me>')
      assert.truthy(
        logged(env):find("swallowed Savage Blade, stun (in the client's list, where ipairs does not reach)", 1, true)
      )
    end)

    it("says a held press was dropped for its target", function()
      local queue, env = world({ mode = "debug" })
      env.player.vitals = { tp = 3000, hp = 1500 }
      env.pinned = MOB
      start_cast(queue)
      queue.press({ type = "ws", action = "Savage Blade", target = "t" }, 'input /ws "Savage Blade" <t>')
      queue.on_action(action(4, 1))
      falls(queue, MOB)
      env.now = env.now + 2.71
      queue.step()
      assert.truthy(logged(env):find("dropped Savage Blade: the target died", 1, true))
    end)

    it("says each death the game reports, and who an unanswered weaponskill left for", function()
      local queue, env = world({ mode = "debug" })
      queue.on_message(fall_message(MOB + 1, 20))
      assert.truthy(logged(env):find("fell 17000002, message 20", 1, true))
      queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
      env.now = env.now + 2.01
      queue.step()
      assert.truthy(logged(env):find("no answer to the last send, a weaponskill at 17000001", 1, true))
    end)

    -- The id sets the line beside its `fell`, and the age says how long after
    -- a death presses still come, which is what a shorter memory would rest on.
    it("says a weaponskill pressed at a fallen target went nowhere, at whom and how long after", function()
      local queue, env = world({ mode = "debug" })
      env.player.vitals = { tp = 3000, hp = 1500 }
      env.pinned = MOB
      falls(queue, MOB)
      env.now = env.now + 0.31
      queue.press({ type = "ws", action = "Savage Blade", target = "t" }, 'input /ws "Savage Blade" <t>')
      assert.truthy(
        logged(env):find("swallowed Savage Blade, the target died (17000001 fell 0.31s ago)", 1, true),
        logged(env)
      )
    end)

    it("says the same of one judged at a cursor's OK", function()
      local queue, env = world({ mode = "debug" })
      env.player.vitals = { tp = 3000, hp = 1500 }
      env.words[MOB] = "lastst"
      falls(queue, MOB)
      env.now = env.now + 0.25
      queue.press({ type = "ws", action = "Savage Blade", target = "stnpc" }, 'input /ws "Savage Blade" <stnpc>')
      queue.on_text("/ta 17000001")
      queue.on_text("/ta 17000001")
      assert.truthy(
        logged(env):find("swallowed Savage Blade, the target died (17000001 fell 0.25s ago)", 1, true),
        logged(env)
      )
    end)

    it("names a system message that comes with a send unanswered", function()
      local queue, env = world({ mode = "debug" })
      queue.on_outgoing(0x01A, outgoing_action(MAGIC, 12))
      env.now = env.now + 0.5
      queue.on_system_message(system_message(12, 7))
      assert.truthy(logged(env):find("system message 12 (param 7) with the last send unanswered", 1, true))
      queue.step()
      assert.is_true(queue.busy())
    end)

    it("says a Trust cast was refused, by its system message", function()
      local queue, env = world({ mode = "debug" })
      finish_cast(queue)
      env.now = env.now + 3
      queue.on_outgoing(0x01A, outgoing_action(MAGIC, 900))
      env.now = env.now + 0.5
      queue.on_system_message(system_message(298, 7))
      assert.truthy(logged(env):find("refused, system message 298 (param 7) +3.50s after finish", 1, true))
      assert.is_nil(logged(env):find("with the last send unanswered", 1, true))
      assert.is_nil(logged(env):find("no spell was waiting", 1, true))
    end)

    it("says when that refusal found no spell waiting on an answer", function()
      local queue, env = world({ mode = "debug" })
      queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42))
      queue.on_system_message(system_message(299))
      assert.truthy(logged(env):find("refused, system message 299 (param 0), no spell was waiting", 1, true))
      assert.is_nil(logged(env):find("with the last send unanswered", 1, true))
    end)

    it("stays quiet about a system message with nothing unanswered, or too short to read", function()
      local queue, env = world({ mode = "debug" })
      queue.on_system_message(system_message(12))
      assert.are.same({}, env.log)
      queue.on_outgoing(0x01A, outgoing_action(MAGIC, 12))
      env.log = {}
      queue.on_system_message(nil)
      queue.on_system_message("short")
      assert.are.same({}, env.log)
    end)

    it("names a message of your own it takes for no refusal, with a send unanswered", function()
      local queue, env = world({ mode = "debug" })
      queue.on_outgoing(0x01A, outgoing_action(MAGIC, 12))
      env.now = env.now + 0.5
      queue.on_message(battle_message(ME, 94))
      assert.truthy(logged(env):find("unlisted message 94 with the last send unanswered", 1, true))
      queue.step()
      assert.is_true(queue.busy())
    end)

    it("stays quiet about such a message that is someone else's", function()
      local queue, env = world({ mode = "debug" })
      queue.on_outgoing(0x01A, outgoing_action(MAGIC, 12))
      env.log = {}
      queue.on_message(battle_message(SOMEONE, 94))
      assert.are.same({}, env.log)
    end)

    it("says a press was already going", function()
      local queue, env = world({ mode = "debug" })
      queue.press(spell("Cure"), command("Cure"))
      queue.press(spell("Cure"), command("Cure"))
      assert.is_not_nil(logged(env):find("swallowed Cure, already going", 1, true))
    end)

    it("says what a cursor did", function()
      local queue, env = world({ mode = "debug" })
      start_cast(queue)
      queue.press(spell("Shell V", "stpc"), 'input /ma "Shell V" <stpc>')
      assert.is_not_nil(logged(env):find("cursor Shell V <stpc>", 1, true))
      queue.on_text("/ta 777")
      queue.on_text("/ta 12345")
      assert.is_not_nil(logged(env):find("OK Shell V at 12345", 1, true))
      assert.is_not_nil(logged(env):find("hold Shell V", 1, true))
    end)

    it("says a press that only changed what OK casts", function()
      local queue, env = world({ mode = "debug" })
      queue.press(spell("Shell V", "stpc"), 'input /ma "Shell V" <stpc>')
      env.arrow_up = true
      queue.press(spell("Protect V", "stpc"), 'input /ma "Protect V" <stpc>')
      assert.is_not_nil(logged(env):find("cursor up, OK takes Protect V", 1, true))
    end)

    it("says a cursor given up for another", function()
      local queue, env = world({ mode = "debug" })
      start_cast(queue)
      queue.press(spell("Shell V", "stpc"), 'input /ma "Shell V" <stpc>')
      queue.on_text("/ta 777")
      queue.on_text("/ta <stnpc>")
      assert.is_not_nil(logged(env):find("no OK for Shell V", 1, true))
    end)

    it("says a cursor nobody confirmed", function()
      local queue, env = world({ mode = "debug" })
      start_cast(queue)
      queue.press(spell("Shell V", "stpc"), 'input /ma "Shell V" <stpc>')
      env.now = env.now + 30.01
      queue.step()
      assert.is_not_nil(logged(env):find("no OK for Shell V", 1, true))
    end)

    it("says once that a release waits on its recast", function()
      local queue, env = world({ mode = "debug" })
      finish_cast(queue)
      env.recast.Cure = 1
      queue.press(spell("Cure"), command("Cure"))
      env.now = env.now + 2.71
      queue.step()
      env.now = env.now + 0.1
      queue.step()
      local _, count = logged(env):gsub("Cure waits 1.00s on its recast", "")
      assert.are.equal(1, count)
    end)

    it("says a release lost to its recast", function()
      local queue, env = world({ mode = "debug" })
      start_cast(queue)
      queue.press(spell("Cure"), command("Cure"))
      finish_cast(queue)
      env.recast.Cure = 2.5
      env.now = env.now + 3.01
      queue.step()
      assert.is_not_nil(logged(env):find("dropped Cure: on recast", 1, true))
    end)

    it("says how much recast a dropped release had left", function()
      local queue, env = world({ mode = "debug" })
      start_cast(queue)
      queue.press(spell("Cure"), command("Cure"))
      finish_cast(queue)
      env.recast.Cure = 2.12
      env.now = env.now + 3.01
      queue.step()
      assert.is_not_nil(logged(env):find("dropped Cure: on recast 2.12s", 1, true))
    end)

    it("says how much recast and lock a press not held had", function()
      local queue, env = world({ mode = "debug" })
      finish_cast(queue)
      env.recast.Cure = 5
      queue.press(spell("Cure"), command("Cure"))
      assert.is_not_nil(logged(env):find("not held: Cure on recast 5.00s, lock 2.70s", 1, true))
    end)

    it("says how much recast and lock an OK not held had", function()
      local queue, env = world({ mode = "debug" })
      finish_cast(queue)
      env.recast["Shell V"] = 5
      queue.press(spell("Shell V", "stpc"), 'input /ma "Shell V" <stpc>')
      queue.on_text("/ta 777")
      queue.on_text("/ta 12345")
      assert.is_not_nil(logged(env):find("not held: Shell V on recast 5.00s, lock 2.70s", 1, true))
    end)

    it("says a backstop fired, which is the case worth seeing", function()
      local queue, env = world({ mode = "debug" })
      queue.press(spell(), command())
      env.now = env.now + 0.61
      queue.step()
      assert.is_not_nil(logged(env):find("nothing went out for the last press", 1, true))
      env.log = {}
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      env.now = env.now + 2.01
      queue.step()
      assert.is_not_nil(logged(env):find("no answer to the last send", 1, true))
      env.log = {}
      start_cast(queue)
      env.now = env.now + 30.01
      queue.step()
      assert.is_not_nil(logged(env):find("no finish for the last start", 1, true))
    end)

    it("says a start's wait ran out, and the lock it took for the finish", function()
      local queue, env = world({ mode = "debug" })
      env.casts.spell[511] = 3
      queue.on_action(start_of(8, 511))
      env.now = env.now + 3.41
      queue.step()
      assert.is_not_nil(logged(env):find("no finish yet for the last start, lock 2.70s", 1, true))
    end)

    it("says a weaponskill's target died, before its answer and before its finish", function()
      local queue, env = world({ mode = "debug" })
      falls(queue, MOB)
      queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
      queue.step()
      assert.is_not_nil(logged(env):find("the target died, no answer to come", 1, true))
      queue.on_action(weaponskill_at(MOB))
      queue.step()
      assert.is_not_nil(logged(env):find("the target died, no finish to come, lock 2.40s", 1, true))
    end)

    it("says what went out ahead of the finish a death was taken for", function()
      local queue, env = world({ mode = "debug" })
      queue.on_action(weaponskill_at(MOB))
      env.now = env.now + 0.1
      falls(queue, MOB)
      queue.step()
      env.now = env.now + 0.1
      queue.on_outgoing(0x01A, outgoing_action(ABILITY))
      assert.is_not_nil(logged(env):find("out ability -0.20s after finish", 1, true))
    end)

    it("says a cursor raised no arrow", function()
      local queue, env = world({ mode = "debug" })
      queue.press(spell("Shell V", "stpc"), 'input /ma "Shell V" <stpc>')
      env.now = env.now + 2.01
      queue.step()
      assert.is_not_nil(logged(env):find("no arrow for Shell V", 1, true))
    end)

    it("says when the lock clears, once", function()
      local queue, env = world({ mode = "debug" })
      finish_cast(queue)
      env.log = {}
      env.now = env.now + 3.01
      queue.step()
      queue.step()
      assert.are.equal(1, #env.log)
      assert.is_not_nil(logged(env):find("lock over", 1, true))
    end)

    it("says a clear", function()
      local queue, env = world({ mode = "debug" })
      start_cast(queue)
      queue.press(spell(), command())
      queue.clear("zone")
      assert.is_not_nil(logged(env):find("cleared: zone", 1, true))
    end)

    describe("of the status and the target, for a player left engaged with nothing to hit", function()
      local IDLE, ENGAGED = 0, 1
      local AUTO_TARGET = 234
      local BLADE = { type = "ws", action = "Savage Blade", target = "t" }
      local BLADE_COMMAND = 'input /ws "Savage Blade" <t>'

      it("says each change of status", function()
        local queue, env = world({ mode = "debug" })
        queue.on_status(ENGAGED)
        env.now = env.now + 1
        queue.on_status(IDLE)
        assert.are.same({ "queue 100.00: status 1", "queue 101.00: status 0" }, env.log)
      end)

      it("says nothing of one outside debug", function()
        local queue, env = world()
        queue.on_status(ENGAGED)
        assert.are.same({}, env.log)
      end)

      it("says whom the game auto-targeted, with nothing sent to be answered", function()
        local queue, env = world({ mode = "debug" })
        queue.on_message(fall_message(MOB, AUTO_TARGET, ME))
        assert.are.same({ "queue 100.00: auto-target " .. MOB }, env.log)
      end)

      it("says nothing of an auto-target that is somebody else's", function()
        local queue, env = world({ mode = "debug" })
        queue.on_message(fall_message(MOB, AUTO_TARGET, SOMEONE))
        assert.are.same({}, env.log)
      end)

      it("takes an auto-target for no answer to what was sent, and says it once", function()
        local queue, env = world({ mode = "debug" })
        queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL))
        queue.on_message(fall_message(MOB, AUTO_TARGET, ME))
        assert.is_true(queue.busy())
        assert.is_not_nil(logged(env):find("auto-target " .. MOB, 1, true))
        assert.is_nil(logged(env):find("unlisted message", 1, true))
      end)

      it("says a press made with no target, and the status it was made in", function()
        local queue, env = world({ mode = "debug" })
        env.player.status = ENGAGED
        env.targets.t = nil
        queue.press(BLADE, BLADE_COMMAND)
        assert.are.equal("queue 100.00: no target for Savage Blade, status 1", env.log[1])
      end)

      it("says it in any status, since which one is the question", function()
        local queue, env = world({ mode = "debug" })
        env.player.status = IDLE
        env.targets.t = nil
        queue.press(BLADE, BLADE_COMMAND)
        assert.is_not_nil(logged(env):find("no target for Savage Blade, status 0", 1, true))
      end)

      it("says it of any kind of press aimed at <t>, however the token is cased", function()
        local queue, env = world({ mode = "debug" })
        env.player.status = ENGAGED
        env.targets.t = nil
        queue.press(spell("Dia", "T"), 'input /ma "Dia" <T>')
        assert.is_not_nil(logged(env):find("no target for Dia, status 1", 1, true))
      end)

      it("says nothing of a press aimed elsewhere, and asks the client nothing for it", function()
        local queue, env = world({ mode = "debug" })
        env.player.status = ENGAGED
        env.targets.t = nil
        queue.press(spell(), command())
        queue.press(spell("Shell V", "stpc"), 'input /ma "Shell V" <stpc>')
        queue.press({ type = "ja", action = "Composure" }, "input /ja Composure")
        assert.is_nil(logged(env):find("no target", 1, true))
        assert.are.equal(0, env.target_asks)
      end)

      it("says it ahead of what became of the press, as of one swallowed under its TP", function()
        local queue, env = world({ mode = "debug" })
        env.player.status = ENGAGED
        env.player.vitals = { tp = 500 }
        env.targets.t = nil
        queue.press(BLADE, BLADE_COMMAND)
        assert.are.same({
          "queue 100.00: no target for Savage Blade, status 1",
          "queue 100.00: swallowed Savage Blade, no TP",
        }, env.log)
      end)

      it("says a press aimed at a target the game has said fell, and how long ago", function()
        local queue, env = world({ mode = "debug" })
        env.player.status = ENGAGED
        env.player.vitals = { tp = 500 }
        env.targets.t = MOB
        falls(queue, MOB)
        env.now = env.now + 2.1
        queue.press(BLADE, BLADE_COMMAND)
        assert.is_not_nil(logged(env):find("target " .. MOB .. " fell 2.10s ago for Savage Blade, status 1", 1, true))
      end)

      it("forgets that death when the queue does", function()
        local queue, env = world({ mode = "debug" })
        env.player.status = ENGAGED
        env.targets.t = MOB
        falls(queue, MOB)
        env.now = env.now + 30
        env.log = {}
        queue.press(BLADE, BLADE_COMMAND)
        assert.is_nil(logged(env):find(", status ", 1, true))
      end)

      it("says nothing of a press made at a target the game has said nothing of", function()
        local queue, env = world({ mode = "debug" })
        env.player.status = ENGAGED
        queue.press(BLADE, BLADE_COMMAND)
        assert.is_nil(logged(env):find(", status ", 1, true))
      end)

      it("copes with a client that names no player or no status", function()
        local queue, env = world({ mode = "debug" })
        env.targets.t = nil
        queue.press(BLADE, BLADE_COMMAND)
        env.player = nil
        assert.has_no.errors(function()
          queue.press(BLADE, BLADE_COMMAND)
        end)
        assert.are.equal(2, select(2, logged(env):gsub("no target for Savage Blade, status unknown", "")))
      end)

      it("asks the client for no target outside debug", function()
        local queue, env = world()
        env.player.status = ENGAGED
        env.targets.t = nil
        queue.press(BLADE, BLADE_COMMAND)
        assert.are.equal(0, env.target_asks)
        assert.are.same({}, env.log)
      end)
    end)

    describe("of who moved the target, the server or the player", function()
      local ENGAGE, DISENGAGE, ASSIST, SWITCH_TARGET = 2, 4, 12, 15
      local OUT_OF_RANGE, UNABLE_TO_SEE = 4, 5

      -- A raw 0x029 with you as its actor, about `target`.
      local function message_about(target, message)
        return fall_message(target, message, ME)
      end

      describe("the server's target packet", function()
        it("is said with the target it sets", function()
          local queue, env = world({ mode = "debug" })
          queue.on_target(target_packet(ME, MOB))
          assert.are.same({ "queue 100.00: server target " .. MOB }, env.log)
        end)

        it("is said with whose it is where that is not known to be yours", function()
          local queue, env = world({ mode = "debug" })
          queue.on_target(target_packet(SOMEONE, MOB))
          env.player = nil
          queue.on_target(target_packet(ME, MOB))
          assert.are.same({
            "queue 100.00: server target " .. MOB .. " for " .. SOMEONE,
            "queue 100.00: server target " .. MOB .. " for " .. ME,
          }, env.log)
        end)

        it("is not said outside debug", function()
          local queue, env = world()
          queue.on_target(target_packet(ME, MOB))
          assert.are.same({}, env.log)
        end)

        it("is passed by when it is cut short or is no packet at all", function()
          local queue, env = world({ mode = "debug" })
          assert.has_no.errors(function()
            queue.on_target(target_packet(ME, MOB):sub(1, 11))
            queue.on_target(nil)
          end)
          assert.are.same({}, env.log)
        end)
      end)

      describe("a targeting packet of the player's own", function()
        it("is said with the mob it names: an engage, a switch of target, an assist", function()
          local queue, env = world({ mode = "debug" })
          queue.on_outgoing(0x01A, outgoing_action(ENGAGE, 0, MOB))
          queue.on_outgoing(0x01A, outgoing_action(SWITCH_TARGET, 0, MOB + 1))
          queue.on_outgoing(0x01A, outgoing_action(ASSIST, 0, SOMEONE))
          assert.are.same({
            "queue 100.00: out engage " .. MOB,
            "queue 100.00: out switch target " .. (MOB + 1),
            "queue 100.00: out assist " .. SOMEONE,
          }, env.log)
        end)

        it("is said bare where it names nobody, as a disengage may", function()
          local queue, env = world({ mode = "debug" })
          queue.on_outgoing(0x01A, outgoing_action(DISENGAGE))
          assert.are.same({ "queue 100.00: out disengage" }, env.log)
        end)

        it("is no action: nothing is busy for it and nothing stands aside", function()
          local queue, env = world({ mode = "debug" })
          queue.on_outgoing(0x01A, outgoing_action(ENGAGE, 0, MOB))
          queue.on_outgoing(0x01A, outgoing_action(SWITCH_TARGET, 0, MOB))
          assert.is_false(queue.busy())
          assert.is_nil(logged(env):find("standing aside", 1, true))
          assert.is_false(queue.press(spell(), command()))
        end)

        it("is not said outside debug", function()
          local queue, env = world()
          queue.on_outgoing(0x01A, outgoing_action(ENGAGE, 0, MOB))
          assert.are.same({}, env.log)
        end)
      end)

      describe("the mob the server has the player fighting", function()
        it("is said when a melee round of his lands, with what the client has under <t>", function()
          local queue, env = world({ mode = "debug" })
          env.targets.t = MOB
          queue.on_action(round_at(MOB))
          assert.are.same({ ("queue 100.00: swing at %d, <t> %d"):format(MOB, MOB) }, env.log)
        end)

        it("is said once for as long as the rounds land on the same mob", function()
          local queue, env = world({ mode = "debug" })
          queue.on_action(round_at(MOB))
          env.now = env.now + 2
          queue.on_action(round_at(MOB))
          assert.are.equal(1, #env.log)
        end)

        it("is said again for the next mob, and of a client with nothing under <t>", function()
          local queue, env = world({ mode = "debug" })
          queue.on_action(round_at(MOB))
          env.targets.t = nil
          queue.on_action(round_at(MOB + 1))
          assert.are.equal(("queue 100.00: swing at %d, <t> none"):format(MOB + 1), env.log[2])
        end)

        it("is not said of somebody else's round", function()
          local queue, env = world({ mode = "debug" })
          queue.on_action(round_at(MOB, SOMEONE))
          assert.are.same({}, env.log)
        end)

        it("is said when the game calls a mob out of his range, or one he cannot see", function()
          local queue, env = world({ mode = "debug" })
          queue.on_message(message_about(MOB, OUT_OF_RANGE))
          queue.on_message(message_about(MOB, UNABLE_TO_SEE))
          assert.are.same({
            ("queue 100.00: out of range of %d, <t> 12345"):format(MOB),
            ("queue 100.00: unable to see %d, <t> 12345"):format(MOB),
          }, env.log)
        end)

        it("is not said of a message that has somebody else for its actor", function()
          local queue, env = world({ mode = "debug" })
          queue.on_message(fall_message(MOB, OUT_OF_RANGE, SOMEONE))
          assert.are.same({}, env.log)
        end)

        it("is said once for a message that repeats", function()
          local queue, env = world({ mode = "debug" })
          queue.on_message(message_about(MOB, OUT_OF_RANGE))
          queue.on_message(message_about(MOB, OUT_OF_RANGE))
          assert.are.equal(1, #env.log)
        end)

        it("is said every time with a send unanswered, as what may be its answer, and never as unlisted", function()
          local queue, env = world({ mode = "debug" })
          finish_cast(queue)
          env.now = env.now + 3
          queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL))
          env.log = {}
          queue.on_message(message_about(MOB, OUT_OF_RANGE))
          queue.on_message(message_about(MOB, OUT_OF_RANGE))
          local line = ("queue 103.00: out of range of %d, <t> 12345"):format(MOB)
            .. " with the last send unanswered +3.00s after finish"
          assert.are.same({ line, line }, env.log)
          assert.is_true(queue.busy())
        end)

        it("copes with a round that names no mob, and with a client that names no player", function()
          local queue, env = world({ mode = "debug" })
          assert.has_no.errors(function()
            queue.on_action(action(1))
            env.player = nil
            queue.on_action(round_at(MOB))
            queue.on_message(message_about(MOB, OUT_OF_RANGE))
          end)
          assert.are.same({}, env.log)
        end)

        it("is said again when a round lands on a mob that was out of range", function()
          local queue, env = world({ mode = "debug" })
          queue.on_message(message_about(MOB, OUT_OF_RANGE))
          queue.on_action(round_at(MOB))
          queue.on_message(message_about(MOB, OUT_OF_RANGE))
          assert.are.equal(3, #env.log)
        end)

        it("is said afresh after a change of status", function()
          local queue, env = world({ mode = "debug" })
          queue.on_action(round_at(MOB))
          queue.on_status(0)
          queue.on_status(1)
          queue.on_action(round_at(MOB))
          assert.are.equal(2, select(2, logged(env):gsub("swing at " .. MOB, "")))
        end)

        it("is said afresh after anything that may have moved his target, back onto the same mob or not", function()
          local AUTO_TARGET = 234
          for _, moved in ipairs({
            function(queue)
              queue.on_outgoing(0x01A, outgoing_action(SWITCH_TARGET, 0, MOB + 1))
            end,
            function(queue)
              queue.on_message(fall_message(MOB + 1, AUTO_TARGET, ME))
            end,
            function(queue)
              queue.on_target(target_packet(ME, MOB + 1))
            end,
          }) do
            local queue, env = world({ mode = "debug" })
            queue.on_action(round_at(MOB))
            moved(queue)
            queue.on_action(round_at(MOB))
            assert.are.equal(2, select(2, logged(env):gsub("swing at " .. MOB .. ",", "")), logged(env))
          end
        end)

        it("is said afresh after debug was switched away and back", function()
          local queue, env = world({ mode = "debug" })
          queue.on_action(round_at(MOB))
          env.mode = "on"
          queue.on_action(round_at(MOB))
          env.mode = "debug"
          queue.on_action(round_at(MOB))
          env.mode = "off"
          queue.step()
          env.mode = "debug"
          queue.on_action(round_at(MOB))
          assert.are.equal(3, #env.log)
        end)

        it("asks the client nothing outside debug", function()
          local queue, env = world()
          queue.on_action(round_at(MOB))
          queue.on_message(message_about(MOB, OUT_OF_RANGE))
          assert.are.equal(0, env.target_asks)
          assert.are.same({}, env.log)
        end)

        it("leaves a round no action of the queue's: nothing is busy for one", function()
          local queue = world({ mode = "debug" })
          queue.on_action(round_at(MOB))
          assert.is_false(queue.busy())
          assert.is_false(queue.press(spell(), command()))
        end)
      end)
    end)
  end)
end)
