-- format.ads — Exact binary format, explicit endianness, bounded types
-- Engineering: aerospace embedded discipline, no host-endian dependence

with Interfaces; use Interfaces;

package Format with SPARK_Mode is

   -- ── Constants ──
   Magic_Value      : constant := 16#4E455442#; -- "BTEN" little-endian
   Version_Current  : constant := 1;

   Header_Size_Bytes       : constant := 64;
   Descriptor_Size_Bytes   : constant := 64;
   Seal_Size_Bytes         : constant := 32; -- SHA-256
   Max_Tensors             : constant := 1024;
   Max_Rank                : constant := 8;
   Max_Dimension           : constant := 16_777_216; -- 16M per axis
   Max_Blob_Bytes          : constant := 2_147_483_648; -- 2 GiB edge limit
   Max_Metadata_Bytes      : constant := 1_048_576; -- 1 MiB
   Max_Payload_Bytes       : constant := 2_147_483_647;

   -- ── Bounded subtypes (HARD ANNOTATIONS) ──
   subtype Blob_Offset is Unsigned_64 range 0 .. Max_Blob_Bytes;
   subtype Blob_Length is Unsigned_64 range 0 .. Max_Blob_Bytes;
   subtype Tensor_Count is Natural range 0 .. Max_Tensors;
   subtype Rank is Natural range 0 .. Max_Rank;
   subtype Dimension is Natural range 0 .. Max_Dimension;
   subtype Alignment is Natural range 1 .. 4096;
   subtype DType_Raw is Unsigned_8 range 0 .. 255;

   type DType_ID is (DType_Invalid, DType_F32, DType_F16, DType_BF16,
                     DType_I32, DType_I16, DType_I8, DType_U8)
     with Size => 8;
   for DType_ID use
     (DType_Invalid => 0, DType_F32 => 1, DType_F16 => 2, DType_BF16 => 3,
      DType_I32 => 4, DType_I16 => 5, DType_I8 => 6, DType_U8 => 7);

   subtype Valid_DType is DType_ID range DType_F32 .. DType_U8;

   function Element_Size( D : Valid_DType) return Positive with Inline;

   type Raw_Header is record
      Magic                 : Unsigned_32;
      Version               : Unsigned_16;
      Flags                 : Unsigned_16;
      Header_Size           : Unsigned_32;
      Tensor_Count          : Unsigned_32;
      Desc_Table_Offset     : Unsigned_64;
      Desc_Size             : Unsigned_32;
      Meta_Offset           : Unsigned_64;
      Meta_Length           : Unsigned_32;
      Payload_Offset        : Unsigned_64;
      Payload_Length        : Unsigned_64;
      Header_CRC32          : Unsigned_32;
      Reserved              : Unsigned_32;
   end record with Size => 64*8, Bit_Order => Low_Order_First;

   for Raw_Header use record
      Magic              at 0  range 0..31;
      Version            at 4  range 0..15;
      Flags              at 6  range 0..15;
      Header_Size        at 8  range 0..31;
      Tensor_Count       at 12 range 0..31;
      Desc_Table_Offset  at 16 range 0..63;
      Desc_Size          at 24 range 0..31;
      Meta_Offset        at 28 range 0..63;
      Meta_Length        at 36 range 0..31;
      Payload_Offset     at 40 range 0..63;
      Payload_Length     at 48 range 0..63;
      Header_CRC32       at 56 range 0..31;
      Reserved           at 60 range 0..31;
   end record;

   type Dim_Array is array (0..Max_Rank-1) of Unsigned_32;

   type Raw_Descriptor is record
      Tensor_ID   : Unsigned_32;
      DType       : Unsigned_8;
      Rank        : Unsigned_8;
      Reserved0   : Unsigned_16;
      Offset      : Unsigned_64;
      Length      : Unsigned_64;
      Dims        : Dim_Array;
      Alignment   : Unsigned_32;
      Desc_CRC32  : Unsigned_32;
   end record with Size => 64*8;

   for Raw_Descriptor use record
      Tensor_ID  at 0  range 0..31;
      DType      at 4  range 0..7;
      Rank       at 5  range 0..7;
      Reserved0  at 6  range 0..15;
      Offset     at 8  range 0..63;
      Length     at 16 range 0..63;
      Dims       at 24 range 0..255;
      Alignment  at 56 range 0..31;
      Desc_CRC32 at 60 range 0..31;
   end record;

   function LE_U16(B0,B1 : Unsigned_8) return Unsigned_16 with Inline;
   function LE_U32(B0,B1,B2,B3 : Unsigned_8) return Unsigned_32 with Inline;
   function LE_U64(B0,B1,B2,B3,B4,B5,B6,B7 : Unsigned_8) return Unsigned_64 with Inline;

   function Is_Power_Of_Two(A : Alignment) return Boolean with Inline;

   function CRC32( Data : access constant Unsigned_8; Len : Natural) return Unsigned_32;

end Format;
