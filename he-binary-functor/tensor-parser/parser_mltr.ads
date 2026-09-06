-- parser_mltr.ads
with Format_MLTR; use Format_MLTR;

package Parser_MLTR is
   pragma SPARK_Mode (On);

   type Parser_State is (
      Start,
      Header_Parsed,
      Descriptors_Parsed,
      Metadata_Parsed,
      Validated,
      Ready,
      Reject
   );

   type Model_Context is record
      State : Parser_State;
      Blob_Address : System.Address;
      Blob_Length : Blob_Index;
      Header : Model_Header;
      Tensor_Count : Tensor_Count_Type;
   end record;

   procedure Initialize_Parser (
      Ctx : out Model_Context;
      Addr : in System.Address;
      Len : in Blob_Index
   ) with
      Pre => Len >= Header_Size,
      Post => Ctx.State = Start and Ctx.Blob_Length = Len;

   procedure Parse_Header (Ctx : in out Model_Context) with
      Pre => Ctx.State = Start,
      Post => Ctx.State = Header_Parsed or Ctx.State = Reject,
      Depends => (Ctx => Ctx);

   procedure Parse_Descriptors (Ctx : in out Model_Context) with
      Pre => Ctx.State = Header_Parsed,
      Post => Ctx.State = Descriptors_Parsed or Ctx.State = Reject,
      Depends => (Ctx => Ctx);

   procedure Parse_Metadata (Ctx : in out Model_Context) with
      Pre => Ctx.State = Descriptors_Parsed,
      Post => Ctx.State = Metadata_Parsed or Ctx.State = Reject,
      Depends => (Ctx => Ctx);

   procedure Validate_Model (Ctx : in out Model_Context) with
      Pre => Ctx.State = Metadata_Parsed,
      Post => Ctx.State = Ready or Ctx.State = Reject,
      Depends => (Ctx => Ctx);

end Parser_MLTR;
