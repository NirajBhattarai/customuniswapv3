// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.30;

struct Info {
    // the amount of liquidity owned by this position
    uint128 liquidity;
    // fee growth per unit of liquidity as of the last update to liquidity or fees owed
    uint256 feeGrowthInside0LastX128;
    uint256 feeGrowthInside1LastX128;
    // the fees owed to the position owner in token0/token1
    uint128 tokensOwed0;
    uint128 tokensOwed1;
}

library PositionLibrary {
    function get(mapping(bytes32 => Info) storage self, address owner, int24 tickLower, int24 tickUpper)
        internal
        view
        returns (Info storage position)
    {
        bytes32 key = keccak256(abi.encodePacked(owner, tickLower, tickUpper));
        position = self[key];
    }
}
