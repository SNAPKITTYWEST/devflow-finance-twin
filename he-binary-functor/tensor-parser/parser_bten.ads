-- parser.ads — Zero-copy deterministic parser, explicit state machine
with Format; use Format;
with Validation; use Validation;
with Interfaces; use Interfaces;
with System;

package Parser with SPARK_Mode is

   type Parser_State is (S_Start, S_Header, S_Descriptors, S_Metadata, S_Validate, S_Ready, S_Reject);

   subtype Blob_Index is Natural range 0 .. Format.Max_Blob_Bytes;

   type Byte is mod 2**8;
   type Byte_Array is array (Blob_Index range <>) of Byte with Pack;

   type Tensor_View is record
      Tensor_ID : Unsigned_32;
      DType     : Valid_DType;
      Rank      : Rank;
      Dims      : Dim_Array;
      Offset    : Blob_Offset;
      Length    : Blob_Length;
      Alignment : Alignment;
   end record;

   type Tensor_Table is array (Tensor_Count range <>) of Tensor_View;

   type Model_Header_View is record
      Version        : Unsigned_16;
      Tensor_Count   : Tensor_Count;
      Desc_Off       : Blob_Offset;
      Meta_Off       : Blob_Offset;
      Meta_Len       : Blob_Length;
      Payload_Off    : Blob_Offset;
      Payload_Len    : Blob_Length;
   end record;

   type Parser_Context is record
      State        : Parser_State := S_Start;
      Blob_Len     : Blob_Length := 0;
      Header       : Raw_Header;
      Header_View  : Model_Header_View;
      Tensor_Count : Tensor_Count := 0;
      Tensors      : Tensor_Table(0..Max_Tensors-1);
      Error        : Validation_Error := OK;
      Seal_Off     : Blob_Offset := 0;
   end record;

   procedure Init(P : out Parser_Context)
     with Post => P.State=S_Start;

   procedure Parse(P : in out Parser_Context; Blob : in Byte_Array)
     with
       Pre => Blob'Length <= Max_Blob_Bytes,
       Post => (P.State=S_Ready or P.State=S_Reject),
       Depends => (P => (P, Blob));

   function Get_Payload_Bounds(P : Parser_Context; Tensor_ID : Unsigned_32;
                               Off : out Blob_Offset; Len : out Blob_Length) return Boolean
     with Pre => P.State=S_Ready;

   function Find_Tensor(P : Parser_Context; ID : Unsigned_32; View : out Tensor_View) return Boolean
     with Pre => P.State=S_Ready;

   function Verify_Seal(P : Parser_Context; Blob : Byte_Array) return Boolean
     with Pre => P.State=S_Ready and Blob'Length>=32;

end Parser;
