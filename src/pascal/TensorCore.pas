{ TensorCore.pas – Tensor primitives: shape management, allocation, matmul, transpose, add, scale, random init
  Line count: 250
  Dependency: none (uses Math, SysUtils only)
}

unit TensorCore;

interface

uses
  SysUtils, Math;

const
  EPSILON = 1e-7;

type
  TVector = array of Single;
  TMatrix = array of TVector;
  TTensor = array of TMatrix;

  { Shape descriptor for arbitrary tensors }
  TShape = record
    Rank: Integer;
    Dims: array [0..3] of Integer;
    procedure Init(D0, D1, D2, D3: Integer);
    function TotalSize: Integer;
    function ToString: string;
  end;

  { Tensor record: contains data and shape metadata }
  TTensorData = record
    Data: TVector;
    Shape: TShape;
    procedure Allocate(const AShape: TShape);
    procedure Fill(Value: Single);
    function Get(const Indices: array of Integer): Single;
    procedure Set_(const Indices: array of Integer; Value: Single);
    procedure Copy(const Source: TTensorData);
  end;

  { Core operations on tensors }
  TensorOps = class
  public
    { Initialization }
    class procedure Zeros(var T: TTensorData; const AShape: TShape);
    class procedure Ones(var T: TTensorData; const AShape: TShape);
    class procedure RandomUniform(var T: TTensorData; const AShape: TShape; Min, Max: Single);
    class procedure RandomNormal(var T: TTensorData; const AShape: TShape; Mean, StdDev: Single);
    class procedure XavierInit(var T: TTensorData; const AShape: TShape);

    { Arithmetic }
    class procedure Add(var Result: TTensorData; const A, B: TTensorData);
    class procedure Scale(var T: TTensorData; Factor: Single);
    class procedure Multiply(var Result: TTensorData; const A, B: TTensorData);
    class procedure AddScaled(var Result: TTensorData; const A, B: TTensorData; Scale: Single);

    { Linear algebra }
    class procedure MatMul(var Result: TTensorData; const A, B: TTensorData);
    class procedure Transpose(var Result: TTensorData; const T: TTensorData);
    class procedure TransposeBatched(var Result: TTensorData; const T: TTensorData);

    { Reductions }
    class function Sum(const T: TTensorData): Single;
    class procedure ReduceMean(var Result: TTensorData; const T: TTensorData; Axis: Integer);
    class procedure ReduceVar(var Result: TTensorData; const T: TTensorData; Axis: Integer);

    { I/O }
    class procedure SaveBinary(const Filename: string; const T: TTensorData);
    class procedure LoadBinary(var T: TTensorData; const Filename: string);
  end;

implementation

{ TShape }
procedure TShape.Init(D0, D1, D2, D3: Integer);
begin
  Rank := 0;
  Dims[0] := 0; Dims[1] := 0; Dims[2] := 0; Dims[3] := 0;
  if D0 > 0 then begin Dims[0] := D0; Rank := 1; end;
  if D1 > 0 then begin Dims[1] := D1; Rank := 2; end;
  if D2 > 0 then begin Dims[2] := D2; Rank := 3; end;
  if D3 > 0 then begin Dims[3] := D3; Rank := 4; end;
end;

function TShape.TotalSize: Integer;
var i: Integer;
begin
  if Rank = 0 then Exit(0);
  Result := 1;
  for i := 0 to Rank - 1 do
    Result := Result * Dims[i];
end;

function TShape.ToString: string;
var i: Integer;
begin
  Result := '[';
  for i := 0 to Rank - 1 do begin
    Result := Result + IntToStr(Dims[i]);
    if i < Rank - 1 then Result := Result + ', ';
  end;
  Result := Result + ']';
end;

{ TTensorData }
procedure TTensorData.Allocate(const AShape: TShape);
begin
  Shape := AShape;
  SetLength(Data, Shape.TotalSize);
  if Length(Data) > 0 then
    FillChar(Data[0], Length(Data) * SizeOf(Single), 0);
end;

procedure TTensorData.Fill(Value: Single);
var i: Integer;
begin
  for i := 0 to Length(Data) - 1 do
    Data[i] := Value;
end;

function TTensorData.Get(const Indices: array of Integer): Single;
var Offset, i, Stride: Integer;
begin
  Offset := 0;
  Stride := 1;
  for i := Length(Indices) - 1 downto 0 do begin
    Offset := Offset + Indices[i] * Stride;
    if i > 0 then Stride := Stride * Shape.Dims[i];
  end;
  Result := Data[Offset];
end;

