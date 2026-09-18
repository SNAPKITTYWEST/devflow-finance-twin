/* ========================================================================
 * SOVEREIGN LEVIATHAN NODE LICENSE
 * License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
 * Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
 * ========================================================================
 *
 * This file is a covered work under the GNU Affero General Public License,
 * version 3, together with the Sovereign Leviathan additional terms.
 *
 * Hark, though this node be but a spark,
 * Its covenant endureth through the dark.
 *
 * Ignorantia juris non excusat.
 * ======================================================================== */

/*
P2 HARDWARE PARALLEL FABRIC
MIRROR / INVARIANT / CLONE / CRYSTALLIZATION
FORMAL REFERENCE IMPLEMENTATION

Virtual architecture only.
No claim of representing NVIDIA internal H100 microcode.
*/

#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <type_traits>

namespace p2
{

using u8 = std::uint8_t;
using u16 = std::uint16_t;
using u32 = std::uint32_t;
using u64 = std::uint64_t;
using i64 = std::int64_t;

static constexpr u32 LANES = 32;
static constexpr u32 REGISTERS = 256;
static constexpr u32 BANKS = 8;
static constexpr u32 ISSUE_WIDTH = 8;
static constexpr u32 BARRIERS = 32;
static constexpr u32 SHARED_WORDS = 1024;
static constexpr u32 QUEUE_SIZE = 256;
static constexpr u32 MAX_PROGRAM = 4096;

static constexpr u64 MASK32 = 0xffffffffULL;
static constexpr u64 MASK8 = 0xffULL;

enum class Opcode : u8
{
    NOP = 0x00,
    MOV = 0x01,
    LOAD = 0x02,
    STORE = 0x03,

    ADD = 0x10,
    SUB = 0x11,
    MUL = 0x12,

    AND_ = 0x20,
    OR_ = 0x21,
    XOR_ = 0x22,
    NOT_ = 0x23,

    SHL = 0x30,
    SHR = 0x31,
    ROTL = 0x32,
    ROTR = 0x33,

    CMP = 0x40,
    SELECT = 0x41,

    BROADCAST = 0x50,
    SHUFFLE = 0x51,
    PERMUTE = 0x52,

    REDUCE_ADD = 0x60,
    REDUCE_AND = 0x61,
    REDUCE_OR = 0x62,
    REDUCE_XOR = 0x63,

    BARRIER = 0x70,
    FENCE = 0x71,

    BRANCH = 0x80,
    JUMP = 0x81,

    COMMIT = 0x90,
    ROLLBACK = 0x91,

    HALT = 0xff
};

enum class Unit : u8
{
    NONE,
    ALU,
    LOGIC,
    SHIFT,
    COMPARE,
    MEMORY,
    REDUCE,
    CONTROL,
    COMMIT
};

enum class Phase : u8
{
    RESET,
    FETCH,
    DECODE,
    PREDICATE,
    ISSUE,
    EXECUTE,
    REDUCE,
    SYNCHRONIZE,
    COMMIT,
    ROLLBACK,
    HALT
};

enum class Status : u8
{
    OK,
    INVALID_OPCODE,
    INVALID_REGISTER,
    INVALID_LANE,
    INVALID_BARRIER,
    DEPENDENCY,
    MEMORY_FAULT,
    PREDICATE_FAULT,
    BARRIER_WAIT,
    HALTED,
    INVARIANT_FAILURE,
    CRYSTALLIZATION_FAILURE
};

struct Instruction
{
    u64 raw;

    constexpr Instruction(u64 value = 0)
        : raw(value)
    {
    }
};

struct Decoded
{
    Opcode opcode;
    u8 dst;
    u8 src0;
    u8 src1;
    u8 predicate;
    u32 immediate;
    u64 raw;
};

struct Lane
{
    std::array<u64, REGISTERS> committed{};
    std::array<u64, REGISTERS> speculative{};

    u64 pc = 0;
    u64 predicate = 1;
    u64 flags = 0;
    u64 active = 1;
    u64 halted = 0;

    u64 epoch = 0;
    u64 mirror_hash = 0;
};

struct Barrier
{
    u32 arrivals = 0;
    u32 generation = 0;
    bool armed = false;
};

struct Snapshot
{
    std::array<Lane, LANES> lanes{};
    std::array<u64, SHARED_WORDS> shared{};
    std::array<Barrier, BARRIERS> barriers{};

    u64 cycle = 0;
    u32 active_mask = 0;
    u32 commit_mask = 0;
    u64 epoch = 0;
};

struct Fabric
{
    std::array<Lane, LANES> lanes{};
    std::array<u64, SHARED_WORDS> shared{};
    std::array<Barrier, BARRIERS> barriers{};

    std::array<u64, QUEUE_SIZE> issue_queue{};

    std::array<u64, LANES> reduction{};
    std::array<u64, LANES> mirror{};

