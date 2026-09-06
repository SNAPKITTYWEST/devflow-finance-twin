-- format.adb — LE decoders, element sizes, CRC32, power-of-two
with Interfaces; use Interfaces;

package body Format with SPARK_Mode is

   function Element_Size(D : Valid_DType) return Positive is
   begin
      case D is
         when DType_F32 => return 4;
         when DType_I32 => return 4;
         when DType_F16 | DType_BF16 | DType_I16 => return 2;
         when DType_I8 | DType_U8 => return 1;
      end case;
   end Element_Size;

   function LE_U16(B0,B1 : Unsigned_8) return Unsigned_16 is
   begin
      return Unsigned_16(B0) or Shift_Left(Unsigned_16(B1),8);
   end LE_U16;

   function LE_U32(B0,B1,B2,B3 : Unsigned_8) return Unsigned_32 is
   begin
      return Unsigned_32(B0) or Shift_Left(Unsigned_32(B1),8)
           or Shift_Left(Unsigned_32(B2),16) or Shift_Left(Unsigned_32(B3),24);
   end LE_U32;

   function LE_U64(B0,B1,B2,B3,B4,B5,B6,B7 : Unsigned_8) return Unsigned_64 is
   begin
      return Unsigned_64(B0) or Shift_Left(Unsigned_64(B1),8)
           or Shift_Left(Unsigned_64(B2),16) or Shift_Left(Unsigned_64(B3),24)
           or Shift_Left(Unsigned_64(B4),32) or Shift_Left(Unsigned_64(B5),40)
           or Shift_Left(Unsigned_64(B6),48) or Shift_Left(Unsigned_64(B7),56);
   end LE_U64;

   function Is_Power_Of_Two(A : Alignment) return Boolean is
      U : Unsigned_32 := Unsigned_32(A);
   begin
      return U/=0 and (U and (U-1))=0;
   end Is_Power_Of_Two;

   function CRC32(Data : access constant Unsigned_8; Len : Natural) return Unsigned_32 is
      Crc : Unsigned_32 := 16#FFFF_FFFF#;
   begin
      for I in 0..Len-1 loop
         Crc := Crc xor Unsigned_32(Data(I));
         for _ in 1..8 loop
            if (Crc and 1)=1 then
               Crc := Shift_Right(Crc,1) xor 16#EDB8_8320#;
            else
               Crc := Shift_Right(Crc,1);
            end if;
         end loop;
      end loop;
      return not Crc;
   end CRC32;

end Format;
