// Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
// SPDX-License-Identifier: AGPL-3.0-or-later
// DEED-089: Sovereign Treasury Engine — Scala Pure Pipeline
// Functor-driven deterministic serialization, SHA-256 chain, append-only WORM store.

import java.nio.{ByteBuffer, ByteOrder}
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path, Paths, StandardOpenOption}
import java.security.MessageDigest
import java.time.Instant
import scala.util.{Try, Success, Failure}

// ── 1. Core domain — mirrors the PL/I TREASURY_LEDGER_ENTRY ──────────────────

final case class TreasuryEntry(
  txId: String,
  txTimestamp: Long,
  txSequence: Int,
  sourceAccount: String,
  destAccount: String,
  transferAmount: BigDecimal,
  currencyCode: String,
  complianceFlag: Byte
)

// ── 2. WORM block — exact analogue of the PL/I / C WormBlock ─────────────────

final case class WormBlock(
  magic: String,
  prevHash: String,
  currHash: String,
  recordCount: Int,
  payload: Array[Byte]
) {
  def toBytes: Array[Byte] = {
    val buf = ByteBuffer.allocate(4 + 64 + 64 + 4 + payload.length)
      .order(ByteOrder.BIG_ENDIAN)
    buf.put(magic.getBytes(StandardCharsets.US_ASCII))
    buf.put(prevHash.getBytes(StandardCharsets.US_ASCII))
    buf.put(currHash.getBytes(StandardCharsets.US_ASCII))
    buf.putInt(recordCount)
    buf.put(payload)
    buf.array()
  }
}

// ── 3. Functor layer (explicit, no external Cats dependency) ─────────────────

trait Functor[F[_]] {
  def map[A, B](fa: F[A])(f: A => B): F[B]
}

case class Id[A](value: A)
object Id {
  implicit val idFunctor: Functor[Id] = new Functor[Id] {
    def map[A, B](fa: Id[A])(f: A => B): Id[B] = Id(f(fa.value))
  }
}

case class Chained[A](value: A, prevHash: String)
object Chained {
  implicit val chainedFunctor: Functor[Chained] = new Functor[Chained] {
    def map[A, B](fa: Chained[A])(f: A => B): Chained[B] =
      Chained(f(fa.value), fa.prevHash)
  }
}

def fmap[F[_], A, B](fa: F[A])(f: A => B)(implicit F: Functor[F]): F[B] =
  F.map(fa)(f)

// ── 4. Deterministic serialization (byte-level, fixed offsets) ───────────────

object Serializer {
  private val EntrySize = 128
  private val PayloadSize = 4096

  def serializeEntry(e: TreasuryEntry): Array[Byte] = {
    val buf = ByteBuffer.allocate(EntrySize).order(ByteOrder.BIG_ENDIAN)

    def putFixed(str: String, len: Int): Unit = {
      val bytes = str.getBytes(StandardCharsets.US_ASCII)
      buf.put(bytes.take(len))
      if (bytes.length < len) buf.put(Array.fill(len - bytes.length)(0.toByte))
    }

    putFixed(e.txId, 36)
    buf.putLong(e.txTimestamp)
    buf.putInt(e.txSequence)
    putFixed(e.sourceAccount, 16)
    putFixed(e.destAccount, 16)

    val amountScaled = (e.transferAmount * 100)
      .setScale(0, BigDecimal.RoundingMode.HALF_EVEN).longValue
    buf.putLong(amountScaled)

    putFixed(e.currencyCode, 3)
    buf.put(e.complianceFlag)

    while (buf.position() < EntrySize) buf.put(0.toByte)
    buf.array()
  }

  def buildPayload(entries: Seq[TreasuryEntry]): Array[Byte] = {
    val buf = ByteBuffer.allocate(PayloadSize)
    entries.foreach { e =>
      val ser = serializeEntry(e)
      if (buf.remaining() >= ser.length) buf.put(ser)
    }
    while (buf.hasRemaining) buf.put(0.toByte)
    buf.array()
  }
}

// ── 5. Cryptographic hashing (SHA-256, deterministic) ────────────────────────

