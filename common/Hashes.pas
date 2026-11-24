unit Hashes;

{ Hash algorithms for the Checksums area and the checksum program it makes (from the Checksum Applet Creator).
  Deliberately uses only the System unit (no SysUtils/Classes) so the checksum program stays tiny.
  Algorithms: MD2, MD4, MD5, SHA1, SHA256/384/512, CRC32, Adler32, GOST R 34.11-94 (test parameters),
  RIPEMD128/160, Tiger128/160/192. Builds with Delphi and Free Pascal; tests\EngineTest checks both. }

{$IFDEF FPC}{$mode delphiunicode}{$H+}{$WARN 4110 OFF}{$ENDIF}
{$Q-,R-,O+}

interface

type
  THashAlgo = (haMD5, haMD2, haMD4, haSHA1, haSHA256, haSHA384, haSHA512,
    haCRC32, haAdler32, haGOST, haRIPEMD128, haRIPEMD160,
    haTiger128, haTiger160, haTiger192);

const
  HashNames: array[THashAlgo] of string = ('MD5', 'MD2', 'MD4', 'SHA1',
    'SHA256', 'SHA384', 'SHA512', 'CRC32', 'Adler32', 'GOST', 'RIPEMD128',
    'RIPEMD160', 'TIGER128', 'TIGER160', 'TIGER192');
  HashDigestBytes: array[THashAlgo] of Integer = (16, 16, 16, 20, 32, 48, 64,
    4, 4, 32, 16, 20, 16, 20, 24);

type
  TDigest = record
    Len: Integer;
    B: array[0..63] of Byte;
  end;

  THasher = class
  protected
    FBuf: array[0..127] of Byte;
    FFill: Integer;
    FLen: UInt64;
    function BlockSize: Integer; virtual;
    procedure Block(P: PByte); virtual; abstract;
    procedure PadMD(LenBytes: Integer; BigEndian: Boolean; PadByte: Byte);
  public
    constructor Create;
    procedure Reset; virtual;
    procedure Update(Data: Pointer; Len: NativeInt); virtual;
    procedure Final(out D: TDigest); virtual; abstract;
  end;

function NewHasher(A: THashAlgo): THasher;
function HashAlgoByName(const S: string; out A: THashAlgo): Boolean;
function DigestToHex(const D: TDigest): string;
function HexToDigest(const S: string; out D: TDigest): Boolean;
function DigestsEqual(const A, B: TDigest): Boolean;

implementation

{$I HashTables.inc}

type
  TCardArr = array[0..63] of Cardinal;
  PCardArr = ^TCardArr;
  TQuadArr = array[0..15] of UInt64;
  PQuadArr = ^TQuadArr;

function ROL32(X: Cardinal; N: Integer): Cardinal; inline;
begin
  Result := (X shl N) or (X shr (32 - N));
end;

function ROR32(X: Cardinal; N: Integer): Cardinal; inline;
begin
  Result := (X shr N) or (X shl (32 - N));
end;

function ROR64(X: UInt64; N: Integer): UInt64; inline;
begin
  Result := (X shr N) or (X shl (64 - N));
end;

function BSwap32(V: Cardinal): Cardinal; inline;
begin
  Result := (V shl 24) or ((V and $FF00) shl 8) or ((V shr 8) and $FF00) or (V shr 24);
end;

function BSwap64(V: UInt64): UInt64; inline;
begin
  Result := (UInt64(BSwap32(Cardinal(V))) shl 32) or BSwap32(Cardinal(V shr 32));
end;

procedure PutLE32(P: PByte; V: Cardinal);
begin
  PCardinal(P)^ := V;
end;

procedure PutBE32(P: PByte; V: Cardinal);
begin
  PCardinal(P)^ := BSwap32(V);
end;

procedure PutLE64(P: PByte; V: UInt64);
begin
  PUInt64(P)^ := V;
end;

procedure PutBE64(P: PByte; V: UInt64);
begin
  PUInt64(P)^ := BSwap64(V);
end;

{ ---------------------------------------------------------------- THasher }

constructor THasher.Create;
begin
  inherited Create;
  Reset;
end;

function THasher.BlockSize: Integer;
begin
  Result := 64;
end;

procedure THasher.Reset;
begin
  FFill := 0;
  FLen := 0;
end;

procedure THasher.Update(Data: Pointer; Len: NativeInt);
var
  P: PByte;
  BS, N: Integer;
begin
  P := Data;
  Inc(FLen, Len);
  BS := BlockSize;
  if FFill > 0 then
  begin
    N := BS - FFill;
    if N > Len then N := Len;
    Move(P^, FBuf[FFill], N);
    Inc(FFill, N);
    Inc(P, N);
    Dec(Len, N);
    if FFill = BS then
    begin
      Block(@FBuf[0]);
      FFill := 0;
    end;
  end;
  while Len >= BS do
  begin
    Block(P);
    Inc(P, BS);
    Dec(Len, BS);
  end;
  if Len > 0 then
  begin
    Move(P^, FBuf[0], Len);
    FFill := Len;
  end;
