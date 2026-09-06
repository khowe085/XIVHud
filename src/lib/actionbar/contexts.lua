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

--[[ The code-defined context roster: buff-conditioned binding layers, in
     stack order -- later in the list wins. Definitions and their order are
     code; users author only the per-context overrides (in the per-job files).
     Adding a context is one entry here. The roster is the SCH arts/addendum
     family (buff ids ported from an xivcrossbar fork) plus BLU's Unbridled
     Learning.

     Every entry names the JOB it belongs to, and off that job it is neither
     listed nor live (Kevin, 2026-09-04): a context watches a buff only one
     job can raise, so an entry on the wrong job is a layer that could never
     fire. `jobs` counts the sub job as well as the main, since an arts
     context is reachable on /SCH; `main_only` narrows it back to the main
     job for an ability no subjob can hold.

     A context is active while ANY buff in `any_of` is up. The addendum ids
     appear in the arts predicates too: using an Addendum makes FFXI
     re-evaluate the arts status and fire a spurious arts `lose buff` while
     arts is still active, so the arts layer must survive on the addendum buff
     alone. (The other half of that defence -- re-syncing from the full buff
     list rather than deltas -- belongs to the binding model.) ]]

local contexts = {
  {
    name = "light-arts",
    label = "Light Arts",
    any_of = { 358, 401 }, -- Light Arts; Addendum: White implies it
    icon = "abilities/book_white",
    jobs = { "SCH" },
  },
  {
    name = "dark-arts",
    label = "Dark Arts",
    any_of = { 359, 402 }, -- Dark Arts; Addendum: Black implies it
    icon = "abilities/book_black",
    jobs = { "SCH" },
  },
  {
    name = "addendum-white",
    label = "Addendum: White",
    any_of = { 401 },
    icon = "abilities/book_white",
    jobs = { "SCH" },
  },
  {
    name = "addendum-black",
    label = "Addendum: Black",
    any_of = { 402 },
    icon = "abilities/book_black",
    jobs = { "SCH" },
  },
  --[[ Learning and its merit upgrade Wisdom under one name: the two open the
       same door and the bar wants the same slots for either, so they sit in
       one predicate the way an addendum sits in its arts. Last in the roster,
       and so above the arts family where a slot somehow held both - which no
       single job can produce, one family being BLU-main and the other SCH.

       The icon is the JOB's rather than the ability's: the shipped ability
       sheet is keyed by RECAST id (render.lua), and this container cannot
       look one up. ]]
  {
    name = "unbridled",
    label = "Unbridled Learning",
    any_of = { 485, 505 }, -- Unbridled Learning; Unbridled Wisdom
    icon = "jobs/blu",
    jobs = { "BLU" },
    -- Learned at BLU 96: no subjob can ever hold it.
    main_only = true,
  },
}

return contexts
