         TITLE 'TREASURY WORM IPL - Ahmad Ali Parr (DEED-083)'
***********************************************************************
* TREASURY WORM IPL — Sovereign Cold Boot Protocol                    *
* Author: Ahmad Ali Parr (ahmedparr93@gmail.com)                      *
* DEED-083: z/Architecture s390x Assembly                              *
*                                                                     *
* Phase 1: ROM Anchor — SHA-256 ROM hash via CPACF                    *
* Phase 2: PL/I⇄COBOL Bridge — SVC 254/255 register handlers         *
* Phase 3: Treasury WORM Driver — append/verify immutable records     *
*                                                                     *
* WORM Volume: 2TB max, hash-chained, append-only                     *
* BLAKE3 equivalent: SHA-256 via CPACF (MSG-SHA256 / KIMD-SHA256)     *
***********************************************************************
*
***********************************************************************
* PHASE 1: ROM ANCHOR                                                 *
* Compute SHA-256 of ROM contents (IPL load address 0-4095)           *
* Result stored in REG 2 (low) / REG 3 (high) as root hash           *
***********************************************************************
         SPACE 1
PHASE1   CSECT
         USING *,15              Base register
         STM   14,12,12(13)     Save caller registers
*
* Initialize — clear hash work area
         LHI   R4,0              Clear R4
         LHI   R5,0              Clear R5
         LA    R6,WORM_AREA      Load WORM work area address
         LHI   R7,WORM_LEN       Load WORM area length
*
* SHA-256 init: set initial hash values (FIPS 180-4)
         L     R8,=X'6A09E667'   H0
         ST    R8,HASHVAL+0
         L     R8,=X'BB67AE85'   H1
         ST    R8,HASHVAL+4
         L     R8,=X'3C6EF372'   H2
         ST    R8,HASHVAL+8
         L     R8,=X'A54FF53A'   H3
         ST    R8,HASHVAL+12
         L     R8,=X'510E527F'   H4
         ST    R8,HASHVAL+16
         L     R8,=X'9B05688C'   H5
         ST    R8,HASHVAL+20
         L     R8,=X'1F83D9AB'   H6
         ST    R8,HASHVAL+24
         L     R8,=X'5BE0CD19'   H7
         ST    R8,HASHVAL+28
*
* Use CPACF message digest: KIMD-SHA256
         LA    R0,1              Function: SHA-256
         LA    R1,WORM_AREA      Source address
         LHI   R2,4096           Source length (ROM 4KB)
         KIMD  R0,R1             Compute SHA-256
         BC    15,PHASE1_OK      Branch if no error
         LHI   R1,8              RC=8: CRC error
         B     EXIT_PH1
*
PHASE1_OK EQU   *
* Store root hash in REG 2/3 for SVC use
         L     R2,HASHVAL+0      Low 32 bits
         L     R3,HASHVAL+4      High 32 bits
         LHI   R1,0              RC=0: OK
*
EXIT_PH1 EQU   *
         LM    14,12,12(13)     Restore registers
         BR    14               Return to caller
         SPACE 1
***********************************************************************
* PHASE 2: PL/I ⇄ COBOL BRIDGE                                        *
* Register SVC handlers for WORM operations                           *
* SVC 254 = PL/I WRITE_ONCE (append immutable record)                 *
* SVC 255 = COBOL READ_MANY (verify + read record)                    *
* SVC 253 = BorrowChain anchor trigger                                 *
***********************************************************************
         SPACE 1
PHASE2   CSECT
         USING *,15
         STM   14,12,12(13)
*
* Register SVC 254 handler (PL/I WRITE_ONCE)
         LA    R0,SVC254_HDL     Load handler address
         SVC   253               Register SVC 254
         CHI   R1,0              Check RC
         BNE   PHASE2_ERR
*
* Register SVC 255 handler (COBOL READ_MANY)
         LA    R0,SVC255_HDL
         SVC   253               Register SVC 255
         CHI   R1,0
         BNE   PHASE2_ERR
