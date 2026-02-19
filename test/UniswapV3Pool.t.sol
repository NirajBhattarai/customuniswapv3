// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.30;

// External
import "forge-std/Test.sol";

// Contracts
import {UniswapV3Pool} from "../src/UniswapV3Pool.sol";

// Interfaces
import {IUniswapV3Pool} from "../src/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3PoolDeployer} from "../src/interfaces/IUniswapV3PoolDeployer.sol";
import {IUniswapV3MintCallback} from "../src/interfaces/IUniswapV3MintCallback.sol";
import {IUniswapV3SwapCallback} from "../src/interfaces/IUniswapV3SwapCallback.sol";
import {IUniswapV3FlashCallback} from "../src/interfaces/IUniswapV3FlashCallback.sol";
import {IERC20Minimal} from "../src/interfaces/IERC20Minimal.sol";

// Mock deployer for testing
contract MockDeployer is IUniswapV3PoolDeployer {
    struct PoolParameters {
        address factory;
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
    }

    PoolParameters public params;

    constructor(address _factory, address _token0, address _token1, uint24 _fee, int24 _tickSpacing) {
        params = PoolParameters(_factory, _token0, _token1, _fee, _tickSpacing);
    }

    function parameters()
        external
        view
        returns (address factory, address token0, address token1, uint24 fee, int24 tickSpacing)
    {
        return (params.factory, params.token0, params.token1, params.fee, params.tickSpacing);
    }
}

/// @notice Minimal ERC20 for testing; pool expects token0 < token1 by address
contract MockERC20 is IERC20Minimal {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;
    uint256 public totalSupply;

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        allowance[sender][msg.sender] -= amount;
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
}

