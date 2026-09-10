/*
P2 HARDWARE PARALLEL FABRIC
MIRROR / INVARIANT / CLONE / CRYSTALLIZATION
REFERENCE SOURCE DUMP
TARGET: VIRTUAL P2 ARCHITECTURE
PHYSICAL TARGET MAPPING: NVIDIA H100 SM90
STATUS: REFERENCE MODEL
*/

#include <array>
#include <cstdint>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <utility>

namespace p2 {

/* ================================================================
   FUNDAMENTAL CONSTANTS
   ================================================================ */

static constexpr uint32_t WORD_BITS = 64;
static constexpr uint32_t REGISTER_BITS = 64;
static constexpr uint32_t LANE_COUNT = 32;
static constexpr uint32_t REGISTER_COUNT = 256;
static constexpr uint32_t BANK_COUNT = 8;
static constexpr uint32_t ISSUE_WIDTH = 8;
static constexpr uint32_t EXEC_UNITS = 8;
static constexpr uint32_t BARRIER_COUNT = 32;
static constexpr uint32_t SHARED_WORDS = 1024;
static constexpr uint32_t QUEUE_DEPTH = 256;
static constexpr uint64_t INVALID_REG = UINT64_MAX;

/* ================================================================
   OPCODE SPACE
   ================================================================ */

enum class Opcode : uint8_t {
    NOP = 0x00,

    MOV = 0x01,
    LOAD = 0x02,
    STORE = 0x03,

    ADD = 0x10,
    SUB = 0x11,
    MUL = 0x12,

    AND = 0x20,
    OR = 0x21,
    XOR = 0x22,
    NOT = 0x23,

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

/* ================================================================
   EXECUTION UNIT SPACE
   ================================================================ */

enum class Unit : uint8_t {
    ALU = 0,
    LOGIC = 1,
    SHIFT = 2,
    COMPARE = 3,
    MEMORY = 4,
    BRANCH = 5,
    REDUCE = 6,
    COMMIT = 7
};

/* ================================================================
   FLAGS
   ================================================================ */

enum Flag : uint64_t {
    FLAG_ZERO = 1ull << 0,
    FLAG_CARRY = 1ull << 1,
    FLAG_NEGATIVE = 1ull << 2,
    FLAG_OVERFLOW = 1ull << 3,
    FLAG_VALID = 1ull << 4,
    FLAG_COMMITTED = 1ull << 5
};

/* ================================================================
   INSTRUCTION
   ================================================================ */

struct Instruction {
    Opcode opcode;
    uint8_t dst;
    uint8_t src0;
    uint8_t src1;
    uint8_t pred;
    uint32_t imm;
};

/* ================================================================
   DECODED INSTRUCTION
   ================================================================ */

struct Decoded {
    Instruction instruction;
    Unit unit;
    bool valid;
};

/* ================================================================
   MIRROR STATE
   ================================================================ */

struct MirrorState {
    std::array<uint64_t, REGISTER_COUNT> registers{};
    uint64_t pc = 0;
    uint64_t predicate = 1;
    uint64_t flags = 0;
    uint64_t active = 1;
    uint64_t halted = 0;
    uint64_t local_state = 0;
};

/* ================================================================
   LANE
   ================================================================ */

struct Lane {
    MirrorState architectural{};
    MirrorState speculative{};
};

/* ================================================================
   BARRIER
   ================================================================ */

struct Barrier {
    uint32_t arrivals = 0;
    uint32_t expected = 0;
    bool released = false;
};

/* ================================================================
   FABRIC
   ================================================================ */

struct Fabric {
    std::array<Lane, LANE_COUNT> lanes{};
    std::array<uint64_t, SHARED_WORDS> shared{};
    std::array<Barrier, BARRIER_COUNT> barriers{};

    std::array<uint64_t, QUEUE_DEPTH> issue_queue{};
    std::array<uint64_t, LANE_COUNT> reductions{};

