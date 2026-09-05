with Interfaces; use Interfaces;
with System;

package SHA256
  with SPARK_Mode => On
is
   subtype Byte is Unsigned_8;
   subtype Word is Unsigned_32;
   subtype Byte_Array is array (Positive range <>) of Byte;
   subtype Word_Array is array (Positive range <>) of Word;

   subtype Digest is Byte_Array (1 .. 32);
   subtype Block is Byte_Array (1 .. 64);

   type Context is private;

   procedure Init (Ctx : out Context)
     with Global => null;

   procedure Update (Ctx : in out Context;
                     Data : System.Address;
                     Data_Len: Byte_Count)
     with
       Pre => Data_Len <= Byte_Count (Storage_Offset'Last),
       Global => null;

   procedure Final (Ctx : in out Context;
                     Result : out Digest)
     with Global => null;

   procedure Hash (Data : System.Address;
                   Data_Len: Byte_Count;
                   Result : out Digest)
     with
       Pre => Data_Len <= Byte_Count (Storage_Offset'Last),
       Global => null;

private
   type State_Array is array (0 .. 7) of Word;
   type W_Array is array (0 .. 63) of Word;

   type Context is record
      State : State_Array;
      Total_Len : Unsigned_64;
      Buf : Block;
      Buf_Len : Natural;
   end record;

end SHA256;
