namespace ManifoldOptimization {
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Canon;
    open Microsoft.Quantum.Convert;

    operation ManifoldGreedyStep(qubits : Qubit[], theta : Double) : Unit is Adj + Ctl {
        let n = Length(qubits);
        for i in 0 .. n - 1 {
            Rx(theta * IntAsDouble(i + 1), qubits[i]);

            if i > 0 {
                CNOT(qubits[i - 1], qubits[i]);
            }
        }
    }
}