end;

procedure THasher.PadMD(LenBytes: Integer; BigEndian: Boolean; PadByte: Byte);
var
  Bits: UInt64;
  Pad: array[0..255] of Byte;
  PL, I: Integer;
begin
  Bits := FLen * 8;
  PL := BlockSize - LenBytes - FFill;
  if PL < 1 then Inc(PL, BlockSize);
  FillChar(Pad, SizeOf(Pad), 0);
  Pad[0] := PadByte;
  Update(@Pad[0], PL);
  FillChar(Pad, SizeOf(Pad), 0);
  for I := 0 to 7 do
    if BigEndian then
      Pad[LenBytes - 1 - I] := Byte(Bits shr (8 * I))
    else
      Pad[I] := Byte(Bits shr (8 * I));
  Update(@Pad[0], LenBytes);
end;

{ -------------------------------------------------------------------- MD5 }

type
  TMD5 = class(THasher)
  private
    FS: array[0..3] of Cardinal;
  protected
    procedure Block(P: PByte); override;
  public
    procedure Reset; override;
    procedure Final(out D: TDigest); override;
  end;

const
  MD5Shift: array[0..15] of Byte = (7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21);

procedure TMD5.Reset;
begin
  inherited;
  FS[0] := $67452301; FS[1] := $EFCDAB89; FS[2] := $98BADCFE; FS[3] := $10325476;
end;

procedure TMD5.Block(P: PByte);
var
  X: PCardArr;
  A, B, C, D, F, T: Cardinal;
  I, G: Integer;
begin
  X := PCardArr(P);
  A := FS[0]; B := FS[1]; C := FS[2]; D := FS[3];
  for I := 0 to 63 do
  begin
    case I shr 4 of
      0: begin F := (B and C) or (not B and D); G := I; end;
      1: begin F := (D and B) or (not D and C); G := (5 * I + 1) and 15; end;
      2: begin F := B xor C xor D; G := (3 * I + 5) and 15; end;
    else
      begin F := C xor (B or not D); G := (7 * I) and 15; end;
    end;
    T := D; D := C; C := B;
    B := B + ROL32(A + F + MD5K[I] + X^[G], MD5Shift[((I shr 4) shl 2) + (I and 3)]);
    A := T;
  end;
  Inc(FS[0], A); Inc(FS[1], B); Inc(FS[2], C); Inc(FS[3], D);
end;

procedure TMD5.Final(out D: TDigest);
var I: Integer;
begin
  PadMD(8, False, $80);
  D.Len := 16;
  for I := 0 to 3 do PutLE32(@D.B[I * 4], FS[I]);
end;

{ -------------------------------------------------------------------- MD4 }

type
  TMD4 = class(THasher)
  private
    FS: array[0..3] of Cardinal;
  protected
    procedure Block(P: PByte); override;
  public
    procedure Reset; override;
    procedure Final(out D: TDigest); override;
  end;

procedure TMD4.Reset;
begin
  inherited;
  FS[0] := $67452301; FS[1] := $EFCDAB89; FS[2] := $98BADCFE; FS[3] := $10325476;
end;

procedure TMD4.Block(P: PByte);
const
  K2: array[0..15] of Byte = (0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15);
  K3: array[0..15] of Byte = (0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15);
  S1: array[0..3] of Byte = (3, 7, 11, 19);
  S2: array[0..3] of Byte = (3, 5, 9, 13);
  S3: array[0..3] of Byte = (3, 9, 11, 15);
var
  X: PCardArr;
  A, B, C, D, T: Cardinal;
  I: Integer;
begin
  X := PCardArr(P);
  A := FS[0]; B := FS[1]; C := FS[2]; D := FS[3];
  for I := 0 to 15 do
  begin
    T := ROL32(A + ((B and C) or (not B and D)) + X^[I], S1[I and 3]);
    A := D; D := C; C := B; B := T;
  end;
  for I := 0 to 15 do
  begin
    T := ROL32(A + ((B and C) or (B and D) or (C and D)) + X^[K2[I]] + $5A827999, S2[I and 3]);
    A := D; D := C; C := B; B := T;
  end;
  for I := 0 to 15 do
  begin
    T := ROL32(A + (B xor C xor D) + X^[K3[I]] + $6ED9EBA1, S3[I and 3]);
    A := D; D := C; C := B; B := T;
  end;
  Inc(FS[0], A); Inc(FS[1], B); Inc(FS[2], C); Inc(FS[3], D);
end;

procedure TMD4.Final(out D: TDigest);
var I: Integer;
begin
  PadMD(8, False, $80);
  D.Len := 16;
  for I := 0 to 3 do PutLE32(@D.B[I * 4], FS[I]);
end;

{ -------------------------------------------------------------------- MD2 }

