-- validation_mltr.ads
with Interfaces;
with Format_MLTR; use Format_MLTR;
with System;

package Validation_MLTR is
   pragma SPARK_Mode (On);

   procedure Verify_Structure (
      Addr : in System.Address;
      Len : in Blob_Index;
      Header : in Model_Header;
      Valid : out Boolean
   ) with
      Pre => Len >= Header_Size,
      Post => (if Valid then Header.Tensor_Count <= Max_Tensors);

end Validation_MLTR;
