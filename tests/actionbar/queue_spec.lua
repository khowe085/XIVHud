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
    dead = {},
  }
  local dead = nil
  if not opts.no_dead then
    dead = function(id)
      return env.dead[id] == true
    end
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
    pin = function(command, target)
      if target == "me" then
        return command
      end
      if target == "t" then
        local id = env.pinned or 12345
        return (command:gsub(" <t>$", " " .. id)), id
      end
      return nil
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
    dead = dead,
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

    it("pins the target at the press", function()
      local queue = world()
      start_cast(queue)
      queue.press(spell("Stone", "t"), 'input /ma "Stone" <t>')
      assert.are.equal('input /ma "Stone" 12345', queue.held().command)
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
    local AIMED = 'input /ma "Shell V" 12345'

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
      assert.are.equal(AIMED, queue.held().command)
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
      assert.are.equal(AIMED, queue.held().command)
    end)

    it("casts the newest press at OK when another slot is pressed with the arrow up", function()
      local queue, env = world()
      finish_cast(queue)
      cursor_up(queue)
      env.arrow_up = true
      queue.press(spell("Protect V", "stpc"), 'input /ma "Protect V" <stpc>')
      queue.on_text("/ta 12345")
      assert.are.equal('input /ma "Protect V" 12345', queue.held().command)
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

    it("takes OK, so the /ta never changes your target, and holds the action at the chosen id", function()
      local queue = world()
      finish_cast(queue)
      cursor_up(queue)
      local swallowed, send = queue.on_text("/ta 12345")
      assert.is_true(swallowed)
      assert.is_nil(send)
      assert.are.equal(AIMED, queue.held().command)
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
      assert.are.equal('input /ma "Shell V" 777', queue.held().command)
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
      assert.are.equal(AIMED, queue.held().command)
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
      assert.are.equal(AIMED, queue.held().command)
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
      assert.are.equal(AIMED, queue.held().command)
    end)

    it("replaces what was held at OK, not at the press: the newest command wins", function()
      local queue = world()
      finish_cast(queue)
      queue.press(spell("Cure"), command("Cure"))
      cursor_up(queue)
      assert.are.equal(command("Cure"), queue.held().command)
      queue.on_text("/ta 12345")
      assert.are.equal(AIMED, queue.held().command)
    end)

    it("starts over for a press once the arrow has gone", function()
      local queue = world()
      finish_cast(queue)
      cursor_up(queue)
      local _, instead = queue.press(spell("Protect V", "stpc"), 'input /ma "Protect V" <stpc>')
      assert.are.equal("input /ta <stpc>", instead)
      assert.is_false(queue.on_text("/ta 777"), "the new cursor's arrow")
      queue.on_text("/ta 12345")
      assert.are.equal('input /ma "Protect V" 12345', queue.held().command)
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
        env.dead[MOB] = true
        queue.step()
        assert.is_false(queue.busy())
      end)

      it("sends what it held once that target is dead", function()
        local queue, env = world()
        queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
        queue.press(spell(), command())
        assert.is_nil(queue.step())
        env.dead[MOB] = true
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
        env.dead[MOB] = true
        queue.on_outgoing(0x01A, outgoing_action(MAGIC, 12, MOB))
        env.now = env.now + 1.99
        queue.step()
        assert.is_true(queue.busy())
      end)

      it("ends a start once its target is dead, with no lock", function()
        local queue, env = world()
        queue.on_action(weaponskill_at(MOB))
        queue.press(spell(), command())
        env.now = env.now + 0.3
        assert.is_nil(queue.step())
        env.dead[MOB] = true
        assert.are.equal(command(), queue.step())
      end)

      it("leaves a spell's start alone when its target is dead", function()
        local queue, env = world()
        env.casts.spell[12] = 3
        env.dead[MOB] = true
        local start = start_of(8, 12)
        start.targets[1].id = MOB
        queue.on_action(start)
        env.now = env.now + 1
        queue.step()
        assert.is_true(queue.busy())
      end)

      it("still locks on that weaponskill's finish if it comes after all", function()
        local queue, env = world()
        queue.on_action(weaponskill_at(MOB))
        env.dead[MOB] = true
        queue.step()
        assert.is_false(queue.busy())
        queue.on_action(action(3, 42))
        env.now = env.now + 2.39
        queue.step()
        assert.is_true(queue.busy())
      end)

      it("keeps the lock a lost finish was given when the death shows only after it", function()
        local queue, env = world()
        queue.on_action(weaponskill_at(MOB))
        env.now = env.now + 1.21
        queue.step()
        env.dead[MOB] = true
        env.now = env.now + 2.3
        queue.step()
        assert.is_true(queue.busy())
        env.now = env.now + 0.1
        queue.step()
        assert.is_false(queue.busy())
      end)

      it("ends the start that comes after the answer it stopped waiting for", function()
        local queue, env = world()
        queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
        env.dead[MOB] = true
        queue.step()
        queue.on_action(weaponskill_at(MOB))
        queue.step()
        assert.is_false(queue.busy())
      end)

      it("reads a client that cannot say as one whose target lives", function()
        local queue, env = world({ no_dead = true })
        queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
        queue.on_action(weaponskill_at(MOB))
        env.now = env.now + 1.19
        queue.step()
        assert.is_true(queue.busy())
      end)

      --[[ Kevin, 2026-11-12: ten weaponskills left for targets that died and
           every one waited out its 2s, and one that had started its 3.6s: the
           client's own table never showed the death in time. The game says a
           death in a 0x029, by the messages the Debuffed addon reads one off. ]]
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

      it("ends a start once the game says its target fell", function()
        local queue, env = world()
        queue.on_action(weaponskill_at(MOB))
        queue.press(spell(), command())
        env.now = env.now + 0.3
        assert.is_nil(queue.step())
        queue.on_message(fall_message(MOB))
        assert.are.equal(command(), queue.step())
      end)

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
      env.dead[MONSTER] = true
      assert.is_nil(release(queue, env))
      assert.is_nil(queue.held())
      assert.is_false(queue.busy())
    end)

    it("drops it when the game said that target fell", function()
      local queue, env = held_at(MONSTER, BLADE, BLADE_COMMAND)
      queue.on_message(fall_message(MONSTER))
      assert.is_nil(release(queue, env))
      assert.is_nil(queue.held())
    end)

    it("releases a weaponskill whose target lives", function()
      local queue, env = held_at(MONSTER, BLADE, BLADE_COMMAND)
      env.dead[MONSTER + 1] = true
      assert.are.equal('input /ws "Savage Blade" 17000001', release(queue, env))
    end)

    it("drops a spell pinned to a dead monster", function()
      local queue, env = held_at(MONSTER, SLEEPGA, SLEEPGA_COMMAND)
      env.dead[MONSTER] = true
      assert.is_nil(release(queue, env))
      assert.is_nil(queue.held())
    end)

    it("releases a spell pinned to a dead player: a Raise is aimed at one", function()
      local queue, env = held_at(PLAYER, { type = "ma", action = "Raise", target = "t" }, 'input /ma "Raise" <t>')
      env.dead[PLAYER] = true
      assert.are.equal('input /ma "Raise" 71391', release(queue, env))
    end)

    it("releases an ability pinned to a dead monster, which is the game's to refuse", function()
      local queue, env = held_at(MONSTER, PROVOKE, PROVOKE_COMMAND)
      env.dead[MONSTER] = true
      assert.are.equal('input /ja "Provoke" 17000001', release(queue, env))
    end)

    it("releases what was pinned to nothing", function()
      local queue, env = held_at(MONSTER, spell(), command())
      env.dead[MONSTER] = true
      assert.are.equal(command(), release(queue, env))
    end)

    it("judges the target a newer press pinned", function()
      local queue, env = held_at(MONSTER, BLADE, BLADE_COMMAND)
      env.dead[MONSTER] = true
      env.pinned = MONSTER + 1
      queue.press(BLADE, BLADE_COMMAND)
      assert.are.equal('input /ws "Savage Blade" 17000002', release(queue, env))
    end)

    it("drops a cursor's weaponskill whose target died after OK", function()
      local queue, env = world()
      env.player.vitals = { tp = 3000, hp = 1500 }
      start_cast(queue)
      queue.press({ type = "ws", action = "Savage Blade", target = "stnpc" }, 'input /ws "Savage Blade" <stnpc>')
      queue.on_text("/ta <stnpc>")
      queue.on_text("/ta 17000001")
      queue.on_text("/ta 17000001")
      queue.on_action(action(4, 1))
      env.dead[MONSTER] = true
      assert.is_nil(release(queue, env))
      assert.is_nil(queue.held())
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
      assert.are.equal('input /ws "Savage Blade" 12345', queue.held().command)
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
      assert.are.equal('input /ws "Savage Blade" 12345', queue.step())
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
        assert.are.equal('input /ws "Savage Blade" 12345', send)
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
        assert.are.equal('input /ws "Savage Blade" 12345', send)
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
      env.dead[MOB] = true
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

    it("names a system message that comes with a send unanswered", function()
      local queue, env = world({ mode = "debug" })
      queue.on_outgoing(0x01A, outgoing_action(MAGIC, 12))
      env.now = env.now + 0.5
      queue.on_system_message(system_message(298, 7))
      assert.truthy(logged(env):find("system message 298 (param 7) with the last send unanswered", 1, true))
      queue.step()
      assert.is_true(queue.busy())
    end)

    it("stays quiet about a system message with nothing unanswered, or too short to read", function()
      local queue, env = world({ mode = "debug" })
      queue.on_system_message(system_message(298))
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
      env.dead[MOB] = true
      queue.on_outgoing(0x01A, outgoing_action(WEAPONSKILL, 42, MOB))
      queue.step()
      assert.is_not_nil(logged(env):find("the target died, no answer to come", 1, true))
      queue.on_action(weaponskill_at(MOB))
      queue.step()
      assert.is_not_nil(logged(env):find("the target died, no finish to come", 1, true))
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
  end)
end)
