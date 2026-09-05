-- format.ads
-- Dense Binary Tensor Container Format (DBTC) v1
-- Little-endian multi-byte fields. Explicit layout. No host dependence.

package Format
  with SPARK_Mode => On
is
   Magic_Value : constant := 16#44_42_54_43#; -- "DBTC"
   Current_Version : constant := 1;

   Max_Tensors : constant := 65_536;
   Max_Rank : constant := 8;
   Max_Dimension : constant := 2**30 - 1; -- practical edge limit
   Max_Blob_Size : constant := 2**40 - 1; -- 1 TiB theoretical

   subtype Byte_Index is Long_Long_Integer range 0 .. Max_Blob_Size;
   subtype Byte_Count is Long_Long_Integer range 0 .. Max_Blob_Size;
   subtype Tensor_Count is Natural range 0 .. Max_Tensors;
   subtype Rank_Type is Natural range 0 .. Max_Rank;
   subtype Dim_Type is Natural range 0 .. Max_Dimension;
   subtype Align_Type is Natural range 1 .. 64; -- power-of-two only validated later
   subtype DType_Id is Natural range 0 .. 31;

   type Endianness is (Little, Big);
   type DType is
     (F32, F16, BF16, I8, U8, I16, U16, I32, U32, I64, U64,
      Q4_0, Q4_1, Q5_0, Q5_1, Q8_0, Q2_K, Q3_K, Q4_K, Q5_K, Q6_K,
      Ternary_1_58, Bit_Packed_2, Custom_0);

   -- Fixed header (32 bytes)
   type Header is record
      Magic : Interfaces.Unsigned_32;
      Version : Interfaces.Unsigned_16;
      Endian : Interfaces.Unsigned_8; -- 0 = LE, 1 = BE
      Header_Size : Interfaces.Unsigned_8; -- must be 32
      Tensor_Count : Interfaces.Unsigned_32;
      Descriptor_Off : Interfaces.Unsigned_64; -- absolute offset
      Metadata_Off : Interfaces.Unsigned_64;
      Payload_Off : Interfaces.Unsigned_64;
      Seal : Interfaces.Unsigned_64; -- CRC64 or XXH64 of structural parts
   end record
     with Size => 32 * 8,
          Alignment => 8,
          Object_Size => 32 * 8;

   for Header use record
      Magic at 0 range 0 .. 31;
      Version at 4 range 0 .. 15;
      Endian at 6 range 0 .. 7;
      Header_Size at 7 range 0 .. 7;
      Tensor_Count at 8 range 0 .. 31;
      Descriptor_Off at 12 range 0 .. 63;
      Metadata_Off at 20 range 0 .. 63;
      Payload_Off at 28 range 0 .. 63;
      -- Seal is after Payload_Off in full layout; adjusted for density
   end record;

   -- Per-tensor descriptor (64 bytes, cache-line friendly)
   type Shape_Array is array (1 .. Max_Rank) of Dim_Type
     with Pack, Component_Size => 32;

   type Tensor_Descriptor is record
      Tensor_ID : Interfaces.Unsigned_32;
      Offset : Interfaces.Unsigned_64; -- relative to Payload_Off
      Length : Interfaces.Unsigned_64; -- byte length
      Rank : Interfaces.Unsigned_8;
      DType : Interfaces.Unsigned_8;
      Alignment : Interfaces.Unsigned_8;
      Reserved : Interfaces.Unsigned_8;
      Shape : Shape_Array;
      Element_Cnt : Interfaces.Unsigned_64; -- validated product
   end record
     with Size => 64 * 8,
          Alignment => 8;

end Format;
