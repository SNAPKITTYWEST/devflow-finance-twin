{ gpu_host.pas
  Pascal host skeleton for launching CUDA kernels via a C shim.
  Free Pascal (FPC) compatible.
  Purpose:
    - Simple memory manager with bookkeeping and bounds checks
    - External C shim calls to allocate/free device memory and launch kernels
    - Test harness: vector add kernel launch and basic diagnostics
  Build: see build.sh
}

program GPUHost;

{$mode objfpc}{$H+}

uses
  ctypes, SysUtils;

{ -------------------------
  Simple memory manager
  ------------------------- }

type
  TBlockState = (bsAllocated, bsFreed);

  PBlock = ^TBlock;
  TBlock = record
    addr: Pointer;
    size: NativeUInt;
    state: TBlockState;
  end;

var
  Blocks: array of PBlock = nil;

procedure RegisterBlock(p: Pointer; sz: NativeUInt);
var
  b: PBlock;
begin
  New(b);
  b^.addr := p;
  b^.size := sz;
  b^.state := bsAllocated;
  SetLength(Blocks, Length(Blocks) + 1);
  Blocks[High(Blocks)] := b;
end;

function FindBlock(p: Pointer): Integer;
var
  i: Integer;
begin
  for i := 0 to High(Blocks) do
    if Blocks[i]^.addr = p then Exit(i);
  Result := -1;
end;

procedure MarkFreed(p: Pointer);
var
  idx: Integer;
begin
  idx := FindBlock(p);
  if idx = -1 then
    raise Exception.Create('MarkFreed: unknown pointer');
  if Blocks[idx]^.state = bsFreed then
    raise Exception.Create('MarkFreed: double free detected');
  Blocks[idx]^.state := bsFreed;
end;

procedure CheckLeaks;
var
  i: Integer;
begin
  for i := 0 to High(Blocks) do
    if Blocks[i]^.state = bsAllocated then
      Writeln('Memory leak: addr=', Blocks[i]^.addr, ' size=', Blocks[i]^.size);
end;

{ -------------------------
  C shim declarations
  (must match cuda_shim.c)
  ------------------------- }

type
  TCUResult = cint;

procedure cuda_init; cdecl; external 'libcuda_shim.so';
procedure cuda_finalize; cdecl; external 'libcuda_shim.so';
function cuda_alloc(size: NativeUInt): Pointer; cdecl; external 'libcuda_shim.so';
procedure cuda_free(p: Pointer); cdecl; external 'libcuda_shim.so';
function cuda_memcpy_h2d(dst: Pointer; src: Pointer; size: NativeUInt): TCUResult; cdecl; external 'libcuda_shim.so';
function cuda_memcpy_d2h(dst: Pointer; src: Pointer; size: NativeUInt): TCUResult; cdecl; external 'libcuda_shim.so';
function cuda_launch_vector_add(a_dev, b_dev, c_dev: Pointer; n: cint): TCUResult; cdecl; external 'libcuda_shim.so';
function cuda_launch_micro_op(a_dev, b_dev, c_dev: Pointer; n: cint): TCUResult; cdecl; external 'libcuda_shim.so';

{ -------------------------
  Pascal wrappers
  ------------------------- }

function HostAlloc(size: NativeUInt): Pointer;
begin
  Result := cuda_alloc(size);
  if Result = nil then
    raise Exception.Create('HostAlloc: cuda_alloc returned NULL');
  RegisterBlock(Result, size);
end;

procedure HostFree(p: Pointer);
begin
  MarkFreed(p);
  cuda_free(p);
end;

{ -------------------------
  Utility: allocate host buffer (malloc)
  ------------------------- }

function HostMalloc(size: NativeUInt): Pointer;
begin
  GetMem(Result, size);
  if Result = nil then
    raise Exception.Create('HostMalloc failed');
end;

procedure HostFreeMem(p: Pointer);
begin
  FreeMem(p);
end;

{ -------------------------
  Test: vector add on GPU
  - allocate host buffers, fill, copy to device, launch kernel, copy back
  ------------------------- }

procedure TestVectorAdd(n: Integer);
var
  bytes: NativeUInt;
  a_dev, b_dev, c_dev: Pointer;
  hostA, hostB, hostC: PSingle;
  i: Integer;
  res: TCUResult;
