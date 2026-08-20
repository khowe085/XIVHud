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

--[[ Action name -> icon file name, taken verbatim from xivcrossbar's
     libs/kebab_casify.lua (MIT (c) 2020 AliekberFFXI): icon files resolve
     as <category>/<kebab_casify(name)>.png. The full MIT notice text is
     reproduced in this component's assets/LICENSE.txt, alongside the other
     upstream notices the CB4 asset import carries.

     The QMARK / newline shuffle is upstream's trick for keeping '?' and '/'
     through the punctuation strip: both are %p, so each is parked as something
     the strip ignores (letters were lowercased first, so 'QMARK' cannot occur
     naturally; '\n' is a control character, not punctuation) and restored at
     the end. ]]

local function kebab(name)
  local result = name
    :lower()
    :gsub("?", "QMARK")
    :gsub("/", "\n")
    :gsub(":", "")
    :gsub("-", " ")
    :gsub("%p", "")
    :gsub(" ", "-")
    :gsub("\n", "/")
    :gsub("QMARK", "?")
  return result
end

return kebab
