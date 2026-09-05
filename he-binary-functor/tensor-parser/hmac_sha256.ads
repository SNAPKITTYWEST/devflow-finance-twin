with Interfaces; use Interfaces;
with System;

package HMAC_SHA256
  with SPARK_Mode => On
is
   subtype Byte is Unsigned_8;
   type Byte_Array is array (Positive range <>) of Byte;
   subtype Digest is Byte_Array (1 .. 32);
   subtype Block is Byte_Array (1 .. 64);

   type Key_View is record
      Addr : System.Address;
      Len : Natural;
   end record;

   procedure Compute
     (Key : Key_View;
      Data : System.Address;
      Data_Len: Byte_Count;
      Result : out Digest)
     with
       Pre => Key.Len <= 64
               and then Data_Len <= Byte_Count (Storage_Offset'Last),
       Global => null;

   function Equal (A, B : Digest) return Boolean
     with Inline, Global => null;

end HMAC_SHA256;
