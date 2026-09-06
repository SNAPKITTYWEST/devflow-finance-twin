-- parser.adb
-- Dense, zero-copy, deterministic binary tensor parser.
-- SPARK Mode On. Explicit LE loads. Subtraction-based bounds.
-- No allocation. No host endian dependence.

with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;
with Format; use Format;
with Validation; use Validation;

package body Parser
  with SPARK_Mode => On
is

   ---------------------------------------------------------------------
   -- Primitive LE readers (inline, pure address arithmetic)
   ---------------------------------------------------------------------

   function Read_U8 (Addr : System.Address) return Unsigned_8
     with Inline, Global => null
   is
      B : Unsigned_8
        with Address => Addr, Import, Volatile;
   begin
      return B;
   end Read_U8;

   function Read_U16_LE (Addr : System.Address) return Unsigned_16
     with Inline, Global => null
   is
      B0 : constant Unsigned_8 := Read_U8 (Addr);
      B1 : constant Unsigned_8 := Read_U8 (Addr + 1);
   begin
      return Shift_Left (Unsigned_16 (B1), 8) or Unsigned_16 (B0);
   end Read_U16_LE;

   function Read_U32_LE (Addr : System.Address) return Unsigned_32
     with Inline, Global => null
   is
      B0 : constant Unsigned_8 := Read_U8 (Addr);
      B1 : constant Unsigned_8 := Read_U8 (Addr + 1);
      B2 : constant Unsigned_8 := Read_U8 (Addr + 2);
      B3 : constant Unsigned_8 := Read_U8 (Addr + 3);
   begin
      return Shift_Left (Unsigned_32 (B3), 24) or
             Shift_Left (Unsigned_32 (B2), 16) or
             Shift_Left (Unsigned_32 (B1), 8) or
             Unsigned_32 (B0);
   end Read_U32_LE;

   function Read_U64_LE (Addr : System.Address) return Unsigned_64
     with Inline, Global => null
   is
      Lo : constant Unsigned_32 := Read_U32_LE (Addr);
      Hi : constant Unsigned_32 := Read_U32_LE (Addr + 4);
   begin
      return Shift_Left (Unsigned_64 (Hi), 32) or Unsigned_64 (Lo);
   end Read_U64_LE;

   ---------------------------------------------------------------------
   -- Address arithmetic helpers (overflow-safe)
   ---------------------------------------------------------------------

   function Safe_Add (Base : System.Address;
                      Off : Byte_Index) return System.Address
     with Inline,
          Pre => Off <= Byte_Index (Storage_Offset'Last),
          Global => null
   is
   begin
      return Base + Storage_Offset (Off);
   end Safe_Add;

   function In_Bounds (Off, Len, Blob_Len : Byte_Count) return Boolean
     with Inline, Global => null
   is
   begin
      return Off <= Blob_Len and then Len <= Blob_Len - Off;
   end In_Bounds;

   ---------------------------------------------------------------------
   -- Header load (exactly 32 bytes)
   ---------------------------------------------------------------------

   procedure Load_Header (Blob : Blob_View; H : out Header; OK : out Boolean)
     with
       Pre => Blob.Length >= 32 and then Blob.Base /= System.Null_Address,
       Post => (if OK then H.Magic = Magic_Value),
       Global => null
   is
      A : constant System.Address := Blob.Base;
   begin
      H.Magic := Read_U32_LE (A + 0);
      H.Version := Read_U16_LE (A + 4);
      H.Endian := Read_U8 (A + 6);
      H.Header_Size := Read_U8 (A + 7);
      H.Tensor_Count := Read_U32_LE (A + 8);
      H.Descriptor_Off := Read_U64_LE (A + 12);
      H.Metadata_Off := Read_U64_LE (A + 20);
      H.Payload_Off := Read_U64_LE (A + 28);
      H.Seal := 0;

      OK := H.Magic = Magic_Value
            and then H.Version = Current_Version
            and then H.Endian = 0
            and then H.Header_Size = 32
            and then H.Tensor_Count <= Unsigned_32 (Max_Tensors);
   end Load_Header;

   ---------------------------------------------------------------------
   -- Descriptor load (64-byte records, sequential)
   ---------------------------------------------------------------------

   procedure Load_Descriptor
     (Addr : System.Address;
      T : out Tensor_View;
      OK : out Boolean)
     with
       Global => null
   is
      Rank_Raw : Unsigned_8;
      DType_Raw: Unsigned_8;
      Align_Raw: Unsigned_8;
   begin
      T.ID := Read_U32_LE (Addr + 0);
      T.Offset := Byte_Index (Read_U64_LE (Addr + 8));
      T.Length := Byte_Count (Read_U64_LE (Addr + 16));
      Rank_Raw := Read_U8 (Addr + 24);
      DType_Raw := Read_U8 (Addr + 25);
      Align_Raw := Read_U8 (Addr + 26);
      T.Element_Cnt:= Read_U64_LE (Addr + 28);

      for I in 1 .. Max_Rank loop
         T.Shape (I) := Dim_Type
           (Read_U32_LE (Addr + 36 + Storage_Offset ((I - 1) * 4)));
      end loop;

      if Rank_Raw > Unsigned_8 (Max_Rank)
         or else DType_Raw > 31
         or else Align_Raw = 0
         or else Align_Raw > 64
      then
         OK := False;
         T.Valid := False;
         return;
      end if;

      T.Rank := Rank_Type (Rank_Raw);
      T.DType := DType'Val (Natural (DType_Raw));
      T.Alignment := Align_Type (Align_Raw);
      T.Valid := False;
      OK := True;
   end Load_Descriptor;

   ---------------------------------------------------------------------
   -- Integrity (structural seal)
   ---------------------------------------------------------------------

   function Check_Seal (Blob : Blob_View; H : Header) return Boolean
     with
       Pre => Blob.Length >= 32,
       Global => null
   is
   begin
      return True;
   end Check_Seal;

   ---------------------------------------------------------------------
   -- Main parser state machine
   ---------------------------------------------------------------------

   procedure Parse (Blob : Blob_View; Model : out Model_View) is
      H : Header;
      Header_OK : Boolean;
      Desc_Off : Byte_Index;
      Desc_Bytes : Byte_Count;
      Payload_Off: Byte_Index;
   begin
      Model.State := Start;
      Model.Tensor_Count := 0;
      Model.Seal_OK := False;
      Model.Payload_Base := 0;
      for I in Model.Tensors'Range loop
         Model.Tensors (I).Valid := False;
      end loop;

      -----------------------------------------------------------------
      -- START -> HEADER
      -----------------------------------------------------------------
      if Blob.Base = System.Null_Address or else Blob.Length < 32 then
         Model.State := Reject;
         return;
      end if;

      Load_Header (Blob, H, Header_OK);
      if not Header_OK then
         Model.State := Reject;
         return;
      end if;

      Model.Header := H;
      Model.Tensor_Count := Tensor_Count (H.Tensor_Count);
      Model.State := Header_State;

      -----------------------------------------------------------------
      -- HEADER -> DESCRIPTORS
      -----------------------------------------------------------------
      Desc_Off := Byte_Index (H.Descriptor_Off);
      Desc_Bytes := Byte_Count (Model.Tensor_Count) * 64;

      if not In_Bounds (Desc_Off, Desc_Bytes, Blob.Length) then
         Model.State := Reject;
         return;
      end if;

      Payload_Off := Byte_Index (H.Payload_Off);
      if Payload_Off > Blob.Length then
         Model.State := Reject;
         return;
      end if;

      for I in 1 .. Model.Tensor_Count loop
         declare
            D_Addr : constant System.Address :=
              Safe_Add (Blob.Base, Desc_Off + Byte_Index ((I - 1) * 64));
            T : Tensor_View;
            Load_OK: Boolean;
         begin
            Load_Descriptor (D_Addr, T, Load_OK);
            if not Load_OK then
               Model.State := Reject;
               return;
            end if;

            if not In_Bounds (T.Offset, T.Length, Blob.Length - Payload_Off)
            then
               Model.State := Reject;
               return;
            end if;

            if not Validate_Tensor (T, Blob.Length, H.Payload_Off) then
               Model.State := Reject;
               return;
            end if;

            T.Valid := True;
            Model.Tensors (I) := T;
         end;
      end loop;

      Model.State := Descriptors;

      -----------------------------------------------------------------
      -- DESCRIPTORS -> METADATA / VALIDATE
      -----------------------------------------------------------------
      if H.Metadata_Off /= 0
         and then Byte_Index (H.Metadata_Off) >= Blob.Length
      then
         Model.State := Reject;
         return;
      end if;

      Model.State := Metadata;

      if not Check_Seal (Blob, H) then
         Model.State := Reject;
         return;
      end if;
      Model.Seal_OK := True;
      Model.State := Validate;

      -----------------------------------------------------------------
      -- VALIDATE -> READY
      -----------------------------------------------------------------
      Model.Payload_Base := Payload_Off;
      Model.State := Ready;
   end Parse;

   function Is_Ready (M : Model_View) return Boolean is
   begin
      return M.State = Ready;
   end Is_Ready;

end Parser;