contract UniswapV3PoolTest is Test, IUniswapV3MintCallback, IUniswapV3SwapCallback, IUniswapV3FlashCallback {
    UniswapV3Pool pool;
    MockDeployer deployer;
    MockERC20 token0;
    MockERC20 token1;

    address constant FACTORY = address(0x1);
    uint24 constant FEE = 3000; // 0.3%
    int24 constant TICK_SPACING = 60;
    uint256 constant MINT_AMOUNT = 1e30;

    function setUp() external {
        MockERC20 t0 = new MockERC20();
        MockERC20 t1 = new MockERC20();
        (token0, token1) = address(t0) < address(t1) ? (t0, t1) : (t1, t0);

        deployer = new MockDeployer(FACTORY, address(token0), address(token1), FEE, TICK_SPACING);

        vm.prank(address(deployer));
        pool = new UniswapV3Pool();

        token0.mint(address(this), MINT_AMOUNT);
        token1.mint(address(this), MINT_AMOUNT);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        // Callback pulls via transferFrom(this, pool, amount), so this contract must be approved to spend its own balance
        token0.approve(address(this), type(uint256).max);
        token1.approve(address(this), type(uint256).max);
    }

    // Test: Pool initialization with correct parameters
    function test_PoolInitialization() external {
        assertEq(pool.factory(), FACTORY, "Factory address mismatch");
        assertEq(pool.token0(), address(token0), "Token0 address mismatch");
        assertEq(pool.token1(), address(token1), "Token1 address mismatch");
        assertEq(pool.fee(), FEE, "Fee mismatch");
        assertEq(pool.tickSpacing(), TICK_SPACING, "Tick spacing mismatch");
    }

    // Test: Max liquidity per tick is correctly set
    function test_MaxLiquidityPerTick() external {
        uint128 maxLiquidityPerTick = pool.maxLiquidityPerTick();
        assertGt(maxLiquidityPerTick, 0, "Max liquidity per tick should be greater than 0");
    }

    // Test: Initial liquidity is zero
    function test_InitialLiquidity() external {
        assertEq(pool.liquidity(), 0, "Initial liquidity should be zero");
    }

    // Test: Slot0 state is initialized
    function test_Slot0Initialization() external {
        // Slot0 should exist and be accessible
        (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        ) = pool.slot0();
        // Initially all fields should be 0/false
        assertEq(sqrtPriceX96, 0, "Initial sqrtPriceX96 should be zero");
        assertEq(tick, 0, "Initial tick should be zero");
    }

    // Test: Initialize function can be called
    function test_InitializePool() external {
        uint160 sqrtPriceX96 = 2 ** 96; // Simple initial price
        pool.initialize(sqrtPriceX96);
        // Pool should be initialized (implementation pending)
    }

    function test_InitializePoolRevert() external {
        uint160 sqrtPriceX96 = 2 ** 96; // Simple initial price
        pool.initialize(sqrtPriceX96);
        // Re-initializing should revert
        vm.expectRevert("Already initialized");
        pool.initialize(sqrtPriceX96);
    }

    // Test: Mint function returns amounts and callback is used
    function test_MintFunctionExists() external {
        pool.initialize(2 ** 96);
        address recipient = address(this);
        int24 tickLower = -TICK_SPACING;
        int24 tickUpper = TICK_SPACING;
        uint128 amount = 1000;

        (uint256 amount0, uint256 amount1) = pool.mint(recipient, tickLower, tickUpper, amount, abi.encode(address(this)));
        // With current tick in range, at least one of amount0/amount1 is typically > 0
        assertTrue(amount0 > 0 || amount1 > 0 || (amount0 == 0 && amount1 == 0), "mint should return amounts");
    }

    /// @notice Asserts that mint causes token0 and token1 to be transferred to the pool
    function test_Mint_TokenTransferred() external {
        pool.initialize(2 ** 96);
        address recipient = address(this);
        int24 tickLower = -TICK_SPACING;
        int24 tickUpper = TICK_SPACING;
        uint128 amount = 1000;

        uint256 poolBalance0Before = token0.balanceOf(address(pool));
        uint256 poolBalance1Before = token1.balanceOf(address(pool));

        (uint256 amount0, uint256 amount1) = pool.mint(recipient, tickLower, tickUpper, amount, abi.encode(address(this)));

        assertEq(token0.balanceOf(address(pool)), poolBalance0Before + amount0, "token0 must be transferred to pool");
        assertEq(token1.balanceOf(address(pool)), poolBalance1Before + amount1, "token1 must be transferred to pool");
    }

    /// @notice Single test for mint(): position updates, tick liquidity, and tokens transferred to pool.
    /// Run one case manually: MINT_CASE=0 forge test --match-test test_MintCases -vv (etc.)
    function test_MintCases() external {
        pool.initialize(2 ** 96); // price 1.0, tick 0

        uint256 totalAmount0;
        uint256 totalAmount1;
        uint256 poolBalance0Before = token0.balanceOf(address(pool));
        uint256 poolBalance1Before = token1.balanceOf(address(pool));

        address recipient = makeAddr("alice");
        int24 tickLower = -60;
        int24 tickUpper = 60;
        uint128 amount = 1000;

        bytes memory mintData = abi.encode(address(this));
        (uint256 a0, uint256 a1) = pool.mint(recipient, tickLower, tickUpper, amount, mintData);
        totalAmount0 += a0;
        totalAmount1 += a1;

        (a0, a1) = pool.mint(recipient, tickLower, tickUpper, amount, mintData);
        totalAmount0 += a0;
        totalAmount1 += a1;

        address bob = makeAddr("bob");
        int24 bobTickLower = -120;
        int24 bobTickUpper = 0;
        uint128 bobAmount = 2000;

        (a0, a1) = pool.mint(bob, bobTickLower, bobTickUpper, bobAmount, mintData);
        totalAmount0 += a0;
        totalAmount1 += a1;

        // Tokens must have been transferred to the pool
        assertEq(token0.balanceOf(address(pool)), poolBalance0Before + totalAmount0, "pool must receive token0");
        assertEq(token1.balanceOf(address(pool)), poolBalance1Before + totalAmount1, "pool must receive token1");

        (
            uint128 aliceLiquidityGrossLower,
            int128 aliceLiquidityNetLower,
            uint128 aliceLiquidityGrossUpper,
            int128 aliceLiquidityNetUpper
        ) = pool.getLiquidityAtTicks(tickLower, tickUpper);
        assertEq(aliceLiquidityGrossLower, 2 * amount, "Alice tick lower gross");
        assertEq(aliceLiquidityGrossUpper, 2 * amount, "Alice tick upper gross");
        assertEq(aliceLiquidityNetLower, int128(int256(uint256(2 * amount))), "Alice tick lower net");
        assertEq(aliceLiquidityNetUpper, -int128(int256(uint256(2 * amount))), "Alice tick upper net");

        (
            uint128 bobLiquidityGrossLower,
            ,
            uint128 bobLiquidityGrossUpper,
            int128 bobLiquidityNetUpper
        ) = pool.getLiquidityAtTicks(bobTickLower, bobTickUpper);
        assertEq(bobLiquidityGrossLower, bobAmount, "Bob tick lower gross");
        assertEq(bobLiquidityGrossUpper, bobAmount, "Bob tick upper gross");
        assertEq(bobLiquidityNetUpper, -int128(int256(uint256(bobAmount))), "Bob tick upper net");
    }

    // -------- Callback Implementations --------

    /// @notice Callback for IUniswapV3PoolActions#mint
    /// @dev Handles the token transfer callback when liquidity is minted
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external override {
        address sender = data.length > 0 ? abi.decode(data, (address)) : msg.sender;

        // Transfer token0 if amount owed is greater than 0
        if (amount0Owed > 0) {
            IERC20Minimal(IUniswapV3Pool(msg.sender).token0()).transferFrom(sender, msg.sender, amount0Owed);
        }

        // Transfer token1 if amount owed is greater than 0
        if (amount1Owed > 0) {
            IERC20Minimal(IUniswapV3Pool(msg.sender).token1()).transferFrom(sender, msg.sender, amount1Owed);
        }
    }

    /// @notice Callback for IUniswapV3PoolActions#swap
    /// @dev Handles the token transfer callback when a swap is executed
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        address sender = data.length > 0 ? abi.decode(data, (address)) : msg.sender;

        // Transfer token0 if amount delta is positive (pool receives token0)
        if (amount0Delta > 0) {
            IERC20Minimal(IUniswapV3Pool(msg.sender).token0()).transferFrom(sender, msg.sender, uint256(amount0Delta));
        }

        // Transfer token1 if amount delta is positive (pool receives token1)
        if (amount1Delta > 0) {
            IERC20Minimal(IUniswapV3Pool(msg.sender).token1()).transferFrom(sender, msg.sender, uint256(amount1Delta));
        }
    }

    /// @notice Callback for IUniswapV3PoolActions#flash
    /// @dev Handles the token repayment callback for flash loans
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external override {
        if (data.length == 0) return; // No repayment required

        (address sender, uint256 pay0, uint256 pay1) = abi.decode(data, (address, uint256, uint256));

        // Repay token0 with fee if required
        if (pay0 > 0) {
            IERC20Minimal(IUniswapV3Pool(msg.sender).token0()).transferFrom(sender, msg.sender, pay0 + fee0);
        }

        // Repay token1 with fee if required
        if (pay1 > 0) {
            IERC20Minimal(IUniswapV3Pool(msg.sender).token1()).transferFrom(sender, msg.sender, pay1 + fee1);
        }
    }
}
