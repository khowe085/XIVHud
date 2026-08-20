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

--[[ Pure enchanted-item maths: charges, warmup and recast read from a decoded
     extdata table, with the clock injected as an argument. The equip -> wait
     -> use scheduling itself lives with the widget (the pending-warp state
     machine); this module only answers what the numbers mean.

     extdata's timestamps sit 18000 seconds off os.time -- the `+ 18000 - now`
     shape is MyHome's and the extdata library's own usage, kept as a named
     constant here.

     Everything here has a live caller: nothing is parked for the backlog
     enchanted-item slot feature (xivcrossbar's `enchanteditem` bind type),
     which the plan records as a binding/catalog question over this module
     rather than new maths. ]]

local enchanted = {}

-- extdata timestamps are offset this far from os.time.
local EXTDATA_OFFSET = 18000

-- An item needing more than this many seconds of warmup is abandoned at once
-- rather than waited out (MyHome's give-up rule -- a bound on the remaining
-- delay, not a timer).
local GIVE_UP_SECONDS = 30

--- Seconds until the enchantment can fire again; 0 when ready. Nil for a
--- non-enchanted item, one with no charges left, or an ext that is not
--- enchanted-shaped at all - the same degrade-not-throw posture step() has,
--- because this feeds warp's ladder walk.
function enchanted.recast_remaining(ext, now)
  if type(ext) ~= "table" or ext.type ~= "Enchanted Equipment" then
    return nil
  end
  if type(ext.charges_remaining) ~= "number" or ext.charges_remaining <= 0 then
    return nil
  end
  if type(ext.next_use_time) ~= "number" then
    return nil
  end
  return math.max(ext.next_use_time + EXTDATA_OFFSET - now, 0)
end

--- Seconds of equip warmup still to pass before the enchantment activates.
function enchanted.warmup_remaining(ext, now)
  return math.max(ext.activation_time + EXTDATA_OFFSET - now, 0)
end

--- One poll of the equip -> wait -> use plan: "use" when extdata reports the
--- item usable, "abandon" when the remaining delay exceeds the give-up bound,
--- "wait" otherwise. Nil for an ext that is not enchanted-shaped (no numeric
--- activation_time): this runs per frame under a shared handler guard, so a
--- foreign decode must degrade, never arithmetic-throw.
function enchanted.step(ext, now)
  if type(ext) ~= "table" then
    return nil
  end
  if ext.usable then
    return "use"
  end
  if type(ext.activation_time) ~= "number" then
    return nil
  end
  if enchanted.warmup_remaining(ext, now) > GIVE_UP_SECONDS then
    return "abandon"
  end
  return "wait"
end

return enchanted
