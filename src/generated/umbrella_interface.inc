// アンブレラ（PaPiMeLa.pas）の interface 部に入る宣言。
// tools/genumbrella.bb が次のユニットの interface 部から生成する。手で直さず、
// 生成器を直して作り直すこと（tools/genumbrella.bb --check が古さを調べる）。
//   PaPiMeLa.Types
//   PaPiMeLa.Errors
//   PaPiMeLa.Core
//   PaPiMeLa.Events
//   PaPiMeLa.Events.Drop
//   PaPiMeLa.Events.Keymap
//   PaPiMeLa.Keycodes
//   PaPiMeLa.Pixels
//   PaPiMeLa.Surface
//   PaPiMeLa.Surface.Blit
//   PaPiMeLa.Surface.BMP
//   PaPiMeLa.IO
//   PaPiMeLa.Video
//   PaPiMeLa.Clipboard
//   PaPiMeLa.Render
//   PaPiMeLa.TextInput
//   PaPiMeLa.Time
//   PaPiMeLa.Atomic
//   PaPiMeLa.Threading
//   PaPiMeLa.Properties
//   PaPiMeLa.Log
//   PaPiMeLa.App
//   PaPiMeLa.Video.Backend
//   PaPiMeLa.TextInput.Backend

// ---- PaPiMeLa.Types
type
  TPMLSubsystemTag = PaPiMeLa.Types.TPMLSubsystemTag;
  TPMLWindowID = PaPiMeLa.Types.TPMLWindowID;
  TPMLStringArray = PaPiMeLa.Types.TPMLStringArray;
  TPMLRect = PaPiMeLa.Types.TPMLRect;
  TPMLColor = PaPiMeLa.Types.TPMLColor;
  TPMLColors = PaPiMeLa.Types.TPMLColors;
  TPMLFColor = PaPiMeLa.Types.TPMLFColor;
  TPMLBlendMode = PaPiMeLa.Types.TPMLBlendMode;
  TPMLScaleMode = PaPiMeLa.Types.TPMLScaleMode;
  TPMLFPoint = PaPiMeLa.Types.TPMLFPoint;
  TPMLFPoints = PaPiMeLa.Types.TPMLFPoints;
  TPMLFRect = PaPiMeLa.Types.TPMLFRect;
  TPMLFRects = PaPiMeLa.Types.TPMLFRects;
  TPMLKeyModifier = PaPiMeLa.Types.TPMLKeyModifier;
  TPMLKeyModifiers = PaPiMeLa.Types.TPMLKeyModifiers;
  TPMLKeyFilterResult = PaPiMeLa.Types.TPMLKeyFilterResult;
  TPMLSegmentState = PaPiMeLa.Types.TPMLSegmentState;
  TPMLUnderlineStyle = PaPiMeLa.Types.TPMLUnderlineStyle;
  TPMLCompositionSegment = PaPiMeLa.Types.TPMLCompositionSegment;
  TPMLCompositionSegments = PaPiMeLa.Types.TPMLCompositionSegments;
  TPMLComposition = PaPiMeLa.Types.TPMLComposition;
  TPMLTextEditingData = PaPiMeLa.Types.TPMLTextEditingData;
  TPMLDeleteSurroundingData = PaPiMeLa.Types.TPMLDeleteSurroundingData;
  TPMLSubsystemTagHelper = type helper(PaPiMeLa.Types.TPMLSubsystemTagHelper) for TPMLSubsystemTag end;

// ---- PaPiMeLa.Errors
type
  EPMLError = PaPiMeLa.Errors.EPMLError;
  EPMLInitError = PaPiMeLa.Errors.EPMLInitError;
  EPMLVideoError = PaPiMeLa.Errors.EPMLVideoError;
  EPMLRenderError = PaPiMeLa.Errors.EPMLRenderError;
  EPMLAudioError = PaPiMeLa.Errors.EPMLAudioError;
  EPMLInputError = PaPiMeLa.Errors.EPMLInputError;
  EPMLTextInputError = PaPiMeLa.Errors.EPMLTextInputError;
  EPMLIOError = PaPiMeLa.Errors.EPMLIOError;
  EPMLThreadError = PaPiMeLa.Errors.EPMLThreadError;
  EPMLEventError = PaPiMeLa.Errors.EPMLEventError;
  EPMLUnsupported = PaPiMeLa.Errors.EPMLUnsupported;
  EPMLArgument = PaPiMeLa.Errors.EPMLArgument;
  EPMLThreadAffinity = PaPiMeLa.Errors.EPMLThreadAffinity;
  EPMLBackendLost = PaPiMeLa.Errors.EPMLBackendLost;
  EPMLPlatformLibrary = PaPiMeLa.Errors.EPMLPlatformLibrary;

// ---- PaPiMeLa.Core
type
  TPMLSubsystem = PaPiMeLa.Core.TPMLSubsystem;
  TPMLSubsystems = PaPiMeLa.Core.TPMLSubsystems;
  TPMLTimerService = PaPiMeLa.Core.TPMLTimerService;
  TPMLContextOptions = PaPiMeLa.Core.TPMLContextOptions;
  TPMLContext = PaPiMeLa.Core.TPMLContext;

// ---- PaPiMeLa.Events
type
  TPMLEventKind = PaPiMeLa.Events.TPMLEventKind;
  TPMLEventKinds = PaPiMeLa.Events.TPMLEventKinds;
  TPMLKeyEventData = PaPiMeLa.Events.TPMLKeyEventData;
  TPMLWindowEventData = PaPiMeLa.Events.TPMLWindowEventData;
  TPMLMouseMotionData = PaPiMeLa.Events.TPMLMouseMotionData;
  TPMLMouseButtonData = PaPiMeLa.Events.TPMLMouseButtonData;
  TPMLMouseWheelData = PaPiMeLa.Events.TPMLMouseWheelData;
  TPMLTouchPoint = PaPiMeLa.Events.TPMLTouchPoint;
  TPMLTouchPoints = PaPiMeLa.Events.TPMLTouchPoints;
  TPMLTouchFingerData = PaPiMeLa.Events.TPMLTouchFingerData;
  TPMLDropEventData = PaPiMeLa.Events.TPMLDropEventData;
  TPMLDragAction = PaPiMeLa.Events.TPMLDragAction;
  TPMLDragActions = PaPiMeLa.Events.TPMLDragActions;
  TPMLDragEventData = PaPiMeLa.Events.TPMLDragEventData;
  TPMLClipboardEventData = PaPiMeLa.Events.TPMLClipboardEventData;
  TPMLUserEventData = PaPiMeLa.Events.TPMLUserEventData;
  TPMLEvent = PaPiMeLa.Events.TPMLEvent;
  IPMLEventPumpSource = PaPiMeLa.Events.IPMLEventPumpSource;
  IPMLEventWatch = PaPiMeLa.Events.IPMLEventWatch;
  IPMLKeyFilter = PaPiMeLa.Events.IPMLKeyFilter;
  TPMLDeferredKey = PaPiMeLa.Events.TPMLDeferredKey;
  TPMLDeferredKeyQueue = PaPiMeLa.Events.TPMLDeferredKeyQueue;
  TPMLMainThreadProc = PaPiMeLa.Events.TPMLMainThreadProc;
  TPMLKeyboardState = PaPiMeLa.Events.TPMLKeyboardState;
  TPMLMouseState = PaPiMeLa.Events.TPMLMouseState;
  TPMLTouchState = PaPiMeLa.Events.TPMLTouchState;
  TPMLDropState = PaPiMeLa.Events.TPMLDropState;
  TPMLEventQueue = PaPiMeLa.Events.TPMLEventQueue;
function PMLNowNS: UInt64; inline;

// ---- PaPiMeLa.Events.Drop
function PMLURIToLocalPath(const AURI: String; out APath: String): Boolean; inline;
function PMLURIListToLocalPaths(const AList: String): TStringArray; inline;