begin
  bytes := NativeUInt(n) * SizeOf(Single);

  Writeln('Allocating device buffers...');
  a_dev := HostAlloc(bytes);
  b_dev := HostAlloc(bytes);
  c_dev := HostAlloc(bytes);

  Writeln('Allocating host buffers...');
  hostA := HostMalloc(bytes);
  hostB := HostMalloc(bytes);
  hostC := HostMalloc(bytes);

  Writeln('Filling host buffers...');
  for i := 0 to n-1 do
  begin
    hostA[i] := i * 1.0;
    hostB[i] := (n - i) * 0.5;
  end;

  Writeln('Copying host->device...');
  res := cuda_memcpy_h2d(a_dev, hostA, bytes);
  if res <> 0 then raise Exception.Create('cuda_memcpy_h2d a failed');
  res := cuda_memcpy_h2d(b_dev, hostB, bytes);
  if res <> 0 then raise Exception.Create('cuda_memcpy_h2d b failed');

  Writeln('Launching vector add kernel...');
  res := cuda_launch_vector_add(a_dev, b_dev, c_dev, n);
  if res <> 0 then raise Exception.Create('cuda_launch_vector_add failed');

  Writeln('Copying device->host...');
  res := cuda_memcpy_d2h(hostC, c_dev, bytes);
  if res <> 0 then raise Exception.Create('cuda_memcpy_d2h c failed');

  Writeln('Verifying results (first 8 elements):');
  for i := 0 to Min(7, n-1) do
    Writeln(i, ': ', hostA[i]:0:6, ' + ', hostB[i]:0:6, ' = ', hostC[i]:0:6);

  { cleanup }
  HostFreeMem(hostA);
  HostFreeMem(hostB);
  HostFreeMem(hostC);

  HostFree(a_dev);
  HostFree(b_dev);
  HostFree(c_dev);
end;

{ -------------------------
  Test: micro op (PTX) launch
  ------------------------- }

procedure TestMicroOp(n: Integer);
var
  bytes: NativeUInt;
  a_dev, b_dev, c_dev: Pointer;
  hostA, hostB, hostC: PCardinal;
  i: Integer;
  res: TCUResult;
begin
  bytes := NativeUInt(n) * SizeOf(Cardinal);

  Writeln('Allocating device buffers for micro op...');
  a_dev := HostAlloc(bytes);
  b_dev := HostAlloc(bytes);
  c_dev := HostAlloc(bytes);

  hostA := HostMalloc(bytes);
  hostB := HostMalloc(bytes);
  hostC := HostMalloc(bytes);

  for i := 0 to n-1 do
  begin
    hostA[i] := Cardinal(i);
    hostB[i] := Cardinal(n - i);
  end;

  res := cuda_memcpy_h2d(a_dev, hostA, bytes);
  if res <> 0 then raise Exception.Create('cuda_memcpy_h2d a failed');
  res := cuda_memcpy_h2d(b_dev, hostB, bytes);
  if res <> 0 then raise Exception.Create('cuda_memcpy_h2d b failed');

  Writeln('Launching micro op kernel (PTX) ...');
  res := cuda_launch_micro_op(a_dev, b_dev, c_dev, n);
  if res <> 0 then raise Exception.Create('cuda_launch_micro_op failed');

  res := cuda_memcpy_d2h(hostC, c_dev, bytes);
  if res <> 0 then raise Exception.Create('cuda_memcpy_d2h c failed');

  Writeln('Micro op results (first 8):');
  for i := 0 to Min(7, n-1) do
    Writeln(i, ': ', hostA[i], ' ^ ', hostB[i], ' -> ', hostC[i]);

  HostFreeMem(hostA);
  HostFreeMem(hostB);
  HostFreeMem(hostC);

  HostFree(a_dev);
  HostFree(b_dev);
  HostFree(c_dev);
end;

{ -------------------------
  Main
  ------------------------- }

begin
  try
    Writeln('Initializing CUDA shim...');
    cuda_init();

    Writeln('Running vector add test...');
    TestVectorAdd(1024);

    Writeln('Running micro op test...');
    TestMicroOp(1024);

    Writeln('Finalizing...');
    cuda_finalize();

    CheckLeaks();
    Writeln('All done.');
  except
    on E: Exception do
      Writeln('Error: ', E.ClassName, ': ', E.Message);
  end;
end.
