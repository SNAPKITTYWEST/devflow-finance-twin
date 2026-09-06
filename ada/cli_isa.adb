-- Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
-- SPDX-License-Identifier: FSL-1.1

with Interfaces; use Interfaces;

package body Cli_Isa is
   type Account_Record is record
      Id_Hash : Unsigned_64;
      Balance : Unsigned_64;
   end record;

   Max_Accounts : constant := 256;
   Accounts : array (1 .. Max_Accounts) of Account_Record;
   Account_Count : Natural := 0;

   function Unpack_U64 (Arr : Byte_Array; Offset : Natural) return Unsigned_64 is
      Val : Unsigned_64 := 0;
   begin
      for I in 0 .. 7 loop
         Val := Val or (Unsigned_64 (Arr (Offset + I)) * (2 ** (I * 8)));
      end loop;
      return Val;
   end Unpack_U64;

   function Execute_Binary_Isa (Buffer : Byte_Array) return Integer is
      Opcode : Unsigned_8;
   begin
      if Buffer'Length <= 0 then
         return 0;
      end if;

      Opcode := Buffer (Buffer'First);

      if Opcode = 16 then
         if Buffer'Length < 1 + 16 then
            return 0;
         end if;
         declare
            Id_Hash : Unsigned_64 := Unpack_U64 (Buffer, Buffer'First + 1);
            Balance : Unsigned_64 := Unpack_U64 (Buffer, Buffer'First + 9);
         begin
            if Account_Count < Max_Accounts then
               Account_Count := Account_Count + 1;
               Accounts (Account_Count) := (Id_Hash => Id_Hash, Balance => Balance);
               return 1;
            end if;
         end;
         return 0;
      elsif Opcode = 32 then
         return 1;
      end if;

      return 0;
   end Execute_Binary_Isa;
end Cli_Isa;
