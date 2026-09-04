// Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
// SPDX-License-Identifier: AGPL-3.0-or-later
// DEED-089: Sovereign Treasury Engine — Scala + ZIO Effectful Pipeline
// Resource-safe WORM store, streaming, batch processing, effectful execution.

import zio._
import zio.stream._
import java.nio.{ByteBuffer, ByteOrder}
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path, Paths, StandardOpenOption}
import java.nio.channels.FileChannel
import java.security.MessageDigest
import java.time.Instant

// ── 1. Domain model (unchanged — pure) ───────────────────────────────────────

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

final case class WormBlock(
  magic: String,
  prevHash: String,
  currHash: String,
  recordCount: Int,
  payload: Array[Byte]
) {
  def toBytes: Array[Byte] = {
    val buf = ByteBuffer
      .allocate(4 + 64 + 64 + 4 + payload.length)
      .order(ByteOrder.BIG_ENDIAN)
    buf.put(magic.getBytes(StandardCharsets.US_ASCII))
    buf.put(prevHash.getBytes(StandardCharsets.US_ASCII))
    buf.put(currHash.getBytes(StandardCharsets.US_ASCII))
    buf.putInt(recordCount)
    buf.put(payload)
    buf.array()
  }
}

// ── 2. Error ADT ──────────────────────────────────────────────────────────────

sealed trait TreasuryError extends Throwable
object TreasuryError {
  final case class SerializationError(msg: String) extends TreasuryError {
    override def getMessage: String = msg
  }
  final case class HashError(msg: String) extends TreasuryError {
    override def getMessage: String = msg
  }
  final case class WormIOError(msg: String, cause: Option[Throwable] = None)
      extends TreasuryError {
    override def getMessage: String = msg
    override def getCause: Throwable = cause.orNull
  }
  final case class PipelineError(msg: String) extends TreasuryError {
    override def getMessage: String = msg
  }
}

// ── 3. Pure serialization & crypto (no effects) ──────────────────────────────

object Serializer {
  private val EntrySize = 128
  private val PayloadSize = 4096

