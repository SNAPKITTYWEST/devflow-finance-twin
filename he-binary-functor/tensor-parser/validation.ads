-- validation.ads
package Validation
  with SPARK_Mode => On
is
   function Validate_Tensor
     (T : Tensor_View;
      Blob_Len : Byte_Count;
      Payload_Off: Unsigned_64) return Boolean
     with
       Post => (if Validate_Tensor'Result then
                  T.Offset <= Blob_Len
                  and then T.Length <= Blob_Len - T.Offset
                  and then T.Rank <= Max_Rank
                  and then Element_Size (T.DType) > 0
                  and then Consistent_Shape (T));

   function Element_Size (D : DType) return Natural
     with Post => Element_Size'Result in 0 | 1 | 2 | 4 | 8;

   function Consistent_Shape (T : Tensor_View) return Boolean;

   function Check_Seal (Blob : Blob_View; H : Header) return Boolean;

end Validation;
