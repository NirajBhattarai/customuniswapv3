// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.30;

// Interfaces
import "./interfaces/IUniswapV3Pool.sol";
import "./interfaces/IUniswapV3PoolDeployer.sol";

// Types
import {Slot0} from "./types/slot0.sol";
import {Observation, initialize as initializeObservations} from "./types/oracle.sol";
import {Info, PositionLibrary} from "./types/position.sol";
import {ModifyPositionParams, checkTicks} from "./types/modifyPositionParams.sol";

// Math & Utilities
import {tickSpacingToMaxLiquidityPerTick} from "./math/tick.sol";
import {getTickAtSqrtRatio} from "./math/tickmath.sol";

contract UniswapV3Pool is IUniswapV3Pool {
    using PositionLibrary for mapping(bytes32 => Info);

    Slot0 public slot0;

    /// @inheritdoc IUniswapV3PoolState
    uint256 public override feeGrowthGlobal0X128;
    /// @inheritdoc IUniswapV3PoolState
    uint256 public override feeGrowthGlobal1X128;

    /// @inheritdoc IUniswapV3PoolImmutables
    address public immutable override factory;
    /// @inheritdoc IUniswapV3PoolImmutables
    address public immutable override token0;
    /// @inheritdoc IUniswapV3PoolImmutables
    address public immutable override token1;
    /// @inheritdoc IUniswapV3PoolImmutables
    uint24 public immutable override fee;

    /// @inheritdoc IUniswapV3PoolImmutables
    int24 public immutable override tickSpacing;

    /// @inheritdoc IUniswapV3PoolImmutables
    uint128 public immutable override maxLiquidityPerTick;

    /// @inheritdoc IUniswapV3PoolState
    uint128 public override liquidity;

    /// @inheritdoc IUniswapV3PoolState
    Observation[65535] public override observations;

    /// @inheritdoc IUniswapV3PoolState
    mapping(bytes32 => Info) public override positions;

    constructor() {
        int24 _tickSpacing;
        (factory, token0, token1, fee, _tickSpacing) = IUniswapV3PoolDeployer(msg.sender).parameters();
        tickSpacing = _tickSpacing;

        maxLiquidityPerTick = tickSpacingToMaxLiquidityPerTick(_tickSpacing);
    }

    function initialize(uint160 sqrtPriceX96) external override {
        require(slot0.sqrtPriceX96 == 0, "Already initialized");
        int24 tick = getTickAtSqrtRatio(sqrtPriceX96);

        (uint16 cardinality, uint16 cardinalityNext) = initializeObservations(observations, uint32(block.timestamp));

        slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex: 0,
            observationCardinality: cardinality,
            observationCardinalityNext: cardinalityNext,
            feeProtocol: 0,
            unlocked: true
        });

        emit Initialize(sqrtPriceX96, tick);
    }

    function _updatePosition(address owner, int24 tickLower, int24 tickUpper, int128 liquidityDelta, int24 tick)
        internal
        returns (Info storage position)
    {
        position = positions.get(owner, tickLower, tickUpper);

        uint256 _feeGrowthGlobal0X128 = feeGrowthGlobal0X128; // SLOAD for gas optimization
        uint256 _feeGrowthGlobal1X128 = feeGrowthGlobal1X128; // SLOAD for gas optimization

        bool flippedLower;
        bool flippedUpper;
            // position = pos
    }

    function _modifyPosition(ModifyPositionParams memory params)
        internal
        returns (Info memory position, uint256 amount0, uint256 amount1)
    {
        params.checkTicks();

        Slot0 memory _slot0 = slot0; // SLOAD for gas optimization

        // Get storage reference to the position
        // position = positions[positionKey];

        // TODO: Implement liquidity modification logic
        amount0 = 0;
        amount1 = 0;
    }

    function mint(address recipient, int24 tickLower, int24 tickUpper, uint128 amount, bytes calldata data)
        external
        override
        returns (uint256 amount0, uint256 amount1)
    {
        require(amount > 0, "Amount >0");
        return (0, 0);
    }
}
