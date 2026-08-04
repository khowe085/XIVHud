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

--[[ Error isolation for Windower event handlers.

     Windower calls our handlers directly, and `prerender` runs every frame. An
     error in there recurs sixty times a second: the useful first message is
     buried instantly, and the client can be wedged by the sheer volume. Worse,
     a handler that dies part way through can leave input captured, which reads
     to the player as a freeze rather than as a bug.

     So every handler is wrapped: the first distinct error is reported, repeats
     of the same message are swallowed, and a handler that keeps failing is
     switched off entirely rather than being allowed to run every frame. The
     addon degrades to doing nothing, which is always better than taking the
     game with it. ]]

local DEFAULT_LIMIT = 5

local function new(deps)
  local self = {}
  local limit = deps.limit or DEFAULT_LIMIT
  local any_failed = false

  local function notify(message)
    if deps.notify then
      deps.notify(message)
    end
  end

  -- Wraps one handler. `fallback` is returned whenever the handler fails or has
  -- been switched off — pass `false` for the mouse and keyboard handlers, whose
  -- return value decides whether input reaches the game.
  function self.wrap(name, handler, fallback)
    local errors, last_message, disabled = 0, nil, false

    return function(...)
      if disabled then
        return fallback
      end

      local results = { pcall(handler, ...) }
      if results[1] then
        return unpack(results, 2)
      end

      local message = tostring(results[2])
      errors = errors + 1

      -- The same error every frame is one piece of information, not sixty.
      if message ~= last_message then
        last_message = message
        notify("error in the " .. name .. " handler: " .. message)
      end

      if errors >= limit then
        disabled = true
        any_failed = true
        notify(
          ("the %s handler has been disabled after %d failures — '//lua reload xivhud' to try again"):format(
            name,
            errors
          )
        )
      end

      return fallback
    end
  end

  function self.failed()
    return any_failed
  end

  return self
end

return new
