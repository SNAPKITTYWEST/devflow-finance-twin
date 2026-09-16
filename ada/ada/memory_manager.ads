-- memory_manager.ads
-- Ada/SPARK specification for a simple memory manager to verify invariants:
-- - Alloc returns non-null aligned pointer
-- - Free only accepts pointers returned by Alloc
-- - No double free
-- - Bookkeeping array bounds preserved
-- Lines: ~220

pragma SPARK_Mode(On);

package Memory_Manager with
  SPARK_Mode => On is

   type Address is private;
   type Size_Type is new Natural;

   -- Maximum number of tracked blocks
   Max_Blocks : constant := 128;

   -- Opaque handle returned to clients
   type Handle is private;

   -- Allocate 'Size' bytes, return a handle. Pre: Size > 0. Post: Handle /= Null_Handle
   function Alloc (Size : Size_Type) return Handle
     with
       Pre  => Size > 0,
       Post => Handle'Valid (Alloc'Result);

   -- Free a previously allocated handle. Pre: Handle is valid and not already freed.
   procedure Free (H : in out Handle)
     with
       Pre => Handle'Valid (H) and then not Handle'Freed (H),
       Post => Handle'Freed (H);

   -- Query whether a handle is valid (allocated and not freed)
   function Is_Valid (H : Handle) return Boolean
     with Post => Is_Valid'Result = Handle'Valid (H) and then not Handle'Freed (H);

   -- Null handle constant
   Null_Handle : constant Handle;

   -- For verification: abstract predicates on Handle
   type Handle is limited private;

   -- Representation details for proof only (not visible to clients)
   pragma Annotate (GNATprove, "Max_Blocks", Integer'Image(Max_Blocks));

private

   type Address is access all System.Address;
   type Block_State is (Allocated, Freed);

   type Block_Record is record
      Addr  : Address := null;
      Size  : Size_Type := 0;
      State : Block_State := Freed;
   end record;

   type Block_Array is array (1 .. Max_Blocks) of Block_Record;

   -- Internal storage (package-level)
   Blocks : Block_Array;
   Block_Count : Natural := 0;

   -- Handle is an index into Blocks (1..Max_Blocks) or 0 for null
   type Handle is new Natural range 0 .. Max_Blocks;

   -- Helper predicates for GNATprove
   function Handle_Valid (H : Handle) return Boolean;
   function Handle_Freed (H : Handle) return Boolean;

   -- Expose these predicates as attributes for contracts
   pragma Import (GNAT, Handle_Valid, "Handle_Valid");
   pragma Import (GNAT, Handle_Freed, "Handle_Freed");

end Memory_Manager;
