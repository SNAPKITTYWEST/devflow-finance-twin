-- Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
-- SPDX-License-Identifier: FSL-1.1
-- DEED-088: Unsigned type definitions for Ada/C interop.

package Unsigned_Types is

   pragma Pure (Unsigned_Types);

   type Unsigned_8 is mod 2 ** 8
      with Size => 8;

   type Unsigned_16 is mod 2 ** 16
      with Size => 16;

   type Unsigned_32 is mod 2 ** 32
      with Size => 32;

   type Unsigned_64 is mod 2 ** 64
      with Size => 64;

end Unsigned_Types;
