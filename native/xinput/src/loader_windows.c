/*
Copyright © 2026, Azureblood2
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of LuaXInput nor the
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
*/

/* The real XInput: the newest of Windows' three XInput DLLs that has
   XInputGetState, each call resolved on its own, so one the DLL lacks is
   NULL rather than a failed load. */

#include <string.h>
#include <windows.h>

#include "loader.h"

static const char *const libraries[] = {"xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll"};

/* From the system directory alone, so a DLL of the same name dropped beside
   the game cannot stand in for Windows' own. Never freed: a read must never
   land in a library that has been unloaded. */
static HMODULE load_system(const char *name) {
  char path[MAX_PATH];
  UINT length = GetSystemDirectoryA(path, MAX_PATH);
  size_t name_length = strlen(name);
  if (length == 0 || length + 1 + name_length + 1 > MAX_PATH) {
    return NULL;
  }
  path[length] = '\\';
  memcpy(path + length + 1, name, name_length + 1);
  return LoadLibraryA(path);
}

/* Through `void (*)(void)`, the pointer type every compiler lets any function
   pointer pass through without a warning. */
typedef void (*lx_any_fn)(void);

static lx_any_fn find(HMODULE module, const char *name) {
  return (lx_any_fn)GetProcAddress(module, name);
}

void lx_load(lx_api *api) {
  size_t i;
  memset(api, 0, sizeof *api);
  for (i = 0; i < sizeof libraries / sizeof libraries[0]; i++) {
    HMODULE module = load_system(libraries[i]);
    lx_any_fn get_state;
    if (module == NULL) {
      continue;
    }
    get_state = find(module, "XInputGetState");
    if (get_state == NULL) {
      continue;
    }
    api->library = libraries[i];
    api->get_state = (lx_get_state_fn)get_state;
    api->set_state = (lx_set_state_fn)find(module, "XInputSetState");
    api->get_capabilities = (lx_get_capabilities_fn)find(module, "XInputGetCapabilities");
    api->get_battery = (lx_get_battery_fn)find(module, "XInputGetBatteryInformation");
    api->get_keystroke = (lx_get_keystroke_fn)find(module, "XInputGetKeystroke");
    return;
  }
}