// ---- PaPiMeLa.Events.Keymap
type
  TPMLKeycodeOption = PaPiMeLa.Events.Keymap.TPMLKeycodeOption;
  TPMLKeycodeOptions = PaPiMeLa.Events.Keymap.TPMLKeycodeOptions;
  TPMLKeymap = PaPiMeLa.Events.Keymap.TPMLKeymap;
  TPMLScancodeHelper = type helper(PaPiMeLa.Events.Keymap.TPMLScancodeHelper) for TPMLScancode end;
  TPMLKeycodeHelper = type helper(PaPiMeLa.Events.Keymap.TPMLKeycodeHelper) for TPMLKeycode end;
const
  PML_DEFAULT_KEYCODE_OPTIONS = PaPiMeLa.Events.Keymap.PML_DEFAULT_KEYCODE_OPTIONS;
function PMLDefaultKeyFromScancode(AScancode: TPMLScancode; AShifted: Boolean): TPMLKeycode; inline;
function PMLDefaultScancodeFromKey(AKey: TPMLKeycode; out AShifted: Boolean): TPMLScancode; inline;
function PMLScancodeFromName(const AName: String): TPMLScancode; inline;
function PMLKeysymToUcs4(AKeysym: LongWord): LongWord; inline;
function PMLKeymapKeycode(
  AKeysym: LongWord;
  AScancode: TPMLScancode;
  AShifted: Boolean): TPMLKeycode; inline;
function PMLScancodeFromEvdev(AEvdevCode: LongWord): TPMLScancode; inline;

// ---- PaPiMeLa.Keycodes
type
  TPMLScancode = PaPiMeLa.Keycodes.TPMLScancode;
  TPMLKeycode = PaPiMeLa.Keycodes.TPMLKeycode;
