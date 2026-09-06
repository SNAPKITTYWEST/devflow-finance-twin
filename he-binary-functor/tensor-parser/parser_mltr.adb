-- parser_mltr.adb
with Interfaces.C;
with System.Storage_Elements; use System.Storage_Elements;
with Validation_MLTR;

package body Parser_MLTR is
   pragma SPARK_Mode (On);

   use type Interfaces.Unsigned_32;

   procedure Initialize_Parser (
      Ctx : out Model_Context;
      Addr : in System.Address;
      Len : in Blob_Index
   ) is
   begin
      Ctx := (
         State => Start,
         Blob_Address => Addr,
         Blob_Length => Len,
         Header => (others => <>),
         Tensor_Count => 0
      );
   end Initialize_Parser;

   procedure Parse_Header (Ctx : in out Model_Context) is
      Header_Ptr : constant System.Address := Ctx.Blob_Address;
      Source_Header : Model_Header;
      for Source_Header'Address use Header_Ptr;
      pragma Import (Ada, Source_Header);
   begin
      if Ctx.Blob_Length < Header_Size then
         Ctx.State := Reject;
         return;
      end if;

      Ctx.Header := Source_Header;

      if Ctx.Header.Magic /= Magic_Constant then
         Ctx.State := Reject;
         return;
      end if;

      if Ctx.Header.Version /= Current_Version then
         Ctx.State := Reject;
         return;
      end if;

      if Ctx.Header.Endianness /= Little_Endian then
         Ctx.State := Reject;
         return;
      end if;

      if Ctx.Header.Tensor_Count > Max_Tensors then
         Ctx.State := Reject;
         return;
      end if;

      Ctx.Tensor_Count := Ctx.Header.Tensor_Count;
      Ctx.State := Header_Parsed;
   end Parse_Header;

   procedure Parse_Descriptors (Ctx : in out Model_Context) is
      Expected_Desc_Bytes : constant Blob_Index := Blob_Index(Ctx.Tensor_Count) * 32;
      Desc_Start_Offset : constant Blob_Index := Header_Size;
   begin
      if Expected_Desc_Bytes > Ctx.Blob_Length - Desc_Start_Offset then
         Ctx.State := Reject;
         return;
      end if;

      Ctx.State := Descriptors_Parsed;
   end Parse_Descriptors;

   procedure Parse_Metadata (Ctx : in out Model_Context) is
      Meta_Off : constant Blob_Index := Ctx.Header.Meta_Offset;
      Meta_Len : constant Blob_Index := Ctx.Header.Meta_Length;
   begin
      if Meta_Len > 0 then
         if Meta_Len > Ctx.Blob_Length - Meta_Off then
            Ctx.State := Reject;
            return;
         end if;
      end if;

      Ctx.State := Metadata_Parsed;
   end Parse_Metadata;

   procedure Validate_Model (Ctx : in out Model_Context) is
      Valid : Boolean;
   begin
      Validation_MLTR.Verify_Structure (
         Ctx.Blob_Address,
         Ctx.Blob_Length,
         Ctx.Header,
         Valid
      );

      if Valid then
         Ctx.State := Ready;
      else
         Ctx.State := Reject;
      end if;
   end Validate_Model;

end Parser_MLTR;
