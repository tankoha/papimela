{
  PaPiMeLa.Errors — 例外階層

  Origin : original work (clean-room design; not derived from SDL sources)
  Design : docs/DESIGN.md §5

  WHAT:
    エラーはすべて例外で表す。SDL の「false を返してスレッドローカルの
    エラー文字列を置く」方式は採らない。

  WHY:
    呼び出し側がエラーチェックを書き忘れても黙って進まないため。
    SDL_GetError 相当は移植しない。

  RESOLVED:
    - 1 サブシステム = 1 例外クラス。関数単位の例外クラスは作らない
    - Subsystem は各派生クラスの SubsystemOf クラス関数が返す
    - Message の書式は '[<BackendName>] <説明>: <ネイティブ説明>'

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Errors;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types;

type
  EPMLError = class(Exception)
  strict private
    FSubsystem  : TPMLSubsystemTag;
    FBackendName: String;
    FNativeCode : Int64;
  protected
    // 派生クラスが自分の所属を返す。既定は Core。
    class function SubsystemOf: TPMLSubsystemTag; virtual;
  public
    constructor Create(const AMsg: String);
    constructor CreateFmt(const AFmt: String; const AArgs: array of const);
    constructor CreateNative(const AMsg: String; ANativeCode: Int64;
      const ABackend: String = ''; const ANativeDesc: String = '');
    property Subsystem  : TPMLSubsystemTag read FSubsystem;
    property BackendName: String read FBackendName;
    property NativeCode : Int64 read FNativeCode;
  end;

  EPMLInitError = class(EPMLError);

  EPMLVideoError = class(EPMLError)
  protected
    class function SubsystemOf: TPMLSubsystemTag; override;
  end;

  EPMLRenderError = class(EPMLError)
  protected
    class function SubsystemOf: TPMLSubsystemTag; override;
  end;

  EPMLAudioError = class(EPMLError)
  protected
    class function SubsystemOf: TPMLSubsystemTag; override;
  end;

  EPMLInputError = class(EPMLError)
  protected
    class function SubsystemOf: TPMLSubsystemTag; override;
  end;

  EPMLTextInputError = class(EPMLError)
  protected
    class function SubsystemOf: TPMLSubsystemTag; override;
  end;

  EPMLIOError = class(EPMLError)
  protected
    class function SubsystemOf: TPMLSubsystemTag; override;
  end;

  EPMLThreadError = class(EPMLError)
  protected
    class function SubsystemOf: TPMLSubsystemTag; override;
  end;

  EPMLEventError = class(EPMLError)
  protected
    class function SubsystemOf: TPMLSubsystemTag; override;
  end;

  // 状態系（Error 接尾辞なし）
  EPMLUnsupported     = class(EPMLError);
  EPMLArgument        = class(EPMLError);
  EPMLThreadAffinity  = class(EPMLError);
  EPMLBackendLost     = class(EPMLError);
  EPMLPlatformLibrary = class(EPMLInitError)
  protected
    class function SubsystemOf: TPMLSubsystemTag; override;
  end;

implementation

function ComposeMessage(const ABackend, AMsg, ANativeDesc: String): String;
begin
  Result := AMsg;
  if ANativeDesc <> '' then
    Result := Result + ': ' + ANativeDesc;
  if ABackend <> '' then
    Result := '[' + ABackend + '] ' + Result;
end;

class function EPMLError.SubsystemOf: TPMLSubsystemTag;
begin
  Result := TPMLSubsystemTag.Core;
end;

constructor EPMLError.Create(const AMsg: String);
begin
  inherited Create(AMsg);
  FSubsystem := SubsystemOf;
  FBackendName := '';
  FNativeCode := 0;
end;

constructor EPMLError.CreateFmt(const AFmt: String; const AArgs: array of const);
begin
  Create(Format(AFmt, AArgs));
end;

constructor EPMLError.CreateNative(const AMsg: String; ANativeCode: Int64;
  const ABackend: String; const ANativeDesc: String);
begin
  inherited Create(ComposeMessage(ABackend, AMsg, ANativeDesc));
  FSubsystem := SubsystemOf;
  FBackendName := ABackend;
  FNativeCode := ANativeCode;
end;

class function EPMLVideoError.SubsystemOf: TPMLSubsystemTag;
begin
  Result := TPMLSubsystemTag.Video;
end;

class function EPMLRenderError.SubsystemOf: TPMLSubsystemTag;
begin
  Result := TPMLSubsystemTag.Render;
end;

class function EPMLAudioError.SubsystemOf: TPMLSubsystemTag;
begin
  Result := TPMLSubsystemTag.Audio;
end;

class function EPMLInputError.SubsystemOf: TPMLSubsystemTag;
begin
  Result := TPMLSubsystemTag.Input;
end;

class function EPMLTextInputError.SubsystemOf: TPMLSubsystemTag;
begin
  Result := TPMLSubsystemTag.TextInput;
end;

class function EPMLIOError.SubsystemOf: TPMLSubsystemTag;
begin
  Result := TPMLSubsystemTag.IO;
end;

class function EPMLThreadError.SubsystemOf: TPMLSubsystemTag;
begin
  Result := TPMLSubsystemTag.Threading;
end;

class function EPMLEventError.SubsystemOf: TPMLSubsystemTag;
begin
  Result := TPMLSubsystemTag.Events;
end;

class function EPMLPlatformLibrary.SubsystemOf: TPMLSubsystemTag;
begin
  Result := TPMLSubsystemTag.Platform;
end;

end.
