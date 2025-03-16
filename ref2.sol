//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "hardhat/console.sol";

// ----------------------INTERFACE------------------------------

// Aave
// https://docs.aave.com/developers/the-core-protocol/lendingpool/ilendingpool

interface ILendingPool {
    /**
     * Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1
     * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
     *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of theliquidation
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param user The address of the borrower getting liquidated
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
     * @param receiveAToken `true` if the liquidators wants to receive the collateral aTokens, `false` if he wants
     * to receive the underlying collateral asset directly
     **/
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external;

    /**
     * Returns the user account data across all the reserves
     * @param user The address of the user
     * @return totalCollateralETH the total collateral in ETH of the user
     * @return totalDebtETH the total debt in ETH of the user
     * @return availableBorrowsETH the borrowing power left of the user
     * @return currentLiquidationThreshold the liquidation threshold of the user
     * @return ltv the loan to value of the user
     * @return healthFactor the current health factor of the user
     **/
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
}

// UniswapV2

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IERC20.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/Pair-ERC-20
interface IERC20 {
    // Returns the account balance of another account with address _owner.
    function balanceOf(address owner) external view returns (uint256);

    /**
     * Allows _spender to withdraw from your account multiple times, up to the _value amount.
     * If this function is called again it overwrites the current allowance with _value.
     * Lets msg.sender set their allowance for a spender.
     **/
    function approve(address spender, uint256 value) external; // return type is deleted to be compatible with USDT

    /**
     * Transfers _value amount of tokens to address _to, and MUST fire the Transfer event.
     * The function SHOULD throw if the message caller’s account balance does not have enough tokens to spend.
     * Lets msg.sender send pool tokens to an address.
     **/
    function transfer(address to, uint256 value) external returns (bool);
}

