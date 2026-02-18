// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.30;

// Interfaces
import "./pool/IUniswapV3PoolActions.sol";
import "./pool/IUniswapV3PoolImmutables.sol";
import "./pool/IUniswapV3PoolState.sol";
import "./pool/IUniswapV3PoolEvents.sol";

interface IUniswapV3Pool is
    IUniswapV3PoolActions,
    IUniswapV3PoolImmutables,
    IUniswapV3PoolState,
    IUniswapV3PoolEvents
{}