type
  TMD2 = class(THasher)
  private
    FX: array[0..47] of Byte;
    FC: array[0..15] of Byte;
    FL: Byte;
    procedure Mix(P: PByte);
  protected
    function BlockSize: Integer; override;
    procedure Block(P: PByte); override;
  public
    procedure Reset; override;
    procedure Final(out D: TDigest); override;
  end;

function TMD2.BlockSize: Integer;
begin
  Result := 16;
end;

procedure TMD2.Reset;
begin
  inherited;
  FillChar(FX, SizeOf(FX), 0);
  FillChar(FC, SizeOf(FC), 0);
  FL := 0;
end;

procedure TMD2.Mix(P: PByte);
var J, K, T: Integer;
begin
  for J := 0 to 15 do
  begin
    FX[16 + J] := P[J];
    FX[32 + J] := FX[16 + J] xor FX[J];
  end;
  T := 0;
  for J := 0 to 17 do
  begin
    for K := 0 to 47 do
    begin
      FX[K] := FX[K] xor MD2S[T];
      T := FX[K];
    end;
    T := (T + J) and 255;
  end;
end;

procedure TMD2.Block(P: PByte);
var J: Integer;
begin
  for J := 0 to 15 do
  begin
    FC[J] := FC[J] xor MD2S[P[J] xor FL];
    FL := FC[J];
  end;
  Mix(P);
end;

procedure TMD2.Final(out D: TDigest);
var
  Pad: array[0..15] of Byte;
  N: Integer;
  Sum: array[0..15] of Byte;
begin
  N := 16 - FFill;
  FillChar(Pad, SizeOf(Pad), N);
  Update(@Pad[0], N);
  Move(FC, Sum, 16);
  Mix(@Sum[0]);
  D.Len := 16;
  Move(FX, D.B, 16);
end;

{ ------------------------------------------------------------------- SHA-1 }

type
  TSHA1 = class(THasher)
  private
    FS: array[0..4] of Cardinal;
  protected
    procedure Block(P: PByte); override;
  public
    procedure Reset; override;
    procedure Final(out D: TDigest); override;
  end;

procedure TSHA1.Reset;
begin
  inherited;
  FS[0] := $67452301; FS[1] := $EFCDAB89; FS[2] := $98BADCFE;
  FS[3] := $10325476; FS[4] := $C3D2E1F0;
end;

procedure TSHA1.Block(P: PByte);
var
  W: array[0..79] of Cardinal;
  A, B, C, D, E, F, K, T: Cardinal;
  I: Integer;
begin
  for I := 0 to 15 do W[I] := BSwap32(PCardinal(P + I * 4)^);
  for I := 16 to 79 do W[I] := ROL32(W[I - 3] xor W[I - 8] xor W[I - 14] xor W[I - 16], 1);
  A := FS[0]; B := FS[1]; C := FS[2]; D := FS[3]; E := FS[4];
  for I := 0 to 79 do
  begin
    case I div 20 of
      0: begin F := (B and C) or (not B and D); K := $5A827999; end;
      1: begin F := B xor C xor D; K := $6ED9EBA1; end;
      2: begin F := (B and C) or (B and D) or (C and D); K := $8F1BBCDC; end;
    else
      begin F := B xor C xor D; K := $CA62C1D6; end;
    end;
    T := ROL32(A, 5) + F + E + K + W[I];
    E := D; D := C; C := ROL32(B, 30); B := A; A := T;
  end;
  Inc(FS[0], A); Inc(FS[1], B); Inc(FS[2], C); Inc(FS[3], D); Inc(FS[4], E);
end;

procedure TSHA1.Final(out D: TDigest);
var I: Integer;
begin
  PadMD(8, True, $80);
  D.Len := 20;
  for I := 0 to 4 do PutBE32(@D.B[I * 4], FS[I]);
end;

{ ----------------------------------------------------------------- SHA-256 }

type
  TSHA256 = class(THasher)
  private
    FS: array[0..7] of Cardinal;
  protected
    procedure Block(P: PByte); override;
  public
    procedure Reset; override;
    procedure Final(out D: TDigest); override;
  end;

procedure TSHA256.Reset;
begin
  inherited;
  Move(SHA256IV, FS, SizeOf(FS));
end;

procedure TSHA256.Block(P: PByte);
var
  W: array[0..63] of Cardinal;
  A, B, C, D, E, F, G, H, T1, T2: Cardinal;
  I: Integer;
