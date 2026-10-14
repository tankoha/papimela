{
  test_pipewire_abi — PipeWire の結合（構造体の並び、メソッドの呼び出し、pod、JSON）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. 構造体 30 個の大きさと欄の位置が、PipeWire 1.6.2 のヘッダで C が測った値と同じ
    2. メソッドの呼び出し（spa_api_method_r の写し）: 表の関数に相手のデータと引数が渡る、
       表・関数が無ければ既定の値
    3. spa_hook_remove、spa_dict_lookup
    4. pod の組み立て: SDL の initialize_spa_info と spa_format_audio_raw_build の 10 場面が、
       C の出したバイト列と同じ
    5. pod の読み取り: C で組み立てた 11 の pod（値の数の多すぎ・少なすぎ、最後のプロパティが入りきらない
       ものを含む）で、SDL の get_range_param / get_int_param と同じ結果。spa_pod_find_prop の始点の扱い
    6. JSON: SDL の get_name_from_json の 23 場面と、client_info の session.services の 7 場面が同じ結果。
       14 の入力を spa_json_next で 1 トークンずつ読んだ並びが同じ
    7. libpipewire-0.3.so.0 を開いて、SDL が使う関数が全部ある

  WHY:
    PipeWire の API の半分はヘッダのインライン関数なので、Pascal に写した（#21）。写しは
    C の結果と比べないと分からない。期待値は tools/genpipewire.bb が本物のヘッダで C を動かして
    書いた test/pipewire_abi_expected.inc。PipeWire のサーバは要らない。

  実行前提: 7 は libpipewire-0.3.so.0 が要る。無い環境では PAPIMELA_PIPEWIRE_OPTIONAL=1 で飛ばす
  （既定では失敗にする。空の実装が飛ばされて通らないように）。
}
program test_pipewire_abi;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils, ctypes,
  PaPiMeLa.Audio.Convert,
  PaPiMeLa.Platform.PipeWire,
  PaPiMeLa.Audio.PipeWire;

{$I pipewire_abi_expected.inc}

var
  Failures: Integer = 0;

procedure Check(ACondition: Boolean; const ALabel: String);
begin
  if ACondition then
    WriteLn('  [PASS] ', ALabel)
  else
  begin
    WriteLn('  [FAIL] ', ALabel);
    Inc(Failures);
  end;
end;

{ ---- 1. 並び ---- }

{ 大きさと、欄の位置の組（実際, 期待）を並べて比べる。違う欄の番号を報告に添える。 }
procedure Lay(const AName: String; ASize, AExpSize: PtrUInt; const APairs: array of PtrUInt);
var
  I: Integer;
  Bad: String;
begin
  Bad := '';
  if ASize <> AExpSize then
    Bad := Format(' 大きさ %d（C は %d）', [ASize, AExpSize]);
  I := 0;
  while I < High(APairs) do
  begin
    if APairs[I] <> APairs[I + 1] then
      Bad := Bad + Format(' 欄%d: %d（C は %d）', [I div 2, APairs[I], APairs[I + 1]]);
    Inc(I, 2);
  end;
  Check(Bad = '', AName + ' の大きさと欄の位置が C と同じ' + Bad);
end;

