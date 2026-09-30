{
  PaPiMeLa.Keycodes.Tables — キーボードの変換表（内部用）

  Origin : ported from SDL (src/events/scancodes_linux.h, src/events/SDL_keymap.c,
           src/events/SDL_keysym_to_keycode.c, src/events/imKStoUCS.c)
           Scope: 表のデータだけ。表を引く処理は PaPiMeLa.Events.Keymap にある。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.6、§11 #26

  WHAT:
    evdev のキーコード → スキャンコード、既定（US 配列）のキー配置、
    スキャンコードの名前、キーシム → キーコード、キーシム → Unicode。

  WHY:
    アプリが直接使うものではない。PaPiMeLa.Events.Keymap と Wayland のシートが引く。

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）

  このファイルは tools/genscancodes.bb が生成する。手で直さず、生成器を直して
  作り直すこと。
}
unit PaPiMeLa.Keycodes.Tables;

{$I papimela.inc}

interface

uses
  PaPiMeLa.Keycodes;

type
  TPMLKeysymKeycode = record
    Keysym : LongWord;
    Keycode: TPMLKeycode;
  end;

  TPMLScancodeKeycode = record
    Scancode: TPMLScancode;
    Keycode : TPMLKeycode;
  end;

  { imKStoUCS.c の範囲 1 つ。C の条件は `keysym > Above && keysym < Below` で、
    値は PML_KEYSYM_UCS_DATA[Offset + keysym - Base]。 }
  TPMLKeysymUcsRange = record
    Above, Below, Base: LongWord;
    Offset, Count     : Integer;
  end;

