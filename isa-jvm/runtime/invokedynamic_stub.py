# ========================================================================
# SOVEREIGN LEVIATHAN NODE LICENSE
# License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
# Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
# ========================================================================
#
# This file is a covered work under the GNU Affero General Public License,
# version 3, together with the Sovereign Leviathan additional terms.
#
# Hark, though this node be but a spark,
# Its covenant endureth through the dark.
#
# Ignorantia juris non excusat.
# ========================================================================

"""invokedynamic bootstrap descriptors for late-bound ISA primitives.

Documents linkage; actual BSM is a Java helper class emitted alongside programs.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class InvokeDynamicSite:
    name: str
    descriptor: str
    bootstrap: str
    static_args: tuple[str, ...] = ()

    def purpose(self) -> str:
        return f"Late-bound ISA primitive '{self.name}' resolved via {self.bootstrap}"


# Well-known sites
SITES = {
    "TENSOR_DISPATCH": InvokeDynamicSite(
        name="tensorDispatch",
        descriptor="(JJ)J",
        bootstrap="IsaBootstrap/tensorBSM",
        static_args=("tensor",),
    ),
    "AGENT_SEND": InvokeDynamicSite(
        name="agentSend",
        descriptor="(JJ)V",
        bootstrap="IsaBootstrap/agentBSM",
    ),
    "CHAN_READ": InvokeDynamicSite(
        name="chanRead",
        descriptor="(J)J",
        bootstrap="IsaBootstrap/channelBSM",
    ),
}


def bootstrap_java_source() -> str:
    """Minimal Java bootstrap class source for documentation / emission."""
    return r'''
import java.lang.invoke.*;
public class IsaBootstrap {
  public static CallSite tensorBSM(MethodHandles.Lookup l, String n, MethodType t, String kind)
      throws Exception {
    MethodHandle mh = MethodHandles.lookup().findStatic(IsaBootstrap.class, "tensorOp",
        MethodType.methodType(long.class, long.class, long.class));
    return new ConstantCallSite(mh.asType(t));
  }
  public static long tensorOp(long a, long b) { return a + b; } // placeholder
  public static CallSite agentBSM(MethodHandles.Lookup l, String n, MethodType t) throws Exception {
    MethodHandle mh = MethodHandles.lookup().findStatic(IsaBootstrap.class, "agentSend",
        MethodType.methodType(void.class, long.class, long.class));
    return new ConstantCallSite(mh.asType(t));
  }
  public static void agentSend(long agent, long val) { /* runtime hooks */ }
  public static CallSite channelBSM(MethodHandles.Lookup l, String n, MethodType t) throws Exception {
    MethodHandle mh = MethodHandles.lookup().findStatic(IsaBootstrap.class, "chanRead",
        MethodType.methodType(long.class, long.class));
    return new ConstantCallSite(mh.asType(t));
  }
  public static long chanRead(long ch) { return 0L; }
}
'''