begin
  for I := 0 to 15 do W[I] := BSwap32(PCardinal(P + I * 4)^);
  for I := 16 to 63 do
    W[I] := (ROR32(W[I - 2], 17) xor ROR32(W[I - 2], 19) xor (W[I - 2] shr 10)) + W[I - 7] +
      (ROR32(W[I - 15], 7) xor ROR32(W[I - 15], 18) xor (W[I - 15] shr 3)) + W[I - 16];
  A := FS[0]; B := FS[1]; C := FS[2]; D := FS[3];
  E := FS[4]; F := FS[5]; G := FS[6]; H := FS[7];
  for I := 0 to 63 do
  begin
    T1 := H + (ROR32(E, 6) xor ROR32(E, 11) xor ROR32(E, 25)) + ((E and F) xor (not E and G)) + SHA256K[I] + W[I];
    T2 := (ROR32(A, 2) xor ROR32(A, 13) xor ROR32(A, 22)) + ((A and B) xor (A and C) xor (B and C));
    H := G; G := F; F := E; E := D + T1; D := C; C := B; B := A; A := T1 + T2;
  end;
  Inc(FS[0], A); Inc(FS[1], B); Inc(FS[2], C); Inc(FS[3], D);
  Inc(FS[4], E); Inc(FS[5], F); Inc(FS[6], G); Inc(FS[7], H);
end;

procedure TSHA256.Final(out D: TDigest);
var I: Integer;
begin
  PadMD(8, True, $80);
  D.Len := 32;
  for I := 0 to 7 do PutBE32(@D.B[I * 4], FS[I]);
end;

{ -------------------------------------------------------- SHA-384 / SHA-512 }

type
  TSHA512 = class(THasher)
  private
    FS: array[0..7] of UInt64;
    F384: Boolean;
  protected
    function BlockSize: Integer; override;
    procedure Block(P: PByte); override;
  public
    procedure Reset; override;
    procedure Final(out D: TDigest); override;
  end;

function TSHA512.BlockSize: Integer;
begin
  Result := 128;
end;

procedure TSHA512.Reset;
begin
  inherited;
  if F384 then Move(SHA384IV, FS, SizeOf(FS)) else Move(SHA512IV, FS, SizeOf(FS));
end;

procedure TSHA512.Block(P: PByte);
var
  W: array[0..79] of UInt64;
  A, B, C, D, E, F, G, H, T1, T2: UInt64;
  I: Integer;
begin
  for I := 0 to 15 do W[I] := BSwap64(PUInt64(P + I * 8)^);
  for I := 16 to 79 do
    W[I] := (ROR64(W[I - 2], 19) xor ROR64(W[I - 2], 61) xor (W[I - 2] shr 6)) + W[I - 7] +
      (ROR64(W[I - 15], 1) xor ROR64(W[I - 15], 8) xor (W[I - 15] shr 7)) + W[I - 16];
  A := FS[0]; B := FS[1]; C := FS[2]; D := FS[3];
  E := FS[4]; F := FS[5]; G := FS[6]; H := FS[7];
  for I := 0 to 79 do
  begin
    T1 := H + (ROR64(E, 14) xor ROR64(E, 18) xor ROR64(E, 41)) + ((E and F) xor (not E and G)) + SHA512K[I] + W[I];
    T2 := (ROR64(A, 28) xor ROR64(A, 34) xor ROR64(A, 39)) + ((A and B) xor (A and C) xor (B and C));
    H := G; G := F; F := E; E := D + T1; D := C; C := B; B := A; A := T1 + T2;
  end;
  Inc(FS[0], A); Inc(FS[1], B); Inc(FS[2], C); Inc(FS[3], D);
  Inc(FS[4], E); Inc(FS[5], F); Inc(FS[6], G); Inc(FS[7], H);
end;

procedure TSHA512.Final(out D: TDigest);
var I: Integer;
begin
  PadMD(16, True, $80);
  for I := 0 to 7 do PutBE64(@D.B[I * 8], FS[I]);
  if F384 then D.Len := 48 else D.Len := 64;
end;

{ ------------------------------------------------------- CRC32 and Adler32 }

var
  CRCTable: array[0..255] of Cardinal;

type
  TCRC32 = class(THasher)
  private
    FCRC: Cardinal;
  protected
    procedure Block(P: PByte); override;
  public
    procedure Reset; override;
    procedure Update(Data: Pointer; Len: NativeInt); override;
    procedure Final(out D: TDigest); override;
  end;

procedure TCRC32.Reset;
begin
  inherited;
  FCRC := $FFFFFFFF;
end;

procedure TCRC32.Block(P: PByte);
begin
end;

procedure TCRC32.Update(Data: Pointer; Len: NativeInt);
var
  P: PByte;
  C: Cardinal;
begin
  P := Data;
  C := FCRC;
  while Len > 0 do
  begin
    C := CRCTable[Byte(C) xor P^] xor (C shr 8);
    Inc(P);
    Dec(Len);
  end;
  FCRC := C;
end;

procedure TCRC32.Final(out D: TDigest);
begin
  D.Len := 4;
  PutBE32(@D.B[0], not FCRC);
end;

type
  TAdler32 = class(THasher)
  private
    FA, FB: Cardinal;
  protected
    procedure Block(P: PByte); override;
  public
    procedure Reset; override;
    procedure Update(Data: Pointer; Len: NativeInt); override;
    procedure Final(out D: TDigest); override;
  end;

