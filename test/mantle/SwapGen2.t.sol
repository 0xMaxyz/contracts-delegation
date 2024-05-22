// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./DeltaSetup.f.sol";

contract SwapGen2Test is DeltaSetup {
    uint256 DEFAULT_IR_MODE = 2; // variable

    function test_mantle_gen_2_spot_exact_in() external /** address user, uint8 lenderId */ {
        address user = testUser;
        vm.assume(user != address(0));
        address assetFrom = USDC;

        address assetTo = USDT;
        deal(assetFrom, user, 1e20);

        uint256 amountToSwap = 2000.0e6;


        bytes memory swapPath = getOpenExactInSingleGen2(assetFrom, assetTo);
        uint256 minimumOut = 10.0e6;
        vm.prank(user);
        IERC20All(assetFrom).approve(brokerProxyAddress, amountToSwap);

        uint256 balanceIn = IERC20All(assetFrom).balanceOf(user);
        uint256 balanceOut = IERC20All(assetTo).balanceOf(user);

        vm.prank(user);
        uint256 gas = gasleft();
        IFlashAggregator(address(brokerProxy)).swapExactInSpot(amountToSwap, minimumOut, swapPath);
        gas = gas - gasleft();
        console.log("gas", gas, 144771);

        balanceOut = IERC20All(assetTo).balanceOf(user) - balanceOut;
        balanceIn = balanceIn - IERC20All(assetFrom).balanceOf(user);
        assertApproxEqAbs(balanceIn, amountToSwap, 0);
        assertApproxEqAbs(amountToSwap, balanceOut, 1e6);
    }


    function test_mantle_gen_2_spot_exact_in_V2() external /** address user, uint8 lenderId */ {
        address user = testUser;
        vm.assume(user != address(0));
        address assetFrom = USDC;

        address assetTo = USDT;
        deal(assetFrom, user, 1e20);

        uint256 amountToSwap = 200.0e6;

        bytes memory swapPath = getOpenExactInSingleGen2V2(assetFrom, assetTo);
        uint256 minimumOut = 10.0e6;

        vm.prank(user);
        IERC20All(assetFrom).approve(brokerProxyAddress, amountToSwap);

        uint256 balanceIn = IERC20All(assetFrom).balanceOf(user);
        uint256 balanceOut = IERC20All(assetTo).balanceOf(user);
        
        console.log("WTST");

        vm.prank(user);
        uint256 gas = gasleft();
        IFlashAggregator(address(brokerProxy)).swapExactInSpot(amountToSwap, minimumOut, swapPath);
        gas = gas - gasleft();
        console.log("gas", gas, 144771);
        balanceOut = IERC20All(assetTo).balanceOf(user) - balanceOut;
        balanceIn = balanceIn - IERC20All(assetFrom).balanceOf(user);
        assertApproxEqAbs(balanceIn, amountToSwap, 0);
        assertApproxEqAbs(198751420, balanceOut, 1);
    }

    function getOpenExactInSingleGen2(address tokenIn, address tokenOut) internal view returns (bytes memory data) {
        uint16 fee = uint16(DEX_FEE_STABLES);
        uint8 poolId = AGNI;
        return abi.encodePacked(tokenIn, uint8(10), poolId, fee, tokenOut);
    }

    function getOpenExactInSingleGen2V2(address tokenIn, address tokenOut) internal view returns (bytes memory data) {
        uint8 poolId = MERCHANT_MOE;
        return abi.encodePacked(tokenIn, uint8(10), poolId, tokenOut);
    }
}
