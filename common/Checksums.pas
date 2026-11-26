unit Checksums;

{ The Checksum Applet area (both editions): makes a checksum list for any folder - and, if asked, a small checksum program
  next to it that checks the files on any PC with nothing installed - and writes the text report of an MD5 check.
  From the Checksum Applet Creator (G:\Claude\ChecksumApplet keeps its own copy). The hashing is in Hashes, the list
  formats in Digests; the checksum program is ..\stub\CheckStub.dpr, built by each edition's build.cmd and kept in
  the exe as the RCDATA resource CHECKSTUB (its default icon: CHECKICON).

  No UI code in here: a page starts a TChecksumJob on a TChecksumThread and reads its progress fields on a timer. }

{$IFDEF FPC}{$mode delphiunicode}{$H+}{$ENDIF}

interface

uses
  Windows, SysUtils, Classes, Hashes, Digests, OfflineEngine, HashThreads;

type
  TMakeFile = record
    RelName: string;             // relative to the folder, backslash separated
    Size: Int64;
  end;
  TMakeFiles = array of TMakeFile;

  TMakeOptions = record
    Folder: string;              // the folder holding the files; the list (and program) are written here
    BaseName: string;            // 'checksum': the list is checksum.md5 (.sha256, ...), the program checksum.exe
    MakeProgram: Boolean;        // also write <BaseName>.exe
    IconFile: string;            // the program's icon; '' = the built-in one
    Algo: THashAlgo;
    Format: TDigestFormat;
  end;

  TMakeResult = (mkDone, mkCancelled, mkFailed);

  { One run: reads every file, writes the list, then the program. Run blocks - TChecksumThread runs it in the
    background. The progress fields are read by the page while it runs (a stale read only shows an older number). }
  TChecksumJob = class
  private
    FCancelled: Boolean;
    // while Run reads the files (several at once - HashThreads): each worker's hasher and buffer, and per file its
    // checksum, whether it was read (0 not yet, 1 read, 2 could not be read) and why not (a Windows error code)
    FRoot: string;
    FHashers: array of THasher;
    FBufs: array of Pointer;
    FDigests: array of TDigest;
    FState: array of Byte;
    FError: array of DWORD;
    FFailedAt: LongInt;          // the first file that could not be read (MaxInt: none yet); later ones are not read
    FThreads: Integer;
    // per worker: the file it is reading (-1: none) and how much of it - fixed size, so the page can read them
    // while the job runs (ReadingNow)
    FSlotItem: array[0..MaxHashThreads - 1] of LongInt;
    FSlotDone: array[0..MaxHashThreads - 1] of Int64;
    procedure HashOne(Worker, Index: Integer);
    procedure WriteProgram(const ExePath, ListName: string);
  public
    Options: TMakeOptions;
    Files: TMakeFiles;
    StubFile: string;            // tests only: the program is copied from this file instead of the CHECKSTUB resource
    // progress
    FileIndex: Integer;          // a file being read now (the last one a worker started)
    BytesDone, BytesTotal: Int64;
    // the result
    Outcome: TMakeResult;
    ErrorText: string;           // why it failed, in a sentence or two
    ListPath, ExePath: string;   // what was written ('' if not)
    Started, Finished: TDateTime;
    constructor Create(const O: TMakeOptions; const AFiles: TMakeFiles);
    procedure Run;
    procedure Cancel;            // safe from another thread
    property Cancelled: Boolean read FCancelled;
    property Threads: Integer read FThreads;   // after Run: how many files were read at once
    // the files being read right now, the biggest first (at most MaxReading); safe from another thread
    function ReadingNow: TReadingFiles;
  end;

  TChecksumThread = class(TThread)
  private
    FJob: TChecksumJob;
  protected
    procedure Execute; override;
  public
    constructor Create(Job: TChecksumJob);    // starts at once; the job is the caller's to free (after the thread)
    property Job: TChecksumJob read FJob;
  end;

const
  DefaultBaseName = 'checksum';

