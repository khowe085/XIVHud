local new_queue = require("lib/actionbar/queue")

local ME = 777
local SOMEONE = 888

local MAGIC, WEAPONSKILL, ABILITY, RANGED = 3, 7, 9, 16
local INTERRUPTED = 28787
local STARTING = 24931

local function world(opts)
  opts = opts or {}
  local env = {
    now = 100,
    mode = opts.mode or "on",
    player = { id = ME },
    chat = {},
    log = {},
    recast = {},
    names = {},
    blocked = nil,
    pins = {},
  }
  local queue = new_queue({
    now = function()
      return env.now
    end,
    config = function()
      return { queue = env.mode, queue_locks = env.locks }
    end,
    get_player = function()
      return env.player
    end,
    say = function(line)
      env.chat[#env.chat + 1] = line
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
        return (command:gsub(" <t>$", " 12345"))
      end
      return nil
    end,
    blocked = function()
      return env.blocked
    end,
    name_of = function(_, id)
      return env.names[id]
    end,
    arrow_up = function()
      return env.arrow_up == true
    end,
  })
  return queue, env
end

local function said(env)
  return table.concat(env.chat, "\n")
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

-- A raw outgoing 0x01A with its category at 0x0A and its param at 0x0C.
local function outgoing_action(category, param)
  param = param or 0
  local low, high = category % 256, math.floor(category / 256)
  return string.rep("\0", 10)
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

describe("the action queue", function()
  describe("its mode", function()
    it("ships off, and reads a broken value as off", function()
      local queue, env = world({ mode = "off" })
      assert.are.same({ queue = "off" }, queue.defaults())
      assert.are.equal("off", queue.mode())
      assert.is_false(queue.enabled())
      env.mode = "sometimes"
      assert.are.equal("off", queue.mode())
      assert.is_false(queue.enabled())
      env.mode = 1
      assert.are.equal("off", queue.mode())
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
      assert.is_not_nil(said(env):find("finish spell, lock 2.50s", 1, true))
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

    it("leaves an arrow it did not open to the game: a macro's OK is its own", function()
      local queue, env = world()
      env.arrow_up = true
      local taken, instead = queue.press(SHELL, SHELL_COMMAND)
      assert.is_false(taken)
      assert.is_nil(instead)
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
      env.recast["Shell V"] = 4
      local swallowed, send = queue.on_text("/ta 12345")
      assert.is_true(swallowed)
      assert.are.equal(AIMED, send)
      assert.is_nil(queue.held())
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
      start_cast(queue)
      queue.on_action(action(4, 1))
      queue.on_action(action(8, INTERRUPTED))
      env.now = env.now + 2.71
      assert.is_false(queue.busy())
    end)

    it("keeps the interrupt's lock when the finish comes after it", function()
      local queue, env = world()
      start_cast(queue)
      queue.on_action(action(8, INTERRUPTED))
      queue.on_action(action(4, 1))
      env.now = env.now + 2.71
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
      env.recast.Cure = 2
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
      assert.are.same({}, env.chat)
    end)

    it("says nothing in off", function()
      local queue, env = world({ mode = "off" })
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      start_cast(queue)
      finish_cast(queue)
      assert.are.same({}, env.chat)
    end)

    it("writes every line to the log too, for a client nobody is sitting at", function()
      local queue, env = world({ mode = "debug" })
      finish_cast(queue)
      assert.are.equal(2, #env.log)
      assert.are.same(env.chat, env.log)
    end)

    it("names what went out", function()
      local queue, env = world({ mode = "debug" })
      env.names[143] = "Cure IV"
      queue.on_outgoing(0x01A, outgoing_action(MAGIC, 143))
      assert.is_not_nil(said(env):find("out spell Cure IV", 1, true))
    end)

    it("says the id of what it cannot name", function()
      local queue, env = world({ mode = "debug" })
      queue.on_outgoing(0x01A, outgoing_action(MAGIC, 143))
      assert.is_not_nil(said(env):find("out spell 143", 1, true))
    end)

    it("says a category 4 it ignored, with the message that explains it", function()
      local queue, env = world({ mode = "debug" })
      queue.on_action(paralyzed_round(84))
      assert.is_not_nil(said(env):find("ignored a finish with no cast running, message 84", 1, true))
      assert.is_nil(said(env):find("lock", 1, true))
    end)

    it("copes with one that carries no message", function()
      local queue, env = world({ mode = "debug" })
      assert.has_no.errors(function()
        queue.on_action(action(4, 0))
      end)
      assert.is_not_nil(said(env):find("ignored a finish with no cast running", 1, true))
    end)

    it("says the arrow, so a cursor that never raised one shows", function()
      local queue, env = world({ mode = "debug" })
      start_cast(queue)
      queue.press(spell("Shell V", "stpc"), 'input /ma "Shell V" <stpc>')
      queue.on_text("/ta 777")
      assert.is_not_nil(said(env):find("arrow 777", 1, true))
    end)

    it("writes nothing to the log in on or off", function()
      for _, mode in ipairs({ "on", "off" }) do
        local queue, env = world({ mode = mode })
        start_cast(queue)
        finish_cast(queue)
        assert.are.same({}, env.log)
      end
    end)

    it("stamps every line with the clock", function()
      local queue, env = world({ mode = "debug" })
      env.now = 123.456
      start_cast(queue)
      assert.is_not_nil(said(env):find("queue 123.46: ", 1, true))
    end)

    it("says what went out and how long after the last finish", function()
      local queue, env = world({ mode = "debug" })
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      assert.is_not_nil(said(env):find("out spell", 1, true))
      finish_cast(queue)
      env.chat = {}
      env.now = env.now + 2.41
      queue.on_outgoing(0x01A, outgoing_action(ABILITY))
      assert.is_not_nil(said(env):find("out ability +2.41s after finish", 1, true))
    end)

    it("says what started, finished and was interrupted", function()
      local queue, env = world({ mode = "debug" })
      start_cast(queue)
      assert.is_not_nil(said(env):find("start spell", 1, true))
      finish_cast(queue)
      assert.is_not_nil(said(env):find("finish spell, lock 2.70s", 1, true))
      queue.on_action(action(7, STARTING))
      queue.on_action(action(7, INTERRUPTED))
      assert.is_not_nil(said(env):find("interrupted weaponskill, lock 2.70s", 1, true))
    end)

    it("says a start's distance from the last finish, the other half of the bracket", function()
      local queue, env = world({ mode = "debug" })
      finish_cast(queue)
      env.chat = {}
      env.now = env.now + 2.8
      start_cast(queue)
      assert.is_not_nil(said(env):find("start spell +2.80s after finish", 1, true))
    end)

    it("says a refusal's message and distance from the last finish", function()
      local queue, env = world({ mode = "debug" })
      finish_cast(queue)
      env.chat = {}
      env.now = env.now + 2.4
      queue.on_message(battle_message(ME, 17))
      assert.is_not_nil(said(env):find("refused, message 17 +2.40s after finish", 1, true))
    end)

    it("stays quiet about a message that is not a refusal", function()
      local queue, env = world({ mode = "debug" })
      queue.on_message(battle_message(ME, 94))
      assert.are.same({}, env.chat)
    end)

    it("says what it held, replaced, released and dropped", function()
      local queue, env = world({ mode = "debug" })
      finish_cast(queue)
      queue.press(spell("Cure"), command("Cure"))
      assert.is_not_nil(said(env):find("hold Cure", 1, true))
      env.now = env.now + 1
      queue.press(spell("Stone"), command("Stone"))
      assert.is_not_nil(said(env):find("hold Stone, replacing Cure", 1, true))
      env.now = env.now + 2.01
      queue.step()
      assert.is_not_nil(said(env):find("release Stone after 2.01s", 1, true))
      queue.press(spell("Cure"), command("Cure"))
      queue.drop("re-attach")
      assert.is_not_nil(said(env):find("dropped Cure: re-attach", 1, true))
    end)

    it("says why a press was not held", function()
      local queue, env = world({ mode = "debug" })
      start_cast(queue)
      env.recast.Cure = 4
      queue.press(spell("Cure"), command("Cure"))
      assert.is_not_nil(said(env):find("not held: Cure on recast", 1, true))
      queue.press(spell("Stone", "ft"), 'input /ma "Stone" <ft>')
      assert.is_not_nil(said(env):find("not held: Stone, <ft> cannot be pinned", 1, true))
      env.blocked = "edit mode"
      queue.press(spell("Stone"), command("Stone"))
      assert.is_not_nil(said(env):find("not held: Stone, edit mode", 1, true))
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
      assert.truthy(said(env):find("swallowed Savage Blade, no TP", 1, true))
      env.now = env.now + 2.41
      queue.step()
      assert.truthy(said(env):find("dropped Savage Blade: no TP", 1, true))
    end)

    it("says a press was already going", function()
      local queue, env = world({ mode = "debug" })
      queue.press(spell("Cure"), command("Cure"))
      queue.press(spell("Cure"), command("Cure"))
      assert.is_not_nil(said(env):find("swallowed Cure, already going", 1, true))
    end)

    it("says what a cursor did", function()
      local queue, env = world({ mode = "debug" })
      start_cast(queue)
      queue.press(spell("Shell V", "stpc"), 'input /ma "Shell V" <stpc>')
      assert.is_not_nil(said(env):find("cursor Shell V <stpc>", 1, true))
      queue.on_text("/ta 777")
      queue.on_text("/ta 12345")
      assert.is_not_nil(said(env):find("OK Shell V at 12345", 1, true))
      assert.is_not_nil(said(env):find("hold Shell V", 1, true))
    end)

    it("says a press that only changed what OK casts", function()
      local queue, env = world({ mode = "debug" })
      queue.press(spell("Shell V", "stpc"), 'input /ma "Shell V" <stpc>')
      env.arrow_up = true
      queue.press(spell("Protect V", "stpc"), 'input /ma "Protect V" <stpc>')
      assert.is_not_nil(said(env):find("cursor up, OK takes Protect V", 1, true))
    end)

    it("says a cursor given up for another", function()
      local queue, env = world({ mode = "debug" })
      start_cast(queue)
      queue.press(spell("Shell V", "stpc"), 'input /ma "Shell V" <stpc>')
      queue.on_text("/ta 777")
      queue.on_text("/ta <stnpc>")
      assert.is_not_nil(said(env):find("no OK for Shell V", 1, true))
    end)

    it("says a cursor nobody confirmed", function()
      local queue, env = world({ mode = "debug" })
      start_cast(queue)
      queue.press(spell("Shell V", "stpc"), 'input /ma "Shell V" <stpc>')
      env.now = env.now + 30.01
      queue.step()
      assert.is_not_nil(said(env):find("no OK for Shell V", 1, true))
    end)

    it("says a release lost to its recast", function()
      local queue, env = world({ mode = "debug" })
      start_cast(queue)
      queue.press(spell("Cure"), command("Cure"))
      finish_cast(queue)
      env.recast.Cure = 2
      env.now = env.now + 3.01
      queue.step()
      assert.is_not_nil(said(env):find("dropped Cure: on recast", 1, true))
    end)

    it("says a backstop fired, which is the case worth seeing", function()
      local queue, env = world({ mode = "debug" })
      queue.press(spell(), command())
      env.now = env.now + 0.61
      queue.step()
      assert.is_not_nil(said(env):find("nothing went out for the last press", 1, true))
      env.chat = {}
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      env.now = env.now + 2.01
      queue.step()
      assert.is_not_nil(said(env):find("no answer to the last send", 1, true))
      env.chat = {}
      start_cast(queue)
      env.now = env.now + 30.01
      queue.step()
      assert.is_not_nil(said(env):find("no finish for the last start", 1, true))
    end)

    it("says when the lock clears, once", function()
      local queue, env = world({ mode = "debug" })
      finish_cast(queue)
      env.chat = {}
      env.now = env.now + 3.01
      queue.step()
      queue.step()
      assert.are.equal(1, #env.chat)
      assert.is_not_nil(said(env):find("lock over", 1, true))
    end)

    it("says a clear", function()
      local queue, env = world({ mode = "debug" })
      start_cast(queue)
      queue.press(spell(), command())
      queue.clear("zone")
      assert.is_not_nil(said(env):find("cleared: zone", 1, true))
    end)

    it("is plain ASCII, because chat is not UTF-8", function()
      local queue, env = world({ mode = "debug" })
      queue.on_outgoing(0x01A, outgoing_action(MAGIC))
      start_cast(queue)
      queue.press(spell(), command())
      finish_cast(queue)
      env.now = env.now + 3.01
      queue.step()
      assert.is_nil(said(env):find("[\128-\255]"))
    end)
  end)
end)
