// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import {MarginTrading} from "./MarginTrading.sol";
import {Commands} from "../shared/Commands.sol";

/**
 * @title Universal aggregator contract.
 *        Allows spot and margin swap aggregation
 *        Efficient baching through compact calldata usage.
 * @author 1delta Labs AG
 */
contract OneDeltaComposerPolygon is MarginTrading {
    /// @dev The highest bit signals whether the swap is internal (the payer is this contract)
    uint256 private constant _PAY_SELF = 1 << 255;
    /// @dev The second bit signals whether the input token is a FOT token
    ///      Only used for SWAP_EXACT_IN
    uint256 private constant _FEE_ON_TRANSFER = 1 << 254;
    /// @dev We use uint112-encoded amounts to typically fit one bit flag, one path length (uint16)
    ///      add 2 amounts (2xuint112) into 32bytes, as such we use this mask for extracting those
    uint256 private constant _UINT112_MASK = 0x000000000000000000000000000000000000ffffffffffffffffffffffffffff;
    /// @dev we need USDCE and USDT to identify Compound V3's selectors
    address internal constant USDCE = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address internal constant USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;

    /**
     * Batch-executes a series of operations
     * @param data compressed instruction calldata
     */
    function deltaCompose(bytes calldata data) external payable {
        _deltaComposeInternal(msg.sender, data);
    }

    /**
     * Execute a set op packed operations
     * @param callerAddress the address of the EOA/contract that
     *                      initially triggered the `deltaCompose`
     * @param data packed ops array
     * | op0 | length0 | data0 | op1 | length1 | ...
     * | 1   |    16   | ...   |  1  |    16   | ...
     */
    function _deltaComposeInternal(address callerAddress, bytes calldata data) internal {
        // data loop paramters
        uint256 currentOffset;
        uint256 maxIndex;
        assembly {
            maxIndex := add(data.length, data.offset)
            currentOffset := data.offset
        }

        ////////////////////////////////////////////////////
        // Progressively loop through the calldata
        // The first byte defines the operation
        // From there on, we read the data based on the
        // what the operation expects, e.g. read the next 32 bytes as uint256.
        //
        // `currentOffset` represents the current byte at which we
        //            are in the calldata
        // `maxIndex` is used as break criteria, this means that if
        //            currentOffset >= maxIndex, we iterated through
        //            the entire calldata.
        ////////////////////////////////////////////////////
        while (true) {
            uint256 operation;
            // fetch op metadata
            assembly {
                operation := shr(248, calldataload(currentOffset)) // last byte
                // we increment the current offset to skip the operation
                currentOffset := add(1, currentOffset)
            }
            if (operation < 0x10) {
                // exec op
                if (operation == Commands.SWAP_EXACT_IN) {
                    ////////////////////////////////////////////////////
                    // Encoded parameters for the swap
                    // | receiver | amount | pathLength | path |
                    // | address  | uint240|   uint16   | bytes|
                    // where amount is provided as
                    // pay self         (bool)      in the upper bit if true, payer is this contract
                    // fot              (bool)      2nd bit, if true, assume fee-on-transfer as input
                    // minimumAmountOut (uint120)   in the bytes starting at bit 128
                    //                              from the right
                    // amountIn         (uint128)   in the lowest bytes
                    //                              zero is for paying withn the balance of
                    //                              payer (self or caller)
                    ////////////////////////////////////////////////////
                    uint256 opdataOffset;
                    uint256 opdataLength;
                    uint256 amountIn;
                    address payer;
                    address receiver;
                    uint256 minimumAmountOut;
                    bool noFOT;
                    assembly {
                        // the path starts after the path length
                        opdataOffset := add(currentOffset, 52) // 20 + 32 (address + amountBitmap)
                        // the first 20 bytes are the receiver address
                        receiver := shr(96, calldataload(currentOffset))
                        // assign the entire 32 bytes of amounts data
                        amountIn := calldataload(add(currentOffset, 20))
                        // this is the path data length
                        opdataLength := and(amountIn, UINT16_MASK)
                        // validation amount starts at bit 128 from the right
                        minimumAmountOut := and(_UINT112_MASK, shr(128, amountIn))
                        // check whether the swap is internal by the highest bit
                        switch iszero(and(_PAY_SELF, amountIn))
                        case 0 {
                            payer := address()
                        }
                        default {
                            payer := callerAddress
                        }
                        noFOT := iszero(and(_FEE_ON_TRANSFER, amountIn))
                        // mask input amount
                        amountIn := and(_UINT112_MASK, shr(16, amountIn))
                        // fetch balance if needed
                        if iszero(amountIn) {
                            // selector for balanceOf(address)
                            mstore(0, ERC20_BALANCE_OF)
                            // add payer address as parameter
                            mstore(0x04, payer)
                            // call to token
                            pop(
                                staticcall(
                                    gas(),
                                    calldataload(and(ADDRESS_MASK, sub(opdataOffset, 12))), // fetches first token
                                    0x0,
                                    0x24,
                                    0x0,
                                    0x20 //
                                )
                            )
                            // load the retrieved balance
                            amountIn := mload(0x0)
                        }
                        currentOffset := add(currentOffset, add(52, opdataLength))
                    }
                    uint256 dexId = _preFundTrade(payer, amountIn, opdataOffset);
                    // swap execution
                    if (noFOT) amountIn = swapExactIn(amountIn, dexId, payer, receiver, opdataOffset, opdataLength);
                    else amountIn = swapExactInFOT(amountIn, dexId, receiver, opdataOffset, opdataLength);
                    // slippage check
                    assembly {
                        if lt(amountIn, minimumAmountOut) {
                            mstore(0, SLIPPAGE)
                            revert(0, 0x4)
                        }
                    }
                } else if (operation == Commands.SWAP_EXACT_OUT) {
                    ////////////////////////////////////////////////////
                    // Always uses a flash swap when possible
                    // Encoded parameters for the swap
                    // | receiver | amount  | pathLength | path |
                    // | address  | uint240 | uint16     | bytes|
                    // where amount is provided as
                    // pay self         (bool)      in the upper bit
                    //                              if true, payer is this contract
                    // maximumAmountIn  (uint120)   in the bytes starting at bit 128
                    //                              from the right
                    // amountOut        (uint128)   in the lowest bytes
                    //                              zero is for paying withn the balance of
                    //                              payer (self or caller)
                    ////////////////////////////////////////////////////
                    uint256 opdataOffset;
                    uint256 opdataLength;
                    uint256 amountOut;
                    address payer;
                    address receiver;
                    uint256 amountInMaximum;
                    assembly {
                        opdataOffset := add(currentOffset, 52) // 20 + 32 (address + amountBitmap)
                        receiver := shr(96, calldataload(currentOffset))
                        // get the number parameters
                        amountOut := calldataload(add(currentOffset, 20))
                        // we get the calldatalength of the path
                        opdataLength := and(amountOut, UINT16_MASK)
                        // validation amount starts at bit 128 from the right
                        amountInMaximum := and(_UINT112_MASK, shr(128, amountOut))
                        // check the upper bit as to whether it is a internal swap
                        switch iszero(and(_PAY_SELF, amountOut))
                        case 0 {
                            payer := address()
                        }
                        default {
                            payer := callerAddress
                        }
                        // rigth shigt by pathlength size and masking yields
                        // the final amout out
                        amountOut := and(_UINT112_MASK, shr(16, amountOut))
                        if iszero(amountOut) {
                            // selector for balanceOf(address)
                            mstore(0, ERC20_BALANCE_OF)
                            // add this address as parameter
                            mstore(0x04, payer)
                            // call to token
                            pop(
                                staticcall(
                                    gas(),
                                    calldataload(
                                        and(
                                            ADDRESS_MASK,
                                            add(currentOffset, 32) // this puts the address already in lower bytes
                                        )
                                    ),
                                    0x0,
                                    0x24,
                                    0x0,
                                    0x20 //
                                )
                            )
                            // load the retrieved balance
                            amountOut := mload(0x0)
                        }
                        currentOffset := add(currentOffset, add(52, opdataLength))
                    }
                    swapExactOutInternal(amountOut, amountInMaximum, payer, receiver, opdataOffset, opdataLength);
                } else if (operation == Commands.FLASH_SWAP_EXACT_IN) {
                    ////////////////////////////////////////////////////
                    // Encoded parameters for the swap
                    // | amount | pathLength | path |
                    // | uint240|  uint16    | bytes|
                    // where amount is provided as
                    // pay self         (bool)      in the upper bit
                    //                              if true, payer is this contract
                    //                              the following bits are empty
                    // minimumAmountOut (uint112)   in the bytes starting at bit 128
                    //                              from the right
                    // amountIn         (uint112)   in the lowest bytes
                    //                              zero is for paying with the balance of
                    //                              payer (self or caller)
                    ////////////////////////////////////////////////////
                    uint256 opdataOffset;
                    uint256 opdataLength;
                    uint256 amountIn;
                    address payer;
                    uint256 minimumAmountOut;
                    // all but balance fetch same as for SWAP_EXACT_IN
                    assembly {
                        // the path starts after the path length
                        opdataOffset := add(currentOffset, 32) // 32
                        // lastparam includes receiver address and pathlength
                        let firstParam := calldataload(currentOffset)
                        // this is the path data length
                        // included in lowest 2 bytes
                        opdataLength := and(firstParam, UINT16_MASK)
                        // extract lowr 112 bits shifted by 16
                        minimumAmountOut := and(_UINT112_MASK, shr(128, firstParam))

                        // upper bit signals whether to pay self
                        switch iszero(and(_PAY_SELF, firstParam))
                        case 0 {
                            payer := address()
                        }
                        default {
                            payer := callerAddress
                        }
                        // mask input amount
                        amountIn := and(_UINT112_MASK, shr(16, firstParam))
                        ////////////////////////////////////////////////////
                        // Fetching the balance here is a bit trickier here
                        // We have to fetch the lender-specific collateral
                        // balance
                        // `tokenIn`    is at the beginning of the path; and
                        // `lenderId`   is at the end of the path
                        ////////////////////////////////////////////////////
                        if iszero(amountIn) {
                            let tokenIn := and(ADDRESS_MASK, shr(96, calldataload(opdataOffset)))
                            let lenderId := and(
                                shr(
                                    8,
                                    calldataload(
                                        sub(
                                            add(opdataLength, opdataOffset), //
                                            32
                                        )
                                    )
                                ),
                                UINT8_MASK
                            )
                            mstore(0x0, tokenIn)
                            mstore8(0x0, lenderId)
                            mstore(0x20, COLLATERAL_TOKENS_SLOT)
                            let collateralToken := sload(keccak256(0x0, 0x40))
                            // selector for balanceOf(address)
                            mstore(0x0, ERC20_BALANCE_OF)
                            // add caller address as parameter
                            mstore(add(0x0, 0x4), callerAddress)
                            // call to collateralToken
                            pop(staticcall(gas(), collateralToken, 0x0, 0x24, 0x0, 0x20))
                            // load the retrieved balance
                            amountIn := mload(0x0)
                        }
                        currentOffset := add(currentOffset, add(32, opdataLength)) // 32 args plus path
                    }
                    flashSwapExactInInternal(amountIn, minimumAmountOut, payer, opdataOffset, opdataLength);
                } else if (operation == Commands.FLASH_SWAP_EXACT_OUT) {
                    ////////////////////////////////////////////////////
                    // Always uses a flash swap when possible
                    // Encoded parameters for the swap
                    // | amount | pathLength | path |
                    // | uint240|  uint16    | bytes|
                    // where amount is provided as
                    // pay self         (bool)      in the upper bit
                    //                              if true, payer is this contract
                    //                              The ext 7 bits are empty
                    // maximumAmountIn  (uint112)   in the bytes starting at bit 128
                    //                              from the right
                    // amountOut        (uint112)   in the lowest bytes
                    //                              zero is for paying with the balance of
                    //                              payer (self or caller)
                    ////////////////////////////////////////////////////
                    uint256 opdataOffset;
                    uint256 opdataLength;
                    uint256 amountOut;
                    address payer;
                    uint256 amountInMaximum;
                    assembly {
                        opdataOffset := add(currentOffset, 32) // opdata starts in 2nd byte
                        let firstParam := calldataload(currentOffset)

                        // we get the calldatalength of the path
                        // these are populated in the lower two bytes
                        opdataLength := and(firstParam, UINT16_MASK)
                        // check amount strats at bit 128 from the right (within first 32 )
                        amountInMaximum := and(shr(128, firstParam), _UINT112_MASK)
                        // check highest bit
                        switch iszero(and(_PAY_SELF, firstParam))
                        case 0 {
                            payer := address()
                        }
                        default {
                            payer := callerAddress
                        }
                        amountOut := and(_UINT112_MASK, shr(16, firstParam))
                        ////////////////////////////////////////////////////
                        // Fetch the debt balance in case amountOut is zero
                        ////////////////////////////////////////////////////
                        if iszero(amountOut) {
                            let tokenIn := calldataload(opdataOffset)
                            let mode := and(UINT8_MASK, shr(88, tokenIn))
                            tokenIn := and(ADDRESS_MASK, shr(96, tokenIn))

                            // last 32 bytes
                            let lastWord := calldataload(sub(add(opdataLength, opdataOffset), 32))
                            let lenderId := and(shr(8, lastWord), UINT8_MASK)
                            mstore(0x0, tokenIn)
                            mstore8(0x0, lenderId)
                            switch mode
                            case 2 {
                                mstore(0x20, VARIABLE_DEBT_TOKENS_SLOT)
                            }
                            case 1 {
                                mstore(0x20, STABLE_DEBT_TOKENS_SLOT)
                            }
                            default {
                                revert(0, 0)
                            }

                            let debtToken := sload(keccak256(0x0, 0x40))
                            // selector for balanceOf(address)
                            mstore(0x0, ERC20_BALANCE_OF)
                            // add caller address as parameter
                            mstore(0x4, callerAddress)
                            // call to debtToken
                            pop(staticcall(gas(), debtToken, 0x0, 0x24, 0x0, 0x20))
                            // load the retrieved balance
                            amountOut := mload(0x0)
                        }
                        currentOffset := add(currentOffset, add(32, opdataLength))
                    }
                    flashSwapExactOutInternal(amountOut, amountInMaximum, payer, opdataOffset, opdataLength);
                } else if (operation == Commands.EXTERNAL_CALL) {
                    ////////////////////////////////////////////////////
                    // Execute call to external contract. It consits of
                    // an approval target and call target.
                    // The combo of [approvalTarget, target] has to be whitelisted
                    // for calls. Those are exclusively swap aggregator contracts.
                    // An amount has to be supplied to check the allowance from
                    // this contract to target.
                    // NEVER whitelist a token as an attacker can call
                    // `transferFrom` on target
                    // Data layout:
                    //      bytes 0-20:                  token
                    //      bytes 20-40:                 approvalTarget
                    //      bytes 40-60:                 target
                    //      bytes 60-74:                 amount
                    //      bytes 74-76:                 calldata length
                    //      bytes 76-(76+data length):   data
                    ////////////////////////////////////////////////////
                    assembly {
                        // get first three addresses
                        let token := shr(96, calldataload(currentOffset))
                        let approvalTarget := and(ADDRESS_MASK, shr(96, calldataload(add(currentOffset, 20))))
                        let aggregator := and(ADDRESS_MASK, shr(96, calldataload(add(currentOffset, 40))))

                        // get slot isValidApproveAndCallTarget[approvalTarget][aggregator]
                        mstore(0x0, approvalTarget)
                        mstore(0x20, EXTERNAL_CALLS_SLOT)
                        mstore(0x20, keccak256(0x0, 0x40))
                        mstore(0x0, aggregator)
                        // validate approvalTarget / target combo
                        if iszero(sload(keccak256(0x0, 0x40))) {
                            mstore(0, INVALID_TARGET)
                            revert(0, 0x4)
                        }
                        // get amount to check allowance
                        let amount := calldataload(add(currentOffset, 60))
                        let dataLength := and(UINT16_MASK, shr(128, amount))
                        amount := and(_UINT112_MASK, shr(144, amount))

                        // free memo ptr for populating the tx
                        let ptr := mload(0x40)

                        ////////////////////////////////////////////////////
                        // If the token is zero, we assume that it is a native
                        // transfer / swap and the approval check is skipped
                        ////////////////////////////////////////////////////
                        let nativeValue
                        switch iszero(token)
                        case 0 {
                            ////////////////////////////////////////////////////
                            // get allowance and check if we have to approve
                            ////////////////////////////////////////////////////
                            mstore(ptr, ERC20_ALLOWANCE)
                            mstore(add(ptr, 0x4), address())
                            mstore(add(ptr, 0x24), approvalTarget)

                            // call to token
                            // success is false or return data not provided
                            if iszero(staticcall(gas(), token, ptr, 0x44, ptr, 0x20)) {
                                revert(0x0, 0x0)
                            }
                            // approve if necessary
                            if lt(mload(ptr), amount) {
                                ////////////////////////////////////////////////////
                                // Approve, at this point it is clear that the target
                                // is whitelisted
                                ////////////////////////////////////////////////////
                                // selector for approve(address,uint256)
                                mstore(ptr, ERC20_APPROVE)
                                mstore(add(ptr, 0x04), approvalTarget)
                                mstore(add(ptr, 0x24), MAX_UINT256)

                                if iszero(call(gas(), token, 0x0, ptr, 0x44, ptr, 32)) {
                                    revert(0x0, 0x0)
                                }
                            }
                            nativeValue := 0
                        }
                        default {
                            nativeValue := amount
                        }
                        // increment offset to calldata start
                        currentOffset := add(76, currentOffset)
                        // copy calldata
                        calldatacopy(ptr, currentOffset, dataLength)
                        if iszero(
                            call(
                                gas(),
                                aggregator,
                                nativeValue,
                                ptr, //
                                dataLength, // the length must be correct or the call will fail
                                0x0, // output = empty
                                0x0 // output size = zero
                            )
                        ) {
                            let rdsize := returndatasize()
                            returndatacopy(0, 0, rdsize)
                            revert(0, rdsize)
                        }
                        // increment offset by data length
                        currentOffset := add(currentOffset, dataLength)
                    }
                }
            } else if (operation < 0x20) {
                if (operation == Commands.DEPOSIT) {
                    address underlying;
                    address receiver;
                    uint256 amount;
                    uint256 lenderId;
                    assembly {
                        underlying := shr(96, calldataload(currentOffset))
                        receiver := and(ADDRESS_MASK, calldataload(add(currentOffset, 8)))
                        let lastBytes := calldataload(add(currentOffset, 40))
                        amount := and(_UINT112_MASK, shr(136, lastBytes))
                        lenderId := shr(248, lastBytes) // last byte
                        if iszero(amount) {
                            // selector for balanceOf(address)
                            mstore(0, ERC20_BALANCE_OF)
                            // add this address as parameter
                            mstore(0x04, address())
                            // call to token
                            pop(
                                staticcall(
                                    gas(),
                                    underlying, // token
                                    0x0,
                                    0x24,
                                    0x0,
                                    0x20
                                )
                            )
                            // load the retrieved balance
                            amount := mload(0x0)
                        }
                        currentOffset := add(currentOffset, 55)
                    }
                    _deposit(underlying, receiver, amount, lenderId);
                } else if (operation == Commands.BORROW) {
                    address underlying;
                    address receiver;
                    uint256 amount;
                    uint256 lenderId;
                    uint256 mode;
                    assembly {
                        underlying := shr(96, calldataload(currentOffset))
                        receiver := and(ADDRESS_MASK, calldataload(add(currentOffset, 8)))
                        let lastBytes := calldataload(add(currentOffset, 40))
                        amount := and(_UINT112_MASK, shr(128, lastBytes))
                        lenderId := shr(248, lastBytes) // last byte
                        mode := and(UINT8_MASK, shr(240, lastBytes))
                        currentOffset := add(currentOffset, 56)
                    }
                    _borrow(underlying, callerAddress, receiver, amount, mode, lenderId);
                } else if (operation == Commands.REPAY) {
                    address underlying;
                    address receiver;
                    uint256 amount;
                    uint256 lenderId;
                    uint256 mode;
                    assembly {
                        let offset := currentOffset
                        underlying := and(ADDRESS_MASK, shr(96, calldataload(offset)))
                        receiver := and(ADDRESS_MASK, calldataload(add(offset, 8)))
                        let lastBytes := calldataload(add(offset, 40))
                        amount := and(_UINT112_MASK, shr(128, lastBytes))
                        mode := and(UINT8_MASK, shr(240, lastBytes))
                        lenderId := shr(248, lastBytes) // last byte
                        // zero means that we repay whatever is in this contract
                        switch amount
                        // conract balance
                        case 0 {
                            // selector for balanceOf(address)
                            mstore(0, ERC20_BALANCE_OF)
                            // add this address as parameter
                            mstore(0x04, address())
                            // call to token
                            pop(
                                staticcall(
                                    gas(),
                                    underlying, // token
                                    0x0,
                                    0x24,
                                    0x0,
                                    0x20
                                )
                            )
                            // load the retrieved balance
                            amount := mload(0x0)
                        }
                        // full user debt balance
                        // only used for Compound V3. Overpaying results into the residual
                        // being converted to collateral
                        // Aave V2/3s allow higher amounts than the balance and will correclty adapt
                        case 0xffffffffffffffffffffffffffff {
                            let cometPool
                            switch lenderId
                            case 50 {
                                cometPool := COMET_USDC
                            }
                            case 51 {
                                cometPool := COMET_USDT
                            }
                            // default: load comet from storage
                            // if it is not provided directly
                            default {
                                mstore(0x0, lenderId)
                                mstore(0x20, LENDING_POOL_SLOT)
                                cometPool := sload(keccak256(0x0, 0x40))
                                if iszero(cometPool) {
                                    mstore(0, BAD_LENDER)
                                    revert(0, 0x4)
                                }
                            }

                            // borrowBalanceOf(address)
                            mstore(0x0, 0x374c49b400000000000000000000000000000000000000000000000000000000)
                            // add caller address as parameter
                            mstore(0x4, callerAddress)
                            // call to debtToken
                            pop(staticcall(gas(), cometPool, 0x0, 0x24, 0x0, 0x20))
                            // load the retrieved balance
                            amount := mload(0x0)
                        }

                        currentOffset := add(currentOffset, 56)
                    }
                    _repay(underlying, receiver, amount, mode, lenderId);
                } else if (operation == Commands.WITHDRAW) {
                    address underlying;
                    address receiver;
                    uint256 amount;
                    uint256 lenderId;
                    assembly {
                        underlying := shr(96, calldataload(currentOffset))
                        receiver := and(ADDRESS_MASK, calldataload(add(currentOffset, 8)))
                        let lastBytes := calldataload(add(currentOffset, 40))
                        amount := and(_UINT112_MASK, shr(136, lastBytes))
                        lenderId := shr(248, lastBytes) // last byte

                        switch amount
                        // case contract underlying balance
                        case 0 {
                            // selector for balanceOf(address)
                            mstore(0, ERC20_BALANCE_OF)
                            // add this address as parameter
                            mstore(0x04, address())
                            // call to token
                            pop(
                                staticcall(
                                    gas(),
                                    underlying, // token
                                    0x0,
                                    0x24,
                                    0x0,
                                    0x20
                                )
                            )
                            // load the retrieved balance
                            amount := mload(0x0)
                        }
                        // case user collateral balance
                        case 0xffffffffffffffffffffffffffff {
                            switch lt(lenderId, 50)
                            // get aave type user collateral balance
                            case 1 {
                                // Slot for collateralTokens[target] is keccak256(target . collateralTokens.slot).
                                mstore(0x0, underlying)
                                mstore8(0x0, lenderId)
                                mstore(0x20, COLLATERAL_TOKENS_SLOT)
                                let collateralToken := sload(keccak256(0x0, 0x40))
                                // selector for balanceOf(address)
                                mstore(0, ERC20_BALANCE_OF)
                                // add caller address as parameter
                                mstore(0x04, callerAddress)
                                // call to token
                                pop(
                                    staticcall(
                                        gas(),
                                        collateralToken, // collateral token
                                        0x0,
                                        0x24,
                                        0x0,
                                        0x20
                                    )
                                )
                                // load the retrieved balance
                                amount := mload(0x0)
                            }
                            case 0 {
                                let cometPool
                                let cometCcy
                                switch lenderId
                                // Compound V3 USDC.e
                                case 50 {
                                    cometPool := COMET_USDC
                                    cometCcy := USDCE
                                }
                                case 51 {
                                    cometPool := COMET_USDT
                                    cometCcy := USDT
                                }
                                // default: load comet from storage
                                // if it is not provided directly
                                // note that the debt token is stored as 
                                // variable debt token
                                default {
                                    mstore(0x0, lenderId)
                                    mstore(0x20, LENDING_POOL_SLOT)
                                    cometPool := sload(keccak256(0x0, 0x40))
                                    if iszero(cometPool) {
                                        mstore(0, BAD_LENDER)
                                        revert(0, 0x4)
                                    }

                                    mstore(0x0, cometPool)
                                    mstore8(0x0, lenderId)
                                    mstore(0x20, VARIABLE_DEBT_TOKENS_SLOT)
                                    cometCcy := sload(keccak256(0x0, 0x40))
                                }

                                switch eq(underlying, cometCcy)
                                case 1 {
                                    // selector for balanceOf(address)
                                    mstore(0, ERC20_BALANCE_OF)
                                    // add caller address as parameter
                                    mstore(0x04, callerAddress)
                                    // call to token
                                    pop(
                                        staticcall(
                                            gas(),
                                            cometPool, // collateral token
                                            0x0,
                                            0x24,
                                            0x0,
                                            0x20
                                        )
                                    )
                                    // load the retrieved balance
                                    amount := mload(0x0)
                                }
                                default {
                                    let ptr := mload(0x40)
                                    // selector for userCollateral(address,address)
                                    mstore(ptr, 0x2b92a07d00000000000000000000000000000000000000000000000000000000)
                                    // add caller address as parameter
                                    mstore(add(ptr, 0x04), callerAddress)
                                    // add underlying address
                                    mstore(add(ptr, 0x24), underlying)
                                    // call to token
                                    pop(
                                        staticcall(
                                            gas(),
                                            cometPool, // collateral token
                                            ptr,
                                            0x44,
                                            ptr,
                                            0x20
                                        )
                                    )
                                    // load the retrieved balance (lower 128 bits)
                                    amount := and(UINT128_MASK, mload(ptr))
                                }
                            }
                        }
                        currentOffset := add(currentOffset, 55)
                    }
                    _withdraw(underlying, callerAddress, receiver, amount, lenderId);
                }
            } else if (operation < 0x30) {
                if (operation == Commands.TRANSFER_FROM) {
                    ////////////////////////////////////////////////////
                    // Transfers tokens froom caller to this address
                    // zero amount flags that the entire balance is sent
                    ////////////////////////////////////////////////////
                    assembly {
                        let underlying := shr(96, calldataload(currentOffset))
                        let receiver := and(ADDRESS_MASK, calldataload(add(currentOffset, 8)))
                        let amount := and(_UINT112_MASK, calldataload(add(currentOffset, 22)))
                        // when entering 0 as amount, use the callwe balance
                        if iszero(amount) {
                            // selector for balanceOf(address)
                            mstore(0, ERC20_BALANCE_OF)
                            // add this address as parameter
                            mstore(0x04, callerAddress)
                            // call to token
                            pop(
                                staticcall(
                                    gas(),
                                    underlying, // token
                                    0x0,
                                    0x24,
                                    0x0,
                                    0x20
                                )
                            )
                            // load the retrieved balance
                            amount := mload(0x0)
                        }
                        let ptr := mload(0x40) // free memory pointer

                        // selector for transferFrom(address,address,uint256)
                        mstore(ptr, ERC20_TRANSFER_FROM)
                        mstore(add(ptr, 0x04), callerAddress)
                        mstore(add(ptr, 0x24), receiver)
                        mstore(add(ptr, 0x44), amount)

                        let success := call(gas(), underlying, 0, ptr, 0x64, ptr, 32)

                        let rdsize := returndatasize()

                        // Check for ERC20 success. ERC20 tokens should return a boolean,
                        // but some don't. We accept 0-length return data as success, or at
                        // least 32 bytes that starts with a 32-byte boolean true.
                        success := and(
                            success, // call itself succeeded
                            or(
                                iszero(rdsize), // no return data, or
                                and(
                                    iszero(lt(rdsize, 32)), // at least 32 bytes
                                    eq(mload(ptr), 1) // starts with uint256(1)
                                )
                            )
                        )

                        if iszero(success) {
                            returndatacopy(0, 0, rdsize)
                            revert(0, rdsize)
                        }
                        currentOffset := add(currentOffset, 54)
                    }
                } else if (operation == Commands.SWEEP) {
                    ////////////////////////////////////////////////////
                    // Transfers either token or native balance from this
                    // contract to receiver. Reverts if minAmount is
                    // less than the contract balance
                    // native asset is flagge via address(0) as parameter
                    // Data layout:
                    //      bytes 0-20:                  token (if zero, we assume native)
                    //      bytes 20-40:                 receiver
                    //      bytes 40-41:                 config
                    //                                      0: sweep balance and validate against amount
                    //                                         fetches the balance and checks balance >= amount
                    //                                      1: transfer amount to receiver, skip validation
                    //                                         forwards the ERC20 error if not enough balance
                    //      bytes 41-55:                 amount, either validation or transfer amount
                    ////////////////////////////////////////////////////
                    assembly {
                        let underlying := shr(96, calldataload(currentOffset))
                        // we skip shr by loading the address to the lower bytes
                        let receiver := and(ADDRESS_MASK, calldataload(add(currentOffset, 8)))
                        // load so that amount is in the lower 14 bytes already
                        let providedAmount := calldataload(add(currentOffset, 23))
                        // load config
                        let config := and(UINT8_MASK, shr(112, providedAmount))
                        // mask amount
                        providedAmount := and(_UINT112_MASK, providedAmount)
                        // initialize transferAmount
                        let transferAmount

                        // zero address is native
                        switch iszero(underlying)
                        ////////////////////////////////////////////////////
                        // Transfer token
                        ////////////////////////////////////////////////////
                        case 0 {
                            // for config = 0, the amount is the balance and we
                            // check that the balance is larger tha the amount provided
                            switch config
                            case 0 {
                                // selector for balanceOf(address)
                                mstore(0, ERC20_BALANCE_OF)
                                // add this address as parameter
                                mstore(0x04, address())
                                // call to token
                                pop(
                                    staticcall(
                                        gas(),
                                        underlying,
                                        0x0,
                                        0x24,
                                        0x0,
                                        0x20 //
                                    )
                                )
                                // load the retrieved balance
                                transferAmount := mload(0x0)
                                // revert if balance is not enough
                                if lt(transferAmount, providedAmount) {
                                    mstore(0, SLIPPAGE)
                                    revert(0, 0x4)
                                }
                            }
                            default {
                                transferAmount := providedAmount
                            }
                            if gt(transferAmount, 0) {
                                let ptr := mload(0x40) // free memory pointer

                                // selector for transfer(address,uint256)
                                mstore(ptr, ERC20_TRANSFER)
                                mstore(add(ptr, 0x04), receiver)
                                mstore(add(ptr, 0x24), transferAmount)

                                let success := call(gas(), underlying, 0, ptr, 0x44, ptr, 32)

                                let rdsize := returndatasize()

                                // Check for ERC20 success. ERC20 tokens should return a boolean,
                                // but some don't. We accept 0-length return data as success, or at
                                // least 32 bytes that starts with a 32-byte boolean true.
                                success := and(
                                    success, // call itself succeeded
                                    or(
                                        iszero(rdsize), // no return data, or
                                        and(
                                            iszero(lt(rdsize, 32)), // at least 32 bytes
                                            eq(mload(ptr), 1) // starts with uint256(1)
                                        )
                                    )
                                )

                                if iszero(success) {
                                    returndatacopy(0, 0, rdsize)
                                    revert(0, rdsize)
                                }
                            }
                        }
                        ////////////////////////////////////////////////////
                        // Transfer native
                        ////////////////////////////////////////////////////
                        default {
                            switch config
                            case 0 {
                                transferAmount := selfbalance()
                                // revert if balance is not enough
                                if lt(transferAmount, providedAmount) {
                                    mstore(0, SLIPPAGE)
                                    revert(0, 0x4)
                                }
                            }
                            default {
                                transferAmount := providedAmount
                            }
                            if gt(transferAmount, 0) {
                                if iszero(
                                    call(
                                        gas(),
                                        receiver,
                                        providedAmount,
                                        0x0, // input = empty for fallback/receive
                                        0x0, // input size = zero
                                        0x0, // output = empty
                                        0x0 // output size = zero
                                    )
                                ) {
                                    mstore(0, NATIVE_TRANSFER)
                                    revert(0, 0x4) // revert when native transfer fails
                                }
                            }
                        }
                        currentOffset := add(currentOffset, 55)
                    }
                } else if (operation == Commands.WRAP_NATIVE) {
                    ////////////////////////////////////////////////////
                    // Wrap native, only uses amount as uint112
                    ////////////////////////////////////////////////////
                    assembly {
                        let amount := and(_UINT112_MASK, shr(144, calldataload(currentOffset)))
                        if iszero(
                            call(
                                gas(),
                                WRAPPED_NATIVE,
                                amount, // ETH to deposit
                                0x0, // no input
                                0x0, // input size = zero
                                0x0, // output = empty
                                0x0 // output size = zero
                            )
                        ) {
                            // revert when native transfer fails
                            mstore(0, WRAP)
                            revert(0, 0x4)
                        }
                        currentOffset := add(currentOffset, 14)
                    }
                } else if (operation == Commands.UNWRAP_WNATIVE) {
                    ////////////////////////////////////////////////////
                    // Transfers either token or native balance from this
                    // contract to receiver. Reverts if minAmount is
                    // less than the contract balance
                    // native asset is flagge via address(0) as parameter
                    //      bytes 1-20:                 receiver
                    //      bytes 20-21:                 config
                    //                                      0: sweep balance and validate against amount
                    //                                         fetches the balance and checks balance >= amount
                    //                                      1: transfer amount to receiver, skip validation
                    //      bytes 21-35:                 amount, either validation or transfer amount
                    ////////////////////////////////////////////////////
                    assembly {
                        let receiver := shr(96, calldataload(currentOffset))
                        let providedAmount := calldataload(add(currentOffset, 3))
                        // load config
                        let config := and(UINT8_MASK, shr(112, providedAmount))
                        providedAmount := and(_UINT112_MASK, providedAmount)

                        let transferAmount
                        // validate if config is zero, otherwise skip
                        switch config
                        case 0 {
                            // selector for balanceOf(address)
                            mstore(0x0, ERC20_BALANCE_OF)
                            // add this address as parameter
                            mstore(0x4, address())

                            // call to underlying
                            pop(staticcall(gas(), WRAPPED_NATIVE, 0x0, 0x24, 0x0, 0x20))

                            transferAmount := mload(0x0)
                            if lt(transferAmount, providedAmount) {
                                mstore(0, SLIPPAGE)
                                revert(0, 0x4)
                            }
                        }
                        default {
                            transferAmount := providedAmount
                        }
                        if gt(transferAmount, 0) {
                            // selector for withdraw(uint256)
                            mstore(0x0, 0x2e1a7d4d00000000000000000000000000000000000000000000000000000000)
                            mstore(0x4, transferAmount)
                            // should not fail since WRAPPED_NATIVE is immutable
                            pop(
                                call(
                                    gas(),
                                    WRAPPED_NATIVE,
                                    0x0, // no ETH
                                    0x0, // start of data
                                    0x24, // input size = selector plus amount
                                    0x0, // output = empty
                                    0x0 // output size = zero
                                )
                            )
                            // transfer to receiver if different from this address
                            if xor(receiver, address()) {
                                // transfer native to receiver
                                if iszero(
                                    call(
                                        gas(),
                                        receiver,
                                        transferAmount,
                                        0x0, // input = empty for fallback
                                        0x0, // input size = zero
                                        0x0, // output = empty
                                        0x0 // output size = zero
                                    )
                                ) {
                                    // should only revert if receiver cannot receive native
                                    mstore(0, NATIVE_TRANSFER)
                                    revert(0, 0x4)
                                }
                            }
                        }
                        currentOffset := add(currentOffset, 35)
                    }
                }
            } else {
                if (operation == Commands.EXEC_PERMIT) {
                    ////////////////////////////////////////////////////
                    // Execute normal transfer permit (Dai, ERC20Permit, P2).
                    // The specific permit type is executed based
                    // on the permit length (credits to 1inch for the implementation)
                    // Data layout:
                    //      bytes 0-20:                  token
                    //      bytes 20-22:                 permit length
                    //      bytes 22-(22+permit length): permit data
                    ////////////////////////////////////////////////////
                    bytes calldata permitData;
                    address token;
                    assembly {
                        token := calldataload(currentOffset)
                        let permitLength := and(UINT16_MASK, shr(80, token))
                        token := shr(96, token)
                        permitData.offset := add(currentOffset, 22)
                        permitData.length := permitLength
                        permitLength := add(22, permitLength)
                        currentOffset := add(currentOffset, permitLength)
                    }
                    _tryPermit(token, permitData);
                } else if (operation == Commands.EXEC_CREDIT_PERMIT) {
                    ////////////////////////////////////////////////////
                    // Execute credit delegation permit.
                    // The specific permit type is executed based
                    // on the permit length (credits to 1inch for the implementation)
                    // Data layout:
                    //      bytes 0-20:                  token
                    //      bytes 20-22:                 permit length
                    //      bytes 22-(22+permit length): permit data
                    ////////////////////////////////////////////////////
                    bytes calldata permitData;
                    address token;
                    assembly {
                        token := calldataload(currentOffset)
                        let permitLength := and(UINT16_MASK, shr(80, token))
                        token := shr(96, token)
                        permitData.offset := add(currentOffset, 22)
                        permitData.length := permitLength
                        permitLength := add(22, permitLength)
                        currentOffset := add(currentOffset, permitLength)
                    }
                    _tryCreditPermit(token, permitData);
                } else if (operation == Commands.FLASH_LOAN) {
                    ////////////////////////////////////////////////////
                    // Execute single asset flash loan
                    // It will forward the calldata and current caller to
                    // the flash loan operator
                    // It has to be made sure that the contract holds the
                    // loaned tokens at the end of the execution
                    // Leftover assets should be swept in the bach step
                    // afterwards.
                    // Data layout:
                    //      bytes 0-1:                   source (uint8)
                    //      bytes 1-21:                  asset  (address)
                    //      bytes 21-35:                 amount (uint112)
                    //      bytes 35-37:                 params length (uint16)
                    //      bytes 37-(37+data length):   params (bytes) (to execute deltaCompose)
                    ////////////////////////////////////////////////////
                    assembly {
                        // first slice, including poolId, refCode, asset
                        let slice := calldataload(currentOffset)
                        let source := and(UINT8_MASK, shr(248, slice))
                        // get token to loan
                        let token := and(ADDRESS_MASK, shr(88, slice))
                        // second calldata slice including amount annd params length
                        slice := calldataload(add(currentOffset, 21))
                        let amount := and(_UINT112_MASK, shr(144, slice))
                        // length of params
                        let calldataLength := and(UINT16_MASK, shr(128, slice))
                        switch source
                        case 0xff {
                            // balancer should be the primary choice
                            let ptr := mload(0x40)
                            // flashLoan(...)
                            mstore(ptr, 0x5c38449e00000000000000000000000000000000000000000000000000000000)
                            mstore(add(ptr, 4), address())
                            mstore(add(ptr, 36), 0x80) // offset assets
                            mstore(add(ptr, 68), 0xc0) // offset amounts
                            mstore(add(ptr, 100), 0x100) // offset calldata
                            mstore(add(ptr, 132), 1) // length assets
                            mstore(add(ptr, 164), token) // asset
                            mstore(add(ptr, 196), 1) // length amounts
                            mstore(add(ptr, 228), amount) // amount
                            mstore(add(ptr, 260), add(21, calldataLength)) // length calldata
                            mstore8(add(ptr, 292), source) // source id
                            // caller at the beginning
                            mstore(add(ptr, 293), shl(96, callerAddress))
                            // caller at the beginning
                            currentOffset := add(currentOffset, 37)
                            calldatacopy(add(ptr, 313), currentOffset, calldataLength) // calldata
                            // set entry flag
                            sstore(FLASH_LOAN_GATEWAY_SLOT, 2)
                            if iszero(
                                call(
                                    gas(),
                                    BALANCER_V2_VAULT,
                                    0x0,
                                    ptr,
                                    add(calldataLength, 345), // = 10 * 32 + 4
                                    0x0,
                                    0x0 //
                                )
                            ) {
                                let rdlen := returndatasize()
                                returndatacopy(0, 0, rdlen)
                                revert(0x0, rdlen)
                            }
                            // unset entry flasg
                            sstore(FLASH_LOAN_GATEWAY_SLOT, 1)
                        }
                        default {
                            let pool
                            switch source
                            case 0 {
                                pool := AAVE_V3
                            }
                            case 1 {
                                pool := YLDR
                            }
                            default {
                                mstore(0, INVALID_FLASH_LOAN)
                                revert(0, 0x4)
                            }

                            let ptr := mload(0x40)
                            // flashLoanSimple(...)
                            mstore(ptr, 0x42b0b77c00000000000000000000000000000000000000000000000000000000)
                            mstore(add(ptr, 4), address())
                            mstore(add(ptr, 36), token) // asset
                            mstore(add(ptr, 68), amount) // amount
                            mstore(add(ptr, 100), 0xa0) // offset calldata
                            mstore(add(ptr, 132), 0) // refCode
                            mstore(add(ptr, 164), add(21, calldataLength)) // length calldata
                            mstore8(add(ptr, 196), source) // source id
                            // caller at the beginning
                            mstore(add(ptr, 197), shl(96, callerAddress))
                            currentOffset := add(currentOffset, 37)
                            calldatacopy(add(ptr, 217), currentOffset, calldataLength) // calldata
                            if iszero(
                                call(
                                    gas(),
                                    pool,
                                    0x0,
                                    ptr,
                                    add(calldataLength, 228), // = 10 * 32 + 4
                                    0x0,
                                    0x0 //
                                )
                            ) {
                                let rdlen := returndatasize()
                                returndatacopy(0, 0, rdlen)
                                revert(0x0, rdlen)
                            }
                        }
                        // increment offset
                        currentOffset := add(currentOffset, calldataLength)
                    }
                } else {
                    assembly {
                        mstore(0, INVALID_OPERATION)
                        revert(0, 0x4)
                    }
                }
            }
            // break criteria - we shifted to the end of the calldata
            if (currentOffset >= maxIndex) break;
        }
    }

    /**
     * @dev When `flashLoanSimple` is called on the the Aave pool, it invokes the `executeOperation` hook on the recipient.
     *  We assume that the flash loan fee and params have been pre-computed
     *  We never expect more than one token to be flashed
     *  We assume that the asset loaned is already infinite-approved (this->flashPool)
     */
    function executeOperation(
        address,
        uint256,
        uint256,
        address initiator,
        bytes calldata params // user params
    ) external returns (bool) {
        address origCaller;
        assembly {
            // we expect at least an address
            // and a sourceId (uint8)
            // invalid params will lead to errors in the
            // compose at the bottom
            if lt(params.length, 21) {
                mstore(0, INVALID_FLASH_LOAN)
                revert(0, 0x4)
            }
            // validate caller
            // - extract id from params
            let firstWord := calldataload(params.offset)
            // needs no uint8 masking as we shift 248 bits
            let source := shr(248, firstWord)

            // Validate the caller
            // We check that the caller is one of the lending pools
            // This is a crucial check since this makes
            // the `initiator` paramter the caller of `flashLoan`
            switch source
            case 0 {
                if xor(caller(), AAVE_V3) {
                    mstore(0, INVALID_FLASH_LOAN)
                    revert(0, 0x4)
                }
            }
            case 1 {
                if xor(caller(), YLDR) {
                    mstore(0, INVALID_FLASH_LOAN)
                    revert(0, 0x4)
                }
            }
            // We revert on any other id
            default {
                mstore(0, INVALID_FLASH_LOAN)
                revert(0, 0x4)
            }
            // We require to self-initiate
            // this prevents caller impersonation,
            // but ONLY if the caller address is
            // an Aave V3 type lending pool
            if xor(address(), initiator) {
                mstore(0, INVALID_CALLER)
                revert(0, 0x4)
            }
            // Slice the original caller off the beginnig of the calldata
            // From here on we have validated that the `origCaller`
            // was attached in the deltaCompose function
            // Otherwise, this would be a vulnerability
            origCaller := and(ADDRESS_MASK, shr(88, firstWord))
            // shift / slice params
            params.offset := add(params.offset, 21)
            params.length := sub(params.length, 21)
        }
        // within the flash loan, any compose operation
        // can be executed
        _deltaComposeInternal(origCaller, params);
        return true;
    }

    /**
     * @dev Balancer flash loan call
     * Gated via flash loan gateway flag to prevent calls from sources other than this contract
     */
    function receiveFlashLoan(
        address[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata params //
    ) external {
        address origCaller;
        assembly {
            // we expect at least an address
            // and a sourceId (uint8)
            // invalid params will lead to errors in the
            // compose at the bottom
            if lt(params.length, 21) {
                mstore(0, INVALID_FLASH_LOAN)
                revert(0, 0x4)
            }
            // validate caller
            // - extract id from params
            let firstWord := calldataload(params.offset)
            // needs no uint8 masking as we shift 248 bits
            let source := shr(248, firstWord)

            // Validate the caller
            // We check that the caller is one of the lending pools
            // This is a crucial check since this makes
            // the `initiator` paramter the caller of `flashLoan`
            switch source
            case 0xff {
                if xor(caller(), BALANCER_V2_VAULT) {
                    mstore(0, INVALID_FLASH_LOAN)
                    revert(0, 0x4)
                }
            }
            // We revert on any other id
            default {
                mstore(0, INVALID_FLASH_LOAN)
                revert(0, 0x4)
            }
            // check that the entry flag is
            if iszero(eq(2, sload(FLASH_LOAN_GATEWAY_SLOT))) {
                mstore(0, INVALID_CALLER)
                revert(0, 0x4)
            }
            // Slice the original caller off the beginnig of the calldata
            // From here on we have validated that the `origCaller`
            // was attached in the deltaCompose function
            // Otherwise, this would be a vulnerability
            origCaller := and(ADDRESS_MASK, shr(88, firstWord))
            // shift / slice params
            params.offset := add(params.offset, 21)
            params.length := sub(params.length, 21)
        }
        // within the flash loan, any compose operation
        // can be executed
        _deltaComposeInternal(origCaller, params);
    }
}
