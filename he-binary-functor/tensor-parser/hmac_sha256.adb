with System.Storage_Elements; use System.Storage_Elements;
with SHA256;

package body HMAC_SHA256
  with SPARK_Mode => On
is

   procedure Compute
     (Key : Key_View;
      Data : System.Address;
      Data_Len: Byte_Count;
      Result : out Digest)
   is
      K : Block := (others => 0);
      IPad, OPad : Block;
      Inner_Hash : Digest;
      Outer_Hash : Digest;
      Key_Len : constant Natural := Key.Len;
   begin
      if Key_Len > 64 then
         SHA256.Hash (Key.Addr, Byte_Count (Key_Len), K (1 .. 32));
      else
         for I in 1 .. Key_Len loop
            K (I) := Byte'(Read_Byte (Key.Addr + Storage_Offset (I - 1)));
         end loop;
      end if;

      for I in Block'Range loop
         IPad (I) := K (I) xor 16#36#;
         OPad (I) := K (I) xor 16#5C#;
      end loop;

      declare
         Inner_State : SHA256.Context;
      begin
         SHA256.Init (Inner_State);
         SHA256.Update (Inner_State, IPad'Address, 64);
         SHA256.Update (Inner_State, Data, Data_Len);
         SHA256.Final (Inner_State, Inner_Hash);
      end;

      declare
         Outer_State : SHA256.Context;
      begin
         SHA256.Init (Outer_State);
         SHA256.Update (Outer_State, OPad'Address, 64);
         SHA256.Update (Outer_State, Inner_Hash'Address, 32);
         SHA256.Final (Outer_State, Outer_Hash);
      end;

      Result := Outer_Hash;
   end Compute;

   function Equal (A, B : Digest) return Boolean is
      Diff : Byte := 0;
   begin
      for I in Digest'Range loop
         Diff := Diff or (A (I) xor B (I));
      end loop;
      return Diff = 0;
   end Equal;

   function Read_Byte (A : System.Address) return Byte
     with Inline, Global => null
   is
      B : Byte with Address => A, Import;
   begin
      return B;
   end Read_Byte;

end HMAC_SHA256;
