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

        /**
     * @dev Returns the state and configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The state of the reserve
     **/
    function getReserveData(address asset)
        external
        view
        returns (DataTypes.ReserveData memory);

    function getReservesList() external view returns (address[] memory);

    /**
     * @dev Returns the configuration of the user across all the reserves
     * @param user The user address
     * @return The configuration of the user
     **/
    function getUserConfiguration(address user)
        external
        view
        returns (DataTypes.UserConfigurationMap memory);

    /**
     * @dev Returns the configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The configuration of the reserve
     **/
    function getConfiguration(address asset)
        external
        view
        returns (DataTypes.ReserveConfigurationMap memory);
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
    
    function decimals() external view returns (uint8);
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

interface IPriceOracleGetter {
    function getAssetPrice(address _asset) external view returns (uint256);
}

// ----------------------IMPLEMENTATION------------------------------

library DataTypes {
  // refer to the whitepaper, section 1.1 basic concepts for a formal description of these properties.
  struct ReserveData {
    //stores the reserve configuration
    ReserveConfigurationMap configuration;
    //the liquidity index. Expressed in ray
    uint128 liquidityIndex;
    //variable borrow index. Expressed in ray
    uint128 variableBorrowIndex;
    //the current supply rate. Expressed in ray
    uint128 currentLiquidityRate;
    //the current variable borrow rate. Expressed in ray
    uint128 currentVariableBorrowRate;
    //the current stable borrow rate. Expressed in ray
    uint128 currentStableBorrowRate;
    uint40 lastUpdateTimestamp;
    //tokens addresses
    address aTokenAddress;
    address stableDebtTokenAddress;
    address variableDebtTokenAddress;
    //address of the interest rate strategy
    address interestRateStrategyAddress;
    //the id of the reserve. Represents the position in the list of the active reserves
    uint8 id;
  }

  struct ReserveConfigurationMap {
    //bit 0-15: LTV
    //bit 16-31: Liq. threshold
    //bit 32-47: Liq. bonus
    //bit 48-55: Decimals
    //bit 56: Reserve is active
    //bit 57: reserve is frozen
    //bit 58: borrowing is enabled
    //bit 59: stable rate borrowing enabled
    //bit 60-63: reserved
    //bit 64-79: reserve factor
    uint256 data;
  }

  struct UserConfigurationMap {
    uint256 data;
  }

  enum InterestRateMode {NONE, STABLE, VARIABLE}
}

library ReserveConfiguration {
    uint256 constant LIQUIDATION_BONUS_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFF; // prettier-ignore
    uint256 constant LIQUIDATION_BONUS_START_BIT_POSITION = 32;

    /**
     * @dev Gets the liquidation bonus of the reserve
     * @param self The reserve configuration
     * @return The liquidation bonus
     **/
    function getLiquidationBonus(DataTypes.ReserveConfigurationMap memory self)
        internal
        pure
        returns (uint256)
    {
        return
            (self.data & ~LIQUIDATION_BONUS_MASK) >>
            LIQUIDATION_BONUS_START_BIT_POSITION;
    }
}

interface ILendingPoolExtended is ILendingPool {
    function getReserveConfigurationData(address asset)
        external
        view
        returns (
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 reserveDecimals,
            bool usageAsCollateralEnabled
        );
}


// end cust libra

