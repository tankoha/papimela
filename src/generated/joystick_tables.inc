{ src/generated/joystick_tables.inc — tools/genjoystick.bb が作る。手で直さない。
  SDL の joystick/SDL_joystick.c の VID/PID の表 11 個と、controller_list.h（Valve。zlib）の
  コントローラの表 608 件。 }

const
  JoystickOldXboxOneControllersInitial: array[0..156] of LongWord = (
    $00006686,
    $007918a1,
    $007918c2,
    $007918c8,
    $007918cf,
    $03f00495,
    $045e02d1,
    $045e02dd,
    $045e02e0,
    $045e02e3,
    $045e02ea,
    $045e02fd,
    $045e02ff,
    $045e0867,
    $045e0b00,
    $045e0b05,
    $045e0b0a,
    $045e0b0c,
    $045e0b20,
    $045e0b21,
    $045e0b22,
    $046d0000,
    $046d1004,
    $046d1007,
    $046d1008,
    $046df301,
    $073802a0,
    $07384a01,
    $07387263,
    $0738b738,
    $0738cb29,
    $0738f401,
    $0c120e17,
    $0c120e1c,
    $0c120e22,
    $0c120e30,
    $0d629a1a,
    $0d629a1b,
    $0e000e00,
    $0e6f012a,
    $0e6f0139,
    $0e6f013b,
    $0e6f013a,
    $0e6f0145,
    $0e6f0146,
    $0e6f0152,
    $0e6f015b,
    $0e6f015c,
    $0e6f015d,
    $0e6f015f,
    $0e6f0160,
    $0e6f0161,
    $0e6f0162,
    $0e6f0163,
    $0e6f0164,
    $0e6f0165,
    $0e6f0166,
    $0e6f0167,
    $0e6f0205,
    $0e6f0206,
    $0e6f0246,
    $0e6f0261,
    $0e6f0262,
    $0e6f02a0,
    $0e6f02a1,
    $0e6f02a2,
    $0e6f02a3,
    $0e6f02a4,
    $0e6f02a5,
    $0e6f02a6,
    $0e6f02a7,
    $0e6f02a8,
    $0e6f02a9,
    $0e6f02aa,
    $0e6f02ab,
    $0e6f02ac,
    $0e6f02ad,
    $0e6f02ae,
    $0e6f02af,
    $0e6f02b0,
    $0e6f02b1,
    $0e6f02b2,
    $0e6f02b3,
    $0e6f02b5,
    $0e6f02b6,
    $0e6f02b8,
    $0e6f02bd,
    $0e6f02be,
    $0e6f02bf,
    $0e6f02c0,
    $0e6f02c1,
    $0e6f02c2,
    $0e6f02c3,
    $0e6f02c4,
    $0e6f02c5,
    $0e6f02c6,
    $0e6f02c7,
    $0e6f02c8,
    $0e6f02c9,
    $0e6f02ca,
    $0e6f02cb,
    $0e6f02cd,
    $0e6f02ce,
    $0e6f02cf,
    $0e6f02d5,
    $0e6f0346,
    $0e6f0446,
    $0e6ff501,
    $0f0d0063,
    $0f0d0067,
    $0f0d0078,
    $0f0d0097,
    $0f0d00ba,
    $0f0d00c0,
    $0f0d00c5,
    $0f0d00d8,
    $0f0d00ed,
    $0fff02a1,
    $12ab0304,
    $14300291,
    $143002a9,
    $1430070b,
    $14300719,
    $146b0611,
    $15320a00,
    $15320a03,
    $15320a14,
    $15320a15,
    $16d00f3f,
    $1bad028e,
    $1bad02a0,
    $1bad5500,
    $20ab55ef,
    $24c6541a,
    $24c6542a,
    $24c6543a,
    $24c65509,
    $24c6551a,
    $24c6561a,
    $24c6581a,
    $24c6591a,
    $24c6592a,
    $24c6791a,
    $25160069,
    $25b10360,
    $2c222203,
    $2e240652,
    $2e241618,
    $2e241688,
    $2f240011,
    $2f24002e,
    $2f240050,
    $2f240053,
    $2f24008f,
    $2f240091,
    $2f2400b7,
    $d2d2d2d2
  );

  JoystickArcadeStickDevicesInitial: array[0..31] of LongWord = (
    $0079181a,  // Venom Arcade Stick
    $0079181b,  // Venom Arcade Stick
    $0c120ef6,  // Hitbox Arcade Stick
    $0e6f0109,  // PDP Versus Fighting Pad
    $0f0d0016,  // Hori Real Arcade Pro.EX
    $0f0d001b,  // Hori Real Arcade Pro VX
    $0f0d0063,  // Hori Real Arcade Pro Hayabusa (USA) Xbox One
    $0f0d006a,  // Real Arcade Pro 4
    $0f0d0078,  // Hori Real Arcade Pro V Kai Xbox One
    $0f0d008a,  // HORI Real Arcade Pro 4
    $0f0d008c,  // Hori Real Arcade Pro 4
    $0f0d00aa,  // HORI Real Arcade Pro V Hayabusa in Switch Mode
    $0f0d00ed,  // Hori Fighting Stick mini 4 kai
    $0f0d011c,  // Hori Fighting Stick Alpha in PS4 Mode
    $0f0d011e,  // Hori Fighting Stick Alpha in PC Mode
    $0f0d0184,  // Hori Fighting Stick Alpha in PS5 Mode
    $146b0604,  // NACON Daija Arcade Stick
    $15320a00,  // Razer Atrox Arcade Stick
    $1badf03d,  // Street Fighter IV Arcade Stick TE - Chun Li
    $1badf502,  // Hori Real Arcade Pro.VX SA
    $1badf504,  // Hori Real Arcade Pro. EX
    $1badf506,  // Hori Real Arcade Pro.EX Premium VLX
    $20d6a715,  // PowerA Nintendo Switch Fusion Arcade Stick
    $24c65000,  // Razer Atrox Arcade Stick
    $24c65501,  // Hori Real Arcade Pro VX-SA
    $24c6550e,  // Hori Real Arcade Pro V Kai 360
    $2c222300,  // Qanba Obsidian Arcade Joystick in PS4 Mode
    $2c222302,  // Qanba Obsidian Arcade Joystick in PS3 Mode
    $2c222303,  // Qanba Obsidian Arcade Joystick in PC Mode
    $2c222500,  // Qanba Dragon Arcade Joystick in PS4 Mode
    $2c222502,  // Qanba Dragon Arcade Joystick in PS3 Mode
    $2c222503  // Qanba Dragon Arcade Joystick in PC Mode
  );

  JoystickBlacklistDevicesInitial: array[0..69] of LongWord = (
    $045e009d,
    $045e00b0,
    $045e00b4,
    $045e0730,
    $045e0745,
    $045e0748,
    $045e0750,
    $045e0768,
    $045e0773,
    $045e07a5,
    $045e07b2,
    $045e0800,
    $046dc30a,  // Logitech, Inc. iTouch Composite keyboard
    $04d9a0df,  // Tek Syndicate Mouse (E-Signal USB Gaming Mouse)
    $056a0010,  // Wacom ET-0405 Graphire
    $056a0011,  // Wacom ET-0405A Graphire2 (4x5)
    $056a0012,  // Wacom ET-0507A Graphire2 (5x7)
    $056a0013,  // Wacom CTE-430 Graphire3 (4x5)
    $056a0014,  // Wacom CTE-630 Graphire3 (6x8)
    $056a0015,  // Wacom CTE-440 Graphire4 (4x5)
    $056a0016,  // Wacom CTE-640 Graphire4 (6x8)
    $056a0017,  // Wacom CTE-450 Bamboo Fun (4x5)
    $056a0018,  // Wacom CTE-650 Bamboo Fun 6x8
    $056a0019,  // Wacom CTE-631 Bamboo One
    $056a00d1,  // Wacom Bamboo Pen and Touch CTH-460
    $056a030e,  // Wacom Intuos Pen (S) CTL-480
    $09da054f,  // A4 Tech Co., G7 750 mouse
    $09da1410,  // A4 Tech Co., Ltd Bloody AL9 mouse
    $09da3043,  // A4 Tech Co., Ltd Bloody R8A Gaming Mouse
    $09da31b5,  // A4 Tech Co., Ltd Bloody TL80 Terminator Laser Gaming Mouse
    $09da3997,  // A4 Tech Co., Ltd Bloody RT7 Terminator Wireless
    $09da3f8b,  // A4 Tech Co., Ltd Bloody V8 mouse
    $09da51f4,  // Modecom MC-5006 Keyboard
    $09da5589,  // A4 Tech Co., Ltd Terminator TL9 Laser Gaming Mouse
    $09da7b22,  // A4 Tech Co., Ltd Bloody V5
    $09da7f2d,  // A4 Tech Co., Ltd Bloody R3 mouse
    $09da8090,  // A4 Tech Co., Ltd X-718BK Oscar Optical Gaming Mouse
    $09da9033,  // A4 Tech Co., X7 X-705K
    $09da9066,  // A4 Tech Co., Sharkoon Fireglider Optical
    $09da9090,  // A4 Tech Co., Ltd XL-730K / XL-750BK / XL-755BK Laser Mouse
    $09da90c0,  // A4 Tech Co., Ltd X7 G800V keyboard
    $09daf012,  // A4 Tech Co., Ltd Bloody V7 mouse
    $09daf32a,  // A4 Tech Co., Ltd Bloody B540 keyboard
    $09daf613,  // A4 Tech Co., Ltd Bloody V2 mouse
    $09daf624,  // A4 Tech Co., Ltd Bloody B120 Keyboard
    $1b1c1b3c,  // Corsair Harpoon RGB gaming mouse
    $1d57ad03,  // [T3] 2.4GHz and IR Air Mouse Remote Control
    $1e7d2e4a,  // Roccat Tyon Mouse
    $20a0422d,  // Winkeyless.kr Keyboards
    $2516001f,  // Cooler Master Storm Mizar Mouse
    $25160028,  // Cooler Master Storm Alcor Mouse
    $04d98008,  // OBINLB USB-HID Keyboard (Anne Pro II)
    $04d98009,  // OBINLB USB-HID Keyboard (Anne Pro II)
    $04d9a292,  // OBINLB USB-HID Keyboard (Anne Pro II)
    $04d9a293,  // OBINLB USB-HID Keyboard (Anne Pro II)
    $04f2a13c,  // HP Deluxe Webcam KQ246AA
    $0e6f018a,  // PDP REALMz Wireless Controller for Switch, USB charging
    $15320266,  // Razer Huntsman V2 Analog, non-functional DInput device
    $15320282,  // Razer Huntsman Mini Analog, non-functional DInput device
    $20d60002,  // PowerA Enhanced Wireless Controller for Nintendo Switch (charging port only)
    $256c006d,  // Huion Tablet_GS1331, Huion Tablet_GS1331 Touch Strip
    $256c006e,  // Huion Tablet Kamvas Pro 22, Huion Tablet Kamvas Pro 22 Touch Strip
    $26ce01a2,  // ASRock LED Controller
    $32971969,  // Moonlander MK1 Keyboard
    $34340121,  // Keychron Q3 System Control
    $34340163,  // Keychron Q6 System Control
    $34340211,  // Keychron K1 Pro System Control
    $343402a0,  // Keychron K10 Pro System Control
    $34340353,  // Keychron V5 System Control
    $3434d030  // Keychron Link
  );

  JoystickFlightStickDevicesInitial: array[0..19] of LongWord = (
    $044f0402,  // HOTAS Warthog Joystick
    $044fb10a,  // ThrustMaster, Inc. T.16000M Joystick
    $046dc215,  // Logitech Extreme 3D
    $05836258,  // Padix USB joystick with viewfinder
    $0583688f,  // Padix QF-688uv Windstorm Pro
    $05837070,  // Padix QF-707u Bazooka
    $0583a019,  // Padix USB vibration joystick with viewfinder
    $0583a131,  // Padix USB Wireless 2.4GHz
    $0583a209,  // Padix MetalStrike ForceFeedback
    $0583b010,  // Padix MetalStrike Pro
    $0583b012,  // Padix Wireless MetalStrike
    $0583b013,  // Padix USB Wireless 2.4GHZ
    $07382221,  // Saitek Pro Flight X-56 Rhino Stick
    $10f57084,  // Turtle Beach VelocityOne
    $231d0126,  // Gunfighter Mk.III 'Space Combat Edition' (right)
    $231d0127,  // Gunfighter Mk.III 'Space Combat Edition' (left)
    $231d0200,  // VKB Gladiator NXT Evo (grip)
    $33444391,  // VIRPIL Controls R-VPC Stick MT-50CM3
    $33448390,  // VIRPIL Controls L-VPC Stick MT-50CM3
    $362c0001  // Yawman Arrow
  );

  JoystickGameCubeDevicesInitial: array[0..9] of LongWord = (
    $00791843,  // DragonRise GameCube Controller Adapter
    $00791844,  // DragonRise GameCube Controller Adapter
    $00791846,  // DragonRise GameCube Controller Adapter
    $057e0337,  // Nintendo Wii U GameCube Controller Adapter
    $057e2073,  // Nintendo Switch 2 NSO GameCube Controller
    $05e30681,  // Austgame GameCube to USB convertor
    $09268888,  // Cyber Gadget GameCube Controller
    $0e6f0185,  // PDP Wired Fight Pad Pro for Nintendo Switch
    $1a34f705,  // GameCube HuiJia USB box
    $20d6a711  // PowerA Wired Controller Nintendo GameCube Style
  );

  JoystickROGGamepadMiceInitial: array[0..6] of LongWord = (
    $0b0518e3,  // ROG Chakram (wired) Mouse
    $0b0518e5,  // ROG Chakram (wireless) Mouse
    $0b051906,  // ROG Pugio II
    $0b051958,  // ROG Chakram Core Mouse
    $0b051a18,  // ROG Chakram X (wired) Mouse
    $0b051a1a,  // ROG Chakram X (wireless) Mouse
    $0b051a1c  // ROG Chakram X (Bluetooth) Mouse
  );

  JoystickThrottleDevicesInitial: array[0..3] of LongWord = (
    $044f0404,  // HOTAS Warthog Throttle
    $0738a221,  // Saitek Pro Flight X-56 Rhino Throttle
    $10f57085,  // Turtle Beach VelocityOne Throttle
    $33440196  // VIRPIL Controls VPC VMAX Prime Throttle
  );

  JoystickWheelDevicesInitial: array[0..70] of LongWord = (
    $00791864,  // DragonRise Inc. Wired Wheel (active mode) (also known as PXN V900 (PS3), Superdrive SV-750, or a Genesis Seaborg 400)
    $044fb65d,  // Thrustmaster Wheel FFB
    $044fb65e,  // Thrustmaster T500RS
    $044fb664,  // Thrustmaster TX (initial mode)
    $044fb669,  // Thrustmaster TX (active mode)
    $044fb66d,  // Thrustmaster T300RS (PS4 mode)
    $044fb66d,  // Thrustmaster Wheel FFB
    $044fb66e,  // Thrustmaster T300RS (normal mode)
    $044fb66f,  // Thrustmaster T300RS (advanced mode)
    $044fb677,  // Thrustmaster T150
    $044fb67f,  // Thrustmaster TMX
    $044fb691,  // Thrustmaster TS-XW (initial mode)
    $044fb692,  // Thrustmaster TS-XW (active mode)
    $044fb696,  // Thrustmaster T248
    $046dc24f,  // Logitech G29 (PS3)
    $046dc260,  // Logitech G29 (PS4)
    $046dc261,  // Logitech G920 (initial mode)
    $046dc262,  // Logitech G920 (active mode)
    $046dc266,  // Logitech G923 for Playstation 4 and PC (PC mode)
    $046dc267,  // Logitech G923 for Playstation 4 and PC (PS4 mode)
    $046dc268,  // Logitech PRO Racing Wheel (PC mode)
    $046dc269,  // Logitech PRO Racing Wheel (PS4/PS5 mode)
    $046dc26d,  // Logitech G923 (Xbox)
    $046dc26e,  // Logitech G923
    $046dc272,  // Logitech PRO Racing Wheel for Xbox (PC mode)
    $046dc294,  // Logitech generic wheel
    $046dc295,  // Logitech Momo Force
    $046dc298,  // Logitech Driving Force Pro
    $046dc299,  // Logitech G25
    $046dc29a,  // Logitech Driving Force GT
    $046dc29b,  // Logitech G27
    $046dca03,  // Logitech Momo Racing
    $045e02a2,  // Xbox 360 Wireless Racing Wheel
    $04830522,  // Simagic Wheelbase (including M10, Alpha Mini, Alpha, Alpha U)
    $0483a355,  // VRS DirectForce Pro Wheel Base
    $0583a132,  // Padix USB Wireless 2.4GHz Wheelpad
    $0583a133,  // Padix USB Wireless 2.4GHz Wheel
    $0583a202,  // Padix Force Feedback Wheel
    $0583b002,  // Padix Vibration USB Wheel
    $0583b005,  // Padix USB Wheel
    $0583b008,  // Padix USB Wireless 2.4GHz Wheel
    $0583b009,  // Padix USB Wheel
    $0583b018,  // Padix TW6 Wheel
    $0eb70001,  // Fanatec ClubSport Wheel Base V2
    $0eb70004,  // Fanatec ClubSport Wheel Base V2.5
    $0eb70005,  // Fanatec CSL Elite Wheel Base+ (PS4)
    $0eb70006,  // Fanatec Podium Wheel Base DD1
    $0eb70007,  // Fanatec Podium Wheel Base DD2
    $0eb70011,  // Fanatec Forza Motorsport (CSR Wheel / CSR Elite Wheel)
    $0eb70020,  // Fanatec generic wheel / CSL DD / GT DD Pro
    $0eb70197,  // Fanatec Porsche Wheel (Turbo / GT3 RS / Turbo S / GT3 V2 / GT2)
    $0eb7038e,  // Fanatec ClubSport Wheel Base V1
    $0eb70e03,  // Fanatec CSL Elite Wheel Base
    $11ff0511,  // DragonRise Inc. Wired Wheel (initial mode) (also known as PXN V900 (PS3), Superdrive SV-750, or a Genesis Seaborg 400)
    $1209ffb0,  // Generic FFBoard OpenFFBoard universal forcefeedback wheel
    $16d00d5a,  // Simucube 1 Wheelbase
    $16d00d5f,  // Simucube 2 Ultimate Wheelbase
    $16d00d60,  // Simucube 2 Pro Wheelbase
    $16d00d61,  // Simucube 2 Sport Wheelbase
    $2433f300,  // Asetek SimSports Invicta Wheelbase
    $2433f301,  // Asetek SimSports Forte Wheelbase
    $2433f303,  // Asetek SimSports La Prima Wheelbase
    $2433f306,  // Asetek SimSports Tony Kannan Wheelbase
    $34160301,  // Cammus C5 Wheelbase
    $34160302,  // Cammus C12 Wheelbase
    $346e0000,  // Moza R16/R21 Wheelbase
    $346e0002,  // Moza R9 Wheelbase
    $346e0004,  // Moza R5 Wheelbase
    $346e0005,  // Moza R3 Wheelbase
    $346e0006,  // Moza R12 Wheelbase
    $36e6400f  // PXN VD6 Wheelbase
  );

  JoystickGuitarDevicesInitial: array[0..19] of LongWord = (
    $12ba0100,  // PS3 Guitar Hero Guitar
    $12ba0200,  // PS3 Rock Band Guitar
    $12ba074b,  // PS3 / Wii U Guitar Hero Live Guitar
    $1bad0004,  // Wii RB1 Guitar (Uses PS3 protocol)
    $1bad3010,  // Wii RB2 Guitar (Uses PS3 protocol)
    $03511000,  // CRKD Guitar
    $03512000,  // CRKD Guitar
    $073802a6,  // Mad Catz Wireless Rock Band Guitar
    $073802ab,  // Mad Catz Wireless Precision Bass Guitar
    $07389806,  // Mad Catz Precision Bass Guitar
    $143002a7,  // Guitar Hero Wireless Guitar (Linux)
    $14300705,  // Guitar Hero 5 Guitar
    $1430070b,  // Guitar Hero Live Guitar
    $14304734,  // Guitar Hero World Tour Kiosk
    $14304748,  // RedOctane Guitar Hero X-plorer
    $1bad02a6,  // Rock Band 2 Wireless Guitar (Linux)
    $1bad02ab,  // Rock Band Wireless Bass Guitar (Linux)
    $20680001,  // Power Gig Guitar
    $36511000,  // CRKD Guitar
    $36516000  // CRKD Guitar
  );

  JoystickDrumDevicesInitial: array[0..10] of LongWord = (
    $12ba0120,  // PS3 Guitar Hero Drums
    $12ba0210,  // PS3 Rock Band Drums
    $12ba0218,  // PS3 Midi Pro Adapter - Drums Mode
    $1bad0005,  // Wii RB1 Drums (Uses PS3 protocol)
    $1bad3110,  // Wii RB2 Drums (Uses PS3 protocol)
    $1bad3138,  // Wii RB3 Midi Pro Adapter - Drums Mode (Uses PS3 protocol)
    $143002a8,  // Guitar Hero Wireless Drum Kit (Linux)
    $14300805,  // Band Hero Wireless Drum Kit
    $1bad0003,  // Harmonix Rock Band Drumkit
    $1bad0130,  // ION Drum Rocker
    $20680002  // Power Gig Drums
  );

  JoystickZeroCenteredDevicesInitial: array[0..1] of LongWord = (
    $05a03232,  // 8Bitdo Zero Gamepad
    $0e8f3013  // HuiJia SNES USB adapter
  );

  // コントローラの表（controller_list.h）。Kind は controller_type.h の値、Name は無ければ空。
  JoystickControllerTable: array[0..607] of record
    DeviceID: LongWord;
    Kind    : Integer;
    Name    : String;
  end = (
    (DeviceID: $0079181a; Kind: 33; Name: ''),
    (DeviceID: $044fb315; Kind: 33; Name: ''),
    (DeviceID: $044fd007; Kind: 33; Name: ''),
    (DeviceID: $046dcad1; Kind: 33; Name: ''),
    (DeviceID: $054c0268; Kind: 33; Name: ''),
    (DeviceID: $056e200f; Kind: 33; Name: ''),
    (DeviceID: $056e2013; Kind: 33; Name: ''),
    (DeviceID: $05b81004; Kind: 33; Name: ''),
    (DeviceID: $05b81006; Kind: 33; Name: ''),
    (DeviceID: $06a3f622; Kind: 33; Name: ''),
    (DeviceID: $07383180; Kind: 33; Name: ''),
    (DeviceID: $07383250; Kind: 33; Name: ''),
    (DeviceID: $07383481; Kind: 33; Name: ''),
    (DeviceID: $07388180; Kind: 33; Name: ''),
    (DeviceID: $07388838; Kind: 33; Name: ''),
    (DeviceID: $08100001; Kind: 33; Name: ''),
    (DeviceID: $08100003; Kind: 33; Name: ''),
    (DeviceID: $09250005; Kind: 33; Name: ''),
    (DeviceID: $09258866; Kind: 33; Name: ''),
    (DeviceID: $09258888; Kind: 33; Name: ''),
    (DeviceID: $0e6f0109; Kind: 33; Name: ''),
    (DeviceID: $0e6f011e; Kind: 33; Name: ''),
    (DeviceID: $0e6f0128; Kind: 33; Name: ''),
    (DeviceID: $0e6f0214; Kind: 33; Name: ''),
    (DeviceID: $0e6f1314; Kind: 33; Name: ''),
    (DeviceID: $0e6f6302; Kind: 33; Name: ''),
    (DeviceID: $0e8f0008; Kind: 33; Name: ''),
    (DeviceID: $0e8f3075; Kind: 33; Name: ''),
    (DeviceID: $0e8f310d; Kind: 33; Name: ''),
    (DeviceID: $0f0d0009; Kind: 33; Name: ''),
    (DeviceID: $0f0d004d; Kind: 33; Name: ''),
    (DeviceID: $0f0d005f; Kind: 33; Name: ''),
    (DeviceID: $0f0d006a; Kind: 33; Name: ''),
    (DeviceID: $0f0d006e; Kind: 33; Name: ''),
    (DeviceID: $0f0d0085; Kind: 33; Name: ''),
    (DeviceID: $0f0d0086; Kind: 33; Name: ''),
    (DeviceID: $0f0d0088; Kind: 33; Name: ''),
    (DeviceID: $0f301100; Kind: 33; Name: ''),
    (DeviceID: $11ff3331; Kind: 33; Name: ''),
    (DeviceID: $12ba0100; Kind: 33; Name: ''),
    (DeviceID: $12ba0120; Kind: 33; Name: ''),
    (DeviceID: $12ba0140; Kind: 33; Name: ''),
    (DeviceID: $12ba0200; Kind: 33; Name: ''),
    (DeviceID: $12ba0210; Kind: 33; Name: ''),
    (DeviceID: $12ba0218; Kind: 33; Name: ''),
    (DeviceID: $12ba074b; Kind: 33; Name: ''),
    (DeviceID: $12ba2330; Kind: 33; Name: ''),
    (DeviceID: $12ba2338; Kind: 33; Name: ''),
    (DeviceID: $12ba2430; Kind: 33; Name: ''),
    (DeviceID: $12ba2438; Kind: 33; Name: ''),
    (DeviceID: $12ba2530; Kind: 33; Name: ''),
    (DeviceID: $12ba2538; Kind: 33; Name: ''),
    (DeviceID: $13451000; Kind: 33; Name: ''),
    (DeviceID: $13456005; Kind: 33; Name: ''),
    (DeviceID: $146b5500; Kind: 33; Name: ''),
    (DeviceID: $1a340836; Kind: 33; Name: ''),
    (DeviceID: $1bad0004; Kind: 33; Name: ''),
    (DeviceID: $1bad0005; Kind: 33; Name: ''),
    (DeviceID: $1bad3010; Kind: 33; Name: ''),
    (DeviceID: $1bad3110; Kind: 33; Name: ''),
    (DeviceID: $1bad3138; Kind: 33; Name: ''),
    (DeviceID: $1bad3330; Kind: 33; Name: ''),
    (DeviceID: $1bad3338; Kind: 33; Name: ''),
    (DeviceID: $1bad3430; Kind: 33; Name: ''),
    (DeviceID: $1bad3438; Kind: 33; Name: ''),
    (DeviceID: $1bad3530; Kind: 33; Name: ''),
    (DeviceID: $1bad3538; Kind: 33; Name: ''),
    (DeviceID: $20bc5500; Kind: 33; Name: ''),
    (DeviceID: $20d6576d; Kind: 33; Name: ''),
    (DeviceID: $20d6ca6d; Kind: 33; Name: ''),
    (DeviceID: $25630523; Kind: 33; Name: ''),
    (DeviceID: $25630575; Kind: 33; Name: 'Retro Controller'),
    (DeviceID: $25f083c3; Kind: 33; Name: ''),
    (DeviceID: $25f0c121; Kind: 33; Name: ''),
    (DeviceID: $2c222003; Kind: 33; Name: ''),
    (DeviceID: $2c222302; Kind: 33; Name: ''),
    (DeviceID: $2c222502; Kind: 33; Name: ''),
    (DeviceID: $83800003; Kind: 33; Name: ''),
    (DeviceID: $88880308; Kind: 33; Name: ''),
    (DeviceID: $0079181b; Kind: 34; Name: ''),
    (DeviceID: $044fd00e; Kind: 34; Name: ''),
    (DeviceID: $054c05c4; Kind: 34; Name: ''),
    (DeviceID: $054c05c5; Kind: 34; Name: ''),
    (DeviceID: $054c09cc; Kind: 34; Name: ''),
    (DeviceID: $054c0ba0; Kind: 34; Name: ''),
    (DeviceID: $07388250; Kind: 34; Name: ''),
    (DeviceID: $07388384; Kind: 34; Name: ''),
    (DeviceID: $07388480; Kind: 34; Name: ''),
    (DeviceID: $07388481; Kind: 34; Name: ''),
    (DeviceID: $0c120e10; Kind: 34; Name: ''),
    (DeviceID: $0c120e13; Kind: 34; Name: ''),
    (DeviceID: $0c120e15; Kind: 34; Name: ''),
    (DeviceID: $0c120e20; Kind: 34; Name: ''),
    (DeviceID: $0c120ef6; Kind: 34; Name: ''),
    (DeviceID: $0c121cf6; Kind: 34; Name: ''),
    (DeviceID: $0c121e10; Kind: 34; Name: ''),
    (DeviceID: $0c122e18; Kind: 34; Name: ''),
    (DeviceID: $0e6f0203; Kind: 34; Name: ''),
    (DeviceID: $0e6f0207; Kind: 34; Name: ''),
    (DeviceID: $0e6f020a; Kind: 34; Name: ''),
    (DeviceID: $0f0d0055; Kind: 34; Name: ''),
    (DeviceID: $0f0d005e; Kind: 34; Name: ''),
    (DeviceID: $0f0d0066; Kind: 34; Name: ''),
    (DeviceID: $0f0d0084; Kind: 34; Name: ''),
    (DeviceID: $0f0d0087; Kind: 34; Name: ''),
    (DeviceID: $0f0d008a; Kind: 34; Name: ''),
    (DeviceID: $0f0d009c; Kind: 34; Name: ''),
    (DeviceID: $0f0d00a0; Kind: 34; Name: ''),
    (DeviceID: $0f0d00ed; Kind: 47; Name: ''),
    (DeviceID: $0f0d00ee; Kind: 34; Name: ''),
    (DeviceID: $0f0d011c; Kind: 34; Name: ''),
    (DeviceID: $0f0d0123; Kind: 34; Name: ''),
    (DeviceID: $0f0d0162; Kind: 34; Name: ''),
    (DeviceID: $0f0d0164; Kind: 47; Name: ''),
    (DeviceID: $11c04001; Kind: 34; Name: ''),
    (DeviceID: $146b0603; Kind: 47; Name: ''),
    (DeviceID: $146b0604; Kind: 47; Name: ''),
    (DeviceID: $146b0605; Kind: 47; Name: ''),
    (DeviceID: $146b0606; Kind: 47; Name: ''),
    (DeviceID: $146b0609; Kind: 47; Name: ''),
    (DeviceID: $146b0d01; Kind: 34; Name: ''),
    (DeviceID: $146b0d02; Kind: 34; Name: ''),
    (DeviceID: $146b0d06; Kind: 34; Name: ''),
    (DeviceID: $146b0d08; Kind: 34; Name: ''),
    (DeviceID: $146b0d09; Kind: 34; Name: ''),
    (DeviceID: $146b0d10; Kind: 34; Name: ''),
    (DeviceID: $146b0d10; Kind: 34; Name: ''),
    (DeviceID: $146b0d13; Kind: 34; Name: ''),
    (DeviceID: $146b1103; Kind: 34; Name: ''),
    (DeviceID: $15320401; Kind: 34; Name: ''),
    (DeviceID: $15321000; Kind: 34; Name: ''),
    (DeviceID: $15321004; Kind: 34; Name: ''),
    (DeviceID: $15321007; Kind: 34; Name: ''),
    (DeviceID: $15321008; Kind: 34; Name: ''),
    (DeviceID: $15321009; Kind: 34; Name: ''),
    (DeviceID: $1532100a; Kind: 34; Name: ''),
    (DeviceID: $15321100; Kind: 34; Name: ''),
    (DeviceID: $20d6792a; Kind: 34; Name: ''),
    (DeviceID: $2c222000; Kind: 34; Name: ''),
    (DeviceID: $2c222300; Kind: 34; Name: ''),
    (DeviceID: $2c222303; Kind: 47; Name: ''),
    (DeviceID: $2c222500; Kind: 34; Name: ''),
    (DeviceID: $2c222503; Kind: 47; Name: ''),
    (DeviceID: $32850d16; Kind: 34; Name: ''),
    (DeviceID: $32850d17; Kind: 34; Name: ''),
    (DeviceID: $75450104; Kind: 34; Name: ''),
    (DeviceID: $98860024; Kind: 47; Name: ''),
    (DeviceID: $98860025; Kind: 34; Name: ''),
    (DeviceID: $054c0ce6; Kind: 45; Name: ''),
    (DeviceID: $054c0e5f; Kind: 45; Name: ''),
    (DeviceID: $0e6f0209; Kind: 45; Name: ''),
    (DeviceID: $0f0d0163; Kind: 45; Name: ''),
    (DeviceID: $0f0d0184; Kind: 45; Name: ''),
    (DeviceID: $1532100b; Kind: 45; Name: ''),
    (DeviceID: $1532100c; Kind: 45; Name: ''),
    (DeviceID: $15321012; Kind: 45; Name: ''),
    (DeviceID: $15321024; Kind: 45; Name: ''),
    (DeviceID: $15321026; Kind: 45; Name: ''),
    (DeviceID: $32850d18; Kind: 45; Name: ''),
    (DeviceID: $32850d19; Kind: 45; Name: ''),
    (DeviceID: $358a0104; Kind: 45; Name: ''),
    (DeviceID: $358a0304; Kind: 45; Name: ''),
    (DeviceID: $00790006; Kind: 30; Name: ''),
    (DeviceID: $007918d4; Kind: 31; Name: ''),
    (DeviceID: $03511000; Kind: 31; Name: ''),
    (DeviceID: $03512000; Kind: 31; Name: ''),
    (DeviceID: $03ebff02; Kind: 31; Name: ''),
    (DeviceID: $044fb326; Kind: 31; Name: ''),
    (DeviceID: $045e028e; Kind: 31; Name: 'Xbox 360 Controller'),
    (DeviceID: $045e028f; Kind: 31; Name: 'Xbox 360 Controller'),
    (DeviceID: $045e0291; Kind: 31; Name: 'Xbox 360 Wireless Controller'),
    (DeviceID: $045e02a0; Kind: 31; Name: ''),
    (DeviceID: $045e02a1; Kind: 31; Name: 'Xbox 360 Wireless Controller'),
    (DeviceID: $045e02a2; Kind: 31; Name: 'Xbox 360 Wireless Racing Wheel'),
    (DeviceID: $045e02a9; Kind: 31; Name: 'Xbox 360 Wireless Controller'),
    (DeviceID: $045e0719; Kind: 31; Name: 'Xbox 360 Wireless Controller'),
    (DeviceID: $046dc21d; Kind: 31; Name: ''),
    (DeviceID: $046dc21e; Kind: 31; Name: ''),
    (DeviceID: $046dc21f; Kind: 31; Name: ''),
    (DeviceID: $046dc242; Kind: 31; Name: ''),
    (DeviceID: $056e2004; Kind: 31; Name: ''),
    (DeviceID: $073802a6; Kind: 31; Name: ''),
    (DeviceID: $073802ab; Kind: 31; Name: ''),
    (DeviceID: $07384716; Kind: 31; Name: ''),
    (DeviceID: $07384718; Kind: 31; Name: ''),
    (DeviceID: $07384726; Kind: 31; Name: ''),
    (DeviceID: $07384728; Kind: 31; Name: ''),
    (DeviceID: $07384736; Kind: 31; Name: ''),
    (DeviceID: $07384738; Kind: 31; Name: ''),
    (DeviceID: $07384740; Kind: 31; Name: ''),
    (DeviceID: $07389806; Kind: 31; Name: ''),
    (DeviceID: $0738b726; Kind: 31; Name: ''),
    (DeviceID: $0738beef; Kind: 31; Name: ''),
    (DeviceID: $0738cb02; Kind: 31; Name: ''),
    (DeviceID: $0738cb03; Kind: 31; Name: ''),
    (DeviceID: $0738f738; Kind: 31; Name: ''),
    (DeviceID: $09557210; Kind: 31; Name: ''),
    (DeviceID: $0955b400; Kind: 31; Name: ''),
    (DeviceID: $0b051b4c; Kind: 31; Name: ''),
    (DeviceID: $0e6f0105; Kind: 31; Name: ''),
    (DeviceID: $0e6f0113; Kind: 31; Name: 'PDP Xbox 360 Afterglow'),
    (DeviceID: $0e6f011f; Kind: 31; Name: 'PDP Xbox 360 Rock Candy'),
    (DeviceID: $0e6f0125; Kind: 31; Name: 'PDP INJUSTICE FightStick'),
    (DeviceID: $0e6f0127; Kind: 31; Name: 'PDP INJUSTICE FightPad'),
    (DeviceID: $0e6f0131; Kind: 31; Name: 'PDP EA Soccer Controller'),
    (DeviceID: $0e6f0133; Kind: 31; Name: 'PDP Battlefield 4 Controller'),
    (DeviceID: $0e6f0143; Kind: 31; Name: 'PDP MK X Fight Stick'),
    (DeviceID: $0e6f0147; Kind: 31; Name: 'PDP Xbox 360 Marvel Controller'),
    (DeviceID: $0e6f0201; Kind: 31; Name: 'PDP Xbox 360 Controller'),
    (DeviceID: $0e6f0213; Kind: 31; Name: 'PDP Xbox 360 Afterglow'),
    (DeviceID: $0e6f021f; Kind: 31; Name: 'PDP Xbox 360 Rock Candy'),
    (DeviceID: $0e6f0301; Kind: 31; Name: 'PDP Xbox 360 Controller'),
    (DeviceID: $0e6f0313; Kind: 31; Name: 'PDP Xbox 360 Afterglow'),
    (DeviceID: $0e6f0314; Kind: 31; Name: 'PDP Xbox 360 Afterglow'),
    (DeviceID: $0e6f0401; Kind: 31; Name: 'PDP Xbox 360 Controller'),
    (DeviceID: $0e6f0413; Kind: 31; Name: ''),
    (DeviceID: $0e6f0501; Kind: 31; Name: ''),
    (DeviceID: $0e6ff900; Kind: 31; Name: ''),
    (DeviceID: $0f0d000a; Kind: 31; Name: ''),
    (DeviceID: $0f0d000c; Kind: 31; Name: ''),
    (DeviceID: $0f0d000d; Kind: 31; Name: ''),
    (DeviceID: $0f0d0016; Kind: 31; Name: ''),
    (DeviceID: $0f0d001b; Kind: 31; Name: ''),
    (DeviceID: $0f0d008c; Kind: 31; Name: ''),
    (DeviceID: $0f0d00db; Kind: 31; Name: 'HORI Slime Controller'),
    (DeviceID: $0f0d011e; Kind: 31; Name: ''),
    (DeviceID: $10381430; Kind: 31; Name: 'SteelSeries Stratus Duo'),
    (DeviceID: $10381431; Kind: 31; Name: 'SteelSeries Stratus Duo'),
    (DeviceID: $1038b360; Kind: 31; Name: ''),
    (DeviceID: $11c955f0; Kind: 31; Name: ''),
    (DeviceID: $12ab0004; Kind: 31; Name: ''),
    (DeviceID: $12ab0301; Kind: 31; Name: ''),
    (DeviceID: $12ab0303; Kind: 31; Name: ''),
    (DeviceID: $143002a0; Kind: 31; Name: ''),
    (DeviceID: $143002a7; Kind: 31; Name: ''),
    (DeviceID: $143002a8; Kind: 31; Name: ''),
    (DeviceID: $14300705; Kind: 31; Name: ''),
    (DeviceID: $1430070b; Kind: 31; Name: ''),
    (DeviceID: $14300805; Kind: 31; Name: ''),
    (DeviceID: $14301715; Kind: 31; Name: ''),
    (DeviceID: $14301705; Kind: 31; Name: ''),
    (DeviceID: $14304734; Kind: 31; Name: ''),
    (DeviceID: $14304748; Kind: 31; Name: ''),
    (DeviceID: $1430f801; Kind: 31; Name: ''),
    (DeviceID: $146b0601; Kind: 31; Name: ''),
    (DeviceID: $15e43f00; Kind: 31; Name: ''),
    (DeviceID: $15e43f0a; Kind: 31; Name: ''),
    (DeviceID: $15e43f10; Kind: 31; Name: ''),
    (DeviceID: $162ebeef; Kind: 31; Name: ''),
    (DeviceID: $1689fd00; Kind: 31; Name: ''),
    (DeviceID: $1689fd01; Kind: 31; Name: ''),
    (DeviceID: $1689fe00; Kind: 31; Name: ''),
    (DeviceID: $1949041a; Kind: 31; Name: 'Amazon Luna Controller'),
    (DeviceID: $1bad0002; Kind: 31; Name: ''),
    (DeviceID: $1bad0003; Kind: 31; Name: ''),
    (DeviceID: $1bad0130; Kind: 31; Name: ''),
    (DeviceID: $1bad02a6; Kind: 31; Name: ''),
    (DeviceID: $1bad02ab; Kind: 31; Name: ''),
    (DeviceID: $1bad1330; Kind: 31; Name: ''),
    (DeviceID: $1bad1338; Kind: 31; Name: ''),
    (DeviceID: $1bad1430; Kind: 31; Name: ''),
    (DeviceID: $1bad1530; Kind: 31; Name: ''),
    (DeviceID: $1bad1438; Kind: 31; Name: ''),
    (DeviceID: $1bad1538; Kind: 31; Name: ''),
    (DeviceID: $1badf016; Kind: 31; Name: ''),
    (DeviceID: $1badf018; Kind: 31; Name: ''),
    (DeviceID: $1badf019; Kind: 31; Name: ''),
    (DeviceID: $1badf021; Kind: 31; Name: ''),
    (DeviceID: $1badf023; Kind: 31; Name: ''),
    (DeviceID: $1badf025; Kind: 31; Name: ''),
    (DeviceID: $1badf027; Kind: 31; Name: ''),
    (DeviceID: $1badf028; Kind: 31; Name: ''),
    (DeviceID: $1badf02e; Kind: 31; Name: ''),
    (DeviceID: $1badf036; Kind: 31; Name: ''),
    (DeviceID: $1badf038; Kind: 31; Name: ''),
    (DeviceID: $1badf039; Kind: 31; Name: ''),
    (DeviceID: $1badf03a; Kind: 31; Name: ''),
    (DeviceID: $1badf03d; Kind: 31; Name: ''),
    (DeviceID: $1badf03e; Kind: 31; Name: ''),
    (DeviceID: $1badf03f; Kind: 31; Name: ''),
    (DeviceID: $1badf042; Kind: 31; Name: ''),
    (DeviceID: $1badf080; Kind: 31; Name: ''),
    (DeviceID: $1badf501; Kind: 31; Name: ''),
    (DeviceID: $1badf502; Kind: 31; Name: ''),
    (DeviceID: $1badf503; Kind: 31; Name: ''),
    (DeviceID: $1badf504; Kind: 31; Name: ''),
    (DeviceID: $1badf505; Kind: 31; Name: ''),
    (DeviceID: $1badf506; Kind: 31; Name: ''),
    (DeviceID: $1badf900; Kind: 31; Name: ''),
    (DeviceID: $1badf901; Kind: 31; Name: ''),
    (DeviceID: $1badf902; Kind: 31; Name: ''),
    (DeviceID: $1badf903; Kind: 31; Name: ''),
    (DeviceID: $1badf904; Kind: 31; Name: ''),
    (DeviceID: $1badf906; Kind: 31; Name: ''),
    (DeviceID: $1badfa01; Kind: 31; Name: ''),
    (DeviceID: $1badfd00; Kind: 31; Name: ''),
    (DeviceID: $1badfd01; Kind: 31; Name: ''),
    (DeviceID: $20680001; Kind: 31; Name: ''),
    (DeviceID: $20680002; Kind: 31; Name: ''),
    (DeviceID: $24c65000; Kind: 31; Name: ''),
    (DeviceID: $24c65300; Kind: 31; Name: ''),
    (DeviceID: $24c65303; Kind: 31; Name: ''),
    (DeviceID: $24c6530a; Kind: 31; Name: ''),
    (DeviceID: $24c6531a; Kind: 31; Name: ''),
    (DeviceID: $24c65397; Kind: 31; Name: ''),
    (DeviceID: $24c65500; Kind: 31; Name: ''),
    (DeviceID: $24c65501; Kind: 31; Name: ''),
    (DeviceID: $24c65502; Kind: 31; Name: ''),
    (DeviceID: $24c65503; Kind: 31; Name: ''),
    (DeviceID: $24c65506; Kind: 31; Name: ''),
    (DeviceID: $24c6550d; Kind: 31; Name: ''),
    (DeviceID: $24c6550e; Kind: 31; Name: ''),
    (DeviceID: $24c65508; Kind: 31; Name: ''),
    (DeviceID: $24c65510; Kind: 31; Name: ''),
    (DeviceID: $24c65b00; Kind: 31; Name: ''),
    (DeviceID: $24c65b02; Kind: 31; Name: ''),
    (DeviceID: $24c65b03; Kind: 31; Name: ''),
    (DeviceID: $24c65d04; Kind: 31; Name: ''),
    (DeviceID: $24c6fafa; Kind: 31; Name: ''),
    (DeviceID: $24c6fafb; Kind: 31; Name: ''),
    (DeviceID: $24c6fafc; Kind: 31; Name: ''),
    (DeviceID: $24c6fafd; Kind: 31; Name: ''),
    (DeviceID: $3537103e; Kind: 31; Name: 'Gamesir Xbox Controller'),
    (DeviceID: $24c6fafe; Kind: 31; Name: ''),
    (DeviceID: $36511000; Kind: 31; Name: ''),
    (DeviceID: $36516000; Kind: 31; Name: ''),
    (DeviceID: $03f00495; Kind: 32; Name: ''),
    (DeviceID: $044fd012; Kind: 32; Name: ''),
    (DeviceID: $045e02d1; Kind: 32; Name: 'Xbox One Controller'),
    (DeviceID: $045e02dd; Kind: 32; Name: 'Xbox One Controller'),
    (DeviceID: $045e02e0; Kind: 32; Name: 'Xbox One S Controller'),
    (DeviceID: $045e02ea; Kind: 32; Name: 'Xbox One S Controller'),
    (DeviceID: $045e02fd; Kind: 32; Name: 'Xbox One S Controller'),
    (DeviceID: $045e02ff; Kind: 32; Name: 'Xbox One Controller'),
    (DeviceID: $045e0b0a; Kind: 32; Name: 'Xbox Adaptive Controller'),
    (DeviceID: $045e0b0c; Kind: 32; Name: 'Xbox Adaptive Controller'),
    (DeviceID: $045e0b12; Kind: 32; Name: 'Xbox Series X Controller'),
    (DeviceID: $045e0b13; Kind: 32; Name: 'Xbox Series X Controller'),
    (DeviceID: $045e0b20; Kind: 32; Name: 'Xbox One S Controller'),
    (DeviceID: $045e0b21; Kind: 32; Name: 'Xbox Adaptive Controller'),
    (DeviceID: $07384a01; Kind: 32; Name: ''),
    (DeviceID: $0e6f0139; Kind: 32; Name: 'PDP Xbox One Afterglow'),
    (DeviceID: $0e6f013b; Kind: 32; Name: 'PDP Xbox One Face-Off Controller'),
    (DeviceID: $0e6f013a; Kind: 32; Name: ''),
    (DeviceID: $0e6f0145; Kind: 32; Name: 'PDP MK X Fight Pad'),
    (DeviceID: $0e6f0146; Kind: 32; Name: 'PDP Xbox One Rock Candy'),
    (DeviceID: $0e6f015b; Kind: 32; Name: 'PDP Fallout 4 Vault Boy Controller'),
    (DeviceID: $0e6f015c; Kind: 32; Name: 'PDP Xbox One @Play Controller'),
    (DeviceID: $0e6f015d; Kind: 32; Name: 'PDP Mirror''s Edge Controller'),
    (DeviceID: $0e6f015f; Kind: 32; Name: 'PDP Metallic Controller'),
    (DeviceID: $0e6f0160; Kind: 32; Name: 'PDP NFL Face-Off Controller'),
    (DeviceID: $0e6f0161; Kind: 32; Name: 'PDP Xbox One Camo'),
    (DeviceID: $0e6f0162; Kind: 32; Name: 'PDP Xbox One Controller'),
    (DeviceID: $0e6f0163; Kind: 32; Name: 'PDP Deliverer of Truth'),
    (DeviceID: $0e6f0164; Kind: 32; Name: 'PDP Battlefield 1 Controller'),
    (DeviceID: $0e6f0165; Kind: 32; Name: 'PDP Titanfall 2 Controller'),
    (DeviceID: $0e6f0166; Kind: 32; Name: 'PDP Mass Effect: Andromeda Controller'),
    (DeviceID: $0e6f0167; Kind: 32; Name: 'PDP Halo Wars 2 Face-Off Controller'),
    (DeviceID: $0e6f0205; Kind: 32; Name: 'PDP Victrix Pro Fight Stick'),
    (DeviceID: $0e6f0206; Kind: 32; Name: 'PDP Mortal Kombat Controller'),
    (DeviceID: $0e6f0246; Kind: 32; Name: 'PDP Xbox One Rock Candy'),
    (DeviceID: $0e6f0261; Kind: 32; Name: 'PDP Xbox One Camo'),
    (DeviceID: $0e6f0262; Kind: 32; Name: 'PDP Xbox One Controller'),
    (DeviceID: $0e6f02a0; Kind: 32; Name: 'PDP Xbox One Midnight Blue'),
    (DeviceID: $0e6f02a1; Kind: 32; Name: 'PDP Xbox One Verdant Green'),
    (DeviceID: $0e6f02a2; Kind: 32; Name: 'PDP Xbox One Crimson Red'),
    (DeviceID: $0e6f02a3; Kind: 32; Name: 'PDP Xbox One Arctic White'),
    (DeviceID: $0e6f02a4; Kind: 32; Name: 'PDP Xbox One Phantom Black'),
    (DeviceID: $0e6f02a5; Kind: 32; Name: 'PDP Xbox One Ghost White'),
    (DeviceID: $0e6f02a6; Kind: 32; Name: 'PDP Xbox One Revenant Blue'),
    (DeviceID: $0e6f02a7; Kind: 32; Name: 'PDP Xbox One Raven Black'),
    (DeviceID: $0e6f02a8; Kind: 32; Name: 'PDP Xbox One Arctic White'),
    (DeviceID: $0e6f02a9; Kind: 32; Name: 'PDP Xbox One Midnight Blue'),
    (DeviceID: $0e6f02aa; Kind: 32; Name: 'PDP Xbox One Verdant Green'),
    (DeviceID: $0e6f02ab; Kind: 32; Name: 'PDP Xbox One Crimson Red'),
    (DeviceID: $0e6f02ac; Kind: 32; Name: 'PDP Xbox One Ember Orange'),
    (DeviceID: $0e6f02ad; Kind: 32; Name: 'PDP Xbox One Phantom Black'),
    (DeviceID: $0e6f02ae; Kind: 32; Name: 'PDP Xbox One Ghost White'),
    (DeviceID: $0e6f02af; Kind: 32; Name: 'PDP Xbox One Revenant Blue'),
    (DeviceID: $0e6f02b0; Kind: 32; Name: 'PDP Xbox One Raven Black'),
    (DeviceID: $0e6f02b1; Kind: 32; Name: 'PDP Xbox One Arctic White'),
    (DeviceID: $0e6f02b3; Kind: 32; Name: 'PDP Xbox One Afterglow'),
    (DeviceID: $0e6f02b5; Kind: 32; Name: 'PDP Xbox One GAMEware Controller'),
    (DeviceID: $0e6f02b6; Kind: 32; Name: ''),
    (DeviceID: $0e6f02bd; Kind: 32; Name: 'PDP Xbox One Royal Purple'),
    (DeviceID: $0e6f02be; Kind: 32; Name: 'PDP Xbox One Raven Black'),
    (DeviceID: $0e6f02bf; Kind: 32; Name: 'PDP Xbox One Midnight Blue'),
    (DeviceID: $0e6f02c0; Kind: 32; Name: 'PDP Xbox One Phantom Black'),
    (DeviceID: $0e6f02c1; Kind: 32; Name: 'PDP Xbox One Ghost White'),
    (DeviceID: $0e6f02c2; Kind: 32; Name: 'PDP Xbox One Revenant Blue'),
    (DeviceID: $0e6f02c3; Kind: 32; Name: 'PDP Xbox One Verdant Green'),
    (DeviceID: $0e6f02c4; Kind: 32; Name: 'PDP Xbox One Ember Orange'),
    (DeviceID: $0e6f02c5; Kind: 32; Name: 'PDP Xbox One Royal Purple'),
    (DeviceID: $0e6f02c6; Kind: 32; Name: 'PDP Xbox One Crimson Red'),
    (DeviceID: $0e6f02c7; Kind: 32; Name: 'PDP Xbox One Arctic White'),
    (DeviceID: $0e6f02c8; Kind: 32; Name: 'PDP Kingdom Hearts Controller'),
    (DeviceID: $0e6f02c9; Kind: 32; Name: 'PDP Xbox One Phantasm Red'),
    (DeviceID: $0e6f02ca; Kind: 32; Name: 'PDP Xbox One Specter Violet'),
    (DeviceID: $0e6f02cb; Kind: 32; Name: 'PDP Xbox One Specter Violet'),
    (DeviceID: $0e6f02cd; Kind: 32; Name: 'PDP Xbox One Blu-merang'),
    (DeviceID: $0e6f02ce; Kind: 32; Name: 'PDP Xbox One Cranblast'),
    (DeviceID: $0e6f02cf; Kind: 32; Name: 'PDP Xbox One Aqualime'),
    (DeviceID: $0e6f02d5; Kind: 32; Name: 'PDP Xbox One Red Camo'),
    (DeviceID: $0e6f0346; Kind: 32; Name: 'PDP Xbox One RC Gamepad'),
    (DeviceID: $0e6f0446; Kind: 32; Name: 'PDP Xbox One RC Gamepad'),
    (DeviceID: $0e6f02da; Kind: 32; Name: 'PDP Xbox Series X Afterglow'),
    (DeviceID: $0e6f02d6; Kind: 32; Name: 'Victrix Gambit Tournament Controller'),
    (DeviceID: $0e6f02d9; Kind: 32; Name: 'PDP Xbox Series X Midnight Blue'),
    (DeviceID: $0f0d0063; Kind: 32; Name: ''),
    (DeviceID: $0f0d0067; Kind: 32; Name: ''),
    (DeviceID: $0f0d0078; Kind: 32; Name: ''),
    (DeviceID: $0f0d00c5; Kind: 32; Name: ''),
    (DeviceID: $0f0d0150; Kind: 32; Name: ''),
    (DeviceID: $10f57009; Kind: 32; Name: ''),
    (DeviceID: $10f57013; Kind: 32; Name: ''),
    (DeviceID: $15320a00; Kind: 32; Name: ''),
    (DeviceID: $15320a03; Kind: 32; Name: ''),
    (DeviceID: $15320a14; Kind: 32; Name: ''),
    (DeviceID: $15320a15; Kind: 32; Name: ''),
    (DeviceID: $20d62001; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d62002; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d62003; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d62004; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d62005; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d62006; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d62009; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d6200a; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d6200b; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d6200c; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d6200d; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d6200e; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d6200f; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d62011; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d62012; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d62015; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d62016; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d62017; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d62018; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d62019; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d6201a; Kind: 32; Name: 'PowerA Xbox Series X Controller'),
    (DeviceID: $20d64001; Kind: 32; Name: 'PowerA Fusion Pro 2 Controller'),
    (DeviceID: $20d64002; Kind: 32; Name: 'PowerA Spectra Infinity Controller'),
    (DeviceID: $20d6890b; Kind: 32; Name: ''),
    (DeviceID: $24c6541a; Kind: 32; Name: ''),
    (DeviceID: $24c6542a; Kind: 32; Name: ''),
    (DeviceID: $24c6543a; Kind: 32; Name: 'PowerA Xbox One Controller'),
    (DeviceID: $24c6551a; Kind: 32; Name: ''),
    (DeviceID: $24c6561a; Kind: 32; Name: ''),
    (DeviceID: $24c6581a; Kind: 32; Name: ''),
    (DeviceID: $24c6591a; Kind: 32; Name: ''),
    (DeviceID: $24c6592a; Kind: 32; Name: ''),
    (DeviceID: $24c6791a; Kind: 32; Name: ''),
    (DeviceID: $2dc82002; Kind: 32; Name: ''),
    (DeviceID: $2dc83106; Kind: 32; Name: ''),
    (DeviceID: $2dc8310a; Kind: 32; Name: ''),
    (DeviceID: $2e240652; Kind: 32; Name: ''),
    (DeviceID: $2e241618; Kind: 32; Name: ''),
    (DeviceID: $2e241688; Kind: 32; Name: ''),
    (DeviceID: $146b0611; Kind: 32; Name: ''),
    (DeviceID: $0e6f1414; Kind: 31; Name: ''),
    (DeviceID: $0e6f0159; Kind: 31; Name: ''),
    (DeviceID: $24c6faff; Kind: 31; Name: ''),
    (DeviceID: $0f0d006d; Kind: 31; Name: ''),
    (DeviceID: $0f0d00a4; Kind: 31; Name: ''),
    (DeviceID: $00791832; Kind: 31; Name: ''),
    (DeviceID: $0079187f; Kind: 31; Name: ''),
    (DeviceID: $00791883; Kind: 31; Name: ''),
    (DeviceID: $03ebff01; Kind: 31; Name: ''),
    (DeviceID: $0c120ef8; Kind: 31; Name: ''),
    (DeviceID: $046d1000; Kind: 31; Name: ''),
    (DeviceID: $11ff0511; Kind: 31; Name: ''),
    (DeviceID: $13456006; Kind: 31; Name: ''),
    (DeviceID: $056e2012; Kind: 31; Name: ''),
    (DeviceID: $146b0602; Kind: 31; Name: ''),
    (DeviceID: $0f0d00ae; Kind: 31; Name: ''),
    (DeviceID: $046d0401; Kind: 31; Name: ''),
    (DeviceID: $046d0301; Kind: 31; Name: ''),
    (DeviceID: $046dcaa3; Kind: 31; Name: ''),
    (DeviceID: $046dc261; Kind: 31; Name: ''),
    (DeviceID: $046d0291; Kind: 31; Name: ''),
    (DeviceID: $007918d3; Kind: 31; Name: ''),
    (DeviceID: $0f0d00b1; Kind: 31; Name: ''),
    (DeviceID: $0079188e; Kind: 31; Name: ''),
    (DeviceID: $0079187c; Kind: 31; Name: ''),
    (DeviceID: $0079189c; Kind: 31; Name: ''),
    (DeviceID: $00791874; Kind: 31; Name: ''),
    (DeviceID: $2f240050; Kind: 32; Name: ''),
    (DeviceID: $2f242e; Kind: 32; Name: ''),
    (DeviceID: $2f2491; Kind: 32; Name: ''),
    (DeviceID: $1430719; Kind: 32; Name: ''),
    (DeviceID: $f0ded; Kind: 32; Name: ''),
    (DeviceID: $f0dc0; Kind: 32; Name: ''),
    (DeviceID: $e6f152; Kind: 32; Name: ''),
    (DeviceID: $46d1007; Kind: 32; Name: ''),
    (DeviceID: $e6f2b8; Kind: 32; Name: ''),
    (DeviceID: $7918a1; Kind: 32; Name: ''),
    (DeviceID: $06686; Kind: 32; Name: ''),
    (DeviceID: $12ab304; Kind: 32; Name: ''),
    (DeviceID: $1430291; Kind: 32; Name: ''),
    (DeviceID: $14302a9; Kind: 32; Name: ''),
    (DeviceID: $143070b; Kind: 32; Name: ''),
    (DeviceID: $1bad28e; Kind: 32; Name: ''),
    (DeviceID: $1bad2a0; Kind: 32; Name: ''),
    (DeviceID: $1bad5500; Kind: 32; Name: ''),
    (DeviceID: $20ab55ef; Kind: 32; Name: ''),
    (DeviceID: $24c65509; Kind: 32; Name: ''),
    (DeviceID: $251669; Kind: 32; Name: ''),
    (DeviceID: $25b1360; Kind: 32; Name: ''),
    (DeviceID: $2c222203; Kind: 32; Name: ''),
    (DeviceID: $2f2411; Kind: 32; Name: ''),
    (DeviceID: $2f2453; Kind: 32; Name: ''),
    (DeviceID: $2f24b7; Kind: 32; Name: ''),
    (DeviceID: $46d0; Kind: 32; Name: ''),
    (DeviceID: $46d1004; Kind: 32; Name: ''),
    (DeviceID: $46d1008; Kind: 32; Name: ''),
    (DeviceID: $46df301; Kind: 32; Name: ''),
    (DeviceID: $7382a0; Kind: 32; Name: ''),
    (DeviceID: $7387263; Kind: 32; Name: ''),
    (DeviceID: $738b738; Kind: 32; Name: ''),
    (DeviceID: $738cb29; Kind: 32; Name: ''),
    (DeviceID: $738f401; Kind: 32; Name: ''),
    (DeviceID: $7918c2; Kind: 32; Name: ''),
    (DeviceID: $7918c8; Kind: 32; Name: ''),
    (DeviceID: $7918cf; Kind: 32; Name: ''),
    (DeviceID: $c12e17; Kind: 32; Name: ''),
    (DeviceID: $c12e1c; Kind: 32; Name: ''),
    (DeviceID: $c12e22; Kind: 32; Name: ''),
    (DeviceID: $c12e30; Kind: 32; Name: ''),
    (DeviceID: $d2d2d2d2; Kind: 32; Name: ''),
    (DeviceID: $d629a1a; Kind: 32; Name: ''),
    (DeviceID: $d629a1b; Kind: 32; Name: ''),
    (DeviceID: $e00e00; Kind: 32; Name: ''),
    (DeviceID: $e6f12a; Kind: 32; Name: ''),
    (DeviceID: $e6f2b2; Kind: 32; Name: ''),
    (DeviceID: $f0d97; Kind: 32; Name: ''),
    (DeviceID: $f0dba; Kind: 32; Name: ''),
    (DeviceID: $f0dd8; Kind: 32; Name: ''),
    (DeviceID: $fff2a1; Kind: 32; Name: ''),
    (DeviceID: $45e867; Kind: 32; Name: ''),
    (DeviceID: $16d0f3f; Kind: 32; Name: ''),
    (DeviceID: $2f248f; Kind: 32; Name: ''),
    (DeviceID: $e6ff501; Kind: 32; Name: ''),
    (DeviceID: $057e2006; Kind: 39; Name: ''),
    (DeviceID: $057e2067; Kind: 39; Name: ''),
    (DeviceID: $057e2007; Kind: 40; Name: ''),
    (DeviceID: $057e2066; Kind: 40; Name: ''),
    (DeviceID: $057e2008; Kind: 41; Name: ''),
    (DeviceID: $057e2068; Kind: 41; Name: ''),
    (DeviceID: $057e2009; Kind: 38; Name: ''),
    (DeviceID: $057e2069; Kind: 51; Name: ''),
    (DeviceID: $0f0d00c1; Kind: 42; Name: ''),
    (DeviceID: $0f0d0092; Kind: 42; Name: ''),
    (DeviceID: $0f0d00f6; Kind: 38; Name: ''),
    (DeviceID: $0f0d00dc; Kind: 44; Name: ''),
    (DeviceID: $0e6f0180; Kind: 42; Name: ''),
    (DeviceID: $0e6f0181; Kind: 42; Name: ''),
    (DeviceID: $0e6f0184; Kind: 42; Name: ''),
    (DeviceID: $0e6f0185; Kind: 42; Name: ''),
    (DeviceID: $0e6f0186; Kind: 38; Name: ''),
    (DeviceID: $0e6f0187; Kind: 42; Name: ''),
    (DeviceID: $0e6f0188; Kind: 42; Name: ''),
    (DeviceID: $0e6f018b; Kind: 42; Name: ''),
    (DeviceID: $0e6f018c; Kind: 38; Name: 'PDP REALMz Wireless Controller'),
    (DeviceID: $0e6f0193; Kind: 51; Name: ''),
    (DeviceID: $0e6f0196; Kind: 52; Name: ''),
    (DeviceID: $0e6f0197; Kind: 52; Name: ''),
    (DeviceID: $0e6f0198; Kind: 52; Name: ''),
    (DeviceID: $0f0d00aa; Kind: 42; Name: ''),
    (DeviceID: $20d6a711; Kind: 42; Name: ''),
    (DeviceID: $20d6a712; Kind: 42; Name: ''),
    (DeviceID: $20d6a713; Kind: 42; Name: ''),
    (DeviceID: $20d6a714; Kind: 42; Name: ''),
    (DeviceID: $20d6a715; Kind: 42; Name: ''),
    (DeviceID: $20d6a716; Kind: 42; Name: ''),
    (DeviceID: $20d6a718; Kind: 42; Name: ''),
    (DeviceID: $33dd0001; Kind: 42; Name: ''),
    (DeviceID: $33dd0002; Kind: 42; Name: ''),
    (DeviceID: $33dd0003; Kind: 42; Name: ''),
    (DeviceID: $0f0d00f0; Kind: 42; Name: ''),
    (DeviceID: $054c0df2; Kind: 48; Name: ''),
    (DeviceID: $045e02e3; Kind: 46; Name: 'Xbox One Elite Controller'),
    (DeviceID: $045e0b00; Kind: 46; Name: 'Xbox One Elite 2 Controller'),
    (DeviceID: $045e0b05; Kind: 46; Name: 'Xbox One Elite 2 Controller'),
    (DeviceID: $045e0b22; Kind: 46; Name: 'Xbox One Elite 2 Controller'),
    (DeviceID: $2dc86000; Kind: 50; Name: '8Bitdo SF30 Controller'),
    (DeviceID: $2dc86100; Kind: 50; Name: '8Bitdo SF30 Controller'),
    (DeviceID: $2dc86001; Kind: 50; Name: '8Bitdo SN30 Controller'),
    (DeviceID: $2dc86101; Kind: 50; Name: '8Bitdo SN30 Controller'),
    (DeviceID: $2dc86003; Kind: 50; Name: '8Bitdo Pro 2 Controller'),
    (DeviceID: $2dc86006; Kind: 50; Name: '8Bitdo Pro 2 Controller'),
    (DeviceID: $2dc86009; Kind: 50; Name: '8Bitdo Pro 3 Controller'),
    (DeviceID: $2dc86012; Kind: 50; Name: '8Bitdo Ultimate 2 Wireless Controller'),
    (DeviceID: $000011fb; Kind: 43; Name: ''),
    (DeviceID: $28de1101; Kind: 2; Name: ''),
    (DeviceID: $28de1102; Kind: 2; Name: ''),
    (DeviceID: $28de1105; Kind: 2; Name: ''),
    (DeviceID: $28de1106; Kind: 2; Name: ''),
    (DeviceID: $28de11ff; Kind: 30; Name: ''),
    (DeviceID: $28de1142; Kind: 2; Name: ''),
    (DeviceID: $28de1201; Kind: 3; Name: ''),
    (DeviceID: $28de1202; Kind: 3; Name: ''),
    (DeviceID: $28de1205; Kind: 4; Name: ''),
    (DeviceID: $28de1302; Kind: 10; Name: ''),
    (DeviceID: $28de1303; Kind: 10; Name: ''),
    (DeviceID: $28de1304; Kind: 10; Name: ''),
    (DeviceID: $28de1305; Kind: 10; Name: ''),
    (DeviceID: $0f0d01ab; Kind: 49; Name: ''),
    (DeviceID: $0f0d0196; Kind: 49; Name: '')
  );
