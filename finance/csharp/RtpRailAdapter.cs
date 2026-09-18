public sealed class RtpRailAdapter : IPaymentRailAdapter
{
    public string RailCode => "RTP";
    private readonly IDbConnection _db;
    private readonly ICobolGateway _cobol;

    public RtpRailAdapter(IDbConnection db, ICobolGateway cobol)
    {
        _db = db;
        _cobol = cobol;
    }

    public async Task<SubmissionResult> CreateSubmissionAsync(RailSubmissionRequest req, CancellationToken ct)
    {
        var cmd = _db.CreateCommand();
        cmd.CommandText = @"
            INSERT INTO RAIL_SUBMISSIONS (RAIL_CODE, PAYMENT_ID, TRANSACTION_ID, STATUS, CREATED_AT, UPDATED_AT)
            VALUES (@rail, @pay, @txn, 'CREATED', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
            SELECT IDENTITY_VAL_LOCAL() FROM SYSIBM.SYSDUMMY1";
        AddParam(cmd, "@rail", RailCode);
        AddParam(cmd, "@pay", req.PaymentId);
        AddParam(cmd, "@txn", req.TransactionId);
        var id = Convert.ToInt64(await cmd.ExecuteScalarAsync(ct));
        await EmitEventAsync("RTP.SubmissionCreated", id, req, ct);
        return new SubmissionResult { SubmissionId = id };
    }

    public async Task<SubmissionAck> SubmitAsync(long submissionId, CancellationToken ct)
    {
        var cmd = _db.CreateCommand();
        cmd.CommandText = "UPDATE RAIL_SUBMISSIONS SET STATUS='SUBMITTED', UPDATED_AT=CURRENT_TIMESTAMP WHERE SUBMISSION_ID=@id";
        AddParam(cmd, "@id", submissionId);
        await cmd.ExecuteNonQueryAsync(ct);
        await EmitEventAsync("RTP.Submitted", submissionId, null, ct);
        return new SubmissionAck { SubmissionId = submissionId, Success = true };
    }

    public async Task ProcessNotificationAsync(long submissionId, RailNotification notif, CancellationToken ct)
    {
        var cmd = _db.CreateCommand();
        cmd.CommandText = @"
            INSERT INTO RAIL_NOTIFICATIONS (SUBMISSION_ID, RAIL_CODE, TYPE, PAYLOAD, RECEIVED_AT)
            VALUES (@sid, @rail, @type, @payload, CURRENT_TIMESTAMP)";
        AddParam(cmd, "@sid", submissionId);
        AddParam(cmd, "@rail", RailCode);
        AddParam(cmd, "@type", notif.Type);
        AddParam(cmd, "@payload", notif.Payload);
        await cmd.ExecuteNonQueryAsync(ct);

        if (notif.Type == "SETTLEMENT")
        {
            var cmdRec = new LedgerCommandRecord
            {
                TransactionId  = notif.TransactionId,
                AccountId      = notif.SettlementAccountId,
                Amount         = notif.Amount,
                Currency       = notif.Currency,
                Direction      = "C",
                IdempotencyKey = notif.IdempotencyKey,
                CorrelationId  = notif.CorrelationId
            };
            var cobolGateway = new CobolGateway(new IbmInvoker());
            await cobolGateway.InvokeLedgerCommandAsync(cmdRec, "LEDGER-GATEWAY", ct);
        }

        await EmitEventAsync("RTP.NotificationReceived", submissionId, notif, ct);
    }

    private static IDbDataParameter AddParam(IDbCommand cmd, string name, object value)
    {
        var p = cmd.CreateParameter();
        p.ParameterName = name;
        p.Value = value ?? DBNull.Value;
        cmd.Parameters.Add(p);
        return p;
    }

    private async Task EmitEventAsync(string eventType, long aggregateId, object? payload, CancellationToken ct)
    {
        var cmd = _db.CreateCommand();
        cmd.CommandText = @"
            INSERT INTO EVENT_STORE (EVENT_TYPE, AGGREGATE_ID, AGGREGATE_TYPE, PAYLOAD, OCCURRED_AT, SEQUENCE_NUM, PROCESSED)
            VALUES (@etype, @aid, 'RTP_SUBMISSION', @payload, CURRENT_TIMESTAMP,
                    NEXT VALUE FOR EVENT_STORE_SEQ, 'N')";
        AddParam(cmd, "@etype", eventType);
        AddParam(cmd, "@aid", aggregateId.ToString());
        AddParam(cmd, "@payload", payload is null ? (object)DBNull.Value
                                  : System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(payload));
        await cmd.ExecuteNonQueryAsync(ct);
    }
}
