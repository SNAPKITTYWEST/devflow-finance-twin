-- parser.adb
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;
with Validation; use Validation;

package body Parser
  with SPARK_Mode => On
is
   function Read_U32_LE (Addr : System.Address) return Unsigned_32
     with Inline, Pre => True;

   function Read_U64_LE (Addr : System.Address) return Unsigned_64
     with Inline, Pre => True;

   procedure Parse (Blob : Blob_View; Model : out Model_View) is
      Curr : Byte_Index := 0;
      H : Header;
   begin
      Model := (State => Start, others => <>);

      if Blob.Length < 32 then
         Model.State := Reject;
         return;
      end if;

      H.Magic := Read_U32_LE (Blob.Base);
      H.Version := Unsigned_16 (Read_U32_LE (Blob.Base + 4) and 16#FFFF#);

      if H.Magic /= Magic_Value or else H.Version /= Current_Version then
         Model.State := Reject;
         return;
      end if;

      Model.Header := H;
      Model.Tensor_Count := Tensor_Count (H.Tensor_Count);
      Model.State := Header_State;

      if Model.Tensor_Count > Max_Tensors then
         Model.State := Reject;
         return;
      end if;

      declare
         Desc_Off : constant Byte_Index := Byte_Index (H.Descriptor_Off);
         Desc_End : Byte_Index;
      begin
         if Desc_Off > Blob.Length or else
            Blob.Length - Desc_Off < Byte_Count (Model.Tensor_Count) * 64
         then
            Model.State := Reject;
            return;
         end if;
         Desc_End := Desc_Off + Byte_Count (Model.Tensor_Count) * 64;

         for I in 1 .. Model.Tensor_Count loop
            declare
               D_Addr : constant System.Address :=
                 Blob.Base + Storage_Offset (Desc_Off + (I - 1) * 64);
               T : Tensor_View;
            begin
               T.ID := Read_U32_LE (D_Addr);
               T.Offset := Byte_Index (Read_U64_LE (D_Addr + 8));
               T.Length := Byte_Count (Read_U64_LE (D_Addr + 16));
               T.Rank := Rank_Type (Read_U32_LE (D_Addr + 24) and 16#FF#);

               if not Validate_Tensor (T, Blob.Length, H.Payload_Off) then
                  Model.State := Reject;
                  return;
               end if;
               T.Valid := True;
               Model.Tensors (I) := T;
            end;
         end loop;
      end;

      Model.State := Descriptors;

      if not Check_Seal (Blob, H) then
         Model.State := Reject;
         return;
      end if;
      Model.Seal_OK := True;
      Model.State := Validate;

      Model.Payload_Base := Byte_Index (H.Payload_Off);
      Model.State := Ready;
   end Parse;

   function Is_Ready (M : Model_View) return Boolean is
   begin
      return M.State = Ready;
   end Is_Ready;

end Parser;