procedure TestLayouts;
begin
  WriteLn('-- 構造体の並び（x86_64）');
  Lay('spa_list', SizeOf(TSpaList), PWS_spa_list, [
    PtrUInt(@PSpaList(nil)^.Next), PWO_spa_list_next, PtrUInt(@PSpaList(nil)^.Prev), PWO_spa_list_prev]);
  Lay('spa_callbacks', SizeOf(TSpaCallbacks), PWS_spa_callbacks, [
    PtrUInt(@TSpaCallbacks(nil^).Funcs), PWO_spa_callbacks_funcs,
    PtrUInt(@TSpaCallbacks(nil^).Data), PWO_spa_callbacks_data]);
  Lay('spa_interface', SizeOf(TSpaInterface), PWS_spa_interface, [
    PtrUInt(@PSpaInterface(nil)^.TypeName), PWO_spa_interface_type,
    PtrUInt(@PSpaInterface(nil)^.Version), PWO_spa_interface_version,
    PtrUInt(@PSpaInterface(nil)^.Cb), PWO_spa_interface_cb]);
  Lay('spa_hook', SizeOf(TSpaHook), PWS_spa_hook, [
    PtrUInt(@PSpaHook(nil)^.Link), PWO_spa_hook_link, PtrUInt(@PSpaHook(nil)^.Cb), PWO_spa_hook_cb,
    PtrUInt(@PSpaHook(nil)^.Removed), PWO_spa_hook_removed, PtrUInt(@PSpaHook(nil)^.Priv), PWO_spa_hook_priv]);
  Lay('spa_dict_item', SizeOf(TSpaDictItem), PWS_spa_dict_item, [
    PtrUInt(@PSpaDictItem(nil)^.Key), PWO_spa_dict_item_key,
    PtrUInt(@PSpaDictItem(nil)^.Value), PWO_spa_dict_item_value]);
  Lay('spa_dict', SizeOf(TSpaDict), PWS_spa_dict, [
    PtrUInt(@PSpaDict(nil)^.Flags), PWO_spa_dict_flags, PtrUInt(@PSpaDict(nil)^.NItems), PWO_spa_dict_n_items,
    PtrUInt(@PSpaDict(nil)^.Items), PWO_spa_dict_items]);
  Lay('spa_pod', SizeOf(TSpaPod), PWS_spa_pod, [
    PtrUInt(@PSpaPod(nil)^.Size), PWO_spa_pod_size, PtrUInt(@PSpaPod(nil)^.PodType), PWO_spa_pod_type]);
  Lay('spa_pod_prop', SizeOf(TSpaPodProp), PWS_spa_pod_prop, [
    PtrUInt(@PSpaPodProp(nil)^.Key), PWO_spa_pod_prop_key, PtrUInt(@PSpaPodProp(nil)^.Flags), PWO_spa_pod_prop_flags,
    PtrUInt(@PSpaPodProp(nil)^.Value), PWO_spa_pod_prop_value]);
  Lay('spa_pod_object_body', SizeOf(TSpaPodObjectBody), PWS_spa_pod_object_body, [
    PtrUInt(@TSpaPodObjectBody(nil^).ObjType), PWO_spa_pod_object_body_type,
    PtrUInt(@TSpaPodObjectBody(nil^).Id), PWO_spa_pod_object_body_id]);
  Lay('spa_pod_object', SizeOf(TSpaPodObject), PWS_spa_pod_object, [
    PtrUInt(@PSpaPodObject(nil)^.Pod), PWO_spa_pod_object_pod,
    PtrUInt(@PSpaPodObject(nil)^.Body), PWO_spa_pod_object_body]);
  Lay('spa_pod_choice_body', SizeOf(TSpaPodChoiceBody), PWS_spa_pod_choice_body, [
    PtrUInt(@TSpaPodChoiceBody(nil^).ChoiceType), PWO_spa_pod_choice_body_type,
    PtrUInt(@TSpaPodChoiceBody(nil^).Flags), PWO_spa_pod_choice_body_flags,
    PtrUInt(@TSpaPodChoiceBody(nil^).Child), PWO_spa_pod_choice_body_child]);
  Lay('spa_pod_choice', SizeOf(TSpaPodChoice), PWS_spa_pod_choice, [
    PtrUInt(@PSpaPodChoice(nil)^.Pod), PWO_spa_pod_choice_pod,
    PtrUInt(@PSpaPodChoice(nil)^.Body), PWO_spa_pod_choice_body]);
  Lay('spa_pod_array_body', SizeOf(TSpaPodArrayBody), PWS_spa_pod_array_body, [
    PtrUInt(@TSpaPodArrayBody(nil^).Child), PWO_spa_pod_array_body_child]);
  Lay('spa_param_info', SizeOf(TSpaParamInfo), PWS_spa_param_info, [
    PtrUInt(@PSpaParamInfo(nil)^.Id), PWO_spa_param_info_id, PtrUInt(@PSpaParamInfo(nil)^.Flags), PWO_spa_param_info_flags,
    PtrUInt(@PSpaParamInfo(nil)^.User), PWO_spa_param_info_user, PtrUInt(@PSpaParamInfo(nil)^.Seq), PWO_spa_param_info_seq]);
  Lay('pw_core_info', SizeOf(TPWCoreInfo), PWS_pw_core_info, [
    PtrUInt(@PPWCoreInfo(nil)^.Id), PWO_pw_core_info_id, PtrUInt(@PPWCoreInfo(nil)^.Cookie), PWO_pw_core_info_cookie,
    PtrUInt(@PPWCoreInfo(nil)^.UserName), PWO_pw_core_info_user_name,
    PtrUInt(@PPWCoreInfo(nil)^.HostName), PWO_pw_core_info_host_name,
    PtrUInt(@PPWCoreInfo(nil)^.Version), PWO_pw_core_info_version, PtrUInt(@PPWCoreInfo(nil)^.Name), PWO_pw_core_info_name,
    PtrUInt(@PPWCoreInfo(nil)^.ChangeMask), PWO_pw_core_info_change_mask,
    PtrUInt(@PPWCoreInfo(nil)^.Props), PWO_pw_core_info_props]);
  Lay('pw_node_info', SizeOf(TPWNodeInfo), PWS_pw_node_info, [
    PtrUInt(@PPWNodeInfo(nil)^.Id), PWO_pw_node_info_id,
    PtrUInt(@PPWNodeInfo(nil)^.MaxInputPorts), PWO_pw_node_info_max_input_ports,
    PtrUInt(@PPWNodeInfo(nil)^.MaxOutputPorts), PWO_pw_node_info_max_output_ports,
    PtrUInt(@PPWNodeInfo(nil)^.ChangeMask), PWO_pw_node_info_change_mask,
    PtrUInt(@PPWNodeInfo(nil)^.NInputPorts), PWO_pw_node_info_n_input_ports,
    PtrUInt(@PPWNodeInfo(nil)^.NOutputPorts), PWO_pw_node_info_n_output_ports,
    PtrUInt(@PPWNodeInfo(nil)^.State), PWO_pw_node_info_state, PtrUInt(@PPWNodeInfo(nil)^.Error), PWO_pw_node_info_error,
    PtrUInt(@PPWNodeInfo(nil)^.Props), PWO_pw_node_info_props, PtrUInt(@PPWNodeInfo(nil)^.Params), PWO_pw_node_info_params,
    PtrUInt(@PPWNodeInfo(nil)^.NParams), PWO_pw_node_info_n_params]);
  Lay('pw_client_info', SizeOf(TPWClientInfo), PWS_pw_client_info, [
    PtrUInt(@PPWClientInfo(nil)^.Id), PWO_pw_client_info_id,
    PtrUInt(@PPWClientInfo(nil)^.ChangeMask), PWO_pw_client_info_change_mask,
    PtrUInt(@PPWClientInfo(nil)^.Props), PWO_pw_client_info_props]);
  Lay('pw_buffer', SizeOf(TPWBuffer), PWS_pw_buffer, [
    PtrUInt(@PPWBuffer(nil)^.Buffer), PWO_pw_buffer_buffer, PtrUInt(@PPWBuffer(nil)^.UserData), PWO_pw_buffer_user_data,
    PtrUInt(@PPWBuffer(nil)^.Size), PWO_pw_buffer_size, PtrUInt(@PPWBuffer(nil)^.Requested), PWO_pw_buffer_requested]);
  Lay('spa_buffer', SizeOf(TSpaBuffer), PWS_spa_buffer, [
    PtrUInt(@PSpaBuffer(nil)^.NMetas), PWO_spa_buffer_n_metas, PtrUInt(@PSpaBuffer(nil)^.NDatas), PWO_spa_buffer_n_datas,
    PtrUInt(@PSpaBuffer(nil)^.Metas), PWO_spa_buffer_metas, PtrUInt(@PSpaBuffer(nil)^.Datas), PWO_spa_buffer_datas]);
  Lay('spa_data', SizeOf(TSpaData), PWS_spa_data, [
    PtrUInt(@PSpaData(nil)^.DataType), PWO_spa_data_type, PtrUInt(@PSpaData(nil)^.Flags), PWO_spa_data_flags,
    PtrUInt(@PSpaData(nil)^.Fd), PWO_spa_data_fd, PtrUInt(@PSpaData(nil)^.MapOffset), PWO_spa_data_mapoffset,
    PtrUInt(@PSpaData(nil)^.MaxSize), PWO_spa_data_maxsize, PtrUInt(@PSpaData(nil)^.Data), PWO_spa_data_data,
    PtrUInt(@PSpaData(nil)^.Chunk), PWO_spa_data_chunk]);
  Lay('spa_chunk', SizeOf(TSpaChunk), PWS_spa_chunk, [
    PtrUInt(@PSpaChunk(nil)^.Offset), PWO_spa_chunk_offset, PtrUInt(@PSpaChunk(nil)^.Size), PWO_spa_chunk_size,
    PtrUInt(@PSpaChunk(nil)^.Stride), PWO_spa_chunk_stride, PtrUInt(@PSpaChunk(nil)^.Flags), PWO_spa_chunk_flags]);
  Lay('pw_core_events', SizeOf(TPWCoreEvents), PWS_pw_core_events, [
    PtrUInt(@PPWCoreEvents(nil)^.Version), PWO_pw_core_events_version, PtrUInt(@PPWCoreEvents(nil)^.Info), PWO_pw_core_events_info,
    PtrUInt(@PPWCoreEvents(nil)^.Done), PWO_pw_core_events_done, PtrUInt(@PPWCoreEvents(nil)^.Ping), PWO_pw_core_events_ping,
    PtrUInt(@PPWCoreEvents(nil)^.Error), PWO_pw_core_events_error,
    PtrUInt(@PPWCoreEvents(nil)^.RemoveId), PWO_pw_core_events_remove_id,
    PtrUInt(@PPWCoreEvents(nil)^.BoundId), PWO_pw_core_events_bound_id,
    PtrUInt(@PPWCoreEvents(nil)^.AddMem), PWO_pw_core_events_add_mem,
    PtrUInt(@PPWCoreEvents(nil)^.RemoveMem), PWO_pw_core_events_remove_mem,
    PtrUInt(@PPWCoreEvents(nil)^.BoundProps), PWO_pw_core_events_bound_props]);
  Lay('pw_core_methods', SizeOf(TPWCoreMethods), PWS_pw_core_methods, [
    PtrUInt(@PPWCoreMethods(nil)^.Version), PWO_pw_core_methods_version,
    PtrUInt(@PPWCoreMethods(nil)^.AddListener), PWO_pw_core_methods_add_listener,
    PtrUInt(@PPWCoreMethods(nil)^.Hello), PWO_pw_core_methods_hello, PtrUInt(@PPWCoreMethods(nil)^.Sync), PWO_pw_core_methods_sync,
    PtrUInt(@PPWCoreMethods(nil)^.Pong), PWO_pw_core_methods_pong, PtrUInt(@PPWCoreMethods(nil)^.Error), PWO_pw_core_methods_error,
    PtrUInt(@PPWCoreMethods(nil)^.GetRegistry), PWO_pw_core_methods_get_registry,
    PtrUInt(@PPWCoreMethods(nil)^.CreateObject), PWO_pw_core_methods_create_object,
    PtrUInt(@PPWCoreMethods(nil)^.Destroy), PWO_pw_core_methods_destroy]);
  Lay('pw_registry_events', SizeOf(TPWRegistryEvents), PWS_pw_registry_events, [
    PtrUInt(@PPWRegistryEvents(nil)^.Version), PWO_pw_registry_events_version,
    PtrUInt(@PPWRegistryEvents(nil)^.Global), PWO_pw_registry_events_global,
    PtrUInt(@PPWRegistryEvents(nil)^.GlobalRemove), PWO_pw_registry_events_global_remove]);
  Lay('pw_registry_methods', SizeOf(TPWRegistryMethods), PWS_pw_registry_methods, [
    PtrUInt(@PPWRegistryMethods(nil)^.Version), PWO_pw_registry_methods_version,
    PtrUInt(@PPWRegistryMethods(nil)^.AddListener), PWO_pw_registry_methods_add_listener,
    PtrUInt(@PPWRegistryMethods(nil)^.Bind), PWO_pw_registry_methods_bind,
    PtrUInt(@PPWRegistryMethods(nil)^.Destroy), PWO_pw_registry_methods_destroy]);
  Lay('pw_node_events', SizeOf(TPWNodeEvents), PWS_pw_node_events, [
    PtrUInt(@PPWNodeEvents(nil)^.Version), PWO_pw_node_events_version, PtrUInt(@PPWNodeEvents(nil)^.Info), PWO_pw_node_events_info,
    PtrUInt(@PPWNodeEvents(nil)^.Param), PWO_pw_node_events_param]);
  Lay('pw_node_methods', SizeOf(TPWNodeMethods), PWS_pw_node_methods, [
    PtrUInt(@PPWNodeMethods(nil)^.Version), PWO_pw_node_methods_version,
    PtrUInt(@PPWNodeMethods(nil)^.AddListener), PWO_pw_node_methods_add_listener,
    PtrUInt(@PPWNodeMethods(nil)^.SubscribeParams), PWO_pw_node_methods_subscribe_params,
    PtrUInt(@PPWNodeMethods(nil)^.EnumParams), PWO_pw_node_methods_enum_params,
    PtrUInt(@PPWNodeMethods(nil)^.SetParam), PWO_pw_node_methods_set_param,
    PtrUInt(@PPWNodeMethods(nil)^.SendCommand), PWO_pw_node_methods_send_command]);
  Lay('pw_metadata_events', SizeOf(TPWMetadataEvents), PWS_pw_metadata_events, [
    PtrUInt(@PPWMetadataEvents(nil)^.Version), PWO_pw_metadata_events_version,
    PtrUInt(@PPWMetadataEvents(nil)^.Property_), PWO_pw_metadata_events_property]);
  Lay('pw_client_events', SizeOf(TPWClientEvents), PWS_pw_client_events, [
    PtrUInt(@PPWClientEvents(nil)^.Version), PWO_pw_client_events_version,
    PtrUInt(@PPWClientEvents(nil)^.Info), PWO_pw_client_events_info,
    PtrUInt(@PPWClientEvents(nil)^.Permissions), PWO_pw_client_events_permissions]);
  Lay('pw_stream_events', SizeOf(TPWStreamEvents), PWS_pw_stream_events, [
    PtrUInt(@PPWStreamEvents(nil)^.Version), PWO_pw_stream_events_version,
    PtrUInt(@PPWStreamEvents(nil)^.Destroy), PWO_pw_stream_events_destroy,
    PtrUInt(@PPWStreamEvents(nil)^.StateChanged), PWO_pw_stream_events_state_changed,
    PtrUInt(@PPWStreamEvents(nil)^.ControlInfo), PWO_pw_stream_events_control_info,
    PtrUInt(@PPWStreamEvents(nil)^.IoChanged), PWO_pw_stream_events_io_changed,
    PtrUInt(@PPWStreamEvents(nil)^.ParamChanged), PWO_pw_stream_events_param_changed,
    PtrUInt(@PPWStreamEvents(nil)^.AddBuffer), PWO_pw_stream_events_add_buffer,
    PtrUInt(@PPWStreamEvents(nil)^.RemoveBuffer), PWO_pw_stream_events_remove_buffer,
    PtrUInt(@PPWStreamEvents(nil)^.Process), PWO_pw_stream_events_process,
    PtrUInt(@PPWStreamEvents(nil)^.Drained), PWO_pw_stream_events_drained,
    PtrUInt(@PPWStreamEvents(nil)^.Command), PWO_pw_stream_events_command,
    PtrUInt(@PPWStreamEvents(nil)^.TriggerDone), PWO_pw_stream_events_trigger_done]);
