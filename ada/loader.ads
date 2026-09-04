-- Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
-- SPDX-License-Identifier: FSL-1.1
-- DEED-088: Native WASM Loader — Ada Control Layer
-- Loader state machine, validation, safety invariants, contracts.

package Loader is

   Max_Modules : constant := 16;

   Module_Index_Error : exception;
   Load_Error        : exception;
   ValidationError   : exception;

   type Module_State is (
      Unloaded,
      Loaded,
      Initialized,
      Failed
   );

   type Module_Descriptor is record
      Index       : Integer := -1;
      State       : Module_State := Unloaded;
      Memory_Size : Natural := 0;
      Exports     : Natural := 0;
   end record;

   type Module_Array is array (1 .. Max_Modules) of Module_Descriptor;

   function Load (File_Path : String) return Integer
     with Pre => File_Path'Length > 0,
          Post => Load'Result >= -1;

   function Get_Memory (Module_Index : Integer) return System.Address
     with Pre => Module_Index >= 0 and Module_Index < Max_Modules;

   function Get_Memory_Size (Module_Index : Integer) return Natural
     with Pre => Module_Index >= 0 and Module_Index < Max_Modules;

   function Get_Export_Index
     (Module_Index : Integer;
      Name         : String;
      Kind         : Unsigned_8) return Integer
     with Pre => Module_Index >= 0 and Module_Index < Max_Modules;

   procedure Write_Memory_Byte
     (Module_Index : Integer;
      Offset       : Natural;
      Value        : Unsigned_8)
     with Pre => Module_Index >= 0 and Module_Index < Max_Modules;

   function Read_Memory_Byte
     (Module_Index : Integer;
      Offset       : Natural) return Unsigned_8
     with Pre => Module_Index >= 0 and Module_Index < Max_Modules;

   procedure Write_Memory_Block
     (Module_Index : Integer;
      Dest_Offset  : Natural;
      Source       : System.Address;
      Length       : Natural)
     with Pre => Module_Index >= 0 and Module_Index < Max_Modules;

   procedure Read_Memory_Block
     (Module_Index : Integer;
      Src_Offset   : Natural;
      Dest         : System.Address;
      Length       : Natural)
     with Pre => Module_Index >= 0 and Module_Index < Max_Modules;

   function Get_Global_Value
     (Module_Index : Integer;
      Global_Index : Natural) return Interfaces.Integer_64
     with Pre => Module_Index >= 0 and Module_Index < Max_Modules;

   procedure Set_Global_Value
     (Module_Index : Integer;
      Global_Index : Natural;
      Value        : Interfaces.Integer_64)
     with Pre => Module_Index >= 0 and Module_Index < Max_Modules;

   procedure Free_Module (Module_Index : Integer)
     with Pre => Module_Index >= 0 and Module_Index < Max_Modules;

   procedure Reset;

   function Active_Module_Count return Natural;

   function Execute_Instruction
     (Module_Index : Integer;
      Opcode       : Unsigned_8;
      Payload      : System.Address;
      Payload_Len  : Natural) return Boolean
     with Pre => Module_Index >= 0 and Module_Index < Max_Modules;

   function Run_Engine_Tick (Module_Index : Integer) return Interfaces.Integer_64
     with Pre => Module_Index >= 0 and Module_Index < Max_Modules;

private

   Active_Count : Natural := 0;

   function Is_Valid_Module (Module_Index : Integer) return Boolean;

end Loader;
