// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.30;

using {transform} for Observation global;

struct Observation {
    // the block timestamp of the observation
    uint32 blockTimestamp;
    // the tick accumulator, i.e. tick * time elapsed since the pool was first initialized
    int56 tickCumulative;
    // the seconds per liquidity, i.e. seconds elapsed / max(1, liquidity) since the pool was first initialized
    uint160 secondsPerLiquidityCumulativeX128;
    // whether or not the observation is initialized
    bool initialized;
}

function transform(Observation memory last, uint32 blockTimestamp, int24 tick, uint128 liquidity)
    pure
    returns (Observation memory)
{
    uint32 delta = blockTimestamp - last.blockTimestamp;
    return Observation({
        blockTimestamp: blockTimestamp,
        tickCumulative: last.tickCumulative + int56(tick) * int56(int32(delta)),
        secondsPerLiquidityCumulativeX128: last.secondsPerLiquidityCumulativeX128
            + (uint160(delta) << 128) / (liquidity > 0 ? liquidity : 1),
        initialized: true
    });
}

function initialize(Observation[65535] storage self, uint32 blockTimestamp)
    returns (uint16 cardinality, uint16 cardinalityNext)
{
    self[0] = Observation({
        blockTimestamp: blockTimestamp,
        tickCumulative: 0,
        secondsPerLiquidityCumulativeX128: 0,
        initialized: true
    });
    return (1, 1);
}