end;

{ ---- 2. メソッドの呼び出し ---- }

var
  SeenObject: Pointer;
  SeenA, SeenB: LongWord;
  SeenSeq: cint;
  SeenPtr: Pointer;
  SeenSize: csize_t;

function FakeSync(AObject: Pointer; AId: LongWord; ASeq: cint): cint; cdecl;
begin
  SeenObject := AObject;
  SeenA := AId;
  SeenSeq := ASeq;
  Result := 77;
end;

function FakeCoreAddListener(AObject: Pointer; AListener: PSpaHook; AEvents: PPWCoreEvents;
  AData: Pointer): cint; cdecl;
begin
  SeenObject := AObject;
  SeenPtr := AListener;
  Result := 5;
end;

function FakeGetRegistry(AObject: Pointer; AVersion: LongWord; AUserDataSize: csize_t): PPWRegistry; cdecl;
begin
  SeenObject := AObject;
  SeenA := AVersion;
  SeenSize := AUserDataSize;
  Result := PPWRegistry(PtrUInt($ABC0));
end;

function FakeBind(AObject: Pointer; AId: LongWord; AType: PChar; AVersion: LongWord;
  AUserDataSize: csize_t): Pointer; cdecl;
begin
  SeenObject := AObject;
  SeenA := AId;
  SeenB := AVersion;
  SeenSize := AUserDataSize;
  SeenPtr := AType;
  Result := Pointer(PtrUInt($DEF0));
