"""Command-line entry for the Dream-RSI reconstruction."""

import argparse
import json

from .core import DreamRSI, RunConfig
from .discovery import AlgorithmEngineering, MathematicalOptimization, GPUKernelEngineering


def main(argv=None):
    parser = argparse.ArgumentParser(description="Dream-RSI mechanism reconstruction")
    parser.add_argument("task")
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--revisions", type=int, default=4)
    parser.add_argument("--domain", choices=["algorithm", "math", "gpu"], default="algorithm")
    args = parser.parse_args(argv)

    domain_map = {
        "algorithm": AlgorithmEngineering(),
        "math": MathematicalOptimization(),
        "gpu": GPUKernelEngineering(),
    }
    system = DreamRSI(adapter=domain_map[args.domain])
    result = system.run(RunConfig(args.task, args.rounds, args.revisions))
    print(json.dumps({
        "worlds": result["worlds"],
        "policy": result["policy"].__dict__,
        "metrics": result["metrics"].__dict__,
    }, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
