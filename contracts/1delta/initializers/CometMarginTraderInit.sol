// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {WithStorageComet, CometStorage, Cache, LibStorage, ManagementStorage} from "../storage/CometBrokerStorage.sol";

contract CometMarginTraderInit is WithStorageComet {
    function initCometMarginTrader(address _comet) external {
        CometStorage storage cos = LibStorage.cometStorage();
        cos.comet[0] = _comet;
        ManagementStorage storage ms = LibStorage.managementStorage();
        ms.chief = msg.sender;
        ms.isManager[msg.sender] = true;

        // set cache value for uni routing
        Cache storage cs = LibStorage.cacheStorage();
        cs.amount = type(uint256).max;
    }
}
