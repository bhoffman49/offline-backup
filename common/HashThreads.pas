unit HashThreads;

{ Reading and hashing many files at once (0.12): how many worker threads to use for a folder, and a small runner that
  hands the next file index to whichever worker is free. Each worker keeps its own hasher and buffer; the caller keeps
  one result per index, so lists and reports come out in the same order as with one thread.

  Used by the Checksum Applet's list making (Checksums), the MD5 check page (OfflineEngine.CheckMd5) and the checksum
  program (..\stub\CheckStub.dpr) - so Windows API only, no SysUtils or Classes. Verify drive and recording the
  checksums after a copy stay single-threaded. }

{$IFDEF FPC}{$mode delphiunicode}{$H+}{$ENDIF}

interface

uses
  Windows;

type
  // works on item Index with worker Worker's (0-based) own hasher and buffer; must not raise
  TWorkItemProc = procedure(Worker, Index: Integer) of object;

  { Starts Threads workers at once (below-normal priority, so the PC stays usable); they take the items 0..Count-1
    in order, each the next one not yet taken, until all are taken or Stop is called. Free waits for them
    to finish (all items, unless Stop was called). }
  TParallelWork = class
  private
    FProc: TWorkItemProc;
    FCount: LongInt;
    FNext: LongInt;              // the next index to hand out (interlocked)
    FStop: LongInt;
    FHandles: array of THandle;
    FArgs: array of Pointer;
  public
    constructor Create(Count, Threads: Integer; Proc: TWorkItemProc);
    destructor Destroy; override;
    procedure Stop;              // hands out no more items; the ones being worked on still finish. Any thread.
    function WaitFor(Ms: DWORD): Boolean;   // True once every worker has finished
    function Threads: Integer;
  end;

const
  MaxHashThreads = 32;
  SpareCpus = 2;                 // logical processors left free for the rest of the PC

var
  // > 0: always this many workers (tests; checksum.exe /threads=N). 0 = decide from the CPU and the drive.
  HashThreadsOverride: Integer = 0;

{ Does the volume holding Path report a seek penalty (a spinning disk)? False in the result if Windows can't tell
  (network shares, some USB bridges and encrypted volumes) - Penalty is then False too. }
function VolumeSeekPenalty(const Path: string; out Penalty: Boolean): Boolean;
// logical processors in this PC
function LogicalCpuCount: Integer;
{ Workers to read the files below Path with: 1 on a spinning disk (reading several files at once makes it seek),
  otherwise the logical processors less SpareCpus (at least 1, at most MaxHashThreads) }
function HashThreadCount(const Path: string): Integer;
{ Path in Windows' long form (\\?\C:\... or \\?\UNC\server\...) when it is near or over the old 260-character limit,
  so it can still be opened and listed; shorter paths are returned as they are. Path must be a full path with
  backslashes. }
function ExtendedPath(const Path: string): string;
// Target := Target + N, safe when several threads add at once
procedure AddBytes(var Target: Int64; N: Int64);
// Target := Value if Value is lower, safe when several threads lower it at once (the first failed index, say)
procedure LowerTo(var Target: LongInt; Value: LongInt);

implementation

type
  PWorkerArg = ^TWorkerArg;
  TWorkerArg = record
    Work: TParallelWork;
    Worker: Integer;
  end;

function WorkerMain(Param: Pointer): {$IFDEF FPC}PtrInt{$ELSE}Integer{$ENDIF};
var
  A: PWorkerArg;
  W: TParallelWork;
  I: LongInt;
begin
  A := Param;
  W := A^.Work;
  while W.FStop = 0 do
  begin
    I := InterlockedIncrement(W.FNext) - 1;
    if I >= W.FCount then Break;
    try
      W.FProc(A^.Worker, I);
    except
      // the item's own code records failures; never let one end the worker
    end;
  end;
  Result := 0;
end;

constructor TParallelWork.Create(Count, Threads: Integer; Proc: TWorkItemProc);
var
  I, N: Integer;
  A: PWorkerArg;
  Tid: LongWord;
  H: THandle;
begin
  inherited Create;
  FProc := Proc;
  FCount := Count;
  FNext := 0;
  FStop := 0;
  if Threads > Count then Threads := Count;
  if Threads > MaxHashThreads then Threads := MaxHashThreads;
  if Threads < 1 then Threads := 1;
  SetLength(FHandles, Threads);
  SetLength(FArgs, Threads);
  N := 0;
  for I := 0 to Threads - 1 do
  begin
    New(A);
    A^.Work := Self;
    A^.Worker := I;
    FArgs[I] := A;
    H := THandle(BeginThread(nil, 0, @WorkerMain, A, CREATE_SUSPENDED, Tid));
    if H = 0 then Continue;
    SetThreadPriority(H, THREAD_PRIORITY_BELOW_NORMAL);
    FHandles[N] := H;
    Inc(N);
  end;
  SetLength(FHandles, N);
  for I := 0 to N - 1 do ResumeThread(FHandles[I]);
  // no thread could be started: do the work here, so the caller still gets every item
  if N = 0 then WorkerMain(FArgs[0]);
end;

destructor TParallelWork.Destroy;
var
  I: Integer;