  def serializeEntry(e: TreasuryEntry): Array[Byte] = {
    val buf = ByteBuffer.allocate(EntrySize).order(ByteOrder.BIG_ENDIAN)

    def putFixed(str: String, len: Int): Unit = {
      val bytes = str.getBytes(StandardCharsets.US_ASCII)
      buf.put(bytes.take(len))
      if (bytes.length < len)
        buf.put(Array.fill[Byte](len - bytes.length)(0))
    }

    putFixed(e.txId, 36)
    buf.putLong(e.txTimestamp)
    buf.putInt(e.txSequence)
    putFixed(e.sourceAccount, 16)
    putFixed(e.destAccount, 16)

    val amountScaled =
      (e.transferAmount * 100)
        .setScale(0, BigDecimal.RoundingMode.HALF_EVEN)
        .longValue
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

// ── 4. ZIO-managed WORM store (resource-safe, append-only) ───────────────────

final class WormStore private (channel: FileChannel) {

  def append(block: WormBlock): IO[TreasuryError, Unit] =
    ZIO
      .attempt {
        val bytes = block.toBytes
        channel.write(ByteBuffer.wrap(bytes))
        channel.force(true)
      }
      .mapError(e => TreasuryError.WormIOError("append failed", Some(e)))
      .unit
}

object WormStore {
  def live(path: Path): ZIO[Scope, TreasuryError, WormStore] =
    ZIO
      .acquireRelease {
        ZIO.attempt {
          if (!Files.exists(path.getParent))
            Files.createDirectories(path.getParent)
          if (!Files.exists(path))
            Files.createFile(path)

          FileChannel.open(
            path,
            StandardOpenOption.WRITE,
            StandardOpenOption.CREATE,
            StandardOpenOption.APPEND
          )
        }.mapError(e => TreasuryError.WormIOError("open failed", Some(e)))
      } { ch =>
        ZIO.attempt(ch.close()).orDie
      }
      .map(new WormStore(_))
}

// ── 5. Pipeline stages ──────────────────────────────────────────────────────

object Pipeline {

  def buildBlock(
    entry: TreasuryEntry,
    prevHash: String
  ): IO[TreasuryError, WormBlock] =
    ZIO.attempt {
      val payload = Serializer.buildPayload(Seq(entry))
      val currHash = Crypto.chainHash(prevHash, payload)
      WormBlock(
        magic = "WORM",
        prevHash = prevHash,
        currHash = currHash,
        recordCount = 1,
        payload = payload
      )
    }.mapError(e => TreasuryError.SerializationError(e.getMessage))

  def processOne(
    entry: TreasuryEntry,
    prevHash: String
  ): ZIO[WormStore, TreasuryError, (WormBlock, String)] =
    for {
      store <- ZIO.service[WormStore]
      block <- buildBlock(entry, prevHash)
      _ <- store.append(block)
    } yield (block, block.currHash)

  def processBatch(
    entries: Seq[TreasuryEntry],
    initialHash: String
  ): ZIO[WormStore, TreasuryError, String] =
    ZIO.foldLeft(entries)(initialHash) { (prev, entry) =>
      processOne(entry, prev).map(_._2)
    }

  def processStream(
    entries: ZStream[Any, Nothing, TreasuryEntry],
    initialHash: String
  ): ZStream[WormStore, TreasuryError, String] =
    entries
      .mapAccumZIO(initialHash) { (prev, entry) =>
        processOne(entry, prev).map { case (_, newHash) =>
          (newHash, newHash)
        }
      }
}

// ── 6. Application layer ────────────────────────────────────────────────────

object SovereignTreasuryZIO extends ZIOAppDefault {

  val sampleEntry: TreasuryEntry = TreasuryEntry(
    txId = "f47ac10b-58cc-4372-a567-0e02b2c3d479",
    txTimestamp = Instant.now().toEpochMilli,
    txSequence = 500001,
    sourceAccount = "SOVEREIGN-TRES01",
    destAccount = "SETTLE-POOL-0007",
    transferAmount = BigDecimal("9876543.21"),
    currencyCode = "USD",
    complianceFlag = 0xc0.toByte
  )

  def makeBatch(base: TreasuryEntry, n: Int): Seq[TreasuryEntry] =
    (1 to n).map { i =>
      base.copy(
        txSequence = base.txSequence + i,
        transferAmount = base.transferAmount + BigDecimal(i * 1000),
        txId = f"${base.txId.take(24)}${base.txSequence + i}%012d"
      )
    }

  val program: ZIO[WormStore, TreasuryError, Unit] =
    for {
      _ <- Console.printLine("=== Sovereign Treasury Engine – ZIO WORM Pipeline ===")
             .orDie

      result <- Pipeline.processOne(sampleEntry, "0" * 64)
      (block, hash) = result

      _ <- Console.printLine(s"Magic : ${block.magic}").orDie
      _ <- Console.printLine(s"Prev Hash : ${block.prevHash.take(32)}...").orDie
      _ <- Console.printLine(s"Curr Hash : ${hash.take(32)}...").orDie
      _ <- Console.printLine(s"Record Count : ${block.recordCount}").orDie
      _ <- Console.printLine(s"TX ID : ${sampleEntry.txId}").orDie
      _ <- Console.printLine(
             s"Amount : ${sampleEntry.transferAmount} ${sampleEntry.currencyCode}"
           ).orDie
      _ <- Console.printLine("Single WORM block committed.").orDie

      batch = makeBatch(sampleEntry, 5)
      finalHash <- Pipeline.processBatch(batch, hash)
      _ <- Console.printLine(s"\nBatch of ${batch.size} records sealed.").orDie
      _ <- Console.printLine(s"Final chain hash: ${finalHash.take(32)}...").orDie

      streamHash <- Pipeline
                      .processStream(ZStream.fromIterable(makeBatch(sampleEntry, 3)), finalHash)
                      .runLast
                      .someOrFail(TreasuryError.PipelineError("empty stream"))
      _ <- Console.printLine(s"Stream final hash: ${streamHash.take(32)}...").orDie

      _ <- Console.printLine("=== Pipeline complete ===").orDie
    } yield ()

  override def run: ZIO[Any, Any, Any] = {
    val path = Paths.get("data/treasury-worm-zio.bin")

    WormStore
      .live(path)
      .flatMap(store => program.provide(ZLayer.succeed(store)))
      .catchAll { err =>
        Console.printLine(s"Pipeline failed: ${err.getMessage}").orDie
      }
  }
}