// https://github.com/Uniswap/v2-periphery/blob/master/contracts/interfaces/IWETH.sol
interface IWETH is IERC20 {
    // Convert the wrapped token back to Ether.
    function withdraw(uint256) external;
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Callee.sol
// The flash loan liquidator we plan to implement this time should be a UniswapV2 Callee
interface IUniswapV2Callee {
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Factory.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/factory
interface IUniswapV2Factory {
    // Returns the address of the pair for tokenA and tokenB, if it has been created, else address(0).
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Pair.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/pair
interface IUniswapV2Pair {
    /**
     * Swaps tokens. For regular swaps, data.length must be 0.
     * Also see [Flash Swaps](https://docs.uniswap.org/protocol/V2/concepts/core-concepts/flash-swaps).
     **/
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    /**
     * Returns the reserves of token0 and token1 used to price trades and distribute liquidity.
     * See Pricing[https://docs.uniswap.org/protocol/V2/concepts/advanced-topics/pricing].
     * Also returns the block.timestamp (mod 2**32) of the last block during which an interaction occured for the pair.
     **/
    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}

// ----------------------IMPLEMENTATION------------------------------

// https://github.com/Uniswap/v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol
interface IUniswapV2Router02 {
    function WETH() external returns (address);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface ILendingPoolAddressesProvider {
    function getLendingPool() external view returns (address);

    function getLendingPoolCore() external view returns (address payable);
}

contract LiquidationOperator is IUniswapV2Callee {
    uint8 public constant health_factor_decimals = 18;
    uint256 healthFactor;

    address Lq_victim = 0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F;
    uint64 block_num = 1621761058;

    // https://docs.uniswap.org/protocol/V2/reference/smart-contracts/router-02.
    IUniswapV2Router02 router =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IWETH WETH = IWETH(router.WETH());
    IERC20 WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IERC20 USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
  //  IERC20 DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    ILendingPoolAddressesProvider provider =
        ILendingPoolAddressesProvider(
            address(0x24a42fD28C976A61Df5D00D0599C34c4f90748c8)
        );
    address lPool = provider.getLendingPool();
    ILendingPool lendingPool =
        ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    // Uniswap interfaces.
    IUniswapV2Factory factory =
        IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    //    IUniswapV2Pair pair_USDT_WBTC = IUniswapV2Pair(factory.getPair(address(WBTC), address(USDT)));
    IUniswapV2Pair pair_WETH_USDT =
        IUniswapV2Pair(factory.getPair(address(WETH), address(USDT)));

   

    // some helper function, it is totally fine if you can finish the lab without using these function
    // https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    // safe mul is not necessary since https://docs.soliditylang.org/en/v0.8.9/080-breaking-changes.html
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // some helper function, it is totally fine if you can finish the lab without using these function
    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    // safe mul is not necessary since https://docs.soliditylang.org/en/v0.8.9/080-breaking-changes.html
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    constructor() {}

    receive() external payable {}

    // required by the testing script, entry for your liquidation call
    function operate() external {
        // 0. security checks and initializing variables
        //uint256 healthFactor; //commented because defined above as global var

        // 1. get the target user account data & make sure it is liquidatable
        uint256 Collateral_ETH;
        uint256 Debt_ETH;
        uint LqThrshld;
        uint ltv;

        (Collateral_ETH,Debt_ETH , ,LqThrshld ,ltv , healthFactor) = lendingPool.getUserAccountData(Lq_victim);
        require(healthFactor < 1e18, "health factor should be < 1 before liquidation");
        
        if(healthFactor < 1e18) console.log("position is liquitable with HF=",healthFactor);
        console.log("total collateral value=",Collateral_ETH/1e18, "ETH");
        console.log("The total debt=", Debt_ETH/1e18, "ETH");
        
        console.log("Liquidation Threshold = %d", LqThrshld);
        console.log("LTV= ", ltv);
        

        // Fine-tuned value. Should be greater than closing factor, but not too much...
        uint256 debtToCoverUSDT = 1790000000000;

        // 2. call flash swap to liquidate the target user
        // based on https://etherscan.io/tx/0xac7df37a43fab1b130318bbb761861b8357650db2e2c6493b73d6da3d9581077
        // we know that the target user borrowed USDT with WBTC as collateral
        // we should borrow USDT, liquidate the target user and get the WBTC, then swap WBTC to repay uniswap
        // (please feel free to develop other workflows as long as they liquidate the target user successfully)
        pair_WETH_USDT.swap(0, debtToCoverUSDT, address(this), "_");

        uint256 balance = WBTC.balanceOf(address(this));
        console.log("WBTC balalnce=", balance);

        address[] memory path = new address[](2);
        path[0] = address(WBTC);
        path[1] = address(WETH);
        router.swapExactTokensForETH(balance, 0, path, msg.sender, block_num);

        uint256 balanceWETH = WETH.balanceOf(address(this)); //I think this means the router already transfered the balance from this to WBTC
        WETH.withdraw(balanceWETH);

        // 3. Convert the profit into ETH and send back to sender
        payable(msg.sender).transfer(balanceWETH);
        
        /* balanceWETH = WETH.balanceOf(address(this));
        console.log("balanceWETH=", balanceWETH); */
       
    }

    // required by the swap
    function uniswapV2Call(
        address,
        uint256,
        uint256 amount1,
        bytes calldata
    ) external override {
        uint112 repay1=119011111111;
       
       // these 3 lines I need when I comment the 2 liquidation steps part and get back to 1 step
       /* (uint112 w_btc, uint112 w_eth, ) = IUniswapV2Pair(msg.sender)
            .getReserves();    // this is just to check that uniswap has enough liquidity, ie. safety check
        repay1=0; */
        
        console.log("1st repay=",repay1);
        USDT.approve(address(lendingPool), repay1);
        (uint112 w_btc, uint112 w_eth, ) = IUniswapV2Pair(msg.sender).getReserves();    // this is just to check that uniswap has enough liquidity, ie. safety check
        lendingPool.liquidationCall(
            address(WBTC),
            address(USDT),
            Lq_victim,
            repay1,
            false
        );
        //checking what we had earned in 1st step
        uint256 balance = WBTC.balanceOf(address(WBTC));
        console.log("After the 1st step we liquidated by now", balance, "WBTC");
         console.log(" with address of this=", WBTC.balanceOf(address(this)), "WBTC");

        {  //checking the result of the 1st liquidation step
        // healthFactor already defined as global
        uint256 Collateral_ETH;
        uint256 Debt_ETH;
        uint LqThrshld;
        uint ltv;

        (Collateral_ETH,Debt_ETH , ,LqThrshld ,ltv , healthFactor) = lendingPool.getUserAccountData(Lq_victim);
        require(healthFactor < 1e18, "health factor should be < 1 before liquidation");
        if(healthFactor < 1e18) console.log("position is still liquitable proceed to 2nd liquidation with HF=",healthFactor);
        console.log("total collateral value in ETH after 1st lquidation=",Collateral_ETH/1e18);
        console.log("The total debt is %d", Debt_ETH/1e18, "ETH");
        console.log("Liquidation Threshold = %d", LqThrshld);
        console.log("LTV= ", ltv);
        }        
                //2nd liquidation
       
        USDT.approve(address(lendingPool), 2**256 - 1); //now in the 2nd step we push the liquidation to its max possible value
        ( w_btc,  w_eth, ) = IUniswapV2Pair(msg.sender)
            .getReserves();
        lendingPool.liquidationCall(
            address(WBTC),
            address(USDT),
            Lq_victim,
            amount1-repay1,
            false
        );
        balance = WBTC.balanceOf(address(WBTC));
        console.log("      ");
        console.log("after 2nd liquidation WBTC balance=", balance);
        console.log(" with address of this=", WBTC.balanceOf(address(this)),"WBTC");
        
        {  //checking the result of the 2nd liquidation step
        
        uint256 Collateral_ETH;
        uint256 Debt_ETH; 
        uint LqThrshld;
        uint ltv;

        (Collateral_ETH,Debt_ETH , ,LqThrshld ,ltv , healthFactor) = lendingPool.getUserAccountData(Lq_victim);
        //require(healthFactor < 1e18, "health factor should be < 1 before liquidation");
        console.log("position should be not liquitable by now HF=",healthFactor);
        console.log("total collateral value in ETH after 1st lquidation=",Collateral_ETH/1e18,"ETH");
        console.log("The total debt is %d", Debt_ETH/1e18,"ETH");
        console.log("Liquidation Threshold = %d", LqThrshld);
        console.log("LTV= ", ltv);
        }
        
        //now routing
        WBTC.approve(address(router), 2**256 - 1);
        address[] memory path = new address[](2);
        path[0] = address(WBTC);
        path[1] = address(WETH);
        ( w_btc,  w_eth, ) = IUniswapV2Pair(msg.sender)
            .getReserves();
        uint256 amountIn = getAmountIn(amount1, w_btc, w_eth);
        console.log("amountIn=",amountIn);  //this is what I will payback to uniswap, it could be larger with less profit If I borrowed extra money originally, this will cause extra unnecessary 3/1000 pool fee that may affect my profit
        router.swapTokensForExactTokens(
            amountIn,
            2**256 - 1,
            path,
            msg.sender,
            block_num
        );
    }
}