begin
  WaitFor(INFINITE);         // to end early, Stop first
  for I := 0 to High(FHandles) do CloseHandle(FHandles[I]);
  for I := 0 to High(FArgs) do Dispose(PWorkerArg(FArgs[I]));
  inherited;
end;

procedure TParallelWork.Stop;
begin
  InterlockedExchange(FStop, 1);
end;

function TParallelWork.WaitFor(Ms: DWORD): Boolean;
begin
  if Length(FHandles) = 0 then Exit(True);
  Result := WaitForMultipleObjects(Length(FHandles), @FHandles[0], True, Ms) <> WAIT_TIMEOUT;
end;

function TParallelWork.Threads: Integer;
begin
  Result := Length(FHandles);
  if Result = 0 then Result := 1;
end;

{ ---------------------------------------------------------------- the drive and the CPU }

const
  IOCTL_STORAGE_QUERY_PROPERTY = $002D1400;
  StorageDeviceSeekPenaltyProperty = 7;
  PropertyStandardQuery = 0;

{$IFDEF FPC}
// not in Free Pascal's Windows unit
function GetVolumePathNameW(lpszFileName: LPCWSTR; lpszVolumePathName: LPWSTR; cchBufferLength: DWORD): BOOL; stdcall;
  external 'kernel32.dll';
function GetVolumeNameForVolumeMountPointW(lpszVolumeMountPoint: LPCWSTR; lpszVolumeName: LPWSTR;
  cchBufferLength: DWORD): BOOL; stdcall; external 'kernel32.dll';
{$ENDIF}

type
  TStoragePropertyQuery = record
    PropertyId: DWORD;
    QueryType: DWORD;
    AdditionalParameters: array[0..3] of Byte;
  end;
  TDeviceSeekPenaltyDescriptor = record
    Version: DWORD;
    Size: DWORD;
    IncursSeekPenalty: ByteBool;
    Pad: array[0..2] of Byte;
  end;

function VolumeSeekPenalty(const Path: string; out Penalty: Boolean): Boolean;
var
  VolPath: array[0..MAX_PATH] of WideChar;
  VolName: array[0..63] of WideChar;
  Dev: string;
  H: THandle;
  Q: TStoragePropertyQuery;
  D: TDeviceSeekPenaltyDescriptor;
  Got: DWORD;
  L: Integer;
begin
  Result := False;
  Penalty := False;
  if not GetVolumePathNameW(PWideChar(Path), VolPath, Length(VolPath)) then Exit;
  if (VolPath[0] = '\') and (VolPath[1] = '\') then Exit;          // a network share
  // \\?\Volume{...}\ for any local volume (also one mounted in a folder); a plain X: otherwise
  if GetVolumeNameForVolumeMountPointW(VolPath, VolName, Length(VolName)) then
  begin
    Dev := VolName;
    L := Length(Dev);
    if (L > 0) and (Dev[L] = '\') then SetLength(Dev, L - 1);     // the volume itself, not its root folder
  end
  else if VolPath[1] = ':' then
    Dev := '\\.\' + VolPath[0] + ':'
  else
    Exit;
  // no access rights needed for this query, so it works without admin
  H := CreateFileW(PWideChar(Dev), 0, FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
  if H = INVALID_HANDLE_VALUE then Exit;
  try
    FillChar(Q, SizeOf(Q), 0);
    Q.PropertyId := StorageDeviceSeekPenaltyProperty;
    Q.QueryType := PropertyStandardQuery;
    FillChar(D, SizeOf(D), 0);
    if not DeviceIoControl(H, IOCTL_STORAGE_QUERY_PROPERTY, @Q, SizeOf(Q), @D, SizeOf(D), Got, nil) then Exit;
    if Got < 9 then Exit;
    Penalty := D.IncursSeekPenalty;
    Result := True;
  finally
    CloseHandle(H);
  end;
end;

function LogicalCpuCount: Integer;
var
  SI: TSystemInfo;
begin
  GetSystemInfo(SI);
  Result := SI.dwNumberOfProcessors;
  if Result < 1 then Result := 1;
end;

function HashThreadCount(const Path: string): Integer;
var
  Penalty: Boolean;
begin
  if HashThreadsOverride > 0 then
    Result := HashThreadsOverride
  else if VolumeSeekPenalty(Path, Penalty) and Penalty then
    Result := 1
  else
    Result := LogicalCpuCount - SpareCpus;
  if Result < 1 then Result := 1;
  if Result > MaxHashThreads then Result := MaxHashThreads;
end;

function ExtendedPath(const Path: string): string;
begin
  if (Length(Path) < 240) or (Copy(Path, 1, 4) = '\\?\') then
    Result := Path
  else if Copy(Path, 1, 2) = '\\' then
    Result := '\\?\UNC\' + Copy(Path, 3, MaxInt)
  else
    Result := '\\?\' + Path;
end;

procedure AddBytes(var Target: Int64; N: Int64);
begin
  {$IFDEF FPC}
  InterLockedExchangeAdd64(Target, N);
  {$ELSE}
  AtomicIncrement(Target, N);
  {$ENDIF}
end;

procedure LowerTo(var Target: LongInt; Value: LongInt);
var
  Old: LongInt;
begin
  repeat
    Old := Target;
    if Value >= Old then Exit;
  until InterlockedCompareExchange(Target, Value, Old) = Old;
end;

end.
