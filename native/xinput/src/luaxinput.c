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

/* _LuaXInput: XInput for Lua 5.1, `require('_LuaXInput')`. README.md is the
   reference. A call that cannot answer returns nil, a reason and - where
   Windows gave one - its code; a bad argument raises, as the Lua API's own
   checks do. */

#include "lauxlib.h"
#include "loader.h"
#include "lua.h"

#if defined(_WIN32)
#define LUAXINPUT_EXPORT __declspec(dllexport)
#else
#define LUAXINPUT_EXPORT
#endif

#define LUAXINPUT_VERSION "1.0.0"

static lx_api api;

static const char *const devices[] = {"gamepad", "headset", NULL};

static void set_integer(lua_State *L, const char *key, lua_Integer value) {
  lua_pushinteger(L, value);
  lua_setfield(L, -2, key);
}

static void set_boolean(lua_State *L, const char *key, int value) {
  lua_pushboolean(L, value);
  lua_setfield(L, -2, key);
}

static void set_string(lua_State *L, const char *key, const char *value) {
  lua_pushstring(L, value);
  lua_setfield(L, -2, key);
}

static void set_gamepad(lua_State *L, const lx_gamepad *gamepad) {
  set_integer(L, "buttons", gamepad->buttons);
  set_integer(L, "left_trigger", gamepad->left_trigger);
  set_integer(L, "right_trigger", gamepad->right_trigger);
  set_integer(L, "thumb_lx", gamepad->thumb_lx);
  set_integer(L, "thumb_ly", gamepad->thumb_ly);
  set_integer(L, "thumb_rx", gamepad->thumb_rx);
  set_integer(L, "thumb_ry", gamepad->thumb_ry);
}

static lx_dword check_pad(lua_State *L, int arg) {
  lua_Integer index = luaL_checkinteger(L, arg);
  luaL_argcheck(L, index >= 0 && index < LX_MAX_PADS, arg, "pad index must be 0 to 3");
  return (lx_dword)index;
}

/* An `out` argument is checked before XInput is asked, so a wrong one raises
   whether or not a pad answers. */
static void check_out(lua_State *L, int arg) {
  if (!lua_isnoneornil(L, arg)) {
    luaL_checktype(L, arg, LUA_TTABLE);
  }
}

/* Leaves the table to fill on top: `out` when one was given, else a new one. */
static void push_out(lua_State *L, int arg, int fields) {
  if (lua_isnoneornil(L, arg)) {
    lua_createtable(L, 0, fields);
  } else {
    lua_pushvalue(L, arg);
  }
}

static int failed(lua_State *L, lx_dword code) {
  lua_pushnil(L);
  if (code == LX_ERROR_DEVICE_NOT_CONNECTED) {
    lua_pushstring(L, "not_connected");
  } else if (code == LX_ERROR_EMPTY) {
    lua_pushstring(L, "empty");
  } else {
    lua_pushstring(L, "error");
  }
  lua_pushinteger(L, (lua_Integer)code);
  return 3;
}

/* No XInput DLL at all, or one without this call. */
static int unavailable(lua_State *L) {
  lua_pushnil(L);
  lua_pushstring(L, api.library == NULL ? "no_xinput" : "not_supported");
  return 2;
}

static int library(lua_State *L) {
  if (api.library == NULL) {
    lua_pushnil(L);
  } else {
    lua_pushstring(L, api.library);
  }
  return 1;
}

/* get_state(index [, out]) */
static int get_state(lua_State *L) {
  lx_state state = {0, {0, 0, 0, 0, 0, 0, 0}};
  lx_dword index = check_pad(L, 1);
  lx_dword code;
  check_out(L, 2);
  if (api.get_state == NULL) {
    return unavailable(L);
  }
  code = api.get_state(index, &state);
  if (code != LX_ERROR_SUCCESS) {
    return failed(L, code);
  }
  push_out(L, 2, 8);
  set_integer(L, "packet", (lua_Integer)state.packet);
  set_gamepad(L, &state.gamepad);
  return 1;
}

static lx_word check_motor(lua_State *L, int arg) {
  lua_Integer speed = luaL_checkinteger(L, arg);
  luaL_argcheck(L, speed >= 0 && speed <= 65535, arg, "motor speed must be 0 to 65535");
  return (lx_word)speed;
}

/* set_vibration(index, left, right) */
static int set_vibration(lua_State *L) {
  lx_vibration vibration;
  lx_dword index = check_pad(L, 1);
  lx_dword code;
  vibration.left_motor = check_motor(L, 2);
  vibration.right_motor = check_motor(L, 3);
  if (api.set_state == NULL) {
    return unavailable(L);
  }
  code = api.set_state(index, &vibration);
  if (code != LX_ERROR_SUCCESS) {
    return failed(L, code);
  }
  lua_pushboolean(L, 1);
  return 1;
}

/* get_capabilities(index [, out]) - of any device type, XInput's flags 0 */
static int get_capabilities(lua_State *L) {
  lx_capabilities capabilities = {0, 0, 0, {0, 0, 0, 0, 0, 0, 0}, {0, 0}};
  lx_dword index = check_pad(L, 1);
  lx_dword code;
  check_out(L, 2);
  if (api.get_capabilities == NULL) {
    return unavailable(L);
  }
  code = api.get_capabilities(index, 0, &capabilities);
  if (code != LX_ERROR_SUCCESS) {
    return failed(L, code);
  }
  push_out(L, 2, 12);
  set_integer(L, "type", capabilities.type);
  set_integer(L, "subtype", capabilities.subtype);
  set_integer(L, "flags", capabilities.flags);
  set_gamepad(L, &capabilities.gamepad);
  set_integer(L, "left_motor", capabilities.vibration.left_motor);
  set_integer(L, "right_motor", capabilities.vibration.right_motor);
  return 1;
}