object Crypto {
  def sha256Hex(data: Array[Byte]): String = {
    val md = MessageDigest.getInstance("SHA-256")
    md.digest(data).map("%02x".format(_)).mkString
  }

  def chainHash(prevHash: String, payload: Array[Byte]): String = {
    val prevBytes = prevHash.getBytes(StandardCharsets.US_ASCII)
    sha256Hex(prevBytes ++ payload)
  }
}

// ── 6. VSAM-style append-only WORM store ──────────────────────────────────────

class WormStore(path: Path) {
  if (!Files.exists(path)) Files.createFile(path)

  def append(block: WormBlock): Try[Unit] = Try {
    val bytes = block.toBytes
    val channel = Files.newByteChannel(
      path,
      StandardOpenOption.WRITE,
      StandardOpenOption.APPEND
    )
    try {
      channel.write(ByteBuffer.wrap(bytes))
      channel.force(true)
    } finally {
      channel.close()
    }
  }

  def lastHash: String = "0" * 64
}

// ── 7. Full pipeline — functor-driven, deterministic ─────────────────────────

object TreasuryPipeline {

  def process(
    entry: TreasuryEntry,
    prevHash: String,
    store: WormStore
  ): Try[(WormBlock, String)] = {

    val idEntry: Id[TreasuryEntry] = Id(entry)
    val serialized: Id[Array[Byte]] = fmap(idEntry)(Serializer.serializeEntry)

    val payload = Serializer.buildPayload(Seq(entry))
    val currHash = Crypto.chainHash(prevHash, payload)

    val block = WormBlock(
      magic = "WORM",
      prevHash = prevHash,
      currHash = currHash,
      recordCount = 1,
      payload = payload
    )

    store.append(block).map(_ => (block, currHash))
  }

  def processBatch(
    entries: Seq[TreasuryEntry],
    initialHash: String,
    store: WormStore
  ): Try[String] = {
    entries.foldLeft(Try(initialHash)) { (accHashTry, entry) =>
      accHashTry.flatMap { prev =>
        process(entry, prev, store).map { case (_, newHash) => newHash }
      }
    }
  }
}

// ── 8. Demonstration ─────────────────────────────────────────────────────────

object SovereignTreasuryApp extends App {
  val storePath = Paths.get("data/treasury-worm.bin")
  Files.createDirectories(storePath.getParent)
  val store = new WormStore(storePath)

  val sample = TreasuryEntry(
    txId = "f47ac10b-58cc-4372-a567-0e02b2c3d479",
    txTimestamp = Instant.now().toEpochMilli,
    txSequence = 500001,
    sourceAccount = "SOVEREIGN-TRES01",
    destAccount = "SETTLE-POOL-0007",
    transferAmount = BigDecimal("9876543.21"),
    currencyCode = "USD",
    complianceFlag = 0xc0.toByte
  )

  println("=== Sovereign Treasury Engine – Scala WORM Pipeline ===")

  val result = TreasuryPipeline.process(sample, "0" * 64, store)

  result match {
    case Success((block, hash)) =>
      println(s"Magic : ${block.magic}")
      println(s"Prev Hash : ${block.prevHash.take(32)}...")
      println(s"Curr Hash : ${hash.take(32)}...")
      println(s"Record Count : ${block.recordCount}")
      println(s"TX ID : ${sample.txId}")
      println(s"Amount : ${sample.transferAmount} ${sample.currencyCode}")
      println("WORM block committed successfully.")
    case Failure(ex) =>
      println(s"Pipeline failed: ${ex.getMessage}")
  }

  val batch = (1 to 5).map { i =>
    sample.copy(
      txSequence = sample.txSequence + i,
      transferAmount = sample.transferAmount + BigDecimal(i * 1000),
      txId = f"${sample.txId.take(24)}${sample.txSequence + i}%012d"
    )
  }

  TreasuryPipeline.processBatch(batch, result.map(_._2).getOrElse("0" * 64), store) match {
    case Success(finalHash) =>
      println(s"\nBatch of ${batch.size} records sealed.")
      println(s"Final chain hash: ${finalHash.take(32)}...")
    case Failure(ex) =>
      println(s"Batch failed: ${ex.getMessage}")
  }

  println("=== Pipeline complete ===")
}