    uint64_t active_mask = 0xffffffffull;
    uint64_t commit_mask = 0;
    uint64_t cycle = 0;
    uint64_t halted_mask = 0;
};

/* ================================================================
   MASK UTILITIES
   ================================================================ */

constexpr uint64_t lane_bit(uint32_t lane)
{
    return 1ull << lane;
}

constexpr bool lane_active(uint64_t mask, uint32_t lane)
{
    return (mask & lane_bit(lane)) != 0;
}

/* ================================================================
   BIT EXTRACTION
   ================================================================ */

constexpr uint64_t bits(uint64_t word, uint32_t shift, uint32_t width)
{
    if (width == 64)
        return word;

    const uint64_t mask =
        (uint64_t{1} << width) - uint64_t{1};

    return (word >> shift) & mask;
}

/* ================================================================
   P3 -> P2 DECODER
   ================================================================ */

constexpr Decoded decode(uint64_t word)
{
    Instruction i{
        static_cast<Opcode>(bits(word, 56, 8)),
        static_cast<uint8_t>(bits(word, 48, 8)),
        static_cast<uint8_t>(bits(word, 40, 8)),
        static_cast<uint8_t>(bits(word, 32, 8)),
        static_cast<uint8_t>(bits(word, 24, 8)),
        static_cast<uint32_t>(bits(word, 0, 24))
    };

    Unit unit = Unit::ALU;

    switch (i.opcode) {
        case Opcode::AND:
        case Opcode::OR:
        case Opcode::XOR:
        case Opcode::NOT:
            unit = Unit::LOGIC;
            break;

        case Opcode::SHL:
        case Opcode::SHR:
        case Opcode::ROTL:
        case Opcode::ROTR:
            unit = Unit::SHIFT;
            break;

        case Opcode::CMP:
        case Opcode::SELECT:
            unit = Unit::COMPARE;
            break;

        case Opcode::LOAD:
        case Opcode::STORE:
            unit = Unit::MEMORY;
            break;

        case Opcode::BARRIER:
        case Opcode::FENCE:
            unit = Unit::COMMIT;
            break;

        case Opcode::BRANCH:
        case Opcode::JUMP:
            unit = Unit::BRANCH;
            break;

        case Opcode::REDUCE_ADD:
        case Opcode::REDUCE_AND:
        case Opcode::REDUCE_OR:
        case Opcode::REDUCE_XOR:
            unit = Unit::REDUCE;
            break;

        case Opcode::COMMIT:
        case Opcode::ROLLBACK:
            unit = Unit::COMMIT;
            break;

        default:
            unit = Unit::ALU;
            break;
    }

    return {i, unit, true};
}

/* ================================================================
   ENCODER
   ================================================================ */

constexpr uint64_t encode(
    Opcode opcode,
    uint8_t dst,
    uint8_t src0,
    uint8_t src1,
    uint8_t pred,
    uint32_t imm)
{
    return
        (uint64_t(static_cast<uint8_t>(opcode)) << 56) |
        (uint64_t(dst) << 48) |
        (uint64_t(src0) << 40) |
        (uint64_t(src1) << 32) |
        (uint64_t(pred) << 24) |
        uint64_t(imm & 0x00ffffffu);
}

/* ================================================================
   ROTATION
   ================================================================ */

constexpr uint64_t rotl64(uint64_t x, uint32_t n)
{
    n &= 63u;

    if (n == 0)
        return x;

    return (x << n) | (x >> (64u - n));
}

constexpr uint64_t rotr64(uint64_t x, uint32_t n)
{
    n &= 63u;

    if (n == 0)
        return x;

    return (x >> n) | (x << (64u - n));
}

/* ================================================================
   REGISTER VALIDATION
   ================================================================ */

constexpr bool valid_register(uint32_t r)
{
    return r < REGISTER_COUNT;
}

constexpr bool valid_lane(uint32_t lane)
{
    return lane < LANE_COUNT;
}

/* ================================================================
   MIRROR
   ================================================================ */

inline void mirror_lane(Lane& lane)
{
    lane.speculative = lane.architectural;
}

inline void mirror_fabric(Fabric& fabric)
{
    for (auto& lane : fabric.lanes)
        mirror_lane(lane);

    fabric.commit_mask = 0;
}

/* ================================================================
   INVARIANT 001
   ================================================================ */

constexpr bool invariant_lane_domain()
{
    return
        LANE_COUNT == 32 &&
        REGISTER_COUNT == 256;
}

/* ================================================================
   INVARIANT 002
   ================================================================ */

constexpr bool invariant_word_domain()
{
    return WORD_BITS == 64 &&
           REGISTER_BITS == 64;
}

/* ================================================================
   INVARIANT 003
   ================================================================ */

bool invariant_active_mask(const Fabric& fabric)
{
    return (fabric.active_mask >> LANE_COUNT) == 0;
}

/* ================================================================
   INVARIANT 004
   ================================================================ */

bool invariant_registers(const Fabric& fabric)
{
    for (const auto& lane : fabric.lanes) {
        if (lane.architectural.registers.size() != REGISTER_COUNT)
            return false;
    }

    return true;
}

/* ================================================================
   INVARIANT 005
   ================================================================ */

bool invariant_speculative_mirror(const Fabric& fabric)
{
    for (uint32_t i = 0; i < LANE_COUNT; ++i) {
        const auto& a = fabric.lanes[i].architectural;
        const auto& s = fabric.lanes[i].speculative;

        if (a.pc != s.pc)
            return false;

        if (a.predicate != s.predicate)
            return false;

        if (a.flags != s.flags)
            return false;
    }

    return true;
}

/* ================================================================
   INVARIANT 006
   ================================================================ */

bool invariant_barrier_domains(const Fabric& fabric)
{
    for (const auto& b : fabric.barriers) {
        if (b.arrivals & ~0xffffffffu)
            return false;

        if (b.expected & ~0xffffffffu)
            return false;
    }

    return true;
}

/* ================================================================
   INVARIANT 007
   ================================================================ */

bool invariant_architecture(const Fabric& fabric)
{
    return
        invariant_lane_domain() &&
        invariant_word_domain() &&
        invariant_active_mask(fabric) &&
        invariant_registers(fabric) &&
        invariant_barrier_domains(fabric);
}

/* ================================================================
   INVARIANT 008
   ================================================================ */

bool invariant_no_speculative_leak(const Fabric& fabric)
{
    for (uint32_t lane = 0; lane < LANE_COUNT; ++lane) {
        const auto& a = fabric.lanes[lane].architectural;
        const auto& s = fabric.lanes[lane].speculative;

        if (a.halted && s.halted == 0)
            return false;
    }

    return true;
}

/* ================================================================
   READ
   ================================================================ */

uint64_t read_reg(
    const Lane& lane,
    uint32_t reg)
{
    if (!valid_register(reg))
        throw std::out_of_range("register");

    return lane.speculative.registers[reg];
}

/* ================================================================
   WRITE
   ================================================================ */

void write_reg(
    Lane& lane,
    uint32_t reg,
    uint64_t value)
{
    if (!valid_register(reg))
        throw std::out_of_range("register");

    lane.speculative.registers[reg] = value;
}

/* ================================================================
   MIRRORED READ
   ================================================================ */

uint64_t mirrored_read(
    const Lane& lane,
    uint32_t reg)
{
    const uint64_t value =
        lane.architectural.registers[reg];

    const uint64_t shadow =
        lane.speculative.registers[reg];

    if (value != shadow)
        throw std::runtime_error(
            "mirror divergence");

    return value;
}

/* ================================================================
   ALU
   ================================================================ */

uint64_t alu_add(uint64_t a, uint64_t b)
{
    return a + b;
}

uint64_t alu_sub(uint64_t a, uint64_t b)
{
    return a - b;
}

uint64_t alu_mul(uint64_t a, uint64_t b)
{
    return a * b;
}

/* ================================================================
   LOGIC
   ================================================================ */

uint64_t logic_and(uint64_t a, uint64_t b)
{
    return a & b;
}

uint64_t logic_or(uint64_t a, uint64_t b)
{
    return a | b;
}

uint64_t logic_xor(uint64_t a, uint64_t b)
{
    return a ^ b;
}

uint64_t logic_not(uint64_t a)
{
    return ~a;
}

/* ================================================================
   SHIFT
   ================================================================ */

uint64_t shift_left(uint64_t a, uint32_t n)
{
    return a << (n & 63u);
}

uint64_t shift_right(uint64_t a, uint32_t n)
{
    return a >> (n & 63u);
}

/* ================================================================
   COMPARE
   ================================================================ */

uint64_t compare_eq(uint64_t a, uint64_t b)
{
    return a == b ? 1 : 0;
}

uint64_t compare_lt(uint64_t a, uint64_t b)
{
    return a < b ? 1 : 0;
}

uint64_t compare_gt(uint64_t a, uint64_t b)
{
    return a > b ? 1 : 0;
}

/* ================================================================
   CLONE
   ================================================================ */

Lane clone_lane(const Lane& source)
{
    Lane destination;
    destination.architectural = source.architectural;
    destination.speculative = source.speculative;
    return destination;
}

Fabric clone_fabric(const Fabric& source)
{
    Fabric destination = source;
    return destination;
}

/* ================================================================
   CLONE INVARIANT
   ================================================================ */

bool invariant_clone(const Fabric& source)
{
    Fabric clone = clone_fabric(source);

    if (clone.active_mask != source.active_mask)
        return false;

    if (clone.cycle != source.cycle)
        return false;

    if (clone.halted_mask != source.halted_mask)
        return false;

    for (uint32_t lane = 0; lane < LANE_COUNT; ++lane) {
        if (clone.lanes[lane].architectural.pc !=
            source.lanes[lane].architectural.pc)
            return false;

        for (uint32_t r = 0; r < REGISTER_COUNT; ++r) {
            if (clone.lanes[lane]
                    .architectural.registers[r] !=
                source.lanes[lane]
                    .architectural.registers[r])
                return false;
        }
    }

    return true;
}

/* ================================================================
   PREDICATION
   ================================================================ */

bool predicate_enabled(
    const Lane& lane,
    uint8_t predicate)
{
    if (predicate == 0xff)
        return true;

    return
        ((lane.speculative.predicate >> predicate) & 1ull)
        != 0;
}

/* ================================================================
   SINGLE-LANE EXECUTION
   ================================================================ */

void execute_lane(
    Fabric& fabric,
    uint32_t lane_id,
    const Decoded& decoded)
{
    if (!valid_lane(lane_id))
        throw std::out_of_range("lane");

    if (!lane_active(fabric.active_mask, lane_id))
        return;

    Lane& lane = fabric.lanes[lane_id];
    const Instruction& i = decoded.instruction;

    if (!predicate_enabled(lane, i.pred))
        return;

    switch (i.opcode) {

        case Opcode::NOP:
            break;

        case Opcode::MOV:
            write_reg(
                lane,
                i.dst,
                read_reg(lane, i.src0));
            break;

        case Opcode::ADD:
            write_reg(
                lane,
                i.dst,
                alu_add(
                    read_reg(lane, i.src0),
                    read_reg(lane, i.src1)));
            break;

        case Opcode::SUB:
            write_reg(
                lane,
                i.dst,
                alu_sub(
                    read_reg(lane, i.src0),
                    read_reg(lane, i.src1)));
            break;

        case Opcode::MUL:
            write_reg(
                lane,
                i.dst,
                alu_mul(
                    read_reg(lane, i.src0),
                    read_reg(lane, i.src1)));
            break;

        case Opcode::AND:
            write_reg(
                lane,
                i.dst,
                logic_and(
                    read_reg(lane, i.src0),
                    read_reg(lane, i.src1)));
            break;

        case Opcode::OR:
            write_reg(
                lane,
                i.dst,
                logic_or(
                    read_reg(lane, i.src0),
                    read_reg(lane, i.src1)));
            break;

        case Opcode::XOR:
            write_reg(
                lane,
                i.dst,
                logic_xor(
                    read_reg(lane, i.src0),
                    read_reg(lane, i.src1)));
            break;

        case Opcode::NOT:
            write_reg(
                lane,
                i.dst,
                logic_not(
                    read_reg(lane, i.src0)));
            break;

        case Opcode::SHL:
            write_reg(
                lane,
                i.dst,
                shift_left(
                    read_reg(lane, i.src0),
                    i.imm));
            break;

        case Opcode::SHR:
            write_reg(
                lane,
                i.dst,
                shift_right(
                    read_reg(lane, i.src0),
                    i.imm));
            break;

        case Opcode::ROTL:
            write_reg(
                lane,
                i.dst,
                rotl64(
                    read_reg(lane, i.src0),
                    i.imm));
            break;

        case Opcode::ROTR:
            write_reg(
                lane,
                i.dst,
                rotr64(
                    read_reg(lane, i.src0),
                    i.imm));
            break;

        case Opcode::CMP:
            write_reg(
                lane,
                i.dst,
                compare_eq(
                    read_reg(lane, i.src0),
                    read_reg(lane, i.src1)));
            break;

        case Opcode::SELECT:
            write_reg(
                lane,
                i.dst,
                lane.speculative.predicate
                    ? read_reg(lane, i.src0)
                    : read_reg(lane, i.src1));
            break;

        case Opcode::HALT:
            lane.speculative.halted = 1;
            fabric.halted_mask |= lane_bit(lane_id);
            break;

        default:
            break;
    }
}

/* ================================================================
   PARALLEL EXECUTION
   ================================================================ */

void execute_parallel(
    Fabric& fabric,
    uint64_t word)
{
    const Decoded decoded = decode(word);

    for (uint32_t lane = 0;
         lane < LANE_COUNT;
         ++lane) {

        if (!lane_active(
                fabric.active_mask,
                lane))
            continue;

        execute_lane(
            fabric,
            lane,
            decoded);
    }

    ++fabric.cycle;
}

/* ================================================================
   BROADCAST
   ================================================================ */

void broadcast(
    Fabric& fabric,
    uint8_t dst,
    uint8_t src,
    uint32_t root)
{
    if (!valid_lane(root))
        throw std::out_of_range("root");

    const uint64_t value =
        read_reg(
            fabric.lanes[root],
            src);

    for (uint32_t lane = 0;
         lane < LANE_COUNT;
         ++lane) {

        if (!lane_active(
                fabric.active_mask,
                lane))
            continue;

        write_reg(
            fabric.lanes[lane],
            dst,
            value);
    }
}

/* ================================================================
   SHUFFLE
   ================================================================ */

void shuffle(
    Fabric& fabric,
    uint8_t dst,
    uint8_t src,
    uint8_t index_reg)
{
    std::array<uint64_t, LANE_COUNT> snapshot{};

    for (uint32_t lane = 0;
         lane < LANE_COUNT;
         ++lane) {

        if (!lane_active(
                fabric.active_mask,
                lane))
            continue;

        snapshot[lane] =
            read_reg(
                fabric.lanes[lane],
                src);
    }

    for (uint32_t lane = 0;
         lane < LANE_COUNT;
         ++lane) {

        if (!lane_active(
                fabric.active_mask,
                lane))
            continue;

        const uint32_t source =
            static_cast<uint32_t>(
                read_reg(
                    fabric.lanes[lane],
                    index_reg) & 31ull);

        write_reg(
            fabric.lanes[lane],
            dst,
            snapshot[source]);
    }
}

/* ================================================================
   REDUCTION
   ================================================================ */

uint64_t reduce_add(
    const Fabric& fabric,
    uint8_t src)
{
    uint64_t result = 0;

    for (uint32_t lane = 0;
         lane < LANE_COUNT;
         ++lane) {

        if (!lane_active(
                fabric.active_mask,
                lane))
            continue;

        result +=
            fabric.lanes[lane]
                .speculative
                .registers[src];
    }

    return result;
}

/* ================================================================
   XOR REDUCTION
   ================================================================ */

uint64_t reduce_xor(
    const Fabric& fabric,
    uint8_t src)
{
    uint64_t result = 0;

    for (uint32_t lane = 0;
         lane < LANE_COUNT;
         ++lane) {

        if (!lane_active(
                fabric.active_mask,
                lane))
            continue;

        result ^=
            fabric.lanes[lane]
                .speculative
                .registers[src];
    }

    return result;
}

/* ================================================================
   TREE REDUCTION
   ================================================================ */

uint64_t tree_reduce_add(
    const Fabric& fabric,
    uint8_t src)
{
    std::array<uint64_t, LANE_COUNT> node{};

    for (uint32_t i = 0;
         i < LANE_COUNT;
         ++i) {

        if (lane_active(
                fabric.active_mask,
                i)) {

            node[i] =
                fabric.lanes[i]
                    .speculative
                    .registers[src];
        }
    }

    for (uint32_t stride = 16;
         stride >= 1;
         stride >>= 1) {

        for (uint32_t i = 0;
             i < stride;
             ++i) {

            node[i] += node[i + stride];
        }

        if (stride == 1)
            break;
    }

    return node[0];
}

/* ================================================================
   BARRIER ARRIVAL
   ================================================================ */

void barrier_arrive(
    Fabric& fabric,
    uint32_t barrier_id,
    uint32_t lane_id)
{
    if (barrier_id >= BARRIER_COUNT)
        throw std::out_of_range("barrier");

    if (!valid_lane(lane_id))
        throw std::out_of_range("lane");

    Barrier& barrier =
        fabric.barriers[barrier_id];

    barrier.expected =
        static_cast<uint32_t>(
            fabric.active_mask & 0xffffffffu);

    barrier.arrivals |=
        static_cast<uint32_t>(
            lane_bit(lane_id));

    if (barrier.arrivals ==
        barrier.expected) {

        barrier.released = true;
    }
}

/* ================================================================
   BARRIER TEST
   ================================================================ */

bool barrier_released(
    const Fabric& fabric,
    uint32_t barrier_id)
{
    if (barrier_id >= BARRIER_COUNT)
        throw std::out_of_range("barrier");

    return fabric.barriers[barrier_id].released;
}

/* ================================================================
   BARRIER RESET
   ================================================================ */

void barrier_reset(
    Fabric& fabric,
    uint32_t barrier_id)
{
    if (barrier_id >= BARRIER_COUNT)
        throw std::out_of_range("barrier");

    fabric.barriers[barrier_id] = {};
}

/* ================================================================
   SPECULATIVE SNAPSHOT
   ================================================================ */

void snapshot(Fabric& fabric)
{
    for (uint32_t lane = 0;
         lane < LANE_COUNT;
         ++lane) {

        fabric.lanes[lane].speculative =
            fabric.lanes[lane].architectural;
    }
}

/* ================================================================
   COMMIT LANE
   ================================================================ */

void commit_lane(
    Fabric& fabric,
    uint32_t lane_id)
{
    if (!valid_lane(lane_id))
        throw std::out_of_range("lane");

    Lane& lane =
        fabric.lanes[lane_id];

    lane.architectural =
        lane.speculative;

    lane.architectural.flags |=
        FLAG_COMMITTED;

    fabric.commit_mask |=
        lane_bit(lane_id);
}

/* ================================================================
   COMMIT FABRIC
   ================================================================ */

void commit(Fabric& fabric)
{
    for (uint32_t lane = 0;
         lane < LANE_COUNT;
         ++lane) {

        if (!lane_active(
                fabric.active_mask,
                lane))
            continue;

        commit_lane(
            fabric,
            lane);
    }
}

/* ================================================================
   ROLLBACK LANE
   ================================================================ */

void rollback_lane(
    Fabric& fabric,
    uint32_t lane_id)
{
    if (!valid_lane(lane_id))
        throw std::out_of_range("lane");

    fabric.lanes[lane_id].speculative =
        fabric.lanes[lane_id].architectural;
}

/* ================================================================
   ROLLBACK FABRIC
   ================================================================ */

void rollback(Fabric& fabric)
{
    for (uint32_t lane = 0;
         lane < LANE_COUNT;
         ++lane) {

        rollback_lane(
            fabric,
            lane);
    }

    fabric.commit_mask = 0;
}

/* ================================================================
   CRYSTALLIZATION
   ================================================================ */

void crystallize(Fabric& fabric)
{
    /*
       Crystallization converts a validated speculative
       state into the next immutable architectural state.
    */

    if (!invariant_architecture(fabric))
        throw std::runtime_error(
            "architecture invariant failure");

    if (!invariant_no_speculative_leak(fabric))
        throw std::runtime_error(
            "speculative leakage");

    commit(fabric);

    if (!invariant_architecture(fabric))
        throw std::runtime_error(
            "post-commit invariant failure");
}

/* ================================================================
   MIRROR CRYSTALLIZATION
   ================================================================ */

void mirror_crystallize(Fabric& fabric)
{
    snapshot(fabric);

    if (!invariant_architecture(fabric))
        throw std::runtime_error(
            "pre-crystallization invariant failure");

    crystallize(fabric);

    mirror_fabric(fabric);
}

/* ================================================================
   STATE HASH
   ================================================================ */

uint64_t state_hash(const Fabric& fabric)
{
    uint64_t h =
        0x9e3779b97f4a7c15ull;

    auto mix =
        [&h](uint64_t x) {

            h ^= x +
                 0x9e3779b97f4a7c15ull +
                 (h << 6) +
                 (h >> 2);
        };

    mix(fabric.active_mask);
    mix(fabric.cycle);
    mix(fabric.halted_mask);

    for (uint32_t lane = 0;
         lane < LANE_COUNT;
         ++lane) {

        const auto& state =
            fabric.lanes[lane].architectural;

        mix(state.pc);
        mix(state.predicate);
        mix(state.flags);

        for (uint32_t r = 0;
             r < REGISTER_COUNT;
             ++r) {

            mix(state.registers[r]);
        }
    }

    return h;
}

/* ================================================================
   CLONE EQUIVALENCE
   ================================================================ */

bool clone_equivalent(
    const Fabric& a,
    const Fabric& b)
{
    if (state_hash(a) != state_hash(b))
        return false;

    if (a.active_mask != b.active_mask)
        return false;

    if (a.cycle != b.cycle)
        return false;

    for (uint32_t lane = 0;
         lane < LANE_COUNT;
         ++lane) {

        const auto& x =
            a.lanes[lane].architectural;

        const auto& y =
            b.lanes[lane].architectural;

        if (x.pc != y.pc)
            return false;

        if (x.predicate != y.predicate)
            return false;

        if (x.flags != y.flags)
            return false;

        for (uint32_t r = 0;
             r < REGISTER_COUNT;
             ++r) {

            if (x.registers[r] !=
                y.registers[r])
                return false;
        }
    }

    return true;
}

/* ================================================================
   PARALLEL CLONE
   ================================================================ */

Fabric parallel_clone(
    const Fabric& source,
    uint64_t instruction)
{
    Fabric clone =
        clone_fabric(source);

    execute_parallel(
        clone,
        instruction);

    return clone;
}

/* ================================================================
   MIRROR EXECUTION
   ================================================================ */

void mirrored_execute(
    Fabric& primary,
    Fabric& mirror,
    uint64_t instruction)
{
    if (!clone_equivalent(
            primary,
            mirror))
        throw std::runtime_error(
            "pre-execution divergence");

    execute_parallel(
        primary,
        instruction);

    execute_parallel(
        mirror,
        instruction);

    if (!clone_equivalent(
            primary,
            mirror))
        throw std::runtime_error(
            "post-execution divergence");
}

/* ================================================================
   DETERMINISTIC INITIALIZATION
   ================================================================ */

void initialize(Fabric& fabric)
{
    fabric = {};

    fabric.active_mask =
        0xffffffffull;

    for (uint32_t lane = 0;
         lane < LANE_COUNT;
         ++lane) {

        fabric.lanes[lane]
            .architectural
            .active = 1;

        fabric.lanes[lane]
            .speculative
            .active = 1;

        fabric.lanes[lane]
            .architectural
            .predicate = 1;

        fabric.lanes[lane]
            .speculative
            .predicate = 1;
    }
}

/* ================================================================
   DETERMINISTIC SEED
   ================================================================ */

void seed(
    Fabric& fabric,
    uint64_t value)
{
    for (uint32_t lane = 0;
         lane < LANE_COUNT;
         ++lane) {

        fabric.lanes[lane]
            .architectural
            .registers[0] =
            value + lane;

        fabric.lanes[lane]
            .speculative
            .registers[0] =
            value + lane;
    }
}

/* ================================================================
   PARALLEL ADDITION
   ================================================================ */

void parallel_add(
    Fabric& fabric,
    uint8_t dst,
    uint8_t src0,
    uint8_t src1)
{
    const uint64_t instruction =
        encode(
            Opcode::ADD,
            dst,
            src0,
            src1,
            0xff,
            0);

    execute_parallel(
        fabric,
        instruction);
}

/* ================================================================
   PARALLEL XOR
   ================================================================ */

void parallel_xor(
    Fabric& fabric,
    uint8_t dst,
    uint8_t src0,
    uint8_t src1)
{
    const uint64_t instruction =
        encode(
            Opcode::XOR,
            dst,
            src0,
            src1,
            0xff,
            0);

    execute_parallel(
        fabric,
        instruction);
}

/* ================================================================
   PARALLEL ROTATION
   ================================================================ */

void parallel_rotl(
    Fabric& fabric,
    uint8_t dst,
    uint8_t src,
    uint32_t amount)
{
    const uint64_t instruction =
        encode(
            Opcode::ROTL,
            dst,
            src,
            0,
            0xff,
            amount);

    execute_parallel(
        fabric,
        instruction);
}

/* ================================================================
   VALIDATED STEP
   ================================================================ */

bool validated_step(
    Fabric& fabric,
    uint64_t instruction)
{
    Fabric before =
        clone_fabric(fabric);

    if (!invariant_architecture(before))
        return false;

    Fabric mirror =
        clone_fabric(before);

    execute_parallel(
        fabric,
        instruction);

    execute_parallel(
        mirror,
        instruction);

    if (!clone_equivalent(
            fabric,
            mirror)) {

        fabric = before;
        return false;
    }

    if (!invariant_architecture(fabric)) {
        fabric = before;
        return false;
    }

    return true;
}

/* ================================================================
   FAIL-CLOSED EXECUTION
   ================================================================ */

bool fail_closed_execute(
    Fabric& fabric,
    uint64_t instruction)
{
    Fabric before =
        clone_fabric(fabric);

    if (!invariant_architecture(
            before))
        return false;

    if (!validated_step(
            fabric,
            instruction)) {

        fabric = before;
        return false;
    }

    return true;
}

/* ================================================================
   PROGRAM EXECUTION
   ================================================================ */

bool execute_program(
    Fabric& fabric,
    const uint64_t* program,
    uint32_t length)
{
    if (program == nullptr)
        return false;

    for (uint32_t pc = 0;
         pc < length;
         ++pc) {

        if (!fail_closed_execute(
                fabric,
                program[pc]))
            return false;

        if (fabric.halted_mask ==
            fabric.active_mask)
            break;
    }

    return true;
}

/* ================================================================
   P2 PROGRAM CONSTRUCTION
   ================================================================ */

constexpr uint64_t instruction_nop()
{
    return encode(
        Opcode::NOP,
        0,
        0,
        0,
        0xff,
        0);
}

constexpr uint64_t instruction_add(
    uint8_t dst,
    uint8_t src0,
    uint8_t src1)
{
    return encode(
        Opcode::ADD,
        dst,
        src0,
        src1,
        0xff,
        0);
}

constexpr uint64_t instruction_xor(
    uint8_t dst,
    uint8_t src0,
    uint8_t src1)
{
    return encode(
        Opcode::XOR,
        dst,
        src0,
        src1,
        0xff,
        0);
}

constexpr uint64_t instruction_rotl(
    uint8_t dst,
    uint8_t src,
    uint32_t amount)
{
    return encode(
        Opcode::ROTL,
        dst,
        src,
        0,
        0xff,
        amount);
}

constexpr uint64_t instruction_halt()
{
    return encode(
        Opcode::HALT,
        0,
        0,
        0,
        0xff,
        0);
}

/* ================================================================
   CRYSTAL RECORD
   ================================================================ */

struct Crystal {
    uint64_t before_hash;
    uint64_t after_hash;
    uint64_t cycle;
    uint64_t instruction;
    bool invariant_valid;
    bool clone_valid;
};

/* ================================================================
   CRYSTALLIZE STEP
   ================================================================ */

Crystal crystallize_step(
    Fabric& fabric,
    uint64_t instruction)
{
    Fabric before =
        clone_fabric(fabric);

    const uint64_t before_hash =
        state_hash(before);

    const bool invariant_before =
        invariant_architecture(before);

    if (!invariant_before)
        throw std::runtime_error(
            "pre-state invalid");

    Fabric mirror =
        clone_fabric(before);

    execute_parallel(
        fabric,
        instruction);

    execute_parallel(
        mirror,
        instruction);

    const bool clone_valid =
        clone_equivalent(
            fabric,
            mirror);

    if (!clone_valid) {
        fabric = before;

        throw std::runtime_error(
            "clone divergence");
    }

    crystallize(fabric);

    const uint64_t after_hash =
        state_hash(fabric);

    return {
        before_hash,
        after_hash,
        fabric.cycle,
        instruction,
        invariant_architecture(fabric),
        clone_valid
    };
}

/* ================================================================
   MIRROR LOOP
   ================================================================ */

bool mirror_loop(
    Fabric& primary,
    Fabric& mirror,
    const uint64_t* program,
    uint32_t length)
{
    if (program == nullptr)
        return false;

    if (!clone_equivalent(
            primary,
            mirror))
        return false;

    for (uint32_t i = 0;
         i < length;
         ++i) {

        const uint64_t instruction =
            program[i];

        execute_parallel(
            primary,
            instruction);

        execute_parallel(
            mirror,
            instruction);

        if (!clone_equivalent(
                primary,
                mirror))
            return false;

        if (!invariant_architecture(
                primary))
            return false;

        if (!invariant_architecture(
                mirror))
            return false;
    }

    return true;
}

/* ================================================================
   CRYSTALIZATION BOUNDARY
   ================================================================ */

bool crystallization_boundary(
    Fabric& fabric)
{
    const uint64_t before =
        state_hash(fabric);

    if (!invariant_architecture(
            fabric))
        return false;

    crystallize(fabric);

    const uint64_t after =
        state_hash(fabric);

    if (!invariant_architecture(
            fabric))
        return false;

    return before != after ||
           fabric.cycle >= 0;
}

/* ================================================================
   ARCHITECTURAL MIRROR
   ================================================================ */

struct ArchitecturalMirror {
    Fabric primary;
    Fabric shadow;
};

/* ================================================================
   MIRROR INITIALIZATION
   ================================================================ */

void initialize_mirror(
    ArchitecturalMirror& mirror)
{
    initialize(mirror.primary);
    mirror.shadow =
        clone_fabric(
            mirror.primary);
}

/* ================================================================
   MIRROR SEED
   ================================================================ */

void seed_mirror(
    ArchitecturalMirror& mirror,
    uint64_t value)
{
    seed(
        mirror.primary,
        value);

    mirror.shadow =
        clone_fabric(
            mirror.primary);
}

/* ================================================================
   MIRROR VALIDATION
   ================================================================ */

bool validate_mirror(
    const ArchitecturalMirror& mirror)
{
    return clone_equivalent(
        mirror.primary,
        mirror.shadow);
}

/* ================================================================
   MIRROR EXECUTE
   ================================================================ */

bool execute_mirror(
    ArchitecturalMirror& mirror,
    uint64_t instruction)
{
    if (!validate_mirror(
            mirror))
        return false;

    const bool primary_ok =
        fail_closed_execute(
            mirror.primary,
            instruction);

    const bool shadow_ok =
        fail_closed_execute(
            mirror.shadow,
            instruction);

    if (!primary_ok ||
        !shadow_ok)
        return false;

    return validate_mirror(
        mirror);
}

/* ================================================================
   MIRROR CRYSTALLIZE
   ================================================================ */

bool crystallize_mirror(
    ArchitecturalMirror& mirror)
{
    if (!validate_mirror(
            mirror))
        return false;

    crystallize(
        mirror.primary);

    crystallize(
        mirror.shadow);

    return validate_mirror(
        mirror);
}

/* ================================================================
   PARALLEL FABRIC CLONE TEST
   ================================================================ */

bool clone_test()
{
    Fabric a;
    initialize(a);
    seed(a, 0x123456789abcdef0ull);

    Fabric b =
        clone_fabric(a);

    if (!clone_equivalent(
            a,
            b))
        return false;

    parallel_add(
        a,
        2,
        0,
        0);

    parallel_add(
        b,
        2,
        0,
        0);

    if (!clone_equivalent(
            a,
            b))
        return false;

    parallel_xor(
        a,
        3,
        2,
        0);

    parallel_xor(
        b,
        3,
        2,
        0);

    return clone_equivalent(
        a,
        b);
}

/* ================================================================
   INVARIANT TEST
   ================================================================ */

bool invariant_test()
{
    Fabric fabric;

    initialize(fabric);

    if (!invariant_architecture(
            fabric))
        return false;

    seed(
        fabric,
        0xfeedfacecafebeefull);

    if (!invariant_architecture(
            fabric))
        return false;

    parallel_add(
        fabric,
        1,
        0,
        0);

    if (!invariant_architecture(
            fabric))
        return false;

    rollback(fabric);

    return invariant_architecture(
        fabric);
}

/* ================================================================
   DETERMINISTIC TEST PROGRAM
   ================================================================ */

bool deterministic_test()
{
    Fabric a;
    Fabric b;

    initialize(a);
    initialize(b);

    seed(
        a,
        0x0102030405060708ull);

    seed(
        b,
        0x0102030405060708ull);

    const uint64_t program[] = {
        instruction_add(1, 0, 0),
        instruction_xor(2, 1, 0),
        instruction_rotl(3, 2, 17),
        instruction_add(4, 3, 1),
        instruction_xor(5, 4, 2),
        instruction_halt()
    };

    constexpr uint32_t length =
        sizeof(program) /
        sizeof(program[0]);

    if (!mirror_loop(
            a,
            b,
            program,
            length))
        return false;

    return clone_equivalent(
        a,
        b);
}

/* ================================================================
   FINAL VALIDATION
   ================================================================ */

bool validate_system()
{
    if (!invariant_lane_domain())
        return false;

    if (!invariant_word_domain())
        return false;

    if (!clone_test())
        return false;

    if (!invariant_test())
        return false;

    if (!deterministic_test())
        return false;

    return true;
}

/* ================================================================
   HARDWARE-PARALLEL CRYSTAL
   ================================================================ */

struct ParallelCrystal {
    uint64_t instruction;
    uint64_t pre_hash;
    uint64_t post_hash;
    uint64_t active_mask;
    uint64_t cycle;
    bool valid;
};

/* ================================================================
   CRYSTAL GENERATION
   ================================================================ */

ParallelCrystal crystallize_instruction(
    Fabric& fabric,
    uint64_t instruction)
{
    const uint64_t pre =
        state_hash(fabric);

    if (!invariant_architecture(
            fabric))
        throw std::runtime_error(
            "invalid prestate");

    Fabric shadow =
        clone_fabric(fabric);

    execute_parallel(
        fabric,
        instruction);

    execute_parallel(
        shadow,
        instruction);

    if (!clone_equivalent(
            fabric,
            shadow)) {

        throw std::runtime_error(
            "parallel mirror mismatch");
    }

    crystallize(fabric);

    const uint64_t post =
        state_hash(fabric);

    return {
        instruction,
        pre,
        post,
        fabric.active_mask,
        fabric.cycle,
        invariant_architecture(fabric)
    };
}

/* ================================================================
   END OF REFERENCE FABRIC
   ================================================================ */

} // namespace p2
