program CheckStub;

{ The checksum program the Checksum Applet area of Offline Backup makes (from the Checksum Applet Creator's applet).
  Offline Backup copies this exe next to a checksum list, adds an icon and a small configuration resource (CHKCFG),
  and the result checks every file listed in the list. Plain Win32 API, no VCL or LCL, so it stays small. Hashing
  runs on a worker thread; the UI never blocks. Builds with Delphi (delphiuild.cmd) and Free Pascal
  (lazarusuild.cmd); each edition keeps its own build of it as the RCDATA resource CHECKSTUB. }

{$APPTYPE GUI}
{$IFDEF FPC}{$mode delphiunicode}{$H+}{$ENDIF}
{$R CheckStub.res}
{$Q-,R-,O+}

uses
  Windows, Messages, ShellAPI, CommCtrl, Hashes, Digests;

{$IFDEF FPC}
const
  SS_ENDELLIPSIS = $4000;      // not in Free Pascal's Windows unit
  SS_PATHELLIPSIS = $8000;

type
  // Free Pascal's Windows unit has only the ANSI form
  TNonClientMetricsW = record
    cbSize: UINT;
    iBorderWidth, iScrollWidth, iScrollHeight, iCaptionWidth, iCaptionHeight: Integer;
    lfCaptionFont: TLogFontW;
    iSmCaptionWidth, iSmCaptionHeight: Integer;
    lfSmCaptionFont: TLogFontW;
    iMenuWidth, iMenuHeight: Integer;
    lfMenuFont, lfStatusFont, lfMessageFont: TLogFontW;
    iPaddedBorderWidth: Integer;
  end;
{$ENDIF}

const
  ID_STATUS = 101;
  ID_FILE   = 102;
  ID_PROG   = 103;
  ID_LIST   = 104;
  ID_STOP   = 105;
  ID_COPY   = 106;
  ID_REPORT = 107;
  ID_BRAND  = 108;
  ID_LINK   = 109;
  BrandUrl  = 'http://www.level103.com';
  TIMER_UI  = 1;
  WM_ALLDONE = WM_APP + 1;

  ST_PENDING = 0;
  ST_OK      = 1;
  ST_BAD     = 2;
  ST_MISSING = 3;
  ST_ERROR   = 4;

  CLASS_NAME = 'ChecksumApplet';

function SetWindowTheme(hwnd: HWND; pszSubAppName, pszSubIdList: LPCWSTR): HRESULT; stdcall;
  external 'uxtheme.dll';

var
  Wnd, hBrand, hLink, hStatus, hFile, hProg, hList, hStop, hCopy, hReport: HWND;
  Font, BigFont, LinkFont: HFONT;
  Dpi: Integer;
  BaseDir, DigestName, AppTitle: string;
  Created: string;           // when the list was made, 'yyyy-mm-dd hh:nn' ('' for a program made before 0.11)
  Algo: THashAlgo;
  Entries: TDigestEntries;
  Results: array of Byte;
  Sizes: array of Int64;
  AbortFlag: LongInt;
  Running: Boolean;
  Interrupted: Boolean;
  WorkerDone: LongInt;
  DoneCount: LongInt;        // written by worker
  CurIndex: LongInt;         // written by worker
  BytesDone, TotalBytes: Int64;
  StartTick: UInt64;
  EndTick: UInt64;
  Scanned: Integer;          // UI side: results already tallied
  CntOK, CntBad, CntMissing, CntError: Integer;
  SummaryColor: COLORREF;
  SummaryText, DetailText: string;
  LastPermille: Integer;
  LogPath: string;
  ExitCodeVal: Integer;

function S(X: Integer): Integer;
begin
  Result := MulDiv(X, Dpi, 96);
end;

function IStr(N: Int64): string;
var
  T: ShortString;
begin
  Str(N, T);
  Result := string(T);
end;

function GroupDigits(N: Int64): string;
var
  T: string;
  I, C: Integer;
begin
  T := IStr(N);
  Result := '';
  C := 0;
  for I := Length(T) downto 1 do
  begin
    if (C > 0) and (C mod 3 = 0) then Result := ',' + Result;
    Result := T[I] + Result;
    Inc(C);
  end;
end;

function FmtBytes(N: Int64): string;
var
  V: Double;
  U: Integer;
  T: ShortString;
const
  Units: array[0..4] of string = (' bytes', ' KB', ' MB', ' GB', ' TB');
begin
  if N < 1024 then
  begin
    Result := IStr(N) + ' bytes';
    Exit;
  end;
  V := N;
  U := 0;
  while (V >= 1024) and (U < 4) do
  begin
    V := V / 1024;
    Inc(U);
  end;
  Str(V:0:1, T);
  Result := string(T) + Units[U];
end;

function FmtTime(Ms: UInt64): string;
var Sec: UInt64;
begin
  Sec := Ms div 1000;
  if Sec < 60 then
    Result := IStr(Sec) + ' s'
  else if Sec < 3600 then
    Result := IStr(Sec div 60) + ' min ' + IStr(Sec mod 60) + ' s'
  else
    Result := IStr(Sec div 3600) + ' h ' + IStr((Sec mod 3600) div 60) + ' min';
end;

procedure Fail(const Msg: string);
begin
  MessageBoxW(0, PWideChar(Msg), 'Checksum', MB_OK or MB_ICONERROR);
  ExitProcess(2);
end;

function ReadWholeFile(const Path: string; out Data: RawByteString): Boolean;
var
  H: THandle;
  Size, Got: DWORD;
begin
  Result := False;
  Data := '';
  H := CreateFileW(PWideChar(Path), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE,
    nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if H = INVALID_HANDLE_VALUE then Exit;
  Size := GetFileSize(H, nil);
  if (Size <> INVALID_FILE_SIZE) and (Size < 256 * 1024 * 1024) then
  begin
    SetLength(Data, Size);
    if Size = 0 then
      Result := True
    else
      Result := ReadFile(H, Data[1], Size, Got, nil) and (Got = Size);
  end;
  CloseHandle(H);
end;

function LongPath(const P: string): string;
begin
  if (Length(P) > 240) and (Copy(P, 1, 2) <> '\\') then
    Result := '\\?\' + P
  else
    Result := P;
end;

{ ------------------------------------------------------------ configuration }

function CfgValue(const Cfg, Key: string): string;
var
  I, Start, EndPos: Integer;
  Line: string;
begin
  Result := '';
  I := 1;
  while I <= Length(Cfg) do
  begin
    Start := I;
    while (I <= Length(Cfg)) and (Cfg[I] <> #10) and (Cfg[I] <> #13) do Inc(I);
    EndPos := I;
    Line := Copy(Cfg, Start, EndPos - Start);
    if (Length(Line) > Length(Key) + 1) and (Copy(Line, 1, Length(Key) + 1) = Key + '=') then
    begin
      Result := Copy(Line, Length(Key) + 2, MaxInt);
      Exit;
    end;
    while (I <= Length(Cfg)) and ((Cfg[I] = #10) or (Cfg[I] = #13)) do Inc(I);
  end;
end;

procedure LoadConfiguration;
var
  Res: HRSRC;
  Mem: HGLOBAL;
  P: Pointer;
  N: DWORD;
  Raw: RawByteString;
  Cfg, AlgoName: string;
  Buf: array[0..MAX_PATH * 2] of WideChar;
  I, L: Integer;
  Data: RawByteString;
  Text: string;
begin
  Res := FindResourceW(HInstance, 'CHKCFG', PWideChar(RT_RCDATA));
  if Res = 0 then Fail('This checksum program has not been set up.' + #13#10 +
    'It is made by the Checksum Applet area of Offline Backup.');
  Mem := LoadResource(HInstance, Res);
  P := LockResource(Mem);
  N := SizeofResource(HInstance, Res);
  SetLength(Raw, N);
  Move(P^, Raw[1], N);
  Cfg := DecodeText(Raw);
  DigestName := CfgValue(Cfg, 'digest');
  AlgoName := CfgValue(Cfg, 'algo');
  AppTitle := CfgValue(Cfg, 'title');
  Created := CfgValue(Cfg, 'created');
  if (DigestName = '') or not HashAlgoByName(AlgoName, Algo) then
    Fail('The applet configuration is damaged.');

  L := GetModuleFileNameW(0, Buf, Length(Buf));
  I := L;
  while (I > 0) and (Buf[I - 1] <> '\') do Dec(I);
  SetString(BaseDir, Buf, I);

  if not ReadWholeFile(LongPath(BaseDir + DigestName), Data) then
    Fail('The digest file "' + DigestName + '" was not found.' + #13#10#13#10 +
      'It must be in the same folder as this program:' + #13#10 + BaseDir);
  Text := DecodeText(Data);
  if ParseDigest(Text, Algo, Entries) = 0 then
    Fail('The digest file "' + DigestName + '" does not list any files.');
  if AppTitle = '' then AppTitle := DigestName;
end;

{ ------------------------------------------------------------------ worker }

function Worker(Param: Pointer): {$IFDEF FPC}PtrInt{$ELSE}Integer{$ENDIF};
var
  H: THasher;
  Buf: Pointer;
  I: Integer;
  Hnd: THandle;
  Got: DWORD;
  Path: string;
  D: TDigest;
  Err: DWORD;
  Ok: Boolean;
  FAD: TWin32FileAttributeData;
begin
  H := NewHasher(Algo);
  GetMem(Buf, 1024 * 1024);
  TotalBytes := 0;
  for I := 0 to High(Entries) do
  begin
    Sizes[I] := -1;
    if GetFileAttributesExW(PWideChar(LongPath(BaseDir + Entries[I].Name)), GetFileExInfoStandard, @FAD) then
    begin
      Sizes[I] := (Int64(FAD.nFileSizeHigh) shl 32) or FAD.nFileSizeLow;
      Inc(TotalBytes, Sizes[I]);
    end;
  end;
  for I := 0 to High(Entries) do
  begin
    if AbortFlag <> 0 then Break;
    CurIndex := I;
    Path := LongPath(BaseDir + Entries[I].Name);
    Hnd := CreateFileW(PWideChar(Path), GENERIC_READ,
      FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
      FILE_FLAG_SEQUENTIAL_SCAN, 0);
    if Hnd = INVALID_HANDLE_VALUE then
    begin
      Err := GetLastError;
      if (Err = ERROR_FILE_NOT_FOUND) or (Err = ERROR_PATH_NOT_FOUND) then
        Results[I] := ST_MISSING
      else
        Results[I] := ST_ERROR;
    end
    else
    begin
      H.Reset;
      Ok := True;
      while True do
      begin
        if AbortFlag <> 0 then Break;
        if not ReadFile(Hnd, Buf^, 1024 * 1024, Got, nil) then
        begin
          Ok := False;
          Break;
        end;
        if Got = 0 then Break;
        H.Update(Buf, Got);
        Inc(BytesDone, Got);
      end;
      CloseHandle(Hnd);
      if AbortFlag <> 0 then Break;
      if not Ok then
        Results[I] := ST_ERROR
      else
      begin
        H.Final(D);
        if DigestsEqual(D, Entries[I].Hash) then Results[I] := ST_OK else Results[I] := ST_BAD;
      end;
    end;
    DoneCount := I + 1;
  end;
  FreeMem(Buf);
  H.Free;
  Interrupted := AbortFlag <> 0;
  InterlockedExchange(WorkerDone, 1);
  PostMessage(Wnd, WM_ALLDONE, 0, 0);
  Result := 0;
end;

{ -------------------------------------------------------------------- UI }

function StatusText(St: Integer): string;
begin
  case St of
    ST_OK: Result := 'OK';
    ST_BAD: Result := 'Checksum mismatch';
    ST_MISSING: Result := 'File missing';
    ST_ERROR: Result := 'Read error';
  else
    Result := '';
  end;
end;

procedure Tally;
begin
  while Scanned < DoneCount do
  begin
    case Results[Scanned] of
      ST_OK: Inc(CntOK);
      ST_BAD: Inc(CntBad);
      ST_MISSING: Inc(CntMissing);
      ST_ERROR: Inc(CntError);
    end;
    Inc(Scanned);
  end;
end;

procedure SetText(H: HWND; const T: string);
begin
  SetWindowTextW(H, PWideChar(T));
end;

procedure BuildSummary;
var Bad: Integer; Tested: Integer;
begin
  Tested := Scanned;
  Bad := CntBad + CntMissing + CntError;
  DetailText := GroupDigits(Tested) + ' file' ;
  if Tested <> 1 then DetailText := DetailText + 's';
  DetailText := DetailText + ' tested, ' + FmtBytes(BytesDone) + ' in ' + FmtTime(EndTick - StartTick) + '  (' + HashNames[Algo] + ')';
  if Interrupted then
  begin
    SummaryColor := GetSysColor(COLOR_WINDOWTEXT);
    SummaryText := 'Stopped after ' + GroupDigits(Tested) + ' of ' + GroupDigits(Length(Entries)) + ' files';
    if Bad > 0 then SummaryText := SummaryText + ' - problems found: ' + GroupDigits(Bad);
  end
  else if Bad = 0 then
  begin
    SummaryColor := RGB(0, 128, 0);
    if Tested = 1 then SummaryText := 'The file is OK' else SummaryText := 'Every file is OK';
  end
  else
  begin
    SummaryColor := RGB(192, 0, 0);
    SummaryText := GroupDigits(Bad) + ' of ' + GroupDigits(Length(Entries)) + ' file' ;
    if Length(Entries) <> 1 then SummaryText := SummaryText + 's';
    SummaryText := SummaryText + ' did not verify';
  end;
end;

procedure RefreshUI;
var
  Permille: Integer;
  Cur: Integer;
begin
  Tally;
  if Running then
  begin
    if TotalBytes > 0 then
      Permille := Integer((BytesDone * 1000) div TotalBytes)
    else if Length(Entries) > 0 then
      Permille := (DoneCount * 1000) div Length(Entries)
    else
      Permille := 1000;
    if Permille > 1000 then Permille := 1000;
    if Permille <> LastPermille then
    begin
      SendMessage(hProg, PBM_SETPOS, Permille, 0);
      LastPermille := Permille;
    end;
    SetText(hStatus, 'Testing files...  ' + GroupDigits(Scanned) + ' of ' + GroupDigits(Length(Entries)));
    Cur := CurIndex;
    if (Cur >= 0) and (Cur < Length(Entries)) then SetText(hFile, Entries[Cur].Name);
    SummaryColor := GetSysColor(COLOR_WINDOWTEXT);
  end;
  if Scanned > 0 then
  begin
    SendMessage(hList, LVM_REDRAWITEMS, 0, Scanned - 1);
    if Running then SendMessage(hList, LVM_ENSUREVISIBLE, Scanned - 1, 0);
  end;
end;

procedure WriteLog; forward;
function BuildReport: string; forward;

procedure FinishUI;
var
  I: Integer;
begin
  KillTimer(Wnd, TIMER_UI);
  EndTick := GetTickCount64;
  Running := False;
  Tally;
  BuildSummary;
  SetText(hStatus, SummaryText);
  SetText(hFile, DetailText);
  SetText(hStop, 'Close');
  SetText(hReport, BuildReport);
  ShowWindow(hList, SW_HIDE);
  ShowWindow(hReport, SW_SHOW);
  if not Interrupted then SendMessage(hProg, PBM_SETPOS, 1000, 0);
  InvalidateRect(hStatus, nil, True);
  SendMessage(hList, LVM_REDRAWITEMS, 0, Length(Entries) - 1);
  if (CntBad + CntMissing + CntError) > 0 then
  begin
    // jump to the first problem
    for I := 0 to Scanned - 1 do
      if Results[I] >= ST_BAD then
      begin
        SendMessage(hList, LVM_ENSUREVISIBLE, I, 0);
        Break;
      end;
  end;
  if Interrupted then ExitCodeVal := 3
  else if (CntBad + CntMissing + CntError) > 0 then ExitCodeVal := 1
  else ExitCodeVal := 0;
  if LogPath <> '' then
  begin
    WriteLog;
    DestroyWindow(Wnd);
  end
  else
    MessageBeep(MB_OK);
end;

function UpperStatus(St: Integer): string;
begin
  case St of
    ST_OK: Result := 'OK';
    ST_BAD: Result := 'FAILED';
    ST_MISSING: Result := 'MISSING';
    ST_ERROR: Result := 'ERROR';
  else
    Result := '';
  end;
end;

{ 'yyyy-mm-dd hh:nn' as 'Nov 23, 2026 10:47 PM' - the same on every PC; '' if it is not such a date }
function FriendlyDate(const S: string): string;
const
  Months: array[1..12] of string = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
var
  Y, Mo, D, H, Mi, Code: Integer;
  AmPm: string;
begin
  Result := '';
  if (Length(S) <> 16) or (S[5] <> '-') or (S[8] <> '-') or (S[11] <> ' ') or (S[14] <> ':') then Exit;
  Val(Copy(S, 1, 4), Y, Code); if Code <> 0 then Exit;
  Val(Copy(S, 6, 2), Mo, Code); if (Code <> 0) or (Mo < 1) or (Mo > 12) then Exit;
  Val(Copy(S, 9, 2), D, Code); if Code <> 0 then Exit;
  Val(Copy(S, 12, 2), H, Code); if (Code <> 0) or (H > 23) then Exit;
  Val(Copy(S, 15, 2), Mi, Code); if (Code <> 0) or (Mi > 59) then Exit;
  if H < 12 then AmPm := ' AM' else AmPm := ' PM';
  if H mod 12 = 0 then H := 12 else H := H mod 12;
  Result := Months[Mo] + ' ' + IStr(D) + ', ' + IStr(Y) + '  ' + IStr(H) + ':' + Copy(S, 15, 2) + AmPm;
end;

function BuildReport: string;
var
  I, Bad: Integer;
  Algo_: string;
begin
  Algo_ := HashNames[Algo];
  Bad := CntBad + CntMissing + CntError;
  Result := 'Testing files in digest: ' + BaseDir + DigestName + #13#10#13#10 + 'SUMMARY:' + #13#10;
  if Interrupted then
    Result := Result + 'TESTING WAS STOPPED before all files were checked.' + #13#10
  else if Bad = 0 then
    Result := Result + 'EVERY FILE APPEARS TO BE OK (no errors).' + #13#10
  else
    Result := Result + 'PROBLEMS WERE FOUND - ' + GroupDigits(Bad) + ' file(s) did not verify - see PROBLEM FILES below.' + #13#10;
  Result := Result + #9 + GroupDigits(CntOK) + ' file(s) passed checksum validation.' + #13#10;
  if CntBad > 0 then Result := Result + #9 + GroupDigits(CntBad) + ' file(s) FAILED (checksum does not match).' + #13#10;
  if CntMissing > 0 then Result := Result + #9 + GroupDigits(CntMissing) + ' file(s) are MISSING.' + #13#10;
  if CntError > 0 then Result := Result + #9 + GroupDigits(CntError) + ' file(s) could not be read.' + #13#10;
  if Interrupted then Result := Result + #9 + GroupDigits(Length(Entries) - Scanned) + ' file(s) were not tested.' + #13#10;
  Result := Result + #9 + DetailText + #13#10;
  if FriendlyDate(Created) <> '' then
    Result := Result + #9 + 'Checksums created: ' + FriendlyDate(Created) + #13#10;
  if Bad > 0 then
  begin
    Result := Result + #13#10 + 'PROBLEM FILES:' + #13#10;
    for I := 0 to Scanned - 1 do
      if Results[I] >= ST_BAD then
        Result := Result + UpperStatus(Results[I]) + #9 + Algo_ + #9 + Entries[I].Name + #13#10;
  end;
  Result := Result + #13#10 + 'DETAILED REPORT:' + #13#10;
  for I := 0 to Scanned - 1 do
    Result := Result + UpperStatus(Results[I]) + #9 + Algo_ + #9 + Entries[I].Name + #13#10;
end;

procedure CopyReport;
var
  T: string;
  Mem: HGLOBAL;
  P: Pointer;
  Bytes: NativeInt;
begin
  T := BuildReport;
  if not OpenClipboard(Wnd) then Exit;
  EmptyClipboard;
  Bytes := (Length(T) + 1) * SizeOf(WideChar);
  Mem := GlobalAlloc(GMEM_MOVEABLE, Bytes);
  if Mem <> 0 then
  begin
    P := GlobalLock(Mem);
    Move(PWideChar(T)^, P^, Bytes);
    GlobalUnlock(Mem);
    SetClipboardData(CF_UNICODETEXT, Mem);
  end;
  CloseClipboard;
end;

procedure WriteLog;
var
  H: THandle;
  Raw: RawByteString;
  Got: DWORD;
begin
  Raw := EncodeUtf8(BuildReport);
  H := CreateFileW(PWideChar(LogPath), GENERIC_WRITE, 0, nil, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if H = INVALID_HANDLE_VALUE then Exit;
  if Raw <> '' then WriteFile(H, Raw[1], Length(Raw), Got, nil);
  CloseHandle(H);
end;

procedure DoLayout;
var
  R: TRect;
  W, H, M, BH, Y: Integer;
begin
  GetClientRect(Wnd, R);
  W := R.Right;
  H := R.Bottom;
  M := S(12);
  BH := S(28);
  MoveWindow(hStatus, M, M, W - 2 * M - S(250), S(30), True);
  MoveWindow(hBrand, W - M - S(250), M, S(250), S(18), True);
  MoveWindow(hLink, W - M - S(250), M + S(17), S(250), S(18), True);
  MoveWindow(hFile, M, M + S(32), W - 2 * M, S(20), True);
  MoveWindow(hProg, M, M + S(56), W - 2 * M, S(16), True);
  Y := M + S(80);
  MoveWindow(hList, M, Y, W - 2 * M, H - Y - BH - 2 * M, True);
  MoveWindow(hReport, M, Y, W - 2 * M, H - Y - BH - 2 * M, True);
  MoveWindow(hStop, W - M - S(100), H - M - BH, S(100), BH, True);
  MoveWindow(hCopy, W - M - S(100) - S(8) - S(130), H - M - BH, S(130), BH, True);
end;

function MakeFonts: Boolean;
var
  NCM: TNonClientMetricsW;
  LF: TLogFontW;
begin
  FillChar(NCM, SizeOf(NCM), 0);
  NCM.cbSize := SizeOf(NCM);
  if SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, SizeOf(NCM), @NCM, 0) then
    LF := NCM.lfMessageFont
  else
  begin
    FillChar(LF, SizeOf(LF), 0);
    LF.lfHeight := -S(12);
    lstrcpyW(LF.lfFaceName, 'Segoe UI');
  end;
  Font := CreateFontIndirectW(LF);
  LF.lfUnderline := 1;
  LinkFont := CreateFontIndirectW(LF);
  LF.lfUnderline := 0;
  LF.lfHeight := (LF.lfHeight * 16) div 9;
  LF.lfWeight := FW_SEMIBOLD;
  BigFont := CreateFontIndirectW(LF);
  Result := True;
end;

function AddCtl(const Cls, Text: string; Style, ExStyle: DWORD; Id: Integer; F: HFONT): HWND;
begin
  Result := CreateWindowExW(ExStyle, PWideChar(Cls), PWideChar(Text),
    WS_CHILD or WS_VISIBLE or Style, 0, 0, 10, 10, Wnd, HMENU(Id), HInstance, nil);
  SendMessage(Result, WM_SETFONT, WPARAM(F), 1);
end;

procedure CreateControls;
var
  Col: TLVColumnW;
  DC: HDC;
  Tid: LongWord;
  TabStop: Integer;
begin
  DC := GetDC(0);
  Dpi := GetDeviceCaps(DC, LOGPIXELSX);
  ReleaseDC(0, DC);
  MakeFonts;
  hStatus := AddCtl('STATIC', 'Preparing...', SS_NOPREFIX or SS_ENDELLIPSIS, 0, ID_STATUS, BigFont);
  hBrand := AddCtl('STATIC', 'Developed by: Level103 Communications', SS_NOPREFIX or SS_RIGHT, 0, ID_BRAND, Font);
  hLink := AddCtl('STATIC', BrandUrl, SS_NOPREFIX or SS_RIGHT or SS_NOTIFY, 0, ID_LINK, LinkFont);
  hFile := AddCtl('STATIC', '', SS_NOPREFIX or SS_PATHELLIPSIS, 0, ID_FILE, Font);
  hProg := AddCtl('msctls_progress32', '', PBS_SMOOTH, 0, ID_PROG, Font);
  SendMessage(hProg, PBM_SETRANGE32, 0, 1000);
  hList := AddCtl('SysListView32', '', LVS_REPORT or LVS_OWNERDATA or LVS_SHOWSELALWAYS or WS_TABSTOP or WS_BORDER,
    0, ID_LIST, Font);
  SendMessage(hList, LVM_SETEXTENDEDLISTVIEWSTYLE, 0, LVS_EX_FULLROWSELECT or LVS_EX_DOUBLEBUFFER or LVS_EX_LABELTIP);
  SetWindowTheme(hList, 'Explorer', nil);
  FillChar(Col, SizeOf(Col), 0);
  Col.mask := LVCF_TEXT or LVCF_WIDTH;
  Col.cx := S(380);
  Col.pszText := 'File';
  SendMessage(hList, LVM_INSERTCOLUMNW, 0, LPARAM(@Col));
  Col.cx := S(150);
  Col.pszText := 'Result';
  SendMessage(hList, LVM_INSERTCOLUMNW, 1, LPARAM(@Col));
  ListView_SetItemCountEx(hList, Length(Entries), LVSICF_NOINVALIDATEALL);
  hReport := AddCtl('EDIT', '', ES_MULTILINE or ES_READONLY or ES_AUTOVSCROLL or ES_AUTOHSCROLL or WS_VSCROLL or WS_HSCROLL or WS_TABSTOP,
    WS_EX_CLIENTEDGE, ID_REPORT, Font);
  SendMessage(hReport, EM_SETLIMITTEXT, 0, 0);
  TabStop := S(60) * 4 div 4;
  SendMessage(hReport, EM_SETTABSTOPS, 1, LPARAM(@TabStop));
  ShowWindow(hReport, SW_HIDE);
  hCopy := AddCtl('BUTTON', 'Copy report', BS_PUSHBUTTON or WS_TABSTOP, 0, ID_COPY, Font);
  hStop := AddCtl('BUTTON', 'Stop', BS_DEFPUSHBUTTON or WS_TABSTOP, 0, ID_STOP, Font);
  DoLayout;
  StartTick := GetTickCount64;
  CurIndex := 0;
  Running := True;
  LastPermille := -1;
  SetTimer(Wnd, TIMER_UI, 100, nil);
  BeginThread(nil, 0, @Worker, nil, 0, Tid);
end;

procedure OnGetDispInfo(Info: PLVDispInfoW);
var I: Integer;
begin
  I := Info^.item.iItem;
  if (I < 0) or (I >= Length(Entries)) then Exit;
  if (Info^.item.mask and LVIF_TEXT) = 0 then Exit;
  if Info^.item.iSubItem = 0 then
    Info^.item.pszText := PWideChar(Entries[I].Name)
  else
  begin
    case Results[I] of
      ST_OK: Info^.item.pszText := 'OK';
      ST_BAD: Info^.item.pszText := 'Checksum mismatch';
      ST_MISSING: Info^.item.pszText := 'File missing';
      ST_ERROR: Info^.item.pszText := 'Read error';
    else
      Info^.item.pszText := '';
    end;
    if I >= DoneCount then Info^.item.pszText := '';
  end;
end;

function OnCustomDraw(CD: PNMLVCustomDraw): LRESULT;
var I: Integer;
begin
  Result := CDRF_DODEFAULT;
  case CD^.nmcd.dwDrawStage of
    CDDS_PREPAINT: Result := CDRF_NOTIFYITEMDRAW;
    CDDS_ITEMPREPAINT:
      begin
        I := CD^.nmcd.dwItemSpec;
        if (I >= 0) and (I < DoneCount) and ((CD^.nmcd.uItemState and CDIS_SELECTED) = 0) then
          case Results[I] of
            ST_OK: CD^.clrText := RGB(0, 120, 0);
            ST_BAD, ST_MISSING, ST_ERROR: CD^.clrText := RGB(200, 0, 0);
          end;
        Result := CDRF_NEWFONT;
      end;
  end;
end;

function WndProc(H: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT; stdcall;
var
  NM: PNMHdr;
  MMI: PMinMaxInfo;
  DC: HDC;
begin
  Result := 0;
  case Msg of
    WM_CREATE:
      begin
        Wnd := H;
        CreateControls;
      end;
    WM_SIZE:
      if hList <> 0 then DoLayout;
    WM_GETMINMAXINFO:
      begin
        MMI := PMinMaxInfo(LP);
        MMI^.ptMinTrackSize.X := S(420);
        MMI^.ptMinTrackSize.Y := S(300);
      end;
    WM_TIMER:
      if WP = TIMER_UI then RefreshUI;
    WM_ALLDONE:
      FinishUI;
    WM_NOTIFY:
      begin
        NM := PNMHdr(LP);
        if NM^.hwndFrom = hList then
          case Integer(NM^.code) of
            LVN_GETDISPINFOW: OnGetDispInfo(PLVDispInfoW(LP));
            NM_CUSTOMDRAW: Result := OnCustomDraw(PNMLVCustomDraw(LP));
          end;
      end;
    WM_CTLCOLORSTATIC:
      begin
        DC := HDC(WP);
        if HWND(LP) = hReport then
        begin
          SetTextColor(DC, GetSysColor(COLOR_WINDOWTEXT));
          SetBkColor(DC, GetSysColor(COLOR_WINDOW));
          Result := LRESULT(GetSysColorBrush(COLOR_WINDOW));
        end
        else
        begin
          if HWND(LP) = hStatus then SetTextColor(DC, SummaryColor);
          if HWND(LP) = hLink then SetTextColor(DC, RGB(0, 102, 204));
          SetBkMode(DC, TRANSPARENT);
          Result := LRESULT(GetSysColorBrush(COLOR_BTNFACE));
        end;
      end;
    WM_COMMAND:
      case LOWORD(WP) of
        ID_STOP, IDCANCEL:
          if Running and (LOWORD(WP) = ID_STOP) then
          begin
            AbortFlag := 1;
            EnableWindow(hStop, False);
          end
          else
            DestroyWindow(H);
        ID_COPY: CopyReport;
        ID_LINK: ShellExecuteW(H, 'open', BrandUrl, nil, nil, SW_SHOWNORMAL);
      end;
    WM_SETCURSOR:
      if HWND(WP) = hLink then
      begin
        SetCursor(LoadCursor(0, IDC_HAND));
        Result := 1;
      end
      else
        Result := DefWindowProcW(H, Msg, WP, LP);
    WM_CLOSE:
      begin
        // close instantly, even in the middle of a scan
        ExitProcess(0);
      end;
    WM_DESTROY:
      PostQuitMessage(0);
  else
    Result := DefWindowProcW(H, Msg, WP, LP);
  end;
end;

var
  WC: TWndClassExW;
  Msg: TMsg;
  ICC: TInitCommonControlsEx;
  IconBig, IconSmall: HICON;
  R: TRect;
  I: Integer;
begin
  for I := 1 to ParamCount do
    if (Copy(ParamStr(I), 1, 5) = '/log=') or (Copy(ParamStr(I), 1, 5) = '-log=') then
      LogPath := Copy(ParamStr(I), 6, MaxInt);
  ICC.dwSize := SizeOf(ICC);
  ICC.dwICC := ICC_LISTVIEW_CLASSES or ICC_PROGRESS_CLASS or ICC_STANDARD_CLASSES;
  InitCommonControlsEx(ICC);
  LoadConfiguration;
  SetLength(Results, Length(Entries));
  SetLength(Sizes, Length(Entries));

  IconBig := LoadImageW(HInstance, PWideChar(MakeIntResource(1)), IMAGE_ICON,
    GetSystemMetrics(SM_CXICON), GetSystemMetrics(SM_CYICON), LR_DEFAULTCOLOR);
  IconSmall := LoadImageW(HInstance, PWideChar(MakeIntResource(1)), IMAGE_ICON,
    GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), LR_DEFAULTCOLOR);
  if IconBig = 0 then IconBig := LoadIcon(0, IDI_APPLICATION);

  FillChar(WC, SizeOf(WC), 0);
  WC.cbSize := SizeOf(WC);
  WC.lpfnWndProc := @WndProc;
  WC.hInstance := HInstance;
  WC.hIcon := IconBig;
  WC.hIconSm := IconSmall;
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  WC.hbrBackground := HBRUSH(COLOR_BTNFACE + 1);
  WC.lpszClassName := CLASS_NAME;
  RegisterClassExW(WC);

  Dpi := 96;
  R.Left := 0;
  CreateWindowExW(0, CLASS_NAME, PWideChar('Checksum - ' + AppTitle), WS_OVERLAPPEDWINDOW,
    CW_USEDEFAULT, CW_USEDEFAULT, 760, 540, 0, 0, HInstance, nil);
  if Wnd = 0 then ExitProcess(1);
  // size now that the real DPI is known
  SetWindowPos(Wnd, 0, 0, 0, S(760), S(540), SWP_NOMOVE or SWP_NOZORDER or SWP_NOACTIVATE);
  ShowWindow(Wnd, SW_SHOWNORMAL);
  UpdateWindow(Wnd);

  while GetMessage(Msg, 0, 0, 0) do
    if not IsDialogMessage(Wnd, Msg) then
    begin
      TranslateMessage(Msg);
      DispatchMessage(Msg);
    end;
  ExitProcess(ExitCodeVal);
end.