const
  PMLK_EXTENDED_MASK = PaPiMeLa.Keycodes.PMLK_EXTENDED_MASK;
  PMLK_SCANCODE_MASK = PaPiMeLa.Keycodes.PMLK_SCANCODE_MASK;
  PMLK_UNKNOWN = PaPiMeLa.Keycodes.PMLK_UNKNOWN;
  PMLK_RETURN = PaPiMeLa.Keycodes.PMLK_RETURN;
  PMLK_ESCAPE = PaPiMeLa.Keycodes.PMLK_ESCAPE;
  PMLK_BACKSPACE = PaPiMeLa.Keycodes.PMLK_BACKSPACE;
  PMLK_TAB = PaPiMeLa.Keycodes.PMLK_TAB;
  PMLK_SPACE = PaPiMeLa.Keycodes.PMLK_SPACE;
  PMLK_EXCLAIM = PaPiMeLa.Keycodes.PMLK_EXCLAIM;
  PMLK_DBLAPOSTROPHE = PaPiMeLa.Keycodes.PMLK_DBLAPOSTROPHE;
  PMLK_HASH = PaPiMeLa.Keycodes.PMLK_HASH;
  PMLK_DOLLAR = PaPiMeLa.Keycodes.PMLK_DOLLAR;
  PMLK_PERCENT = PaPiMeLa.Keycodes.PMLK_PERCENT;
  PMLK_AMPERSAND = PaPiMeLa.Keycodes.PMLK_AMPERSAND;
  PMLK_APOSTROPHE = PaPiMeLa.Keycodes.PMLK_APOSTROPHE;
  PMLK_LEFTPAREN = PaPiMeLa.Keycodes.PMLK_LEFTPAREN;
  PMLK_RIGHTPAREN = PaPiMeLa.Keycodes.PMLK_RIGHTPAREN;
  PMLK_ASTERISK = PaPiMeLa.Keycodes.PMLK_ASTERISK;
  PMLK_PLUS = PaPiMeLa.Keycodes.PMLK_PLUS;
  PMLK_COMMA = PaPiMeLa.Keycodes.PMLK_COMMA;
  PMLK_MINUS = PaPiMeLa.Keycodes.PMLK_MINUS;
  PMLK_PERIOD = PaPiMeLa.Keycodes.PMLK_PERIOD;
  PMLK_SLASH = PaPiMeLa.Keycodes.PMLK_SLASH;
  PMLK_0 = PaPiMeLa.Keycodes.PMLK_0;
  PMLK_1 = PaPiMeLa.Keycodes.PMLK_1;
  PMLK_2 = PaPiMeLa.Keycodes.PMLK_2;
  PMLK_3 = PaPiMeLa.Keycodes.PMLK_3;
  PMLK_4 = PaPiMeLa.Keycodes.PMLK_4;
  PMLK_5 = PaPiMeLa.Keycodes.PMLK_5;
  PMLK_6 = PaPiMeLa.Keycodes.PMLK_6;
  PMLK_7 = PaPiMeLa.Keycodes.PMLK_7;
  PMLK_8 = PaPiMeLa.Keycodes.PMLK_8;
  PMLK_9 = PaPiMeLa.Keycodes.PMLK_9;
  PMLK_COLON = PaPiMeLa.Keycodes.PMLK_COLON;
  PMLK_SEMICOLON = PaPiMeLa.Keycodes.PMLK_SEMICOLON;
  PMLK_LESS = PaPiMeLa.Keycodes.PMLK_LESS;
  PMLK_EQUALS = PaPiMeLa.Keycodes.PMLK_EQUALS;
  PMLK_GREATER = PaPiMeLa.Keycodes.PMLK_GREATER;
  PMLK_QUESTION = PaPiMeLa.Keycodes.PMLK_QUESTION;
  PMLK_AT = PaPiMeLa.Keycodes.PMLK_AT;
  PMLK_LEFTBRACKET = PaPiMeLa.Keycodes.PMLK_LEFTBRACKET;
  PMLK_BACKSLASH = PaPiMeLa.Keycodes.PMLK_BACKSLASH;
  PMLK_RIGHTBRACKET = PaPiMeLa.Keycodes.PMLK_RIGHTBRACKET;
  PMLK_CARET = PaPiMeLa.Keycodes.PMLK_CARET;
  PMLK_UNDERSCORE = PaPiMeLa.Keycodes.PMLK_UNDERSCORE;
  PMLK_GRAVE = PaPiMeLa.Keycodes.PMLK_GRAVE;
  PMLK_A = PaPiMeLa.Keycodes.PMLK_A;
  PMLK_B = PaPiMeLa.Keycodes.PMLK_B;
  PMLK_C = PaPiMeLa.Keycodes.PMLK_C;
  PMLK_D = PaPiMeLa.Keycodes.PMLK_D;
  PMLK_E = PaPiMeLa.Keycodes.PMLK_E;
  PMLK_F = PaPiMeLa.Keycodes.PMLK_F;
  PMLK_G = PaPiMeLa.Keycodes.PMLK_G;
  PMLK_H = PaPiMeLa.Keycodes.PMLK_H;
  PMLK_I = PaPiMeLa.Keycodes.PMLK_I;
  PMLK_J = PaPiMeLa.Keycodes.PMLK_J;
  PMLK_K = PaPiMeLa.Keycodes.PMLK_K;
  PMLK_L = PaPiMeLa.Keycodes.PMLK_L;
  PMLK_M = PaPiMeLa.Keycodes.PMLK_M;
  PMLK_N = PaPiMeLa.Keycodes.PMLK_N;
  PMLK_O = PaPiMeLa.Keycodes.PMLK_O;
  PMLK_P = PaPiMeLa.Keycodes.PMLK_P;
  PMLK_Q = PaPiMeLa.Keycodes.PMLK_Q;
  PMLK_R = PaPiMeLa.Keycodes.PMLK_R;
  PMLK_S = PaPiMeLa.Keycodes.PMLK_S;
  PMLK_T = PaPiMeLa.Keycodes.PMLK_T;
  PMLK_U = PaPiMeLa.Keycodes.PMLK_U;
  PMLK_V = PaPiMeLa.Keycodes.PMLK_V;
  PMLK_W = PaPiMeLa.Keycodes.PMLK_W;
  PMLK_X = PaPiMeLa.Keycodes.PMLK_X;
  PMLK_Y = PaPiMeLa.Keycodes.PMLK_Y;
  PMLK_Z = PaPiMeLa.Keycodes.PMLK_Z;
  PMLK_LEFTBRACE = PaPiMeLa.Keycodes.PMLK_LEFTBRACE;
  PMLK_PIPE = PaPiMeLa.Keycodes.PMLK_PIPE;
  PMLK_RIGHTBRACE = PaPiMeLa.Keycodes.PMLK_RIGHTBRACE;
  PMLK_TILDE = PaPiMeLa.Keycodes.PMLK_TILDE;
  PMLK_DELETE = PaPiMeLa.Keycodes.PMLK_DELETE;
  PMLK_PLUSMINUS = PaPiMeLa.Keycodes.PMLK_PLUSMINUS;
  PMLK_CAPSLOCK = PaPiMeLa.Keycodes.PMLK_CAPSLOCK;
  PMLK_F1 = PaPiMeLa.Keycodes.PMLK_F1;
  PMLK_F2 = PaPiMeLa.Keycodes.PMLK_F2;
  PMLK_F3 = PaPiMeLa.Keycodes.PMLK_F3;
  PMLK_F4 = PaPiMeLa.Keycodes.PMLK_F4;
  PMLK_F5 = PaPiMeLa.Keycodes.PMLK_F5;
  PMLK_F6 = PaPiMeLa.Keycodes.PMLK_F6;
  PMLK_F7 = PaPiMeLa.Keycodes.PMLK_F7;
  PMLK_F8 = PaPiMeLa.Keycodes.PMLK_F8;
  PMLK_F9 = PaPiMeLa.Keycodes.PMLK_F9;
  PMLK_F10 = PaPiMeLa.Keycodes.PMLK_F10;
  PMLK_F11 = PaPiMeLa.Keycodes.PMLK_F11;
  PMLK_F12 = PaPiMeLa.Keycodes.PMLK_F12;
  PMLK_PRINTSCREEN = PaPiMeLa.Keycodes.PMLK_PRINTSCREEN;
  PMLK_SCROLLLOCK = PaPiMeLa.Keycodes.PMLK_SCROLLLOCK;
  PMLK_PAUSE = PaPiMeLa.Keycodes.PMLK_PAUSE;
  PMLK_INSERT = PaPiMeLa.Keycodes.PMLK_INSERT;
  PMLK_HOME = PaPiMeLa.Keycodes.PMLK_HOME;
  PMLK_PAGEUP = PaPiMeLa.Keycodes.PMLK_PAGEUP;
  PMLK_END = PaPiMeLa.Keycodes.PMLK_END;
  PMLK_PAGEDOWN = PaPiMeLa.Keycodes.PMLK_PAGEDOWN;
  PMLK_RIGHT = PaPiMeLa.Keycodes.PMLK_RIGHT;
  PMLK_LEFT = PaPiMeLa.Keycodes.PMLK_LEFT;
  PMLK_DOWN = PaPiMeLa.Keycodes.PMLK_DOWN;
  PMLK_UP = PaPiMeLa.Keycodes.PMLK_UP;
  PMLK_NUMLOCKCLEAR = PaPiMeLa.Keycodes.PMLK_NUMLOCKCLEAR;
  PMLK_KP_DIVIDE = PaPiMeLa.Keycodes.PMLK_KP_DIVIDE;
  PMLK_KP_MULTIPLY = PaPiMeLa.Keycodes.PMLK_KP_MULTIPLY;
  PMLK_KP_MINUS = PaPiMeLa.Keycodes.PMLK_KP_MINUS;
  PMLK_KP_PLUS = PaPiMeLa.Keycodes.PMLK_KP_PLUS;
  PMLK_KP_ENTER = PaPiMeLa.Keycodes.PMLK_KP_ENTER;
  PMLK_KP_1 = PaPiMeLa.Keycodes.PMLK_KP_1;
  PMLK_KP_2 = PaPiMeLa.Keycodes.PMLK_KP_2;
  PMLK_KP_3 = PaPiMeLa.Keycodes.PMLK_KP_3;
  PMLK_KP_4 = PaPiMeLa.Keycodes.PMLK_KP_4;
  PMLK_KP_5 = PaPiMeLa.Keycodes.PMLK_KP_5;
  PMLK_KP_6 = PaPiMeLa.Keycodes.PMLK_KP_6;
  PMLK_KP_7 = PaPiMeLa.Keycodes.PMLK_KP_7;
  PMLK_KP_8 = PaPiMeLa.Keycodes.PMLK_KP_8;
  PMLK_KP_9 = PaPiMeLa.Keycodes.PMLK_KP_9;
  PMLK_KP_0 = PaPiMeLa.Keycodes.PMLK_KP_0;
  PMLK_KP_PERIOD = PaPiMeLa.Keycodes.PMLK_KP_PERIOD;
  PMLK_APPLICATION = PaPiMeLa.Keycodes.PMLK_APPLICATION;
  PMLK_POWER = PaPiMeLa.Keycodes.PMLK_POWER;
  PMLK_KP_EQUALS = PaPiMeLa.Keycodes.PMLK_KP_EQUALS;
  PMLK_F13 = PaPiMeLa.Keycodes.PMLK_F13;
  PMLK_F14 = PaPiMeLa.Keycodes.PMLK_F14;
  PMLK_F15 = PaPiMeLa.Keycodes.PMLK_F15;
  PMLK_F16 = PaPiMeLa.Keycodes.PMLK_F16;
  PMLK_F17 = PaPiMeLa.Keycodes.PMLK_F17;
  PMLK_F18 = PaPiMeLa.Keycodes.PMLK_F18;
  PMLK_F19 = PaPiMeLa.Keycodes.PMLK_F19;
  PMLK_F20 = PaPiMeLa.Keycodes.PMLK_F20;
  PMLK_F21 = PaPiMeLa.Keycodes.PMLK_F21;
  PMLK_F22 = PaPiMeLa.Keycodes.PMLK_F22;
  PMLK_F23 = PaPiMeLa.Keycodes.PMLK_F23;
  PMLK_F24 = PaPiMeLa.Keycodes.PMLK_F24;
  PMLK_EXECUTE = PaPiMeLa.Keycodes.PMLK_EXECUTE;
  PMLK_HELP = PaPiMeLa.Keycodes.PMLK_HELP;
  PMLK_MENU = PaPiMeLa.Keycodes.PMLK_MENU;
  PMLK_SELECT = PaPiMeLa.Keycodes.PMLK_SELECT;
  PMLK_STOP = PaPiMeLa.Keycodes.PMLK_STOP;
  PMLK_AGAIN = PaPiMeLa.Keycodes.PMLK_AGAIN;
  PMLK_UNDO = PaPiMeLa.Keycodes.PMLK_UNDO;
  PMLK_CUT = PaPiMeLa.Keycodes.PMLK_CUT;
  PMLK_COPY = PaPiMeLa.Keycodes.PMLK_COPY;
  PMLK_PASTE = PaPiMeLa.Keycodes.PMLK_PASTE;
  PMLK_FIND = PaPiMeLa.Keycodes.PMLK_FIND;
  PMLK_MUTE = PaPiMeLa.Keycodes.PMLK_MUTE;
  PMLK_VOLUMEUP = PaPiMeLa.Keycodes.PMLK_VOLUMEUP;
  PMLK_VOLUMEDOWN = PaPiMeLa.Keycodes.PMLK_VOLUMEDOWN;
  PMLK_KP_COMMA = PaPiMeLa.Keycodes.PMLK_KP_COMMA;
  PMLK_KP_EQUALSAS400 = PaPiMeLa.Keycodes.PMLK_KP_EQUALSAS400;
  PMLK_ALTERASE = PaPiMeLa.Keycodes.PMLK_ALTERASE;
  PMLK_SYSREQ = PaPiMeLa.Keycodes.PMLK_SYSREQ;
  PMLK_CANCEL = PaPiMeLa.Keycodes.PMLK_CANCEL;
  PMLK_CLEAR = PaPiMeLa.Keycodes.PMLK_CLEAR;
  PMLK_PRIOR = PaPiMeLa.Keycodes.PMLK_PRIOR;
  PMLK_RETURN2 = PaPiMeLa.Keycodes.PMLK_RETURN2;
  PMLK_SEPARATOR = PaPiMeLa.Keycodes.PMLK_SEPARATOR;
  PMLK_OUT = PaPiMeLa.Keycodes.PMLK_OUT;
  PMLK_OPER = PaPiMeLa.Keycodes.PMLK_OPER;
  PMLK_CLEARAGAIN = PaPiMeLa.Keycodes.PMLK_CLEARAGAIN;
  PMLK_CRSEL = PaPiMeLa.Keycodes.PMLK_CRSEL;
  PMLK_EXSEL = PaPiMeLa.Keycodes.PMLK_EXSEL;
  PMLK_FRONT = PaPiMeLa.Keycodes.PMLK_FRONT;
  PMLK_KP_00 = PaPiMeLa.Keycodes.PMLK_KP_00;
  PMLK_KP_000 = PaPiMeLa.Keycodes.PMLK_KP_000;
  PMLK_THOUSANDSSEPARATOR = PaPiMeLa.Keycodes.PMLK_THOUSANDSSEPARATOR;
  PMLK_DECIMALSEPARATOR = PaPiMeLa.Keycodes.PMLK_DECIMALSEPARATOR;
  PMLK_CURRENCYUNIT = PaPiMeLa.Keycodes.PMLK_CURRENCYUNIT;
  PMLK_CURRENCYSUBUNIT = PaPiMeLa.Keycodes.PMLK_CURRENCYSUBUNIT;
  PMLK_KP_LEFTPAREN = PaPiMeLa.Keycodes.PMLK_KP_LEFTPAREN;
  PMLK_KP_RIGHTPAREN = PaPiMeLa.Keycodes.PMLK_KP_RIGHTPAREN;
  PMLK_KP_LEFTBRACE = PaPiMeLa.Keycodes.PMLK_KP_LEFTBRACE;
  PMLK_KP_RIGHTBRACE = PaPiMeLa.Keycodes.PMLK_KP_RIGHTBRACE;
  PMLK_KP_TAB = PaPiMeLa.Keycodes.PMLK_KP_TAB;
  PMLK_KP_BACKSPACE = PaPiMeLa.Keycodes.PMLK_KP_BACKSPACE;
  PMLK_KP_A = PaPiMeLa.Keycodes.PMLK_KP_A;
  PMLK_KP_B = PaPiMeLa.Keycodes.PMLK_KP_B;
  PMLK_KP_C = PaPiMeLa.Keycodes.PMLK_KP_C;
  PMLK_KP_D = PaPiMeLa.Keycodes.PMLK_KP_D;
  PMLK_KP_E = PaPiMeLa.Keycodes.PMLK_KP_E;
  PMLK_KP_F = PaPiMeLa.Keycodes.PMLK_KP_F;
  PMLK_KP_XOR = PaPiMeLa.Keycodes.PMLK_KP_XOR;
  PMLK_KP_POWER = PaPiMeLa.Keycodes.PMLK_KP_POWER;
  PMLK_KP_PERCENT = PaPiMeLa.Keycodes.PMLK_KP_PERCENT;
  PMLK_KP_LESS = PaPiMeLa.Keycodes.PMLK_KP_LESS;
  PMLK_KP_GREATER = PaPiMeLa.Keycodes.PMLK_KP_GREATER;
  PMLK_KP_AMPERSAND = PaPiMeLa.Keycodes.PMLK_KP_AMPERSAND;
  PMLK_KP_DBLAMPERSAND = PaPiMeLa.Keycodes.PMLK_KP_DBLAMPERSAND;
  PMLK_KP_VERTICALBAR = PaPiMeLa.Keycodes.PMLK_KP_VERTICALBAR;
  PMLK_KP_DBLVERTICALBAR = PaPiMeLa.Keycodes.PMLK_KP_DBLVERTICALBAR;
  PMLK_KP_COLON = PaPiMeLa.Keycodes.PMLK_KP_COLON;
  PMLK_KP_HASH = PaPiMeLa.Keycodes.PMLK_KP_HASH;
  PMLK_KP_SPACE = PaPiMeLa.Keycodes.PMLK_KP_SPACE;
  PMLK_KP_AT = PaPiMeLa.Keycodes.PMLK_KP_AT;
  PMLK_KP_EXCLAM = PaPiMeLa.Keycodes.PMLK_KP_EXCLAM;
  PMLK_KP_MEMSTORE = PaPiMeLa.Keycodes.PMLK_KP_MEMSTORE;
  PMLK_KP_MEMRECALL = PaPiMeLa.Keycodes.PMLK_KP_MEMRECALL;
  PMLK_KP_MEMCLEAR = PaPiMeLa.Keycodes.PMLK_KP_MEMCLEAR;
  PMLK_KP_MEMADD = PaPiMeLa.Keycodes.PMLK_KP_MEMADD;
  PMLK_KP_MEMSUBTRACT = PaPiMeLa.Keycodes.PMLK_KP_MEMSUBTRACT;
  PMLK_KP_MEMMULTIPLY = PaPiMeLa.Keycodes.PMLK_KP_MEMMULTIPLY;
  PMLK_KP_MEMDIVIDE = PaPiMeLa.Keycodes.PMLK_KP_MEMDIVIDE;
  PMLK_KP_PLUSMINUS = PaPiMeLa.Keycodes.PMLK_KP_PLUSMINUS;
  PMLK_KP_CLEAR = PaPiMeLa.Keycodes.PMLK_KP_CLEAR;
  PMLK_KP_CLEARENTRY = PaPiMeLa.Keycodes.PMLK_KP_CLEARENTRY;
  PMLK_KP_BINARY = PaPiMeLa.Keycodes.PMLK_KP_BINARY;
  PMLK_KP_OCTAL = PaPiMeLa.Keycodes.PMLK_KP_OCTAL;
  PMLK_KP_DECIMAL = PaPiMeLa.Keycodes.PMLK_KP_DECIMAL;
  PMLK_KP_HEXADECIMAL = PaPiMeLa.Keycodes.PMLK_KP_HEXADECIMAL;
  PMLK_LCTRL = PaPiMeLa.Keycodes.PMLK_LCTRL;
  PMLK_LSHIFT = PaPiMeLa.Keycodes.PMLK_LSHIFT;
  PMLK_LALT = PaPiMeLa.Keycodes.PMLK_LALT;
  PMLK_LGUI = PaPiMeLa.Keycodes.PMLK_LGUI;
  PMLK_RCTRL = PaPiMeLa.Keycodes.PMLK_RCTRL;
  PMLK_RSHIFT = PaPiMeLa.Keycodes.PMLK_RSHIFT;
  PMLK_RALT = PaPiMeLa.Keycodes.PMLK_RALT;
  PMLK_RGUI = PaPiMeLa.Keycodes.PMLK_RGUI;
  PMLK_MODE = PaPiMeLa.Keycodes.PMLK_MODE;
  PMLK_SLEEP = PaPiMeLa.Keycodes.PMLK_SLEEP;
  PMLK_WAKE = PaPiMeLa.Keycodes.PMLK_WAKE;
  PMLK_CHANNEL_INCREMENT = PaPiMeLa.Keycodes.PMLK_CHANNEL_INCREMENT;
  PMLK_CHANNEL_DECREMENT = PaPiMeLa.Keycodes.PMLK_CHANNEL_DECREMENT;
  PMLK_MEDIA_PLAY = PaPiMeLa.Keycodes.PMLK_MEDIA_PLAY;
  PMLK_MEDIA_PAUSE = PaPiMeLa.Keycodes.PMLK_MEDIA_PAUSE;
  PMLK_MEDIA_RECORD = PaPiMeLa.Keycodes.PMLK_MEDIA_RECORD;
  PMLK_MEDIA_FAST_FORWARD = PaPiMeLa.Keycodes.PMLK_MEDIA_FAST_FORWARD;
  PMLK_MEDIA_REWIND = PaPiMeLa.Keycodes.PMLK_MEDIA_REWIND;
  PMLK_MEDIA_NEXT_TRACK = PaPiMeLa.Keycodes.PMLK_MEDIA_NEXT_TRACK;
  PMLK_MEDIA_PREVIOUS_TRACK = PaPiMeLa.Keycodes.PMLK_MEDIA_PREVIOUS_TRACK;
  PMLK_MEDIA_STOP = PaPiMeLa.Keycodes.PMLK_MEDIA_STOP;
  PMLK_MEDIA_EJECT = PaPiMeLa.Keycodes.PMLK_MEDIA_EJECT;
  PMLK_MEDIA_PLAY_PAUSE = PaPiMeLa.Keycodes.PMLK_MEDIA_PLAY_PAUSE;
  PMLK_MEDIA_SELECT = PaPiMeLa.Keycodes.PMLK_MEDIA_SELECT;
  PMLK_AC_NEW = PaPiMeLa.Keycodes.PMLK_AC_NEW;
  PMLK_AC_OPEN = PaPiMeLa.Keycodes.PMLK_AC_OPEN;
  PMLK_AC_CLOSE = PaPiMeLa.Keycodes.PMLK_AC_CLOSE;
  PMLK_AC_EXIT = PaPiMeLa.Keycodes.PMLK_AC_EXIT;
  PMLK_AC_SAVE = PaPiMeLa.Keycodes.PMLK_AC_SAVE;
  PMLK_AC_PRINT = PaPiMeLa.Keycodes.PMLK_AC_PRINT;
  PMLK_AC_PROPERTIES = PaPiMeLa.Keycodes.PMLK_AC_PROPERTIES;
  PMLK_AC_SEARCH = PaPiMeLa.Keycodes.PMLK_AC_SEARCH;
  PMLK_AC_HOME = PaPiMeLa.Keycodes.PMLK_AC_HOME;
  PMLK_AC_BACK = PaPiMeLa.Keycodes.PMLK_AC_BACK;
  PMLK_AC_FORWARD = PaPiMeLa.Keycodes.PMLK_AC_FORWARD;
  PMLK_AC_STOP = PaPiMeLa.Keycodes.PMLK_AC_STOP;
  PMLK_AC_REFRESH = PaPiMeLa.Keycodes.PMLK_AC_REFRESH;
  PMLK_AC_BOOKMARKS = PaPiMeLa.Keycodes.PMLK_AC_BOOKMARKS;
  PMLK_SOFTLEFT = PaPiMeLa.Keycodes.PMLK_SOFTLEFT;
  PMLK_SOFTRIGHT = PaPiMeLa.Keycodes.PMLK_SOFTRIGHT;
  PMLK_CALL = PaPiMeLa.Keycodes.PMLK_CALL;
  PMLK_ENDCALL = PaPiMeLa.Keycodes.PMLK_ENDCALL;
  PMLK_LEFT_TAB = PaPiMeLa.Keycodes.PMLK_LEFT_TAB;
  PMLK_LEVEL5_SHIFT = PaPiMeLa.Keycodes.PMLK_LEVEL5_SHIFT;
  PMLK_MULTI_KEY_COMPOSE = PaPiMeLa.Keycodes.PMLK_MULTI_KEY_COMPOSE;
  PMLK_LMETA = PaPiMeLa.Keycodes.PMLK_LMETA;
  PMLK_RMETA = PaPiMeLa.Keycodes.PMLK_RMETA;
  PMLK_LHYPER = PaPiMeLa.Keycodes.PMLK_LHYPER;
  PMLK_RHYPER = PaPiMeLa.Keycodes.PMLK_RHYPER;