end;

function FakeRegAddListener(AObject: Pointer; AListener: PSpaHook; AEvents: PPWRegistryEvents;
  AData: Pointer): cint; cdecl;
begin
  SeenObject := AObject;
  SeenPtr := AData;
  Result := 6;
end;

function FakeEnumParams(AObject: Pointer; ASeq: cint; AId, AStart, ANum: LongWord; AFilter: PSpaPod): cint; cdecl;
begin
  SeenObject := AObject;
  SeenSeq := ASeq;
  SeenA := AId;
  SeenB := AStart + ANum * 100;
  Result := 9;
end;

procedure TestMethods;
var
  Iface: TSpaInterface;
  CoreM: TPWCoreMethods;
  RegM: TPWRegistryMethods;
  NodeM: TPWNodeMethods;
  Hook: TSpaHook;
  Name: PChar;
begin
  WriteLn('-- メソッドの呼び出し（spa_api_method_r）');
  Iface := Default(TSpaInterface);
  CoreM := Default(TPWCoreMethods);
  CoreM.Sync := @FakeSync;
  CoreM.AddListener := @FakeCoreAddListener;
  CoreM.GetRegistry := @FakeGetRegistry;
  Iface.Cb.Funcs := @CoreM;
  Iface.Cb.Data := Pointer(PtrUInt($1234));
  SeenObject := nil;
  Check((PMLPWCoreSync(PPWCore(@Iface), PW_ID_CORE, 9) = 77) and (SeenObject = Pointer(PtrUInt($1234)))
    and (SeenA = PW_ID_CORE) and (SeenSeq = 9), 'pw_core_sync は表の関数に相手のデータと引数を渡す');
  Check((PMLPWCoreAddListener(PPWCore(@Iface), @Hook, nil, nil) = 5) and (SeenPtr = @Hook), 'pw_core_add_listener');
  Check((PMLPWCoreGetRegistry(PPWCore(@Iface), PW_VERSION_REGISTRY, 0) = PPWRegistry(PtrUInt($ABC0)))
    and (SeenA = PW_VERSION_REGISTRY) and (SeenSize = 0), 'pw_core_get_registry');
  CoreM.Sync := nil;
  Check(PMLPWCoreSync(PPWCore(@Iface), PW_ID_CORE, 1) = -ENOTSUP, '関数が無ければ -ENOTSUP');
  Iface.Cb.Funcs := nil;
  Check(PMLPWCoreGetRegistry(PPWCore(@Iface), 3, 0) = nil, '表が無ければ nil');

  RegM := Default(TPWRegistryMethods);
  RegM.Bind := @FakeBind;
  RegM.AddListener := @FakeRegAddListener;
  Iface.Cb.Funcs := @RegM;
  Iface.Cb.Data := Pointer(PtrUInt($5678));
  Name := 'PipeWire:Interface:Node';
  Check((PMLPWRegistryBind(PPWRegistry(@Iface), 42, Name, 3, 128) = PPWProxy(PtrUInt($DEF0)))
    and (SeenObject = Pointer(PtrUInt($5678))) and (SeenA = 42) and (SeenB = 3) and (SeenSize = 128)
    and (SeenPtr = Name), 'pw_registry_bind');
  Check((PMLPWRegistryAddListener(PPWRegistry(@Iface), @Hook, nil, Pointer(PtrUInt($99))) = 6)
    and (SeenPtr = Pointer(PtrUInt($99))), 'pw_registry_add_listener');

  NodeM := Default(TPWNodeMethods);
  NodeM.EnumParams := @FakeEnumParams;
  Iface.Cb.Funcs := @NodeM;
  Check((PMLPWNodeEnumParams(PPWProxy(@Iface), 3, SPA_PARAM_EnumFormat, 1, 2, nil) = 9) and (SeenSeq = 3)
    and (SeenA = SPA_PARAM_EnumFormat) and (SeenB = 201), 'pw_node_enum_params');
  // 版の確かめ（SPA_CALLBACK_VERSION_MIN）。この関数たちは版 0 を求めるので、表の版によらず呼ぶ。
  NodeM.Version := 0;
  Check(PMLPWNodeEnumParams(PPWProxy(@Iface), 0, 0, 0, 0, nil) = 9, '表の版が 0 でも呼ぶ');