const
  // scancodes_linux.h。添字は evdev のキーコード（xkb のキーコード - 8）。
  PML_LINUX_SCANCODES: array[0..767] of TPMLScancode = (
    TPMLScancode.UNKNOWN,                  // 0
    TPMLScancode.ESCAPE,                   // 1
    TPMLScancode.Digit1,                   // 2
    TPMLScancode.Digit2,                   // 3
    TPMLScancode.Digit3,                   // 4
    TPMLScancode.Digit4,                   // 5
    TPMLScancode.Digit5,                   // 6
    TPMLScancode.Digit6,                   // 7
    TPMLScancode.Digit7,                   // 8
    TPMLScancode.Digit8,                   // 9
    TPMLScancode.Digit9,                   // 10
    TPMLScancode.Digit0,                   // 11
    TPMLScancode.MINUS,                    // 12
    TPMLScancode.EQUALS,                   // 13
    TPMLScancode.BACKSPACE,                // 14
    TPMLScancode.TAB,                      // 15
    TPMLScancode.Q,                        // 16
    TPMLScancode.W,                        // 17
    TPMLScancode.E,                        // 18
    TPMLScancode.R,                        // 19
    TPMLScancode.T,                        // 20
    TPMLScancode.Y,                        // 21
    TPMLScancode.U,                        // 22
    TPMLScancode.I,                        // 23
    TPMLScancode.O,                        // 24
    TPMLScancode.P,                        // 25
    TPMLScancode.LEFTBRACKET,              // 26
    TPMLScancode.RIGHTBRACKET,             // 27
    TPMLScancode.RETURN,                   // 28
    TPMLScancode.LCTRL,                    // 29
    TPMLScancode.A,                        // 30
    TPMLScancode.S,                        // 31
    TPMLScancode.D,                        // 32
    TPMLScancode.F,                        // 33
    TPMLScancode.G,                        // 34
    TPMLScancode.H,                        // 35
    TPMLScancode.J,                        // 36
    TPMLScancode.K,                        // 37
    TPMLScancode.L,                        // 38
    TPMLScancode.SEMICOLON,                // 39
    TPMLScancode.APOSTROPHE,               // 40
    TPMLScancode.GRAVE,                    // 41
    TPMLScancode.LSHIFT,                   // 42
    TPMLScancode.BACKSLASH,                // 43
    TPMLScancode.Z,                        // 44
    TPMLScancode.X,                        // 45
    TPMLScancode.C,                        // 46
    TPMLScancode.V,                        // 47
    TPMLScancode.B,                        // 48
    TPMLScancode.N,                        // 49
    TPMLScancode.M,                        // 50
    TPMLScancode.COMMA,                    // 51
    TPMLScancode.PERIOD,                   // 52
    TPMLScancode.SLASH,                    // 53
    TPMLScancode.RSHIFT,                   // 54
    TPMLScancode.KP_MULTIPLY,              // 55
    TPMLScancode.LALT,                     // 56
    TPMLScancode.SPACE,                    // 57
    TPMLScancode.CAPSLOCK,                 // 58
    TPMLScancode.F1,                       // 59
    TPMLScancode.F2,                       // 60
    TPMLScancode.F3,                       // 61
    TPMLScancode.F4,                       // 62
    TPMLScancode.F5,                       // 63
    TPMLScancode.F6,                       // 64
    TPMLScancode.F7,                       // 65
    TPMLScancode.F8,                       // 66
    TPMLScancode.F9,                       // 67
    TPMLScancode.F10,                      // 68
    TPMLScancode.NUMLOCKCLEAR,             // 69
    TPMLScancode.SCROLLLOCK,               // 70
    TPMLScancode.KP_7,                     // 71
    TPMLScancode.KP_8,                     // 72
    TPMLScancode.KP_9,                     // 73
    TPMLScancode.KP_MINUS,                 // 74
    TPMLScancode.KP_4,                     // 75
    TPMLScancode.KP_5,                     // 76
    TPMLScancode.KP_6,                     // 77
    TPMLScancode.KP_PLUS,                  // 78
    TPMLScancode.KP_1,                     // 79
    TPMLScancode.KP_2,                     // 80
    TPMLScancode.KP_3,                     // 81
    TPMLScancode.KP_0,                     // 82
    TPMLScancode.KP_PERIOD,                // 83
    TPMLScancode.UNKNOWN,                  // 84
    TPMLScancode.LANG5,                    // 85
    TPMLScancode.NONUSBACKSLASH,           // 86
    TPMLScancode.F11,                      // 87
    TPMLScancode.F12,                      // 88
    TPMLScancode.INTERNATIONAL1,           // 89
    TPMLScancode.LANG3,                    // 90
    TPMLScancode.LANG4,                    // 91
    TPMLScancode.INTERNATIONAL4,           // 92
    TPMLScancode.INTERNATIONAL2,           // 93
    TPMLScancode.INTERNATIONAL5,           // 94
    TPMLScancode.INTERNATIONAL6,           // 95
    TPMLScancode.KP_ENTER,                 // 96
    TPMLScancode.RCTRL,                    // 97
    TPMLScancode.KP_DIVIDE,                // 98
    TPMLScancode.SYSREQ,                   // 99
    TPMLScancode.RALT,                     // 100
    TPMLScancode.UNKNOWN,                  // 101
    TPMLScancode.HOME,                     // 102
    TPMLScancode.UP,                       // 103
    TPMLScancode.PAGEUP,                   // 104
    TPMLScancode.LEFT,                     // 105
    TPMLScancode.RIGHT,                    // 106
    TPMLScancode.&END,                     // 107
    TPMLScancode.DOWN,                     // 108
    TPMLScancode.PAGEDOWN,                 // 109
    TPMLScancode.INSERT,                   // 110
    TPMLScancode.DELETE,                   // 111
    TPMLScancode.UNKNOWN,                  // 112
    TPMLScancode.MUTE,                     // 113
    TPMLScancode.VOLUMEDOWN,               // 114
    TPMLScancode.VOLUMEUP,                 // 115
    TPMLScancode.POWER,                    // 116
    TPMLScancode.KP_EQUALS,                // 117
    TPMLScancode.KP_PLUSMINUS,             // 118
    TPMLScancode.PAUSE,                    // 119
    TPMLScancode.UNKNOWN,                  // 120
    TPMLScancode.KP_COMMA,                 // 121
    TPMLScancode.LANG1,                    // 122
    TPMLScancode.LANG2,                    // 123
    TPMLScancode.INTERNATIONAL3,           // 124
    TPMLScancode.LGUI,                     // 125
    TPMLScancode.RGUI,                     // 126
    TPMLScancode.APPLICATION,              // 127
    TPMLScancode.STOP,                     // 128
    TPMLScancode.AGAIN,                    // 129
    TPMLScancode.AC_PROPERTIES,            // 130
    TPMLScancode.UNDO,                     // 131
    TPMLScancode.FRONT,                    // 132
    TPMLScancode.COPY,                     // 133
    TPMLScancode.AC_OPEN,                  // 134
    TPMLScancode.PASTE,                    // 135
    TPMLScancode.FIND,                     // 136
    TPMLScancode.CUT,                      // 137
    TPMLScancode.HELP,                     // 138
    TPMLScancode.MENU,                     // 139
    TPMLScancode.UNKNOWN,                  // 140
    TPMLScancode.UNKNOWN,                  // 141
    TPMLScancode.SLEEP,                    // 142
    TPMLScancode.WAKE,                     // 143
    TPMLScancode.UNKNOWN,                  // 144
    TPMLScancode.UNKNOWN,                  // 145
    TPMLScancode.UNKNOWN,                  // 146
    TPMLScancode.UNKNOWN,                  // 147
    TPMLScancode.UNKNOWN,                  // 148
    TPMLScancode.UNKNOWN,                  // 149
    TPMLScancode.UNKNOWN,                  // 150
    TPMLScancode.UNKNOWN,                  // 151
    TPMLScancode.UNKNOWN,                  // 152
    TPMLScancode.UNKNOWN,                  // 153
    TPMLScancode.UNKNOWN,                  // 154
    TPMLScancode.UNKNOWN,                  // 155
    TPMLScancode.AC_BOOKMARKS,             // 156
    TPMLScancode.UNKNOWN,                  // 157
    TPMLScancode.AC_BACK,                  // 158
    TPMLScancode.AC_FORWARD,               // 159
    TPMLScancode.UNKNOWN,                  // 160
    TPMLScancode.MEDIA_EJECT,              // 161
    TPMLScancode.MEDIA_EJECT,              // 162
    TPMLScancode.MEDIA_NEXT_TRACK,         // 163
    TPMLScancode.MEDIA_PLAY_PAUSE,         // 164
    TPMLScancode.MEDIA_PREVIOUS_TRACK,     // 165
    TPMLScancode.MEDIA_STOP,               // 166
    TPMLScancode.MEDIA_RECORD,             // 167
    TPMLScancode.MEDIA_REWIND,             // 168
    TPMLScancode.UNKNOWN,                  // 169
    TPMLScancode.UNKNOWN,                  // 170
    TPMLScancode.UNKNOWN,                  // 171
    TPMLScancode.AC_HOME,                  // 172
    TPMLScancode.AC_REFRESH,               // 173
    TPMLScancode.AC_EXIT,                  // 174
    TPMLScancode.UNKNOWN,                  // 175
    TPMLScancode.UNKNOWN,                  // 176
    TPMLScancode.UNKNOWN,                  // 177
    TPMLScancode.UNKNOWN,                  // 178
    TPMLScancode.KP_LEFTPAREN,             // 179
    TPMLScancode.KP_RIGHTPAREN,            // 180
    TPMLScancode.AC_NEW,                   // 181
    TPMLScancode.AGAIN,                    // 182
    TPMLScancode.F13,                      // 183
    TPMLScancode.F14,                      // 184
    TPMLScancode.F15,                      // 185
    TPMLScancode.F16,                      // 186
    TPMLScancode.F17,                      // 187
    TPMLScancode.F18,                      // 188
    TPMLScancode.F19,                      // 189
    TPMLScancode.F20,                      // 190
    TPMLScancode.F21,                      // 191
    TPMLScancode.F22,                      // 192
    TPMLScancode.F23,                      // 193
    TPMLScancode.F24,                      // 194
    TPMLScancode.UNKNOWN,                  // 195
    TPMLScancode.UNKNOWN,                  // 196
    TPMLScancode.UNKNOWN,                  // 197
    TPMLScancode.UNKNOWN,                  // 198
    TPMLScancode.UNKNOWN,                  // 199
    TPMLScancode.MEDIA_PLAY,               // 200
    TPMLScancode.MEDIA_PAUSE,              // 201
    TPMLScancode.UNKNOWN,                  // 202
    TPMLScancode.UNKNOWN,                  // 203
    TPMLScancode.UNKNOWN,                  // 204
    TPMLScancode.UNKNOWN,                  // 205
    TPMLScancode.AC_CLOSE,                 // 206
    TPMLScancode.MEDIA_PLAY,               // 207
    TPMLScancode.MEDIA_FAST_FORWARD,       // 208
    TPMLScancode.UNKNOWN,                  // 209
    TPMLScancode.PRINTSCREEN,              // 210
    TPMLScancode.UNKNOWN,                  // 211
    TPMLScancode.UNKNOWN,                  // 212
    TPMLScancode.UNKNOWN,                  // 213
    TPMLScancode.UNKNOWN,                  // 214
    TPMLScancode.UNKNOWN,                  // 215
    TPMLScancode.UNKNOWN,                  // 216
    TPMLScancode.AC_SEARCH,                // 217
    TPMLScancode.UNKNOWN,                  // 218
    TPMLScancode.UNKNOWN,                  // 219
    TPMLScancode.UNKNOWN,                  // 220
    TPMLScancode.UNKNOWN,                  // 221
    TPMLScancode.ALTERASE,                 // 222
    TPMLScancode.CANCEL,                   // 223
    TPMLScancode.UNKNOWN,                  // 224
    TPMLScancode.UNKNOWN,                  // 225
    TPMLScancode.MEDIA_SELECT,             // 226
    TPMLScancode.UNKNOWN,                  // 227
    TPMLScancode.UNKNOWN,                  // 228
    TPMLScancode.UNKNOWN,                  // 229
    TPMLScancode.UNKNOWN,                  // 230
    TPMLScancode.UNKNOWN,                  // 231
    TPMLScancode.UNKNOWN,                  // 232
    TPMLScancode.UNKNOWN,                  // 233
    TPMLScancode.AC_SAVE,                  // 234
    TPMLScancode.UNKNOWN,                  // 235
    TPMLScancode.UNKNOWN,                  // 236
    TPMLScancode.UNKNOWN,                  // 237
    TPMLScancode.UNKNOWN,                  // 238
    TPMLScancode.UNKNOWN,                  // 239
    TPMLScancode.UNKNOWN,                  // 240
    TPMLScancode.UNKNOWN,                  // 241
    TPMLScancode.UNKNOWN,                  // 242
    TPMLScancode.UNKNOWN,                  // 243
    TPMLScancode.UNKNOWN,                  // 244
    TPMLScancode.UNKNOWN,                  // 245
    TPMLScancode.UNKNOWN,                  // 246
    TPMLScancode.UNKNOWN,                  // 247
    TPMLScancode.UNKNOWN,                  // 248
    TPMLScancode.UNKNOWN,                  // 249
    TPMLScancode.UNKNOWN,                  // 250
    TPMLScancode.UNKNOWN,                  // 251
    TPMLScancode.UNKNOWN,                  // 252
    TPMLScancode.UNKNOWN,                  // 253
    TPMLScancode.UNKNOWN,                  // 254
    TPMLScancode.UNKNOWN,                  // 255
    TPMLScancode.UNKNOWN,                  // 256
    TPMLScancode.UNKNOWN,                  // 257
    TPMLScancode.UNKNOWN,                  // 258
    TPMLScancode.UNKNOWN,                  // 259
    TPMLScancode.UNKNOWN,                  // 260
    TPMLScancode.UNKNOWN,                  // 261
    TPMLScancode.UNKNOWN,                  // 262
    TPMLScancode.UNKNOWN,                  // 263
    TPMLScancode.UNKNOWN,                  // 264
    TPMLScancode.UNKNOWN,                  // 265
    TPMLScancode.UNKNOWN,                  // 266
    TPMLScancode.UNKNOWN,                  // 267
    TPMLScancode.UNKNOWN,                  // 268
    TPMLScancode.UNKNOWN,                  // 269
    TPMLScancode.UNKNOWN,                  // 270
    TPMLScancode.UNKNOWN,                  // 271
    TPMLScancode.UNKNOWN,                  // 272
    TPMLScancode.UNKNOWN,                  // 273
    TPMLScancode.UNKNOWN,                  // 274
    TPMLScancode.UNKNOWN,                  // 275
    TPMLScancode.UNKNOWN,                  // 276
    TPMLScancode.UNKNOWN,                  // 277
    TPMLScancode.UNKNOWN,                  // 278
    TPMLScancode.UNKNOWN,                  // 279
    TPMLScancode.UNKNOWN,                  // 280
    TPMLScancode.UNKNOWN,                  // 281
    TPMLScancode.UNKNOWN,                  // 282
    TPMLScancode.UNKNOWN,                  // 283
    TPMLScancode.UNKNOWN,                  // 284
    TPMLScancode.UNKNOWN,                  // 285
    TPMLScancode.UNKNOWN,                  // 286
    TPMLScancode.UNKNOWN,                  // 287
    TPMLScancode.UNKNOWN,                  // 288
    TPMLScancode.UNKNOWN,                  // 289
    TPMLScancode.UNKNOWN,                  // 290
    TPMLScancode.UNKNOWN,                  // 291
    TPMLScancode.UNKNOWN,                  // 292
    TPMLScancode.UNKNOWN,                  // 293
    TPMLScancode.UNKNOWN,                  // 294
    TPMLScancode.UNKNOWN,                  // 295
    TPMLScancode.UNKNOWN,                  // 296
    TPMLScancode.UNKNOWN,                  // 297
    TPMLScancode.UNKNOWN,                  // 298
    TPMLScancode.UNKNOWN,                  // 299
    TPMLScancode.UNKNOWN,                  // 300
    TPMLScancode.UNKNOWN,                  // 301
    TPMLScancode.UNKNOWN,                  // 302
    TPMLScancode.UNKNOWN,                  // 303
    TPMLScancode.UNKNOWN,                  // 304
    TPMLScancode.UNKNOWN,                  // 305
    TPMLScancode.UNKNOWN,                  // 306
    TPMLScancode.UNKNOWN,                  // 307
    TPMLScancode.UNKNOWN,                  // 308
    TPMLScancode.UNKNOWN,                  // 309
    TPMLScancode.UNKNOWN,                  // 310
    TPMLScancode.UNKNOWN,                  // 311
    TPMLScancode.UNKNOWN,                  // 312
    TPMLScancode.UNKNOWN,                  // 313
    TPMLScancode.UNKNOWN,                  // 314
    TPMLScancode.UNKNOWN,                  // 315
    TPMLScancode.UNKNOWN,                  // 316
    TPMLScancode.UNKNOWN,                  // 317
    TPMLScancode.UNKNOWN,                  // 318
    TPMLScancode.UNKNOWN,                  // 319
    TPMLScancode.UNKNOWN,                  // 320
    TPMLScancode.UNKNOWN,                  // 321
    TPMLScancode.UNKNOWN,                  // 322
    TPMLScancode.UNKNOWN,                  // 323
    TPMLScancode.UNKNOWN,                  // 324
    TPMLScancode.UNKNOWN,                  // 325
    TPMLScancode.UNKNOWN,                  // 326
    TPMLScancode.UNKNOWN,                  // 327
    TPMLScancode.UNKNOWN,                  // 328
    TPMLScancode.UNKNOWN,                  // 329
    TPMLScancode.UNKNOWN,                  // 330
    TPMLScancode.UNKNOWN,                  // 331
    TPMLScancode.UNKNOWN,                  // 332
    TPMLScancode.UNKNOWN,                  // 333
    TPMLScancode.UNKNOWN,                  // 334
    TPMLScancode.UNKNOWN,                  // 335
    TPMLScancode.UNKNOWN,                  // 336
    TPMLScancode.UNKNOWN,                  // 337
    TPMLScancode.UNKNOWN,                  // 338
    TPMLScancode.UNKNOWN,                  // 339
    TPMLScancode.UNKNOWN,                  // 340
    TPMLScancode.UNKNOWN,                  // 341
    TPMLScancode.UNKNOWN,                  // 342
    TPMLScancode.UNKNOWN,                  // 343
    TPMLScancode.UNKNOWN,                  // 344
    TPMLScancode.UNKNOWN,                  // 345
    TPMLScancode.UNKNOWN,                  // 346
    TPMLScancode.UNKNOWN,                  // 347
    TPMLScancode.UNKNOWN,                  // 348
    TPMLScancode.UNKNOWN,                  // 349
    TPMLScancode.UNKNOWN,                  // 350
    TPMLScancode.UNKNOWN,                  // 351
    TPMLScancode.UNKNOWN,                  // 352
    TPMLScancode.SELECT,                   // 353
    TPMLScancode.UNKNOWN,                  // 354
    TPMLScancode.CLEAR,                    // 355
    TPMLScancode.UNKNOWN,                  // 356
    TPMLScancode.UNKNOWN,                  // 357
    TPMLScancode.UNKNOWN,                  // 358
    TPMLScancode.UNKNOWN,                  // 359
    TPMLScancode.UNKNOWN,                  // 360
    TPMLScancode.UNKNOWN,                  // 361
    TPMLScancode.UNKNOWN,                  // 362
    TPMLScancode.UNKNOWN,                  // 363
    TPMLScancode.UNKNOWN,                  // 364
    TPMLScancode.UNKNOWN,                  // 365
    TPMLScancode.UNKNOWN,                  // 366
    TPMLScancode.UNKNOWN,                  // 367
    TPMLScancode.UNKNOWN,                  // 368
    TPMLScancode.UNKNOWN,                  // 369
    TPMLScancode.UNKNOWN,                  // 370
    TPMLScancode.UNKNOWN,                  // 371
    TPMLScancode.UNKNOWN,                  // 372
    TPMLScancode.MODE,                     // 373
    TPMLScancode.UNKNOWN,                  // 374
    TPMLScancode.UNKNOWN,                  // 375
    TPMLScancode.UNKNOWN,                  // 376
    TPMLScancode.UNKNOWN,                  // 377
    TPMLScancode.UNKNOWN,                  // 378
    TPMLScancode.UNKNOWN,                  // 379
    TPMLScancode.UNKNOWN,                  // 380
    TPMLScancode.UNKNOWN,                  // 381
    TPMLScancode.UNKNOWN,                  // 382
    TPMLScancode.UNKNOWN,                  // 383
    TPMLScancode.UNKNOWN,                  // 384
    TPMLScancode.UNKNOWN,                  // 385
    TPMLScancode.UNKNOWN,                  // 386
    TPMLScancode.UNKNOWN,                  // 387
    TPMLScancode.UNKNOWN,                  // 388
    TPMLScancode.UNKNOWN,                  // 389
    TPMLScancode.UNKNOWN,                  // 390
    TPMLScancode.UNKNOWN,                  // 391
    TPMLScancode.UNKNOWN,                  // 392
    TPMLScancode.UNKNOWN,                  // 393
    TPMLScancode.UNKNOWN,                  // 394
    TPMLScancode.UNKNOWN,                  // 395
    TPMLScancode.UNKNOWN,                  // 396
    TPMLScancode.UNKNOWN,                  // 397
    TPMLScancode.UNKNOWN,                  // 398
    TPMLScancode.UNKNOWN,                  // 399
    TPMLScancode.UNKNOWN,                  // 400
    TPMLScancode.UNKNOWN,                  // 401
    TPMLScancode.CHANNEL_INCREMENT,        // 402
    TPMLScancode.CHANNEL_DECREMENT,        // 403
    TPMLScancode.UNKNOWN,                  // 404
    TPMLScancode.UNKNOWN,                  // 405
    TPMLScancode.UNKNOWN,                  // 406
    TPMLScancode.UNKNOWN,                  // 407
    TPMLScancode.UNKNOWN,                  // 408
    TPMLScancode.UNKNOWN,                  // 409
    TPMLScancode.UNKNOWN,                  // 410
    TPMLScancode.UNKNOWN,                  // 411
    TPMLScancode.UNKNOWN,                  // 412
    TPMLScancode.UNKNOWN,                  // 413
    TPMLScancode.UNKNOWN,                  // 414
    TPMLScancode.UNKNOWN,                  // 415
    TPMLScancode.UNKNOWN,                  // 416
    TPMLScancode.UNKNOWN,                  // 417
    TPMLScancode.UNKNOWN,                  // 418
    TPMLScancode.UNKNOWN,                  // 419
    TPMLScancode.UNKNOWN,                  // 420
    TPMLScancode.UNKNOWN,                  // 421
    TPMLScancode.UNKNOWN,                  // 422
    TPMLScancode.UNKNOWN,                  // 423
    TPMLScancode.UNKNOWN,                  // 424
    TPMLScancode.UNKNOWN,                  // 425
    TPMLScancode.UNKNOWN,                  // 426
    TPMLScancode.UNKNOWN,                  // 427
    TPMLScancode.UNKNOWN,                  // 428
    TPMLScancode.UNKNOWN,                  // 429
    TPMLScancode.UNKNOWN,                  // 430
    TPMLScancode.UNKNOWN,                  // 431
    TPMLScancode.UNKNOWN,                  // 432
    TPMLScancode.UNKNOWN,                  // 433
    TPMLScancode.UNKNOWN,                  // 434
    TPMLScancode.UNKNOWN,                  // 435
    TPMLScancode.UNKNOWN,                  // 436
    TPMLScancode.UNKNOWN,                  // 437
    TPMLScancode.UNKNOWN,                  // 438
    TPMLScancode.UNKNOWN,                  // 439
    TPMLScancode.UNKNOWN,                  // 440
    TPMLScancode.UNKNOWN,                  // 441
    TPMLScancode.UNKNOWN,                  // 442
    TPMLScancode.UNKNOWN,                  // 443
    TPMLScancode.UNKNOWN,                  // 444
    TPMLScancode.UNKNOWN,                  // 445
    TPMLScancode.UNKNOWN,                  // 446
    TPMLScancode.UNKNOWN,                  // 447
    TPMLScancode.UNKNOWN,                  // 448
    TPMLScancode.UNKNOWN,                  // 449
    TPMLScancode.UNKNOWN,                  // 450
    TPMLScancode.UNKNOWN,                  // 451
    TPMLScancode.UNKNOWN,                  // 452
    TPMLScancode.UNKNOWN,                  // 453
    TPMLScancode.UNKNOWN,                  // 454
    TPMLScancode.UNKNOWN,                  // 455
    TPMLScancode.UNKNOWN,                  // 456
    TPMLScancode.UNKNOWN,                  // 457
    TPMLScancode.UNKNOWN,                  // 458
    TPMLScancode.UNKNOWN,                  // 459
    TPMLScancode.UNKNOWN,                  // 460
    TPMLScancode.UNKNOWN,                  // 461
    TPMLScancode.UNKNOWN,                  // 462
    TPMLScancode.UNKNOWN,                  // 463
    TPMLScancode.UNKNOWN,                  // 464
    TPMLScancode.UNKNOWN,                  // 465
    TPMLScancode.UNKNOWN,                  // 466
    TPMLScancode.UNKNOWN,                  // 467
    TPMLScancode.UNKNOWN,                  // 468
    TPMLScancode.UNKNOWN,                  // 469
    TPMLScancode.UNKNOWN,                  // 470
    TPMLScancode.UNKNOWN,                  // 471
    TPMLScancode.UNKNOWN,                  // 472
    TPMLScancode.UNKNOWN,                  // 473
    TPMLScancode.UNKNOWN,                  // 474
    TPMLScancode.UNKNOWN,                  // 475
    TPMLScancode.UNKNOWN,                  // 476
    TPMLScancode.UNKNOWN,                  // 477
    TPMLScancode.UNKNOWN,                  // 478
    TPMLScancode.UNKNOWN,                  // 479
    TPMLScancode.UNKNOWN,                  // 480
    TPMLScancode.UNKNOWN,                  // 481
    TPMLScancode.UNKNOWN,                  // 482
    TPMLScancode.UNKNOWN,                  // 483
    TPMLScancode.UNKNOWN,                  // 484
    TPMLScancode.UNKNOWN,                  // 485
    TPMLScancode.UNKNOWN,                  // 486
    TPMLScancode.UNKNOWN,                  // 487
    TPMLScancode.UNKNOWN,                  // 488
    TPMLScancode.UNKNOWN,                  // 489
    TPMLScancode.UNKNOWN,                  // 490
    TPMLScancode.UNKNOWN,                  // 491
    TPMLScancode.UNKNOWN,                  // 492
    TPMLScancode.UNKNOWN,                  // 493
    TPMLScancode.UNKNOWN,                  // 494
    TPMLScancode.UNKNOWN,                  // 495
    TPMLScancode.UNKNOWN,                  // 496
    TPMLScancode.UNKNOWN,                  // 497
    TPMLScancode.UNKNOWN,                  // 498
    TPMLScancode.UNKNOWN,                  // 499
    TPMLScancode.UNKNOWN,                  // 500
    TPMLScancode.UNKNOWN,                  // 501
    TPMLScancode.UNKNOWN,                  // 502
    TPMLScancode.UNKNOWN,                  // 503
    TPMLScancode.UNKNOWN,                  // 504
    TPMLScancode.UNKNOWN,                  // 505
    TPMLScancode.UNKNOWN,                  // 506
    TPMLScancode.UNKNOWN,                  // 507
    TPMLScancode.UNKNOWN,                  // 508
    TPMLScancode.UNKNOWN,                  // 509
    TPMLScancode.UNKNOWN,                  // 510
    TPMLScancode.UNKNOWN,                  // 511
    TPMLScancode.UNKNOWN,                  // 512
    TPMLScancode.UNKNOWN,                  // 513
    TPMLScancode.UNKNOWN,                  // 514
    TPMLScancode.UNKNOWN,                  // 515
    TPMLScancode.UNKNOWN,                  // 516
    TPMLScancode.UNKNOWN,                  // 517
    TPMLScancode.UNKNOWN,                  // 518
    TPMLScancode.UNKNOWN,                  // 519
    TPMLScancode.UNKNOWN,                  // 520
    TPMLScancode.UNKNOWN,                  // 521
    TPMLScancode.UNKNOWN,                  // 522
    TPMLScancode.UNKNOWN,                  // 523
    TPMLScancode.UNKNOWN,                  // 524
    TPMLScancode.UNKNOWN,                  // 525
    TPMLScancode.UNKNOWN,                  // 526
    TPMLScancode.UNKNOWN,                  // 527
    TPMLScancode.UNKNOWN,                  // 528
    TPMLScancode.UNKNOWN,                  // 529
    TPMLScancode.UNKNOWN,                  // 530
    TPMLScancode.UNKNOWN,                  // 531
    TPMLScancode.UNKNOWN,                  // 532
    TPMLScancode.UNKNOWN,                  // 533
    TPMLScancode.UNKNOWN,                  // 534
    TPMLScancode.UNKNOWN,                  // 535
    TPMLScancode.UNKNOWN,                  // 536
    TPMLScancode.UNKNOWN,                  // 537
    TPMLScancode.UNKNOWN,                  // 538
    TPMLScancode.UNKNOWN,                  // 539
    TPMLScancode.UNKNOWN,                  // 540
    TPMLScancode.UNKNOWN,                  // 541
    TPMLScancode.UNKNOWN,                  // 542
    TPMLScancode.UNKNOWN,                  // 543
    TPMLScancode.UNKNOWN,                  // 544
    TPMLScancode.UNKNOWN,                  // 545
    TPMLScancode.UNKNOWN,                  // 546
    TPMLScancode.UNKNOWN,                  // 547
    TPMLScancode.UNKNOWN,                  // 548
    TPMLScancode.UNKNOWN,                  // 549
    TPMLScancode.UNKNOWN,                  // 550
    TPMLScancode.UNKNOWN,                  // 551
    TPMLScancode.UNKNOWN,                  // 552
    TPMLScancode.UNKNOWN,                  // 553
    TPMLScancode.UNKNOWN,                  // 554
    TPMLScancode.UNKNOWN,                  // 555
    TPMLScancode.UNKNOWN,                  // 556
    TPMLScancode.UNKNOWN,                  // 557
    TPMLScancode.UNKNOWN,                  // 558
    TPMLScancode.UNKNOWN,                  // 559
    TPMLScancode.UNKNOWN,                  // 560
    TPMLScancode.UNKNOWN,                  // 561
    TPMLScancode.UNKNOWN,                  // 562
    TPMLScancode.UNKNOWN,                  // 563
    TPMLScancode.UNKNOWN,                  // 564
    TPMLScancode.UNKNOWN,                  // 565
    TPMLScancode.UNKNOWN,                  // 566
    TPMLScancode.UNKNOWN,                  // 567
    TPMLScancode.UNKNOWN,                  // 568
    TPMLScancode.UNKNOWN,                  // 569
    TPMLScancode.UNKNOWN,                  // 570
    TPMLScancode.UNKNOWN,                  // 571
    TPMLScancode.UNKNOWN,                  // 572
    TPMLScancode.UNKNOWN,                  // 573
    TPMLScancode.UNKNOWN,                  // 574
    TPMLScancode.UNKNOWN,                  // 575
    TPMLScancode.UNKNOWN,                  // 576
    TPMLScancode.UNKNOWN,                  // 577
    TPMLScancode.UNKNOWN,                  // 578
    TPMLScancode.UNKNOWN,                  // 579
    TPMLScancode.UNKNOWN,                  // 580
    TPMLScancode.UNKNOWN,                  // 581
    TPMLScancode.UNKNOWN,                  // 582
    TPMLScancode.UNKNOWN,                  // 583
    TPMLScancode.UNKNOWN,                  // 584
    TPMLScancode.UNKNOWN,                  // 585
    TPMLScancode.UNKNOWN,                  // 586
    TPMLScancode.UNKNOWN,                  // 587
    TPMLScancode.UNKNOWN,                  // 588
    TPMLScancode.UNKNOWN,                  // 589
    TPMLScancode.UNKNOWN,                  // 590
    TPMLScancode.UNKNOWN,                  // 591
    TPMLScancode.UNKNOWN,                  // 592
    TPMLScancode.UNKNOWN,                  // 593
    TPMLScancode.UNKNOWN,                  // 594
    TPMLScancode.UNKNOWN,                  // 595
    TPMLScancode.UNKNOWN,                  // 596
    TPMLScancode.UNKNOWN,                  // 597
    TPMLScancode.UNKNOWN,                  // 598
    TPMLScancode.UNKNOWN,                  // 599
    TPMLScancode.UNKNOWN,                  // 600
    TPMLScancode.UNKNOWN,                  // 601
    TPMLScancode.UNKNOWN,                  // 602
    TPMLScancode.UNKNOWN,                  // 603
    TPMLScancode.UNKNOWN,                  // 604
    TPMLScancode.UNKNOWN,                  // 605
    TPMLScancode.UNKNOWN,                  // 606
    TPMLScancode.UNKNOWN,                  // 607
    TPMLScancode.UNKNOWN,                  // 608
    TPMLScancode.UNKNOWN,                  // 609
    TPMLScancode.UNKNOWN,                  // 610
    TPMLScancode.UNKNOWN,                  // 611
    TPMLScancode.UNKNOWN,                  // 612
    TPMLScancode.UNKNOWN,                  // 613
    TPMLScancode.UNKNOWN,                  // 614
    TPMLScancode.UNKNOWN,                  // 615
    TPMLScancode.UNKNOWN,                  // 616
    TPMLScancode.UNKNOWN,                  // 617
    TPMLScancode.UNKNOWN,                  // 618
    TPMLScancode.UNKNOWN,                  // 619
    TPMLScancode.UNKNOWN,                  // 620
    TPMLScancode.UNKNOWN,                  // 621
    TPMLScancode.UNKNOWN,                  // 622
    TPMLScancode.UNKNOWN,                  // 623
    TPMLScancode.UNKNOWN,                  // 624
    TPMLScancode.UNKNOWN,                  // 625
    TPMLScancode.UNKNOWN,                  // 626
    TPMLScancode.UNKNOWN,                  // 627
    TPMLScancode.UNKNOWN,                  // 628
    TPMLScancode.UNKNOWN,                  // 629
    TPMLScancode.UNKNOWN,                  // 630
    TPMLScancode.UNKNOWN,                  // 631
    TPMLScancode.UNKNOWN,                  // 632
    TPMLScancode.UNKNOWN,                  // 633
    TPMLScancode.UNKNOWN,                  // 634
    TPMLScancode.UNKNOWN,                  // 635
    TPMLScancode.UNKNOWN,                  // 636
    TPMLScancode.UNKNOWN,                  // 637
    TPMLScancode.UNKNOWN,                  // 638
    TPMLScancode.UNKNOWN,                  // 639
    TPMLScancode.UNKNOWN,                  // 640
    TPMLScancode.UNKNOWN,                  // 641
    TPMLScancode.UNKNOWN,                  // 642
    TPMLScancode.UNKNOWN,                  // 643
    TPMLScancode.UNKNOWN,                  // 644
    TPMLScancode.UNKNOWN,                  // 645
    TPMLScancode.UNKNOWN,                  // 646
    TPMLScancode.UNKNOWN,                  // 647
    TPMLScancode.UNKNOWN,                  // 648
    TPMLScancode.UNKNOWN,                  // 649
    TPMLScancode.UNKNOWN,                  // 650
    TPMLScancode.UNKNOWN,                  // 651
    TPMLScancode.UNKNOWN,                  // 652
    TPMLScancode.UNKNOWN,                  // 653
    TPMLScancode.UNKNOWN,                  // 654
    TPMLScancode.UNKNOWN,                  // 655
    TPMLScancode.UNKNOWN,                  // 656
    TPMLScancode.UNKNOWN,                  // 657
    TPMLScancode.UNKNOWN,                  // 658
    TPMLScancode.UNKNOWN,                  // 659
    TPMLScancode.UNKNOWN,                  // 660
    TPMLScancode.UNKNOWN,                  // 661
    TPMLScancode.UNKNOWN,                  // 662
    TPMLScancode.UNKNOWN,                  // 663
    TPMLScancode.UNKNOWN,                  // 664
    TPMLScancode.UNKNOWN,                  // 665
    TPMLScancode.UNKNOWN,                  // 666
    TPMLScancode.UNKNOWN,                  // 667
    TPMLScancode.UNKNOWN,                  // 668
    TPMLScancode.UNKNOWN,                  // 669
    TPMLScancode.UNKNOWN,                  // 670
    TPMLScancode.UNKNOWN,                  // 671
    TPMLScancode.UNKNOWN,                  // 672
    TPMLScancode.UNKNOWN,                  // 673
    TPMLScancode.UNKNOWN,                  // 674
    TPMLScancode.UNKNOWN,                  // 675
    TPMLScancode.UNKNOWN,                  // 676
    TPMLScancode.UNKNOWN,                  // 677
    TPMLScancode.UNKNOWN,                  // 678
    TPMLScancode.UNKNOWN,                  // 679
    TPMLScancode.UNKNOWN,                  // 680
    TPMLScancode.UNKNOWN,                  // 681
    TPMLScancode.UNKNOWN,                  // 682
    TPMLScancode.UNKNOWN,                  // 683
    TPMLScancode.UNKNOWN,                  // 684
    TPMLScancode.UNKNOWN,                  // 685
    TPMLScancode.UNKNOWN,                  // 686
    TPMLScancode.UNKNOWN,                  // 687
    TPMLScancode.UNKNOWN,                  // 688
    TPMLScancode.UNKNOWN,                  // 689
    TPMLScancode.UNKNOWN,                  // 690
    TPMLScancode.UNKNOWN,                  // 691
    TPMLScancode.UNKNOWN,                  // 692
    TPMLScancode.UNKNOWN,                  // 693
    TPMLScancode.UNKNOWN,                  // 694
    TPMLScancode.UNKNOWN,                  // 695
    TPMLScancode.UNKNOWN,                  // 696
    TPMLScancode.UNKNOWN,                  // 697
    TPMLScancode.UNKNOWN,                  // 698
    TPMLScancode.UNKNOWN,                  // 699
    TPMLScancode.UNKNOWN,                  // 700
    TPMLScancode.UNKNOWN,                  // 701
    TPMLScancode.UNKNOWN,                  // 702
    TPMLScancode.UNKNOWN,                  // 703
    TPMLScancode.UNKNOWN,                  // 704
    TPMLScancode.UNKNOWN,                  // 705
    TPMLScancode.UNKNOWN,                  // 706
    TPMLScancode.UNKNOWN,                  // 707
    TPMLScancode.UNKNOWN,                  // 708
    TPMLScancode.UNKNOWN,                  // 709
    TPMLScancode.UNKNOWN,                  // 710
    TPMLScancode.UNKNOWN,                  // 711
    TPMLScancode.UNKNOWN,                  // 712
    TPMLScancode.UNKNOWN,                  // 713
    TPMLScancode.UNKNOWN,                  // 714
    TPMLScancode.UNKNOWN,                  // 715
    TPMLScancode.UNKNOWN,                  // 716
    TPMLScancode.UNKNOWN,                  // 717
    TPMLScancode.UNKNOWN,                  // 718
    TPMLScancode.UNKNOWN,                  // 719
    TPMLScancode.UNKNOWN,                  // 720
    TPMLScancode.UNKNOWN,                  // 721
    TPMLScancode.UNKNOWN,                  // 722
    TPMLScancode.UNKNOWN,                  // 723
    TPMLScancode.UNKNOWN,                  // 724
    TPMLScancode.UNKNOWN,                  // 725
    TPMLScancode.UNKNOWN,                  // 726
    TPMLScancode.UNKNOWN,                  // 727
    TPMLScancode.UNKNOWN,                  // 728
    TPMLScancode.UNKNOWN,                  // 729
    TPMLScancode.UNKNOWN,                  // 730
    TPMLScancode.UNKNOWN,                  // 731
    TPMLScancode.UNKNOWN,                  // 732
    TPMLScancode.UNKNOWN,                  // 733
    TPMLScancode.UNKNOWN,                  // 734
    TPMLScancode.UNKNOWN,                  // 735
    TPMLScancode.UNKNOWN,                  // 736
    TPMLScancode.UNKNOWN,                  // 737
    TPMLScancode.UNKNOWN,                  // 738
    TPMLScancode.UNKNOWN,                  // 739
    TPMLScancode.UNKNOWN,                  // 740
    TPMLScancode.UNKNOWN,                  // 741
    TPMLScancode.UNKNOWN,                  // 742
    TPMLScancode.UNKNOWN,                  // 743
    TPMLScancode.UNKNOWN,                  // 744
    TPMLScancode.UNKNOWN,                  // 745
    TPMLScancode.UNKNOWN,                  // 746
    TPMLScancode.UNKNOWN,                  // 747
    TPMLScancode.UNKNOWN,                  // 748
    TPMLScancode.UNKNOWN,                  // 749
    TPMLScancode.UNKNOWN,                  // 750
    TPMLScancode.UNKNOWN,                  // 751
    TPMLScancode.UNKNOWN,                  // 752
    TPMLScancode.UNKNOWN,                  // 753
    TPMLScancode.UNKNOWN,                  // 754
    TPMLScancode.UNKNOWN,                  // 755
    TPMLScancode.UNKNOWN,                  // 756
    TPMLScancode.UNKNOWN,                  // 757
    TPMLScancode.UNKNOWN,                  // 758
    TPMLScancode.UNKNOWN,                  // 759
    TPMLScancode.UNKNOWN,                  // 760
    TPMLScancode.UNKNOWN,                  // 761
    TPMLScancode.UNKNOWN,                  // 762
    TPMLScancode.UNKNOWN,                  // 763
    TPMLScancode.UNKNOWN,                  // 764
    TPMLScancode.UNKNOWN,                  // 765
    TPMLScancode.UNKNOWN,                  // 766
    TPMLScancode.UNKNOWN                   // 767
  );

  // SDL_keymap.c の SDL_scancode_names。名前の無いものは空文字列。
  PML_SCANCODE_NAMES: array[TPMLScancode] of String = (
    '',
    '',
    '',
    '',
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '0',
    'Return',
    'Escape',
    'Backspace',
    'Tab',
    'Space',
    '-',
    '=',
    '[',
    ']',
    '\',
    '#',
    ';',
    '''',
    '`',
    ',',
    '.',
    '/',
    'CapsLock',
    'F1',
    'F2',
    'F3',
    'F4',
    'F5',
    'F6',
    'F7',
    'F8',
    'F9',
    'F10',
    'F11',
    'F12',
    'PrintScreen',
    'ScrollLock',
    'Pause',
    'Insert',
    'Home',
    'PageUp',
    'Delete',
    'End',
    'PageDown',
    'Right',
    'Left',
    'Down',
    'Up',
    'Numlock',
    'Keypad /',
    'Keypad *',
    'Keypad -',
    'Keypad +',
    'Keypad Enter',
    'Keypad 1',
    'Keypad 2',
    'Keypad 3',
    'Keypad 4',
    'Keypad 5',
    'Keypad 6',
    'Keypad 7',
    'Keypad 8',
    'Keypad 9',
    'Keypad 0',
    'Keypad .',
    'NonUSBackslash',
    'Application',
    'Power',
    'Keypad =',
    'F13',
    'F14',
    'F15',
    'F16',
    'F17',
    'F18',
    'F19',
    'F20',
    'F21',
    'F22',
    'F23',
    'F24',
    'Execute',
    'Help',
    'Menu',
    'Select',
    'Stop',
    'Again',
    'Undo',
    'Cut',
    'Copy',
    'Paste',
    'Find',
    'Mute',
    'VolumeUp',
    'VolumeDown',
    '',
    '',
    '',
    'Keypad ,',
    'Keypad = (AS400)',
    'International 1',
    'International 2',
    'International 3',
    'International 4',
    'International 5',
    'International 6',
    'International 7',
    'International 8',
    'International 9',
    'Language 1',
    'Language 2',
    'Language 3',
    'Language 4',
    'Language 5',
    'Language 6',
    'Language 7',
    'Language 8',
    'Language 9',
    'AltErase',
    'SysReq',
    'Cancel',
    'Clear',
    'Prior',
    'Return',
    'Separator',
    'Out',
    'Oper',
    'Clear / Again',
    'CrSel',
    'ExSel',
    'Front',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    'Keypad 00',
    'Keypad 000',
    'ThousandsSeparator',
    'DecimalSeparator',
    'CurrencyUnit',
    'CurrencySubUnit',
    'Keypad (',
    'Keypad )',
    'Keypad {',
    'Keypad }',
    'Keypad Tab',
    'Keypad Backspace',
    'Keypad A',
    'Keypad B',
    'Keypad C',
    'Keypad D',
    'Keypad E',
    'Keypad F',
    'Keypad XOR',
    'Keypad ^',
    'Keypad %',
    'Keypad <',
    'Keypad >',
    'Keypad &',
    'Keypad &&',
    'Keypad |',
    'Keypad ||',
    'Keypad :',
    'Keypad #',
    'Keypad Space',
    'Keypad @',
    'Keypad !',
    'Keypad MemStore',
    'Keypad MemRecall',
    'Keypad MemClear',
    'Keypad MemAdd',
    'Keypad MemSubtract',
    'Keypad MemMultiply',
    'Keypad MemDivide',
    'Keypad +/-',
    'Keypad Clear',
    'Keypad ClearEntry',
    'Keypad Binary',
    'Keypad Octal',
    'Keypad Decimal',
    'Keypad Hexadecimal',
    '',
    '',
    'Left Ctrl',
    'Left Shift',
    'Left Alt',
    'Left GUI',
    'Right Ctrl',
    'Right Shift',
    'Right Alt',
    'Right GUI',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    'ModeSwitch',
    'Sleep',
    'Wake',
    'ChannelUp',
    'ChannelDown',
    'MediaPlay',
    'MediaPause',
    'MediaRecord',
    'MediaFastForward',
    'MediaRewind',
    'MediaTrackNext',
    'MediaTrackPrevious',
    'MediaStop',
    'Eject',
    'MediaPlayPause',
    'MediaSelect',
    'AC New',
    'AC Open',
    'AC Close',
    'AC Exit',
    'AC Save',
    'AC Print',
    'AC Properties',
    'AC Search',
    'AC Home',
    'AC Back',
    'AC Forward',
    'AC Stop',
    'AC Refresh',
    'AC Bookmarks',
    'SoftLeft',
    'SoftRight',
    'Call',
    'EndCall',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    ''
  );

  // SDL_extended_key_names。PMLK_EXTENDED_MASK の付いたキーコードの下位ビット - 1 が添字。
  PML_EXTENDED_KEY_NAMES: array[0..6] of String = (
    'LeftTab',
    'Level5Shift',
    'MultiKeyCompose',
    'Left Meta',
    'Right Meta',
    'Left Hyper',
    'Right Hyper'
  );

  // normal_default_symbols。Digit1 から Slash まで、Shift なし。
  PML_NORMAL_DEFAULT_SYMBOLS: array[0..26] of TPMLKeycode = (
    PMLK_1,
    PMLK_2,
    PMLK_3,
    PMLK_4,
    PMLK_5,
    PMLK_6,
    PMLK_7,
    PMLK_8,
    PMLK_9,
    PMLK_0,
    PMLK_RETURN,
    PMLK_ESCAPE,
    PMLK_BACKSPACE,
    PMLK_TAB,
    PMLK_SPACE,
    PMLK_MINUS,
    PMLK_EQUALS,
    PMLK_LEFTBRACKET,
    PMLK_RIGHTBRACKET,
    PMLK_BACKSLASH,
    PMLK_HASH,
    PMLK_SEMICOLON,
    PMLK_APOSTROPHE,
    PMLK_GRAVE,
    PMLK_COMMA,
    PMLK_PERIOD,
    PMLK_SLASH
  );

  // shifted_default_symbols。同じ範囲の Shift あり。
  PML_SHIFTED_DEFAULT_SYMBOLS: array[0..26] of TPMLKeycode = (
    PMLK_EXCLAIM,
    PMLK_AT,
    PMLK_HASH,
    PMLK_DOLLAR,
    PMLK_PERCENT,
    PMLK_CARET,
    PMLK_AMPERSAND,
    PMLK_ASTERISK,
    PMLK_LEFTPAREN,
    PMLK_RIGHTPAREN,
    PMLK_RETURN,
    PMLK_ESCAPE,
    PMLK_BACKSPACE,
    PMLK_TAB,
    PMLK_SPACE,
    PMLK_UNDERSCORE,
    PMLK_PLUS,
    PMLK_LEFTBRACE,
    PMLK_RIGHTBRACE,
    PMLK_PIPE,
    PMLK_HASH,
    PMLK_COLON,
    PMLK_DBLAPOSTROPHE,
    PMLK_TILDE,
    PMLK_LESS,
    PMLK_GREATER,
    PMLK_QUESTION
  );

  // extended_default_symbols。
  PML_EXTENDED_DEFAULT_SYMBOLS: array[0..4] of TPMLScancodeKeycode = (
    (Scancode: TPMLScancode.TAB; Keycode: PMLK_LEFT_TAB),
    (Scancode: TPMLScancode.APPLICATION; Keycode: PMLK_MULTI_KEY_COMPOSE),
    (Scancode: TPMLScancode.LGUI; Keycode: PMLK_LMETA),
    (Scancode: TPMLScancode.RGUI; Keycode: PMLK_RMETA),
    (Scancode: TPMLScancode.APPLICATION; Keycode: PMLK_RHYPER)
  );

  // SDL_GetDefaultKeyFromScancode の switch（印字できないキー）。
  PML_DEFAULT_KEYS: array[0..174] of TPMLScancodeKeycode = (
    (Scancode: TPMLScancode.DELETE; Keycode: PMLK_DELETE),
    (Scancode: TPMLScancode.CAPSLOCK; Keycode: PMLK_CAPSLOCK),
    (Scancode: TPMLScancode.F1; Keycode: PMLK_F1),
    (Scancode: TPMLScancode.F2; Keycode: PMLK_F2),
    (Scancode: TPMLScancode.F3; Keycode: PMLK_F3),
    (Scancode: TPMLScancode.F4; Keycode: PMLK_F4),
    (Scancode: TPMLScancode.F5; Keycode: PMLK_F5),
    (Scancode: TPMLScancode.F6; Keycode: PMLK_F6),
    (Scancode: TPMLScancode.F7; Keycode: PMLK_F7),
    (Scancode: TPMLScancode.F8; Keycode: PMLK_F8),
    (Scancode: TPMLScancode.F9; Keycode: PMLK_F9),
    (Scancode: TPMLScancode.F10; Keycode: PMLK_F10),
    (Scancode: TPMLScancode.F11; Keycode: PMLK_F11),
    (Scancode: TPMLScancode.F12; Keycode: PMLK_F12),
    (Scancode: TPMLScancode.PRINTSCREEN; Keycode: PMLK_PRINTSCREEN),
    (Scancode: TPMLScancode.SCROLLLOCK; Keycode: PMLK_SCROLLLOCK),
    (Scancode: TPMLScancode.PAUSE; Keycode: PMLK_PAUSE),
    (Scancode: TPMLScancode.INSERT; Keycode: PMLK_INSERT),
    (Scancode: TPMLScancode.HOME; Keycode: PMLK_HOME),
    (Scancode: TPMLScancode.PAGEUP; Keycode: PMLK_PAGEUP),
    (Scancode: TPMLScancode.&END; Keycode: PMLK_END),
    (Scancode: TPMLScancode.PAGEDOWN; Keycode: PMLK_PAGEDOWN),
    (Scancode: TPMLScancode.RIGHT; Keycode: PMLK_RIGHT),
    (Scancode: TPMLScancode.LEFT; Keycode: PMLK_LEFT),
    (Scancode: TPMLScancode.DOWN; Keycode: PMLK_DOWN),
    (Scancode: TPMLScancode.UP; Keycode: PMLK_UP),
    (Scancode: TPMLScancode.NUMLOCKCLEAR; Keycode: PMLK_NUMLOCKCLEAR),
    (Scancode: TPMLScancode.KP_DIVIDE; Keycode: PMLK_KP_DIVIDE),
    (Scancode: TPMLScancode.KP_MULTIPLY; Keycode: PMLK_KP_MULTIPLY),
    (Scancode: TPMLScancode.KP_MINUS; Keycode: PMLK_KP_MINUS),
    (Scancode: TPMLScancode.KP_PLUS; Keycode: PMLK_KP_PLUS),
    (Scancode: TPMLScancode.KP_ENTER; Keycode: PMLK_KP_ENTER),
    (Scancode: TPMLScancode.KP_1; Keycode: PMLK_KP_1),
    (Scancode: TPMLScancode.KP_2; Keycode: PMLK_KP_2),
    (Scancode: TPMLScancode.KP_3; Keycode: PMLK_KP_3),
    (Scancode: TPMLScancode.KP_4; Keycode: PMLK_KP_4),
    (Scancode: TPMLScancode.KP_5; Keycode: PMLK_KP_5),
    (Scancode: TPMLScancode.KP_6; Keycode: PMLK_KP_6),
    (Scancode: TPMLScancode.KP_7; Keycode: PMLK_KP_7),
    (Scancode: TPMLScancode.KP_8; Keycode: PMLK_KP_8),
    (Scancode: TPMLScancode.KP_9; Keycode: PMLK_KP_9),
    (Scancode: TPMLScancode.KP_0; Keycode: PMLK_KP_0),
    (Scancode: TPMLScancode.KP_PERIOD; Keycode: PMLK_KP_PERIOD),
    (Scancode: TPMLScancode.APPLICATION; Keycode: PMLK_APPLICATION),
    (Scancode: TPMLScancode.POWER; Keycode: PMLK_POWER),
    (Scancode: TPMLScancode.KP_EQUALS; Keycode: PMLK_KP_EQUALS),
    (Scancode: TPMLScancode.F13; Keycode: PMLK_F13),
    (Scancode: TPMLScancode.F14; Keycode: PMLK_F14),
    (Scancode: TPMLScancode.F15; Keycode: PMLK_F15),
    (Scancode: TPMLScancode.F16; Keycode: PMLK_F16),
    (Scancode: TPMLScancode.F17; Keycode: PMLK_F17),
    (Scancode: TPMLScancode.F18; Keycode: PMLK_F18),
    (Scancode: TPMLScancode.F19; Keycode: PMLK_F19),
    (Scancode: TPMLScancode.F20; Keycode: PMLK_F20),
    (Scancode: TPMLScancode.F21; Keycode: PMLK_F21),
    (Scancode: TPMLScancode.F22; Keycode: PMLK_F22),
    (Scancode: TPMLScancode.F23; Keycode: PMLK_F23),
    (Scancode: TPMLScancode.F24; Keycode: PMLK_F24),
    (Scancode: TPMLScancode.EXECUTE; Keycode: PMLK_EXECUTE),
    (Scancode: TPMLScancode.HELP; Keycode: PMLK_HELP),
    (Scancode: TPMLScancode.MENU; Keycode: PMLK_MENU),
    (Scancode: TPMLScancode.SELECT; Keycode: PMLK_SELECT),
    (Scancode: TPMLScancode.STOP; Keycode: PMLK_STOP),
    (Scancode: TPMLScancode.AGAIN; Keycode: PMLK_AGAIN),
    (Scancode: TPMLScancode.UNDO; Keycode: PMLK_UNDO),
    (Scancode: TPMLScancode.CUT; Keycode: PMLK_CUT),
    (Scancode: TPMLScancode.COPY; Keycode: PMLK_COPY),
    (Scancode: TPMLScancode.PASTE; Keycode: PMLK_PASTE),
    (Scancode: TPMLScancode.FIND; Keycode: PMLK_FIND),
    (Scancode: TPMLScancode.MUTE; Keycode: PMLK_MUTE),
    (Scancode: TPMLScancode.VOLUMEUP; Keycode: PMLK_VOLUMEUP),
    (Scancode: TPMLScancode.VOLUMEDOWN; Keycode: PMLK_VOLUMEDOWN),
    (Scancode: TPMLScancode.KP_COMMA; Keycode: PMLK_KP_COMMA),
    (Scancode: TPMLScancode.KP_EQUALSAS400; Keycode: PMLK_KP_EQUALSAS400),
    (Scancode: TPMLScancode.ALTERASE; Keycode: PMLK_ALTERASE),
    (Scancode: TPMLScancode.SYSREQ; Keycode: PMLK_SYSREQ),
    (Scancode: TPMLScancode.CANCEL; Keycode: PMLK_CANCEL),
    (Scancode: TPMLScancode.CLEAR; Keycode: PMLK_CLEAR),
    (Scancode: TPMLScancode.PRIOR; Keycode: PMLK_PRIOR),
    (Scancode: TPMLScancode.RETURN2; Keycode: PMLK_RETURN2),
    (Scancode: TPMLScancode.SEPARATOR; Keycode: PMLK_SEPARATOR),
    (Scancode: TPMLScancode.&OUT; Keycode: PMLK_OUT),
    (Scancode: TPMLScancode.OPER; Keycode: PMLK_OPER),
    (Scancode: TPMLScancode.CLEARAGAIN; Keycode: PMLK_CLEARAGAIN),
    (Scancode: TPMLScancode.CRSEL; Keycode: PMLK_CRSEL),
    (Scancode: TPMLScancode.EXSEL; Keycode: PMLK_EXSEL),
    (Scancode: TPMLScancode.FRONT; Keycode: PMLK_FRONT),
    (Scancode: TPMLScancode.KP_00; Keycode: PMLK_KP_00),
    (Scancode: TPMLScancode.KP_000; Keycode: PMLK_KP_000),
    (Scancode: TPMLScancode.THOUSANDSSEPARATOR; Keycode: PMLK_THOUSANDSSEPARATOR),
    (Scancode: TPMLScancode.DECIMALSEPARATOR; Keycode: PMLK_DECIMALSEPARATOR),
    (Scancode: TPMLScancode.CURRENCYUNIT; Keycode: PMLK_CURRENCYUNIT),
    (Scancode: TPMLScancode.CURRENCYSUBUNIT; Keycode: PMLK_CURRENCYSUBUNIT),
    (Scancode: TPMLScancode.KP_LEFTPAREN; Keycode: PMLK_KP_LEFTPAREN),
    (Scancode: TPMLScancode.KP_RIGHTPAREN; Keycode: PMLK_KP_RIGHTPAREN),
    (Scancode: TPMLScancode.KP_LEFTBRACE; Keycode: PMLK_KP_LEFTBRACE),
    (Scancode: TPMLScancode.KP_RIGHTBRACE; Keycode: PMLK_KP_RIGHTBRACE),
    (Scancode: TPMLScancode.KP_TAB; Keycode: PMLK_KP_TAB),
    (Scancode: TPMLScancode.KP_BACKSPACE; Keycode: PMLK_KP_BACKSPACE),
    (Scancode: TPMLScancode.KP_A; Keycode: PMLK_KP_A),
    (Scancode: TPMLScancode.KP_B; Keycode: PMLK_KP_B),
    (Scancode: TPMLScancode.KP_C; Keycode: PMLK_KP_C),
    (Scancode: TPMLScancode.KP_D; Keycode: PMLK_KP_D),
    (Scancode: TPMLScancode.KP_E; Keycode: PMLK_KP_E),
    (Scancode: TPMLScancode.KP_F; Keycode: PMLK_KP_F),
    (Scancode: TPMLScancode.KP_XOR; Keycode: PMLK_KP_XOR),
    (Scancode: TPMLScancode.KP_POWER; Keycode: PMLK_KP_POWER),
    (Scancode: TPMLScancode.KP_PERCENT; Keycode: PMLK_KP_PERCENT),
    (Scancode: TPMLScancode.KP_LESS; Keycode: PMLK_KP_LESS),
    (Scancode: TPMLScancode.KP_GREATER; Keycode: PMLK_KP_GREATER),
    (Scancode: TPMLScancode.KP_AMPERSAND; Keycode: PMLK_KP_AMPERSAND),
    (Scancode: TPMLScancode.KP_DBLAMPERSAND; Keycode: PMLK_KP_DBLAMPERSAND),
    (Scancode: TPMLScancode.KP_VERTICALBAR; Keycode: PMLK_KP_VERTICALBAR),
    (Scancode: TPMLScancode.KP_DBLVERTICALBAR; Keycode: PMLK_KP_DBLVERTICALBAR),
    (Scancode: TPMLScancode.KP_COLON; Keycode: PMLK_KP_COLON),
    (Scancode: TPMLScancode.KP_HASH; Keycode: PMLK_KP_HASH),
    (Scancode: TPMLScancode.KP_SPACE; Keycode: PMLK_KP_SPACE),
    (Scancode: TPMLScancode.KP_AT; Keycode: PMLK_KP_AT),
    (Scancode: TPMLScancode.KP_EXCLAM; Keycode: PMLK_KP_EXCLAM),
    (Scancode: TPMLScancode.KP_MEMSTORE; Keycode: PMLK_KP_MEMSTORE),
    (Scancode: TPMLScancode.KP_MEMRECALL; Keycode: PMLK_KP_MEMRECALL),
    (Scancode: TPMLScancode.KP_MEMCLEAR; Keycode: PMLK_KP_MEMCLEAR),
    (Scancode: TPMLScancode.KP_MEMADD; Keycode: PMLK_KP_MEMADD),
    (Scancode: TPMLScancode.KP_MEMSUBTRACT; Keycode: PMLK_KP_MEMSUBTRACT),
    (Scancode: TPMLScancode.KP_MEMMULTIPLY; Keycode: PMLK_KP_MEMMULTIPLY),
    (Scancode: TPMLScancode.KP_MEMDIVIDE; Keycode: PMLK_KP_MEMDIVIDE),
    (Scancode: TPMLScancode.KP_PLUSMINUS; Keycode: PMLK_KP_PLUSMINUS),
    (Scancode: TPMLScancode.KP_CLEAR; Keycode: PMLK_KP_CLEAR),
    (Scancode: TPMLScancode.KP_CLEARENTRY; Keycode: PMLK_KP_CLEARENTRY),
    (Scancode: TPMLScancode.KP_BINARY; Keycode: PMLK_KP_BINARY),
    (Scancode: TPMLScancode.KP_OCTAL; Keycode: PMLK_KP_OCTAL),
    (Scancode: TPMLScancode.KP_DECIMAL; Keycode: PMLK_KP_DECIMAL),
    (Scancode: TPMLScancode.KP_HEXADECIMAL; Keycode: PMLK_KP_HEXADECIMAL),
    (Scancode: TPMLScancode.LCTRL; Keycode: PMLK_LCTRL),
    (Scancode: TPMLScancode.LSHIFT; Keycode: PMLK_LSHIFT),
    (Scancode: TPMLScancode.LALT; Keycode: PMLK_LALT),
    (Scancode: TPMLScancode.LGUI; Keycode: PMLK_LGUI),
    (Scancode: TPMLScancode.RCTRL; Keycode: PMLK_RCTRL),
    (Scancode: TPMLScancode.RSHIFT; Keycode: PMLK_RSHIFT),
    (Scancode: TPMLScancode.RALT; Keycode: PMLK_RALT),
    (Scancode: TPMLScancode.RGUI; Keycode: PMLK_RGUI),
    (Scancode: TPMLScancode.MODE; Keycode: PMLK_MODE),
    (Scancode: TPMLScancode.SLEEP; Keycode: PMLK_SLEEP),
    (Scancode: TPMLScancode.WAKE; Keycode: PMLK_WAKE),
    (Scancode: TPMLScancode.CHANNEL_INCREMENT; Keycode: PMLK_CHANNEL_INCREMENT),
    (Scancode: TPMLScancode.CHANNEL_DECREMENT; Keycode: PMLK_CHANNEL_DECREMENT),
    (Scancode: TPMLScancode.MEDIA_PLAY; Keycode: PMLK_MEDIA_PLAY),
    (Scancode: TPMLScancode.MEDIA_PAUSE; Keycode: PMLK_MEDIA_PAUSE),
    (Scancode: TPMLScancode.MEDIA_RECORD; Keycode: PMLK_MEDIA_RECORD),
    (Scancode: TPMLScancode.MEDIA_FAST_FORWARD; Keycode: PMLK_MEDIA_FAST_FORWARD),
    (Scancode: TPMLScancode.MEDIA_REWIND; Keycode: PMLK_MEDIA_REWIND),
    (Scancode: TPMLScancode.MEDIA_NEXT_TRACK; Keycode: PMLK_MEDIA_NEXT_TRACK),
    (Scancode: TPMLScancode.MEDIA_PREVIOUS_TRACK; Keycode: PMLK_MEDIA_PREVIOUS_TRACK),
    (Scancode: TPMLScancode.MEDIA_STOP; Keycode: PMLK_MEDIA_STOP),
    (Scancode: TPMLScancode.MEDIA_EJECT; Keycode: PMLK_MEDIA_EJECT),
    (Scancode: TPMLScancode.MEDIA_PLAY_PAUSE; Keycode: PMLK_MEDIA_PLAY_PAUSE),
    (Scancode: TPMLScancode.MEDIA_SELECT; Keycode: PMLK_MEDIA_SELECT),
    (Scancode: TPMLScancode.AC_NEW; Keycode: PMLK_AC_NEW),
    (Scancode: TPMLScancode.AC_OPEN; Keycode: PMLK_AC_OPEN),
    (Scancode: TPMLScancode.AC_CLOSE; Keycode: PMLK_AC_CLOSE),
    (Scancode: TPMLScancode.AC_EXIT; Keycode: PMLK_AC_EXIT),
    (Scancode: TPMLScancode.AC_SAVE; Keycode: PMLK_AC_SAVE),
    (Scancode: TPMLScancode.AC_PRINT; Keycode: PMLK_AC_PRINT),
    (Scancode: TPMLScancode.AC_PROPERTIES; Keycode: PMLK_AC_PROPERTIES),
    (Scancode: TPMLScancode.AC_SEARCH; Keycode: PMLK_AC_SEARCH),
    (Scancode: TPMLScancode.AC_HOME; Keycode: PMLK_AC_HOME),
    (Scancode: TPMLScancode.AC_BACK; Keycode: PMLK_AC_BACK),
    (Scancode: TPMLScancode.AC_FORWARD; Keycode: PMLK_AC_FORWARD),
    (Scancode: TPMLScancode.AC_STOP; Keycode: PMLK_AC_STOP),
    (Scancode: TPMLScancode.AC_REFRESH; Keycode: PMLK_AC_REFRESH),
    (Scancode: TPMLScancode.AC_BOOKMARKS; Keycode: PMLK_AC_BOOKMARKS),
    (Scancode: TPMLScancode.SOFTLEFT; Keycode: PMLK_SOFTLEFT),
    (Scancode: TPMLScancode.SOFTRIGHT; Keycode: PMLK_SOFTRIGHT),
    (Scancode: TPMLScancode.CALL; Keycode: PMLK_CALL),
    (Scancode: TPMLScancode.ENDCALL; Keycode: PMLK_ENDCALL)
  );

  // SDL_keysym_to_keycode.c の keysym_to_keycode_table。
  PML_KEYSYM_KEYCODES: array[0..7] of TPMLKeysymKeycode = (
    (Keysym: $0000FE03; Keycode: PMLK_MODE),
    (Keysym: $0000FE11; Keycode: PMLK_LEVEL5_SHIFT),
    (Keysym: $0000FE20; Keycode: PMLK_LEFT_TAB),
    (Keysym: $0000FF20; Keycode: PMLK_MULTI_KEY_COMPOSE),
    (Keysym: $0000FFE7; Keycode: PMLK_LMETA),
    (Keysym: $0000FFE8; Keycode: PMLK_RMETA),
    (Keysym: $0000FFED; Keycode: PMLK_LHYPER),
    (Keysym: $0000FFEE; Keycode: PMLK_RHYPER)
  );

  // imKStoUCS.c の範囲判定。
  PML_KEYSYM_UCS_RANGES: array[0..19] of TPMLKeysymUcsRange = (
    (Above: $01A0; Below: $0200; Base: $01A1; Offset:    0; Count:  95),     // 1a1_1ff
    (Above: $02A0; Below: $02FF; Base: $02A1; Offset:   95; Count:  94),     // 2a1_2fe
    (Above: $03A1; Below: $03FF; Base: $03A2; Offset:  189; Count:  93),     // 3a2_3fe
    (Above: $04A0; Below: $04E0; Base: $04A1; Offset:  282; Count:  63),     // 4a1_4df
    (Above: $0589; Below: $05FF; Base: $0590; Offset:  345; Count: 111),     // 590_5fe
    (Above: $067F; Below: $0700; Base: $0680; Offset:  456; Count: 128),     // 680_6ff
    (Above: $07A0; Below: $07FA; Base: $07A1; Offset:  584; Count:  89),     // 7a1_7f9
    (Above: $08A3; Below: $08FF; Base: $08A4; Offset:  673; Count:  91),     // 8a4_8fe
    (Above: $09DE; Below: $09F9; Base: $09DF; Offset:  764; Count:  26),     // 9df_9f8
    (Above: $0AA0; Below: $0AFF; Base: $0AA1; Offset:  790; Count:  94),     // aa1_afe
    (Above: $0CDE; Below: $0CFB; Base: $0CDF; Offset:  884; Count:  28),     // cdf_cfa
    (Above: $0DA0; Below: $0DFA; Base: $0DA1; Offset:  912; Count:  89),     // da1_df9
    (Above: $0E9F; Below: $0F00; Base: $0EA0; Offset: 1001; Count:  96),     // ea0_eff
    (Above: $12A0; Below: $12FF; Base: $12A1; Offset: 1097; Count:  94),     // 12a1_12fe
    (Above: $13BB; Below: $13BF; Base: $13BC; Offset: 1191; Count:   3),     // 13bc_13be
    (Above: $14A0; Below: $1500; Base: $14A1; Offset: 1194; Count:  95),     // 14a1_14ff
    (Above: $15CF; Below: $15F7; Base: $15D0; Offset: 1289; Count:  39),     // 15d0_15f6
    (Above: $169F; Below: $16F7; Base: $16A0; Offset: 1328; Count:  87),     // 16a0_16f6
    (Above: $1E9E; Below: $1F00; Base: $1E9F; Offset: 1415; Count:  97),     // 1e9f_1eff
    (Above: $209F; Below: $20AD; Base: $20A0; Offset: 1512; Count:  13)      // 20a0_20ac
  );

  // imKStoUCS.c の表を範囲の順に 1 本に並べたもの。
  PML_KEYSYM_UCS_DATA: array[0..1524] of Word = (
    $0104, $02D8, $0141, $0000, $013D, $015A, $0000, $0000,
    $0160, $015E, $0164, $0179, $0000, $017D, $017B, $0000,
    $0105, $02DB, $0142, $0000, $013E, $015B, $02C7, $0000,
    $0161, $015F, $0165, $017A, $02DD, $017E, $017C, $0154,
    $0000, $0000, $0102, $0000, $0139, $0106, $0000, $010C,
    $0000, $0118, $0000, $011A, $0000, $0000, $010E, $0110,
    $0143, $0147, $0000, $0000, $0150, $0000, $0000, $0158,
    $016E, $0000, $0170, $0000, $0000, $0162, $0000, $0155,
    $0000, $0000, $0103, $0000, $013A, $0107, $0000, $010D,
    $0000, $0119, $0000, $011B, $0000, $0000, $010F, $0111,
    $0144, $0148, $0000, $0000, $0151, $0000, $0000, $0159,
    $016F, $0000, $0171, $0000, $0000, $0163, $02D9, $0126,
    $0000, $0000, $0000, $0000, $0124, $0000, $0000, $0130,
    $0000, $011E, $0134, $0000, $0000, $0000, $0000, $0127,
    $0000, $0000, $0000, $0000, $0125, $0000, $0000, $0131,
    $0000, $011F, $0135, $0000, $0000, $0000, $0000, $0000,
    $0000, $0000, $0000, $010A, $0108, $0000, $0000, $0000,
    $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000,
    $0000, $0000, $0000, $0120, $0000, $0000, $011C, $0000,
    $0000, $0000, $0000, $016C, $015C, $0000, $0000, $0000,
    $0000, $0000, $0000, $010B, $0109, $0000, $0000, $0000,
    $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000,
    $0000, $0000, $0000, $0121, $0000, $0000, $011D, $0000,
    $0000, $0000, $0000, $016D, $015D, $0138, $0156, $0000,
    $0128, $013B, $0000, $0000, $0000, $0112, $0122, $0166,
    $0000, $0000, $0000, $0000, $0000, $0000, $0157, $0000,
    $0129, $013C, $0000, $0000, $0000, $0113, $0123, $0167,
    $014A, $0000, $014B, $0100, $0000, $0000, $0000, $0000,
    $0000, $0000, $012E, $0000, $0000, $0000, $0000, $0116,
    $0000, $0000, $012A, $0000, $0145, $014C, $0136, $0000,
    $0000, $0000, $0000, $0000, $0172, $0000, $0000, $0000,
    $0168, $016A, $0000, $0101, $0000, $0000, $0000, $0000,
    $0000, $0000, $012F, $0000, $0000, $0000, $0000, $0117,
    $0000, $0000, $012B, $0000, $0146, $014D, $0137, $0000,
    $0000, $0000, $0000, $0000, $0173, $0000, $0000, $0000,
    $0169, $016B, $3002, $3008, $3009, $3001, $30FB, $30F2,
    $30A1, $30A3, $30A5, $30A7, $30A9, $30E3, $30E5, $30E7,
    $30C3, $30FC, $30A2, $30A4, $30A6, $30A8, $30AA, $30AB,
    $30AD, $30AF, $30B1, $30B3, $30B5, $30B7, $30B9, $30BB,
    $30BD, $30BF, $30C1, $30C4, $30C6, $30C8, $30CA, $30CB,
    $30CC, $30CD, $30CE, $30CF, $30D2, $30D5, $30D8, $30DB,
    $30DE, $30DF, $30E0, $30E1, $30E2, $30E4, $30E6, $30E8,
    $30E9, $30EA, $30EB, $30EC, $30ED, $30EF, $30F3, $309B,
    $309C, $06F0, $06F1, $06F2, $06F3, $06F4, $06F5, $06F6,
    $06F7, $06F8, $06F9, $0000, $0000, $0000, $0000, $0000,
    $0000, $0000, $0000, $0000, $0000, $0000, $066A, $0670,
    $0679, $067E, $0686, $0688, $0691, $060C, $0000, $06D4,
    $0000, $0660, $0661, $0662, $0663, $0664, $0665, $0666,
    $0667, $0668, $0669, $0000, $061B, $0000, $0000, $0000,
    $061F, $0000, $0621, $0622, $0623, $0624, $0625, $0626,
    $0627, $0628, $0629, $062A, $062B, $062C, $062D, $062E,
    $062F, $0630, $0631, $0632, $0633, $0634, $0635, $0636,
    $0637, $0638, $0639, $063A, $0000, $0000, $0000, $0000,
    $0000, $0640, $0641, $0642, $0643, $0644, $0645, $0646,
    $0647, $0648, $0649, $064A, $064B, $064C, $064D, $064E,
    $064F, $0650, $0651, $0652, $0653, $0654, $0655, $0698,
    $06A4, $06A9, $06AF, $06BA, $06BE, $06CC, $06D2, $06C1,
    $0492, $0496, $049A, $049C, $04A2, $04AE, $04B0, $04B2,
    $04B6, $04B8, $04BA, $0000, $04D8, $04E2, $04E8, $04EE,
    $0493, $0497, $049B, $049D, $04A3, $04AF, $04B1, $04B3,
    $04B7, $04B9, $04BB, $0000, $04D9, $04E3, $04E9, $04EF,
    $0000, $0452, $0453, $0451, $0454, $0455, $0456, $0457,
    $0458, $0459, $045A, $045B, $045C, $0491, $045E, $045F,
    $2116, $0402, $0403, $0401, $0404, $0405, $0406, $0407,
    $0408, $0409, $040A, $040B, $040C, $0490, $040E, $040F,
    $044E, $0430, $0431, $0446, $0434, $0435, $0444, $0433,
    $0445, $0438, $0439, $043A, $043B, $043C, $043D, $043E,
    $043F, $044F, $0440, $0441, $0442, $0443, $0436, $0432,
    $044C, $044B, $0437, $0448, $044D, $0449, $0447, $044A,
    $042E, $0410, $0411, $0426, $0414, $0415, $0424, $0413,
    $0425, $0418, $0419, $041A, $041B, $041C, $041D, $041E,
    $041F, $042F, $0420, $0421, $0422, $0423, $0416, $0412,
    $042C, $042B, $0417, $0428, $042D, $0429, $0427, $042A,
    $0386, $0388, $0389, $038A, $03AA, $0000, $038C, $038E,
    $03AB, $0000, $038F, $0000, $0000, $0385, $2015, $0000,
    $03AC, $03AD, $03AE, $03AF, $03CA, $0390, $03CC, $03CD,
    $03CB, $03B0, $03CE, $0000, $0000, $0000, $0000, $0000,
    $0391, $0392, $0393, $0394, $0395, $0396, $0397, $0398,
    $0399, $039A, $039B, $039C, $039D, $039E, $039F, $03A0,
    $03A1, $03A3, $0000, $03A4, $03A5, $03A6, $03A7, $03A8,
    $03A9, $0000, $0000, $0000, $0000, $0000, $0000, $0000,
    $03B1, $03B2, $03B3, $03B4, $03B5, $03B6, $03B7, $03B8,
    $03B9, $03BA, $03BB, $03BC, $03BD, $03BE, $03BF, $03C0,
    $03C1, $03C3, $03C2, $03C4, $03C5, $03C6, $03C7, $03C8,
    $03C9, $2320, $2321, $0000, $231C, $231D, $231E, $231F,
    $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000,
    $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000,
    $0000, $2264, $2260, $2265, $222B, $2234, $0000, $221E,
    $0000, $0000, $2207, $0000, $0000, $2245, $2246, $0000,
    $0000, $0000, $0000, $21D2, $0000, $0000, $0000, $0000,
    $0000, $0000, $0000, $221A, $0000, $0000, $0000, $2282,
    $2283, $2229, $222A, $2227, $2228, $0000, $0000, $0000,
    $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000,
    $0000, $0000, $0000, $0000, $2202, $0000, $0000, $0000,
    $0000, $0000, $0000, $0192, $0000, $0000, $0000, $0000,
    $2190, $2191, $2192, $2193, $2422, $2666, $25A6, $2409,
    $240C, $240D, $240A, $0000, $0000, $240A, $240B, $2518,
    $2510, $250C, $2514, $253C, $2500, $0000, $0000, $0000,
    $0000, $251C, $2524, $2534, $252C, $2502, $2003, $2002,
    $2004, $2005, $2007, $2008, $2009, $200A, $2014, $2013,
    $0000, $0000, $0000, $2026, $2025, $2153, $2154, $2155,
    $2156, $2157, $2158, $2159, $215A, $2105, $0000, $0000,
    $2012, $2039, $2024, $203A, $0000, $0000, $0000, $0000,
    $215B, $215C, $215D, $215E, $0000, $0000, $2122, $2120,
    $0000, $25C1, $25B7, $25CB, $25AD, $2018, $2019, $201C,
    $201D, $211E, $2030, $2032, $2033, $0000, $271D, $0000,
    $220E, $25C2, $2023, $25CF, $25AC, $25E6, $25AB, $25AE,
    $25B5, $25BF, $2606, $2022, $25AA, $25B4, $25BE, $261A,
    $261B, $2663, $2666, $2665, $0000, $2720, $2020, $2021,
    $2713, $2612, $266F, $266D, $2642, $2640, $2121, $2315,
    $2117, $2038, $201A, $201E, $2017, $05D0, $05D1, $05D2,
    $05D3, $05D4, $05D5, $05D6, $05D7, $05D8, $05D9, $05DA,
    $05DB, $05DC, $05DD, $05DE, $05DF, $05E0, $05E1, $05E2,
    $05E3, $05E4, $05E5, $05E6, $05E7, $05E8, $05E9, $05EA,
    $0E01, $0E02, $0E03, $0E04, $0E05, $0E06, $0E07, $0E08,
    $0E09, $0E0A, $0E0B, $0E0C, $0E0D, $0E0E, $0E0F, $0E10,
    $0E11, $0E12, $0E13, $0E14, $0E15, $0E16, $0E17, $0E18,
    $0E19, $0E1A, $0E1B, $0E1C, $0E1D, $0E1E, $0E1F, $0E20,
    $0E21, $0E22, $0E23, $0E24, $0E25, $0E26, $0E27, $0E28,
    $0E29, $0E2A, $0E2B, $0E2C, $0E2D, $0E2E, $0E2F, $0E30,
    $0E31, $0E32, $0E33, $0E34, $0E35, $0E36, $0E37, $0E38,
    $0E39, $0E3A, $0000, $0000, $0000, $0E3E, $0E3F, $0E40,
    $0E41, $0E42, $0E43, $0E44, $0E45, $0E46, $0E47, $0E48,
    $0E49, $0E4A, $0E4B, $0E4C, $0E4D, $0000, $0000, $0E50,
    $0E51, $0E52, $0E53, $0E54, $0E55, $0E56, $0E57, $0E58,
    $0E59, $0000, $1101, $1101, $11AA, $1102, $11AC, $11AD,
    $1103, $1104, $1105, $11B0, $11B1, $11B2, $11B3, $11B4,
    $11B5, $11B6, $1106, $1107, $1108, $11B9, $1109, $110A,
    $110B, $110C, $110D, $110E, $110F, $1110, $1111, $1112,
    $1161, $1162, $1163, $1164, $1165, $1166, $1167, $1168,
    $1169, $116A, $116B, $116C, $116D, $116E, $116F, $1170,
    $1171, $1172, $1173, $1174, $1175, $11A8, $11A9, $11AA,
    $11AB, $11AC, $11AD, $11AE, $11AF, $11B0, $11B1, $11B2,
    $11B3, $11B4, $11B5, $11B6, $11B7, $11B8, $11B9, $11BA,
    $11BB, $11BC, $11BD, $11BE, $11BF, $11C0, $11C1, $11C2,
    $0000, $0000, $0000, $1140, $0000, $0000, $1159, $119E,
    $0000, $11EB, $0000, $11F9, $0000, $0000, $0000, $0000,
    $20A9, $1E02, $1E03, $0000, $0000, $0000, $1E0A, $0000,
    $1E80, $0000, $1E82, $1E0B, $1EF2, $0000, $0000, $0000,
    $1E1E, $1E1F, $0000, $0000, $1E40, $1E41, $0000, $1E56,
    $1E81, $1E57, $1E83, $1E60, $1EF3, $1E84, $1E85, $1E61,
    $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000,
    $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000,
    $0174, $0000, $0000, $0000, $0000, $0000, $0000, $1E6A,
    $0000, $0000, $0000, $0000, $0000, $0000, $0176, $0000,
    $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000,
    $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000,
    $0175, $0000, $0000, $0000, $0000, $0000, $0000, $1E6B,
    $0000, $0000, $0000, $0000, $0000, $0000, $0177, $0152,
    $0153, $0178, $2741, $00A7, $0589, $0029, $0028, $00BB,
    $00AB, $2014, $002E, $055D, $002C, $2013, $058A, $2026,
    $055C, $055B, $055E, $0531, $0561, $0532, $0562, $0533,
    $0563, $0534, $0564, $0535, $0565, $0536, $0566, $0537,
    $0567, $0538, $0568, $0539, $0569, $053A, $056A, $053B,
    $056B, $053C, $056C, $053D, $056D, $053E, $056E, $053F,
    $056F, $0540, $0570, $0541, $0571, $0542, $0572, $0543,
    $0573, $0544, $0574, $0545, $0575, $0546, $0576, $0547,
    $0577, $0548, $0578, $0549, $0579, $054A, $057A, $054B,
    $057B, $054C, $057C, $054D, $057D, $054E, $057E, $054F,
    $057F, $0550, $0580, $0551, $0581, $0552, $0582, $0553,
    $0583, $0554, $0584, $0555, $0585, $0556, $0586, $2019,
    $0027, $10D0, $10D1, $10D2, $10D3, $10D4, $10D5, $10D6,
    $10D7, $10D8, $10D9, $10DA, $10DB, $10DC, $10DD, $10DE,
    $10DF, $10E0, $10E1, $10E2, $10E3, $10E4, $10E5, $10E6,
    $10E7, $10E8, $10E9, $10EA, $10EB, $10EC, $10ED, $10EE,
    $10EF, $10F0, $10F1, $10F2, $10F3, $10F4, $10F5, $10F6,
    $0000, $0000, $F0A2, $1E8A, $0000, $F0A5, $012C, $F0A7,
    $F0A8, $01B5, $01E6, $0000, $0000, $0000, $0000, $019F,
    $0000, $0000, $F0B2, $1E8B, $01D1, $F0B5, $012D, $F0B7,
    $F0B8, $01B6, $01E7, $0000, $0000, $01D2, $0000, $0275,
    $0000, $0000, $0000, $0000, $0000, $0000, $018F, $0000,
    $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000,
    $0000, $1E36, $F0D2, $F0D3, $0000, $0000, $0000, $0000,
    $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000,
    $0000, $1E37, $F0E2, $F0E3, $0000, $0000, $0000, $0000,
    $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000,
    $0000, $0000, $0000, $0000, $0000, $0000, $0259, $0303,
    $1EA0, $1EA1, $1EA2, $1EA3, $1EA4, $1EA5, $1EA6, $1EA7,
    $1EA8, $1EA9, $1EAA, $1EAB, $1EAC, $1EAD, $1EAE, $1EAF,
    $1EB0, $1EB1, $1EB2, $1EB3, $1EB4, $1EB5, $1EB6, $1EB7,
    $1EB8, $1EB9, $1EBA, $1EBB, $1EBC, $1EBD, $1EBE, $1EBF,
    $1EC0, $1EC1, $1EC2, $1EC3, $1EC4, $1EC5, $1EC6, $1EC7,
    $1EC8, $1EC9, $1ECA, $1ECB, $1ECC, $1ECD, $1ECE, $1ECF,
    $1ED0, $1ED1, $1ED2, $1ED3, $1ED4, $1ED5, $1ED6, $1ED7,
    $1ED8, $1ED9, $1EDA, $1EDB, $1EDC, $1EDD, $1EDE, $1EDF,
    $1EE0, $1EE1, $1EE2, $1EE3, $1EE4, $1EE5, $1EE6, $1EE7,
    $1EE8, $1EE9, $1EEA, $1EEB, $1EEC, $1EED, $1EEE, $1EEF,
    $1EF0, $1EF1, $0300, $0301, $1EF4, $1EF5, $1EF6, $1EF7,
    $1EF8, $1EF9, $01A0, $01A1, $01AF, $01B0, $0309, $0323,
    $20A0, $20A1, $20A2, $20A3, $20A4, $20A5, $20A6, $20A7,
    $20A8, $20A9, $20AA, $20AB, $20AC
  );

implementation

end.
