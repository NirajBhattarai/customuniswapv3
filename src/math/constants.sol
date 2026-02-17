// SPDX-License-Identifier: ekubo-license-v1.eth
pragma solidity >=0.8.30;

/// @dev The minimum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**-128
int24 constant MIN_TICK = -887272;
/// @dev The maximum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**128
int24 constant MAX_TICK = -MIN_TICK;