// ---- PaPiMeLa.Pixels
type
  TPMLPixelFormat = PaPiMeLa.Pixels.TPMLPixelFormat;
  TPMLPixelType = PaPiMeLa.Pixels.TPMLPixelType;
  TPMLPackedOrder = PaPiMeLa.Pixels.TPMLPackedOrder;
  TPMLArrayOrder = PaPiMeLa.Pixels.TPMLArrayOrder;
  TPMLPackedLayout = PaPiMeLa.Pixels.TPMLPackedLayout;
  TPMLPixelFormatDetails = PaPiMeLa.Pixels.TPMLPixelFormatDetails;
  TPMLPalette = PaPiMeLa.Pixels.TPMLPalette;
const
  PML_PIXELFORMAT_UNKNOWN = PaPiMeLa.Pixels.PML_PIXELFORMAT_UNKNOWN;
  PML_PIXELFORMAT_INDEX1LSB = PaPiMeLa.Pixels.PML_PIXELFORMAT_INDEX1LSB;
  PML_PIXELFORMAT_INDEX1MSB = PaPiMeLa.Pixels.PML_PIXELFORMAT_INDEX1MSB;
  PML_PIXELFORMAT_INDEX2LSB = PaPiMeLa.Pixels.PML_PIXELFORMAT_INDEX2LSB;
  PML_PIXELFORMAT_INDEX2MSB = PaPiMeLa.Pixels.PML_PIXELFORMAT_INDEX2MSB;
  PML_PIXELFORMAT_INDEX4LSB = PaPiMeLa.Pixels.PML_PIXELFORMAT_INDEX4LSB;
  PML_PIXELFORMAT_INDEX4MSB = PaPiMeLa.Pixels.PML_PIXELFORMAT_INDEX4MSB;
  PML_PIXELFORMAT_INDEX8 = PaPiMeLa.Pixels.PML_PIXELFORMAT_INDEX8;
  PML_PIXELFORMAT_RGB332 = PaPiMeLa.Pixels.PML_PIXELFORMAT_RGB332;
  PML_PIXELFORMAT_XRGB4444 = PaPiMeLa.Pixels.PML_PIXELFORMAT_XRGB4444;
  PML_PIXELFORMAT_XBGR4444 = PaPiMeLa.Pixels.PML_PIXELFORMAT_XBGR4444;
  PML_PIXELFORMAT_XRGB1555 = PaPiMeLa.Pixels.PML_PIXELFORMAT_XRGB1555;
  PML_PIXELFORMAT_XBGR1555 = PaPiMeLa.Pixels.PML_PIXELFORMAT_XBGR1555;
  PML_PIXELFORMAT_ARGB4444 = PaPiMeLa.Pixels.PML_PIXELFORMAT_ARGB4444;
  PML_PIXELFORMAT_RGBA4444 = PaPiMeLa.Pixels.PML_PIXELFORMAT_RGBA4444;
  PML_PIXELFORMAT_ABGR4444 = PaPiMeLa.Pixels.PML_PIXELFORMAT_ABGR4444;
  PML_PIXELFORMAT_BGRA4444 = PaPiMeLa.Pixels.PML_PIXELFORMAT_BGRA4444;
  PML_PIXELFORMAT_ARGB1555 = PaPiMeLa.Pixels.PML_PIXELFORMAT_ARGB1555;
  PML_PIXELFORMAT_RGBA5551 = PaPiMeLa.Pixels.PML_PIXELFORMAT_RGBA5551;
  PML_PIXELFORMAT_ABGR1555 = PaPiMeLa.Pixels.PML_PIXELFORMAT_ABGR1555;
  PML_PIXELFORMAT_BGRA5551 = PaPiMeLa.Pixels.PML_PIXELFORMAT_BGRA5551;
  PML_PIXELFORMAT_RGB565 = PaPiMeLa.Pixels.PML_PIXELFORMAT_RGB565;
  PML_PIXELFORMAT_BGR565 = PaPiMeLa.Pixels.PML_PIXELFORMAT_BGR565;
  PML_PIXELFORMAT_RGB24 = PaPiMeLa.Pixels.PML_PIXELFORMAT_RGB24;
  PML_PIXELFORMAT_BGR24 = PaPiMeLa.Pixels.PML_PIXELFORMAT_BGR24;
  PML_PIXELFORMAT_XRGB8888 = PaPiMeLa.Pixels.PML_PIXELFORMAT_XRGB8888;
  PML_PIXELFORMAT_RGBX8888 = PaPiMeLa.Pixels.PML_PIXELFORMAT_RGBX8888;
  PML_PIXELFORMAT_XBGR8888 = PaPiMeLa.Pixels.PML_PIXELFORMAT_XBGR8888;
  PML_PIXELFORMAT_BGRX8888 = PaPiMeLa.Pixels.PML_PIXELFORMAT_BGRX8888;
  PML_PIXELFORMAT_ARGB8888 = PaPiMeLa.Pixels.PML_PIXELFORMAT_ARGB8888;
  PML_PIXELFORMAT_RGBA8888 = PaPiMeLa.Pixels.PML_PIXELFORMAT_RGBA8888;
  PML_PIXELFORMAT_ABGR8888 = PaPiMeLa.Pixels.PML_PIXELFORMAT_ABGR8888;
  PML_PIXELFORMAT_BGRA8888 = PaPiMeLa.Pixels.PML_PIXELFORMAT_BGRA8888;
  PML_PIXELFORMAT_XRGB2101010 = PaPiMeLa.Pixels.PML_PIXELFORMAT_XRGB2101010;
  PML_PIXELFORMAT_XBGR2101010 = PaPiMeLa.Pixels.PML_PIXELFORMAT_XBGR2101010;
  PML_PIXELFORMAT_ARGB2101010 = PaPiMeLa.Pixels.PML_PIXELFORMAT_ARGB2101010;
  PML_PIXELFORMAT_ABGR2101010 = PaPiMeLa.Pixels.PML_PIXELFORMAT_ABGR2101010;
  PML_PIXELFORMAT_RGB48 = PaPiMeLa.Pixels.PML_PIXELFORMAT_RGB48;
  PML_PIXELFORMAT_BGR48 = PaPiMeLa.Pixels.PML_PIXELFORMAT_BGR48;
  PML_PIXELFORMAT_RGBA64 = PaPiMeLa.Pixels.PML_PIXELFORMAT_RGBA64;
  PML_PIXELFORMAT_ARGB64 = PaPiMeLa.Pixels.PML_PIXELFORMAT_ARGB64;
  PML_PIXELFORMAT_BGRA64 = PaPiMeLa.Pixels.PML_PIXELFORMAT_BGRA64;
  PML_PIXELFORMAT_ABGR64 = PaPiMeLa.Pixels.PML_PIXELFORMAT_ABGR64;
  PML_PIXELFORMAT_RGB48_FLOAT = PaPiMeLa.Pixels.PML_PIXELFORMAT_RGB48_FLOAT;
  PML_PIXELFORMAT_BGR48_FLOAT = PaPiMeLa.Pixels.PML_PIXELFORMAT_BGR48_FLOAT;
  PML_PIXELFORMAT_RGBA64_FLOAT = PaPiMeLa.Pixels.PML_PIXELFORMAT_RGBA64_FLOAT;
  PML_PIXELFORMAT_ARGB64_FLOAT = PaPiMeLa.Pixels.PML_PIXELFORMAT_ARGB64_FLOAT;
  PML_PIXELFORMAT_BGRA64_FLOAT = PaPiMeLa.Pixels.PML_PIXELFORMAT_BGRA64_FLOAT;
  PML_PIXELFORMAT_ABGR64_FLOAT = PaPiMeLa.Pixels.PML_PIXELFORMAT_ABGR64_FLOAT;
  PML_PIXELFORMAT_RGB96_FLOAT = PaPiMeLa.Pixels.PML_PIXELFORMAT_RGB96_FLOAT;
  PML_PIXELFORMAT_BGR96_FLOAT = PaPiMeLa.Pixels.PML_PIXELFORMAT_BGR96_FLOAT;
  PML_PIXELFORMAT_RGBA128_FLOAT = PaPiMeLa.Pixels.PML_PIXELFORMAT_RGBA128_FLOAT;
  PML_PIXELFORMAT_ARGB128_FLOAT = PaPiMeLa.Pixels.PML_PIXELFORMAT_ARGB128_FLOAT;
  PML_PIXELFORMAT_BGRA128_FLOAT = PaPiMeLa.Pixels.PML_PIXELFORMAT_BGRA128_FLOAT;
  PML_PIXELFORMAT_ABGR128_FLOAT = PaPiMeLa.Pixels.PML_PIXELFORMAT_ABGR128_FLOAT;
  PML_PIXELFORMAT_YV12 = PaPiMeLa.Pixels.PML_PIXELFORMAT_YV12;
  PML_PIXELFORMAT_IYUV = PaPiMeLa.Pixels.PML_PIXELFORMAT_IYUV;
  PML_PIXELFORMAT_YUY2 = PaPiMeLa.Pixels.PML_PIXELFORMAT_YUY2;
  PML_PIXELFORMAT_UYVY = PaPiMeLa.Pixels.PML_PIXELFORMAT_UYVY;
  PML_PIXELFORMAT_YVYU = PaPiMeLa.Pixels.PML_PIXELFORMAT_YVYU;
  PML_PIXELFORMAT_NV12 = PaPiMeLa.Pixels.PML_PIXELFORMAT_NV12;
  PML_PIXELFORMAT_NV21 = PaPiMeLa.Pixels.PML_PIXELFORMAT_NV21;
  PML_PIXELFORMAT_I444 = PaPiMeLa.Pixels.PML_PIXELFORMAT_I444;
  PML_PIXELFORMAT_P010 = PaPiMeLa.Pixels.PML_PIXELFORMAT_P010;
  PML_PIXELFORMAT_I0FL = PaPiMeLa.Pixels.PML_PIXELFORMAT_I0FL;
  PML_PIXELFORMAT_I4FL = PaPiMeLa.Pixels.PML_PIXELFORMAT_I4FL;
  PML_PIXELFORMAT_EXTERNAL_OES = PaPiMeLa.Pixels.PML_PIXELFORMAT_EXTERNAL_OES;
  PML_PIXELFORMAT_MJPG = PaPiMeLa.Pixels.PML_PIXELFORMAT_MJPG;
  PML_PIXELFORMAT_RGBA32 = PaPiMeLa.Pixels.PML_PIXELFORMAT_RGBA32;
  PML_PIXELFORMAT_ARGB32 = PaPiMeLa.Pixels.PML_PIXELFORMAT_ARGB32;
  PML_PIXELFORMAT_BGRA32 = PaPiMeLa.Pixels.PML_PIXELFORMAT_BGRA32;
  PML_PIXELFORMAT_ABGR32 = PaPiMeLa.Pixels.PML_PIXELFORMAT_ABGR32;
  PML_PIXELFORMAT_RGBX32 = PaPiMeLa.Pixels.PML_PIXELFORMAT_RGBX32;
  PML_PIXELFORMAT_XRGB32 = PaPiMeLa.Pixels.PML_PIXELFORMAT_XRGB32;
  PML_PIXELFORMAT_BGRX32 = PaPiMeLa.Pixels.PML_PIXELFORMAT_BGRX32;
  PML_PIXELFORMAT_XBGR32 = PaPiMeLa.Pixels.PML_PIXELFORMAT_XBGR32;