{ The base name for the list and program as typed (with or without .exe), or '' if it can't be a file name }
function NormalizeBaseName(const S: string): string;
function ListFileName(const O: TMakeOptions): string;    // 'checksum.md5'
function ProgramFileName(const O: TMakeOptions): string; // 'checksum.exe'
// True for files a run with this base name writes (checksum.exe and checksum.<any list extension>), so making the
// list again does not list its own earlier output
function IsMakerOutput(const RelName, BaseName: string): Boolean;
// every file below Folder (in its subfolders too if Recurse), sorted, without earlier output for BaseName
function ScanFolder(const Folder: string; Recurse: Boolean; const BaseName: string): TMakeFiles;
function IconBytesValid(const Data: TBytes): Boolean;
function ReadIconFile(const Path: string): TBytes;       // nil if it can't be read or isn't an .ico
function DefaultProgramIcon: TBytes;                     // the built-in icon (CHECKICON), nil if the exe has none
// a Windows icon of the entry nearest Size (0 if none) - for showing the icon on the page; DestroyIcon it after
function IconHandle(const Ico: TBytes; Size: Integer): HICON;

{ The text report of an MD5 check page result (like ExactFile's): a summary, the problem files, then every file }
function CheckReportText(const ListFile: string; Algo: THashAlgo; const Items: TCheckItems; R: TCopyResult): string;
// writes Text to Path as UTF-8 (with a BOM, so Notepad reads it right); False if it could not
function SaveTextUtf8(const Path, Text: string): Boolean;

implementation

function NormalizeBaseName(const S: string): string;
const
  Bad = '\/:*?"<>|';
var
  I: Integer;
  T: string;
begin
  T := Trim(S);
  if T = '' then T := DefaultBaseName;
  if SameText(ExtractFileExt(T), '.exe') then T := Copy(T, 1, Length(T) - 4);
  T := Trim(T);
  Result := '';
  if (T = '') or (T[Length(T)] = '.') then Exit;
  for I := 1 to Length(T) do
    if (System.Pos(T[I], Bad) > 0) or (T[I] < ' ') then Exit;
  Result := T;
end;

function ListFileName(const O: TMakeOptions): string;
begin
  Result := O.BaseName + '.' + FormatExtension(O.Format, O.Algo);
end;

function ProgramFileName(const O: TMakeOptions): string;
begin
  Result := O.BaseName + '.exe';
end;

function IsMakerOutput(const RelName, BaseName: string): Boolean;
var
  Ext: string;
  A: THashAlgo;
begin
  Result := False;
  if System.Pos('\', RelName) > 0 then Exit;            // only the folder's own files, not its subfolders'
  if not SameText(ChangeFileExt(RelName, ''), BaseName) then Exit;
  Ext := LowerCase(Copy(ExtractFileExt(RelName), 2, MaxInt));
  if (Ext = 'exe') or (Ext = 'md5') or (Ext = 'sha1') or (Ext = 'sfv') then Exit(True);
  for A := Low(THashAlgo) to High(THashAlgo) do
    if SameText(Ext, HashNames[A]) then Exit(True);
end;

function JoinParts(const Parts: TPathList): string;
var
  I, N, P: Integer;
begin
  N := 0;
  for I := 0 to High(Parts) do Inc(N, Length(Parts[I]));
  SetLength(Result, N);
  P := 1;
  for I := 0 to High(Parts) do
    if Parts[I] <> '' then
    begin
      Move(Parts[I][1], Result[P], Length(Parts[I]) * SizeOf(Char));
      Inc(P, Length(Parts[I]));
    end;
end;

procedure SortFiles(var L: TMakeFiles);
  procedure Sort(Lo, Hi: Integer);
  var
    I, J: Integer;
    P: string;
    T: TMakeFile;
  begin
    repeat
      I := Lo;
      J := Hi;
      P := L[(Lo + Hi) div 2].RelName;
      repeat
        while CompareText(L[I].RelName, P) < 0 do Inc(I);
        while CompareText(L[J].RelName, P) > 0 do Dec(J);
        if I <= J then
        begin
          T := L[I]; L[I] := L[J]; L[J] := T;
          Inc(I);
          Dec(J);
        end;
      until I > J;
      if Lo < J then Sort(Lo, J);
      Lo := I;
    until I >= Hi;
  end;
begin
  if Length(L) > 1 then Sort(0, High(L));
end;

function ScanFolder(const Folder: string; Recurse: Boolean; const BaseName: string): TMakeFiles;
var
  Root: string;
  N: Integer;

  procedure Walk(const Rel: string);
  var
    FD: TWin32FindDataW;
    H: THandle;
    Name: string;
  begin
    H := FindFirstFileW(PWideChar(ExtendedPath(Root + Rel + '*')), FD);
    if H = INVALID_HANDLE_VALUE then Exit;
    try
      repeat
        Name := FD.cFileName;
        if (Name = '.') or (Name = '..') then Continue;
        if (FD.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
        begin
          // not into junctions and links (they can loop, and their files are someone else's), nor into Windows'
          // own hidden system folders - a drive's $RECYCLE.BIN and System Volume Information
          if Recurse and ((FD.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) = 0) and
             ((FD.dwFileAttributes and (FILE_ATTRIBUTE_HIDDEN or FILE_ATTRIBUTE_SYSTEM)) <>
              (FILE_ATTRIBUTE_HIDDEN or FILE_ATTRIBUTE_SYSTEM)) then
            Walk(Rel + Name + '\');
        end
        else if (BaseName = '') or not IsMakerOutput(Rel + Name, BaseName) then
        begin
          if N = Length(Result) then SetLength(Result, N * 2 + 64);
          Result[N].RelName := Rel + Name;
          Result[N].Size := (Int64(FD.nFileSizeHigh) shl 32) or FD.nFileSizeLow;
          Inc(N);
        end;
      until not FindNextFileW(H, FD);
    finally
      Windows.FindClose(H);
    end;
  end;

begin
  Result := nil;
  N := 0;
  Root := IncludeTrailingPathDelimiter(Folder);
  Walk('');
  SetLength(Result, N);
  SortFiles(Result);
end;

{ ---------------------------------------------------------------- the program's icon and configuration }

type
  TIcoEntry = packed record
    W, H, Colors, Res: Byte;
    Planes, BitCount: Word;
    Bytes, Offset: DWORD;
  end;
  TGrpEntry = packed record
    W, H, Colors, Res: Byte;
    Planes, BitCount: Word;
    Bytes: DWORD;
    Id: Word;
  end;

function IconBytesValid(const Data: TBytes): Boolean;
var
  Count, I: Integer;
  E: TIcoEntry;
begin
  Result := False;
  if Length(Data) < 6 then Exit;
  if (PWord(@Data[0])^ <> 0) or (PWord(@Data[2])^ <> 1) then Exit;
  Count := PWord(@Data[4])^;
  if (Count < 1) or (6 + Count * SizeOf(TIcoEntry) > Length(Data)) then Exit;
  for I := 0 to Count - 1 do
  begin
    Move(Data[6 + I * SizeOf(TIcoEntry)], E, SizeOf(E));
    if (E.Bytes = 0) or (Int64(E.Offset) + E.Bytes > Length(Data)) then Exit;
  end;
  Result := True;
end;

function ResourceBytes(const Name: string): TBytes;
var
  RS: TResourceStream;
begin
  Result := nil;
  if FindResourceW(HInstance, PWideChar(Name), PWideChar(RT_RCDATA)) = 0 then Exit;
  RS := TResourceStream.Create(HInstance, Name, RT_RCDATA);
  try
    SetLength(Result, RS.Size);
    if RS.Size > 0 then RS.ReadBuffer(Result[0], RS.Size);
  finally
    RS.Free;
  end;
end;

function FileBytes(const Path: string): TBytes;
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, FS.Size);
    if FS.Size > 0 then FS.ReadBuffer(Result[0], FS.Size);
  finally
    FS.Free;
  end;
end;

procedure SaveBytes(const Path: string; const Data: TBytes);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(Path, fmCreate);
  try
    if Length(Data) > 0 then FS.WriteBuffer(Data[0], Length(Data));
  finally
    FS.Free;
  end;
end;

function ReadIconFile(const Path: string): TBytes;
begin
  try
    Result := FileBytes(Path);
  except
    Result := nil;
  end;
  if not IconBytesValid(Result) then Result := nil;
end;

function DefaultProgramIcon: TBytes;
begin
  Result := ResourceBytes('CHECKICON');
  if not IconBytesValid(Result) then Result := nil;
end;

function IconHandle(const Ico: TBytes; Size: Integer): HICON;
var
  Count, I, Best, W, BestW: Integer;
  E: TIcoEntry;
begin
  Result := 0;
  if not IconBytesValid(Ico) then Exit;
  Count := PWord(@Ico[4])^;
  Best := -1;
  BestW := 0;
  for I := 0 to Count - 1 do
  begin
    Move(Ico[6 + I * SizeOf(TIcoEntry)], E, SizeOf(E));
    W := E.W;
    if W = 0 then W := 256;
    if (Best < 0) or (Abs(W - Size) < Abs(BestW - Size)) or ((Abs(W - Size) = Abs(BestW - Size)) and (W > BestW)) then
    begin
      Best := I;
      BestW := W;
    end;
  end;
  Move(Ico[6 + Best * SizeOf(TIcoEntry)], E, SizeOf(E));
  Result := CreateIconFromResourceEx(@Ico[E.Offset], E.Bytes, True, $00030000, Size, Size, 0);
end;

{ Puts the icon (as icon group 1) and the configuration (RCDATA CHKCFG) into the copied program }
procedure PatchProgram(const ExePath: string; const Ico: TBytes; const Cfg: string);
const
  Lang = 1033;
var
  H: THandle;
  Count, I: Integer;
  E: TIcoEntry;
  Grp: TBytes;
  G: TGrpEntry;
  Raw: RawByteString;
  Ok: Boolean;
begin
  H := BeginUpdateResourceW(PWideChar(ExePath), False);
  if H = 0 then raise Exception.Create('Could not open the program for editing: ' + SysErrorMessage(GetLastError));
  Ok := False;
  try
    Count := PWord(@Ico[4])^;
    SetLength(Grp, 6 + Count * SizeOf(TGrpEntry));
    PWord(@Grp[0])^ := 0;
    PWord(@Grp[2])^ := 1;
    PWord(@Grp[4])^ := Count;
    for I := 0 to Count - 1 do
    begin
      Move(Ico[6 + I * SizeOf(TIcoEntry)], E, SizeOf(E));
      G.W := E.W; G.H := E.H; G.Colors := E.Colors; G.Res := 0;
      G.Planes := E.Planes; G.BitCount := E.BitCount; G.Bytes := E.Bytes;
      G.Id := I + 1;
      Move(G, Grp[6 + I * SizeOf(TGrpEntry)], SizeOf(G));
      if not UpdateResourceW(H, PWideChar(RT_ICON), PWideChar(MakeIntResource(I + 1)), Lang, @Ico[E.Offset],
        E.Bytes) then
        raise Exception.Create('Could not write the icon: ' + SysErrorMessage(GetLastError));
    end;
    if not UpdateResourceW(H, PWideChar(RT_GROUP_ICON), PWideChar(MakeIntResource(1)), Lang, @Grp[0], Length(Grp)) then
      raise Exception.Create('Could not write the icon: ' + SysErrorMessage(GetLastError));
    Raw := EncodeUtf8(Cfg);
    if not UpdateResourceW(H, PWideChar(RT_RCDATA), 'CHKCFG', Lang, @Raw[1], Length(Raw)) then
      raise Exception.Create('Could not write the configuration: ' + SysErrorMessage(GetLastError));
    Ok := True;
  finally
    EndUpdateResourceW(H, not Ok);
  end;
end;

{ ---------------------------------------------------------------- the job }

constructor TChecksumJob.Create(const O: TMakeOptions; const AFiles: TMakeFiles);
var
  I: Integer;
begin
  inherited Create;
  Options := O;
  Files := Copy(AFiles);
  FileIndex := 0;
  Outcome := mkFailed;
  for I := 0 to MaxHashThreads - 1 do FSlotItem[I] := -1;
end;

function TChecksumJob.ReadingNow: TReadingFiles;
var
  W, Item, N: Integer;
begin
  Result := nil;
  N := 0;
  for W := 0 to MaxHashThreads - 1 do
  begin
    Item := FSlotItem[W];
    if (Item < 0) or (Item > High(Files)) then Continue;
    SetLength(Result, N + 1);
    Result[N].Name := Files[Item].RelName;
    Result[N].Size := Files[Item].Size;
    Result[N].Done := FSlotDone[W];
    if Result[N].Done > Result[N].Size then Result[N].Done := Result[N].Size;
    Inc(N);
  end;
  SortReading(Result);
end;

procedure TChecksumJob.Cancel;
begin
  FCancelled := True;
end;

procedure TChecksumJob.WriteProgram(const ExePath, ListName: string);
var
  Ico, Stub: TBytes;
  Cfg: string;
begin
  if Options.IconFile <> '' then
  begin
    try
      Ico := FileBytes(Options.IconFile);
    except
      on E: Exception do raise Exception.Create('Could not read the icon file: ' + E.Message);
    end;
    if not IconBytesValid(Ico) then raise Exception.Create('The icon file is not a valid .ico file.');
  end
  else
    Ico := ResourceBytes('CHECKICON');
  if StubFile <> '' then Stub := FileBytes(StubFile) else Stub := ResourceBytes('CHECKSTUB');
  if Length(Stub) = 0 then raise Exception.Create('This build has no checksum program in it.');
  SaveBytes(ExePath, Stub);
  Cfg := 'digest=' + ListName + #13#10 + 'algo=' + HashNames[Options.Algo] + #13#10 +
    'format=' + FormatNames[Options.Format] + #13#10 +
    'title=' + ExtractFileName(ExcludeTrailingPathDelimiter(Options.Folder)) + #13#10 +
    // when the list was made, for the program's report (always yyyy-mm-dd hh:nn, whatever the PC's date format)
    'created=' + FormatDateTime('yyyy"-"mm"-"dd" "hh":"nn', Started) + #13#10;
  if IconBytesValid(Ico) then
    PatchProgram(ExePath, Ico, Cfg)
  else
    raise Exception.Create('This build has no icon for the checksum program.');
end;

const
  ChunkSize = 1024 * 1024;

{ One file, on worker Worker (TParallelWork): its checksum into FDigests, or why it could not be read into FError.
  The first file that can't be read stops the files after it from being read - the run fails on it, as it always
  did; the files before it are still read, so it is the same file a one-thread run fails on. }
procedure TChecksumJob.HashOne(Worker, Index: Integer);
var
  H: THandle;
  Got: DWORD;
  Hasher: THasher;
  Buf: Pointer;

  procedure Failed(Code: DWORD);
  begin
    FError[Index] := Code;
    FState[Index] := 2;
    LowerTo(FFailedAt, Index);
  end;

begin
  if FCancelled or (Index > FFailedAt) then Exit;
  FileIndex := Index;
  Hasher := FHashers[Worker];
  Buf := FBufs[Worker];
  FSlotDone[Worker] := 0;
  InterlockedExchange(FSlotItem[Worker], Index);
  try
    try
      H := CreateFileW(PWideChar(ExtendedPath(FRoot + Files[Index].RelName)), GENERIC_READ,
        FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, 0);
      if H = INVALID_HANDLE_VALUE then
      begin
        Failed(GetLastError);
        Exit;
      end;
      try
        Hasher.Reset;
        repeat
          if FCancelled or (Index > FFailedAt) then Exit;
          if not Windows.ReadFile(H, Buf^, ChunkSize, Got, nil) then
          begin
            Failed(GetLastError);
            Exit;
          end;
          if Got > 0 then
          begin
            Hasher.Update(Buf, Got);
            AddBytes(BytesDone, Got);
            Inc(FSlotDone[Worker], Got);
          end;
        until Got = 0;
      finally
        CloseHandle(H);
      end;
      Hasher.Final(FDigests[Index]);
      FState[Index] := 1;
    except
      Failed(0);
    end;
  finally
    InterlockedExchange(FSlotItem[Worker], -1);   // also after an Exit above
  end;
end;

procedure TChecksumJob.Run;
var
  ListName, Text, Exe, Why: string;
  I: Integer;
  Parts: TPathList;
  Raw: RawByteString;
  FS: TFileStream;
begin
  Started := Now;
  Outcome := mkFailed;
  ErrorText := '';
  ListPath := '';
  ExePath := '';
  BytesDone := 0;
  BytesTotal := 0;
  for I := 0 to High(Files) do Inc(BytesTotal, Files[I].Size);
  FRoot := IncludeTrailingPathDelimiter(Options.Folder);
  FThreads := 0;
  try
    try
      if not DirectoryExists(FRoot) then raise Exception.Create('The folder is not there: ' + FRoot);
      if Length(Files) = 0 then raise Exception.Create('There are no files to list.');
      if not FormatSupports(Options.Format, Options.Algo) then
        raise Exception.Create(FormatNames[Options.Format] + ' lists cannot hold ' + HashNames[Options.Algo] +
          ' checksums.');
      ListName := ListFileName(Options);
      SetLength(FDigests, Length(Files));
      SetLength(FState, Length(Files));
      SetLength(FError, Length(Files));
      for I := 0 to High(Files) do FState[I] := 0;
      FFailedAt := MaxInt;
      FThreads := HashThreadCount(FRoot);
      if FThreads > Length(Files) then FThreads := Length(Files);
      SetLength(FHashers, FThreads);
      SetLength(FBufs, FThreads);
      for I := 0 to FThreads - 1 do
      begin
        FHashers[I] := NewHasher(Options.Algo);
        FBufs[I] := VirtualAlloc(nil, ChunkSize, MEM_COMMIT, PAGE_READWRITE);
        if FBufs[I] = nil then OutOfMemoryError;
      end;
      TParallelWork.Create(Length(Files), FThreads, HashOne).Free;   // Free waits for every worker
      if FCancelled then Exit;
      SetLength(Parts, Length(Files) + 1);
      Parts[0] := DigestHeader(Options.Format, Options.Algo, 'Offline Backup ' + AppVersion + ' on ' +
        FormatDateTime('yyyy"-"mm"-"dd" "hh":"nn', Started));
      for I := 0 to High(Files) do
      begin
        // files are started in list order, so every file before the first unreadable one has been read
        if FState[I] <> 1 then
        begin
          Why := '';
          if (FState[I] = 2) and (FError[I] <> 0) then Why := ': ' + SysErrorMessage(FError[I]);
          raise Exception.Create('Could not read ' + Files[I].RelName + Why);
        end;
        Parts[I + 1] := DigestLine(Options.Format, Options.Algo, Files[I].RelName, FDigests[I]) +
          DigestEOL(Options.Format);
      end;
      Text := JoinParts(Parts);
      Raw := EncodeUtf8(Text);
      ListPath := FRoot + ListName;
      try
        FS := TFileStream.Create(ListPath, fmCreate);
        try
          if Length(Raw) > 0 then FS.WriteBuffer(Raw[1], Length(Raw));
        finally
          FS.Free;
        end;
      except
        on E: Exception do
        begin
          ListPath := '';
          raise Exception.Create('Could not write the list: ' + E.Message);
        end;
      end;
      if Options.MakeProgram then
      begin
        Exe := FRoot + ProgramFileName(Options);
        try
          WriteProgram(Exe, ListName);
          ExePath := Exe;
        except
          on E: Exception do
          begin
            SysUtils.DeleteFile(Exe);
            raise Exception.Create('The list was written, but not the checksum program: ' + E.Message);
          end;
        end;
      end;
      Outcome := mkDone;
    except
      on E: Exception do
      begin
        Outcome := mkFailed;
        ErrorText := E.Message;
      end;
    end;
  finally
    if FCancelled and (Outcome <> mkDone) then Outcome := mkCancelled;
    for I := 0 to High(FBufs) do
      if FBufs[I] <> nil then VirtualFree(FBufs[I], 0, MEM_RELEASE);
    for I := 0 to High(FHashers) do FHashers[I].Free;
    FBufs := nil;
    FHashers := nil;
    FDigests := nil;
    FState := nil;
    FError := nil;
    Finished := Now;
  end;
end;

constructor TChecksumThread.Create(Job: TChecksumJob);
begin
  FJob := Job;
  inherited Create(False);
end;

procedure TChecksumThread.Execute;
begin
  FJob.Run;
end;

{ ---------------------------------------------------------------- report }

function CheckReportText(const ListFile: string; Algo: THashAlgo; const Items: TCheckItems; R: TCopyResult): string;
const
  Upper: array[TCheckStatus] of string = ('OK', 'FAILED', 'MISSING', 'UNREADABLE');
var
  Count: array[TCheckStatus] of Integer;
  St: TCheckStatus;
  I, Bad: Integer;
  Name: string;
  Parts: TPathList;

  procedure Add(const S: string);
  begin
    SetLength(Parts, Length(Parts) + 1);
    Parts[High(Parts)] := S + #13#10;
  end;

begin
  Parts := nil;
  Name := HashNames[Algo];
  for St := Low(TCheckStatus) to High(TCheckStatus) do Count[St] := 0;
  for I := 0 to High(Items) do Inc(Count[Items[I].Status]);
  Bad := Count[csBad] + Count[csMissing] + Count[csUnreadable];
  Add('Checking the files listed in: ' + ListFile);
  Add('Checked by Offline Backup ' + AppVersion + ' on ' + FormatDateTime('yyyy-mm-dd hh:nn', Now) + ', ' + Name);
  Add('');
  Add('SUMMARY:');
  if R = crCancelled then Add('THE CHECK WAS CANCELLED before every file was checked.')
  else if Bad = 0 then Add('EVERY FILE IS OK (no errors).')
  else Add('PROBLEMS WERE FOUND - ' + IntToStr(Bad) + ' file(s) did not check out - see PROBLEM FILES below.');
  Add(#9 + IntToStr(Count[csOk]) + ' file(s) match their checksum.');
  if Count[csBad] > 0 then Add(#9 + IntToStr(Count[csBad]) + ' file(s) FAILED (the checksum does not match).');
  if Count[csMissing] > 0 then Add(#9 + IntToStr(Count[csMissing]) + ' file(s) are MISSING.');
  if Count[csUnreadable] > 0 then Add(#9 + IntToStr(Count[csUnreadable]) + ' file(s) could not be read.');
  if Bad > 0 then
  begin
    Add('');
    Add('PROBLEM FILES:');
    for I := 0 to High(Items) do
      if Items[I].Status <> csOk then Add(Upper[Items[I].Status] + #9 + Name + #9 + Items[I].Path);
  end;
  Add('');
  Add('DETAILED REPORT:');
  for I := 0 to High(Items) do Add(Upper[Items[I].Status] + #9 + Name + #9 + Items[I].Path);
  Result := JoinParts(Parts);
end;

function SaveTextUtf8(const Path, Text: string): Boolean;
var
  Raw: RawByteString;
  FS: TFileStream;
begin
  Raw := #$EF#$BB#$BF + EncodeUtf8(Text);
  try
    FS := TFileStream.Create(Path, fmCreate);
    try
      FS.WriteBuffer(Raw[1], Length(Raw));
    finally
      FS.Free;
    end;
    Result := True;
  except
    Result := False;
  end;
end;

end.
