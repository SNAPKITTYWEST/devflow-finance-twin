with SHA256; use SHA256;
with System.Storage_Elements; use System.Storage_Elements;

package body SHA256_Reverse
  with SPARK_Mode => On
is

   procedure Reverse_Hash_32bit (
      Target_Digest : in Digest;
      Base_Block : in Block;
      Payload_Index : in Positive;
      Found : out Boolean;
      Preimage : out Unsigned_32
   )
   is
      Current_Block : Block := Base_Block;
      Computed_Dig : Digest;
      Val : Unsigned_32 := 0;
   begin
      Found := False;
      Preimage := 0;

      for I in Unsigned_32'Range loop
         Current_Block (Payload_Index)     := Byte(Shift_Right(Val, 24) and 16#FF#);
         Current_Block (Payload_Index + 1) := Byte(Shift_Right(Val, 16) and 16#FF#);
         Current_Block (Payload_Index + 2) := Byte(Shift_Right(Val, 8) and 16#FF#);
         Current_Block (Payload_Index + 3) := Byte(Val and 16#FF#);

         Hash (
            Data => Current_Block(1)'Address,
            Data_Len => 64,
            Result => Computed_Dig
         );

         declare
            Match : Boolean := True;
         begin
            for J in Digest'Range loop
               if Computed_Dig (J) /= Target_Digest (J) then
                  Match := False;
                  exit;
               end if;
            end loop;

            if Match then
               Found := True;
               Preimage := Val;
               return;
            end if;
         end;

         exit when Val = Unsigned_32'Last;
         Val := Val + 1;
      end loop;
   end Reverse_Hash_32bit;

end SHA256_Reverse;