function PMLPixelFlag(AFormat: TPMLPixelFormat): LongWord; inline;
function PMLPixelType(AFormat: TPMLPixelFormat): TPMLPixelType; inline;
function PMLPixelOrder(AFormat: TPMLPixelFormat): LongWord; inline;
function PMLPixelLayout(AFormat: TPMLPixelFormat): TPMLPackedLayout; inline;
function PMLBitsPerPixel(AFormat: TPMLPixelFormat): Integer; inline;
function PMLBytesPerPixel(AFormat: TPMLPixelFormat): Integer; inline;
function PMLIsPixelFormatIndexed(AFormat: TPMLPixelFormat): Boolean; inline;
function PMLIsPixelFormatPacked(AFormat: TPMLPixelFormat): Boolean; inline;
function PMLIsPixelFormatArray(AFormat: TPMLPixelFormat): Boolean; inline;
function PMLIsPixelFormatAlpha(AFormat: TPMLPixelFormat): Boolean; inline;
function PMLIsPixelFormatFourCC(AFormat: TPMLPixelFormat): Boolean; inline;
function PMLIsPixelFormatFloat(AFormat: TPMLPixelFormat): Boolean; inline;
function PMLIsPixelFormat10Bit(AFormat: TPMLPixelFormat): Boolean; inline;
function PMLPixelFormatName(AFormat: TPMLPixelFormat): String; inline;
function PMLGetPixelFormatDetails(
  AFormat: TPMLPixelFormat;
  out ADetails: TPMLPixelFormatDetails): Boolean; inline;