procedure TAdler32.Reset;
begin
  inherited;
  FA := 1;
  FB := 0;
end;

procedure TAdler32.Block(P: PByte);
begin
end;

procedure TAdler32.Update(Data: Pointer; Len: NativeInt);
var
  P: PByte;
  A, B: Cardinal;
  N: Integer;
begin
  P := Data;
  A := FA;
  B := FB;
  while Len > 0 do
  begin
    if Len > 5552 then N := 5552 else N := Len;
    Dec(Len, N);
    while N > 0 do
    begin
      Inc(A, P^);
      Inc(B, A);
      Inc(P);
      Dec(N);
    end;
    A := A mod 65521;
    B := B mod 65521;
  end;
  FA := A;
  FB := B;
end;

procedure TAdler32.Final(out D: TDigest);
begin
  D.Len := 4;
  PutBE32(@D.B[0], (FB shl 16) or FA);
end;

{ ----------------------------------------------------- RIPEMD-128 / 160 }

type
  TRIPEMD = class(THasher)
  private
    FS: array[0..4] of Cardinal;
    F160: Boolean;
  protected
    procedure Block(P: PByte); override;
  public
    procedure Reset; override;
    procedure Final(out D: TDigest); override;
  end;

const
  RMD_R: array[0..79] of Byte = (
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
    3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
    1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
    4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13);
  RMD_RP: array[0..79] of Byte = (
    5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
    6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
    15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
    8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
    12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11);
  RMD_S: array[0..79] of Byte = (
    11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
    7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
    11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
    11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
    9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6);
  RMD_SP: array[0..79] of Byte = (
    8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
    9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
    9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
    15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
    8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11);
  RMD_K: array[0..4] of Cardinal = ($00000000, $5A827999, $6ED9EBA1, $8F1BBCDC, $A953FD4E);
  RMD_KP160: array[0..4] of Cardinal = ($50A28BE6, $5C4DD124, $6D703EF3, $7A6D76E9, $00000000);
  RMD_KP128: array[0..3] of Cardinal = ($50A28BE6, $5C4DD124, $6D703EF3, $00000000);

function RMDF(J: Integer; X, Y, Z: Cardinal): Cardinal; inline;
begin
  case J shr 4 of
    0: Result := X xor Y xor Z;
    1: Result := (X and Y) or (not X and Z);
    2: Result := (X or not Y) xor Z;
    3: Result := (X and Z) or (Y and not Z);
  else
    Result := X xor (Y or not Z);
  end;
end;

procedure TRIPEMD.Reset;
begin
  inherited;
  FS[0] := $67452301; FS[1] := $EFCDAB89; FS[2] := $98BADCFE;
  FS[3] := $10325476; FS[4] := $C3D2E1F0;
end;

procedure TRIPEMD.Block(P: PByte);
var
  X: PCardArr;
  A, B, C, D, E, AP, BP, CP, DP, EP, T: Cardinal;
  J: Integer;
begin
  X := PCardArr(P);
  A := FS[0]; B := FS[1]; C := FS[2]; D := FS[3]; E := FS[4];
  AP := A; BP := B; CP := C; DP := D; EP := E;
  if F160 then
  begin
    for J := 0 to 79 do
    begin
      T := ROL32(A + RMDF(J, B, C, D) + X^[RMD_R[J]] + RMD_K[J shr 4], RMD_S[J]) + E;
      A := E; E := D; D := ROL32(C, 10); C := B; B := T;
      T := ROL32(AP + RMDF(79 - J, BP, CP, DP) + X^[RMD_RP[J]] + RMD_KP160[J shr 4], RMD_SP[J]) + EP;
      AP := EP; EP := DP; DP := ROL32(CP, 10); CP := BP; BP := T;
    end;
    T := FS[1] + C + DP;
    FS[1] := FS[2] + D + EP;
    FS[2] := FS[3] + E + AP;
    FS[3] := FS[4] + A + BP;
    FS[4] := FS[0] + B + CP;
    FS[0] := T;
  end
  else
  begin
    for J := 0 to 63 do
    begin
      T := ROL32(A + RMDF(J, B, C, D) + X^[RMD_R[J]] + RMD_K[J shr 4], RMD_S[J]);
      A := D; D := C; C := B; B := T;
      T := ROL32(AP + RMDF(63 - J, BP, CP, DP) + X^[RMD_RP[J]] + RMD_KP128[J shr 4], RMD_SP[J]);
      AP := DP; DP := CP; CP := BP; BP := T;
    end;
    T := FS[1] + C + DP;
    FS[1] := FS[2] + D + AP;
    FS[2] := FS[3] + A + BP;
    FS[3] := FS[0] + B + CP;
    FS[0] := T;
  end;
end;

procedure TRIPEMD.Final(out D: TDigest);
var I, N: Integer;
begin
  PadMD(8, False, $80);
  if F160 then N := 5 else N := 4;
  D.Len := N * 4;
  for I := 0 to N - 1 do PutLE32(@D.B[I * 4], FS[I]);
