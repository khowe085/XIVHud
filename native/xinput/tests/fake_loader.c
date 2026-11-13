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

/* A scripted XInput for the binding's spec. In the test build lx_load hands
   the binding these calls instead of a DLL's, and luaopen__LuaXInputFake -
   reached through package.loadlib from the same build - is how the spec says
   what they answer. Never part of the real DLL. */

#include "lauxlib.h"
#include "loader.h"
#include "lua.h"

enum { CALL_STATE, CALL_VIBRATION, CALL_CAPABILITIES, CALL_BATTERY, CALL_KEYSTROKE, CALLS };

static const char *const call_names[] = {"get_state", "set_state", "get_capabilities", "get_battery",
                                         "get_keystroke", NULL};

static struct {
  int connected;
  lx_state state;
  lx_capabilities capabilities;
  lx_battery battery[2];
  lx_vibration vibration;
  int vibration_calls;
} pads[LX_MAX_PADS];

static const char *library;
static int missing[CALLS];
static int forced[CALLS];
static lx_dword forced_code[CALLS];
static lx_dword last_index[CALLS];
static lx_dword last_flags;
static lx_byte last_device;
static int keystroke_waiting;
static lx_keystroke keystroke;

static lx_dword answer(int call, lx_dword index, int needs_pad) {
  last_index[call] = index;
  if (forced[call]) {
    return forced_code[call];
  }
  if (needs_pad && (index >= LX_MAX_PADS || !pads[index].connected)) {
    return LX_ERROR_DEVICE_NOT_CONNECTED;
  }
  return LX_ERROR_SUCCESS;
}

static lx_dword LX_CALL fake_get_state(lx_dword index, lx_state *state) {
  lx_dword code = answer(CALL_STATE, index, 1);
  if (code == LX_ERROR_SUCCESS) {
    *state = pads[index].state;
  }
  return code;
}

static lx_dword LX_CALL fake_set_state(lx_dword index, lx_vibration *vibration) {
  lx_dword code = answer(CALL_VIBRATION, index, 1);
  if (code == LX_ERROR_SUCCESS) {
    pads[index].vibration = *vibration;
    pads[index].vibration_calls++;
  }
  return code;
}

static lx_dword LX_CALL fake_get_capabilities(lx_dword index, lx_dword flags, lx_capabilities *capabilities) {
  lx_dword code = answer(CALL_CAPABILITIES, index, 1);
  last_flags = flags;
  if (code == LX_ERROR_SUCCESS) {
    *capabilities = pads[index].capabilities;
  }
  return code;
}

static lx_dword LX_CALL fake_get_battery(lx_dword index, lx_byte device, lx_battery *battery) {
  lx_dword code = answer(CALL_BATTERY, index, 1);
  last_device = device;
  if (code == LX_ERROR_SUCCESS) {
    *battery = pads[index].battery[device == LX_BATTERY_DEVTYPE_HEADSET ? 1 : 0];
  }
  return code;
}

static lx_dword LX_CALL fake_get_keystroke(lx_dword index, lx_dword reserved, lx_keystroke *out) {
  lx_dword code;
  (void)reserved;
  code = answer(CALL_KEYSTROKE, index, index != LX_INDEX_ANY);
  if (code != LX_ERROR_SUCCESS) {
    return code;
  }
  if (!keystroke_waiting) {
    return LX_ERROR_EMPTY;
  }
  *out = keystroke;
  keystroke_waiting = 0;
  return LX_ERROR_SUCCESS;
}

void lx_load(lx_api *api) {
  api->library = library;
  api->get_state = library != NULL && !missing[CALL_STATE] ? fake_get_state : NULL;
  api->set_state = library != NULL && !missing[CALL_VIBRATION] ? fake_set_state : NULL;
  api->get_capabilities = library != NULL && !missing[CALL_CAPABILITIES] ? fake_get_capabilities : NULL;
  api->get_battery = library != NULL && !missing[CALL_BATTERY] ? fake_get_battery : NULL;
  api->get_keystroke = library != NULL && !missing[CALL_KEYSTROKE] ? fake_get_keystroke : NULL;
}

/* The control module ------------------------------------------------------ */

static lx_dword check_pad(lua_State *L, int arg) {
  lua_Integer index = luaL_checkinteger(L, arg);
  luaL_argcheck(L, index >= 0 && index < LX_MAX_PADS, arg, "pad index must be 0 to 3");
  return (lx_dword)index;
}

/* A field of the table at `t`, zero when absent. */
static lua_Integer field(lua_State *L, int t, const char *key) {
  lua_Integer value;
  lua_getfield(L, t, key);
  value = lua_tointeger(L, -1);
  lua_pop(L, 1);
  return value;
}

static void read_gamepad(lua_State *L, int t, lx_gamepad *gamepad) {
  gamepad->buttons = (lx_word)field(L, t, "buttons");
  gamepad->left_trigger = (lx_byte)field(L, t, "left_trigger");
  gamepad->right_trigger = (lx_byte)field(L, t, "right_trigger");
  gamepad->thumb_lx = (lx_short)field(L, t, "thumb_lx");
  gamepad->thumb_ly = (lx_short)field(L, t, "thumb_ly");
  gamepad->thumb_rx = (lx_short)field(L, t, "thumb_rx");
  gamepad->thumb_ry = (lx_short)field(L, t, "thumb_ry");
}