function PMLGetPixelFormatForMasks(
  ABitsPerPixel: Integer;
  ARMask, AGMask, ABMask, AAMask: LongWord): TPMLPixelFormat; inline;
function PMLMapRGB(
  const ADetails: TPMLPixelFormatDetails;
  APalette: TPMLPalette;
  AR, AG, AB: Byte): LongWord; inline;
function PMLMapRGBA(
  const ADetails: TPMLPixelFormatDetails;
  APalette: TPMLPalette;
  AR, AG, AB, AA: Byte): LongWord; inline;
function PMLMapColor(
  const ADetails: TPMLPixelFormatDetails;
  APalette: TPMLPalette;
  const AColor: TPMLColor): LongWord; inline;
procedure PMLGetRGB(
  APixel: LongWord;
  const ADetails: TPMLPixelFormatDetails;
  APalette: TPMLPalette;
  out AR, AG, AB: Byte); inline;
procedure PMLGetRGBA(
  APixel: LongWord;
  const ADetails: TPMLPixelFormatDetails;
  APalette: TPMLPalette;
  out AR, AG, AB, AA: Byte); inline;
function PMLGetColor(
  APixel: LongWord;
  const ADetails: TPMLPixelFormatDetails;
  APalette: TPMLPalette): TPMLColor; inline;