end;

{ ------------------------------------------------------------------ Tiger }

type
  TTiger = class(THasher)
  private
    FA, FB, FC: UInt64;
    FOutLen: Integer;
  protected
    procedure Block(P: PByte); override;
  public
    procedure Reset; override;
    procedure Final(out D: TDigest); override;
  end;

procedure TigerRound(var A, B, C: UInt64; X, Mul: UInt64); inline;
begin
  C := C xor X;
  A := A - (TigerSBox[Byte(C)] xor TigerSBox[256 + Byte(C shr 16)] xor
    TigerSBox[512 + Byte(C shr 32)] xor TigerSBox[768 + Byte(C shr 48)]);
  B := B + (TigerSBox[768 + Byte(C shr 8)] xor TigerSBox[512 + Byte(C shr 24)] xor
    TigerSBox[256 + Byte(C shr 40)] xor TigerSBox[Byte(C shr 56)]);
  B := B * Mul;
end;

procedure TTiger.Reset;
begin
  inherited;
  FA := $0123456789ABCDEF;
  FB := $FEDCBA9876543210;
  FC := $F096A5B4C3B2E187;
end;

procedure TTiger.Block(P: PByte);
var
  X: array[0..7] of UInt64;
  A, B, C, AA, BB, CC: UInt64;

  procedure Pass(var A, B, C: UInt64; Mul: UInt64);
  begin
    TigerRound(A, B, C, X[0], Mul);
    TigerRound(B, C, A, X[1], Mul);
    TigerRound(C, A, B, X[2], Mul);
    TigerRound(A, B, C, X[3], Mul);
    TigerRound(B, C, A, X[4], Mul);
    TigerRound(C, A, B, X[5], Mul);
    TigerRound(A, B, C, X[6], Mul);
    TigerRound(B, C, A, X[7], Mul);
  end;

  procedure KeySchedule;
  begin
    X[0] := X[0] - (X[7] xor $A5A5A5A5A5A5A5A5);
    X[1] := X[1] xor X[0];
    X[2] := X[2] + X[1];
    X[3] := X[3] - (X[2] xor ((not X[1]) shl 19));
    X[4] := X[4] xor X[3];
    X[5] := X[5] + X[4];
    X[6] := X[6] - (X[5] xor ((not X[4]) shr 23));
    X[7] := X[7] xor X[6];
    X[0] := X[0] + X[7];
    X[1] := X[1] - (X[0] xor ((not X[7]) shl 19));
    X[2] := X[2] xor X[1];
    X[3] := X[3] + X[2];
    X[4] := X[4] - (X[3] xor ((not X[2]) shr 23));
    X[5] := X[5] xor X[4];
    X[6] := X[6] + X[5];
    X[7] := X[7] - (X[6] xor $0123456789ABCDEF);
  end;

begin
  Move(P^, X, 64);
  A := FA; B := FB; C := FC;
  AA := A; BB := B; CC := C;
  Pass(A, B, C, 5);
  KeySchedule;
  Pass(C, A, B, 7);
  KeySchedule;
  Pass(B, C, A, 9);
  FA := A xor AA;
  FB := B - BB;
  FC := C + CC;
end;

procedure TTiger.Final(out D: TDigest);
begin
  PadMD(8, False, $01);
  PutLE64(@D.B[0], FA);
  PutLE64(@D.B[8], FB);
  PutLE64(@D.B[16], FC);
  D.Len := FOutLen;
end;

{ ------------------------------------------------------------------- GOST }

type
  TGost32 = array[0..31] of Byte;

  TGOST = class(THasher)
  private
    FH, FSum: TGost32;
    procedure Step(var H: TGost32; const M: TGost32);
  protected
    function BlockSize: Integer; override;
    procedure Block(P: PByte); override;
  public
    procedure Reset; override;
    procedure Final(out D: TDigest); override;
  end;

const
  { GOST R 34.11-94 "test parameters" S-box (RFC 5831), row = nibble position }
  GostSBox: array[0..7, 0..15] of Byte = (
    (4, 10, 9, 2, 13, 8, 0, 14, 6, 11, 1, 12, 7, 15, 5, 3),
    (14, 11, 4, 12, 6, 13, 15, 10, 2, 3, 8, 1, 0, 7, 5, 9),
    (5, 8, 1, 13, 10, 3, 4, 2, 14, 15, 12, 7, 6, 0, 9, 11),
    (7, 13, 10, 1, 0, 8, 9, 15, 14, 4, 6, 12, 11, 2, 5, 3),
    (6, 12, 7, 1, 5, 15, 13, 8, 4, 10, 9, 14, 0, 3, 11, 2),
    (4, 11, 10, 0, 7, 2, 1, 13, 3, 6, 8, 5, 9, 12, 15, 14),
    (13, 11, 4, 1, 3, 15, 5, 9, 0, 10, 14, 7, 6, 8, 2, 12),
    (1, 15, 13, 0, 5, 7, 10, 4, 9, 2, 3, 14, 6, 11, 8, 12));
  { constant C3, little-endian byte order }
  GostC3: TGost32 = (
    $00, $FF, $00, $FF, $00, $FF, $00, $FF, $FF, $00, $FF, $00, $FF, $00, $FF, $00,
    $00, $FF, $FF, $00, $FF, $00, $00, $FF, $FF, $00, $00, $00, $FF, $FF, $00, $FF);

