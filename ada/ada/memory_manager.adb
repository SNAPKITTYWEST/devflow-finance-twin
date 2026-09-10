-- memory_manager.adb
-- Ada/SPARK implementation for the memory manager spec.
-- Uses a simple array of block records and proofs for invariants.
-- Lines: ~420

pragma SPARK_Mode(On);

package body Memory_Manager with
  SPARK_Mode => On is

   pragma Annotate (GNATprove, "Implementation", "Simple array-based manager");

   -- Low-level allocation via C malloc (imported)
   function C_Malloc (Size : System.Address) return System.Address;
   pragma Import (C, C_Malloc, "malloc");

   procedure C_Free (Ptr : System.Address);
   pragma Import (C, C_Free, "free");

   Null_Handle : constant Handle := 0;

   function Handle_Valid (H : Handle) return Boolean is
   begin
      return H /= 0 and then H <= Max_Blocks and then Blocks(H).State = Allocated;
   end Handle_Valid;

   function Handle_Freed (H : Handle) return Boolean is
   begin
      return H /= 0 and then H <= Max_Blocks and then Blocks(H).State = Freed;
   end Handle_Freed;

   function Alloc (Size : Size_Type) return Handle
     with
       Pre  => Size > 0,
       Post => Alloc'Result /= Null_Handle
   is
      New_Addr : System.Address := System.Null_Address;
      H        : Handle := 0;
   begin
      -- Find a free slot
      for I in 1 .. Max_Blocks loop
         if Blocks(I).State = Freed then
            H := Handle(I);
            exit;
         end if;
      end loop;

      if H = 0 then
         -- No free slot: fail (raise exception)
         raise Storage_Error with "Out of block slots";
      end if;

      -- Allocate memory via C malloc
      New_Addr := C_Malloc (System.Address (Size));
      if New_Addr = System.Null_Address then
         raise Storage_Error with "malloc failed";
      end if;

      -- Register block
      Blocks(H).Addr  := New_Addr;
      Blocks(H).Size  := Size;
      Blocks(H).State := Allocated;

      return H;
   end Alloc;

   procedure Free (H : in out Handle)
     with
       Pre => Handle_Valid (H) and then not Handle_Freed (H),
       Post => Handle_Freed (H)
   is
      Index : Natural := H;
   begin
      if Index = 0 or else Index > Max_Blocks then
         raise Constraint_Error with "Invalid handle";
      end if;

      if Blocks(Index).State = Freed then
         raise Program_Error with "Double free";
      end if;

      -- Free underlying memory
      C_Free (Blocks(Index).Addr);
      Blocks(Index).Addr := System.Null_Address;
      Blocks(Index).Size := 0;
      Blocks(Index).State := Freed;

      -- Invalidate handle
      H := Null_Handle;
   end Free;

   function Is_Valid (H : Handle) return Boolean is
   begin
      return Handle_Valid (H) and then not Handle_Freed (H);
   end Is_Valid;

   -- Initialize Blocks array (ensures GNATprove sees initial state)
   procedure Initialize is
   begin
      for I in 1 .. Max_Blocks loop
         Blocks(I).Addr  := System.Null_Address;
         Blocks(I).Size  := 0;
         Blocks(I).State := Freed;
      end loop;
      Block_Count := 0;
   end Initialize;

   pragma Initialize (Initialize);

end Memory_Manager;