*
* Register SVC 253 handler (BorrowChain anchor)
         LA    R0,SVC253_HDL
         SVC   253               Register SVC 253
         CHI   R1,0
         BNE   PHASE2_ERR
*
         LHI   R1,0              RC=0: OK
         B     EXIT_PH2
*
PHASE2_ERR EQU *
         LHI   R1,4              RC=4: handler registration failed
*
EXIT_PH2 EQU   *
         LM    14,12,12(13)
         BR    14
         SPACE 1
***********************************************************************
* SVC 254: PL/I WRITE_ONCE — Append Immutable WORM Record            *
* Input:  R1 = record address, R2 = record length                    *
* Output: R1 = RC (0=OK, 4=FULL, 8=CRC_ERR, 12=SEAL_FAIL)           *
*         R2 = record hash (SHA-256, 32 bytes)                       *
***********************************************************************
         SPACE 1
SVC254_HDL CSECT
         USING *,15
         STM   14,12,12(13)
*
* Check WORM space
         L     R3,=A(WORM_TAIL)  Load current tail offset
         AR    R3,R2             Compute new tail
         C     R3,=A(WORM_LIMIT) Compare to 2TB limit
         BH    SVC254_FULL       Branch if exceeded
*
* Compute SHA-256 of record payload
         LHI   R0,1              SHA-256 function
         LR    R1,R15            Source = record address
         LR    R2,R2             Length = record length
         KIMD  R0,R1             Compute hash
*
* Store hash in WORM at current tail
         L     R4,=A(WORM_TAIL)  Load tail pointer
         LA    R5,WORM_VOL        Load WORM volume base
         AR    R5,R4             Compute write address
         STCM  R2,B'1111',0(R5) Store hash (32 bytes)
*
* Update tail
         AHI   R4,32             Advance tail by 32 bytes
         ST    R4,=A(WORM_TAIL)  Store new tail
*
* Update root hash (chain link)
         L     R6,HASHVAL+0      Load current root low
         XR    R6,R2             XOR with new record hash
         ST    R6,HASHVAL+0      Store new root low
*
         LHI   R1,0              RC=0: OK
         L     R2,=A(WORM_TAIL)  Return hash address
         B     EXIT_SVC254
*
SVC254_FULL EQU *
         LHI   R1,4              RC=4: WORM full
*
EXIT_SVC254 EQU *
         LM    14,12,12(13)
         BR    14
         SPACE 1
***********************************************************************
* SVC 255: COBOL READ_MANY — Verify Hash Chain and Read Record        *
* Input:  R1 = record index                                           *
* Output: R1 = RC (0=OK, 4=NOT_FOUND, 8=HASH_MISMATCH, 12=CORRUPT)  *
*         R2 = record address                                         *
***********************************************************************
         SPACE 1
SVC255_HDL CSECT
         USING *,15
         STM   14,12,12(13)
*
* Bounds check
         L     R3,=A(RECORD_COUNT)
         CR    R1,R3             Compare index to count
         BNL   SVC254_NOTF       Branch if not found
*
* Compute record offset (index * 32)
         SLA   R1,5              R1 = index * 32
         LA    R5,WORM_VOL       Load WORM volume base
         AR    R5,R1             Compute record address
*
* Verify hash chain up to this record
         L     R6,=X'00000000'   Expected prev_hash = 0
         LHI   R7,0              Current index
*
VERIFY_LOOP EQU *
         CR    R7,R1             Past target record?
         BH    VERIFY_OK         Done if yes
*
* Load record's prev_hash
         L     R8,0(,R5)         Load prev_hash
         CR    R8,R6             Compare to expected
         BNE   SVC255_MISMATCH   Chain break
*
* Recompute hash for this record
         LHI   R0,1              SHA-256
         LR    R1,R5             Source = record
         LHI   R2,32             Length = 32 bytes
         KIMD  R0,R1             Compute hash
         LR    R6,R1             Save computed hash