end;

{ ---- 3. hook と dict ---- }

var
  RemovedHook: PSpaHook;

procedure OnRemoved(AHook: PSpaHook); cdecl;
begin
  RemovedHook := AHook;
end;

procedure TestHookAndDict;
var
  Head: TSpaList;
  H1, H2: TSpaHook;
  Items: array[0..2] of TSpaDictItem;
  Dict: TSpaDict;
begin
  WriteLn('-- spa_hook_remove と spa_dict_lookup');
  PMLSpaListInit(Head);
  Check((Head.Next = @Head) and (Head.Prev = @Head), 'spa_list_init は自分を指す');
  H1 := Default(TSpaHook);
  H2 := Default(TSpaHook);
  // 頭 → H1 → H2 → 頭
  Head.Next := @H1.Link;
  H1.Link.Prev := @Head;
  H1.Link.Next := @H2.Link;
  H2.Link.Prev := @H1.Link;
  H2.Link.Next := @Head;
  Head.Prev := @H2.Link;
  H1.Removed := @OnRemoved;
  RemovedHook := nil;
  PMLSpaHookRemove(@H1);
  Check((Head.Next = @H2.Link) and (H2.Link.Prev = @Head) and (RemovedHook = @H1),
    'spa_hook_remove はつながりから外し、removed を呼ぶ');
  H1 := Default(TSpaHook);   // 初期化されていない（prev が nil）
  H1.Removed := @OnRemoved;
  RemovedHook := nil;
  PMLSpaHookRemove(@H1);
  Check((RemovedHook = @H1) and (Head.Next = @H2.Link), '初期化されていない hook は外さず、removed だけ呼ぶ');

  Items[0].Key := 'media.class';
  Items[0].Value := 'Audio/Sink';
  Items[1].Key := 'node.name';
  Items[1].Value := 'alsa_output';
  Items[2].Key := 'audio.channels';
  Items[2].Value := '2';
  Dict.Flags := 0;
  Dict.NItems := 3;
  Dict.Items := @Items[0];
  Check((PMLSpaDictLookup(@Dict, 'node.name') <> nil)
    and (StrComp(PMLSpaDictLookup(@Dict, 'node.name'), 'alsa_output') = 0), 'spa_dict_lookup');
  Check(PMLSpaDictLookup(@Dict, 'node.nam') = nil, '無い鍵は nil');
  Dict.NItems := 2;
  Check(PMLSpaDictLookup(@Dict, 'audio.channels') = nil, 'NItems の外は見ない');
