-- Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
-- SPDX-License-Identifier: FSL-1.1
-- DEED-088: Native WASM Loader — Ada Control Layer Implementation
-- State machine, validation, safety invariants, error handling.

with System;
with Interfaces;
with Interfaces.C;
with Unsigned_Types; use Unsigned_Types;

package body Loader is

   -- ── C Bindings to Zig Runtime Layer ───────────────────────────────────────

   function C_Load_Wasm (Path : Interfaces.C.char_array) return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "loader_load_wasm";

   function C_Get_Memory (Idx : Interfaces.C.int) return System.Address
     with Import => True, Convention => C, External_Name => "loader_get_memory";

   function C_Get_Memory_Size (Idx : Interfaces.C.int) return Interfaces.C.unsigned
     with Import => True, Convention => C, External_Name => "loader_get_memory_size";

   function C_Get_Export_Index
     (Idx  : Interfaces.C.int;
      Name : Interfaces.C.char_array;
      Kind : Unsigned_8) return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "loader_get_export_index";

   procedure C_Write_Memory_Byte
     (Idx    : Interfaces.C.int;
      Offset : Interfaces.C.unsigned;
      Value  : Unsigned_8)
     with Import => True, Convention => C, External_Name => "loader_write_memory_byte";

   function C_Read_Memory_Byte
     (Idx    : Interfaces.C.int;
      Offset : Interfaces.C.unsigned) return Unsigned_8
     with Import => True, Convention => C, External_Name => "loader_read_memory_byte";

   procedure C_Write_Memory_Block
     (Idx      : Interfaces.C.int;
      Dest     : Interfaces.C.unsigned;
      Src      : System.Address;
      Len      : Interfaces.C.unsigned)
     with Import => True, Convention => C, External_Name => "loader_write_memory_block";

   procedure C_Read_Memory_Block
     (Idx      : Interfaces.C.int;
      Src      : Interfaces.C.unsigned;
      Dest     : System.Address;
      Len      : Interfaces.C.unsigned)
     with Import => True, Convention => C, External_Name => "loader_read_memory_block";

   function C_Get_Global_Value
     (Idx        : Interfaces.C.int;
      Global_Idx : Interfaces.C.unsigned) return Interfaces.Integer_64
     with Import => True, Convention => C, External_Name => "loader_get_global_value";

   procedure C_Set_Global_Value
     (Idx        : Interfaces.C.int;
      Global_Idx : Interfaces.C.unsigned;
      Value      : Interfaces.Integer_64)
     with Import => True, Convention => C, External_Name => "loader_set_global_value";

   procedure C_Free_Module (Idx : Interfaces.C.int)
     with Import => True, Convention => C, External_Name => "loader_free_module";

   procedure C_Reset
     with Import => True, Convention => C, External_Name => "loader_reset";

   function C_Call_Func
     (Idx       : Interfaces.C.int;
      Func_Idx  : Interfaces.C.unsigned;
      Args_Ptr  : System.Address;
      Args_Len  : Interfaces.C.unsigned) return Interfaces.Integer_64
     with Import => True, Convention => C, External_Name => "loader_call_func";

   -- ── Internal State ───────────────────────────────────────────────────────

   Modules : Module_Array;

   function Is_Valid_Module (Module_Index : Integer) return Boolean is
   begin
      return Module_Index >= 0
        and then Module_Index < Max_Modules
        and then Modules (Module_Index + 1).State /= Unloaded;
   end Is_Valid_Module;

   function Active_Module_Count return Natural is
   begin
      return Active_Count;
   end Active_Module_Count;

   -- ── Public Interface ─────────────────────────────────────────────────────

   function Load (File_Path : String) return Integer is
      C_Path  : Interfaces.C.char_array (1 .. Interfaces.C.size_t (File_Path'Length + 1));
      Result  : Interfaces.C.int;
   begin
      if File_Path'Length = 0 then
         raise ValidationError with "Empty file path";
      end if;

      if Active_Count >= Max_Modules then
         raise Load_Error with "Maximum module count reached";
      end if;

      -- Convert Ada String to C string
      for I in File_Path'Range loop
         C_Path (Interfaces.C.size_t (I - File_Path'First + 1)) :=
            Interfaces.C.char (Character'Pos (File_Path (I)));
      end loop;
      C_Path (C_Path'Last) := Interfaces.C.nul;

      Result := C_Load_Wasm (C_Path);

      if Result < 0 then
         raise Load_Error with "Failed to load WASM: " & File_Path;
      end if;

      -- Update Ada-side descriptor
      Modules (Result + 1).Index := Result;
      Modules (Result + 1).State := Loaded;
      Modules (Result + 1).Memory_Size := Natural (C_Get_Memory_Size (Result));
      Active_Count := Active_Count + 1;

      return Integer (Result);
   end Load;

   function Get_Memory (Module_Index : Integer) return System.Address is
   begin
      if not Is_Valid_Module (Module_Index) then
         raise Module_Index_Error with "Invalid module index";
      end if;
      return C_Get_Memory (Interfaces.C.int (Module_Index));
   end Get_Memory;

   function Get_Memory_Size (Module_Index : Integer) return Natural is
   begin
      if not Is_Valid_Module (Module_Index) then
         raise Module_Index_Error with "Invalid module index";
      end if;
      return Natural (C_Get_Memory_Size (Interfaces.C.int (Module_Index)));
   end Get_Memory_Size;

   function Get_Export_Index
     (Module_Index : Integer;
      Name         : String;
      Kind         : Unsigned_8) return Integer
   is
      C_Name : Interfaces.C.char_array (1 .. Interfaces.C.size_t (Name'Length + 1));
   begin
      if not Is_Valid_Module (Module_Index) then
         raise Module_Index_Error with "Invalid module index";
      end if;

      for I in Name'Range loop
         C_Name (Interfaces.C.size_t (I - Name'First + 1)) :=
            Interfaces.C.char (Character'Pos (Name (I)));
      end loop;
         C_Name (C_Name'Last) := Interfaces.C.nul;

      return Integer (C_Get_Export_Index
         (Interfaces.C.int (Module_Index),
          C_Name,
          Kind));
   end Get_Export_Index;

   procedure Write_Memory_Byte
     (Module_Index : Integer;
      Offset       : Natural;
      Value        : Unsigned_8)
   is
   begin
      if not Is_Valid_Module (Module_Index) then
         raise Module_Index_Error with "Invalid module index";
      end if;

      if Offset >= Modules (Module_Index + 1).Memory_Size then
         raise ValidationError with "Memory offset out of bounds";
      end if;

      C_Write_Memory_Byte
         (Interfaces.C.int (Module_Index),
          Interfaces.C.unsigned (Offset),
          Value);
   end Write_Memory_Byte;

   function Read_Memory_Byte
     (Module_Index : Integer;
      Offset       : Natural) return Unsigned_8
   is
   begin
      if not Is_Valid_Module (Module_Index) then
         raise Module_Index_Error with "Invalid module index";
      end if;

      if Offset >= Modules (Module_Index + 1).Memory_Size then
         raise ValidationError with "Memory offset out of bounds";
      end if;

      return C_Read_Memory_Byte
         (Interfaces.C.int (Module_Index),
          Interfaces.C.unsigned (Offset));
   end Read_Memory_Byte;

   procedure Write_Memory_Block
     (Module_Index : Integer;
      Dest_Offset  : Natural;
      Source       : System.Address;
      Length       : Natural)
   is
   begin
      if not Is_Valid_Module (Module_Index) then
         raise Module_Index_Error with "Invalid module index";
      end if;

      if Dest_Offset + Length > Modules (Module_Index + 1).Memory_Size then
         raise ValidationError with "Memory block exceeds bounds";
      end if;

      C_Write_Memory_Block
         (Interfaces.C.int (Module_Index),
          Interfaces.C.unsigned (Dest_Offset),
          Source,
          Interfaces.C.unsigned (Length));
   end Write_Memory_Block;

   procedure Read_Memory_Block
     (Module_Index : Integer;
      Src_Offset   : Natural;
      Dest         : System.Address;
      Length       : Natural)
   is
   begin
      if not Is_Valid_Module (Module_Index) then
         raise Module_Index_Error with "Invalid module index";
      end if;

      if Src_Offset + Length > Modules (Module_Index + 1).Memory_Size then
         raise ValidationError with "Memory block exceeds bounds";
      end if;

      C_Read_Memory_Block
         (Interfaces.C.int (Module_Index),
          Interfaces.C.unsigned (Src_Offset),
          Dest,
          Interfaces.C.unsigned (Length));
   end Read_Memory_Block;

   function Get_Global_Value
     (Module_Index : Integer;
      Global_Index : Natural) return Interfaces.Integer_64
   is
   begin
      if not Is_Valid_Module (Module_Index) then
         raise Module_Index_Error with "Invalid module index";
      end if;
      return C_Get_Global_Value
         (Interfaces.C.int (Module_Index),
          Interfaces.C.unsigned (Global_Index));
   end Get_Global_Value;

   procedure Set_Global_Value
     (Module_Index : Integer;
      Global_Index : Natural;
      Value        : Interfaces.Integer_64)
   is
   begin
      if not Is_Valid_Module (Module_Index) then
         raise Module_Index_Error with "Invalid module index";
      end if;
      C_Set_Global_Value
         (Interfaces.C.int (Module_Index),
          Interfaces.C.unsigned (Global_Index),
          Value);
   end Set_Global_Value;

   procedure Free_Module (Module_Index : Integer) is
   begin
      if not Is_Valid_Module (Module_Index) then
         raise Module_Index_Error with "Invalid module index";
      end if;

      C_Free_Module (Interfaces.C.int (Module_Index));
      Modules (Module_Index + 1).State := Unloaded;
      Modules (Module_Index + 1).Index := -1;
      Modules (Module_Index + 1).Memory_Size := 0;
      Active_Count := Active_Count - 1;
   end Free_Module;

   procedure Reset is
   begin
      C_Reset;
      for I in Modules'Range loop
         Modules (I) := (Index => -1, State => Unloaded, Memory_Size => 0, Exports => 0);
      end loop;
      Active_Count := 0;
   end Reset;

   function Execute_Instruction
     (Module_Index : Integer;
      Opcode       : Unsigned_8;
      Payload      : System.Address;
      Payload_Len  : Natural) return Boolean
   is
      Mem_Addr : System.Address;
      Base     : constant := 2048;
   begin
      if not Is_Valid_Module (Module_Index) then
         raise Module_Index_Error with "Invalid module index";
      end if;

      -- Write opcode + payload to WASM memory at fixed offset
      Write_Memory_Byte (Module_Index, Base, Opcode);
      if Payload_Len > 0 then
         Write_Memory_Block (Module_Index, Base + 1, Payload, Payload_Len);
      end if;

      -- Mark as initialized on first instruction
      if Modules (Module_Index + 1).State = Loaded then
         Modules (Module_Index + 1).State := Initialized;
      end if;

      -- Call execute_binary_isa function (export index 0, kind=0)
      return C_Call_Func
         (Interfaces.C.int (Module_Index),
          0, -- func index
          System.Null_Address,
          0) = 1;
   end Execute_Instruction;

   function Run_Engine_Tick (Module_Index : Integer) return Interfaces.Integer_64 is
   begin
      if not Is_Valid_Module (Module_Index) then
         raise Module_Index_Error with "Invalid module index";
      end if;

      -- Mark as initialized on first tick
      if Modules (Module_Index + 1).State = Loaded then
         Modules (Module_Index + 1).State := Initialized;
      end if;

      -- Call engine_tick function (export index 1, kind=0)
      return C_Call_Func
         (Interfaces.C.int (Module_Index),
          1, -- func index
          System.Null_Address,
          0);
   end Run_Engine_Tick;

end Loader;
