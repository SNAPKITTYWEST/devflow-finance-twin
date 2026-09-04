-- Malbolge Co-Processor Firmware (Ring -3)
-- Runs on dedicated security core, isolated from main CPU
-- Provides hardware entropy source via chaotic ternary computation

-- Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
-- SPDX-License-Identifier: FSL-1.1

with Interfaces; use Interfaces;
with System; use System;

package body Malbolge_Firmware is

   MEMORY_SIZE : constant := 59049; -- 3^10
   TRYTE_SIZE  : constant := 10;

   type Trit is mod 3;

   type Tryte is array (1 .. TRYTE_SIZE) of Trit;

   type Memory_Array is array (0 .. MEMORY_SIZE - 1) of Tryte;

   type Registers is record
      A : Tryte;
      C : Tryte;
      D : Tryte;
   end record;

   Proc_Regs : Registers;
   Proc_Mem  : Memory_Array;
   Entropy_Buffer : array (0 .. 8191) of Unsigned_32;
   Entropy_Count  : Natural := 0;

   function Tryte_To_Nat (T : Tryte) return Natural is
      Result : Natural := 0;
   begin
      for I in T'Range loop
         Result := Result * 3 + Natural(T(I));
      end loop;
      return Result mod MEMORY_SIZE;
   end Tryte_To_Nat;

   function Nat_To_Tryte (N : Natural) return Tryte is
      Val : Natural := N mod MEMORY_SIZE;
      Result : Tryte;
   begin
      for I in reverse TRYTE_SIZE loop
         Result(I) := Trit(Val mod 3);
         Val := Val / 3;
      end loop;
      return Result;
   end Nat_To_Tryte;

   function Crazy_Op (A, B : Trit) return Trit is
   begin
      case A is
         when 0 =>
            case B is
               when 0 => return 1;
               when 1 => return 0;
               when 2 => return 0;
            end case;
         when 1 =>
            case B is
               when 0 => return 2;
               when 1 => return 2;
               when 2 => return 1;
            end case;
         when 2 =>
            case B is
               when 0 => return 0;
               when 1 => return 2;
               when 2 => return 2;
            end case;
      end case;
   end Crazy_Op;

   procedure Execute_Step is
      Addr   : Natural;
      Encrypted : Tryte;
      Decrypted : Tryte;
      Opcode : Trit;
      Mem_Val : Tryte;
      New_A   : Tryte;
      New_Mem_Val : Tryte;
      Input_Val : Unsigned_32;
   begin
      Addr := Tryte_To_Nat(Proc_Regs.C);
      Encrypted := Proc_Mem(Addr);

      -- Decrypt: subtract address from each trit
      for I in TRYTE_SIZE loop
         Decrypted(I) := Trit((Integer(Encrypted(I)) - (Addr / (3 ** (I - 1))) mod 3 + 3) mod 3);
      end loop;

      Opcode := Decrypted(1);

      case Opcode is
         when 0 => -- Jmp: C <- [D]; D <- D + 1
            Proc_Regs.C := Proc_Mem(Tryte_To_Nat(Proc_Regs.D));
            Proc_Regs.D := Nat_To_Tryte((Tryte_To_Nat(Proc_Regs.D) + 1) mod MEMORY_SIZE);

         when 1 => -- Rot: A <- crazy(A, [D]); [D] <- permute([D]); D <- D + 1
            Mem_Val := Proc_Mem(Tryte_To_Nat(Proc_Regs.D));
            for I in TRYTE_SIZE loop
               New_A(I) := Crazy_Op(Proc_Regs.A(I), Mem_Val(I));
               New_Mem_Val(I) := Crazy_Op(Mem_Val(I), Mem_Val(I));
            end loop;
            Proc_Regs.A := New_A;
            Proc_Mem(Tryte_To_Nat(Proc_Regs.D)) := New_Mem_Val;
            Proc_Regs.D := Nat_To_Tryte((Tryte_To_Nat(Proc_Regs.D) + 1) mod MEMORY_SIZE);

         when 2 => -- Out: output A; D <- D + 1
            if Entropy_Count < 8192 then
               Entropy_Buffer(Entropy_Count) := Unsigned_32(Tryte_To_Nat(Proc_Regs.A));
               Entropy_Count := Entropy_Count + 1;
            end if;
            Proc_Regs.D := Nat_To_Tryte((Tryte_To_Nat(Proc_Regs.D) + 1) mod MEMORY_SIZE);

         when others => -- Nop/End: D <- D + 1 or halt
            Proc_Regs.D := Nat_To_Tryte((Tryte_To_Nat(Proc_Regs.D) + 1) mod MEMORY_SIZE);
      end case;
   end Execute_Step;

   procedure Initialize is
   begin
      Proc_Regs := (A => (others => 0), C => (others => 0), D => (others => 0));
      for I in 0 .. MEMORY_SIZE - 1 loop
         Proc_Mem(I) := Nat_To_Tryte(I);
      end loop;
      Entropy_Count := 0;
   end Initialize;

   function Get_Entropy return Unsigned_32 is
   begin
      if Entropy_Count > 0 then
         Entropy_Count := Entropy_Count - 1;
         return Entropy_Buffer(Entropy_Count);
      else
         return 0;
      end if;
   end Get_Entropy;

   procedure Run_Steps (Count : Natural) is
   begin
      for I in 1 .. Count loop
         Execute_Step;
      end loop;
   end Run_Steps;

end Malbolge_Firmware;
