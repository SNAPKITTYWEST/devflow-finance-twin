-- parser.adb — Dense state machine, overflow-safe, zero-copy
with Format; use Format;
with Validation; use Validation;
with Interfaces; use Interfaces;

package body Parser with SPARK_Mode is

   procedure Init(P : out Parser_Context) is
   begin
      P.State := S_Start;
      P.Blob_Len := 0;
      P.Tensor_Count := 0;
      P.Error := OK;
      P.Seal_Off := 0;
   end Init;

   function Read_U32_LE(B : Byte_Array; Off : Natural) return Unsigned_32 is
      (LE_U32(Unsigned_8(B(Off)), Unsigned_8(B(Off+1)), Unsigned_8(B(Off+2)), Unsigned_8(B(Off+3))))
     with Pre => Off+3 < B'Length;

   function Read_U16_LE(B : Byte_Array; Off : Natural) return Unsigned_16 is
      (LE_U16(Unsigned_8(B(Off)), Unsigned_8(B(Off+1))))
     with Pre => Off+1 < B'Length;

   function Read_U64_LE(B : Byte_Array; Off : Natural) return Unsigned_64 is
      (LE_U64(Unsigned_8(B(Off)), Unsigned_8(B(Off+1)), Unsigned_8(B(Off+2)), Unsigned_8(B(Off+3)),
              Unsigned_8(B(Off+4)), Unsigned_8(B(Off+5)), Unsigned_8(B(Off+6)), Unsigned_8(B(Off+7))))
     with Pre => Off+7 < B'Length;

   procedure Parse_Header_Raw(B : Byte_Array; H : out Raw_Header; Ok : out Boolean) is
   begin
      Ok := False;
      if B'Length < Header_Size_Bytes then return; end if;
      H.Magic := Read_U32_LE(B,0);
      H.Version := Read_U16_LE(B,4);
      H.Flags := Read_U16_LE(B,6);
      H.Header_Size := Read_U32_LE(B,8);
      H.Tensor_Count := Read_U32_LE(B,12);
      H.Desc_Table_Offset := Read_U64_LE(B,16);
      H.Desc_Size := Read_U32_LE(B,24);
      H.Meta_Offset := Read_U64_LE(B,28);
      H.Meta_Length := Read_U32_LE(B,36);
      H.Payload_Offset := Read_U64_LE(B,40);
      H.Payload_Length := Read_U64_LE(B,48);
      H.Header_CRC32 := Read_U32_LE(B,56);
      H.Reserved := Read_U32_LE(B,60);
      Ok := True;
   end Parse_Header_Raw;

   procedure Parse_Descriptor_Raw(B : Byte_Array; Off : Natural; D : out Raw_Descriptor; Ok : out Boolean) is
   begin
      Ok := False;
      if Off+Descriptor_Size_Bytes > B'Length then return; end if;
      D.Tensor_ID := Read_U32_LE(B,Off);
      D.DType := Unsigned_8(B(Off+4));
      D.Rank := Unsigned_8(B(Off+5));
      D.Reserved0 := Read_U16_LE(B,Off+6);
      D.Offset := Read_U64_LE(B,Off+8);
      D.Length := Read_U64_LE(B,Off+16);
      for I in 0..Max_Rank-1 loop
         D.Dims(I) := Read_U32_LE(B,Off+24+I*4);
      end loop;
      D.Alignment := Read_U32_LE(B,Off+56);
      D.Desc_CRC32 := Read_U32_LE(B,Off+60);
      Ok := True;
   end Parse_Descriptor_Raw;

   procedure Parse(P : in out Parser_Context; Blob : in Byte_Array) is
      RawH : Raw_Header;
      Ok : Boolean;
      Err : Validation_Error;
   begin
      P.Blob_Len := Blob'Length;
      P.State := S_Start;

      if Blob'Length < Header_Size_Bytes then
         P.State := S_Reject; P.Error := Err_Meta_Bounds; return;
      end if;
      Parse_Header_Raw(Blob, RawH, Ok);
      if not Ok then P.State:=S_Reject; P.Error:=Err_Magic; return; end if;

      P.Header := RawH;

      Validate_Header(RawH, Blob_Length(Blob'Length), Err);
      if Err/=OK then P.State:=S_Reject; P.Error:=Err; return; end if;
      P.State := S_Header;
      P.Tensor_Count := Natural(RawH.Tensor_Count);
      P.Header_View := (Version=>RawH.Version, Tensor_Count=>Natural(RawH.Tensor_Count),
                        Desc_Off=>Blob_Offset(RawH.Desc_Table_Offset),
                        Meta_Off=>Blob_Offset(RawH.Meta_Offset),
                        Meta_Len=>Blob_Length(RawH.Meta_Length),
                        Payload_Off=>Blob_Offset(RawH.Payload_Offset),
                        Payload_Len=>Blob_Length(RawH.Payload_Length));
      if In_Bounds(Blob_Offset(RawH.Meta_Offset), Blob_Offset(RawH.Meta_Length), Blob_Offset(Blob'Length)) then
         P.Seal_Off := Blob_Offset(RawH.Meta_Offset + Unsigned_64(RawH.Meta_Length));
      else
         P.State:=S_Reject; P.Error:=Err_Meta_Bounds; return;
      end if;

      P.State := S_Descriptors;
      for Idx in 0..P.Tensor_Count-1 loop
         declare
            Off : Natural := Natural(RawH.Desc_Table_Offset) + Idx*Descriptor_Size_Bytes;
            RawD : Raw_Descriptor;
         begin
            Parse_Descriptor_Raw(Blob, Off, RawD, Ok);
            if not Ok then P.State:=S_Reject; P.Error:=Err_Desc_Offset; return; end if;
            Validate_Descriptor(RawD, Blob_Length(Blob'Length),
                                Blob_Offset(RawH.Payload_Offset), Blob_Offset(RawH.Payload_Length), Err);
            if Err/=OK then P.State:=S_Reject; P.Error:=Err; return; end if;
            P.Tensors(Idx) := (Tensor_ID=>RawD.Tensor_ID,
                               DType=>Valid_DType'Val(RawD.DType),
                               Rank=>Rank(RawD.Rank),
                               Dims=>RawD.Dims,
                               Offset=>Blob_Offset(RawD.Offset),
                               Length=>Blob_Length(RawD.Length),
                               Alignment=>Alignment(RawD.Alignment));
         end;
      end loop;

      P.State := S_Metadata;
      if RawH.Meta_Length > Max_Metadata_Bytes then
         P.State:=S_Reject; P.Error:=Err_Meta_Bounds; return;
      end if;

      P.State := S_Validate;

      P.State := S_Ready;
      P.Error := OK;
   end Parse;

   function Get_Payload_Bounds(P : Parser_Context; Tensor_ID : Unsigned_32;
                               Off : out Blob_Offset; Len : out Blob_Length) return Boolean is
   begin
      for I in 0..P.Tensor_Count-1 loop
         if P.Tensors(I).Tensor_ID = Tensor_ID then
            Off := P.Tensors(I).Offset;
            Len := P.Tensors(I).Length;
            return True;
         end if;
      end loop;
      return False;
   end Get_Payload_Bounds;

   function Find_Tensor(P : Parser_Context; ID : Unsigned_32; View : out Tensor_View) return Boolean is
   begin
      for I in 0..P.Tensor_Count-1 loop
         if P.Tensors(I).Tensor_ID = ID then
            View := P.Tensors(I);
            return True;
         end if;
      end loop;
      return False;
   end Find_Tensor;

   function Verify_Seal(P : Parser_Context; Blob : Byte_Array) return Boolean is
   begin
      if P.Seal_Off + Seal_Size_Bytes > Blob_Offset(Blob'Length) then return False; end if;
      return True;
   end Verify_Seal;

end Parser;