static const char *battery_type(lx_byte type) {
  switch (type) {
  case LX_BATTERY_TYPE_DISCONNECTED:
    return "disconnected";
  case LX_BATTERY_TYPE_WIRED:
    return "wired";
  case LX_BATTERY_TYPE_ALKALINE:
    return "alkaline";
  case LX_BATTERY_TYPE_NIMH:
    return "nimh";
  default:
    return "unknown";
  }
}

static const char *battery_level(lx_byte level) {
  switch (level) {
  case LX_BATTERY_LEVEL_EMPTY:
    return "empty";
  case LX_BATTERY_LEVEL_LOW:
    return "low";
  case LX_BATTERY_LEVEL_MEDIUM:
    return "medium";
  case LX_BATTERY_LEVEL_FULL:
    return "full";
  default:
    return "unknown";
  }
}

/* get_battery(index [, "gamepad" | "headset"]) */
static int get_battery(lua_State *L) {
  lx_battery battery = {0, 0};
  lx_dword index = check_pad(L, 1);
  lx_byte device = (lx_byte)(luaL_checkoption(L, 2, "gamepad", devices) == 1 ? LX_BATTERY_DEVTYPE_HEADSET
                                                                              : LX_BATTERY_DEVTYPE_GAMEPAD);
  lx_dword code;
  if (api.get_battery == NULL) {
    return unavailable(L);
  }
  code = api.get_battery(index, device, &battery);
  if (code != LX_ERROR_SUCCESS) {
    return failed(L, code);
  }
  lua_createtable(L, 0, 2);
  set_string(L, "type", battery_type(battery.type));
  set_string(L, "level", battery_level(battery.level));
  return 1;
}

/* get_keystroke(index) - a pad, or ANY for whichever has one waiting */
static int get_keystroke(lua_State *L) {
  lx_keystroke keystroke = {0, 0, 0, 0, 0};
  lua_Integer index = luaL_checkinteger(L, 1);
  lx_dword code;
  luaL_argcheck(L, (index >= 0 && index < LX_MAX_PADS) || index == LX_INDEX_ANY, 1,
                "pad index must be 0 to 3, or ANY");
  if (api.get_keystroke == NULL) {
    return unavailable(L);
  }
  code = api.get_keystroke((lx_dword)index, 0, &keystroke);
  if (code != LX_ERROR_SUCCESS) {
    return failed(L, code);
  }
  lua_createtable(L, 0, 7);
  set_integer(L, "key", keystroke.virtual_key);
  set_integer(L, "unicode", keystroke.unicode);
  set_integer(L, "user_index", keystroke.user_index);
  set_integer(L, "hid_code", keystroke.hid_code);
  set_boolean(L, "down", (keystroke.flags & LX_KEYSTROKE_KEYDOWN) != 0);
  set_boolean(L, "up", (keystroke.flags & LX_KEYSTROKE_KEYUP) != 0);
  set_boolean(L, "repeating", (keystroke.flags & LX_KEYSTROKE_REPEAT) != 0);
  return 1;
}

static const luaL_Reg functions[] = {{"library", library},
                                     {"get_state", get_state},
                                     {"set_vibration", set_vibration},
                                     {"get_capabilities", get_capabilities},
                                     {"get_battery", get_battery},
                                     {"get_keystroke", get_keystroke},
                                     {NULL, NULL}};

static void set_buttons(lua_State *L) {
  lua_createtable(L, 0, 14);
  set_integer(L, "dpad_up", 0x0001);
  set_integer(L, "dpad_down", 0x0002);
  set_integer(L, "dpad_left", 0x0004);
  set_integer(L, "dpad_right", 0x0008);
  set_integer(L, "start", 0x0010);
  set_integer(L, "back", 0x0020);
  set_integer(L, "left_thumb", 0x0040);
  set_integer(L, "right_thumb", 0x0080);
  set_integer(L, "left_shoulder", 0x0100);
  set_integer(L, "right_shoulder", 0x0200);
  set_integer(L, "a", 0x1000);
  set_integer(L, "b", 0x2000);
  set_integer(L, "x", 0x4000);
  set_integer(L, "y", 0x8000);
  lua_setfield(L, -2, "buttons");
}

/* The module table; no global is set. */
LUAXINPUT_EXPORT int luaopen__LuaXInput(lua_State *L) {
  lx_load(&api);
  lua_newtable(L);
  luaL_register(L, NULL, functions);
  set_string(L, "VERSION", LUAXINPUT_VERSION);
  set_integer(L, "MAX_PADS", LX_MAX_PADS);
  set_integer(L, "ANY", LX_INDEX_ANY);
  set_integer(L, "TRIGGER_THRESHOLD", LX_TRIGGER_THRESHOLD);
  set_integer(L, "LEFT_THUMB_DEADZONE", LX_LEFT_THUMB_DEADZONE);
  set_integer(L, "RIGHT_THUMB_DEADZONE", LX_RIGHT_THUMB_DEADZONE);
  set_buttons(L);
  return 1;
}
