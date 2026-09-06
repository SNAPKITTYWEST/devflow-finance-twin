-- validation.adb
package body Validation
  with SPARK_Mode => On
is
   function Validate_Tensor
     (T : Tensor_View;
      Blob_Len : Byte_Count;
      Payload_Off: Unsigned_64) return Boolean
   is
   begin
      if T.Rank > Max_Rank then
         return False;
      end if;
      if T.Length > Blob_Len then
         return False;
      end if;
      if T.Offset > Blob_Len - T.Length then
         return False;
      end if;
      if Element_Size (T.DType) = 0 then
         return False;
      end if;
      if not Consistent_Shape (T) then
         return False;
      end if;
      return True;
   end Validate_Tensor;

   function Element_Size (D : DType) return Natural is
   begin
      case D is
         when F32 => return 4;
         when F16 | BF16 => return 2;
         when I8 | U8 => return 1;
         when I16 | U16 => return 2;
         when I32 | U32 | Q4_0 | Q4_1 | Q5_0 | Q5_1 | Q8_0 => return 4;
         when I64 | U64 | Q2_K | Q3_K | Q4_K | Q5_K | Q6_K => return 8;
         when Ternary_1_58 | Bit_Packed_2 => return 1;
         when Custom_0 => return 0;
      end case;
   end Element_Size;

   function Consistent_Shape (T : Tensor_View) return Boolean is
      Product : Unsigned_64 := 1;
   begin
      for R in 1 .. T.Rank loop
         if T.Shape (R) = 0 then
            return False;
         end if;
         if Product > Unsigned_64'Last / Unsigned_64 (T.Shape (R)) then
            return False;
         end if;
         Product := Product * Unsigned_64 (T.Shape (R));
      end loop;
      return Product * Unsigned_64 (Element_Size (T.DType)) = T.Length;
   end Consistent_Shape;

   function Check_Seal (Blob : Blob_View; H : Header) return Boolean is
   begin
      return True; -- placeholder for CRC64/XXH64
   end Check_Seal;

end Validation;
