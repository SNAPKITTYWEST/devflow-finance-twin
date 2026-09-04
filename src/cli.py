import argparse
import sys
from pathlib import Path

try:
    from worm import WormStorageEngine
    from twin import FinanceTwinEngine
    from quantum import QuantumAbstractionLayer
except ImportError:
    from src.worm import WormStorageEngine
    from src.twin import FinanceTwinEngine
    from src.quantum import QuantumAbstractionLayer

def main():
    parser = argparse.ArgumentParser(description="Devflow Finance Twin & Quantum Sovereign Stack")
    parser.add_argument("--storage", default="ledger.worm", help="Path to WORM storage file")
    subparsers = parser.add_subparsers(dest="command", help="Command to execute")

    # CREATE_ACCOUNT
    acc_parser = subparsers.add_parser("CREATE_ACCOUNT", help="Create a new account")
    acc_parser.add_argument("--account_id", required=True)
    acc_parser.add_argument("--balance", default="0.0000")
    acc_parser.add_argument("--actor", default="treasurer_admin")

    # POST_TRANSACTION
    tx_parser = subparsers.add_parser("POST_TRANSACTION", help="Post financial transaction")
    tx_parser.add_argument("--tx_id", required=True)
    tx_parser.add_argument("--from_account", required=True)
    tx_parser.add_argument("--to_account", required=True)
    tx_parser.add_argument("--amount", required=True)
    tx_parser.add_argument("--actor", default="system_operator")

    # VERIFY
    subparsers.add_parser("VERIFY_HISTORY", help="Verify WORM integrity and replay ledger state")

    # STATUS
    subparsers.add_parser("STATUS", help="Display current ledger state and Merkle seal")

    args = parser.parse_args()
    storage = WormStorageEngine(args.storage)
    twin = FinanceTwinEngine(storage)

    if args.command == "CREATE_ACCOUNT":
        res = twin.execute_command("CREATE_ACCOUNT", args.actor, {
            "account_id": args.account_id,
            "initial_balance": args.balance
        })
        print(f"Account Created successfully:\n{res}")

    elif args.command == "POST_TRANSACTION":
        res = twin.execute_command("POST_TRANSACTION", args.actor, {
            "transaction_id": args.tx_id,
            "from_account": args.from_account,
            "to_account": args.to_account,
            "amount": args.amount
        })
        print(f"Transaction Posted successfully:\n{res}")

    elif args.command == "VERIFY_HISTORY":
        valid, err = twin.verify_ledger_consistency()
        if valid:
            print("VERIFICATION SUCCESSFUL: Ledger integrity and state replay verified pristine.")
            sys.exit(0)
        else:
            print(f"VERIFICATION FAILED: {err}")
            sys.exit(1)

    elif args.command == "STATUS":
        print(f"Event Count: {twin.event_count}")
        print(f"Accounts: {dict(twin.accounts)}")
        seal = twin.latest_decision_seal['cryptographic_digest'] if twin.latest_decision_seal else 'None'
        print(f"Latest Seal Digest: {seal}")

    else:
        parser.print_help()

if __name__ == "__main__":
    main()
