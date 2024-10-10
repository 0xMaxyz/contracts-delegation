// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title PermitConstants
/// @notice A contract containing constants used for Permit2 & ERC20 type permits
abstract contract PermitConstants {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev default Permit2 address
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // solhint-disable-line var-name-mixedcase

    bytes32 internal constant ERC20_PERMIT = 0xd505accf00000000000000000000000000000000000000000000000000000000;
    bytes32 internal constant DAI_PERMIT = 0x8fcbaf0c00000000000000000000000000000000000000000000000000000000;
    bytes32 internal constant PERMIT2_PERMIT = 0x2b67b57000000000000000000000000000000000000000000000000000000000;
    bytes32 internal constant CREDIT_PERMIT = 0x0b52d55800000000000000000000000000000000000000000000000000000000;
    bytes32 internal constant PERMIT2_TRANSFER_FROM = 0x36c7851600000000000000000000000000000000000000000000000000000000;

    bytes4 internal constant _PERMIT_LENGTH_ERROR = 0x68275857; // SafePermitBadLength.selector
}