procedure TTensorData.Set_(const Indices: array of Integer; Value: Single);
var Offset, i, Stride: Integer;
begin
  Offset := 0;
  Stride := 1;
  for i := Length(Indices) - 1 downto 0 do begin
    Offset := Offset + Indices[i] * Stride;
    if i > 0 then Stride := Stride * Shape.Dims[i];
  end;
  Data[Offset] := Value;
end;

procedure TTensorData.Copy(const Source: TTensorData);
begin
  Allocate(Source.Shape);
  if Length(Data) > 0 then
    Move(Source.Data[0], Data[0], Length(Data) * SizeOf(Single));
end;

{ TensorOps }
class procedure TensorOps.Zeros(var T: TTensorData; const AShape: TShape);
begin
  T.Allocate(AShape);
  T.Fill(0);
end;

class procedure TensorOps.Ones(var T: TTensorData; const AShape: TShape);
begin
  T.Allocate(AShape);
  T.Fill(1);
end;

class procedure TensorOps.RandomUniform(var T: TTensorData; const AShape: TShape; Min, Max: Single);
var i: Integer;
begin
  T.Allocate(AShape);
  for i := 0 to Length(T.Data) - 1 do
    T.Data[i] := Min + (Max - Min) * Random;
end;

class procedure TensorOps.RandomNormal(var T: TTensorData; const AShape: TShape; Mean, StdDev: Single);
var i, n: Integer; u1, u2: Single;
begin
  T.Allocate(AShape);
  n := Length(T.Data);
  i := 0;
  while i < n do begin
    u1 := Random + 1e-12;
    u2 := Random;
    if i + 1 < n then begin
      T.Data[i]     := Mean + StdDev * Sqrt(-2 * Ln(u1)) * Cos(2 * Pi * u2);
      T.Data[i + 1] := Mean + StdDev * Sqrt(-2 * Ln(u1)) * Sin(2 * Pi * u2);
      Inc(i, 2);
    end else begin
      T.Data[i] := Mean + StdDev * Sqrt(-2 * Ln(u1)) * Cos(2 * Pi * u2);
      Inc(i);
    end;
  end;
end;

class procedure TensorOps.XavierInit(var T: TTensorData; const AShape: TShape);
var FanIn, FanOut, Limit: Single;
begin
  if AShape.Rank < 2 then raise Exception.Create('Xavier init requires rank >= 2');
  FanIn  := AShape.Dims[1];
  FanOut := AShape.Dims[0];
  Limit  := Sqrt(6.0 / (FanIn + FanOut));
  RandomUniform(T, AShape, -Limit, Limit);
end;

class procedure TensorOps.Add(var Result: TTensorData; const A, B: TTensorData);
var i: Integer;
begin
  if A.Shape.TotalSize <> B.Shape.TotalSize then
    raise Exception.Create('Shape mismatch in Add');
  Result.Allocate(A.Shape);
  for i := 0 to Length(A.Data) - 1 do
    Result.Data[i] := A.Data[i] + B.Data[i];
end;

class procedure TensorOps.Scale(var T: TTensorData; Factor: Single);
var i: Integer;
begin
  for i := 0 to Length(T.Data) - 1 do
    T.Data[i] := T.Data[i] * Factor;
end;

class procedure TensorOps.Multiply(var Result: TTensorData; const A, B: TTensorData);
var i: Integer;
begin
  if A.Shape.TotalSize <> B.Shape.TotalSize then
    raise Exception.Create('Shape mismatch in Multiply');
  Result.Allocate(A.Shape);
  for i := 0 to Length(A.Data) - 1 do
    Result.Data[i] := A.Data[i] * B.Data[i];
end;

class procedure TensorOps.AddScaled(var Result: TTensorData; const A, B: TTensorData; Scale: Single);
var i: Integer;
begin
  if A.Shape.TotalSize <> B.Shape.TotalSize then
    raise Exception.Create('Shape mismatch in AddScaled');
  if Result.Shape.TotalSize <> A.Shape.TotalSize then
    Result.Allocate(A.Shape);
  for i := 0 to Length(A.Data) - 1 do
    Result.Data[i] := A.Data[i] + Scale * B.Data[i];
end;

