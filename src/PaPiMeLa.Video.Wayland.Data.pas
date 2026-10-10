{
  PaPiMeLa.Video.Wayland.Data — クリップボード、プライマリ選択、ドラッグ＆ドロップ（受信と開始）
  （wl_data_device / primary selection）

  Origin : ported from SDL (src/video/wayland/SDL_waylanddatamanager.c,
           src/video/wayland/SDL_waylandclipboard.c)
           Scope: パイプでの送受信（全部書く、SIGPIPE を捨てる、タイムアウト付きで読む）、
           オファーの MIME 一覧、選択を置くときの serial の扱い、テキストの MIME タイプ 5 種。
           SDL_waylandevents.c のデータデバイス / プライマリ選択デバイスのリスナー
           （data_offer、selection、ドラッグ＆ドロップの enter / leave / motion / drop と、
           drop の document-portal の枝）も含む。
           ドラッグを始める側（StartDrag。wl_data_source の send / action / dnd_drop_performed /
           dnd_finished / cancelled と start_drag、絵のサーフェス）は SDL に無く、papimela が
           wl_data_device の仕様から書いた。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §3.2（TPMLWaylandDataManager）、§11 #38

  WHAT:
    TPMLClipboardBackend の Wayland 実装（TPMLWaylandClipboard）。最初のシートの
    wl_data_device と zwp_primary_selection_device_v1 を使い、選択を置く・他のアプリの
    選択を読む。データそのものは持たず、置いたデータは公開層から借りた提供者から、
    他のアプリのデータは相手からパイプで読む。
    同じデータデバイスで、他のアプリからのドラッグ＆ドロップ（ファイルとテキスト）を受け、
    Context.Events.Drop（TPMLDropState）へ流す。

  WHY:
    SDL はシートごとのデータデバイスを持ち、データを SDL_clipboard.c の内部に置く。
    papimela はシートを 1 つとして扱い（§6）、データの持ち主は公開層（TPMLClipboard）
    なので、この部品は Wayland のオブジェクトの管理とパイプの出入りだけを引き受ける。

  RESOLVED:
    - 自分の選択の折り返し（echo）は、置いたソースだけが持つ印の MIME タイプで見分ける。
      印は MIME の名前に pid・起動ごとの値・連番を入れる（SDL は印の中身をパイプで
      読んで比べるので 1 往復余計に要る。名前に入れれば、オファーの MIME 一覧を見るだけで
      同期的に決まる）。印は公開する MIME 一覧からも、sink へ渡す一覧からも除く
    - echo と見なすのは、印が「いま生きているソース」か「自分で手放したソース」のもの。
      置き換えを続けたとき、1 つ前の echo が後から届いても他のアプリと取り違えない。
      他のアプリに取られて cancelled を受けたソースの印は覚えない（そのソースの echo は
      cancelled より前に届いているので、あとから同じ印のオファーが来たら、それは
      クリップボードマネージャによる再公開であり、他のアプリのもの）
    - 置いた直後は、自分の echo が届くまで、他のアプリのオファーを「置く前の選択の通知が
      追い越してきただけ」かもしれないものとして扱い、所有権を手放さず通知もしない。
      cancelled が来たらそれが本物だったと分かるので、そこで通知する
    - 黙って断られた set_selection（serial が古いと、コンポジタは知らせずに無視する。
      wl-copy が置いたあとに入力無しで置き直すと起きる。labwc で実測）は、置いた直後に送る
      wl_display.sync の返事で見分ける。コンポジタは要求を順に処理するので、受け入れて
      いてキーボードフォーカスがあれば echo は done より前に届く。届いていなければ断られた:
      印を覚えずにソースを捨て、ClipboardOwnershipLost を呼び、置く前から見えていた
      他のアプリのオファーを（そのまま有効なので）ClipboardOffered で知らせ直す。
      置く前のオファーは、echo が届くまで捨てずに持っておく（断られたら読み続けるため）
    - serial は PaPiMeLa.Video.Wayland.Seat が覚えた直近の入力の serial。まだ無ければ
      選択を保留にして、最初の serial が来たときに置く（SDL と同じ）
    - 受け取りはタイムアウト付き（1 回の待ちが 5 秒、全体で 60 秒）。送りは待ちが
      1 回 2 秒。どちらも主スレッドで同期的に行う
    - 送りの最中に相手が読むのをやめても SIGPIPE で落ちない（スレッドのマスクで
      止め、溜まった分を捨ててから戻す）
    - ドラッグ＆ドロップの受信（SDL_waylandevents.c の data_device_handle_enter / leave /
      motion / drop）:
        - enter: ウィンドウが DropFile か DropText を受ける設定で、オファーが text/uri-list
          （無ければ TextMimeTypes の最初に合うもの）を持つなら、accept と
          set_actions(copy)（バージョン 3 から）を送り、最初の位置を DropPosition にする。
          持たなければ accept(NULL) と set_actions(none) で断る
        - motion: DropPosition。座標はサーフェスの座標のまま（ポインタと同じ。拡大率は掛けない）
        - drop: パイプで受け取り（クリップボードと同じ待ち）、DropFile（ローカルのパスごと）か
          DropText（行ごと）を積み、DropComplete を積む。操作が来ていれば finish（バージョン 3
          から）を送り、オファーを捨てる
        - leave: ドロップ前に出ていったなら DropComplete を積み、オファーを捨てる
          （SDL と同じ）。drop のあとの leave は何もしない
    - document-portal の枝（SDL_waylandevents.c の drop の FILE_PORTAL_MIME）:
        - enter: オファーが application/vnd.portal.filetransfer を持てばファイルのドロップとして
          受ける。text/uri-list もあればそれを accept し、無ければポータルの MIME タイプを accept する
        - drop: ポータルの MIME タイプがあれば鍵を受け取り、Documents ポータル
          （PaPiMeLa.Platform.DocumentPortal）で開いたパスごとに DropFile を積む。開けなければ
          text/uri-list へ戻る（ディレクトリを含むときなど。SDL と同じ）
    - ドラッグを始める側（StartDrag）:
        - 始める条件: データデバイスがあり、そのウィンドウにポインタのフォーカスがあってボタンが
          押されていること（Seat.ImplicitGrab。押下の serial を start_drag に使う）。無ければ False
        - wl_data_source に MIME タイプと自分のドラッグだと見分ける印の MIME タイプを並べ、
          操作（Copy = 1、Move = 2、Ask = 4）を set_actions で伝える（バージョン 3 から）
        - 絵は ARGB8888 のバッファ（アルファを掛けた形）。ポインタの先が絵の (HotX, HotY) に
          来るよう、原点を (-HotX, -HotY) へずらす。詳しくは StartDrag の前のコメント
        - send は提供者から読んで書く（クリップボードと同じ書き込み）。dnd_finished で
          DragEnded(True, 最後の action)、cancelled で DragEnded(False, Copy)
        - CancelDrag はソースを捨てて DragEnded(False, Copy) を同期的に呼ぶ
        - 自分のウィンドウへ落ちたとき（オファーに自分のドラッグの印がある）は、パイプを
          通さず提供者から直接読む（自分の書き込みを自分で待って止まるのを避ける）。印の MIME
          タイプは受け取る MIME タイプに選ばない

  NOT RESOLVED:
    - ドラッグを始める側は、実際の操作でのコンポジタとの受け渡し（絵の位置、dnd_finished の
      時機）を実機で確かめていない。タッチからのドラッグは始められない。data_source が
      バージョン 3 未満のコンポジタでは終わりの知らせが無いので、最初の send を書き終えた
      時点で終わりとみなす（詳しくは StartDrag の前のコメント）
    - 受信は受け入れる操作が Copy だけ。Move だけを許すドラッグ元には落とせない（SDL と同じ）
    - ドロップを受けるかは DropFile / DropText が有効かだけで決まる。SDL の
      accepts_drag_and_drop のようなウィンドウごとの切り替えは無い
    - 受信は主スレッドを止めて読む（相手が書かないと最大 5 秒）。SDL と同じ
    - シートは最初の 1 つだけ（SDL は最後に入力を受けたシートを選ぶ）
    - フォーカスが無いときに黙って断られた set_selection は見分けられない（コンポジタは
      フォーカスの無いクライアントに echo を送らないので、sync の時点では断られたのか
      受け入れられたのか分からない）。そのときは待ちを終えるだけで、置く前のオファーは
      捨てる。次にフォーカスが入ったとき届く現在の選択（echo か他のアプリのオファー）に
      通常の規則が働き、断られていれば所有権を手放す。それまで IsOwner は True のまま。
      断られる仕組み（データコントロール経由の選択の serial がこちらの最後の入力の
      serial より新しい）は推測で、未確認
    - 巨大なデータの送りは送り終わるまで主スレッドを止める（相手が読む限り）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Video.Wayland.Data;

{$I papimela.inc}

interface

uses
  SysUtils, BaseUnix, ctypes,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Events,
  PaPiMeLa.Events.Drop,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video.Wayland.Types,
  PaPiMeLa.Video.Wayland.Seat,
  PaPiMeLa.Video.Wayland.Shm,
  PaPiMeLa.Platform.DocumentPortal,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland,
  PaPiMeLa.Platform.Wayland.Protocols.WpPrimarySelectionUnstableV1;

type
  TPMLWaylandClipboard = class;
  TPMLWaylandOffer = class;
  TPMLWaylandSource = class;

  { ---- 転送クラス（生成リスナーは抽象クラスなので 1 クラス 1 リスナー） ---- }

  TPMLWaylandDataOfferFwd = class(Twl_data_offer_listener)
  strict private
    FOffer: TPMLWaylandOffer;
  public
    constructor Create(AOffer: TPMLWaylandOffer);
    procedure offer(AProxy: Pwl_data_offer; mime_type: PAnsiChar); override;
    // ドラッグ＆ドロップで、コンポジタが選んだ操作（copy / move / none）。
    procedure action(AProxy: Pwl_data_offer; dnd_action: LongWord); override;
    // source_actions は使わない（SDL も見ない。こちらは copy だけを受け付ける）。
  end;

  TPMLWaylandPrimaryOfferFwd = class(Tzwp_primary_selection_offer_v1_listener)
  strict private
    FOffer: TPMLWaylandOffer;
  public
    constructor Create(AOffer: TPMLWaylandOffer);
    procedure offer(AProxy: Pzwp_primary_selection_offer_v1; mime_type: PAnsiChar); override;
  end;

  TPMLWaylandDataSourceFwd = class(Twl_data_source_listener)
  strict private
    FSource: TPMLWaylandSource;
  public
    constructor Create(ASource: TPMLWaylandSource);
    procedure send(AProxy: Pwl_data_source; mime_type: PAnsiChar; fd: LongInt); override;
    procedure cancelled(AProxy: Pwl_data_source); override;
    // ドラッグ＆ドロップ（こちらが始めたドラッグ）。target は使わない（既定の空実装）。
    procedure dnd_drop_performed(AProxy: Pwl_data_source); override;
    procedure dnd_finished(AProxy: Pwl_data_source); override;
    procedure action(AProxy: Pwl_data_source; dnd_action: LongWord); override;
  end;

  TPMLWaylandPrimarySourceFwd = class(Tzwp_primary_selection_source_v1_listener)
  strict private
    FSource: TPMLWaylandSource;
  public
    constructor Create(ASource: TPMLWaylandSource);
    procedure send(AProxy: Pzwp_primary_selection_source_v1; mime_type: PAnsiChar;
      fd: LongInt); override;
    procedure cancelled(AProxy: Pzwp_primary_selection_source_v1); override;
  end;

  TPMLWaylandDataDeviceFwd = class(Twl_data_device_listener)
  strict private
    FOwner: TPMLWaylandClipboard;
  public
    constructor Create(AOwner: TPMLWaylandClipboard);
    procedure data_offer(AProxy: Pwl_data_device; id: Pwl_data_offer); override;
    procedure enter(AProxy: Pwl_data_device; serial: LongWord; surface: Pwl_surface;
      x: wl_fixed_t; y: wl_fixed_t; id: Pwl_data_offer); override;
    procedure leave(AProxy: Pwl_data_device); override;
    procedure motion(AProxy: Pwl_data_device; time: LongWord; x: wl_fixed_t;
      y: wl_fixed_t); override;
    procedure drop(AProxy: Pwl_data_device); override;
    procedure selection(AProxy: Pwl_data_device; id: Pwl_data_offer); override;
  end;

  TPMLWaylandPrimaryDeviceFwd = class(Tzwp_primary_selection_device_v1_listener)
  strict private
    FOwner: TPMLWaylandClipboard;
  public
    constructor Create(AOwner: TPMLWaylandClipboard);
    procedure data_offer(AProxy: Pzwp_primary_selection_device_v1;
      offer: Pzwp_primary_selection_offer_v1); override;
    procedure selection(AProxy: Pzwp_primary_selection_device_v1;
      id: Pzwp_primary_selection_offer_v1); override;
  end;

  { 他のアプリが配っている 1 つのオファー（wl_data_offer / primary selection offer）。
    SDL_WaylandDataOffer / SDL_WaylandPrimarySelectionOffer に当たる。 }
  TPMLWaylandOffer = class
  strict private
    FOwner    : TPMLWaylandClipboard;
    FKind     : TPMLClipboardSelection;
    FDataProxy: Pwl_data_offer;
    FPrimProxy: Pzwp_primary_selection_offer_v1;
    FDataFwd  : TPMLWaylandDataOfferFwd;
    FPrimFwd  : TPMLWaylandPrimaryOfferFwd;
    FMimes    : TStringArray;
    FDndAction: LongWord;
  public
    constructor CreateData(AOwner: TPMLWaylandClipboard; AProxy: Pwl_data_offer);
    constructor CreatePrimary(AOwner: TPMLWaylandClipboard;
      AProxy: Pzwp_primary_selection_offer_v1);
    destructor Destroy; override;
    procedure AddMime(const AMime: String);
    function  HasMime(const AMime: String): Boolean;
    // 相手に AFD へ書かせる。AFD は呼び出し側が閉じる。
    procedure Receive(const AMime: String; AFD: LongInt);
    function  ProxyPtr: Pointer;
    // ---- ドラッグ＆ドロップ（wl_data_offer の要求。プライマリ選択のオファーでは何もしない）
    // AMime が空なら断る（mime_type = NULL）。
    procedure Accept(ASerial: LongWord; const AMime: String);
    // バージョン 3 から。それ未満のコンポジタには送らない。
    procedure SetActions(AActions, APreferred: LongWord);
    procedure Finish;
    property Kind : TPMLClipboardSelection read FKind;
    // コンポジタが最後に知らせた操作（wl_data_offer.action）。0 = none、または未着。
    property DndAction: LongWord read FDndAction write FDndAction;
    // 相手が配っているままの MIME タイプ（echo の印を含む）。
    property Mimes: TStringArray read FMimes write FMimes;
  end;

  { こちらが置いた 1 つのソース。SDL_WaylandDataSource / SDL_WaylandPrimarySelectionSource に当たる。 }
  TPMLWaylandSource = class
  strict private
    FOwner    : TPMLWaylandClipboard;
    FKind     : TPMLClipboardSelection;
    FDataProxy: Pwl_data_source;
    FPrimProxy: Pzwp_primary_selection_source_v1;
    FDataFwd  : TPMLWaylandDataSourceFwd;
    FPrimFwd  : TPMLWaylandPrimarySourceFwd;
    FMarker   : String;
    FMimes    : TStringArray;
    FProvider : IPMLClipboardDataProvider;
    FPublished: Boolean;
    FAwaitEcho: Boolean;
    FIsDrag   : Boolean;
  public
    constructor CreateData(AOwner: TPMLWaylandClipboard; AProxy: Pwl_data_source);
    constructor CreatePrimary(AOwner: TPMLWaylandClipboard;
      AProxy: Pzwp_primary_selection_source_v1);
    destructor Destroy; override;
    // wl_data_source.offer（印の MIME タイプも同じ経路で足す）。
    procedure OfferMime(const AMime: String);
    function  HasMime(const AMime: String): Boolean;
    // wl_data_source.set_actions（バージョン 3 から。それ未満には送らない）。
    procedure SetActions(AActions: LongWord);
    function  Version: LongWord;
    property Owner   : TPMLWaylandClipboard read FOwner;
    property Kind    : TPMLClipboardSelection read FKind;
    property DataProxy: Pwl_data_source read FDataProxy;
    property PrimProxy: Pzwp_primary_selection_source_v1 read FPrimProxy;
    property Marker  : String read FMarker write FMarker;
    // 公開層が配ってよいと言った MIME タイプ（印を含まない）。
    property Mimes   : TStringArray read FMimes write FMimes;
    property Provider: IPMLClipboardDataProvider read FProvider write FProvider;
    // set_selection を送った（serial があった）。
    property IsPublished: Boolean read FPublished write FPublished;
    // 送ったが、自分の echo がまだ届いていない。
    property AwaitEcho: Boolean read FAwaitEcho write FAwaitEcho;
    // StartDrag で作ったソース（選択ではなくドラッグに使う）。
    property IsDrag  : Boolean read FIsDrag write FIsDrag;
  end;

  TPMLWaylandOffers = array of TPMLWaylandOffer;

  { set_selection の直後に送る wl_display.sync の返事を待つ。コンポジタは要求を順に処理するので、
    選択が受け入れられてキーボードフォーカスがあれば、こちらの折り返し（echo）は
    done より前に届く。届かなければ、黙って断られた。 }
  TPMLWaylandSyncFwd = class(Twl_callback_listener)
  strict private
    FOwner : TPMLWaylandClipboard;
    FKind  : TPMLClipboardSelection;
    FMarker: String;
    FProxy : Pwl_callback;
  public
    constructor Create(AOwner: TPMLWaylandClipboard; AKind: TPMLClipboardSelection;
      const AMarker: String; AProxy: Pwl_callback);
    procedure done(AProxy: Pwl_callback; callback_data: LongWord); override;
    property Kind  : TPMLClipboardSelection read FKind;
    property Marker: String read FMarker;
    property Proxy : Pwl_callback read FProxy;
  end;
  TPMLWaylandSyncs = array of TPMLWaylandSyncFwd;

  TPMLWaylandClipboard = class(TPMLClipboardBackend)
  strict private
    FConn      : TPMLWaylandConnection;
    FSeat      : TPMLWaylandSeat;
    FDataDevice: Pwl_data_device;
    FPrimDevice: Pzwp_primary_selection_device_v1;
    FDataFwd   : TPMLWaylandDataDeviceFwd;
    FPrimFwd   : TPMLWaylandPrimaryDeviceFwd;
    FSyncs     : TPMLWaylandSyncs;    // 返事待ちの sync
    FOffers    : TPMLWaylandOffers;   // 受け取ったがまだ捨てていないオファーの全部
    FSelOffer  : array[TPMLClipboardSelection] of TPMLWaylandOffer;  // いまの選択（他のアプリ）
    FSource    : array[TPMLClipboardSelection] of TPMLWaylandSource;
    // 自分で手放したソースの印。置き換えの途中で、前の echo が後から届いても見分ける。
    FRetired   : array[TPMLClipboardSelection] of TStringArray;
    FMarkerBase: String;
    FSeq       : Integer;
    FLastError : String;
    // ---- ドラッグ＆ドロップ（SDL_WaylandDataDevice の drag_offer / dnd_window / has_mime_*）
    FDragOffer : TPMLWaylandOffer;    // enter で渡されたオファー。drop / leave で捨てる
    FDragWindow: TPMLWindowID;        // 受け付けたウィンドウ。0 = 受け付けていない
    FDragMime  : String;              // 受け取る MIME タイプ
    FDragFiles : Boolean;             // FDragMime は text/uri-list
    FDragText  : Boolean;             // FDragMime はテキスト
    // ---- ドラッグ＆ドロップの送り側（StartDrag）。受信（上の FDrag*）とは独立
    FDragSrc   : TPMLWaylandSource;   // 始めたドラッグのソース。nil = ドラッグ中でない
    FDragAction: LongWord;            // コンポジタが最後に知らせた操作（wl_data_source.action）
    FDragPerformed: Boolean;          // dnd_drop_performed が来た
    FIconSurface: Pwl_surface;        // ドラッグの絵のサーフェス。無ければ nil
    FIconBuffer : Pwl_buffer;
    procedure RecordError(const AWhere: String; E: Exception);
    function  NewMarker: String;
    function  CreateSource(ASelection: TPMLClipboardSelection): TPMLWaylandSource;
    procedure SetSelectionOn(ASelection: TPMLClipboardSelection; ASource: TPMLWaylandSource;
      ASerial: LongWord);
    procedure Publish(ASource: TPMLWaylandSource);
    procedure StartSync(ASource: TPMLWaylandSource);
    procedure RetireSource(ASource: TPMLWaylandSource; ARemember: Boolean);
    procedure ReleaseSelection(ASelection: TPMLClipboardSelection);
    procedure DiscardOffer(AOffer: TPMLWaylandOffer);
    procedure DiscardSelOffer(ASelection: TPMLClipboardSelection);
    function  EchoMarkerOf(ASelection: TPMLClipboardSelection; AOffer: TPMLWaylandOffer): String;
    function  OfferOfProxy(AProxy: Pointer): TPMLWaylandOffer;
    function  ReceiveFromOffer(AOffer: TPMLWaylandOffer; const AMimeType: String;
      out AData: TBytes): Boolean;
    function  AcceptsDrops: Boolean;
    procedure EndDrag;
    function  PublicMimes(AOffer: TPMLWaylandOffer): TStringArray;
    procedure HandleSelection(ASelection: TPMLClipboardSelection; AOffer: TPMLWaylandOffer);
    procedure HandleInputSerial(ASerial: LongWord);
    procedure AddOffer(AOffer: TPMLWaylandOffer);
    // ---- ドラッグの送り側
    procedure ReleaseDragObjects;
    procedure FinishDrag(ADropped: Boolean; AAction: LongWord);
    procedure BuildIconBuffer(const AIcon: TPMLDragIcon);
    procedure PresentIcon(const AIcon: TPMLDragIcon);
    function  IsOwnDrag(AOffer: TPMLWaylandOffer): Boolean;
    function  FetchDropData(AOffer: TPMLWaylandOffer; const AMime: String;
      out AData: TBytes): Boolean;
  private
    // ---- 送り側のソースの知らせ
    procedure HandleDragAction(ASource: TPMLWaylandSource; AAction: LongWord);
    procedure HandleDragDropPerformed(ASource: TPMLWaylandSource);
    procedure HandleDragFinished(ASource: TPMLWaylandSource);
    // ---- 転送クラスから呼ばれる（C からの呼び出しなので例外は出さない）
    procedure HandleDataOffer(AProxy: Pwl_data_offer);
    procedure HandlePrimaryOffer(AProxy: Pzwp_primary_selection_offer_v1);
    procedure HandleDataSelection(AProxy: Pwl_data_offer);
    procedure HandlePrimarySelection(AProxy: Pzwp_primary_selection_offer_v1);
    procedure HandleDragEnter(ASerial: LongWord; ASurface: Pwl_surface; AX, AY: wl_fixed_t;
      AProxy: Pwl_data_offer);
    procedure HandleDragLeave;
    procedure HandleDragMotion(AX, AY: wl_fixed_t);
    procedure HandleDragDrop;
    procedure HandleSend(ASource: TPMLWaylandSource; const AMime: String; AFD: LongInt);
    procedure HandleCancelled(ASource: TPMLWaylandSource);
    procedure HandleOfferMime(AOffer: TPMLWaylandOffer; const AMime: String);
    procedure HandleSyncDone(ASync: TPMLWaylandSyncFwd);
  public
    // ASeat の wl_seat からデータデバイスを作る。マネージャが無ければその選択は使えない。
    constructor Create(AContextRef: TObject; AOwner: TPMLObject;
      AConn: TPMLWaylandConnection; ASeat: TPMLWaylandSeat);
    destructor Destroy; override;

    function  SupportsSelection(ASelection: TPMLClipboardSelection): Boolean; override;
    function  SetSelection(ASelection: TPMLClipboardSelection; const AMimeTypes: TStringArray;
      AProvider: IPMLClipboardDataProvider): Boolean; override;
    function  OfferedMimeTypes(ASelection: TPMLClipboardSelection): TStringArray; override;
    function  ReceiveOffer(ASelection: TPMLClipboardSelection; const AMimeType: String;
      out AData: TBytes): Boolean; override;
    function  TextMimeTypes: TStringArray; override;

    // ---- ドラッグを始める側（papimela 独自）
    function  SupportsDrag: Boolean; override;
    function  StartDrag(AWindowID: TPMLWindowID; const AMimeTypes: TStringArray;
      AProvider: IPMLClipboardDataProvider; AActions: TPMLDragActions;
      const AIcon: TPMLDragIcon): Boolean; override;
    procedure CancelDrag; override;

    // 直近の握りつぶした失敗の説明（診断用）。
    property LastNonFatalError: String read FLastError;
  end;

implementation

const
  // echo の印の MIME タイプの前半。SDL の SDL_DATA_ORIGIN_MIME（application/x-sdl3-source-id）に当たる。
  ORIGIN_MIME_PREFIX = 'application/x-papimela-origin-';

  // 読み取りの待ち。SDL の EXTENDED_PIPE_TIMEOUT_NS（5 秒）と同じ 1 回の待ちに、全体の上限を足す。
  READ_CHUNK_TIMEOUT_MS = 5000;
  READ_TOTAL_TIMEOUT_MS = 60000;
  // 書き込みの待ち。SDL は 14 ms で、遅い相手だと途中で打ち切られる。
  WRITE_CHUNK_TIMEOUT_MS = 2000;
  // pipe(7)。POLLOUT の後ならこの大きさまでは止まらずに書ける。
  PIPE_ATOMIC = 4096;
  // fcntl(2) の FD_CLOEXEC（BaseUnix に無い）。
  FD_CLOEXEC_FLAG = 1;
  // 手放したソースの印を覚える数。
  RETIRED_MAX = 16;

  // ドラッグ＆ドロップで、ファイルが落とされたときの MIME タイプ。SDL の FILE_MIME。
  URI_LIST_MIME = 'text/uri-list';

{ ---- パイプの出入り（SDL の ReadPipe / WritePipe / SendData） ---- }

{ AFD を待つ。1 = 用意できた、0 = 時間切れ、-1 = 失敗。シグナルで割り込まれたら待ち直す。 }
function WaitFD(AFD: cint; AEvents: SmallInt; ATimeoutMs: Integer): Integer;
var
  PFD: TPollFd;
  R  : cint;
begin
  PFD.fd := AFD;
  PFD.events := AEvents;
  PFD.revents := 0;
  repeat
    R := fppoll(@PFD, 1, ATimeoutMs);
  until (R >= 0) or (fpgeterrno <> ESysEINTR);
  if R > 0 then
    Result := 1
  else if R = 0 then
    Result := 0
  else
    Result := -1;
end;

{ AFD が閉じられる（EOF）まで読む。時間切れ・失敗・空は False。

  PORT-NOTE: SDL の ReadPipe は時間切れでもそこまで読んだ分を成功として返す（受け取り側は
  途中で切れたデータを完全なものとして使ってしまう）。papimela は時間切れを失敗にして
  捨てる。空（0 バイトで EOF）は SDL と同じく失敗（SDL は buffer == NULL を返す）。 }
function ReadAllFromPipe(AFD: cint; out AData: TBytes): Boolean;
var
  Used, Cap, Remaining, Wait: Integer;
  N: TSsize;
  Deadline: UInt64;
begin
  AData := nil;
  Used := 0;
  Cap := 0;
  Deadline := PMLNowNS + UInt64(READ_TOTAL_TIMEOUT_MS) * 1000000;
  Result := False;
  repeat
    if PMLNowNS >= Deadline then
      Break;
    Remaining := Integer((Deadline - PMLNowNS) div 1000000);
    Wait := READ_CHUNK_TIMEOUT_MS;
    if Remaining < Wait then
      Wait := Remaining;
    if WaitFD(AFD, POLLIN, Wait) <= 0 then
      Break;
    if Cap - Used < 65536 then
    begin
      if Cap = 0 then
        Cap := 65536 * 2
      else
        Cap := Cap * 2;
      SetLength(AData, Cap);
    end;
    N := fpread(AFD, @AData[Used], Cap - Used);
    if N > 0 then
      Inc(Used, N)
    else if N = 0 then
    begin
      Result := Used > 0;
      Break;
    end
    else if (fpgeterrno <> ESysEAGAIN) and (fpgeterrno <> ESysEINTR) then
      Break;
  until False;
  if Result then
    SetLength(AData, Used)
  else
    AData := nil;
end;

{ AData を全部 AFD へ書く。相手が読むのをやめた・時間切れ・失敗は False。

  PORT-NOTE: SDL の WritePipe は 1 回の待ちが 14 ms で、時間切れはその場で打ち切る
  （読み手が 14 ms 動かないだけで、相手には途中で切れたデータが渡る）。papimela は 1 回の
  待ちを 2 秒にした。主スレッドを止める上限が伸びる代わりに、遅い読み手でも切れない。

  SIGPIPE は SDL と同じく、このスレッドのマスクで止めて書き、溜まった分を捨ててから戻す。 }
function WriteAllToPipe(AFD: cint; const AData: TBytes): Boolean;
var
  Blocked, Old: TSigSet;
  Zero: TTimeSpec;
  Pos, N: Integer;
  W: TSsize;
begin
  Result := False;
  fpsigemptyset(Blocked);
  fpsigaddset(Blocked, SIGPIPE);
  fpsigprocmask(SIG_BLOCK, @Blocked, @Old);
  try
    Pos := 0;
    while Pos < Length(AData) do
    begin
      if WaitFD(AFD, POLLOUT, WRITE_CHUNK_TIMEOUT_MS) <= 0 then
        Exit;
      N := Length(AData) - Pos;
      if N > PIPE_ATOMIC then
        N := PIPE_ATOMIC;
      W := fpwrite(AFD, @AData[Pos], N);
      if W > 0 then
        Inc(Pos, W)
      else if (W <= 0) and (fpgeterrno <> ESysEAGAIN) and (fpgeterrno <> ESysEINTR) then
        Exit;
    end;
    Result := True;
  finally
    // 相手が先に閉じていれば SIGPIPE が溜まっている。マスクを戻す前に捨てる。
    FillChar(Zero, SizeOf(Zero), 0);
    fpsigtimedwait(Blocked, nil, @Zero);
    fpsigprocmask(SIG_SETMASK, @Old, nil);
  end;
end;

{ 受け取り用のパイプを作る。読む側だけ O_NONBLOCK にする。

  PORT-NOTE: SDL は pipe2(O_CLOEXEC | O_NONBLOCK) で両端を非ブロックにし、書く側の fd を
  相手に渡す。非ブロックの書き込み側を想定していない送り手が、大きなデータで EAGAIN を
  エラーにするのを避けるため、papimela は読む側だけを非ブロックにする。 }
function MakeReceivePipe(out AFDs: TFildes): Boolean;
var
  Flags: cint;
begin
  Result := False;
  if fppipe(AFDs) <> 0 then
    Exit;
  fpfcntl(AFDs[0], F_SETFD, FD_CLOEXEC_FLAG);
  fpfcntl(AFDs[1], F_SETFD, FD_CLOEXEC_FLAG);
  Flags := fpfcntl(AFDs[0], F_GETFL);
  if (Flags < 0) or (fpfcntl(AFDs[0], F_SETFL, Flags or O_NONBLOCK) < 0) then
  begin
    fpclose(AFDs[0]);
    fpclose(AFDs[1]);
    Exit;
  end;
  Result := True;
end;

procedure AppendString(var AList: TStringArray; const AValue: String);
begin
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := AValue;
end;

// CR / LF で分けた行（空の行は捨てる）。SDL_strtok_r(buffer, "\r\n", ...) に当たる。
function SplitLines(const AText: String): TStringArray;
var
  I, Start: Integer;

  procedure TakeLine;
  begin
    if I > Start then
      AppendString(Result, Copy(AText, Start, I - Start));
  end;

begin
  Result := nil;
  Start := 1;
  for I := 1 to Length(AText) do
    if (AText[I] = #13) or (AText[I] = #10) then
    begin
      TakeLine;
      Start := I + 1;
    end;
  I := Length(AText) + 1;
  TakeLine;
end;

function ContainsString(const AList: TStringArray; const AValue: String): Boolean;
var
  S: String;
begin
  for S in AList do
    if S = AValue then
      Exit(True);
  Result := False;
end;

{ バイト列を文字列にする。C の文字列として扱う SDL に合わせ、最初の NUL で打ち切る。 }
function DataToCString(const AData: TBytes): String;
var
  P: Integer;
begin
  Result := '';
  if Length(AData) = 0 then
    Exit;
  SetString(Result, PAnsiChar(@AData[0]), Length(AData));
  P := Pos(#0, Result);
  if P > 0 then
    SetLength(Result, P - 1);
end;

function IsOriginMime(const AMime: String): Boolean;
begin
  Result := Copy(AMime, 1, Length(ORIGIN_MIME_PREFIX)) = ORIGIN_MIME_PREFIX;
end;

function PCharToString(AValue: PAnsiChar): String;
begin
  if AValue = nil then
    Result := ''
  else
    Result := String(AValue);
end;

{ ---- 転送クラス ---- }

constructor TPMLWaylandDataOfferFwd.Create(AOffer: TPMLWaylandOffer);
begin
  inherited Create;
  FOffer := AOffer;
end;

procedure TPMLWaylandDataOfferFwd.offer(AProxy: Pwl_data_offer; mime_type: PAnsiChar);
begin
  FOffer.AddMime(PCharToString(mime_type));
end;

procedure TPMLWaylandDataOfferFwd.action(AProxy: Pwl_data_offer; dnd_action: LongWord);
begin
  FOffer.DndAction := dnd_action;
end;

constructor TPMLWaylandPrimaryOfferFwd.Create(AOffer: TPMLWaylandOffer);
begin
  inherited Create;
  FOffer := AOffer;
end;

procedure TPMLWaylandPrimaryOfferFwd.offer(AProxy: Pzwp_primary_selection_offer_v1;
  mime_type: PAnsiChar);
begin
  FOffer.AddMime(PCharToString(mime_type));
end;

constructor TPMLWaylandDataSourceFwd.Create(ASource: TPMLWaylandSource);
begin
  inherited Create;
  FSource := ASource;
end;

procedure TPMLWaylandDataSourceFwd.send(AProxy: Pwl_data_source; mime_type: PAnsiChar;
  fd: LongInt);
begin
  FSource.Owner.HandleSend(FSource, PCharToString(mime_type), fd);
end;

procedure TPMLWaylandDataSourceFwd.cancelled(AProxy: Pwl_data_source);
begin
  // ソースはこの中で破棄される（このリスナー自身も）。戻ったあとは何も触らない。
  FSource.Owner.HandleCancelled(FSource);
end;

procedure TPMLWaylandDataSourceFwd.dnd_drop_performed(AProxy: Pwl_data_source);
begin
  FSource.Owner.HandleDragDropPerformed(FSource);
end;

procedure TPMLWaylandDataSourceFwd.dnd_finished(AProxy: Pwl_data_source);
begin
  // ソースはこの中で破棄される（cancelled と同じ）。戻ったあとは何も触らない。
  FSource.Owner.HandleDragFinished(FSource);
end;

procedure TPMLWaylandDataSourceFwd.action(AProxy: Pwl_data_source; dnd_action: LongWord);
begin
  FSource.Owner.HandleDragAction(FSource, dnd_action);
end;

constructor TPMLWaylandPrimarySourceFwd.Create(ASource: TPMLWaylandSource);
begin
  inherited Create;
  FSource := ASource;
end;

procedure TPMLWaylandPrimarySourceFwd.send(AProxy: Pzwp_primary_selection_source_v1;
  mime_type: PAnsiChar; fd: LongInt);
begin
  FSource.Owner.HandleSend(FSource, PCharToString(mime_type), fd);
end;

procedure TPMLWaylandPrimarySourceFwd.cancelled(AProxy: Pzwp_primary_selection_source_v1);
begin
  FSource.Owner.HandleCancelled(FSource);
end;

constructor TPMLWaylandDataDeviceFwd.Create(AOwner: TPMLWaylandClipboard);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TPMLWaylandDataDeviceFwd.data_offer(AProxy: Pwl_data_device; id: Pwl_data_offer);
begin
  FOwner.HandleDataOffer(id);
end;

procedure TPMLWaylandDataDeviceFwd.enter(AProxy: Pwl_data_device; serial: LongWord;
  surface: Pwl_surface; x: wl_fixed_t; y: wl_fixed_t; id: Pwl_data_offer);
begin
  FOwner.HandleDragEnter(serial, surface, x, y, id);
end;

procedure TPMLWaylandDataDeviceFwd.leave(AProxy: Pwl_data_device);
begin
  FOwner.HandleDragLeave;
end;

procedure TPMLWaylandDataDeviceFwd.motion(AProxy: Pwl_data_device; time: LongWord;
  x: wl_fixed_t; y: wl_fixed_t);
begin
  FOwner.HandleDragMotion(x, y);
end;

procedure TPMLWaylandDataDeviceFwd.drop(AProxy: Pwl_data_device);
begin
  FOwner.HandleDragDrop;
end;

procedure TPMLWaylandDataDeviceFwd.selection(AProxy: Pwl_data_device; id: Pwl_data_offer);
begin
  FOwner.HandleDataSelection(id);
end;

constructor TPMLWaylandPrimaryDeviceFwd.Create(AOwner: TPMLWaylandClipboard);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TPMLWaylandPrimaryDeviceFwd.data_offer(AProxy: Pzwp_primary_selection_device_v1;
  offer: Pzwp_primary_selection_offer_v1);
begin
  FOwner.HandlePrimaryOffer(offer);
end;

procedure TPMLWaylandPrimaryDeviceFwd.selection(AProxy: Pzwp_primary_selection_device_v1;
  id: Pzwp_primary_selection_offer_v1);
begin
  FOwner.HandlePrimarySelection(id);
end;

{ ---- TPMLWaylandSyncFwd ---- }

constructor TPMLWaylandSyncFwd.Create(AOwner: TPMLWaylandClipboard;
  AKind: TPMLClipboardSelection; const AMarker: String; AProxy: Pwl_callback);
begin
  inherited Create;
  FOwner := AOwner;
  FKind := AKind;
  FMarker := AMarker;
  FProxy := AProxy;
end;

procedure TPMLWaylandSyncFwd.done(AProxy: Pwl_callback; callback_data: LongWord);
begin
  FOwner.HandleSyncDone(Self);
end;

{ ---- TPMLWaylandOffer ---- }

constructor TPMLWaylandOffer.CreateData(AOwner: TPMLWaylandClipboard; AProxy: Pwl_data_offer);
begin
  inherited Create;
  FOwner := AOwner;
  FKind := TPMLClipboardSelection.Clipboard;
  FDataProxy := AProxy;
  FDataFwd := TPMLWaylandDataOfferFwd.Create(Self);
  wl_data_offer_add_listener_object(AProxy, FDataFwd);
end;

constructor TPMLWaylandOffer.CreatePrimary(AOwner: TPMLWaylandClipboard;
  AProxy: Pzwp_primary_selection_offer_v1);
begin
  inherited Create;
  FOwner := AOwner;
  FKind := TPMLClipboardSelection.Primary;
  FPrimProxy := AProxy;
  FPrimFwd := TPMLWaylandPrimaryOfferFwd.Create(Self);
  zwp_primary_selection_offer_v1_add_listener_object(AProxy, FPrimFwd);
end;

destructor TPMLWaylandOffer.Destroy;
begin
  // 破棄したプロキシへの未配送のイベントは libwayland が捨てるので、リスナーはその後で消してよい。
  if FDataProxy <> nil then
    wl_data_offer_destroy(FDataProxy);
  if FPrimProxy <> nil then
    zwp_primary_selection_offer_v1_destroy(FPrimProxy);
  FreeAndNil(FDataFwd);
  FreeAndNil(FPrimFwd);
  inherited Destroy;
end;

function TPMLWaylandOffer.ProxyPtr: Pointer;
begin
  if FDataProxy <> nil then
    Result := FDataProxy
  else
    Result := FPrimProxy;
end;

procedure TPMLWaylandOffer.AddMime(const AMime: String);
begin
  FOwner.HandleOfferMime(Self, AMime);
end;

function TPMLWaylandOffer.HasMime(const AMime: String): Boolean;
begin
  Result := ContainsString(FMimes, AMime);
end;

procedure TPMLWaylandOffer.Receive(const AMime: String; AFD: LongInt);
begin
  if FDataProxy <> nil then
    wl_data_offer_receive(FDataProxy, PAnsiChar(AMime), AFD)
  else
    zwp_primary_selection_offer_v1_receive(FPrimProxy, PAnsiChar(AMime), AFD);
end;

procedure TPMLWaylandOffer.Accept(ASerial: LongWord; const AMime: String);
begin
  if FDataProxy = nil then
    Exit;
  if AMime = '' then
    wl_data_offer_accept(FDataProxy, ASerial, nil)
  else
    wl_data_offer_accept(FDataProxy, ASerial, PAnsiChar(AMime));
end;

procedure TPMLWaylandOffer.SetActions(AActions, APreferred: LongWord);
begin
  if (FDataProxy <> nil)
    and (wl_proxy_get_version(Pwl_proxy(FDataProxy)) >= WL_DATA_OFFER_SET_ACTIONS_SINCE_VERSION) then
    wl_data_offer_set_actions(FDataProxy, AActions, APreferred);
end;

procedure TPMLWaylandOffer.Finish;
begin
  if (FDataProxy <> nil)
    and (wl_proxy_get_version(Pwl_proxy(FDataProxy)) >= WL_DATA_OFFER_FINISH_SINCE_VERSION) then
    wl_data_offer_finish(FDataProxy);
end;

{ ---- TPMLWaylandSource ---- }

constructor TPMLWaylandSource.CreateData(AOwner: TPMLWaylandClipboard; AProxy: Pwl_data_source);
begin
  inherited Create;
  FOwner := AOwner;
  FKind := TPMLClipboardSelection.Clipboard;
  FDataProxy := AProxy;
  FDataFwd := TPMLWaylandDataSourceFwd.Create(Self);
  wl_data_source_add_listener_object(AProxy, FDataFwd);
end;

constructor TPMLWaylandSource.CreatePrimary(AOwner: TPMLWaylandClipboard;
  AProxy: Pzwp_primary_selection_source_v1);
begin
  inherited Create;
  FOwner := AOwner;
  FKind := TPMLClipboardSelection.Primary;
  FPrimProxy := AProxy;
  FPrimFwd := TPMLWaylandPrimarySourceFwd.Create(Self);
  zwp_primary_selection_source_v1_add_listener_object(AProxy, FPrimFwd);
end;

destructor TPMLWaylandSource.Destroy;
begin
  if FDataProxy <> nil then
    wl_data_source_destroy(FDataProxy);
  if FPrimProxy <> nil then
    zwp_primary_selection_source_v1_destroy(FPrimProxy);
  FreeAndNil(FDataFwd);
  FreeAndNil(FPrimFwd);
  FProvider := nil;
  inherited Destroy;
end;

procedure TPMLWaylandSource.OfferMime(const AMime: String);
begin
  if FDataProxy <> nil then
    wl_data_source_offer(FDataProxy, PAnsiChar(AMime))
  else
    zwp_primary_selection_source_v1_offer(FPrimProxy, PAnsiChar(AMime));
end;

function TPMLWaylandSource.HasMime(const AMime: String): Boolean;
begin
  Result := ContainsString(FMimes, AMime);
end;

procedure TPMLWaylandSource.SetActions(AActions: LongWord);
begin
  if (FDataProxy <> nil)
    and (wl_proxy_get_version(Pwl_proxy(FDataProxy)) >= WL_DATA_SOURCE_SET_ACTIONS_SINCE_VERSION) then
    wl_data_source_set_actions(FDataProxy, AActions);
end;

function TPMLWaylandSource.Version: LongWord;
begin
  if FDataProxy <> nil then
    Result := wl_proxy_get_version(Pwl_proxy(FDataProxy))
  else
    Result := 0;
end;

{ ---- TPMLWaylandClipboard ---- }

constructor TPMLWaylandClipboard.Create(AContextRef: TObject; AOwner: TPMLObject;
  AConn: TPMLWaylandConnection; ASeat: TPMLWaylandSeat);
begin
  inherited Create(AContextRef, AOwner);
  FConn := AConn;
  FSeat := ASeat;
  FMarkerBase := ORIGIN_MIME_PREFIX + IntToStr(fpgetpid) + '-'
    + IntToHex(PMLNowNS and $FFFFFFFF, 8) + '-';
  if FConn.DataDeviceMgr <> nil then
  begin
    FDataDevice := wl_data_device_manager_get_data_device(FConn.DataDeviceMgr, ASeat.Handle);
    FDataFwd := TPMLWaylandDataDeviceFwd.Create(Self);
    wl_data_device_add_listener_object(FDataDevice, FDataFwd);
  end;
  if FConn.PrimarySelectionMgr <> nil then
  begin
    FPrimDevice := zwp_primary_selection_device_manager_v1_get_device(
      FConn.PrimarySelectionMgr, ASeat.Handle);
    FPrimFwd := TPMLWaylandPrimaryDeviceFwd.Create(Self);
    zwp_primary_selection_device_v1_add_listener_object(FPrimDevice, FPrimFwd);
  end;
  FSeat.OnInputSerial := @HandleInputSerial;
end;

destructor TPMLWaylandClipboard.Destroy;
var
  S: TPMLClipboardSelection;
  I: Integer;
begin
  FSink := nil;
  FSeat.OnInputSerial := nil;
  for I := 0 to High(FSyncs) do
  begin
    wl_proxy_destroy(Pwl_proxy(FSyncs[I].Proxy));
    FSyncs[I].Free;
  end;
  FSyncs := nil;
  // ドラッグ中なら捨てる（公開層は先に CancelDrag している）。提供者へは知らせない。
  ReleaseDragObjects;
  // 提供者はもう呼ばない。選択を手放してソースを捨てる。
  for S := Low(TPMLClipboardSelection) to High(TPMLClipboardSelection) do
  begin
    FSelOffer[S] := nil;
    if FSource[S] <> nil then
    begin
      FSource[S].Provider := nil;
      ReleaseSelection(S);
    end;
  end;
  for I := 0 to High(FOffers) do
    FOffers[I].Free;
  FOffers := nil;
  // wl_data_device.release は version 2 から。1 ならプロキシを破棄するだけ。
  if FDataDevice <> nil then
  begin
    if wl_proxy_get_version(Pwl_proxy(FDataDevice)) >= 2 then
      wl_data_device_release(FDataDevice)
    else
      wl_proxy_destroy(Pwl_proxy(FDataDevice));
    FDataDevice := nil;
  end;
  if FPrimDevice <> nil then
  begin
    zwp_primary_selection_device_v1_destroy(FPrimDevice);
    FPrimDevice := nil;
  end;
  FreeAndNil(FDataFwd);
  FreeAndNil(FPrimFwd);
  if FConn.Display <> nil then
    wl_display_flush(FConn.Display);
  inherited Destroy;
end;

procedure TPMLWaylandClipboard.RecordError(const AWhere: String; E: Exception);
begin
  FLastError := AWhere + ': ' + E.ClassName + ': ' + E.Message;
end;

function TPMLWaylandClipboard.NewMarker: String;
begin
  Inc(FSeq);
  Result := FMarkerBase + IntToStr(FSeq);
end;

function TPMLWaylandClipboard.SupportsSelection(ASelection: TPMLClipboardSelection): Boolean;
begin
  if ASelection = TPMLClipboardSelection.Clipboard then
    Result := FDataDevice <> nil
  else
    Result := FPrimDevice <> nil;
end;

{ SDL_waylandclipboard.c の text_mime_types。UTF-8 を先頭にして、古いアプリ向けの名前が続く。 }
function TPMLWaylandClipboard.TextMimeTypes: TStringArray;
begin
  Result := ['text/plain;charset=utf-8', 'text/plain', 'TEXT', 'UTF8_STRING', 'STRING'];
end;

function TPMLWaylandClipboard.CreateSource(ASelection: TPMLClipboardSelection): TPMLWaylandSource;
begin
  if ASelection = TPMLClipboardSelection.Clipboard then
    Result := TPMLWaylandSource.CreateData(Self,
      wl_data_device_manager_create_data_source(FConn.DataDeviceMgr))
  else
    Result := TPMLWaylandSource.CreatePrimary(Self,
      zwp_primary_selection_device_manager_v1_create_source(FConn.PrimarySelectionMgr));
end;

procedure TPMLWaylandClipboard.SetSelectionOn(ASelection: TPMLClipboardSelection;
  ASource: TPMLWaylandSource; ASerial: LongWord);
var
  DataSrc: Pwl_data_source;
  PrimSrc: Pzwp_primary_selection_source_v1;
begin
  DataSrc := nil;
  PrimSrc := nil;
  if ASource <> nil then
  begin
    DataSrc := ASource.DataProxy;
    PrimSrc := ASource.PrimProxy;
  end;
  if ASelection = TPMLClipboardSelection.Clipboard then
    wl_data_device_set_selection(FDataDevice, DataSrc, ASerial)
  else
    zwp_primary_selection_device_v1_set_selection(FPrimDevice, PrimSrc, ASerial);
end;

{ serial があれば set_selection を送る。無ければ保留（最初の serial が来たときに送る）。 }
procedure TPMLWaylandClipboard.Publish(ASource: TPMLWaylandSource);
var
  Serial: LongWord;
begin
  if ASource.IsPublished then
    Exit;
  Serial := FSeat.InputSerial;
  if Serial = 0 then
    Exit;
  SetSelectionOn(ASource.Kind, ASource, Serial);
  ASource.IsPublished := True;
  ASource.AwaitEcho := True;
  StartSync(ASource);
end;

{ 送った set_selection が受け入れられたかを、sync の返事で確かめる準備をする。 }
procedure TPMLWaylandClipboard.StartSync(ASource: TPMLWaylandSource);
var
  CB: Pwl_callback;
  Fwd: TPMLWaylandSyncFwd;
begin
  if FConn.Display = nil then
    Exit;
  CB := wl_display_sync(FConn.Display);
  if CB = nil then
    Exit;
  Fwd := TPMLWaylandSyncFwd.Create(Self, ASource.Kind, ASource.Marker, CB);
  SetLength(FSyncs, Length(FSyncs) + 1);
  FSyncs[High(FSyncs)] := Fwd;
  wl_callback_add_listener_object(CB, Fwd);
end;

{ set_selection のあとの sync が返ってきた。

  echo が来ていれば何もしない。来ていないとき:
  - キーボードフォーカスがある: コンポジタは選択を受け取っていれば echo を先に送る
    ので、黙って断られた（serial が古い、など）。持ち主のふりをやめる。
  - フォーカスが無い: コンポジタは echo を送らない（フォーカスのあるクライアントにしか
    選択を知らせない）ので、断られたかどうか分からない。待ちだけ終える。次にフォーカスが
    入ったとき、現在の選択（こちらの echo か他のアプリのオファー）が届くので、
    通常の規則で扱える。 }
procedure TPMLWaylandClipboard.HandleSyncDone(ASync: TPMLWaylandSyncFwd);
var
  I, J: Integer;
  K: TPMLClipboardSelection;
  Marker: String;
  Src: TPMLWaylandSource;
begin
  K := ASync.Kind;
  Marker := ASync.Marker;
  for I := 0 to High(FSyncs) do
    if FSyncs[I] = ASync then
    begin
      for J := I to High(FSyncs) - 1 do
        FSyncs[J] := FSyncs[J + 1];
      SetLength(FSyncs, Length(FSyncs) - 1);
      Break;
    end;
  wl_proxy_destroy(Pwl_proxy(ASync.Proxy));
  ASync.Free;   // 戻ったあと、このリスナーには触らない

  // C から呼ばれるので例外を外へ出さない（提供者の ClipboardDataCancelled はアプリのコード）。
  try
    Src := FSource[K];
    if (Src = nil) or (Src.Marker <> Marker) or not Src.AwaitEcho then
      Exit;
    if not FSeat.HasKeyFocus then
    begin
      Src.AwaitEcho := False;
      // 預かっていた他のアプリのオファーは、置く前の選択のもので、いまも有効か分からない。
      DiscardSelOffer(K);
      Exit;
    end;
    // 断られた。echo の印は覚えない（echo は来ない）。
    FSource[K] := nil;
    RetireSource(Src, False);
    if Assigned(FSink) then
      FSink.ClipboardOwnershipLost(K);
    // 置く前から見えていた他のアプリの選択は、そのまま有効。読み続けられるよう知らせ直す。
    if (FSelOffer[K] <> nil) and Assigned(FSink) then
      FSink.ClipboardOffered(K, PublicMimes(FSelOffer[K]));
  except
    on E: Exception do
      RecordError('sync', E);
  end;
end;

procedure TPMLWaylandClipboard.HandleInputSerial(ASerial: LongWord);
var
  S: TPMLClipboardSelection;
begin
  try
    for S := Low(TPMLClipboardSelection) to High(TPMLClipboardSelection) do
      if (FSource[S] <> nil) and not FSource[S].IsPublished then
        Publish(FSource[S]);
    if FConn.Display <> nil then
      wl_display_flush(FConn.Display);
  except
    on E: Exception do
      RecordError('HandleInputSerial', E);
  end;
end;

{ ソースを捨てる。ARemember なら印を覚える（自分で置き換えた・消したとき。echo が
  後から届いても自分のものだと分かるように）。 }
procedure TPMLWaylandClipboard.RetireSource(ASource: TPMLWaylandSource; ARemember: Boolean);
var
  K: TPMLClipboardSelection;
begin
  K := ASource.Kind;
  if ARemember then
  begin
    if Length(FRetired[K]) >= RETIRED_MAX then
      Delete(FRetired[K], 0, 1);
    AppendString(FRetired[K], ASource.Marker);
  end;
  ASource.Free;
end;

{ 置いてあるソースを手放す（提供者へは知らせない。それは公開層の仕事）。 }
procedure TPMLWaylandClipboard.ReleaseSelection(ASelection: TPMLClipboardSelection);
var
  Old: TPMLWaylandSource;
begin
  Old := FSource[ASelection];
  if Old = nil then
    Exit;
  FSource[ASelection] := nil;
  // ソースを破棄するだけで選択は空になる（いま選択がこのソースのときだけ。set_selection(nil)
  // を送ると、他のアプリがすでに取った選択まで消してしまう。取り消しの知らせが
  // まだこちらに届いていない間に起きうる）。
  RetireSource(Old, True);
end;

function TPMLWaylandClipboard.SetSelection(ASelection: TPMLClipboardSelection;
  const AMimeTypes: TStringArray; AProvider: IPMLClipboardDataProvider): Boolean;
var
  Src, Old: TPMLWaylandSource;
  M: String;
begin
  Result := False;
  Src := nil;
  try
    if not SupportsSelection(ASelection) then
      Exit;
    if (AProvider = nil) or (Length(AMimeTypes) = 0) then
    begin
      ReleaseSelection(ASelection);
      if FConn.Display <> nil then
        wl_display_flush(FConn.Display);
      Exit(True);
    end;

    Src := CreateSource(ASelection);
    Src.Marker := NewMarker;
    for M in AMimeTypes do
      Src.OfferMime(M);
    Src.OfferMime(Src.Marker);
    Src.Mimes := Copy(AMimeTypes);
    Src.Provider := AProvider;

    // 他のアプリのオファーは、こちらの echo が届くまで残す。受け入れられれば echo で
    // 捨て、断られれば（HandleSyncDone）そのまま読み続ける。
    // 新しいソースを先に置いてから古いのを捨てる（クリップボードマネージャによっては
    // その順を好む。SDL と同じ）。
    Old := FSource[ASelection];
    FSource[ASelection] := Src;
    Src := nil;   // 以降は FSource が持つ
    Publish(FSource[ASelection]);
    if Old <> nil then
      RetireSource(Old, True);
    if FConn.Display <> nil then
      wl_display_flush(FConn.Display);
    Result := True;
  except
    on E: Exception do
    begin
      RecordError('SetSelection', E);
      Src.Free;   // 置く前に失敗したソースだけが残っている
      Result := False;
    end;
  end;
end;

{ プロキシから、受け取ったオファーを引く。

  PORT-NOTE: SDL は wl_data_offer_set_user_data で自分の構造体を持たせて引く。papimela の
  生成リスナーは add_listener の data にリスナーのオブジェクトを渡すので、user_data は
  それが使っている（上書きするとサンクが別のオブジェクトを呼んで落ちる）。プロキシの
  アドレスで探す。 }
function TPMLWaylandClipboard.OfferOfProxy(AProxy: Pointer): TPMLWaylandOffer;
var
  I: Integer;
begin
  Result := nil;
  if AProxy = nil then
    Exit;
  for I := 0 to High(FOffers) do
    if FOffers[I].ProxyPtr = AProxy then
      Exit(FOffers[I]);
end;

procedure TPMLWaylandClipboard.AddOffer(AOffer: TPMLWaylandOffer);
begin
  SetLength(FOffers, Length(FOffers) + 1);
  FOffers[High(FOffers)] := AOffer;
end;

procedure TPMLWaylandClipboard.DiscardOffer(AOffer: TPMLWaylandOffer);
var
  I, J: Integer;
begin
  if AOffer = nil then
    Exit;
  for I := 0 to High(FOffers) do
    if FOffers[I] = AOffer then
    begin
      for J := I to High(FOffers) - 1 do
        FOffers[J] := FOffers[J + 1];
      SetLength(FOffers, Length(FOffers) - 1);
      Break;
    end;
  AOffer.Free;
end;

procedure TPMLWaylandClipboard.DiscardSelOffer(ASelection: TPMLClipboardSelection);
var
  Old: TPMLWaylandOffer;
begin
  Old := FSelOffer[ASelection];
  FSelOffer[ASelection] := nil;
  DiscardOffer(Old);
end;

{ このオファーがこちらが置いたソースの折り返しなら、その印の MIME タイプ。違えば ''。
  いま生きているソースの印と、自分で手放したソースの印だけが対象。 }
function TPMLWaylandClipboard.EchoMarkerOf(ASelection: TPMLClipboardSelection;
  AOffer: TPMLWaylandOffer): String;
var
  M: String;
begin
  for M in AOffer.Mimes do
  begin
    if not IsOriginMime(M) then
      Continue;
    if (FSource[ASelection] <> nil) and (FSource[ASelection].Marker = M) then
      Exit(M);
    if ContainsString(FRetired[ASelection], M) then
      Exit(M);
  end;
  Result := '';
end;

{ 公開する MIME タイプ（印を除く）。 }
function TPMLWaylandClipboard.PublicMimes(AOffer: TPMLWaylandOffer): TStringArray;
var
  M: String;
begin
  Result := nil;
  for M in AOffer.Mimes do
    if not IsOriginMime(M) then
      AppendString(Result, M);
end;

function TPMLWaylandClipboard.OfferedMimeTypes(ASelection: TPMLClipboardSelection): TStringArray;
begin
  Result := nil;
  try
    if FSelOffer[ASelection] <> nil then
      Result := PublicMimes(FSelOffer[ASelection]);
  except
    on E: Exception do
      RecordError('OfferedMimeTypes', E);
  end;
end;

{ AOffer から AMimeType のデータをパイプで受け取る。例外は呼び出し側が受ける。
  クリップボードの受け取りとドラッグ＆ドロップの受け取りの共通部分。

  PORT-NOTE: SDL の Wayland_DataOfferReceive は、データデバイスが処理しているイベントの
  途中でも読めるよう、パイプを非ブロックにして 14 ms / 5 秒の待ちで読む。papimela は
  公開層がメインスレッドから呼ぶので、待ちは 1 回 5 秒・全体 60 秒の 1 種類にした。 }
function TPMLWaylandClipboard.ReceiveFromOffer(AOffer: TPMLWaylandOffer;
  const AMimeType: String; out AData: TBytes): Boolean;
var
  FDs: TFildes;
begin
  AData := nil;
  Result := False;
  if (AOffer = nil) or (FConn.Display = nil) then
    Exit;
  if not MakeReceivePipe(FDs) then
  begin
    FLastError := 'ReceiveOffer: pipe failed';
    Exit;
  end;
  try
    AOffer.Receive(AMimeType, FDs[1]);
    // 書く側は相手に渡したので、こちらは閉じる。閉じないと EOF が来ない。
    fpclose(FDs[1]);
    FDs[1] := -1;
    wl_display_flush(FConn.Display);
    Result := ReadAllFromPipe(FDs[0], AData);
    if not Result then
      FLastError := 'ReceiveOffer: no data (timeout or empty) for ' + AMimeType;
  finally
    if FDs[1] >= 0 then
      fpclose(FDs[1]);
    fpclose(FDs[0]);
  end;
end;

{ 他のアプリの選択のデータを読む（待ち方は ReceiveFromOffer の PORT-NOTE のとおり）。 }
function TPMLWaylandClipboard.ReceiveOffer(ASelection: TPMLClipboardSelection;
  const AMimeType: String; out AData: TBytes): Boolean;
var
  Offer: TPMLWaylandOffer;
begin
  AData := nil;
  Result := False;
  try
    Offer := FSelOffer[ASelection];
    if (Offer = nil) or not Offer.HasMime(AMimeType) then
      Exit;
    Result := ReceiveFromOffer(Offer, AMimeType, AData);
  except
    on E: Exception do
    begin
      RecordError('ReceiveOffer', E);
      AData := nil;
      Result := False;
    end;
  end;
end;

{ ---- イベント処理 ---- }

procedure TPMLWaylandClipboard.HandleDataOffer(AProxy: Pwl_data_offer);
begin
  try
    if AProxy <> nil then
      AddOffer(TPMLWaylandOffer.CreateData(Self, AProxy));
  except
    on E: Exception do
      RecordError('data_offer', E);
  end;
end;

procedure TPMLWaylandClipboard.HandlePrimaryOffer(AProxy: Pzwp_primary_selection_offer_v1);
begin
  try
    if AProxy <> nil then
      AddOffer(TPMLWaylandOffer.CreatePrimary(Self, AProxy));
  except
    on E: Exception do
      RecordError('primary data_offer', E);
  end;
end;

procedure TPMLWaylandClipboard.HandleOfferMime(AOffer: TPMLWaylandOffer; const AMime: String);
var
  List: TStringArray;
begin
  try
    // MIME の一覧は TPMLWaylandOffer の内側にあるので、同じ並びのコピーを作って渡し直す。
    List := Copy(AOffer.Mimes);
    if (AMime <> '') and not ContainsString(List, AMime) then
      AppendString(List, AMime);
    AOffer.Mimes := List;
  except
    on E: Exception do
      RecordError('offer mime', E);
  end;
end;

procedure TPMLWaylandClipboard.HandleDataSelection(AProxy: Pwl_data_offer);
begin
  try
    HandleSelection(TPMLClipboardSelection.Clipboard, OfferOfProxy(AProxy));
  except
    on E: Exception do
      RecordError('selection', E);
  end;
end;

procedure TPMLWaylandClipboard.HandlePrimarySelection(AProxy: Pzwp_primary_selection_offer_v1);
begin
  try
    HandleSelection(TPMLClipboardSelection.Primary, OfferOfProxy(AProxy));
  except
    on E: Exception do
      RecordError('primary selection', E);
  end;
end;

{ ---- ドラッグ＆ドロップの受信（data_device_handle_enter / leave / motion / drop） ---- }

{ このドラッグを受け付けるか。SDL は SDL_EVENT_DROP_FILE か SDL_EVENT_DROP_TEXT が
  有効なときだけウィンドウに accepts_drag_and_drop を立てる。papimela はウィンドウごとに
  切り替えず、有効かどうかをドラッグが入ってきたときに見る。 }
function TPMLWaylandClipboard.AcceptsDrops: Boolean;
var
  Q: TPMLEventQueue;
begin
  Q := FSeat.Queue;
  Result := Q.GetEnabled(TPMLEventKind.DropFile) or Q.GetEnabled(TPMLEventKind.DropText);
end;

{ ドラッグの状態を戻し、enter で渡されたオファーを捨てる。 }
procedure TPMLWaylandClipboard.EndDrag;
var
  Old: TPMLWaylandOffer;
begin
  Old := FDragOffer;
  FDragOffer := nil;
  FDragWindow := 0;
  FDragMime := '';
  FDragFiles := False;
  FDragText := False;
  DiscardOffer(Old);
end;

{ ドラッグがウィンドウに入った。

  WHAT:
    受け取る MIME タイプを選び、accept と set_actions(copy) を送って、最初の位置を知らせる。
    受けないドラッグには accept(NULL) と set_actions(none) を送って断る。
    どちらでも、オファーは leave か drop まで持つ（そこで捨てる）。

  WHY:
    SDL は text/uri-list を見たあとでテキストの MIME タイプも探し、両方あると
    mime_type を後者で上書きする。その状態で drop すると、テキストのデータを
    URI の一覧として読む。papimela は text/uri-list があればそれだけを使い、
    無いときだけテキストを探す。


  PORT-NOTE: SDL の document-portal の枝。SDL は application/vnd.portal.filetransfer を
  持つオファーに FILE_PORTAL_MIME を accept し、text/uri-list もあれば後からそちらを
  accept し直す（最後の accept が効く）。papimela は text/uri-list があればそれ、
  無いときだけポータルの MIME タイプを accept する（同じ結果）。 }
procedure TPMLWaylandClipboard.HandleDragEnter(ASerial: LongWord; ASurface: Pwl_surface;
  AX, AY: wl_fixed_t; AProxy: Pwl_data_offer);
var
  Offer: TPMLWaylandOffer;
  Win: TPMLWindowID;
  M: String;
begin
  try
    // leave が来ないまま次の enter が来たら、前のドラッグを終わらせる（オファーが溜まらない
    // ように）。
    HandleDragLeave;

    Offer := OfferOfProxy(AProxy);
    FDragOffer := Offer;
    if Offer = nil then
      Exit;
    Win := FSeat.WindowIDOf(ASurface);
    if (Win <> 0) and AcceptsDrops then
    begin
      if Offer.HasMime(URI_LIST_MIME) then
      begin
        FDragFiles := True;
        FDragMime := URI_LIST_MIME;
      end
      else if Offer.HasMime(PML_PORTAL_FILETRANSFER_MIME) then
      begin
        // text/uri-list が無く、ポータルの鍵だけを配る相手（サンドボックスのアプリ）。
        // 鍵が開けなければ何も受け取れないが、ドロップとしては受け付ける。
        FDragFiles := True;
        FDragMime := PML_PORTAL_FILETRANSFER_MIME;
      end
      else
        for M in TextMimeTypes do
          if Offer.HasMime(M) then
          begin
            FDragText := True;
            FDragMime := M;
            Break;
          end;
    end;

    if FDragFiles or FDragText then
    begin
      Offer.Accept(ASerial, FDragMime);
      // SDL は copy だけを受け付ける。
      Offer.SetActions(WL_DATA_DEVICE_MANAGER_DND_ACTION_COPY,
        WL_DATA_DEVICE_MANAGER_DND_ACTION_COPY);
      FDragWindow := Win;
      FSeat.Queue.Drop.SendPosition(Win, PMLFixedToSingle(AX), PMLFixedToSingle(AY));
    end
    else
    begin
      Offer.Accept(ASerial, '');
      Offer.SetActions(WL_DATA_DEVICE_MANAGER_DND_ACTION_NONE,
        WL_DATA_DEVICE_MANAGER_DND_ACTION_NONE);
    end;
    if FConn.Display <> nil then
      wl_display_flush(FConn.Display);
  except
    on E: Exception do
      RecordError('data_device.enter', E);
  end;
end;

{ ドロップされずにポインタが出ていった（または、まだ drop が無い間に次のドラッグが来た）。
  受け付けていたなら DropComplete を積む（SDL と同じ）。drop のあとは FDragOffer が
  無いので何もしない。コンポジタが drop のあとにも leave を送ってくる場合に、
  余計な DropComplete を積まないため。 }
procedure TPMLWaylandClipboard.HandleDragLeave;
begin
  try
    if FDragOffer <> nil then
    begin
      if FDragWindow <> 0 then
        FSeat.Queue.Drop.SendComplete(FDragWindow);
      EndDrag;
    end;
  except
    on E: Exception do
      RecordError('data_device.leave', E);
  end;
end;

procedure TPMLWaylandClipboard.HandleDragMotion(AX, AY: wl_fixed_t);
begin
  try
    if (FDragOffer <> nil) and (FDragWindow <> 0) then
      FSeat.Queue.Drop.SendPosition(FDragWindow, PMLFixedToSingle(AX), PMLFixedToSingle(AY));
  except
    on E: Exception do
      RecordError('data_device.motion', E);
  end;
end;

{ ドロップされた。

  WHAT:
    データを受け取り、text/uri-list ならローカルのパスごとに DropFile、テキストなら
    行ごとに DropText を積み、最後に DropComplete を積む。受け取りに失敗しても
    DropComplete は積む（DropBegin を閉じるため。SDL と同じ）。そのあと finish を送って
    オファーを捨てる。

  WHY:
    finish は、コンポジタが操作（copy / move）を知らせてきたオファーにだけ送る。
    wl_data_offer の仕様は、操作が来ていないオファーへの finish をクライアントの
    誤りとして接続ごと切る（invalid_finish）と定めている。SDL は確かめずに送る。

  RESOLVED:
    - document-portal の枝（Flatpak などパスが見えない環境向け）。オファーが
      application/vnd.portal.filetransfer を持てば、まずその鍵を受け取って
      Documents ポータルで開き、パスごとに DropFile を積む。開けなければ text/uri-list
    - 自分のドラッグが自分のウィンドウへ落ちたときは、パイプを通さず提供者から直接読む
      （自分が書くのを自分で待って止まるのを避ける）

  NOT RESOLVED:
    - text/uri-list にローカルのファイルが 1 つも無い（ブラウザのリンクなど）ときに、
      同じオファーのテキストへ切り替えること（SDL もしない） }
procedure TPMLWaylandClipboard.HandleDragDrop;
var
  Win: TPMLWindowID;
  Offer: TPMLWaylandOffer;
  Data: TBytes;
  Text, S: String;
  Paths: TStringArray;
  Done, OwnLegacy: Boolean;
begin
  OwnLegacy := False;
  try
    try
      if (FDragOffer = nil) or (FDragWindow = 0) or not (FDragFiles or FDragText) then
        Exit;
      Win := FDragWindow;
      Offer := FDragOffer;

      // 自分のドラッグが自分のウィンドウへ落ちた。終わりの知らせ（dnd_finished）が来ない
      // バージョン 3 未満では、受け取り終えた時点でこちらから終わらせる。
      OwnLegacy := IsOwnDrag(Offer) and (FDragSrc.Version < 3);

      Done := False;
      if FDragFiles and Offer.HasMime(PML_PORTAL_FILETRANSFER_MIME) then
      begin
        // PORT-NOTE: SDL の data_device_handle_drop の document-portal の枝。鍵を受け取り、
        // Documents ポータルで開いたパスごとに DropFile を積む。SDL は D-Bus が使えなければ
        // 枝ごと飛ばす（papimela は PMLPortalRetrieveFiles が False を返す）。
        // 開けなければ（ディレクトリを含む、鍵が古い、など）text/uri-list へ戻る。
        if FetchDropData(Offer, PML_PORTAL_FILETRANSFER_MIME, Data) then
          if PMLPortalRetrieveFiles(DataToCString(Data), Paths) then
          begin
            for S in Paths do
              FSeat.Queue.Drop.SendFile(Win, S);
            Done := True;
          end;
      end;

      if not Done then
      begin
        // text/uri-list が無く、ポータルの鍵も開けなかったときは、受け取るものが無い。
        Text := '';
        if (FDragMime <> PML_PORTAL_FILETRANSFER_MIME)
          and FetchDropData(Offer, FDragMime, Data) then
          Text := DataToCString(Data);
        if FDragFiles then
        begin
          for S in PMLURIListToLocalPaths(Text) do
            FSeat.Queue.Drop.SendFile(Win, S);
        end
        else
          for S in SplitLines(Text) do
            FSeat.Queue.Drop.SendText(Win, S);
      end;
      FSeat.Queue.Drop.SendComplete(Win);

      if Offer.DndAction <> 0 then
        Offer.Finish;
      if FConn.Display <> nil then
        wl_display_flush(FConn.Display);
    finally
      // 受け付けていなくても、drop のあとはオファーを捨てる。
      EndDrag;
    end;
    if OwnLegacy then
      FinishDrag(True, WL_DATA_DEVICE_MANAGER_DND_ACTION_COPY);
  except
    on E: Exception do
      RecordError('data_device.drop', E);
  end;
end;

{ 選択が変わった。AOffer = nil は選択が無くなった。

  sink へは、他のアプリの選択が見えるようになった（または無くなった）ときだけ知らせる。
  こちらが置いたものの折り返しは知らせない。 }
procedure TPMLWaylandClipboard.HandleSelection(ASelection: TPMLClipboardSelection;
  AOffer: TPMLWaylandOffer);
var
  Src: TPMLWaylandSource;
  Echo: String;
  Had: Boolean;
begin
  Src := FSource[ASelection];

  Echo := '';
  if AOffer <> nil then
    Echo := EchoMarkerOf(ASelection, AOffer);
  if Echo <> '' then
  begin
    // 自分の折り返し。オファーは捨て、前に見えていた他のアプリのオファーも無効になっている。
    DiscardOffer(AOffer);
    DiscardSelOffer(ASelection);
    // いま置いているソースの折り返しが届いたときだけ「待ち」を解く（1 つ前のものでは解かない）。
    if (Src <> nil) and (Src.Marker = Echo) then
      Src.AwaitEcho := False;
    Exit;
  end;

  if (Src <> nil) and (Src.AwaitEcho or not Src.IsPublished) then
  begin
    // 置いた直後で、自分の折り返しがまだ届いていない。これは置く前の選択の通知が
    // 追い越してきただけかもしれない。所有権は手放さず、通知もしない（オファーだけ
    // 覚えておく）。本物なら cancelled が届くので、そこで通知する。
    DiscardSelOffer(ASelection);
    FSelOffer[ASelection] := AOffer;
    Exit;
  end;

  if AOffer = nil then
  begin
    Had := FSelOffer[ASelection] <> nil;
    DiscardSelOffer(ASelection);
    // 他のアプリの選択が無くなったときだけ知らせる。こちらが消した分の通知は不要。
    if Had and Assigned(FSink) then
      FSink.ClipboardOffered(ASelection, nil);
    Exit;
  end;

  if FSelOffer[ASelection] <> AOffer then
  begin
    DiscardSelOffer(ASelection);
    FSelOffer[ASelection] := AOffer;
  end;
  if Src <> nil then
  begin
    // 他のアプリが選択を取った。cancelled より先にこちらが届いた順序。
    FSource[ASelection] := nil;
    RetireSource(Src, False);
    if Assigned(FSink) then
      FSink.ClipboardOwnershipLost(ASelection);
  end;
  if Assigned(FSink) then
    FSink.ClipboardOffered(ASelection, PublicMimes(AOffer));
end;

{ こちらのソースに、相手がデータを求めてきた。
  提供者からバイト列をもらい、全部書いて fd を閉じる。 }
procedure TPMLWaylandClipboard.HandleSend(ASource: TPMLWaylandSource; const AMime: String;
  AFD: LongInt);
var
  Provider: IPMLClipboardDataProvider;
  Data: TBytes;
  DragSendDone: Boolean;
begin
  DragSendDone := False;
  try
    try
      // 提供者へ聞くのは、いま生きているソースの、公開層が配ってよいと言った MIME タイプだけ。
      // 印の MIME タイプには中身が無い（空のまま閉じる）。
      if (((not ASource.IsDrag) and (FSource[ASource.Kind] = ASource))
        or (ASource.IsDrag and (ASource = FDragSrc)))
        and ASource.HasMime(AMime) and (ASource.Provider <> nil) then
      begin
        Provider := ASource.Provider;
        Data := nil;
        // 以降 ASource に触らない（提供者が公開層の API を呼んで置き換えてくるかもしれない）。
        if Provider.GetClipboardData(AMime, Data) and (Length(Data) > 0) then
          if not WriteAllToPipe(AFD, Data) then
            FLastError := 'send: write failed or timed out for ' + AMime;
      end;
      // バージョン 3 未満のドラッグは終わりの知らせが無い。データを渡し終えたら終わりとみなす。
      if ASource.IsDrag and (ASource = FDragSrc) and (ASource.Version < 3) then
        DragSendDone := True;
    finally
      fpclose(AFD);
    end;
    if DragSendDone then
      FinishDrag(True, WL_DATA_DEVICE_MANAGER_DND_ACTION_COPY);
  except
    on E: Exception do
      RecordError('send', E);
  end;
end;

{ こちらのソースが取り消された（他のアプリが選択を取った）。 }
procedure TPMLWaylandClipboard.HandleCancelled(ASource: TPMLWaylandSource);
var
  K: TPMLClipboardSelection;
begin
  try
    if ASource.IsDrag then
    begin
      // ドラッグのソース。落とし先が無かった・取り消された。
      if ASource = FDragSrc then
        FinishDrag(False, 0);
      Exit;
    end;
    K := ASource.Kind;
    if FSource[K] <> ASource then
      Exit;
    FSource[K] := nil;
    // 取り消されたソースの echo は cancelled より前に届いているので、印は覚えない。
    RetireSource(ASource, False);
    if Assigned(FSink) then
      FSink.ClipboardOwnershipLost(K);
    // 「置いた直後」に預かっていた他のアプリのオファーは、本物だった。ここで通知する。
    if (FSelOffer[K] <> nil) and Assigned(FSink) then
      FSink.ClipboardOffered(K, PublicMimes(FSelOffer[K]));
  except
    on E: Exception do
      RecordError('cancelled', E);
  end;
end;


{ ---- ドラッグ＆ドロップの送り側（こちらがドラッグを始める。papimela 独自で SDL には無い） ----

  WHAT:
    StartDrag は wl_data_source を作って MIME タイプ（と自分のドラッグだと見分ける印）を
    並べ、操作（copy / move / ask）を伝え、絵のサーフェスを作って
    wl_data_device.start_drag を送る。あとはコンポジタからの知らせで進む。
      - send              : 落とし先がデータを求めた。提供者から読んでパイプへ書く
      - action            : 落とし先と決まった操作。最後に来たものを覚える
      - dnd_drop_performed: ボタンが離されて落とされた。覚えるだけ
      - dnd_finished      : 落とし先が受け取り終えた。DragEnded(True, 最後の操作)
      - cancelled         : 取り消された・落とし先が無かった。DragEnded(False, Copy)

  WHY:
    start_drag にはポインタのボタンを押した入力の serial が要り、コンポジタはグラブの
    始まりでなければ黙って無視する。そのため暗黙のグラブ（シートが覚えている押下）が
    無ければ始めずに False を返す。

  RESOLVED:
    - 絵の位置: ポインタの先が絵の (HotX, HotY) に来るよう、絵のサーフェスの原点を
      (-HotX, -HotY) へずらす。初めの置き方は「絵の左上がカーソルの先」なので、
      attach の (x, y)（wl_surface バージョン 5 以降は wl_surface.offset）に
      (-HotX, -HotY) を与える。これは wl_data_device.start_drag と wl_surface.offset の
      仕様の読みで、labwc / wlroots が実際にこの位置へ描くかは確かめていない
      （wlroots のソースは読めず、実機のドラッグも操作できなかった）
    - 絵は start_drag を送ったあとに attach して commit する（プロトコルの記述が
      その順。サーフェスの役割は start_drag で決まる）
    - 絵のバッファは ARGB8888（アルファを掛けた形）。wl_shm の共有ファイルは
      PMLCreateShmFile で作り、バッファを作ったらプールとマッピングはすぐ捨てる
    - 終わるときはソースを先に捨ててから公開層（DragEnded）へ知らせる。提供者が
      知らせの中から次の StartDrag を呼べるように

  NOT RESOLVED:
    - data_source のバージョンが 3 未満（dnd_finished も action も無い）のコンポジタでは、
      終わりが分からない。最初の send を書き終えたら DragEnded(True, Copy) とする
      近似にした（バージョン 3 未満では、データを求められるのは落とされたあとだけ）。
      3 未満では set_actions も送れないので操作は Copy 固定
    - タッチからのドラッグは始められない（ポインタのボタンだけを見る）
    - 絵の位置がコンポジタで実際にそうなるかは未確認（実機のドラッグを操作できていない） }

function TPMLWaylandClipboard.SupportsDrag: Boolean;
begin
  Result := (FDataDevice <> nil) and (FConn.DataDeviceMgr <> nil);
end;

{ ドラッグのソースと絵を畳む。提供者へは知らせない（それは公開層の仕事）。 }
procedure TPMLWaylandClipboard.ReleaseDragObjects;
var
  Src: TPMLWaylandSource;
begin
  Src := FDragSrc;
  FDragSrc := nil;
  FDragAction := 0;
  FDragPerformed := False;
  if Src <> nil then
  begin
    Src.Provider := nil;
    Src.Free;
  end;
  // バッファはサーフェスより先に捨ててよい（commit 済みの内容はコンポジタが持つ）が、
  // 順に畳む。
  if FIconSurface <> nil then
  begin
    wl_surface_destroy(FIconSurface);
    FIconSurface := nil;
  end;
  if FIconBuffer <> nil then
  begin
    wl_buffer_destroy(FIconBuffer);
    FIconBuffer := nil;
  end;
end;

{ ドラッグが終わった。ソースと絵を捨ててから公開層へ知らせる。 }
procedure TPMLWaylandClipboard.FinishDrag(ADropped: Boolean; AAction: LongWord);
var
  A: TPMLDragAction;
begin
  if FDragSrc = nil then
    Exit;
  ReleaseDragObjects;
  if FConn.Display <> nil then
    wl_display_flush(FConn.Display);
  case AAction of
    WL_DATA_DEVICE_MANAGER_DND_ACTION_MOVE: A := TPMLDragAction.Move;
    WL_DATA_DEVICE_MANAGER_DND_ACTION_ASK : A := TPMLDragAction.Ask;
  else
    A := TPMLDragAction.Copy;
  end;
  if Assigned(FSink) then
    FSink.DragEnded(ADropped, A);
end;

{ ARGB8888（アルファを掛けていない）の絵から、アルファを掛けた wl_buffer を作る。
  失敗は例外（呼び出し側が絵なしで続ける）。 }
procedure TPMLWaylandClipboard.BuildIconBuffer(const AIcon: TPMLDragIcon);
var
  Size: PtrUInt;
  FD: cint;
  Map: Pointer;
  Pool: Pwl_shm_pool;
  I, N: Integer;
  P: PLongWord;
  V, A, R, G, B: LongWord;
begin
  N := AIcon.Width * AIcon.Height;
  Size := PtrUInt(N) * 4;
  FD := PMLCreateShmFile(Size);
  try
    Map := Fpmmap(nil, Size, PROT_READ or PROT_WRITE, MAP_SHARED, FD, 0);
    if (Map = nil) or (Map = Pointer(-1)) then
      raise EPMLVideoError.CreateNative('mmap on the drag icon file failed',
        FpGetErrno, 'wayland');
    try
      P := PLongWord(Map);
      for I := 0 to N - 1 do
      begin
        V := AIcon.Pixels[I];
        A := V shr 24;
        R := (((V shr 16) and $FF) * A + 127) div 255;
        G := (((V shr 8) and $FF) * A + 127) div 255;
        B := ((V and $FF) * A + 127) div 255;
        P[I] := (A shl 24) or (R shl 16) or (G shl 8) or B;
      end;
      Pool := wl_shm_create_pool(FConn.Shm, FD, LongInt(Size));
    finally
      Fpmunmap(Map, Size);
    end;
  finally
    FpClose(FD);
  end;
  FIconBuffer := wl_shm_pool_create_buffer(Pool, 0, AIcon.Width, AIcon.Height,
    AIcon.Width * 4, WL_SHM_FORMAT_ARGB8888);
  wl_shm_pool_destroy(Pool);
  if FIconBuffer = nil then
    raise EPMLVideoError.CreateNative('wl_shm_pool.create_buffer failed (drag icon)', 0, 'wayland');
end;

{ start_drag のあとに絵を載せる。ポインタの先が絵の (HotX, HotY) に来るよう、
  サーフェスの原点を (-HotX, -HotY) へずらす。 }
procedure TPMLWaylandClipboard.PresentIcon(const AIcon: TPMLDragIcon);
begin
  if wl_proxy_get_version(Pwl_proxy(FIconSurface)) >= WL_SURFACE_OFFSET_SINCE_VERSION then
  begin
    // バージョン 5 以降は attach の x, y が 0 以外だとプロトコルエラー。offset を使う。
    wl_surface_attach(FIconSurface, FIconBuffer, 0, 0);
    wl_surface_offset(FIconSurface, -AIcon.HotX, -AIcon.HotY);
  end
  else
    wl_surface_attach(FIconSurface, FIconBuffer, -AIcon.HotX, -AIcon.HotY);
  if wl_proxy_get_version(Pwl_proxy(FIconSurface)) >= 4 then
    wl_surface_damage_buffer(FIconSurface, 0, 0, AIcon.Width, AIcon.Height)
  else
    wl_surface_damage(FIconSurface, 0, 0, AIcon.Width, AIcon.Height);
  wl_surface_commit(FIconSurface);
end;

function TPMLWaylandClipboard.StartDrag(AWindowID: TPMLWindowID;
  const AMimeTypes: TStringArray; AProvider: IPMLClipboardDataProvider;
  AActions: TPMLDragActions; const AIcon: TPMLDragIcon): Boolean;
var
  Surf: Pwl_surface;
  Serial: LongWord;
  Src: TPMLWaylandSource;
  Acts: LongWord;
  M: String;
  HasIcon: Boolean;
begin
  Result := False;
  try
    if (not SupportsDrag) or (FDragSrc <> nil) or (AProvider = nil) or (Length(AMimeTypes) = 0) then
      Exit;
    // 暗黙のグラブ（そのウィンドウでボタンを押している）が無ければ、コンポジタが
    // 無視するので始めない。
    if not FSeat.ImplicitGrab(AWindowID, Surf, Serial) then
      Exit;

    Acts := 0;
    if TPMLDragAction.Copy in AActions then
      Acts := Acts or WL_DATA_DEVICE_MANAGER_DND_ACTION_COPY;
    if TPMLDragAction.Move in AActions then
      Acts := Acts or WL_DATA_DEVICE_MANAGER_DND_ACTION_MOVE;
    if TPMLDragAction.Ask in AActions then
      Acts := Acts or WL_DATA_DEVICE_MANAGER_DND_ACTION_ASK;

    Src := TPMLWaylandSource.CreateData(Self,
      wl_data_device_manager_create_data_source(FConn.DataDeviceMgr));
    Src.IsDrag := True;
    Src.Marker := NewMarker;
    for M in AMimeTypes do
      Src.OfferMime(M);
    // 自分のウィンドウへ落ちたとき、パイプを通さず提供者から直接読むための印。
    Src.OfferMime(Src.Marker);
    Src.Mimes := Copy(AMimeTypes);
    Src.Provider := AProvider;
    Src.SetActions(Acts);
    FDragSrc := Src;
    FDragAction := 0;
    FDragPerformed := False;

    // 絵は絵のバッファが作れたときだけ。作れなくてもドラッグは始める。
    HasIcon := False;
    if (AIcon.Width > 0) and (AIcon.Height > 0)
      and (Length(AIcon.Pixels) >= AIcon.Width * AIcon.Height)
      and (FConn.Shm <> nil) and (FConn.Compositor <> nil) then
      try
        BuildIconBuffer(AIcon);
        FIconSurface := wl_compositor_create_surface(FConn.Compositor);
        HasIcon := FIconSurface <> nil;
      except
        on E: Exception do
          RecordError('drag icon', E);
      end;

    wl_data_device_start_drag(FDataDevice, Src.DataProxy, Surf, FIconSurface, Serial);
    if HasIcon then
      PresentIcon(AIcon);
    if FConn.Display <> nil then
      wl_display_flush(FConn.Display);
    Result := True;
  except
    on E: Exception do
    begin
      RecordError('StartDrag', E);
      ReleaseDragObjects;
      Result := False;
    end;
  end;
end;

{ 取り消す。ソースを捨てればコンポジタがドラッグを終わらせる。cancelled は自分で
  捨てたソースには届かないので、DragEnded は同期的にこちらから呼ぶ。 }
procedure TPMLWaylandClipboard.CancelDrag;
begin
  try
    FinishDrag(False, 0);
  except
    on E: Exception do
      RecordError('CancelDrag', E);
  end;
end;

procedure TPMLWaylandClipboard.HandleDragAction(ASource: TPMLWaylandSource; AAction: LongWord);
begin
  if ASource = FDragSrc then
    FDragAction := AAction;
end;

procedure TPMLWaylandClipboard.HandleDragDropPerformed(ASource: TPMLWaylandSource);
begin
  if ASource = FDragSrc then
    FDragPerformed := True;
end;

{ 落とし先が受け取り終えた（バージョン 3 から）。決まった操作は最後の action。 }
procedure TPMLWaylandClipboard.HandleDragFinished(ASource: TPMLWaylandSource);
begin
  try
    if ASource = FDragSrc then
      FinishDrag(True, FDragAction);
  except
    on E: Exception do
      RecordError('dnd_finished', E);
  end;
end;

{ 受け取ったオファーが、いま始めているこちらのドラッグのものか（印の MIME タイプで見分ける）。 }
function TPMLWaylandClipboard.IsOwnDrag(AOffer: TPMLWaylandOffer): Boolean;
begin
  Result := (FDragSrc <> nil) and (AOffer <> nil) and AOffer.HasMime(FDragSrc.Marker);
end;

{ ドロップされたオファーから AMime のデータを取る。

  自分のウィンドウへ落ちたとき（自分のドラッグ）は、パイプで読むと自分が書くのを
  待って止まるので、ドラッグの提供者から直接読む。 }
function TPMLWaylandClipboard.FetchDropData(AOffer: TPMLWaylandOffer; const AMime: String;
  out AData: TBytes): Boolean;
var
  Provider: IPMLClipboardDataProvider;
begin
  AData := nil;
  Result := False;
  if IsOwnDrag(AOffer) then
  begin
    if (not FDragSrc.HasMime(AMime)) or (FDragSrc.Provider = nil) then
      Exit;
    Provider := FDragSrc.Provider;
    Result := Provider.GetClipboardData(AMime, AData) and (Length(AData) > 0);
    if not Result then
      AData := nil;
  end
  else
    Result := ReceiveFromOffer(AOffer, AMime, AData);
end;

end.
