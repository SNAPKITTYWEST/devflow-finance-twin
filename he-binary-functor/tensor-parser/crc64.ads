with Interfaces; use Interfaces;

package CRC64
  with SPARK_Mode => On
is
   subtype CRC_Value is Unsigned_64;

   Polynomial : constant CRC_Value := 16#42F0_E1EB_A9EA_3693#;

   function Init return CRC_Value
     with Inline, Global => null,
          Post => Init'Result = 16#FFFF_FFFF_FFFF_FFFF#;

   procedure Update
     (CRC : in out CRC_Value;
      Addr : System.Address;
      Len : Byte_Count)
     with
       Pre => Len <= Byte_Count (Storage_Offset'Last),
       Global => null;

   function Final (CRC : CRC_Value) return CRC_Value
     with Inline, Global => null,
          Post => Final'Result = (CRC xor 16#FFFF_FFFF_FFFF_FFFF#);

   function Compute (Addr : System.Address; Len : Byte_Count) return CRC_Value
     with
       Pre => Len <= Byte_Count (Storage_Offset'Last),
       Global => null;

end CRC64;