// ---- PaPiMeLa.Surface
type
  IPMLSurface = PaPiMeLa.Surface.IPMLSurface;
  TPMLFlipMode = PaPiMeLa.Surface.TPMLFlipMode;
  TPMLSurface = PaPiMeLa.Surface.TPMLSurface;
function PMLPitchFor(AWidth: Integer; AFormat: TPMLPixelFormat): Integer; inline;

// ---- PaPiMeLa.Surface.Blit
function PMLBlit(
  ASrc: TPMLSurface;
  const ASrcRect: TPMLRect;
  ADst: TPMLSurface;
  const ADstRect: TPMLRect): Boolean; inline;
function PMLBlitScaled(
  ASrc: TPMLSurface;
  const ASrcRect: TPMLRect;
  ADst: TPMLSurface;
  const ADstRect: TPMLRect;
  AMode: TPMLScaleMode = TPMLScaleMode.Nearest): Boolean; inline;
function PMLFillRect(
  ADst: TPMLSurface;
  const ARect: TPMLRect;
  const AColor: TPMLColor): Boolean; inline;
function PMLBlendColor(const ASrc, ADst: TPMLColor; AMode: TPMLBlendMode): TPMLColor; inline;

// ---- PaPiMeLa.Surface.BMP
function PMLLoadBMP(AStream: TStream): TPMLSurface; inline;
function PMLLoadBMPFile(const APath: String): TPMLSurface; inline;
procedure PMLSaveBMP(AStream: TStream; ASurface: TPMLSurface); inline;
procedure PMLSaveBMPFile(const APath: String; ASurface: TPMLSurface); inline;

// ---- PaPiMeLa.IO
type
  TPMLFileMode = PaPiMeLa.IO.TPMLFileMode;
  TPMLFileStream = PaPiMeLa.IO.TPMLFileStream;
  TPMLMemoryStream = PaPiMeLa.IO.TPMLMemoryStream;
function PMLReadU8(AStream: TStream): Byte; inline;
function PMLReadU16LE(AStream: TStream): Word; inline;
function PMLReadU32LE(AStream: TStream): LongWord; inline;
function PMLReadU16BE(AStream: TStream): Word; inline;
function PMLReadU32BE(AStream: TStream): LongWord; inline;
function PMLReadS16LE(AStream: TStream): SmallInt; inline;
function PMLReadS32LE(AStream: TStream): LongInt; inline;
procedure PMLWriteU8(AStream: TStream; AValue: Byte); inline;
procedure PMLWriteU16LE(AStream: TStream; AValue: Word); inline;
procedure PMLWriteU32LE(AStream: TStream; AValue: LongWord); inline;
procedure PMLWriteU16BE(AStream: TStream; AValue: Word); inline;
procedure PMLWriteU32BE(AStream: TStream; AValue: LongWord); inline;
procedure PMLReadExactly(AStream: TStream; var ABuffer; ACount: LongInt); inline;
procedure PMLWriteExactly(AStream: TStream; const ABuffer; ACount: LongInt); inline;
function PMLReadAll(AStream: TStream): TBytes; inline;
function PMLLoadFile(const APath: String): TBytes; inline;
procedure PMLSaveFile(const APath: String; const AData: TBytes); inline;
function PMLLoadTextFile(const APath: String): String; inline;

// ---- PaPiMeLa.Video
type
  IPMLWindowDependent = PaPiMeLa.Video.IPMLWindowDependent;
  TPMLWindowOptions = PaPiMeLa.Video.TPMLWindowOptions;
  TPMLDisplay = PaPiMeLa.Video.TPMLDisplay;
  TPMLWindow = PaPiMeLa.Video.TPMLWindow;
  TPMLGLContext = PaPiMeLa.Video.TPMLGLContext;
  TPMLCursorSystem = PaPiMeLa.Video.TPMLCursorSystem;
  TPMLWindowList = PaPiMeLa.Video.TPMLWindowList;
  TPMLDisplayList = PaPiMeLa.Video.TPMLDisplayList;
  TPMLVideoSystem = PaPiMeLa.Video.TPMLVideoSystem;

// ---- PaPiMeLa.Clipboard
type
  TPMLClipboardSelection = PaPiMeLa.Clipboard.TPMLClipboardSelection;
  IPMLClipboardDataProvider = PaPiMeLa.Clipboard.IPMLClipboardDataProvider;
  TPMLDragOptions = PaPiMeLa.Clipboard.TPMLDragOptions;
  TPMLTextClipboardProvider = PaPiMeLa.Clipboard.TPMLTextClipboardProvider;
  TPMLSelectionState = PaPiMeLa.Clipboard.TPMLSelectionState;
  TPMLClipboard = PaPiMeLa.Clipboard.TPMLClipboard;

// ---- PaPiMeLa.Render
type
  TPMLVertex = PaPiMeLa.Render.TPMLVertex;
  TPMLVertices = PaPiMeLa.Render.TPMLVertices;
  TPMLIndices = PaPiMeLa.Render.TPMLIndices;
  TPMLRenderCommandKind = PaPiMeLa.Render.TPMLRenderCommandKind;
  TPMLRenderCommand = PaPiMeLa.Render.TPMLRenderCommand;
  TPMLRenderCommands = PaPiMeLa.Render.TPMLRenderCommands;
  TPMLRenderQueue = PaPiMeLa.Render.TPMLRenderQueue;
  TPMLRenderDriver = PaPiMeLa.Render.TPMLRenderDriver;
  TPMLTextureAccess = PaPiMeLa.Render.TPMLTextureAccess;
  TPMLLogicalPresentation = PaPiMeLa.Render.TPMLLogicalPresentation;
  TPMLFlip = PaPiMeLa.Render.TPMLFlip;
  TPMLFlips = PaPiMeLa.Render.TPMLFlips;
  TPMLRenderViewState = PaPiMeLa.Render.TPMLRenderViewState;
  TPMLTexture = PaPiMeLa.Render.TPMLTexture;
  TPMLTextures = PaPiMeLa.Render.TPMLTextures;
  TPMLRenderer = PaPiMeLa.Render.TPMLRenderer;
  TPMLRenderDriverFactory = PaPiMeLa.Render.TPMLRenderDriverFactory;
  TPMLRenderDriverPrefers = PaPiMeLa.Render.TPMLRenderDriverPrefers;