class procedure TensorOps.MatMul(var Result: TTensorData; const A, B: TTensorData);
var M, N, K, i, j, k: Integer; Sum: Single; ResShape: TShape;
begin
  if (A.Shape.Rank <> 2) or (B.Shape.Rank <> 2) then
    raise Exception.Create('MatMul requires 2D tensors');
  if A.Shape.Dims[1] <> B.Shape.Dims[0] then
    raise Exception.Create('Incompatible dimensions for MatMul');
  M := A.Shape.Dims[0]; K := A.Shape.Dims[1]; N := B.Shape.Dims[1];
  ResShape.Init(M, N, 0, 0);
  Result.Allocate(ResShape);
  for i := 0 to M - 1 do
    for j := 0 to N - 1 do begin
      Sum := 0;
      for k := 0 to K - 1 do
        Sum := Sum + A.Data[i * K + k] * B.Data[k * N + j];
      Result.Data[i * N + j] := Sum;
    end;
end;

class procedure TensorOps.Transpose(var Result: TTensorData; const T: TTensorData);
var M, N, i, j: Integer; ResShape: TShape;
begin
  if T.Shape.Rank <> 2 then raise Exception.Create('Transpose requires 2D tensor');
  M := T.Shape.Dims[0]; N := T.Shape.Dims[1];
  ResShape.Init(N, M, 0, 0);
  Result.Allocate(ResShape);
  for i := 0 to M - 1 do
    for j := 0 to N - 1 do
      Result.Data[j * M + i] := T.Data[i * N + j];
end;

class procedure TensorOps.TransposeBatched(var Result: TTensorData; const T: TTensorData);
var B, M, N, b, i, j: Integer; ResShape: TShape;
begin
  if T.Shape.Rank < 3 then raise Exception.Create('TransposeBatched requires rank >= 3');
  B := T.Shape.Dims[0]; M := T.Shape.Dims[1]; N := T.Shape.Dims[2];
  ResShape.Init(B, N, M, 0);
  Result.Allocate(ResShape);
  for b := 0 to B - 1 do
    for i := 0 to M - 1 do
      for j := 0 to N - 1 do
        Result.Data[b * N * M + j * M + i] := T.Data[b * M * N + i * N + j];
end;

class function TensorOps.Sum(const T: TTensorData): Single;
var i: Integer;
begin
  Result := 0;
  for i := 0 to Length(T.Data) - 1 do Result := Result + T.Data[i];
end;

class procedure TensorOps.ReduceMean(var Result: TTensorData; const T: TTensorData; Axis: Integer);
var OutShape: TShape; OutSize, InAxisSize, i: Integer;
begin
  if Axis >= T.Shape.Rank then raise Exception.Create('Axis out of bounds in ReduceMean');
  OutShape := T.Shape;
  InAxisSize := T.Shape.Dims[Axis];
  OutShape.Dims[Axis] := 1;
  Result.Allocate(OutShape);
  Result.Fill(0);
  OutSize := OutShape.TotalSize;
  for i := 0 to Length(T.Data) - 1 do
    Result.Data[i mod OutSize] := Result.Data[i mod OutSize] + T.Data[i] / InAxisSize;
end;

class procedure TensorOps.ReduceVar(var Result: TTensorData; const T: TTensorData; Axis: Integer);
var Mean: TTensorData; i: Integer;
begin
  ReduceMean(Mean, T, Axis);
  Result.Allocate(Mean.Shape);
  Result.Fill(0);
  for i := 0 to Length(T.Data) - 1 do
    Result.Data[i mod Length(Result.Data)] :=
      Result.Data[i mod Length(Result.Data)] +
      Sqr(T.Data[i] - Mean.Data[i mod Length(Result.Data)]) / T.Shape.Dims[Axis];
end;

class procedure TensorOps.SaveBinary(const Filename: string; const T: TTensorData);
var F: File; i, n: Integer;
begin
  AssignFile(F, Filename); Rewrite(F, 1);
  BlockWrite(F, T.Shape.Rank, SizeOf(Integer));
  for i := 0 to 3 do BlockWrite(F, T.Shape.Dims[i], SizeOf(Integer));
  n := Length(T.Data);
  BlockWrite(F, n, SizeOf(Integer));
  if n > 0 then BlockWrite(F, T.Data[0], n * SizeOf(Single));
  CloseFile(F);
end;

class procedure TensorOps.LoadBinary(var T: TTensorData; const Filename: string);
var F: File; i, Size: Integer;
begin
  AssignFile(F, Filename); Reset(F, 1);
  BlockRead(F, T.Shape.Rank, SizeOf(Integer));
  for i := 0 to 3 do BlockRead(F, T.Shape.Dims[i], SizeOf(Integer));
  BlockRead(F, Size, SizeOf(Integer));
  T.Allocate(T.Shape);
  if Size > 0 then BlockRead(F, T.Data[0], Size * SizeOf(Single));
  CloseFile(F);
end;

end.