end;

{ ---- 4〜6. pod と JSON ---- }

function ToHex(const ABytes: TBytes): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(ABytes) do
    Result := Result + LowerCase(IntToHex(ABytes[I], 2));
end;

{ 16 進の文字列を 8 バイト境界の置き場に入れる（pod は 8 バイトに揃っている前提）。 }
procedure FromHex(const AHex: String; var ABuf: array of QWord);
var
  I: Integer;
  P: PByte;
begin
  FillChar(ABuf[0], Length(ABuf) * 8, 0);
  P := @ABuf[0];
  for I := 0 to (Length(AHex) div 2) - 1 do
    P[I] := StrToInt('$' + Copy(AHex, I * 2 + 1, 2));
end;

procedure TestPods;
var
  I, J: Integer;
  Got: String;
  Buf: array[0..127] of QWord;
  Def, Mn, Mx, Ch: Integer;
  ROk, COk: Boolean;
  First, Last, Again: PSpaPodProp;
begin
  WriteLn('-- pod の組み立て（SDL の initialize_spa_info と spa_format_audio_raw_build）');
  for I := 0 to High(PWBuild) do
  begin
    Got := ToHex(PMLPipeWireBuildFormat(TPMLAudioSpec.Make(PWBuild[I].Format, PWBuild[I].Channels,
      PWBuild[I].Freq), SPA_PARAM_EnumFormat));
    Check(Got = PWBuild[I].Hex, PWBuild[I].Name + ' のバイト列が C と同じ（' + IntToStr(Length(Got) div 2) + ' バイト）');
  end;

  WriteLn('-- pod の読み取り（SDL の get_range_param / get_int_param）');
  for I := 0 to High(PWParse) do
  begin
    FromHex(PWParse[I].Hex, Buf);
    Def := -1;
    Mn := -1;
    Mx := -1;
    Ch := -1;
    ROk := PMLPipeWireGetRangeParam(PSpaPod(@Buf[0]), SPA_FORMAT_AUDIO_rate, Def, Mn, Mx);
    COk := PMLPipeWireGetIntParam(PSpaPod(@Buf[0]), SPA_FORMAT_AUDIO_channels, Ch);
    Check((ROk = PWParse[I].RateOk) and (Def = PWParse[I].RateDef) and (Mn = PWParse[I].RateMin)
      and (Mx = PWParse[I].RateMax) and (COk = PWParse[I].ChannelsOk) and (Ch = PWParse[I].Channels),
      Format('%s: rate %s %d %d %d、channels %s %d', [PWParse[I].Name, BoolToStr(ROk, True), Def, Mn, Mx,
        BoolToStr(COk, True), Ch]));
  end;

  // spa_pod_find_prop の始点: 始点の次から終わりまで探し、無ければ頭から始点の次の手前まで。
  J := -1;
  for I := 0 to High(PWParse) do
    if PWParse[I].Name = 'rate_after_others' then
      J := I;
  FromHex(PWParse[J].Hex, Buf);
  First := PMLSpaPodFindProp(PSpaPod(@Buf[0]), nil, SPA_FORMAT_mediaType);
  Last := PMLSpaPodFindProp(PSpaPod(@Buf[0]), nil, SPA_FORMAT_AUDIO_rate);
  Again := PMLSpaPodFindProp(PSpaPod(@Buf[0]), Last, SPA_FORMAT_mediaType);
  Check((First <> nil) and (Last <> nil) and (Again = First), 'find_prop: 最後の次からは頭へ戻って探す');
  Check(PMLSpaPodFindProp(PSpaPod(@Buf[0]), Last, SPA_FORMAT_AUDIO_rate) = Last,
    'find_prop: 始点そのものも、頭から回って見つかる');
  Check(PMLSpaPodFindProp(PSpaPod(@Buf[0]), First, SPA_FORMAT_AUDIO_format) = nil, 'find_prop: 無い鍵は nil');
