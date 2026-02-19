// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.30;

// Interfaces
import "./interfaces/IUniswapV3Pool.sol";
import "./interfaces/IUniswapV3PoolDeployer.sol";
import "./interfaces/IERC20Minimal.sol";
import "./interfaces/IUniswapV3MintCallback.sol";

// Types
import {Slot0} from "./types/slot0.sol";
import {Observation, OracleLibrary} from "./types/oracle.sol";
import {Info, PositionLibrary} from "./types/position.sol";
import {ModifyPositionParams, checkTicks} from "./types/modifyPositionParams.sol";
import {Tick} from "./libraries/Tick.sol";
import {console} from "forge-std/console.sol";

import "./libraries/TickBitmap.sol";
import "./libraries/TickMath.sol";
import "./libraries/LiquidityMath.sol";
import "./libraries/SafeCast.sol";
import "./libraries/SqrtPriceMath.sol";
import "./libraries/FixedPoint96.sol";
import "./libraries/FullMath.sol";
import "./libraries/UnsafeMath.sol";

// Math & Utilities
import {tickSpacingToMaxLiquidityPerTick} from "./math/tick.sol";
import {getTickAtSqrtRatio} from "./math/tickmath.sol";

contract UniswapV3Pool is IUniswapV3Pool {
    using PositionLibrary for mapping(bytes32 => Info);
    using OracleLibrary for Observation[65535];
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using SafeCast for int256;

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
    mapping(int24 => Tick.Info) public override ticks;

    /// @inheritdoc IUniswapV3PoolState
    uint128 public override liquidity;

    /// @inheritdoc IUniswapV3PoolState
    Observation[65535] public override observations;

    /// @inheritdoc IUniswapV3PoolState
    mapping(bytes32 => Info) public override positions;

    /// @inheritdoc IUniswapV3PoolState
    mapping(int16 => uint256) public override tickBitmap;

    constructor() {
        int24 _tickSpacing;
        (factory, token0, token1, fee, _tickSpacing) = IUniswapV3PoolDeployer(msg.sender).parameters();
        tickSpacing = _tickSpacing;

        maxLiquidityPerTick = tickSpacingToMaxLiquidityPerTick(_tickSpacing);
    }

    /// @dev Returns the block timestamp truncated to 32 bits, i.e. mod 2**32. This method is overridden in tests.
    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp); // truncation is desired
    }

    function initialize(uint160 sqrtPriceX96) external override {
        require(slot0.sqrtPriceX96 == 0, "Already initialized");
        int24 tick = getTickAtSqrtRatio(sqrtPriceX96);

        (uint16 cardinality, uint16 cardinalityNext) = OracleLibrary.initialize(observations, uint32(block.timestamp));

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

        if (liquidityDelta != 0) {
            uint32 time = _blockTimestamp();
            (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observations.observeSingle(
                time, 0, slot0.tick, slot0.observationIndex, liquidity, slot0.observationCardinality
            );
            flippedLower = ticks.update(
                tickLower,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                secondsPerLiquidityCumulativeX128,
                tickCumulative,
                time,
                false,
                maxLiquidityPerTick
            );

            console.log("flippedLower-update", flippedLower);
            flippedUpper = ticks.update(
                tickUpper,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                secondsPerLiquidityCumulativeX128,
                tickCumulative,
                time,
                true,
                maxLiquidityPerTick
            );
            console.log("flippedUpper-update", flippedUpper);
        }

        if (flippedLower) {
            tickBitmap.flipTick(tickLower, tickSpacing);
        }
        if (flippedUpper) {
            tickBitmap.flipTick(tickUpper, tickSpacing);
        }
    }

    function _modifyPosition(ModifyPositionParams memory params)
        internal
        returns (Info storage position, uint256 amount0, uint256 amount1)
    {
        params.checkTicks();

        Slot0 memory _slot0 = slot0; // SLOAD for gas optimization

        position = _updatePosition(params.owner, params.tickLower, params.tickUpper, params.liquidityDelta, _slot0.tick);

        if (params.liquidityDelta != 0) {
            if (_slot0.tick < params.tickLower) {
                // current tick is below the passed range; liquidity can only become in range by crossing from left to
                // right, when we'll need _more_ token0 (it's becoming more valuable) so user must provide it
                amount0 = uint256(
                    SqrtPriceMath.getAmount0Delta(
                        TickMath.getSqrtRatioAtTick(params.tickLower),
                        TickMath.getSqrtRatioAtTick(params.tickUpper),
                        params.liquidityDelta
                    )
                );
            } else if (_slot0.tick < params.tickUpper) {
                // current tick is inside the passed range
                uint128 liquidityBefore = liquidity; // SLOAD for gas optimization

                // write an oracle entry
                (slot0.observationIndex, slot0.observationCardinality) = observations.write(
                    _slot0.observationIndex,
                    _blockTimestamp(),
                    _slot0.tick,
                    liquidityBefore,
                    _slot0.observationCardinality,
                    _slot0.observationCardinalityNext
                );

                amount0 = uint256(
                    SqrtPriceMath.getAmount0Delta(
                        _slot0.sqrtPriceX96, TickMath.getSqrtRatioAtTick(params.tickUpper), params.liquidityDelta
                    )
                );
                amount1 = uint256(
                    SqrtPriceMath.getAmount1Delta(
                        TickMath.getSqrtRatioAtTick(params.tickLower), _slot0.sqrtPriceX96, params.liquidityDelta
                    )
                );

                liquidity = LiquidityMath.addDelta(liquidityBefore, params.liquidityDelta);
            } else {
                // current tick is above the passed range; liquidity can only become in range by crossing from right to
                // left, when we'll need _more_ token1 (it's becoming more valuable) so user must provide it
                amount1 = uint256(
                    SqrtPriceMath.getAmount1Delta(
                        TickMath.getSqrtRatioAtTick(params.tickLower),
                        TickMath.getSqrtRatioAtTick(params.tickUpper),
                        params.liquidityDelta
                    )
                );
            }
        }
    }

    function mint(address recipient, int24 tickLower, int24 tickUpper, uint128 amount, bytes calldata data)
        external
        override
        returns (uint256 amount0, uint256 amount1)
    {
        require(amount > 0, "Amount >0");
        (, uint256 amount0Int, uint256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: recipient,
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(uint256(amount)).toInt128()
            })
        );

        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();
        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0, amount1, data);
        if (amount0 > 0) require(balance0Before + amount0 <= balance0(), "M0");
        if (amount1 > 0) require(balance1Before + amount1 <= balance1(), "M1");
    }

    /// @notice Returns liquidity at tickLower and tickUpper in one call
    /// @param tickLower The lower tick of the range
    /// @param tickUpper The upper tick of the range
    /// @return liquidityGrossLower Total position liquidity using tickLower as a boundary
    /// @return liquidityNetLower Net liquidity delta when crossing tickLower left-to-right
    /// @return liquidityGrossUpper Total position liquidity using tickUpper as a boundary
    /// @return liquidityNetUpper Net liquidity delta when crossing tickUpper left-to-right
    function getLiquidityAtTicks(int24 tickLower, int24 tickUpper)
        external
        view
        returns (
            uint128 liquidityGrossLower,
            int128 liquidityNetLower,
            uint128 liquidityGrossUpper,
            int128 liquidityNetUpper
        )
    {
        Tick.Info storage infoLower = ticks[tickLower];
        Tick.Info storage infoUpper = ticks[tickUpper];
        liquidityGrossLower = infoLower.liquidityGross;
        liquidityNetLower = infoLower.liquidityNet;
        liquidityGrossUpper = infoUpper.liquidityGross;
        liquidityNetUpper = infoUpper.liquidityNet;
    }

    /// @dev Get the pool's balance of token0
    /// @dev This function is gas optimized to avoid a redundant extcodesize check in addition to the returndatasize
    /// check
    function balance0() private view returns (uint256) {
        (bool success, bytes memory data) =
            token0.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this)));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    /// @dev Get the pool's balance of token1
    /// @dev This function is gas optimized to avoid a redundant extcodesize check in addition to the returndatasize
    /// check
    function balance1() private view returns (uint256) {
        (bool success, bytes memory data) =
            token1.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this)));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }
}