var
  { byte-wise S-box lookup, pre-rotated left by 11 }
  GostTab: array[0..3, 0..255] of Cardinal;

function GostF(X: Cardinal): Cardinal; inline;
begin
  Result := GostTab[0, Byte(X)] or GostTab[1, Byte(X shr 8)] or
    GostTab[2, Byte(X shr 16)] or GostTab[3, Byte(X shr 24)];
end;

{ GOST 28147-89, 32 rounds, written without the per-round swap:
  the low result word is B, the high word is A. }
procedure GostEncrypt(const Key: TGost32; Src, Dst: PByte);
var
  K: array[0..7] of Cardinal;
  A, B: Cardinal;
  I: Integer;
begin
  Move(Key, K, 32);
  A := PCardinal(Src)^;
  B := PCardinal(Src + 4)^;
  for I := 0 to 2 do
  begin
    B := B xor GostF(A + K[0]); A := A xor GostF(B + K[1]);
    B := B xor GostF(A + K[2]); A := A xor GostF(B + K[3]);
    B := B xor GostF(A + K[4]); A := A xor GostF(B + K[5]);
    B := B xor GostF(A + K[6]); A := A xor GostF(B + K[7]);
  end;
  B := B xor GostF(A + K[7]); A := A xor GostF(B + K[6]);
  B := B xor GostF(A + K[5]); A := A xor GostF(B + K[4]);
  B := B xor GostF(A + K[3]); A := A xor GostF(B + K[2]);
  B := B xor GostF(A + K[1]); A := A xor GostF(B + K[0]);
  PCardinal(Dst)^ := B;
  PCardinal(Dst + 4)^ := A;
end;

procedure GostA(var Y: TGost32);
var Q: array[0..3] of UInt64;
begin
  Move(Y, Q, 32);
  PUInt64(@Y[0])^ := Q[1];
  PUInt64(@Y[8])^ := Q[2];
  PUInt64(@Y[16])^ := Q[3];
  PUInt64(@Y[24])^ := Q[0] xor Q[1];
end;

procedure GostPsiN(var Y: TGost32; N: Integer);
var
  W: array[0..79] of Word;
  I: Integer;
begin
  Move(Y, W, 32);
  for I := 0 to N - 1 do
    W[16 + I] := W[I] xor W[I + 1] xor W[I + 2] xor W[I + 3] xor W[I + 12] xor W[I + 15];
  Move(W[N], Y, 32);
end;

procedure GostXor(var A: TGost32; const B: TGost32);
begin
  PUInt64(@A[0])^ := PUInt64(@A[0])^ xor PUInt64(@B[0])^;
  PUInt64(@A[8])^ := PUInt64(@A[8])^ xor PUInt64(@B[8])^;
  PUInt64(@A[16])^ := PUInt64(@A[16])^ xor PUInt64(@B[16])^;
  PUInt64(@A[24])^ := PUInt64(@A[24])^ xor PUInt64(@B[24])^;
end;

procedure GostP(const Y: TGost32; var Dst: TGost32);
var I, K: Integer;
begin
  for I := 0 to 3 do
    for K := 0 to 7 do
      Dst[I + 4 * K] := Y[8 * I + K];
end;

function TGOST.BlockSize: Integer;
begin
  Result := 32;
end;

procedure TGOST.Reset;
begin
  inherited;
  FillChar(FH, SizeOf(FH), 0);
  FillChar(FSum, SizeOf(FSum), 0);
end;

procedure TGOST.Step(var H: TGost32; const M: TGost32);
var
  U, V, W, S: TGost32;
  Keys: array[0..3] of TGost32;
  J, I: Integer;
begin
  U := H;
  V := M;
  W := U;
  GostXor(W, V);
  GostP(W, Keys[0]);
  for J := 1 to 3 do
  begin
    GostA(U);
    if J = 2 then GostXor(U, GostC3);
    GostA(V);
    GostA(V);
    W := U;
    GostXor(W, V);
    GostP(W, Keys[J]);
  end;
  for I := 0 to 3 do
    GostEncrypt(Keys[I], @H[8 * I], @S[8 * I]);
  GostPsiN(S, 12);
  GostXor(S, M);
  GostPsiN(S, 1);
  GostXor(S, H);
  GostPsiN(S, 61);
  H := S;
end;

procedure TGOST.Block(P: PByte);
var
  M: TGost32;
  I: Integer;
  C: Cardinal;