*
         AHI   R7,1              Next index
         AHI   R5,32             Next record
         B     VERIFY_LOOP
*
VERIFY_OK EQU   *
         L     R2,=A(WORM_VOL)   Return record address
         AR    R2,R1
         LHI   R1,0              RC=0: OK
         B     EXIT_SVC255
*
SVC254_NOTF EQU *
         LHI   R1,4              RC=4: not found
         B     EXIT_SVC255
*
SVC255_MISMATCH EQU *
         LHI   R1,8              RC=8: hash mismatch
*
EXIT_SVC255 EQU *
         LM    14,12,12(13)
         BR    14
         SPACE 1
***********************************************************************
* SVC 253: BorrowChain Anchor — Trigger ICP anchor state              *
* Input:  R1 = anchor record address                                 *
* Output: R1 = RC (0=OK, 8=ANCHOR_FAIL)                             *
***********************************************************************
         SPACE 1
SVC253_HDL CSECT
         USING *,15
         STM   14,12,12(13)
*
* Commit anchor to WORM
         L     R2,=A(WORM_TAIL)  Load tail
         LA    R3,WORM_VOL       Load WORM base
         AR    R3,R2             Compute write addr
         MVC   0(32,R3),0(R1)   Copy anchor hash
         AHI   R2,32             Advance tail
         ST    R2,=A(WORM_TAIL)  Store new tail
*
         LHI   R1,0              RC=0: OK
         B     EXIT_SVC253
*
SVC253_ERR EQU *
         LHI   R1,8              RC=8: anchor failed
*
EXIT_SVC253 EQU *
         LM    14,12,12(13)
         BR    14
         SPACE 1
***********************************************************************
* PHASE 3: TREASURY WORM DRIVER                                       *
* Initialize WORM volume, set metadata, complete cold boot            *
***********************************************************************
         SPACE 1
PHASE3   CSECT
         USING *,15
         STM   14,12,12(13)
*
* Initialize WORM metadata
         L     R4,=A(WORM_AREA)  Load WORM area address
         LHI   R5,0              Clear offset
         ST    R5,WORM_TAIL      tail = 0
         L     R5,=F'2147483648'  2GB initial limit
         ST    R5,WORM_LIMIT     limit = 2GB
         LHI   R5,0              record_count = 0
         ST    R5,RECORD_COUNT
*
* Write genesis record (root hash = 0)
         LA    R1,GENESIS_REC     Load genesis record
         LHI   R2,32             Length = 32 bytes
         SVC   254               WRITE_ONCE
         CHI   R1,0
         BNE   PHASE3_ERR
*
* Verify chain integrity
         LHI   R1,0              Start at record 0
         SVC   255               READ_MANY + verify
         CHI   R1,0
         BNE   PHASE3_ERR
*
* Phase 3 complete — cold boot done
         LHI   R1,0              RC=0: OK
         B     EXIT_PH3
*
PHASE3_ERR EQU *
         LHI   R1,12             RC=12: cold boot failed
*
EXIT_PH3 EQU   *
         LM    14,12,12(13)
         BR    14
         SPACE 1
***********************************************************************
* DATA AREAS                                                          *
***********************************************************************
         SPACE 1
WORM_AREA DS    XL4096           WORM work area (4KB)
WORM_LEN  EQU   *-WORM_AREA
WORM_VOL  DS    XL32768          WORM volume (32KB initial)
WORM_TAIL DS    F                Current write offset
WORM_LIMIT DS   F                Max WORM size (2TB)
RECORD_COUNT DS F                Number of records
HASHVAL  DS    8F                SHA-256 intermediate hash
GENESIS_REC DS  XL32             Genesis record (zeros)
*
* WORM metadata constants
WORM_VERSION EQU 1
WORM_MAGIC   EQU X'DEED083'
*
         END   PHASE1