static int reset(lua_State *L) {
  int call;
  lx_dword index;
  (void)L;
  for (index = 0; index < LX_MAX_PADS; index++) {
    lx_state no_state = {0, {0, 0, 0, 0, 0, 0, 0}};
    lx_capabilities no_capabilities = {0, 0, 0, {0, 0, 0, 0, 0, 0, 0}, {0, 0}};
    pads[index].connected = 0;
    pads[index].state = no_state;
    pads[index].capabilities = no_capabilities;
    pads[index].battery[0].type = 0;
    pads[index].battery[0].level = 0;
    pads[index].battery[1].type = 0;
    pads[index].battery[1].level = 0;
    pads[index].vibration.left_motor = 0;
    pads[index].vibration.right_motor = 0;
    pads[index].vibration_calls = 0;
  }
  for (call = 0; call < CALLS; call++) {
    missing[call] = 0;
    forced[call] = 0;
    forced_code[call] = 0;
    last_index[call] = 0;
  }
  library = "fake_xinput.dll";
  last_flags = 0xFFFFFFFF;
  last_device = 0xFF;
  keystroke_waiting = 0;
  return 0;
}

/* connect(index [, state]) */
static int connect(lua_State *L) {
  lx_dword index = check_pad(L, 1);
  pads[index].connected = 1;
  if (lua_istable(L, 2)) {
    pads[index].state.packet = (lx_dword)field(L, 2, "packet");
    read_gamepad(L, 2, &pads[index].state.gamepad);
  }
  return 0;
}

static int disconnect(lua_State *L) {
  pads[check_pad(L, 1)].connected = 0;
  return 0;
}

/* capabilities(index, { type, subtype, flags, <gamepad fields>, left_motor, right_motor }) */
static int capabilities(lua_State *L) {
  lx_dword index = check_pad(L, 1);
  lx_capabilities *caps = &pads[index].capabilities;
  luaL_checktype(L, 2, LUA_TTABLE);
  caps->type = (lx_byte)field(L, 2, "type");
  caps->subtype = (lx_byte)field(L, 2, "subtype");
  caps->flags = (lx_word)field(L, 2, "flags");
  read_gamepad(L, 2, &caps->gamepad);
  caps->vibration.left_motor = (lx_word)field(L, 2, "left_motor");
  caps->vibration.right_motor = (lx_word)field(L, 2, "right_motor");
  return 0;
}

/* battery(index, device, type, level) - device 0 the gamepad, 1 the headset */
static int battery(lua_State *L) {
  lx_dword index = check_pad(L, 1);
  lua_Integer device = luaL_checkinteger(L, 2);
  lx_battery *slot = &pads[index].battery[device == 1 ? 1 : 0];
  slot->type = (lx_byte)luaL_checkinteger(L, 3);
  slot->level = (lx_byte)luaL_checkinteger(L, 4);
  return 0;
}

/* keystroke({ key, unicode, flags, user_index, hid_code }) - one, answered once */
static int queue_keystroke(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  keystroke.virtual_key = (lx_word)field(L, 1, "key");
  keystroke.unicode = (lx_word)field(L, 1, "unicode");
  keystroke.flags = (lx_word)field(L, 1, "flags");
  keystroke.user_index = (lx_byte)field(L, 1, "user_index");
  keystroke.hid_code = (lx_byte)field(L, 1, "hid_code");
  keystroke_waiting = 1;
  return 0;
}

/* force(call, code) - that call answers `code` whatever the pad */
static int force(lua_State *L) {
  int call = luaL_checkoption(L, 1, NULL, call_names);
  forced[call] = 1;
  forced_code[call] = (lx_dword)luaL_checkinteger(L, 2);
  return 0;
}

/* drop(call) - the library lacks that call, from the next open */
static int drop(lua_State *L) {
  missing[luaL_checkoption(L, 1, NULL, call_names)] = 1;
  return 0;
}

/* unload() - no XInput library at all, from the next open */
static int unload(lua_State *L) {
  (void)L;
  library = NULL;
  return 0;
}

/* vibration(index) -> left, right, how many times it was set */
static int vibration(lua_State *L) {
  lx_dword index = check_pad(L, 1);
  lua_pushinteger(L, pads[index].vibration.left_motor);
  lua_pushinteger(L, pads[index].vibration.right_motor);
  lua_pushinteger(L, pads[index].vibration_calls);
  return 3;
}

/* last_index(call) -> the index that call was last given */
static int get_last_index(lua_State *L) {
  lua_pushinteger(L, (lua_Integer)last_index[luaL_checkoption(L, 1, NULL, call_names)]);
  return 1;
}

static int get_last_flags(lua_State *L) {
  lua_pushinteger(L, (lua_Integer)last_flags);
  return 1;
}

static int get_last_device(lua_State *L) {
  lua_pushinteger(L, (lua_Integer)last_device);
  return 1;
}

static const luaL_Reg controls[] = {{"reset", reset},
                                    {"connect", connect},
                                    {"disconnect", disconnect},
                                    {"capabilities", capabilities},
                                    {"battery", battery},
                                    {"keystroke", queue_keystroke},
                                    {"force", force},
                                    {"drop", drop},
                                    {"unload", unload},
                                    {"vibration", vibration},
                                    {"last_index", get_last_index},
                                    {"last_flags", get_last_flags},
                                    {"last_device", get_last_device},
                                    {NULL, NULL}};

int luaopen__LuaXInputFake(lua_State *L) {
  reset(L);
  lua_newtable(L);
  luaL_register(L, NULL, controls);
  return 1;
}
