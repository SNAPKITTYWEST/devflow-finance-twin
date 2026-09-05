import argparse
import logging
import signal
import sys
from pathlib import Path
from worm import WormStorageEngine
from twin import FinanceTwinEngine

# Exit codes
EXIT_OK = 0
EXIT_ERROR = 1
EXIT_USAGE = 2

logger = logging.getLogger("devflow.cli")


def setup_logging(verbose: bool = False) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S%z"
    )


def signal_handler(signum, frame):
    print("\nInterrupted. Exiting gracefully.", file=sys.stderr)
    sys.exit(EXIT_OK)


def main():
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    parser = argparse.ArgumentParser(
        description="Devflow Finance Twin — Sovereign Deterministic Finance Engine"
    )
    parser.add_argument("--storage", default="ledger.worm", help="Path to WORM storage file")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable debug logging")
    subparsers = parser.add_subparsers(dest="command", help="Command to execute")

    # CREATE_ACCOUNT
    acc_parser = subparsers.add_parser("CREATE_ACCOUNT", help="Create a new account")
    acc_parser.add_argument("--account_id", required=True, help="Unique account identifier")
    acc_parser.add_argument("--balance", default="0.0000", help="Initial balance (default: 0.0000)")
    acc_parser.add_argument("--actor", default="treasurer_admin", help="Actor performing the action")

    # POST_TRANSACTION
    tx_parser = subparsers.add_parser("POST_TRANSACTION", help="Post financial transaction")
    tx_parser.add_argument("--tx_id", required=True, help="Unique transaction identifier")
    tx_parser.add_argument("--from_account", required=True, help="Source account ID")
    tx_parser.add_argument("--to_account", required=True, help="Destination account ID")
    tx_parser.add_argument("--amount", required=True, help="Transfer amount")
    tx_parser.add_argument("--actor", default="system_operator", help="Actor performing the action")

    # CREATE_INVOICE
    inv_parser = subparsers.add_parser("CREATE_INVOICE", help="Create an invoice")
    inv_parser.add_argument("--invoice_id", required=True, help="Unique invoice identifier")
    inv_parser.add_argument("--amount", required=True, help="Invoice amount")
    inv_parser.add_argument("--actor", default="treasurer_admin", help="Actor performing the action")

    # VERIFY
    subparsers.add_parser("VERIFY_HISTORY", help="Verify WORM integrity and replay ledger state")

    # STATUS
    subparsers.add_parser("STATUS", help="Display current ledger state and Merkle seal")

    args = parser.parse_args()
    setup_logging(args.verbose)

    try:
        storage = WormStorageEngine(args.storage)
        twin = FinanceTwinEngine(storage)
    except Exception as e:
        print(f"FATAL: Failed to initialize engine: {e}", file=sys.stderr)
        sys.exit(EXIT_ERROR)

    try:
        if args.command == "CREATE_ACCOUNT":
            res = twin.execute_command("CREATE_ACCOUNT", args.actor, {
                "account_id": args.account_id,
                "initial_balance": args.balance
            })
            print(f"Account Created: {res['event_id']}")
            print(f"  WORM Hash: {res['worm_record_hash'][:16]}...")
            print(f"  State Hash: {res['current_state_hash'][:16]}...")
            sys.exit(EXIT_OK)

        elif args.command == "POST_TRANSACTION":
            res = twin.execute_command("POST_TRANSACTION", args.actor, {
                "transaction_id": args.tx_id,
                "from_account": args.from_account,
                "to_account": args.to_account,
                "amount": args.amount
            })
            print(f"Transaction Posted: {res['event_id']}")
            print(f"  WORM Hash: {res['worm_record_hash'][:16]}...")
            print(f"  State Hash: {res['current_state_hash'][:16]}...")
            sys.exit(EXIT_OK)

        elif args.command == "CREATE_INVOICE":
            res = twin.execute_command("CREATE_INVOICE", args.actor, {
                "invoice_id": args.invoice_id,
                "amount": args.amount
            })
            print(f"Invoice Created: {res['event_id']}")
            sys.exit(EXIT_OK)

        elif args.command == "VERIFY_HISTORY":
            valid, err = twin.verify_ledger_consistency()
            if valid:
                print("VERIFICATION SUCCESSFUL: Ledger integrity and state replay verified.")
                sys.exit(EXIT_OK)
            else:
                print(f"VERIFICATION FAILED: {err}", file=sys.stderr)
                sys.exit(EXIT_ERROR)

        elif args.command == "STATUS":
            print(f"Event Count:   {twin.event_count}")
            print(f"Accounts:      {len(twin.accounts)}")
            print(f"Transactions:  {len(twin.transactions)}")
            print(f"Invoices:      {len(twin.invoices)}")
            print(f"Obligations:   {len(twin.liabilities)}")
            if twin.latest_decision_seal:
                print(f"Latest Seal:   {twin.latest_decision_seal['cryptographic_digest'][:16]}...")
            else:
                print("Latest Seal:   None")
            sys.exit(EXIT_OK)

        else:
            parser.print_help()
            sys.exit(EXIT_USAGE)

    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(EXIT_ERROR)
    except Exception as e:
        logger.exception("Unexpected error")
        print(f"FATAL: {e}", file=sys.stderr)
        sys.exit(EXIT_ERROR)


if __name__ == "__main__":
    main()