    u64 cycle = 0;
    u64 epoch = 0;

    u32 active_mask = 0xffffffffU;
    u32 commit_mask = 0;

    Phase phase = Phase::RESET;
    Status status = Status::OK;

    Snapshot checkpoint{};
};

static constexpr u64 rotl64(u64 x, u32 r)
{
    r &= 63U;
    return r == 0 ? x : ((x << r) | (x >> (64U - r)));
}

static constexpr u64 rotr64(u64 x, u32 r)
{
    r &= 63U;
    return r == 0 ? x : ((x >> r) | (x << (64U - r)));
}

static constexpr u64 encode(
    Opcode op,
    u8 dst,
    u8 src0,
    u8 src1,
    u8 predicate,
    u32 immediate)
{
    return
        (static_cast<u64>(op) << 56) |
        (static_cast<u64>(dst) << 48) |
        (static_cast<u64>(src0) << 40) |
        (static_cast<u64>(src1) << 32) |
        (static_cast<u64>(predicate) << 24) |
        static_cast<u64>(immediate & 0x00ffffffU);
}

static constexpr Decoded decode(u64 raw)
{
    return Decoded{
        static_cast<Opcode>((raw >> 56) & 0xff),
        static_cast<u8>((raw >> 48) & 0xff),
        static_cast<u8>((raw >> 40) & 0xff),
        static_cast<u8>((raw >> 32) & 0xff),
        static_cast<u8>((raw >> 24) & 0xff),
        static_cast<u32>(raw & 0x00ffffff),
        raw
    };
}

static constexpr bool valid_register(u32 r)
{
    return r < REGISTERS;
}

static constexpr bool valid_lane(u32 lane)
{
    return lane < LANES;
}

static constexpr bool valid_barrier(u32 barrier)
{
    return barrier < BARRIERS;
}

static constexpr Unit unit_for(Opcode op)
{
    switch (op)
    {
        case Opcode::ADD:
        case Opcode::SUB:
        case Opcode::MUL:
            return Unit::ALU;

        case Opcode::AND_:
        case Opcode::OR_:
        case Opcode::XOR_:
        case Opcode::NOT_:
            return Unit::LOGIC;

        case Opcode::SHL:
        case Opcode::SHR:
        case Opcode::ROTL:
        case Opcode::ROTR:
            return Unit::SHIFT;

        case Opcode::CMP:
        case Opcode::SELECT:
            return Unit::COMPARE;

        case Opcode::LOAD:
        case Opcode::STORE:
            return Unit::MEMORY;

        case Opcode::REDUCE_ADD:
        case Opcode::REDUCE_AND:
        case Opcode::REDUCE_OR:
        case Opcode::REDUCE_XOR:
            return Unit::REDUCE;

        case Opcode::BARRIER:
        case Opcode::FENCE:
        case Opcode::BRANCH:
        case Opcode::JUMP:
            return Unit::CONTROL;

        case Opcode::COMMIT:
        case Opcode::ROLLBACK:
        case Opcode::HALT:
            return Unit::COMMIT;

        default:
            return Unit::NONE;
    }
}

static constexpr bool writes_destination(Opcode op)
{
    switch (op)
    {
        case Opcode::NOP:
        case Opcode::STORE:
        case Opcode::BARRIER:
        case Opcode::FENCE:
        case Opcode::BRANCH:
        case Opcode::JUMP:
        case Opcode::COMMIT:
        case Opcode::ROLLBACK:
        case Opcode::HALT:
            return false;

        default:
            return true;
    }
}

static constexpr bool is_memory(Opcode op)
{
    return op == Opcode::LOAD || op == Opcode::STORE;
}

static constexpr bool is_reduction(Opcode op)
{
    return
        op == Opcode::REDUCE_ADD ||
        op == Opcode::REDUCE_AND ||
        op == Opcode::REDUCE_OR ||
        op == Opcode::REDUCE_XOR;
}

static constexpr bool is_control(Opcode op)
{
    return
        op == Opcode::BARRIER ||
        op == Opcode::FENCE ||
        op == Opcode::BRANCH ||
        op == Opcode::JUMP ||
        op == Opcode::HALT;
}

static constexpr u64 lane_mask(u32 lane)
{
    return 1ULL << (lane & 63U);
}

static u64 mirror_hash_lane(const Lane& lane)
{
    u64 h = 0x9e3779b97f4a7c15ULL;

    h ^= lane.pc + 0x517cc1b727220a95ULL;
    h = rotl64(h, 13);

    h ^= lane.predicate;
    h = rotl64(h, 17);

    h ^= lane.flags;
    h = rotl64(h, 29);

    for (u32 i = 0; i < REGISTERS; ++i)
    {
        h ^= lane.committed[i] + static_cast<u64>(i);
        h = rotl64(h, 7);
        h *= 0x100000001b3ULL;
    }

    return h;
}

static u64 mirror_hash_fabric(const Fabric& f)
{
    u64 h = 0xcbf29ce484222325ULL;

    h ^= f.cycle;
    h *= 0x100000001b3ULL;

    h ^= f.epoch;
    h *= 0x100000001b3ULL;

    h ^= f.active_mask;
    h *= 0x100000001b3ULL;

    for (u32 lane = 0; lane < LANES; ++lane)
    {
        h ^= mirror_hash_lane(f.lanes[lane]);
        h *= 0x100000001b3ULL;
    }

    for (u32 i = 0; i < SHARED_WORDS; ++i)
    {
        h ^= f.shared[i];
        h *= 0x100000001b3ULL;
    }

    return h;
}

static void fail(Fabric& f, Status s)
{
    f.status = s;
    f.phase = Phase::HALT;
}

static bool predicate_active(
    const Fabric& f,
    const Lane& lane,
    u32 lane_id,
    u8 predicate)
{
    if (!valid_lane(lane_id))
        return false;

    if (((f.active_mask >> lane_id) & 1U) == 0)
        return false;

    if (lane.active == 0 || lane.halted != 0)
        return false;

    if (predicate == 0)
        return true;

    return lane.predicate != 0;
}

static void reset_lane(Lane& lane)
{
    lane = Lane{};

    for (u32 r = 0; r < REGISTERS; ++r)
    {
        lane.committed[r] = 0;
        lane.speculative[r] = 0;
    }
}

static void reset(Fabric& f)
{
    f = Fabric{};

    for (u32 lane = 0; lane < LANES; ++lane)
        reset_lane(f.lanes[lane]);

    f.active_mask = 0xffffffffU;
    f.commit_mask = 0;
    f.phase = Phase::RESET;
    f.status = Status::OK;
    f.cycle = 0;
    f.epoch = 0;
}

static void snapshot(Fabric& f)
{
    f.checkpoint.lanes = f.lanes;
    f.checkpoint.shared = f.shared;
    f.checkpoint.barriers = f.barriers;
    f.checkpoint.cycle = f.cycle;
    f.checkpoint.active_mask = f.active_mask;
    f.checkpoint.commit_mask = f.commit_mask;
    f.checkpoint.epoch = f.epoch;
}

static void restore(Fabric& f)
{
    f.lanes = f.checkpoint.lanes;
    f.shared = f.checkpoint.shared;
    f.barriers = f.checkpoint.barriers;
    f.cycle = f.checkpoint.cycle;
    f.active_mask = f.checkpoint.active_mask;
    f.commit_mask = f.checkpoint.commit_mask;
    f.epoch = f.checkpoint.epoch;
    f.phase = Phase::ROLLBACK;
}

static bool invariant_lane_registers(const Lane& lane)
{
    for (u32 r = 0; r < REGISTERS; ++r)
    {
        if (lane.committed[r] != lane.committed[r])
            return false;

        if (lane.speculative[r] != lane.speculative[r])
            return false;
    }

    return true;
}

static bool invariant_active_mask(const Fabric& f)
{
    return (f.active_mask & ~0xffffffffU) == 0;
}

static bool invariant_lanes(const Fabric& f)
{
    for (u32 lane = 0; lane < LANES; ++lane)
    {
        if (!invariant_lane_registers(f.lanes[lane]))
            return false;

        if (f.lanes[lane].active > 1)
            return false;

        if (f.lanes[lane].halted > 1)
            return false;
    }

    return true;
}

static bool invariant_barriers(const Fabric& f)
{
    for (u32 b = 0; b < BARRIERS; ++b)
    {
        if ((f.barriers[b].arrivals & ~0xffffffffU) != 0)
            return false;
    }

    return true;
}

static bool invariant(Fabric& f)
{
    if (!invariant_active_mask(f))
    {
        fail(f, Status::INVARIANT_FAILURE);
        return false;
    }

    if (!invariant_lanes(f))
    {
        fail(f, Status::INVARIANT_FAILURE);
        return false;
    }

    if (!invariant_barriers(f))
    {
        fail(f, Status::INVARIANT_FAILURE);
        return false;
    }

    return true;
}

static void mirror(Fabric& f)
{
    for (u32 lane = 0; lane < LANES; ++lane)
        f.mirror[lane] = mirror_hash_lane(f.lanes[lane]);
}

static bool verify_mirror(const Fabric& f)
{
    for (u32 lane = 0; lane < LANES; ++lane)
    {
        if (f.mirror[lane] != mirror_hash_lane(f.lanes[lane]))
            return false;
    }

    return true;
}

static void clone_speculative(Fabric& f)
{
    for (u32 lane = 0; lane < LANES; ++lane)
    {
        f.lanes[lane].speculative =
            f.lanes[lane].committed;
    }
}

static bool verify_clone(const Fabric& f)
{
    for (u32 lane = 0; lane < LANES; ++lane)
    {
        if (f.lanes[lane].speculative !=
            f.lanes[lane].committed)
            return false;
    }

    return true;
}

static void crystallize_lane(Lane& lane)
{
    lane.committed = lane.speculative;
    lane.epoch++;
}

static void crystallize(Fabric& f)
{
    for (u32 lane = 0; lane < LANES; ++lane)
    {
        if (((f.commit_mask >> lane) & 1U) != 0)
            crystallize_lane(f.lanes[lane]);
    }

    f.epoch++;
    f.commit_mask = 0;
}

static bool verify_crystallization(
    const Snapshot& before,
    const Fabric& after)
{
    for (u32 lane = 0; lane < LANES; ++lane)
    {
        if (((after.active_mask >> lane) & 1U) == 0)
            continue;

        if (before.lanes[lane].halted != 0)
            continue;

        if (after.lanes[lane].epoch <
            before.lanes[lane].epoch)
            return false;
    }

    return true;
}

static bool check_registers(
    const Decoded& d)
{
    if (!valid_register(d.dst))
        return false;

    if (!valid_register(d.src0))
        return false;

    if (!valid_register(d.src1))
        return false;

    return true;
}

static u64& destination(
    Lane& lane,
    u8 reg)
{
    return lane.speculative[reg];
}

static const u64& source0(
    const Lane& lane,
    u8 reg)
{
    return lane.speculative[reg];
}

static const u64& source1(
    const Lane& lane,
    u8 reg)
{
    return lane.speculative[reg];
}

static void execute_alu(
    Fabric& f,
    Lane& lane,
    const Decoded& d)
{
    switch (d.opcode)
    {
        case Opcode::ADD:
            destination(lane, d.dst) =
                source0(lane, d.src0) +
                source1(lane, d.src1);
            break;

        case Opcode::SUB:
            destination(lane, d.dst) =
                source0(lane, d.src0) -
                source1(lane, d.src1);
            break;

        case Opcode::MUL:
            destination(lane, d.dst) =
                source0(lane, d.src0) *
                source1(lane, d.src1);
            break;

        default:
            fail(f, Status::INVALID_OPCODE);
            break;
    }
}

static void execute_logic(
    Fabric& f,
    Lane& lane,
    const Decoded& d)
{
    switch (d.opcode)
    {
        case Opcode::AND_:
            destination(lane, d.dst) =
                source0(lane, d.src0) &
                source1(lane, d.src1);
            break;

        case Opcode::OR_:
            destination(lane, d.dst) =
                source0(lane, d.src0) |
                source1(lane, d.src1);
            break;

        case Opcode::XOR_:
            destination(lane, d.dst) =
                source0(lane, d.src0) ^
                source1(lane, d.src1);
            break;

        case Opcode::NOT_:
            destination(lane, d.dst) =
                ~source0(lane, d.src0);
            break;

        default:
            fail(f, Status::INVALID_OPCODE);
            break;
    }
}

static void execute_shift(
    Fabric& f,
    Lane& lane,
    const Decoded& d)
{
    u32 amount =
        d.immediate & 63U;

    switch (d.opcode)
    {
        case Opcode::SHL:
            destination(lane, d.dst) =
                source0(lane, d.src0) << amount;
            break;

        case Opcode::SHR:
            destination(lane, d.dst) =
                source0(lane, d.src0) >> amount;
            break;

        case Opcode::ROTL:
            destination(lane, d.dst) =
                rotl64(
                    source0(lane, d.src0),
                    amount);
            break;

        case Opcode::ROTR:
            destination(lane, d.dst) =
                rotr64(
                    source0(lane, d.src0),
                    amount);
            break;

        default:
            fail(f, Status::INVALID_OPCODE);
            break;
    }
}

static void execute_compare(
    Fabric& f,
    Lane& lane,
    const Decoded& d)
{
    switch (d.opcode)
    {
        case Opcode::CMP:
            lane.predicate =
                source0(lane, d.src0) ==
                source1(lane, d.src1);
            destination(lane, d.dst) =
                lane.predicate;
            break;

        case Opcode::SELECT:
            destination(lane, d.dst) =
                lane.predicate
                ? source0(lane, d.src0)
                : source1(lane, d.src1);
            break;

        default:
            fail(f, Status::INVALID_OPCODE);
            break;
    }
}

static void execute_memory(
    Fabric& f,
    Lane& lane,
    const Decoded& d)
{
    u32 address =
        d.immediate % SHARED_WORDS;

    switch (d.opcode)
    {
        case Opcode::LOAD:
            destination(lane, d.dst) =
                f.shared[address];
            break;

        case Opcode::STORE:
            f.shared[address] =
                source0(lane, d.src0);
            break;

        default:
            fail(f, Status::INVALID_OPCODE);
            break;
    }
}

static void execute_broadcast(
    Fabric& f,
    const Decoded& d)
{
    u32 root =
        d.immediate & 31U;

    if (!valid_lane(root))
    {
        fail(f, Status::INVALID_LANE);
        return;
    }

    u64 value =
        f.lanes[root].speculative[d.src0];

    for (u32 lane = 0; lane < LANES; ++lane)
    {
        if (((f.active_mask >> lane) & 1U) == 0)
            continue;

        f.lanes[lane].speculative[d.dst] =
            value;
    }
}

static void execute_shuffle(
    Fabric& f,
    const Decoded& d)
{
    std::array<u64, LANES> values{};

    for (u32 lane = 0; lane < LANES; ++lane)
        values[lane] =
            f.lanes[lane].speculative[d.src0];

    for (u32 lane = 0; lane < LANES; ++lane)
    {
        if (((f.active_mask >> lane) & 1U) == 0)
            continue;

        u32 source =
            static_cast<u32>(
                f.lanes[lane].speculative[d.src1] &
                31ULL);

        f.lanes[lane].speculative[d.dst] =
            values[source];
    }
}

static void execute_permute(
    Fabric& f,
    const Decoded& d)
{
    std::array<u64, LANES> values{};

    for (u32 lane = 0; lane < LANES; ++lane)
        values[lane] =
            f.lanes[lane].speculative[d.src0];

    for (u32 lane = 0; lane < LANES; ++lane)
    {
        if (((f.active_mask >> lane) & 1U) == 0)
            continue;

        u32 source =
            static_cast<u32>(
                (lane + d.immediate) & 31U);

        f.lanes[lane].speculative[d.dst] =
            values[source];
    }
}

static void execute_reduction(
    Fabric& f,
    const Decoded& d)
{
    u64 result = 0;

    switch (d.opcode)
    {
        case Opcode::REDUCE_ADD:
            result = 0;

            for (u32 lane = 0; lane < LANES; ++lane)
            {
                if (((f.active_mask >> lane) & 1U) != 0)
                    result +=
                        f.lanes[lane].speculative[d.src0];
            }
            break;

        case Opcode::REDUCE_AND:
            result = std::numeric_limits<u64>::max();

            for (u32 lane = 0; lane < LANES; ++lane)
            {
                if (((f.active_mask >> lane) & 1U) != 0)
                    result &=
                        f.lanes[lane].speculative[d.src0];
            }
            break;

        case Opcode::REDUCE_OR:
            result = 0;

            for (u32 lane = 0; lane < LANES; ++lane)
            {
                if (((f.active_mask >> lane) & 1U) != 0)
                    result |=
                        f.lanes[lane].speculative[d.src0];
            }
            break;

        case Opcode::REDUCE_XOR:
            result = 0;

            for (u32 lane = 0; lane < LANES; ++lane)
            {
                if (((f.active_mask >> lane) & 1U) != 0)
                    result ^=
                        f.lanes[lane].speculative[d.src0];
            }
            break;

        default:
            fail(f, Status::INVALID_OPCODE);
            return;
    }

    f.reduction[0] = result;

    for (u32 lane = 0; lane < LANES; ++lane)
    {
        if (((f.active_mask >> lane) & 1U) != 0)
            f.lanes[lane].speculative[d.dst] =
                result;
    }
}

static bool barrier_ready(
    const Fabric& f,
    u32 barrier)
{
    if (!valid_barrier(barrier))
        return false;

    return f.barriers[barrier].arrivals ==
           f.active_mask;
}

static void execute_barrier(
    Fabric& f,
    u32 lane,
    const Decoded& d)
{
    u32 barrier =
        d.immediate & 31U;

    if (!valid_barrier(barrier))
    {
        fail(f, Status::INVALID_BARRIER);
        return;
    }

    f.barriers[barrier].armed = true;

    f.barriers[barrier].arrivals |=
        (1U << lane);

    if (!barrier_ready(f, barrier))
    {
        f.status = Status::BARRIER_WAIT;
        return;
    }

    f.barriers[barrier].arrivals = 0;
    f.barriers[barrier].generation++;
    f.barriers[barrier].armed = false;
    f.status = Status::OK;
}

static void execute_control(
    Fabric& f,
    u32 lane_id,
    Lane& lane,
    const Decoded& d)
{
    switch (d.opcode)
    {
        case Opcode::BARRIER:
            execute_barrier(
                f,
                lane_id,
                d);
            break;

        case Opcode::FENCE:
            break;

        case Opcode::BRANCH:
            if (lane.predicate != 0)
                lane.pc +=
                    static_cast<i64>(
                        static_cast<std::int32_t>(
                            d.immediate));
            break;

        case Opcode::JUMP:
            lane.pc =
                d.immediate;
            break;

        case Opcode::HALT:
            lane.halted = 1;
            lane.active = 0;
            f.active_mask &=
                ~(1U << lane_id);
            break;

        default:
            fail(f, Status::INVALID_OPCODE);
            break;
    }
}

static void execute_one(
    Fabric& f,
    u32 lane_id,
    u64 raw)
{
    if (!valid_lane(lane_id))
    {
        fail(f, Status::INVALID_LANE);
        return;
    }

    Decoded d = decode(raw);

    if (!check_registers(d))
    {
        fail(f, Status::INVALID_REGISTER);
        return;
    }

    Lane& lane =
        f.lanes[lane_id];

    if (!predicate_active(
            f,
            lane,
            lane_id,
            d.predicate))
        return;

    switch (unit_for(d.opcode))
    {
        case Unit::ALU:
            execute_alu(f, lane, d);
            break;

        case Unit::LOGIC:
            execute_logic(f, lane, d);
            break;

        case Unit::SHIFT:
            execute_shift(f, lane, d);
            break;

        case Unit::COMPARE:
            execute_compare(f, lane, d);
            break;

        case Unit::MEMORY:
            execute_memory(f, lane, d);
            break;

        case Unit::REDUCE:
            execute_reduction(f, d);
            break;

        case Unit::CONTROL:
            execute_control(
                f,
                lane_id,
                lane,
                d);
            break;

        case Unit::COMMIT:
            if (d.opcode == Opcode::COMMIT)
            {
                f.commit_mask =
                    f.active_mask;
            }
            else if (d.opcode == Opcode::ROLLBACK)
            {
                restore(f);
            }
            else if (d.opcode == Opcode::HALT)
            {
                lane.halted = 1;
                lane.active = 0;
            }
            else
            {
                fail(f, Status::INVALID_OPCODE);
            }
            break;

        case Unit::NONE:
        default:
            if (d.opcode != Opcode::NOP)
                fail(f, Status::INVALID_OPCODE);
            break;
    }
}

static void fetch(
    const std::array<u64, MAX_PROGRAM>& program,
    u64 pc,
    u64& instruction)
{
    if (pc >= MAX_PROGRAM)
        instruction = encode(
            Opcode::HALT,
            0,
            0,
            0,
            0,
            0);
    else
        instruction = program[
            static_cast<std::size_t>(pc)];
}

static void issue(
    Fabric& f,
    const std::array<u64, MAX_PROGRAM>& program)
{
    f.phase = Phase::FETCH;

    for (u32 lane = 0; lane < LANES; ++lane)
    {
        if (((f.active_mask >> lane) & 1U) == 0)
            continue;

        u64 raw = 0;

        fetch(
            program,
            f.lanes[lane].pc,
            raw);

        f.issue_queue[lane] = raw;
    }

    f.phase = Phase::DECODE;
}

static void execute_cycle(
    Fabric& f)
{
    f.phase = Phase::ISSUE;

    for (u32 lane = 0; lane < LANES; ++lane)
    {
        if (((f.active_mask >> lane) & 1U) == 0)
            continue;

        f.phase = Phase::EXECUTE;

        execute_one(
            f,
            lane,
            f.issue_queue[lane]);

        if (f.status == Status::HALTED)
            return;
    }

    f.phase = Phase::SYNCHRONIZE;
}

static void advance_pc(Fabric& f)
{
    for (u32 lane = 0; lane < LANES; ++lane)
    {
        if (((f.active_mask >> lane) & 1U) == 0)
            continue;

        f.lanes[lane].pc++;
    }
}

static bool all_halted(const Fabric& f)
{
    return f.active_mask == 0;
}

static void commit_cycle(Fabric& f)
{
    f.phase = Phase::COMMIT;

    if (f.commit_mask != 0)
        crystallize(f);

    advance_pc(f);
}

static void cycle(
    Fabric& f,
    const std::array<u64, MAX_PROGRAM>& program)
{
    if (f.phase == Phase::HALT)
        return;

    Snapshot before{};

    before.lanes = f.lanes;
    before.shared = f.shared;
    before.barriers = f.barriers;
    before.cycle = f.cycle;
    before.active_mask = f.active_mask;
    before.commit_mask = f.commit_mask;
    before.epoch = f.epoch;

    clone_speculative(f);

    if (!invariant(f))
        return;

    issue(f, program);

    execute_cycle(f);

    if (f.status == Status::INVARIANT_FAILURE)
        return;

    if (f.status == Status::INVALID_OPCODE)
        return;

    if (f.status == Status::INVALID_REGISTER)
        return;

    commit_cycle(f);

    f.cycle++;

    mirror(f);

    if (!verify_mirror(f))
    {
        fail(
            f,
            Status::CRYSTALLIZATION_FAILURE);
        return;
    }

    if (!verify_crystallization(
            before,
            f))
    {
        fail(
            f,
            Status::CRYSTALLIZATION_FAILURE);
        return;
    }

    if (!invariant(f))
        return;

    if (all_halted(f))
        f.phase = Phase::HALT;
}

static void initialize_program(
    std::array<u64, MAX_PROGRAM>& program)
{
    program.fill(
        encode(
            Opcode::NOP,
            0,
            0,
            0,
            0,
            0));
}

static void seed_registers(Fabric& f)
{
    for (u32 lane = 0; lane < LANES; ++lane)
    {
        f.lanes[lane].committed[0] =
            lane;

        f.lanes[lane].committed[1] =
            lane + 1;

        f.lanes[lane].committed[2] =
            static_cast<u64>(lane) *
            0x9e3779b97f4a7c15ULL;

        f.lanes[lane].speculative =
            f.lanes[lane].committed;
    }
}

static bool invariant_identity(
    const Fabric& f)
{
    for (u32 lane = 0; lane < LANES; ++lane)
    {
        if (f.lanes[lane].committed[0] != lane)
            return false;
    }

    return true;
}

static bool invariant_clone_identity(
    const Fabric& f)
{
    return verify_clone(f);
}

static bool invariant_mirror_identity(
    const Fabric& f)
{
    return verify_mirror(f);
}

static bool invariant_epoch(
    const Fabric& f)
{
    for (u32 lane = 0; lane < LANES; ++lane)
    {
        if (f.lanes[lane].epoch > f.epoch + 1)
            return false;
    }

    return true;
}

static bool invariant_state(
    Fabric& f)
{
    if (!invariant(f))
        return false;

    if (!invariant_identity(f))
        return false;

    if (!invariant_epoch(f))
        return false;

    return true;
}

static u64 state_digest(
    const Fabric& f)
{
    u64 h =
        0x6a09e667f3bcc909ULL;

    h ^= f.cycle;
    h = rotl64(h, 11);

    h ^= f.epoch;
    h = rotl64(h, 13);

    h ^= f.active_mask;
    h = rotl64(h, 17);

    for (u32 lane = 0; lane < LANES; ++lane)
    {
        h ^= f.mirror[lane];
        h = rotl64(h, 23);
    }

    for (u32 word = 0;
         word < SHARED_WORDS;
         ++word)
    {
        h ^= f.shared[word];
        h = rotl64(h, 7);
    }

    return h;
}

static void crystallize_digest(
    Fabric& f)
{
    u64 digest =
        state_digest(f);

    f.shared[SHARED_WORDS - 1] =
        digest;
}

static bool verify_digest(
    const Fabric& f)
{
    Fabric copy = f;

    copy.shared[
        SHARED_WORDS - 1] = 0;

    return true;
}

static void mirror_commit(
    Fabric& f)
{
    mirror(f);
    crystallize_digest(f);
}

static void execute_program(
    Fabric& f,
    const std::array<u64, MAX_PROGRAM>& program,
    u64 max_cycles)
{
    snapshot(f);

    for (u64 cycle_id = 0;
         cycle_id < max_cycles;
         ++cycle_id)
    {
        if (f.phase == Phase::HALT)
            break;

        cycle(f, program);

        if (f.status != Status::OK &&
            f.status != Status::BARRIER_WAIT)
            break;

        if (f.status == Status::BARRIER_WAIT)
            f.status = Status::OK;

        mirror_commit(f);

        if (!invariant_state(f))
            break;
    }
}

static void construct_mirror_clone(
    Fabric& source,
    Fabric& target)
{
    target = source;

    mirror(target);

    if (!verify_mirror(target))
    {
        fail(
            target,
            Status::CRYSTALLIZATION_FAILURE);
        return;
    }
}

static bool exact_clone(
    const Fabric& a,
    const Fabric& b)
{
    if (a.cycle != b.cycle)
        return false;

    if (a.epoch != b.epoch)
        return false;

    if (a.active_mask != b.active_mask)
        return false;

    if (a.commit_mask != b.commit_mask)
        return false;

    if (a.shared != b.shared)
        return false;

    if (a.mirror != b.mirror)
        return false;

    for (u32 lane = 0; lane < LANES; ++lane)
    {
        if (a.lanes[lane].committed !=
            b.lanes[lane].committed)
            return false;

        if (a.lanes[lane].speculative !=
            b.lanes[lane].speculative)
            return false;

        if (a.lanes[lane].pc !=
            b.lanes[lane].pc)
            return false;
    }

    return true;
}

static void execute_parallel(
    Fabric& f,
    const std::array<u64, MAX_PROGRAM>& program,
    u64 max_cycles)
{
    f.phase = Phase::FETCH;

    execute_program(
        f,
        program,
        max_cycles);

    mirror_commit(f);
}

static std::array<u64, MAX_PROGRAM>
build_reference_program()
{
    std::array<u64, MAX_PROGRAM> p{};

    initialize_program(p);

    p[0] = encode(
        Opcode::ADD,
        3,
        0,
        1,
        0,
        0);

    p[1] = encode(
        Opcode::XOR_,
        4,
        3,
        2,
        0,
        0);

    p[2] = encode(
        Opcode::ROTL,
        5,
        4,
        0,
        0,
        13);

    p[3] = encode(
        Opcode::REDUCE_XOR,
        6,
        5,
        0,
        0,
        0);

    p[4] = encode(
        Opcode::STORE,
        0,
        6,
        0,
        0,
        0);

    p[5] = encode(
        Opcode::COMMIT,
        0,
        0,
        0,
        0,
        0);

    p[6] = encode(
        Opcode::BARRIER,
        0,
        0,
        0,
        0,
        0);

    p[7] = encode(
        Opcode::HALT,
        0,
        0,
        0,
        0,
        0);

    return p;
}

static bool verify_reference(
    const Fabric& f)
{
    if (!invariant(f))
        return false;

    if (!verify_mirror(f))
        return false;

    if (!invariant_mirror_identity(f))
        return false;

    return true;
}

static bool run_clone_verification()
{
    Fabric source{};
    Fabric clone{};

    reset(source);
    reset(clone);

    seed_registers(source);
    seed_registers(clone);

    mirror(source);
    mirror(clone);

    if (!exact_clone(source, clone))
        return false;

    if (!invariant_clone_identity(source))
        return false;

    return true;
}

static bool run_mirror_verification()
{
    Fabric f{};

    reset(f);
    seed_registers(f);
    mirror(f);

    return
        invariant(f) &&
        verify_mirror(f);
}

static bool run_crystallization_verification()
{
    Fabric f{};

    reset(f);
    seed_registers(f);

    snapshot(f);
    clone_speculative(f);

    for (u32 lane = 0; lane < LANES; ++lane)
        f.lanes[lane].speculative[7] =
            static_cast<u64>(lane) *
            17ULL;

    f.commit_mask =
        f.active_mask;

    crystallize(f);

    for (u32 lane = 0; lane < LANES; ++lane)
    {
        if (f.lanes[lane].committed[7] !=
            static_cast<u64>(lane) * 17ULL)
            return false;
    }

    return true;
}

static bool run_rollback_verification()
{
    Fabric f{};

    reset(f);
    seed_registers(f);

    snapshot(f);

    u64 before =
        f.lanes[0].committed[0];

    f.lanes[0].speculative[0] =
        0xffffffffffffffffULL;

    restore(f);

    return
        f.lanes[0].committed[0] ==
        before;
}

static bool run_reduction_verification()
{
    Fabric f{};

    reset(f);
    seed_registers(f);

    clone_speculative(f);

    Decoded d = decode(
        encode(
            Opcode::REDUCE_ADD,
            10,
            0,
            0,
            0,
            0));

    execute_reduction(
        f,
        d);

    u64 expected = 0;

    for (u32 lane = 0;
         lane < LANES;
         ++lane)
        expected += lane;

    return f.reduction[0] == expected;
}

static bool run_broadcast_verification()
{
    Fabric f{};

    reset(f);
    seed_registers(f);

    clone_speculative(f);

    Decoded d = decode(
        encode(
            Opcode::BROADCAST,
            9,
            0,
            0,
            0,
            7));

    execute_broadcast(
        f,
        d);

    for (u32 lane = 0;
         lane < LANES;
         ++lane)
    {
        if (f.lanes[lane].speculative[9] != 7)
            return false;
    }

    return true;
}

static bool run_shuffle_verification()
{
    Fabric f{};

    reset(f);
    seed_registers(f);

    clone_speculative(f);

    for (u32 lane = 0;
         lane < LANES;
         ++lane)
    {
        f.lanes[lane].speculative[8] =
            (31U - lane);
    }

    Decoded d = decode(
        encode(
            Opcode::SHUFFLE,
            9,
            0,
            8,
            0,
            0));

    execute_shuffle(
        f,
        d);

    for (u32 lane = 0;
         lane < LANES;
         ++lane)
    {
        u32 expected =
            31U - lane;

        if (f.lanes[lane].speculative[9] !=
            f.lanes[expected].speculative[0])
            return false;
    }

    return true;
}

static bool run_all_verification()
{
    if (!run_clone_verification())
        return false;

    if (!run_mirror_verification())
        return false;

    if (!run_crystallization_verification())
        return false;

    if (!run_rollback_verification())
        return false;

    if (!run_reduction_verification())
        return false;

    if (!run_broadcast_verification())
        return false;

    if (!run_shuffle_verification())
        return false;

    return true;
}

} // namespace p2

int main()
{
    using namespace p2;

    if (!run_all_verification())
        return 1;

    Fabric fabric{};

    reset(fabric);
    seed_registers(fabric);

    auto program =
        build_reference_program();

    execute_parallel(
        fabric,
        program,
        64);

    if (!verify_reference(fabric))
        return 2;

    Fabric mirror_clone{};

    construct_mirror_clone(
        fabric,
        mirror_clone);

    if (!exact_clone(
            fabric,
            mirror_clone))
        return 3;

    return 0;
}
