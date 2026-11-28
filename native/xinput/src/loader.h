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

/* The seam between the binding and XInput itself: loader_windows.c finds the
   real calls, and the tests' fake_loader.c scripts them. */

#ifndef LUAXINPUT_LOADER_H
#define LUAXINPUT_LOADER_H

#include "xinput_abi.h"

/* XInput's calls are WINAPI, which matters on 32-bit Windows alone. */
#if defined(_WIN32)
#define LX_CALL __stdcall
#else
#define LX_CALL
#endif

typedef lx_dword(LX_CALL *lx_get_state_fn)(lx_dword index, lx_state *state);
typedef lx_dword(LX_CALL *lx_set_state_fn)(lx_dword index, lx_vibration *vibration);
typedef lx_dword(LX_CALL *lx_get_capabilities_fn)(lx_dword index, lx_dword flags, lx_capabilities *capabilities);
typedef lx_dword(LX_CALL *lx_get_battery_fn)(lx_dword index, lx_byte device, lx_battery *battery);
typedef lx_dword(LX_CALL *lx_get_keystroke_fn)(lx_dword index, lx_dword reserved, lx_keystroke *keystroke);

typedef struct {
  /* The DLL the calls came from; NULL when none was found, and then every
     call below is NULL too. */
  const char *library;
  lx_get_state_fn get_state;
  lx_set_state_fn set_state;
  lx_get_capabilities_fn get_capabilities;
  lx_get_battery_fn get_battery;
  lx_get_keystroke_fn get_keystroke;
} lx_api;

/* Fills `api`, a call the library lacks left NULL. Run at every open. */
void lx_load(lx_api *api);

#endif
