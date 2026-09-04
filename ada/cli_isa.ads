with Interfaces; use Interfaces;

package Cli_Isa is
   type Byte_Array is array (Natural range <>) of Unsigned_8;
   function Execute_Binary_Isa (Buffer : Byte_Array) return Integer;
end Cli_Isa;
