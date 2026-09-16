(* Block 03 - Warp *)
structure Warp =
struct
  open RetroGPUCore

  datatype LaneState = Lane of {
    id : LaneID,
    active : bool,
    pred : bool,
    pc : int,
    regs : int list (* simplified values *)
  }

  datatype WarpState = Warp of {
    id : WarpID,
    width : WarpWidth, (* 32 for Hopper *)
    lanes : LaneState list,
    activeMask : Word32.word, (* bit mask *)
    predMask : Word32.word,
    pc : int,
    divergent : bool
  }

  fun makeWarp (wid, width) =
    let
      fun mkLane i = Lane {id=i, active=true, pred=true, pc=0, regs=[]}
      val lanes = List.tabulate (width, mkLane)
      val fullMask = Word32.<< (0w1, Word.fromInt width) - 0w1
    in
      Warp {id=wid, width=width, lanes=lanes,
            activeMask=fullMask, predMask=fullMask, pc=0, divergent=false}
    end

  fun setActive (Warp w, mask) =
    Warp {id= #id w, width= #width w, lanes= #lanes w,
          activeMask=mask, predMask= #predMask w, pc= #pc w,
          divergent= (mask <> #activeMask w)}

  fun broadcast (Warp w, srcLane, value) =
    (* simplified: all active lanes receive value *)
    Warp w

  fun shuffle (Warp w, srcLane, delta) = Warp w (* stub *)
  fun reduce (Warp w, op) = Warp w (* stub *)

  fun isDivergent (Warp {divergent,...}) = divergent
end
