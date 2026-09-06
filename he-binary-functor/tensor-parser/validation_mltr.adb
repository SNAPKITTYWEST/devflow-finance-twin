-- validation_mltr.adb
with System.Storage_Elements; use System.Storage_Elements;

package body Validation_MLTR is
   pragma SPARK_Mode (On);

   use type Interfaces.Unsigned_32;
   use type Blob_Index;

   procedure Verify_Structure (
      Addr : in System.Address;
      Len : in Blob_Index;
      Header : in Model_Header;
      Valid : out Boolean
   ) is
      Desc_Offset : constant Blob_Index := Header_Size;
      Desc_Bytes : constant Blob_Index := Blob_Index(Header.Tensor_Count) * 32;
   begin
      Valid := False;

      if Desc_Bytes > Len - Desc_Offset then
         return;
      end if;

      for I in 0 .. Header.Tensor_Count - 1 loop
         declare
            Current_Offset : constant Blob_Index := Desc_Offset + Blob_Index(I) * 32;
            Desc_Ptr : constant System.Address := Addr + Storage_Offset(Current_Offset);
            Desc : Tensor_Descriptor;
            for Desc'Address use Desc_Ptr;
            pragma Import (Ada, Desc);

            Element_Size : Blob_Index;
            Total_Elements : Blob_Index := 1;
         begin
            if Desc.Rank > Max_Rank or Desc.Rank = 0 then
               return;
            end if;

            for R in 1 .. Desc.Rank loop
               declare
                  Dim : constant Blob_Index := Blob_Index(Desc.Shape(Integer(R)));
               begin
                  if Dim = 0 or else Dim > Max_Dimension then
                     return;
                  end if;
                  if Total_Elements > Blob_Index'Last / Dim then
                     return;
                  end if;
                  Total_Elements := Total_Elements * Dim;
               end;
            end loop;

            case Desc.Dtype is
               when Float32 | Bfloat16 => Element_Size := 4;
               when Float16 => Element_Size := 2;
               when Int8 | Uint8 => Element_Size := 1;
            end case;

            if Total_Elements > Blob_Index'Last / Element_Size then
               return;
            end if;

            declare
               Required_Bytes : constant Blob_Index := Total_Elements * Element_Size;
            begin
               if Desc.Length /= Required_Bytes then
                  return;
               end if;

               if Desc.Length > Len - Desc.Offset then
                  return;
               end if;
            end;
         end;
      end loop;

      Valid := True;
   end Verify_Structure;

end Validation_MLTR;
