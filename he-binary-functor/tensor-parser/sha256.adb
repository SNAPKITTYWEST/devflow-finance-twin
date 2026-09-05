with System.Storage_Elements; use System.Storage_Elements;

package body SHA256
  with SPARK_Mode => On
is

   K : constant Word_Array (0 .. 63) :=
     (16#428a2f98#, 16#71374491#, 16#b5c0fbcf#, 16#e9b5dba5#,
      16#3956c25b#, 16#59f111f1#, 16#923f82a4#, 16#ab1c5ed5#,
      16#d807aa98#, 16#12835b01#, 16#243185be#, 16#550c7dc3#,
      16#72be5d74#, 16#80deb1fe#, 16#9bdc06a7#, 16#c19bf174#,
      16#e49b69c1#, 16#efbe4786#, 16#0fc19dc6#, 16#240ca1cc#,
      16#2de92c6f#, 16#4a7484aa#, 16#5cb0a9dc#, 16#76f988da#,
      16#983e5152#, 16#a831c66d#, 16#b00327c8#, 16#bf597fc7#,
      16#c6e00bf3#, 16#d5a79147#, 16#06ca6351#, 16#14292967#,
      16#27b70a85#, 16#2e1b2138#, 16#4d2c6dfc#, 16#53380d13#,
      16#650a7354#, 16#766a0abb#, 16#81c2c92e#, 16#92722c85#,
      16#a2bfe8a1#, 16#a81a664b#, 16#c24b8b70#, 16#c76c51a3#,
      16#d192e819#, 16#d6990624#, 16#f40e3585#, 16#106aa070#,
      16#19a4c116#, 16#1e376c08#, 16#2748774c#, 16#34b0bcb5#,
      16#391c0cb3#, 16#4ed8aa4a#, 16#5b9cca4f#, 16#682e6ff3#,
      16#748f82ee#, 16#78a5636f#, 16#84c87814#, 16#8cc70208#,
      16#90befffa#, 16#a4506ceb#, 16#bef9a3f7#, 16#c67178f2#);

   Init_State : constant State_Array :=
     (16#6a09e667#, 16#bb67ae85#, 16#3c6ef372#, 16#a54ff53a#,
      16#510e527f#, 16#9b05688c#, 16#1f83d9ab#, 16#5be0cd19#);

   function Rotr (X : Word; N : Natural) return Word
     with Inline, Pre => N < 32, Global => null
   is
   begin
      return Rotate_Right (X, N);
   end Rotr;

   function Shr (X : Word; N : Natural) return Word
     with Inline, Pre => N < 32, Global => null
   is
   begin
      return Shift_Right (X, N);
   end Shr;

   function Ch (X, Y, Z : Word) return Word is
     (X and Y) xor ((not X) and Z)
     with Inline;

   function Maj (X, Y, Z : Word) return Word is
     (X and Y) xor (X and Z) xor (Y and Z)
     with Inline;

   function Big_Sigma0 (X : Word) return Word is
     Rotr (X, 2) xor Rotr (X, 13) xor Rotr (X, 22)
     with Inline;

   function Big_Sigma1 (X : Word) return Word is
     Rotr (X, 6) xor Rotr (X, 11) xor Rotr (X, 25)
     with Inline;

   function Small_Sigma0 (X : Word) return Word is
     Rotr (X, 7) xor Rotr (X, 18) xor Shr (X, 3)
     with Inline;

   function Small_Sigma1 (X : Word) return Word is
     Rotr (X, 17) xor Rotr (X, 19) xor Shr (X, 10)
     with Inline;

   procedure Compress (Ctx : in out Context; Block_Data : Block)
     with Global => null
   is
      W : W_Array;
      A, B, C, D, E, F, G, H, T1, T2 : Word;
   begin
      for I in 0 .. 15 loop
         W (I) := Shift_Left (Word (Block_Data (I*4 + 1)), 24) or
                  Shift_Left (Word (Block_Data (I*4 + 2)), 16) or
                  Shift_Left (Word (Block_Data (I*4 + 3)), 8) or
                  Word (Block_Data (I*4 + 4));
      end loop;

      for I in 16 .. 63 loop
         W (I) := Small_Sigma1 (W (I-2)) + W (I-7) +
                  Small_Sigma0 (W (I-15)) + W (I-16);
      end loop;

      A := Ctx.State (0); B := Ctx.State (1);
      C := Ctx.State (2); D := Ctx.State (3);
      E := Ctx.State (4); F := Ctx.State (5);
      G := Ctx.State (6); H := Ctx.State (7);

      for I in 0 .. 63 loop
         T1 := H + Big_Sigma1 (E) + Ch (E, F, G) + K (I) + W (I);
         T2 := Big_Sigma0 (A) + Maj (A, B, C);
         H := G; G := F; F := E;
         E := D + T1;
         D := C; C := B; B := A;
         A := T1 + T2;
      end loop;

      Ctx.State (0) := Ctx.State (0) + A;
      Ctx.State (1) := Ctx.State (1) + B;
      Ctx.State (2) := Ctx.State (2) + C;
      Ctx.State (3) := Ctx.State (3) + D;
      Ctx.State (4) := Ctx.State (4) + E;
      Ctx.State (5) := Ctx.State (5) + F;
      Ctx.State (6) := Ctx.State (6) + G;
      Ctx.State (7) := Ctx.State (7) + H;
   end Compress;

   procedure Init (Ctx : out Context) is
   begin
      Ctx.State := Init_State;
      Ctx.Total_Len := 0;
      Ctx.Buf := (others => 0);
      Ctx.Buf_Len := 0;
   end Init;

   procedure Update (Ctx : in out Context;
                     Data : System.Address;
                     Data_Len: Byte_Count)
   is
      Remaining : Byte_Count := Data_Len;
      Offset : Byte_Count := 0;
      P : System.Address := Data;
      Take : Natural;
   begin
      while Remaining > 0 loop
         Take := Natural'Min (64 - Ctx.Buf_Len, Natural (Remaining));

         for I in 0 .. Take - 1 loop
            Ctx.Buf (Ctx.Buf_Len + I + 1) :=
              Byte'(Read_Byte (P + Storage_Offset (I)));
         end loop;

         Ctx.Buf_Len := Ctx.Buf_Len + Take;
         Ctx.Total_Len := Ctx.Total_Len + Unsigned_64 (Take) * 8;
         Remaining := Remaining - Byte_Count (Take);
         P := P + Storage_Offset (Take);
         Offset := Offset + Byte_Count (Take);

         if Ctx.Buf_Len = 64 then
            Compress (Ctx, Ctx.Buf);
            Ctx.Buf_Len := 0;
         end if;
      end loop;
   end Update;

   procedure Final (Ctx : in out Context; Result : out Digest) is
      Bit_Len : constant Unsigned_64 := Ctx.Total_Len;
      Pad_Len : Natural;
   begin
      Ctx.Buf (Ctx.Buf_Len + 1) := 16#80#;
      Ctx.Buf_Len := Ctx.Buf_Len + 1;

      if Ctx.Buf_Len > 56 then
         while Ctx.Buf_Len < 64 loop
            Ctx.Buf (Ctx.Buf_Len + 1) := 0;
            Ctx.Buf_Len := Ctx.Buf_Len + 1;
         end loop;
         Compress (Ctx, Ctx.Buf);
         Ctx.Buf_Len := 0;
      end if;

      while Ctx.Buf_Len < 56 loop
         Ctx.Buf (Ctx.Buf_Len + 1) := 0;
         Ctx.Buf_Len := Ctx.Buf_Len + 1;
      end loop;

      for I in 0 .. 7 loop
         Ctx.Buf (57 + I) :=
           Byte (Shift_Right (Bit_Len, 56 - I*8) and 16#FF#);
      end loop;

      Compress (Ctx, Ctx.Buf);

      for I in 0 .. 7 loop
         Result (I*4 + 1) := Byte (Shift_Right (Ctx.State (I), 24));
         Result (I*4 + 2) := Byte (Shift_Right (Ctx.State (I), 16) and 16#FF#);
         Result (I*4 + 3) := Byte (Shift_Right (Ctx.State (I), 8) and 16#FF#);
         Result (I*4 + 4) := Byte (Ctx.State (I) and 16#FF#);
      end loop;
   end Final;

   procedure Hash (Data : System.Address;
                   Data_Len: Byte_Count;
                   Result : out Digest)
   is
      Ctx : Context;
   begin
      Init (Ctx);
      Update (Ctx, Data, Data_Len);
      Final (Ctx, Result);
   end Hash;

   function Read_Byte (A : System.Address) return Byte
     with Inline, Global => null
   is
      B : Byte with Address => A, Import;
   begin
      return B;
   end Read_Byte;

end SHA256;