end;

{ 入れ物に入ってから spa_json_next を繰り返し、「長さ:16 進|」の並びと最後の戻り値を返す（生成器の C と同じ）。 }
function TokenDump(const AInput: String): String;
var
  It: array[0..1] of TSpaJson;
  V: PChar;
  R, N, K: Integer;
begin
  PMLSpaJsonInit(It[0], PChar(AInput), Length(AInput));
  if (AInput <> '') and (AInput[1] = '[') then
    R := PMLSpaJsonEnterArray(It[0], It[1])
  else
    R := PMLSpaJsonEnterObject(It[0], It[1]);
  Result := '';
  if R > 0 then
  begin
    N := 0;
    while True do
    begin
      Inc(N);
      if N > 40 then
        Break;
      R := PMLSpaJsonNext(It[1], V);
      if R <= 0 then
        Break;
      Result := Result + IntToStr(R) + ':';
      for K := 0 to R - 1 do
        Result := Result + LowerCase(IntToHex(Ord(V[K]), 2));
      Result := Result + '|';
    end;
  end;
  Result := Result + '=' + IntToStr(R);
end;

procedure TestJson;
var
  I: Integer;
  Name, Got: String;
  Found: Boolean;
begin
  WriteLn('-- JSON（SDL の get_name_from_json）');
  for I := 0 to High(PWJsonNames) do
  begin
    Found := PMLPipeWireNameFromJson(PChar(PWJsonNames[I].Input), Name);
    Check((Found = PWJsonNames[I].Found) and (Name = PWJsonNames[I].Output),
      Format('%d: %s → %s "%s"', [I, Copy(PWJsonNames[I].Input, 1, 40), BoolToStr(Found, True), Copy(Name, 1, 40)]));
  end;
  WriteLn('-- JSON（SDL の client_info の session.services）');
  for I := 0 to High(PWJsonServices) do
    Check(PMLPipeWireServicesHaveAudio(PChar(PWJsonServices[I].Input)) = PWJsonServices[I].HaveAudio,
      Format('%d: %s → audio %s', [I, PWJsonServices[I].Input, BoolToStr(PWJsonServices[I].HaveAudio, True)]));
  WriteLn('-- JSON（spa_json_next の 1 トークンずつ）');
  for I := 0 to High(PWJsonTokens) do
  begin
    Got := TokenDump(PWJsonTokens[I].Input);
    Check(Got = PWJsonTokens[I].Tokens, Format('%d: %s → %s', [I, PWJsonTokens[I].Input, Got]));
  end;