interface IUniswapV2Router {
    function swapExactTokensForTokens(
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

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

}

contract LiquidationOperator is IUniswapV2Callee {
    // number to be fine-tuned
    // use value from ether scan
    // uint256 amt_usdt_loan = 2916378221684; //    24.11903787514428899 ETH
    // uint256 amt_usdt_loan = 1458189110842; //    42.641660897358833962 ETH 50%
    uint256 amt_usdt_loan = 2916378221684 * 50 /100;



    // uint256 amt_usdt_loan = 1748000000000; //    43.830615476105570193 ETH
    // uint256 amt_usdt_loan = 113051570200;
    // uint256 amt_usdt_loan = 1602026656000; //    43.5336237875128 ETH
    // uint256 amt_usdt_loan = 1655196300000; //    43.712743025141580916 ETH
    // uint256 amt_usdt_loan = 1138307990000; //    38.525384567480640616 ETH --> from the max debt
    // uint256 amt_usdt_loan = 1142070000000; //   38.590893553984855508 ETH --> from the max debt
    // uint256 amt_usdt_loan = 1128572743000; //   38.353972347700103809 ETH --> from the max debt
    // uint256 amt_usdt_loan = 2.5e12; //  35.649648283943954735 ETH
    // uint256 amt_usdt_loan = 5451514620000;
    // uint256 amt_usdt_loan = 1753775987074; //   43.829765062859040487 ETH

    // TODO: define constants used in the contract including ERC-20 tokens, Uniswap Pairs, Aave lending pools, etc. */
    //    *** Your code here ***
    address private owner;
    uint256 healthFactor;

    uint8 public constant health_factor_decimals = 18;
    uint256 public constant HEALTH_FACTOR_CONST = 10** health_factor_decimals;
    uint256 public constant ONE_ETHER = 1e18;
    // timestamp 1621761058, block height 12489690
    uint64 constant block_num = 1621761058;
    address constant target_lq = 0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F;
    address constant LENDING_POOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;

    // swap contrct
    IUniswapV2Router router = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);    // address of tokens to be used
    IERC20 constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IERC20 constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IWETH constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // Type of WETH

    // AVAE lending protocol
    ILendingPool lendingPool = ILendingPool(LENDING_POOL);

    // Uniswap Pairs
    IUniswapV2Factory constant factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IUniswapV2Pair pair_WETH_USDT = IUniswapV2Pair(factory.getPair(address(WETH), address(USDT)));
    // END TODO

    /**
     * extra stuff
     */

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    IPriceOracleGetter constant price_oracle = IPriceOracleGetter(0xA50ba011c48153De246E5192C8f9258A2ba79Ca9);
    // using UserConfiguration for DataTypes.UserConfigurationMap;
    uint256 constant CLOSING_FACTOR = 5000;



// // custom function
    function _getLiquidationBonus(address asset)
        private
        view
        returns (uint256)
    {
        DataTypes.ReserveConfigurationMap memory configuration = ILendingPool(
            LENDING_POOL
        ).getConfiguration(asset);

        return configuration.getLiquidationBonus();
    }

// end of custom function

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

    constructor() {
        // TODO: (optional) initialize your contract
        //   *** Your code here ***
        owner = msg.sender;
        // END TODO
    }

    // TODO: add a `receive` function so that you can withdraw your WETH
    //   *** Your code here ***
    receive() external payable{ }
    // END TODO

    function _getAssetPrice() internal view{
        uint256 priceWBTC = price_oracle.getAssetPrice(address(WBTC));
        uint256 priceUSDT = price_oracle.getAssetPrice(address(USDT));
        console.log("1 wbtc price in ETH: ", priceWBTC);
        console.log("1 usdt price in ETH: ", priceUSDT);
    }

