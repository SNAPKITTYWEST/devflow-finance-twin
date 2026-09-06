-- validation.ads
-- Semantic validation of tensor descriptors.
-- Overflow-safe shape product, dtype size table, alignment checks.

with Format; use Format;
with Parser; use Parser;
with Interfaces; use Interfaces;

package Validation
  with SPARK_Mode => On
is

   function Element_Size (D : DType) return Natural
     with
       Post => Element_Size'Result in 0 | 1 | 2 | 4 | 8,
       Global => null;

   function Is_Power_Of_Two (A : Align_Type) return Boolean
     with
       Post => Is_Power_Of_Two'Result =
                 (A = 1 or A = 2 or A = 4 or A = 8 or
                  A = 16 or A = 32 or A = 64),
       Global => null;

   procedure Shape_Product
     (Shape : Shape_Array;
      Rank : Rank_Type;
      Product : out Unsigned_64;
      OK : out Boolean)
     with
       Pre => Rank <= Max_Rank,
       Post => (if OK then Product <= Unsigned_64'Last),
       Global => null;

   function Consistent_Shape (T : Tensor_View) return Boolean
     with
       Global => null;

   function Validate_Tensor
     (T : Tensor_View;
      Blob_Len : Byte_Count;
      Payload_Off : Unsigned_64) return Boolean
     with
       Pre => T.Rank <= Max_Rank,
       Post => (if Validate_Tensor'Result then
                  T.Offset <= Blob_Len
                  and then T.Length <= Blob_Len - T.Offset
                  and then Is_Power_Of_Two (T.Alignment)
                  and then Element_Size (T.DType) > 0
                  and then Consistent_Shape (T)),
       Global => null;

end Validation;