end;

{ ---- 7. ライブラリ ---- }

procedure TestLibrary;
var
  PW: TPMLPipeWire;
  Version: String;
begin
  WriteLn('-- libpipewire-0.3.so.0');
  if not TPMLPipeWire.IsAvailable then
  begin
    if GetEnvironmentVariable('PAPIMELA_PIPEWIRE_OPTIONAL') = '1' then
    begin
      WriteLn('  [SKIP] libpipewire-0.3.so.0 が無い（PAPIMELA_PIPEWIRE_OPTIONAL=1）');
      Exit;
    end;
    Check(False, 'libpipewire-0.3.so.0 がある（無い環境では PAPIMELA_PIPEWIRE_OPTIONAL=1）');
    Exit;
  end;
  PW := nil;
  try
    try
      PW := TPMLPipeWire.Create;
      Check(Assigned(PW.API.init) and Assigned(PW.API.thread_loop_new) and Assigned(PW.API.stream_new_simple)
        and Assigned(PW.API.properties_new) and Assigned(PW.API.stream_update_properties),
        'SDL が使う関数が全部結合できる');
      Version := StrPas(PW.API.get_library_version());
      Check(Version <> '', 'pw_get_library_version: ' + Version);
    except
      on E: Exception do
        Check(False, '結合できない: ' + E.Message);
    end;
  finally
    PW.Free;
  end;
end;

begin
  WriteLn('=== test_pipewire_abi ===');
  try
    TestLayouts;
    TestMethods;
    TestHookAndDict;
    TestPods;
    TestJson;
    TestLibrary;
  except
    on E: Exception do
    begin
      WriteLn('  [FAIL] 例外: ', E.ClassName, ': ', E.Message);
      Inc(Failures);
    end;
  end;
  if Failures = 0 then
    WriteLn('=== 全部通った ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
