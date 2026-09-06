with System.Storage_Elements; use System.Storage_Elements;

package body CRC64
  with SPARK_Mode => On
is
   type Table_Type is array (Unsigned_8) of CRC_Value;
   Table : constant Table_Type := Generate_Table;

   function Generate_Table return Table_Type
     with Global => null
   is
      T : Table_Type;
      C : CRC_Value;
   begin
      for I in Unsigned_8 loop
         C := Shift_Left (CRC_Value (I), 56);
         for J in 1 .. 8 loop
            if (C and 16#8000_0000_0000_0000#) /= 0 then
               C := Shift_Left (C, 1) xor Polynomial;
            else
               C := Shift_Left (C, 1);
            end if;
         end loop;
         T (I) := C;
      end loop;
      return T;
   end Generate_Table;

   function Init return CRC_Value is
   begin
      return 16#FFFF_FFFF_FFFF_FFFF#;
   end Init;

   procedure Update
     (CRC : in out CRC_Value;
      Addr : System.Address;
      Len : Byte_Count)
   is
      P : System.Address := Addr;
      B : Unsigned_8;
   begin
      for I in 1 .. Len loop
         pragma Loop_Invariant (I <= Len + 1);
         B := Unsigned_8'(Read_Byte (P));
         CRC := Shift_Left (CRC, 8) xor
                Table (Unsigned_8 (Shift_Right (CRC, 56)) xor B);
         P := P + 1;
      end loop;
   end Update;

   function Final (CRC : CRC_Value) return CRC_Value is
   begin
      return CRC xor 16#FFFF_FFFF_FFFF_FFFF#;
   end Final;

   function Compute (Addr : System.Address; Len : Byte_Count) return CRC_Value is
      C : CRC_Value := Init;
   begin
      Update (C, Addr, Len);
      return Final (C);
   end Compute;

   function Read_Byte (A : System.Address) return Unsigned_8
     with Inline, Global => null
   is
      B : Unsigned_8 with Address => A, Import;
   begin
      return B;
   end Read_Byte;

end CRC64;