    function _calculateDebtToCover() internal view returns(uint256){
        // debt / collateral = totalCollateralETH / totalDebtETH  = 76.13%
        // 0.53% of the debt is undercollateralised => 0.53% * debt = 42.8963983032 ETH
        // collateral * LT = 8037.818722 ETH
        // debt - collateral * LT = 55.181 ETH ==> debt is larger than borrowing capcity
        // debtToCover = (userStableDebt + userVariableDebt) * LiquidationCloseFactorPercent
        // maxAmountOfCollateralToLiquidate = (debtAssetPrice * debtToCover * liquidationBonus)/ collateralPrice
        uint256 bonus = _getLiquidationBonus(address(WBTC));
        console.log("Liquidation Bonus: ", bonus);
        uint256 totalCollateralETH;
        uint256 totalDebtETH;
        uint256 currentLiquidationThreshold;
        uint256 healthF;
        ( totalCollateralETH, totalDebtETH, , currentLiquidationThreshold, , healthF) = lendingPool.getUserAccountData(target_lq);
        uint256 priceWBTC = price_oracle.getAssetPrice(address(WBTC));
        uint256 priceUSDT = price_oracle.getAssetPrice(address(USDT));
        console.log("1 wbtc price in ETH: ", priceWBTC);
        console.log("1 usdt price in ETH: ", priceUSDT);

        DataTypes.ReserveData memory reserve = ILendingPool(LENDING_POOL).getReserveData(address(USDT));
        uint256 stableDebt = IERC20(reserve.stableDebtTokenAddress).balanceOf(target_lq);
        uint256 variableDebt = IERC20(reserve.variableDebtTokenAddress).balanceOf(target_lq);
        // console.log("stable address: ", reserve.stableDebtTokenAddress);
        // console.log("variable address: ", reserve.variableDebtTokenAddress);
        console.log(IERC20(reserve.variableDebtTokenAddress).decimals());
        console.log("stable Debt in WBTC (8 decimal): ", stableDebt);
        console.log("variable Debt in USDT (6 decimal): ", variableDebt);

        uint256 debtToCover = (stableDebt + variableDebt) * CLOSING_FACTOR / 10000;
        console.log("Debt to cover (USDT): ", debtToCover);
        uint256 debtRepaidValue = (debtToCover / 1e6 * priceUSDT / 1e18) * 1e18;
        console.log("Debt to cover (ETH): ", debtRepaidValue / 1e18);
        uint256 maxCollateralLiquidate = (debtRepaidValue*53/10000 * bonus ) / 10000;
        console.log("Calcuated collateral to cover: ", maxCollateralLiquidate / 1e18 );
        // amt_usdt_loan = maxCollateralLiquidate*10000;
        uint256 deltaDebt = totalDebtETH - totalCollateralETH * currentLiquidationThreshold/10000;
        console.log(deltaDebt / 1e18);
        console.log(deltaDebt / priceUSDT * 1e6  );
        return deltaDebt / priceUSDT * 1e6;
    }


    function _getCurrentStatus() internal view{
        {
            (
                uint256 totalCollateralETH,
                uint256 totalDebtETH,
                uint256 availableBorrowsETH,
                uint256 currentLiquidationThreshold,
                uint256 ltv,
                uint256 healthFactor2
            ) = lendingPool.getUserAccountData(target_lq);

            console.log("***** Loan Status *****");
            console.log("- Collateral value: ", totalCollateralETH/ONE_ETHER, " ETH");
            console.log("- Debt: ", totalDebtETH/ONE_ETHER, " ETH");
            console.log("- Liquidation Threshold: %d", currentLiquidationThreshold, " %");
            console.log("- LTV (WBTC/USDT): %d", ltv);
            console.log("- Available Borrows ETH: %d", availableBorrowsETH);
            console.log("- Health Factor: %d", healthFactor2);
            console.log("***********************\n");
        }
    }

