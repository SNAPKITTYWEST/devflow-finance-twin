-- format_mltr.ads
-- MLTR Tensor Container Format (alternate specification from Ahmad)

with Interfaces;

package Format_MLTR is
   pragma SPARK_Mode (On);

   Magic_Constant : constant Interfaces.Unsigned_32 := 16#4D4C5452#; -- "MLTR"
   Current_Version : constant Interfaces.Unsigned_16 := 1;

   Max_Tensors : constant := 16_384;
   Max_Rank : constant := 8;
   Max_Dimension : constant := 1_073_741_830;
   Header_Size : constant := 64;

   type Endian_Kind is (Little_Endian, Big_Endian);
   for Endian_Kind use (Little_Endian => 16#01#, Big_Endian => 16#02#);

   type Dtype_Kind is (Float32, Float16, Int8, Uint8, Bfloat16);
   for Dtype_Kind use (
      Float32 => 16#01#,
      Float16 => 16#02#,
      Int8 => 16#03#,
      Uint8 => 16#04#,
      Bfloat16 => 16#05#
   );

   type Blob_Index is range 0 .. 2_147_483_647;
   type Tensor_Count_Type is range 0 .. Max_Tensors;
   type Rank_Type is range 0 .. Max_Rank;
   type Dimension_Type is range 1 .. Max_Dimension;

   type Shape_Array is array (Rank_Type range <>) of Dimension_Type;

   type Tensor_Descriptor is record
      Tensor_ID : Interfaces.Unsigned_32;
      Offset : Blob_Index;
      Length : Blob_Index;
      Dtype : Dtype_Kind;
      Rank : Rank_Type;
      Reserved : Interfaces.Unsigned_8;
      Shape : array (1 .. Max_Rank) of Dimension_Type;
      Alignment : Interfaces.Unsigned_32;
   end record
     with Size => 256;

   for Tensor_Descriptor use record
      Tensor_ID at 0 range 0 .. 31;
      Offset at 4 range 0 .. 31;
      Length at 8 range 0 .. 31;
      Dtype at 12 range 0 .. 7;
      Rank at 13 range 0 .. 7;
      Reserved at 14 range 0 .. 15;
      Shape at 16 range 0 .. 223;
      Alignment at 44 range 0 .. 31;
   end record;

   type Descriptor_Array is array (Tensor_Count_Type range <>) of Tensor_Descriptor;

   type Model_Header is record
      Magic : Interfaces.Unsigned_32;
      Version : Interfaces.Unsigned_16;
      Endianness : Endian_Kind;
      Flags : Interfaces.Unsigned_8;
      Tensor_Count : Tensor_Count_Type;
      Meta_Offset : Blob_Index;
      Meta_Length : Blob_Index;
      Payload_Base : Blob_Index;
      Checksum : Interfaces.Unsigned_32;
      Padding : array (1 .. 24) of Interfaces.Unsigned_8;
   end record
     with Size => Header_Size * 8;

   for Model_Header use record
      Magic at 0 range 0 .. 31;
      Version at 4 range 0 .. 15;
      Endianness at 6 range 0 .. 7;
      Flags at 7 range 0 .. 7;
      Tensor_Count at 8 range 0 .. 31;
      Meta_Offset at 12 range 0 .. 31;
      Meta_Length at 16 range 0 .. 31;
      Payload_Base at 20 range 0 .. 31;
      Checksum at 24 range 0 .. 31;
      Padding at 28 range 0 .. 191;
   end record;

end Format_MLTR;
