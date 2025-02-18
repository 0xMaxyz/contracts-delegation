// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract MockRouter {
    uint256 public rate;
    uint256 slippage;

    constructor(uint256 _rate, uint256 _slippage) {
        rate = _rate;
        slippage = _slippage;
    }

    function swapExactIn(address inAsset, address outAsset, uint256 inAm) external returns (uint256 outAm) {
        IERC20(inAsset).transferFrom(msg.sender, address(this), inAm);
        outAm = (inAm * rate) / 1e18 - slippage;
        IERC20(outAsset).transfer(msg.sender, outAm);
    }

    function swapExactOut(address inAsset, address outAsset, uint256 outAm) external returns (uint256 inAm) {
        IERC20(outAsset).transfer(msg.sender, outAm);
        inAm = (outAm * 1e18) / rate - slippage;
        IERC20(inAsset).transferFrom(msg.sender, address(this), inAm);
    }

    function setRate(uint256 _rate) external {
        rate = _rate;
    }
}
