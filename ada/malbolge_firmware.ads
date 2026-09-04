-- Malbolge Co-Processor Firmware Specification (Ring -3)
-- Hardware entropy source via chaotic ternary computation
-- Isolated from main CPU, no external memory access, deterministic execution

with Interfaces; use Interfaces;

package Malbolge_Firmware is

   procedure Initialize;
   -- Reset all registers, memory, and entropy buffer to genesis state

   procedure Run_Steps (Count : Natural);
   -- Execute Count Malbolge steps, collecting entropy from Out instructions

   function Get_Entropy return Unsigned_32;
   -- Retrieve next entropy sample from buffer (returns 0 if empty)

   procedure Execute_Step;
   -- Execute a single Malbolge instruction (internal, exposed for testing)

end Malbolge_Firmware;
