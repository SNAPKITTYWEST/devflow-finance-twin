# docs/WORDCODE.md — instruction reference
One Word per instruction: [op:8|a:16|b:20|c:20].
- Data movement: CONST r imm40 · LOAD r slot · STORE slot r · PUSH r · POP r · DROP · DUP
- Arithmetic: ADD SUB MUL DIV MOD (DIV/MOD fault on 0) · AND OR XOR NOT SHL SHR (fault ≥64) · BOOL r
- Compare (ZF=1 iff true): EQ NE LT LE GT GE — unsigned
- Control: JMP a · JZ a (ZF set) · JNZ a · CALL addr argc framesize · RET (R0 = value)
- Concurrency: SPAWN addr argc framesize (R0 = pid) · SEND ch val (val also staged in R1)
  · RECV ch (R0 = value) · ALT ra rb off (left guard first; timeout skips off+1 words)
  · WAIT pid · YIELD
- Memory: ALLOC r n · FREE r (double free / OOB fault)
- I/O: IN r · OUT r · OUTS off len · CHAN r · HALT (exit code R0)
- NOP
Image: MAGIC VERSION WORD_SIZE CODE_SIZE DATA_SIZE ENTRY ENTRY_FRAME_SIZE, code, data.
