// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.30;

using {checkTicks} for ModifyPositionParams global;

struct ModifyPositionParams {
    // the address that owns the position
    address owner;
    // the lower and upper tick of the position
    int24 tickLower;
    int24 tickUpper;
    // any change in liquidity
    int128 liquidityDelta;
}

function checkTicks(ModifyPositionParams memory params) pure {
    require(params.tickLower < params.tickUpper, "tickLower must be less than tickUpper");
    require(params.tickLower >= -887272, "tickLower must be greater than or equal to -887272");
    require(params.tickUpper <= 887272, "tickUpper must be less than or equal to 887272");
}
