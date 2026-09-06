-- parser.ads
with Format; use Format;
with Interfaces; use Interfaces;

package Parser
  with SPARK_Mode => On
is
   type Parse_State is (Start, Header_State, Descriptors, Metadata, Validate, Ready, Reject);

   type Blob_View is record
      Base : System.Address;
      Length : Byte_Count;
   end record;

   type Tensor_View is record
      ID : Unsigned_32;
      Offset : Byte_Index;
      Length : Byte_Count;
      Rank : Rank_Type;
      Shape : Shape_Array;
      DType : DType;
      Alignment : Align_Type;
      Element_Cnt: Unsigned_64;
      Valid : Boolean := False;
   end record;

   type Tensor_Table is array (1 .. Max_Tensors) of Tensor_View;

   type Model_View is record
      State : Parse_State := Start;
      Header : Header;
      Tensor_Count : Tensor_Count := 0;
      Tensors : Tensor_Table;
      Payload_Base : Byte_Index := 0;
      Seal_OK : Boolean := False;
   end record;

   procedure Parse (Blob : Blob_View; Model : out Model_View)
     with
       Pre => Blob.Length >= 32
               and then Blob.Base /= System.Null_Address,
       Post => (if Model.State = Ready then
                  Model.Tensor_Count <= Max_Tensors
                  and then (for all I in 1 .. Model.Tensor_Count =>
                              Model.Tensors(I).Valid
                              and then Model.Tensors(I).Offset + Model.Tensors(I).Length
                                       <= Blob.Length)),
       Depends => (Model => Blob),
       Global => null;

   function Is_Ready (M : Model_View) return Boolean
     with Post => Is_Ready'Result = (M.State = Ready);

end Parser;