const
  PML_DEBUG_TEXT_FONT_CHARACTER_SIZE = PaPiMeLa.Render.PML_DEBUG_TEXT_FONT_CHARACTER_SIZE;
function PMLSameDrawState(const A, B: TPMLRenderCommand): Boolean; inline;
function PMLRenderDriverNames: TStringArray; inline;

// ---- PaPiMeLa.TextInput
type
  TPMLTextInputCapability = PaPiMeLa.TextInput.TPMLTextInputCapability;
  TPMLTextInputCapabilities = PaPiMeLa.TextInput.TPMLTextInputCapabilities;
  TPMLTextInputType = PaPiMeLa.TextInput.TPMLTextInputType;
  TPMLTextInputHint = PaPiMeLa.TextInput.TPMLTextInputHint;
  TPMLTextInputHints = PaPiMeLa.TextInput.TPMLTextInputHints;
  IPMLTextInputClient = PaPiMeLa.TextInput.IPMLTextInputClient;
  IPMLTextInputSink = PaPiMeLa.TextInput.IPMLTextInputSink;
  IPMLTextInputBackend = PaPiMeLa.TextInput.IPMLTextInputBackend;
  TPMLTextInputSession = PaPiMeLa.TextInput.TPMLTextInputSession;
  TPMLTextInputSystem = PaPiMeLa.TextInput.TPMLTextInputSystem;
const
  PML_IME_KEY_TIMEOUT_NS = PaPiMeLa.TextInput.PML_IME_KEY_TIMEOUT_NS;

// ---- PaPiMeLa.Time
type
  TPMLNowFunc = PaPiMeLa.Time.TPMLNowFunc;
  TPMLSleepProc = PaPiMeLa.Time.TPMLSleepProc;
  TPMLPauseProc = PaPiMeLa.Time.TPMLPauseProc;
  TPMLTimerID = PaPiMeLa.Time.TPMLTimerID;
  TPMLTimerCallback = PaPiMeLa.Time.TPMLTimerCallback;
  TPMLTimerCallbackNS = PaPiMeLa.Time.TPMLTimerCallbackNS;
  TPMLTimerQueue = PaPiMeLa.Time.TPMLTimerQueue;
const
  PML_NS_PER_MS = PaPiMeLa.Time.PML_NS_PER_MS;
  PML_NS_PER_SECOND = PaPiMeLa.Time.PML_NS_PER_SECOND;
procedure PMLDelay(AMs: LongWord); inline;
procedure PMLDelayNS(ANs: UInt64); inline;
procedure PMLDelayPrecise(ANs: UInt64); inline;
procedure PMLDelayPreciseWith(
  ANs: UInt64;
  ANow: TPMLNowFunc;
  ASleep: TPMLSleepProc;
  APause: TPMLPauseProc); inline;

// ---- PaPiMeLa.Atomic
type
  TPMLAtomicInt = PaPiMeLa.Atomic.TPMLAtomicInt;
  TPMLAtomicU32 = PaPiMeLa.Atomic.TPMLAtomicU32;
  TPMLAtomicPointer = PaPiMeLa.Atomic.TPMLAtomicPointer;
  TPMLSpinLock = PaPiMeLa.Atomic.TPMLSpinLock;
  TPMLInitStatus = PaPiMeLa.Atomic.TPMLInitStatus;
  TPMLInitState = PaPiMeLa.Atomic.TPMLInitState;
procedure PMLMemoryBarrierRelease; inline;
procedure PMLMemoryBarrierAcquire; inline;
procedure PMLCPUPause; inline;

// ---- PaPiMeLa.Threading
type
  TPMLPthreadStorage = PaPiMeLa.Threading.TPMLPthreadStorage;
  TPMLMutex = PaPiMeLa.Threading.TPMLMutex;
  TPMLRWLock = PaPiMeLa.Threading.TPMLRWLock;
  TPMLSemaphore = PaPiMeLa.Threading.TPMLSemaphore;
  TPMLCondition = PaPiMeLa.Threading.TPMLCondition;
  TPMLLockGuard = PaPiMeLa.Threading.TPMLLockGuard;
  TPMLThreadPriority = PaPiMeLa.Threading.TPMLThreadPriority;
  TPMLThreadFunc = PaPiMeLa.Threading.TPMLThreadFunc;
  TPMLThread = PaPiMeLa.Threading.TPMLThread;

// ---- PaPiMeLa.Properties
type
  TPMLPropertyType = PaPiMeLa.Properties.TPMLPropertyType;
  TPMLPropertyCleanup = PaPiMeLa.Properties.TPMLPropertyCleanup;
  TPMLPropertyEnumerator = PaPiMeLa.Properties.TPMLPropertyEnumerator;
  TPMLProperties = PaPiMeLa.Properties.TPMLProperties;
  TPMLHintPriority = PaPiMeLa.Properties.TPMLHintPriority;
  TPMLHintValue = PaPiMeLa.Properties.TPMLHintValue;
  TPMLHintSetting = PaPiMeLa.Properties.TPMLHintSetting;
  TPMLHintSettings = PaPiMeLa.Properties.TPMLHintSettings;
  TPMLHintCallback = PaPiMeLa.Properties.TPMLHintCallback;
  TPMLHints = PaPiMeLa.Properties.TPMLHints;
const
  PML_HINT_LOGGING = PaPiMeLa.Properties.PML_HINT_LOGGING;
  PML_HINT_VIDEO = PaPiMeLa.Properties.PML_HINT_VIDEO;
  PML_HINT_IME = PaPiMeLa.Properties.PML_HINT_IME;
function PMLStringBoolean(const AValue: String; ADefault: Boolean): Boolean; inline;
function PMLStringInteger(const AValue: String; ADefault: Integer): Integer; inline;
function PMLStrToInt64C(const AValue: String): Int64; inline;
function PMLStrToFloatC(const AValue: String): Double; inline;

// ---- PaPiMeLa.Log
type
  TPMLLogPriority = PaPiMeLa.Log.TPMLLogPriority;
  TPMLLogOutput = PaPiMeLa.Log.TPMLLogOutput;
  TPMLLog = PaPiMeLa.Log.TPMLLog;
const
  PML_LOG_CATEGORY_APPLICATION = PaPiMeLa.Log.PML_LOG_CATEGORY_APPLICATION;
  PML_LOG_CATEGORY_ERROR = PaPiMeLa.Log.PML_LOG_CATEGORY_ERROR;
  PML_LOG_CATEGORY_ASSERT = PaPiMeLa.Log.PML_LOG_CATEGORY_ASSERT;
  PML_LOG_CATEGORY_SYSTEM = PaPiMeLa.Log.PML_LOG_CATEGORY_SYSTEM;
  PML_LOG_CATEGORY_AUDIO = PaPiMeLa.Log.PML_LOG_CATEGORY_AUDIO;
  PML_LOG_CATEGORY_VIDEO = PaPiMeLa.Log.PML_LOG_CATEGORY_VIDEO;
  PML_LOG_CATEGORY_RENDER = PaPiMeLa.Log.PML_LOG_CATEGORY_RENDER;
  PML_LOG_CATEGORY_INPUT = PaPiMeLa.Log.PML_LOG_CATEGORY_INPUT;
  PML_LOG_CATEGORY_TEST = PaPiMeLa.Log.PML_LOG_CATEGORY_TEST;
  PML_LOG_CATEGORY_GPU = PaPiMeLa.Log.PML_LOG_CATEGORY_GPU;
  PML_LOG_CATEGORY_CUSTOM = PaPiMeLa.Log.PML_LOG_CATEGORY_CUSTOM;

// ---- PaPiMeLa.App
type
  TPMLAppResult = PaPiMeLa.App.TPMLAppResult;
  TPMLApplicationClass = PaPiMeLa.App.TPMLApplicationClass;
  TPMLApplication = PaPiMeLa.App.TPMLApplication;

// ---- PaPiMeLa.Video.Backend
function PMLVideoBackendNames: TStringArray; inline;

// ---- PaPiMeLa.TextInput.Backend
function PMLTextInputBackendNames: TStringArray; inline;

