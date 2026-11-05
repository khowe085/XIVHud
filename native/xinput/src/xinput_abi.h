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

/* XInput's structures and constants, written out rather than taken from
   xinput.h: the binding then needs no Windows header, which is what lets it
   build against a fake for its tests. Every layout is Microsoft's own, and
   the size checks below fail the build if one drifts. */

#ifndef LUAXINPUT_ABI_H
#define LUAXINPUT_ABI_H

#include <stdint.h>

typedef uint8_t lx_byte;
typedef uint16_t lx_word;
typedef int16_t lx_short;
typedef uint32_t lx_dword;

/* XINPUT_GAMEPAD */
typedef struct {
  lx_word buttons;
  lx_byte left_trigger;
  lx_byte right_trigger;
  lx_short thumb_lx;
  lx_short thumb_ly;
  lx_short thumb_rx;
  lx_short thumb_ry;
} lx_gamepad;

/* XINPUT_STATE */
typedef struct {
  lx_dword packet;
  lx_gamepad gamepad;
} lx_state;

/* XINPUT_VIBRATION */
typedef struct {
  lx_word left_motor;
  lx_word right_motor;
} lx_vibration;

/* XINPUT_CAPABILITIES */
typedef struct {
  lx_byte type;
  lx_byte subtype;
  lx_word flags;
  lx_gamepad gamepad;
  lx_vibration vibration;
} lx_capabilities;

/* XINPUT_BATTERY_INFORMATION */
typedef struct {
  lx_byte type;
  lx_byte level;
} lx_battery;

/* XINPUT_KEYSTROKE; `unicode` is a WCHAR, 16 bits on Windows */
typedef struct {
  lx_word virtual_key;
  lx_word unicode;
  lx_word flags;
  lx_byte user_index;
  lx_byte hid_code;
} lx_keystroke;

typedef char lx_gamepad_is_12_bytes[sizeof(lx_gamepad) == 12 ? 1 : -1];
typedef char lx_state_is_16_bytes[sizeof(lx_state) == 16 ? 1 : -1];
typedef char lx_vibration_is_4_bytes[sizeof(lx_vibration) == 4 ? 1 : -1];
typedef char lx_capabilities_is_20_bytes[sizeof(lx_capabilities) == 20 ? 1 : -1];
typedef char lx_battery_is_2_bytes[sizeof(lx_battery) == 2 ? 1 : -1];
typedef char lx_keystroke_is_8_bytes[sizeof(lx_keystroke) == 8 ? 1 : -1];

#define LX_ERROR_SUCCESS 0
#define LX_ERROR_DEVICE_NOT_CONNECTED 1167
#define LX_ERROR_EMPTY 4306

/* XUSER_MAX_COUNT and XUSER_INDEX_ANY */
#define LX_MAX_PADS 4
#define LX_INDEX_ANY 0xFF

#define LX_TRIGGER_THRESHOLD 30
#define LX_LEFT_THUMB_DEADZONE 7849
#define LX_RIGHT_THUMB_DEADZONE 8689

#define LX_BATTERY_DEVTYPE_GAMEPAD 0x00
#define LX_BATTERY_DEVTYPE_HEADSET 0x01

#define LX_BATTERY_TYPE_DISCONNECTED 0x00
#define LX_BATTERY_TYPE_WIRED 0x01
#define LX_BATTERY_TYPE_ALKALINE 0x02
#define LX_BATTERY_TYPE_NIMH 0x03

#define LX_BATTERY_LEVEL_EMPTY 0x00
#define LX_BATTERY_LEVEL_LOW 0x01
#define LX_BATTERY_LEVEL_MEDIUM 0x02
#define LX_BATTERY_LEVEL_FULL 0x03

#define LX_KEYSTROKE_KEYDOWN 0x0001
#define LX_KEYSTROKE_KEYUP 0x0002
#define LX_KEYSTROKE_REPEAT 0x0004

#endif