    // required by the testing script, entry for your liquidation call
    function operate() external {
        // TODO: implement your liquidation logic
        // 0. security checks and initializing variables
        //    *** Your code here ***
        require(owner==msg.sender, "Invalid User");

        // 1. get the target user account data & make sure it is liquidatable
        //    *** Your code here ***
        // get account data
        uint256 totalCollateralETH;
        uint256 totalDebtETH;
        uint256 currentLiquidationThreshold;
        ( totalCollateralETH, totalDebtETH, , currentLiquidationThreshold, , healthFactor) = lendingPool.getUserAccountData(target_lq);

        // check if liquidatable
        require(healthFactor < HEALTH_FACTOR_CONST, "Target not liquidatable");
        if(healthFactor < HEALTH_FACTOR_CONST){
            console.log("Liquitable position: ", healthFactor);
        }
        console.log("\n>> Initial Outlook: ");
        _getCurrentStatus();
        // amt_usdt_loan = _calculateDebtToCover();
        // _calculateDebtToCover();

        // 2. call flash swap to liquidate the target user
        // based on https://etherscan.io/tx/0xac7df37a43fab1b130318bbb761861b8357650db2e2c6493b73d6da3d9581077
        // we know that the target user borrowed USDT with WBTC as collateral
        // we should borrow USDT, liquidate the target user and get the WBTC, then swap WBTC to repay uniswap
        // (please feel free to develop other workflows as long as they liquidate the target user successfully)
        //    *** Your code here ***
        
        // do the sawp, borrow USDT using ETH as collateral, using the pair contract to do the borrow
        console.log("\n>> Begin Swapping");
        pair_WETH_USDT.swap(0, amt_usdt_loan, address(this), "_");
    

        // 3. Convert the profit into ETH and send back to sender
        //    *** Your code here ***
        // check profit
        uint256 balance_wbtc = WBTC.balanceOf(address(this));
        console.log("Total Profit (WBTC): ", balance_wbtc);

        // conver profit to ETH and withdraw
        address[] memory swapPath = new address[](2);
        swapPath[0] = address(WBTC);
        swapPath[1] = address(WETH);
        router.swapExactTokensForETH(balance_wbtc, 0, swapPath, msg.sender, block_num);
        uint256 balanceWETH = WETH.balanceOf(address(this)); 
        WETH.withdraw(balanceWETH);


        // END TODO
    }

    // required by the swap
    function uniswapV2Call(
        address,
        uint256,
        uint256 amount1,
        bytes calldata
    ) external override {
        // TODO: implement your liquidation logic
        console.log("\n****** uniswapV2Call *********");

        // 2.0. security checks and initializing variables
        //    *** Your code here ***
        // call uniswapv2factory to getpair 
        address pair = IUniswapV2Factory(factory).getPair(address(WETH), address(USDT));
        require(msg.sender == pair, "invalid pair");

        // approve the pool to use USDT and WETH
        USDT.approve(address(lendingPool), type(uint).max);
        WETH.approve(address(lendingPool), type(uint).max);

        console.log("WBTC to repay: ", amount1);
        console.log("\nBefore the liquidation, WBTC balance: ");
        console.log("WBTC contract:", WBTC.balanceOf(address(WBTC)));
        console.log("this acc: ", WBTC.balanceOf(address(this)));
        // ensure we have enough tokens to do the liquidity
        (uint112 pairBTC, uint112 pairETH, ) = IUniswapV2Pair(msg.sender).getReserves();
        // do the liquidation call and repay using the amt1
        _getAssetPrice();

        lendingPool.liquidationCall(
            address(WBTC),
            address(USDT),
            target_lq,
            amount1,
            false
        );

        // check the reward of liquidation
        console.log("\n>> After 1st liquidation: ");
        console.log("- WBTC earned: ", WBTC.balanceOf(address(this)));
        // check if another liquidation needed
        _getCurrentStatus();
        _getAssetPrice();


        // uint256 repay2 = _calculateDebtToCover();
        // lendingPool.liquidationCall(
        //     address(WBTC),
        //     address(USDT),
        //     target_lq,
        //     repay2,
        //     false
        // );

        // // check the reward of liquidation
        // console.log("\n>> After 2nd liquidation: ");
        // console.log("- WBTC earned: ", WBTC.balanceOf(address(this)));
        // // check if another liquidation needed
        // _getCurrentStatus();


        // pay back the swap
        WBTC.approve(address(router), type(uint).max);
        address[] memory repayPath = new address[](2);
        repayPath[0] = address(WBTC);
        repayPath[1] = address(WETH);
        (pairBTC, pairETH, ) = IUniswapV2Pair(msg.sender).getReserves();  

        uint256 amountRepay = getAmountIn(amount1, pairBTC, pairETH);
        console.log("Amount need to repay: ", amountRepay);
        router.swapTokensForExactTokens(
            amountRepay,
            2**256-1,
            repayPath,
            msg.sender,
            block_num
        );

        // 2.1 liquidate the target user
        //    *** Your code here ***

        // 2.2 swap WBTC for other things or repay directly
        //    *** Your code here ***

        // 2.3 repay
        //    *** Your code here ***
        
        // END TODO
    }
}