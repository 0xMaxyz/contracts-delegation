// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

interface ICurvePool {
    function coins(uint256) external view returns (address);
}
