-- validation.adb
-- Dense, overflow-safe validation.

with Interfaces; use Interfaces;

package body Validation
  with SPARK_Mode => On
is

   type Size_Table is array (DType) of Natural;

   Element_Sizes : constant Size_Table :=
     (F32 => 4,
      F16 => 2,
      BF16 => 2,
      I8 => 1,
      U8 => 1,
      I16 => 2,
      U16 => 2,
      I32 => 4,
      U32 => 4,
      I64 => 8,
      U64 => 8,
      Q4_0 => 0,
      Q4_1 => 0,
      Q5_0 => 0,
      Q5_1 => 0,
      Q8_0 => 1,
      Q2_K => 0,
      Q3_K => 0,
      Q4_K => 0,
      Q5_K => 0,
      Q6_K => 0,
      Ternary_1_58 => 0,
      Bit_Packed_2 => 0,
      Custom_0 => 0);

   function Element_Size (D : DType) return Natural is
   begin
      return Element_Sizes (D);
   end Element_Size;

   function Is_Power_Of_Two (A : Align_Type) return Boolean is
   begin
      case A is
         when 1 | 2 | 4 | 8 | 16 | 32 | 64 => return True;
         when others => return False;
      end case;
   end Is_Power_Of_Two;

   procedure Shape_Product
     (Shape : Shape_Array;
      Rank : Rank_Type;
      Product : out Unsigned_64;
      OK : out Boolean)
   is
      P : Unsigned_64 := 1;
      D : Unsigned_64;
   begin
      if Rank = 0 then
         Product := 1;
         OK := True;
         return;
      end if;

      for I in 1 .. Rank loop
         D := Unsigned_64 (Shape (I));

         if D = 0 then
            Product := 0;
            OK := True;
            return;
         end if;

         if P > Unsigned_64'Last / D then
            Product := 0;
            OK := False;
            return;
         end if;

         P := P * D;
      end loop;

      Product := P;
      OK := True;
   end Shape_Product;

   function Consistent_Shape (T : Tensor_View) return Boolean is
      Prod : Unsigned_64;
      Prod_OK : Boolean;
      Elem_Sz : constant Natural := Element_Size (T.DType);
      Expected : Unsigned_64;
   begin
      Shape_Product (T.Shape, T.Rank, Prod, Prod_OK);
      if not Prod_OK then
         return False;
      end if;

      if T.Element_Cnt /= Prod then
         return False;
      end if;

      if Elem_Sz > 0 then
         if Prod > Unsigned_64'Last / Unsigned_64 (Elem_Sz) then
            return False;
         end if;
         Expected := Prod * Unsigned_64 (Elem_Sz);
         return T.Length = Byte_Count (Expected);
      end if;

      if Prod = 0 then
         return T.Length = 0;
      else
         return T.Length > 0;
      end if;
   end Consistent_Shape;

   function Validate_Tensor
     (T : Tensor_View;
      Blob_Len : Byte_Count;
      Payload_Off : Unsigned_64) return Boolean
   is
      Abs_Off : Byte_Index;
   begin
      if T.Rank > Max_Rank then
         return False;
      end if;

      if not Is_Power_Of_Two (T.Alignment) then
         return False;
      end if;

      if Element_Size (T.DType) = 0
         and then T.DType not in Q4_0 | Q4_1 | Q5_0 | Q5_1 |
                                 Q2_K | Q3_K | Q4_K | Q5_K | Q6_K |
                                 Ternary_1_58 | Bit_Packed_2 | Custom_0
      then
         return False;
      end if;

      if Payload_Off > Unsigned_64 (Blob_Len) then
         return False;
      end if;

      Abs_Off := Byte_Index (Payload_Off) + T.Offset;

      if Abs_Off > Blob_Len
         or else T.Length > Blob_Len - Abs_Off
      then
         return False;
      end if;

      if Abs_Off mod Byte_Index (T.Alignment) /= 0 then
         return False;
      end if;

      if not Consistent_Shape (T) then
         return False;
      end if;

      for I in 1 .. T.Rank loop
         if T.Shape (I) > Max_Dimension then
            return False;
         end if;
      end loop;

      return True;
   end Validate_Tensor;

end Validation;