begin
  Move(P^, M, 32);
  Step(FH, M);
  C := 0;
  for I := 0 to 31 do
  begin
    C := C + FSum[I] + M[I];
    FSum[I] := Byte(C);
    C := C shr 8;
  end;
end;

procedure TGOST.Final(out D: TDigest);
var
  L: TGost32;
  Bits: UInt64;
begin
  Bits := FLen * 8;
  if FFill > 0 then
  begin
    FillChar(FBuf[FFill], 32 - FFill, 0);
    Block(@FBuf[0]);
  end;
  FillChar(L, SizeOf(L), 0);
  PUInt64(@L[0])^ := Bits;
  Step(FH, L);
  Step(FH, FSum);
  D.Len := 32;
  Move(FH, D.B, 32);
end;

{ ---------------------------------------------------------------- factory }

function NewHasher(A: THashAlgo): THasher;
begin
  case A of
    haMD5: Result := TMD5.Create;
    haMD2: Result := TMD2.Create;
    haMD4: Result := TMD4.Create;
    haSHA1: Result := TSHA1.Create;
    haSHA256: Result := TSHA256.Create;
    haSHA384:
      begin
        Result := TSHA512.Create;
        TSHA512(Result).F384 := True;
        Result.Reset;
      end;
    haSHA512: Result := TSHA512.Create;
    haCRC32: Result := TCRC32.Create;
    haAdler32: Result := TAdler32.Create;
    haGOST: Result := TGOST.Create;
    haRIPEMD128:
      begin
        Result := TRIPEMD.Create;
      end;
    haRIPEMD160:
      begin
        Result := TRIPEMD.Create;
        TRIPEMD(Result).F160 := True;
      end;
  else
    begin
      Result := TTiger.Create;
      TTiger(Result).FOutLen := HashDigestBytes[A];
    end;
  end;
end;

function UpCase8(C: Char): Char; inline;
begin
  if (C >= 'a') and (C <= 'z') then Result := Char(Ord(C) - 32) else Result := C;
end;

function HashAlgoByName(const S: string; out A: THashAlgo): Boolean;
var
  X: THashAlgo;
  I: Integer;
  Same: Boolean;
begin
  Result := False;
  for X := Low(THashAlgo) to High(THashAlgo) do
    if Length(S) = Length(HashNames[X]) then
    begin
      Same := True;
      for I := 1 to Length(S) do
        if UpCase8(S[I]) <> UpCase8(HashNames[X][I]) then
        begin
          Same := False;
          Break;
        end;
      if Same then
      begin
        A := X;
        Exit(True);
      end;
    end;
end;

function DigestToHex(const D: TDigest): string;
const
  Hex: array[0..15] of Char = '0123456789abcdef';
var I: Integer;
begin
  SetLength(Result, D.Len * 2);
  for I := 0 to D.Len - 1 do
  begin
    Result[I * 2 + 1] := Hex[D.B[I] shr 4];
    Result[I * 2 + 2] := Hex[D.B[I] and 15];
  end;
end;

function HexVal(C: Char): Integer; inline;
begin
  case C of
    '0'..'9': Result := Ord(C) - 48;
    'a'..'f': Result := Ord(C) - 87;
    'A'..'F': Result := Ord(C) - 55;
  else
    Result := -1;
  end;
end;

function HexToDigest(const S: string; out D: TDigest): Boolean;
var I, H, L: Integer;
begin
  Result := False;
  D.Len := 0;
  if (Length(S) = 0) or (Length(S) > 128) or Odd(Length(S)) then Exit;
  for I := 0 to Length(S) div 2 - 1 do
  begin
    H := HexVal(S[I * 2 + 1]);
    L := HexVal(S[I * 2 + 2]);
    if (H < 0) or (L < 0) then Exit;
    D.B[I] := Byte(H * 16 + L);
  end;
  D.Len := Length(S) div 2;
  Result := True;
end;

function DigestsEqual(const A, B: TDigest): Boolean;
var I: Integer;
begin
  Result := A.Len = B.Len;
  if Result then
    for I := 0 to A.Len - 1 do
      if A.B[I] <> B.B[I] then Exit(False);
end;

procedure InitTables;
var
  I, J, K: Integer;
  C: Cardinal;
  V: Cardinal;
begin
  for I := 0 to 255 do
  begin
    C := I;
    for J := 0 to 7 do
      if (C and 1) <> 0 then C := (C shr 1) xor $EDB88320 else C := C shr 1;
    CRCTable[I] := C;
  end;
  for K := 0 to 3 do
    for I := 0 to 255 do
    begin
      V := (Cardinal(GostSBox[2 * K, I and 15]) shl (8 * K)) or
        (Cardinal(GostSBox[2 * K + 1, I shr 4]) shl (8 * K + 4));
      GostTab[K, I] := ROL32(V, 11);
    end;
end;

initialization
  InitTables;

end.
